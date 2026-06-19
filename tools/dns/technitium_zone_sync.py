#!/usr/bin/env python3
"""Sync local zone files into Technitium DNS and remove unknown records."""

import argparse
import uuid
import fnmatch
import json
import pathlib
import shlex
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from typing import Dict, List, Optional, Tuple

IGNORED_SYSTEM_TYPES = {
    "RRSIG",
    "NSEC",
    "NSEC3",
    "NSEC3PARAM",
    "DNSKEY",
    "CDS",
    "CDNSKEY",
}

RR_CLASSES = {"IN", "CH", "HS", "CS"}
CANONICAL_SUPPORTED_TYPES = {
    "A",
    "AAAA",
    "NS",
    "CNAME",
    "ANAME",
    "PTR",
    "MX",
    "TXT",
    "SRV",
    "SOA",
    "CAA",
    "HTTPS",
}
SUPPORTED_ZONE_TYPES = set(CANONICAL_SUPPORTED_TYPES)
DELETE_SUPPORTED_TYPES = set(CANONICAL_SUPPORTED_TYPES)


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    sys.exit(1)


def strip_dot(value: str) -> str:
    return value[:-1] if value.endswith(".") else value


def normalize_name(value: str) -> str:
    return strip_dot(value).lower()


def normalize_type(value: str) -> str:
    return value.upper()


def normalize_txt(value: str) -> str:
    # Technitium may preserve leading tabs/spaces from split TXT chunks.
    # Trim outer whitespace so semantic-equivalent TXT content matches.
    return value.strip()


def normalize_svc_target(value: object, origin: Optional[str] = None, resolve_relative: bool = False) -> str:
    text = str(value or "").strip()
    if text in {"", "."}:
        return "."
    if text == "@":
        if origin:
            return normalize_name(origin)
        return ""
    if resolve_relative and origin:
        return resolve_domain_name(text, origin)
    return normalize_name(text)


def normalize_srv_target(value: str, origin: str, resolve_relative: bool) -> str:
    text = value.strip()
    if text in {"", "."}:
        return "."
    if text == "@":
        if origin:
            return normalize_name(origin)
        return ""
    if resolve_relative:
        return resolve_domain_name(text, origin)
    return normalize_name(text)


def strip_comments_outside_quotes(line: str) -> str:
    out: List[str] = []
    in_quotes = False
    escaped = False
    for ch in line:
        if escaped:
            out.append(ch)
            escaped = False
            continue
        if ch == "\\":
            out.append(ch)
            escaped = True
            continue
        if ch == '"':
            out.append(ch)
            in_quotes = not in_quotes
            continue
        if ch == ";" and not in_quotes:
            break
        out.append(ch)
    return "".join(out)


def count_parens_outside_quotes(line: str) -> int:
    depth = 0
    in_quotes = False
    escaped = False
    for ch in line:
        if escaped:
            escaped = False
            continue
        if ch == "\\":
            escaped = True
            continue
        if ch == '"':
            in_quotes = not in_quotes
            continue
        if in_quotes:
            continue
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
    return depth


def resolve_domain_name(name: str, origin: str) -> str:
    token = name.strip()
    if token == "@":
        return normalize_name(origin)
    if token == ".":
        return "."
    if token.endswith("."):
        return normalize_name(token)
    if not origin:
        fail(f"relative name '{token}' encountered without an origin")
    return normalize_name(f"{token}.{origin}")


def _normalize_svc_param_val(value: object) -> str:
    if isinstance(value, list):
        return ",".join(str(v).strip() for v in value if str(v).strip())
    return str(value).strip()


def canonicalize_svc_params(value: object, strict: bool = False) -> Optional[str]:
    """
    Canonical form for compare keys: key=value;key2=value2 (sorted by key).
    Accepts RFC text (key=value), Technitium API pipe format (key|value|...), dict/list.
    """
    if value is None:
        return "false"

    params: Dict[str, str] = {}

    if isinstance(value, dict):
        for k, v in value.items():
            key = str(k).strip().lower()
            if not key:
                continue
            val = _normalize_svc_param_val(v)
            params[key] = val
    elif isinstance(value, list):
        # May be ["alpn","h2","port","443"] or similar.
        tokens = [str(x).strip() for x in value if str(x).strip()]
        if tokens:
            i = 0
            while i < len(tokens):
                key = tokens[i].lower()
                if i + 1 < len(tokens):
                    params[key] = tokens[i + 1]
                    i += 2
                else:
                    params[key] = "true"
                    i += 1
    else:
        text = str(value).strip()
        if not text or text.lower() == "false":
            return "false"
        if '"' in text or "'" in text:
            if strict:
                raise ValueError(
                    "quoted HTTPS/SVCB params are not supported by parser dialect: "
                    f"{text!r}"
                )
            return None
        if "|" in text:
            toks = [t.strip() for t in text.split("|") if t.strip()]
            i = 0
            while i < len(toks):
                key = toks[i].lower()
                if i + 1 < len(toks):
                    params[key] = toks[i + 1]
                    i += 2
                else:
                    params[key] = "true"
                    i += 1
        else:
            # RFC zone text usually key=value tokens separated by spaces.
            for tok in text.split():
                if "=" in tok:
                    k, v = tok.split("=", 1)
                    key = k.strip().lower()
                    if key:
                        params[key] = v.strip()
                else:
                    key = tok.strip().lower()
                    if key:
                        params[key] = "true"

    if not params:
        return "false"
    return ";".join(f"{k}={params[k]}" for k in sorted(params))


def svc_params_to_api(value: object) -> str:
    """
    Technitium API expects pipe format: key|value|key2|value2.
    """
    canonical = canonicalize_svc_params(value, strict=False)
    if canonical in {None, "false"}:
        return "false"
    parts: List[str] = []
    for kv in canonical.split(";"):
        if "=" not in kv:
            continue
        k, v = kv.split("=", 1)
        parts.append(k)
        parts.append(v)
    return "|".join(parts) if parts else "false"


def split_key(key: str) -> Tuple[str, str, str, str]:
    parts = key.split("|", 3)
    if len(parts) != 4:
        return ("", "", "", key)
    return (parts[0], parts[1], parts[2], parts[3])


def _split_first_unescaped_dot(value: str) -> Tuple[str, str]:
    escaped = False
    for idx, ch in enumerate(value):
        if escaped:
            escaped = False
            continue
        if ch == "\\":
            escaped = True
            continue
        if ch == ".":
            return value[:idx], value[idx + 1 :]
    return value, ""


def _unescape_dns_text(value: str) -> str:
    out: List[str] = []
    escaped = False
    for ch in value:
        if escaped:
            out.append(ch)
            escaped = False
            continue
        if ch == "\\":
            escaped = True
            continue
        out.append(ch)
    if escaped:
        out.append("\\")
    return "".join(out)


def soa_rname_to_email(value: str) -> str:
    """
    Normalize SOA RNAME token to mailbox-like form.
    RFC uses mailbox-domain syntax (first label is local-part with dots escaped).
    """
    value = strip_dot(value).strip().lower()
    if "@" in value:
        return value
    local_raw, domain_raw = _split_first_unescaped_dot(value)
    local = _unescape_dns_text(local_raw)
    domain = _unescape_dns_text(domain_raw)
    if local and domain:
        return f"{local}@{domain}"
    return local


def normalize_soa_rname(value: str, origin: str) -> str:
    """
    Policy:
    - mailbox form with '@' is accepted as-is (lowercased).
    - '@' alone is rejected.
    - DNS form is accepted; if relative, it is qualified with current origin.
    """
    token = str(value or "").strip()
    if not token:
        return ""
    if token == "@":
        fail("invalid SOA RNAME '@': use mailbox form (user@example.tld) or DNS form (user.example.tld.)")
    if "@" in token:
        return token.lower()
    fqdn = resolve_domain_name(token, origin) if origin else normalize_name(token)
    return soa_rname_to_email(fqdn)


def canonical_data(record_type: str, record_data: Dict[str, object], zone_origin: str = "") -> Optional[str]:
    rt = normalize_type(record_type)
    rd = record_data or {}
    if rt in {"A", "AAAA"}:
        return str(rd.get("ipAddress", "")).strip()
    if rt == "NS":
        return normalize_name(str(rd.get("nameServer", "")))
    if rt == "CNAME":
        return normalize_name(str(rd.get("cname", "")))
    if rt == "ANAME":
        return normalize_name(str(rd.get("aname", "")))
    if rt == "PTR":
        return normalize_name(str(rd.get("ptrName", "")))
    if rt == "MX":
        return f"{int(rd.get('preference', 0))}|{normalize_name(str(rd.get('exchange', '')))}"
    if rt == "TXT":
        return normalize_txt(str(rd.get("text", "")))
    if rt == "SRV":
        target = normalize_srv_target(str(rd.get("target", ".")), zone_origin, False)
        if not target:
            return None
        return (
            f"{int(rd.get('priority', 0))}|{int(rd.get('weight', 0))}|{int(rd.get('port', 0))}|"
            f"{target}"
        )
    if rt == "SOA":
        # Ignore serial differences: serial changes are expected and managed by the DNS server/date scheme.
        return (
            f"{normalize_name(str(rd.get('primaryNameServer', '')))}|"
            f"{normalize_soa_rname(str(rd.get('responsiblePerson', '')), zone_origin)}|"
            f"{int(rd.get('refresh', 0))}|{int(rd.get('retry', 0))}|"
            f"{int(rd.get('expire', 0))}|{int(rd.get('minimum', 0))}"
        )
    if rt == "CAA":
        return f"{int(rd.get('flags', 0))}|{str(rd.get('tag', ''))}|{str(rd.get('value', ''))}"
    if rt == "HTTPS":
        target = (
            rd.get("svcTargetName")
            if rd.get("svcTargetName") is not None
            else rd.get("targetName", rd.get("target", "."))
        )
        norm_target = normalize_svc_target(target, zone_origin, False)
        if not norm_target:
            return None
        svc_params = canonicalize_svc_params(rd.get("svcParams"), strict=False)
        if svc_params is None:
            return None
        return (
            f"{int(rd.get('svcPriority', 0))}|"
            f"{norm_target}|"
            f"{svc_params}"
        )
    return None


def validate_supported_type_handlers() -> None:
    missing_canonical = SUPPORTED_ZONE_TYPES - CANONICAL_SUPPORTED_TYPES
    missing_delete = SUPPORTED_ZONE_TYPES - DELETE_SUPPORTED_TYPES
    if missing_canonical or missing_delete:
        problems: List[str] = []
        if missing_canonical:
            problems.append(f"missing canonical_data handlers: {sorted(missing_canonical)}")
        if missing_delete:
            problems.append(f"missing delete_record handlers: {sorted(missing_delete)}")
        fail("SUPPORTED_ZONE_TYPES is inconsistent: " + "; ".join(problems))


def make_key(zone: str, name: str, record_type: str, data: str) -> str:
    return f"{normalize_name(zone)}|{normalize_name(name)}|{normalize_type(record_type)}|{data}"

def parse_rr_tokens(owner: str, rr_tokens: List[str], origin: str) -> Tuple[Optional[Tuple[str, str, str]], Optional[str]]:
    if len(rr_tokens) < 2:
        return None, "RR has insufficient fields"

    idx = 0
    # Optional [TTL] [CLASS] or [CLASS] [TTL]
    if idx < len(rr_tokens) and rr_tokens[idx].isdigit():
        idx += 1
        if idx < len(rr_tokens) and rr_tokens[idx].upper() in RR_CLASSES:
            idx += 1
    elif idx < len(rr_tokens) and rr_tokens[idx].upper() in RR_CLASSES:
        idx += 1
        if idx < len(rr_tokens) and rr_tokens[idx].isdigit():
            idx += 1

    if idx >= len(rr_tokens):
        return None, "RR type field missing"

    record_type = normalize_type(rr_tokens[idx])
    if record_type not in SUPPORTED_ZONE_TYPES:
        return None, f"unsupported RR type '{record_type}' for parser dialect"
    rdata_tokens = [
        tok.lstrip("(").rstrip(")")
        for tok in rr_tokens[idx + 1 :]
        if tok not in {"(", ")"}
    ]
    name = owner

    if record_type in {"A", "AAAA"} and len(rdata_tokens) >= 1:
        return (name, record_type, rdata_tokens[0]), None
    if record_type in {"NS", "CNAME", "PTR"} and len(rdata_tokens) >= 1:
        return (name, record_type, resolve_domain_name(rdata_tokens[0], origin)), None
    if record_type == "ANAME" and len(rdata_tokens) >= 1:
        return (name, record_type, resolve_domain_name(rdata_tokens[0], origin)), None
    if record_type == "MX" and len(rdata_tokens) >= 2:
        try:
            return (
                name,
                record_type,
                f"{int(rdata_tokens[0])}|{resolve_domain_name(rdata_tokens[1], origin)}",
            ), None
        except ValueError:
            return None, "invalid MX priority"
    if record_type == "TXT" and len(rdata_tokens) >= 1:
        return (name, record_type, normalize_txt("".join(rdata_tokens))), None
    if record_type == "SRV" and len(rdata_tokens) >= 4:
        try:
            return (
                name,
                record_type,
                (
                    f"{int(rdata_tokens[0])}|{int(rdata_tokens[1])}|{int(rdata_tokens[2])}|"
                    f"{normalize_srv_target(rdata_tokens[3], origin, True)}"
                ),
            ), None
        except ValueError:
            return None, "invalid SRV priority/weight/port"
    if record_type == "SOA" and len(rdata_tokens) >= 7:
        try:
            return (
                name,
                record_type,
                (
                    f"{resolve_domain_name(rdata_tokens[0], origin)}|"
                    f"{normalize_soa_rname(rdata_tokens[1], origin)}|"
                    f"{int(rdata_tokens[3])}|{int(rdata_tokens[4])}|{int(rdata_tokens[5])}|{int(rdata_tokens[6])}"
                ),
            ), None
        except ValueError:
            return None, "invalid SOA timer value"
    if record_type == "CAA" and len(rdata_tokens) >= 3:
        try:
            return (name, record_type, f"{int(rdata_tokens[0])}|{rdata_tokens[1]}|{rdata_tokens[2]}"), None
        except ValueError:
            return None, "invalid CAA flags"
    if record_type == "HTTPS" and len(rdata_tokens) >= 2:
        try:
            svc_priority = int(rdata_tokens[0])
        except ValueError:
            return None, "invalid HTTPS svcPriority"
        svc_target = normalize_svc_target(rdata_tokens[1], origin, True)
        if not svc_target:
            return None, "invalid HTTPS svcTargetName '@' without origin"
        svc_params = " ".join(rdata_tokens[2:]).strip() if len(rdata_tokens) > 2 else "false"
        try:
            canonical_params = canonicalize_svc_params(svc_params, strict=True)
        except ValueError as exc:
            return None, str(exc)
        if canonical_params is None:
            return None, "invalid HTTPS svcParams"
        return (name, record_type, f"{svc_priority}|{svc_target}|{canonical_params}"), None
    return None, f"unsupported or malformed '{record_type}' RDATA"


def parse_zone_file(zone_name: str, zone_text: str) -> Tuple[set, List[str]]:
    desired: set = set()
    buffer: List[str] = []
    paren_depth = 0
    owner_omitted = False
    current_owner = normalize_name(zone_name)
    current_origin = normalize_name(zone_name)
    entry_start_line = 0
    parse_issues: List[str] = []

    for line_no, raw_line in enumerate(zone_text.splitlines(), start=1):
        no_comment = strip_comments_outside_quotes(raw_line)
        if not no_comment.strip():
            continue
        if not buffer:
            owner_omitted = no_comment[:1].isspace()
            entry_start_line = line_no
        buffer.append(no_comment.strip())
        paren_depth += count_parens_outside_quotes(no_comment)
        if paren_depth > 0:
            continue
        if paren_depth < 0:
            parse_issues.append(f"line {entry_start_line}: unmatched closing parenthesis")
            buffer = []
            paren_depth = 0
            continue

        merged = " ".join(buffer).strip()
        buffer = []
        paren_depth = 0

        try:
            tokens = shlex.split(merged, comments=False, posix=True)
        except ValueError as exc:
            parse_issues.append(f"line {entry_start_line}: shlex parse failed: {exc}; text={merged!r}")
            continue
        if not tokens:
            continue

        head = tokens[0].upper()
        if head == "$ORIGIN" and len(tokens) >= 2:
            current_origin = resolve_domain_name(tokens[1], current_origin)
            continue
        if head == "$TTL":
            # TTL defaults are not needed for canonical compare keys.
            continue
        if head == "$INCLUDE":
            parse_issues.append(f"line {entry_start_line}: unsupported directive $INCLUDE")
            continue
        if head == "$GENERATE":
            parse_issues.append(f"line {entry_start_line}: unsupported directive $GENERATE")
            continue
        if head.startswith("$"):
            parse_issues.append(f"line {entry_start_line}: unsupported directive {head}")
            continue

        rr_tokens: List[str]
        if owner_omitted:
            owner = current_owner
            rr_tokens = tokens
        else:
            owner = resolve_domain_name(tokens[0], current_origin)
            current_owner = owner
            rr_tokens = tokens[1:]

        parsed, reason = parse_rr_tokens(owner, rr_tokens, current_origin)
        if parsed is None:
            parse_issues.append(
                f"line {entry_start_line}: could not parse RR ({reason or 'unknown reason'}); text={merged!r}"
            )
            continue
        name, rrtype, data = parsed
        desired.add(make_key(zone_name, name, rrtype, data))

    if buffer:
        parse_issues.append(f"line {entry_start_line}: unterminated parenthesized RR")

    return desired, parse_issues


def parse_ignore_rule(line: str) -> Optional[Tuple[bool, str]]:
    stripped = line.strip()
    if not stripped:
        return None
    if stripped.startswith("#"):
        return None

    # Allow escaped leading comment/negation markers.
    if stripped.startswith(r"\#") or stripped.startswith(r"\!"):
        stripped = stripped[1:]

    negated = stripped.startswith("!")
    if negated:
        stripped = stripped[1:].strip()
        if not stripped:
            return None
    return (negated, stripped)


def read_ignore_rules(args_ignore: List[str], ignore_files: List[pathlib.Path]) -> List[Tuple[bool, str]]:
    rules: List[Tuple[bool, str]] = []
    for raw in args_ignore:
        parsed = parse_ignore_rule(raw)
        if parsed is not None:
            rules.append(parsed)

    for ignore_file in ignore_files:
        if not ignore_file.exists():
            continue
        for line in ignore_file.read_text(encoding="utf-8").splitlines():
            parsed = parse_ignore_rule(line)
            if parsed is not None:
                rules.append(parsed)
    return rules


def should_ignore(key: str, rules: List[Tuple[bool, str]]) -> bool:
    ignored = False
    for negated, pattern in rules:
        if fnmatch.fnmatch(key, pattern):
            ignored = not negated
    return ignored


class TechnitiumClient:
    def __init__(self, base_url: str, token: str, timeout: int) -> None:
        self.base_url = base_url.rstrip("/")
        self.token = token
        self.timeout = timeout

    def _call(
        self,
        path: str,
        params: Optional[Dict[str, object]] = None,
        method: str = "GET",
        body: Optional[bytes] = None,
        content_type: Optional[str] = None,
    ) -> Dict[str, object]:
        query = dict(params or {})
        query["token"] = self.token
        url = f"{self.base_url}{path}?{urllib.parse.urlencode(query, doseq=True)}"
        # Pass request body directly in constructor so urllib sets up the POST payload correctly.
        request = urllib.request.Request(url=url, data=body, method=method)
        if content_type:
            request.add_header("Content-Type", content_type)

        try:
            with urllib.request.urlopen(request, timeout=self.timeout) as response:
                response_bytes = response.read()
        except urllib.error.HTTPError as exc:
            body_text = exc.read().decode("utf-8", errors="replace")
            fail(f"HTTP {exc.code} for {path}: {body_text}")
        except urllib.error.URLError as exc:
            fail(f"Request failed for {path}: {exc}")

        try:
            payload = json.loads(response_bytes.decode("utf-8"))
        except json.JSONDecodeError:
            fail(f"Invalid JSON response from {path}: {response_bytes[:200]!r}")

        status = payload.get("status")
        if status != "ok":
            message = str(payload.get("errorMessage", "unknown error"))
            raise RuntimeError(f"API call failed for {path}: {message}")

        return payload

    def create_zone_if_missing(self, zone: str, dry_run: bool) -> None:
        if dry_run:
            print(f"[dry-run] ensure zone exists: {zone}")
            return

        try:
            self._call(
                "/api/zones/create",
                params={"zone": zone, "type": "Primary"},
            )
            print(f"created zone: {zone}")
        except RuntimeError as exc:
            if "already exists" in str(exc).lower():
                return
            raise

    def import_zone(self, zone: str, zone_text: str, overwrite_soa_serial: bool, dry_run: bool) -> None:
        if dry_run:
            print(f"[dry-run] import zone: {zone}")
            return
        params = {
            "zone": zone,
            "overwrite": "true",
            "overwriteSoaSerial": "true" if overwrite_soa_serial else "false",
        }

        # Preferred path from docs: raw text/plain body.
        try:
            self._call(
                "/api/zones/import",
                params=params,
                method="POST",
                body=zone_text.encode("utf-8"),
                # Technitium checks exact content-type string in ImportZoneAsync.
                content_type="text/plain",
            )
            return
        except RuntimeError as exc:
            if "zone file to import is missing" not in str(exc).lower():
                raise

        # Fallback path for installations that expect multipart uploads.
        multipart_body, multipart_content_type = build_zone_multipart_payload(zone, zone_text)
        self._call(
            "/api/zones/import",
            params=params,
            method="POST",
            body=multipart_body,
            content_type=multipart_content_type,
        )

    def get_zone_records(self, zone: str) -> List[Dict[str, object]]:
        payload = self._call(
            "/api/zones/records/get",
            params={"domain": zone, "zone": zone, "listZone": "true"},
        )
        response = payload.get("response", {})
        return list(response.get("records", []))

    def delete_record(self, zone: str, record: Dict[str, object], dry_run: bool) -> bool:
        name = str(record.get("name", ""))
        record_type = normalize_type(str(record.get("type", "")))
        rdata = record.get("rData", {}) or {}

        params: Dict[str, object] = {"zone": zone, "domain": name, "type": record_type}
        if record_type in {"A", "AAAA"}:
            params["ipAddress"] = rdata.get("ipAddress", "")
        elif record_type == "NS":
            params["nameServer"] = rdata.get("nameServer", "")
        elif record_type == "CNAME":
            params["cname"] = rdata.get("cname", "")
        elif record_type == "ANAME":
            params["aname"] = rdata.get("aname", "")
        elif record_type == "PTR":
            params["ptrName"] = rdata.get("ptrName", "")
        elif record_type == "MX":
            params["preference"] = rdata.get("preference", 0)
            params["exchange"] = rdata.get("exchange", "")
        elif record_type == "TXT":
            params["text"] = rdata.get("text", "")
        elif record_type == "SRV":
            params["priority"] = rdata.get("priority", 0)
            params["weight"] = rdata.get("weight", 0)
            params["port"] = rdata.get("port", 0)
            params["target"] = normalize_srv_target(str(rdata.get("target", ".")), normalize_name(zone), False)
        elif record_type == "SOA":
            params["primaryNameServer"] = rdata.get("primaryNameServer", "")
            params["responsiblePerson"] = rdata.get("responsiblePerson", "")
            params["serial"] = rdata.get("serial", 0)
            params["refresh"] = rdata.get("refresh", 0)
            params["retry"] = rdata.get("retry", 0)
            params["expire"] = rdata.get("expire", 0)
            params["minimum"] = rdata.get("minimum", 0)
        elif record_type == "CAA":
            params["flags"] = rdata.get("flags", 0)
            params["tag"] = rdata.get("tag", "")
            params["value"] = rdata.get("value", "")
        elif record_type == "HTTPS":
            params["svcPriority"] = rdata.get("svcPriority", 0)
            target = (
                rdata.get("svcTargetName")
                if rdata.get("svcTargetName") is not None
                else rdata.get("targetName", rdata.get("target", "."))
            )
            params["svcTargetName"] = normalize_svc_target(target, normalize_name(zone), False)
            params["svcParams"] = svc_params_to_api(rdata.get("svcParams"))
        else:
            return False

        if dry_run:
            print(
                "[dry-run] delete "
                f"{normalize_name(zone)} {normalize_name(name)} {record_type} {json.dumps(rdata, sort_keys=True)}"
            )
            return True
        self._call("/api/zones/records/delete", params=params)
        return True


def build_zones_with_nix(repo_root: pathlib.Path) -> pathlib.Path:
    cmd = ["nix", "build", ".#dns-zones", "--out-link", "result"]
    process = subprocess.run(cmd, cwd=repo_root, check=False, capture_output=True, text=True)
    if process.returncode != 0:
        error_message = process.stderr.strip() or process.stdout.strip() or "nix build failed"
        fail(error_message)
    return repo_root / "result"


def build_zone_multipart_payload(zone: str, zone_text: str) -> Tuple[bytes, str]:
    boundary = f"----technitium-sync-{uuid.uuid4().hex}"
    boundary_bytes = boundary.encode("ascii")
    lines: List[bytes] = []

    # Some versions/parsers accept different form-data names. Add all common names.
    for field_name in ("file", "zoneFile", "zone"):
        lines.append(b"--" + boundary_bytes)
        lines.append(
            (
                f'Content-Disposition: form-data; name="{field_name}"; '
                f'filename="{zone}.zone"'
            ).encode("utf-8")
        )
        lines.append(b"Content-Type: text/plain; charset=utf-8")
        lines.append(b"")
        lines.append(zone_text.encode("utf-8"))

    lines.append(b"--" + boundary_bytes + b"--")
    lines.append(b"")
    body = b"\r\n".join(lines)
    content_type = f"multipart/form-data; boundary={boundary}"
    return body, content_type


def desired_types_by_name(desired_keys: set) -> Dict[str, set]:
    mapping: Dict[str, set] = {}
    for key in desired_keys:
        _, name, record_type, _ = split_key(key)
        mapping.setdefault(name, set()).add(record_type)
    return mapping


def print_post_sync_report(report: Dict[str, object], report_file: Optional[pathlib.Path]) -> None:
    zones_total = int(report.get("zones_total", 0))
    extra_total = int(report.get("extra_total", 0))
    missing_total = int(report.get("missing_total", 0))
    unsupported_total = int(report.get("unsupported_total", 0))
    ignored_records = list(report.get("ignored_records", []))
    zones = report.get("zones", {})

    print("post-sync report:")
    print(
        f"  zones_scanned={zones_total}, extra_records={extra_total}, "
        f"missing_records={missing_total}, unsupported_live_records={unsupported_total}, "
        f"ignored_records={len(ignored_records)}"
    )

    if extra_total == 0 and missing_total == 0 and unsupported_total == 0:
        print("  no inconsistencies detected on supported record types.")
    else:
        for zone, zone_report in zones.items():
            extras = zone_report.get("extra", [])
            missing = zone_report.get("missing", [])
            unsupported = zone_report.get("unsupported_live", [])
            if not extras and not missing and not unsupported:
                continue
            print(f"  zone {zone}:")
            if extras:
                print(f"    extra ({len(extras)}):")
                for key in extras:
                    print(f"      - {key}")
            if missing:
                print(f"    missing ({len(missing)}):")
                for key in missing:
                    print(f"      - {key}")
            if unsupported:
                print(f"    unsupported_live ({len(unsupported)}):")
                for item in unsupported:
                    print(f"      - {item}")
    if ignored_records:
        print("  ignored records:")
        for key in ignored_records:
            print(f"    - {key}")

    if report_file is not None:
        report_file.parent.mkdir(parents=True, exist_ok=True)
        report_file.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(f"  report written: {report_file}")


def cleanup_cname_conflicts(
    client: TechnitiumClient,
    zone: str,
    desired_types_map: Dict[str, set],
    dry_run: bool,
) -> int:
    """Delete records that conflict with desired CNAME/non-CNAME type requirements."""
    removed = 0
    records = client.get_zone_records(zone)
    for record in records:
        name = normalize_name(str(record.get("name", "")))
        rtype = normalize_type(str(record.get("type", "")))
        desired_types = desired_types_map.get(name)
        if not desired_types:
            continue

        should_remove = False
        if "CNAME" in desired_types and rtype != "CNAME":
            should_remove = True
        elif "CNAME" not in desired_types and rtype == "CNAME":
            should_remove = True

        if not should_remove:
            continue

        if rtype in IGNORED_SYSTEM_TYPES:
            continue
        if rtype == "SOA":
            fail(f"CNAME conflict at {name} in {zone}: cannot remove SOA. Fix desired/live zone data.")

        deleted = client.delete_record(zone, record, dry_run=dry_run)
        if not deleted:
            fail(
                f"CNAME conflict at {name} in {zone}: unsupported type '{rtype}' cannot be auto-removed. "
                "Please remove it manually."
            )
        removed += 1
    return removed


def zone_files_from_dir(zones_dir: pathlib.Path) -> List[pathlib.Path]:
    if not zones_dir.exists():
        fail(f"zones dir not found: {zones_dir}")
    files = sorted(zones_dir.glob("*.zone"))
    if not files:
        fail(f"no .zone files in: {zones_dir}")
    return files


def main() -> None:
    validate_supported_type_handlers()

    parser = argparse.ArgumentParser(description="Import RFC1035 zone files into Technitium and prune unknown records.")
    parser.add_argument("--server", default="http://127.0.0.1:5380", help="Technitium base URL")
    token_group = parser.add_mutually_exclusive_group(required=True)
    token_group.add_argument("--token", help="Technitium API token")
    token_group.add_argument("--token-file", type=pathlib.Path, help="Path to file containing Technitium API token")
    parser.add_argument("--timeout", type=int, default=30, help="HTTP timeout in seconds")
    parser.add_argument(
        "--zones-dir",
        type=pathlib.Path,
        default=None,
        help="Directory containing *.zone files. If omitted, runs `nix build .#dns-zones` and uses ./result",
    )
    parser.add_argument("--zone", action="append", default=[], help="Only sync the given zone (repeatable)")
    parser.add_argument(
        "--ignore",
        action="append",
        default=[],
        help="Ignore rule for key zone|name|type|data. Prefix with ! to re-include like .gitignore",
    )
    parser.add_argument(
        "--ignore-file",
        type=pathlib.Path,
        default=None,
        help="Ignore file path (default: .technitiumignore and dns/.technitiumignore, if present)",
    )
    parser.add_argument("--dry-run", action="store_true", help="Print planned changes but do not call mutating APIs")
    parser.add_argument("--no-cleanup", action="store_true", help="Import zones but skip deleting unknown records")
    parser.add_argument(
        "--allow-unparsed",
        action="store_true",
        help="Continue when zone parser encounters unparsed lines/directives (unsafe for cleanup)",
    )
    parser.add_argument(
        "--overwrite-soa-serial",
        action="store_true",
        help="Pass overwriteSoaSerial=true while importing zones",
    )
    parser.add_argument(
        "--diff",
        action="store_true",
        help="Show mismatch details for records selected for deletion (implies --dry-run; never mutates server)",
    )
    parser.add_argument(
        "--post-sync-report-file",
        type=pathlib.Path,
        default=None,
        help="Optional path to write post-sync consistency report as JSON",
    )
    args = parser.parse_args()
    if args.diff:
        args.dry_run = True

    token: str
    if args.token_file is not None:
        if not args.token_file.exists():
            fail(f"token file not found: {args.token_file}")
        token = args.token_file.read_text(encoding="utf-8").strip()
        if not token:
            fail(f"token file is empty: {args.token_file}")
    else:
        token = (args.token or "").strip()
        if not token:
            fail("token is empty")

    repo_root = pathlib.Path(__file__).resolve().parents[2]
    zones_dir = args.zones_dir if args.zones_dir is not None else build_zones_with_nix(repo_root)
    zone_files = zone_files_from_dir(zones_dir)
    selected = {normalize_name(z) for z in args.zone}

    default_ignore_files = [repo_root / ".technitiumignore", repo_root / "dns/.technitiumignore"]
    if args.ignore_file is not None:
        if not args.ignore_file.exists():
            fail(f"ignore file not found: {args.ignore_file}")
        ignore_files = [args.ignore_file]
    else:
        ignore_files = default_ignore_files
    ignore_rules = read_ignore_rules(args.ignore, ignore_files)
    client = TechnitiumClient(base_url=args.server, token=token, timeout=args.timeout)

    if args.diff:
        print("note: --diff implies --dry-run; no changes will be made to the server.")
    if args.dry_run and not args.no_cleanup:
        print("note: --dry-run does not apply import changes; cleanup diff is against current server state.")
    if args.allow_unparsed:
        print("warning: --allow-unparsed enabled; cleanup safety is reduced and may delete unintended records.")

    total_deleted = 0
    total_skipped_ignored = 0
    ignored_records: List[str] = []
    total_unsupported = 0
    total_would_be_replaced_by_import = 0
    total_skipped_soa = 0
    total_cname_conflicts_removed = 0
    zone_desired_map: Dict[str, set] = {}
    unparsed_report: Dict[str, List[str]] = {}

    for zone_file in zone_files:
        zone = normalize_name(zone_file.stem)
        if selected and zone not in selected:
            continue

        zone_text = zone_file.read_text(encoding="utf-8")
        desired, parse_issues = parse_zone_file(zone, zone_text)
        if parse_issues:
            unparsed_report[zone] = parse_issues
            if not args.allow_unparsed:
                fail(
                    "zone parser encountered unparsed entries.\n"
                    + "\n".join(f"{zone}: {issue}" for issue in parse_issues[:20])
                    + ("\n... (use --allow-unparsed to continue)" if len(parse_issues) > 20 else "")
                )
        zone_desired_map[zone] = desired
        desired_type_map = desired_types_by_name(desired)
        desired_by_name_type: Dict[Tuple[str, str], List[str]] = {}
        for key in desired:
            _, desired_name, desired_type, desired_data = split_key(key)
            desired_by_name_type.setdefault((desired_name, desired_type), []).append(desired_data)

        print(f"syncing zone: {zone}")
        try:
            client.create_zone_if_missing(zone, dry_run=args.dry_run)
            try:
                client.import_zone(zone, zone_text, overwrite_soa_serial=args.overwrite_soa_serial, dry_run=args.dry_run)
            except RuntimeError as exc:
                error_text = str(exc).lower()
                if "cname record cannot exists with other record types" not in error_text:
                    raise
                removed = cleanup_cname_conflicts(
                    client=client,
                    zone=zone,
                    desired_types_map=desired_type_map,
                    dry_run=args.dry_run,
                )
                total_cname_conflicts_removed += removed
                client.import_zone(zone, zone_text, overwrite_soa_serial=args.overwrite_soa_serial, dry_run=args.dry_run)
        except RuntimeError as exc:
            fail(str(exc))

        if args.no_cleanup:
            continue

        try:
            records = client.get_zone_records(zone)
        except RuntimeError as exc:
            fail(str(exc))
        for record in records:
            rtype = normalize_type(str(record.get("type", "")))
            if rtype in IGNORED_SYSTEM_TYPES:
                continue

            name = normalize_name(str(record.get("name", "")))
            data = canonical_data(rtype, record.get("rData", {}) or {}, zone)
            if data is None:
                total_unsupported += 1
                continue

            key = make_key(zone, name, rtype, data)
            if key in desired:
                continue

            if should_ignore(key, ignore_rules):
                total_skipped_ignored += 1
                ignored_records.append(key)
                continue

            wanted = sorted(desired_by_name_type.get((name, rtype), []))
            # In dry-run mode import is not applied, so records in an existing desired RRset
            # appear as stale even though real execution would overwrite that RRset first.
            if args.dry_run and wanted:
                if args.diff:
                    print(f"[diff] {zone}|{name}|{rtype}")
                    print(f"       live: {data}")
                    print(f"    wanted: {json.dumps(wanted, ensure_ascii=True)}")
                    print("     note: would be replaced by import (suppressed in dry-run)")
                total_would_be_replaced_by_import += 1
                continue

            if args.diff:
                print(f"[diff] {zone}|{name}|{rtype}")
                print(f"       live: {data}")
                if wanted:
                    print(f"    wanted: {json.dumps(wanted, ensure_ascii=True)}")
                else:
                    print("    wanted: [] (record missing from desired zone)")

            # Technitium does not allow deleting SOA via records/delete.
            # SOA convergence is handled by zone import/update semantics.
            if rtype == "SOA":
                if args.diff:
                    print("     note: SOA cleanup delete is skipped (undeletable via API)")
                total_skipped_soa += 1
                continue

            try:
                client.delete_record(zone, record, dry_run=args.dry_run)
            except RuntimeError as exc:
                fail(str(exc))
            total_deleted += 1

    print(
        "done: "
        f"deleted={total_deleted}, ignored={total_skipped_ignored}, "
        f"unsupported_seen={total_unsupported}, would_be_replaced_by_import={total_would_be_replaced_by_import}, "
        f"skipped_soa_cleanup={total_skipped_soa}, cname_conflicts_removed={total_cname_conflicts_removed}"
    )
    if unparsed_report:
        print("unparsed zone entries:")
        for zone, issues in sorted(unparsed_report.items()):
            print(f"  {zone}: {len(issues)}")
            shown = 10
            for issue in issues[:shown]:
                print(f"    - {issue}")
            if len(issues) > shown:
                print(f"    - ... and {len(issues) - shown} more")
    if ignored_records:
        print("ignored records:")
        for key in sorted(set(ignored_records)):
            print(f"  - {key}")

    # Post-sync verification pass against live server state.
    post_report: Dict[str, object] = {
        "zones_total": 0,
        "extra_total": 0,
        "missing_total": 0,
        "unsupported_total": 0,
        "ignored_records": [],
        "zones": {},
    }
    for zone, desired in zone_desired_map.items():
        try:
            records = client.get_zone_records(zone)
        except RuntimeError as exc:
            fail(str(exc))

        live_supported_keys: set = set()
        extra: List[str] = []
        unsupported_live: List[str] = []
        for record in records:
            rtype = normalize_type(str(record.get("type", "")))
            if rtype in IGNORED_SYSTEM_TYPES:
                continue

            name = normalize_name(str(record.get("name", "")))
            data = canonical_data(rtype, record.get("rData", {}) or {}, zone)
            if data is None:
                unsupported_live.append(f"{zone}|{name}|{rtype}")
                continue

            key = make_key(zone, name, rtype, data)
            live_supported_keys.add(key)
            if key in desired:
                continue
            if should_ignore(key, ignore_rules):
                ignored_records.append(key)
                continue
            if rtype == "SOA":
                # SOA may still be normalized/managed differently by server settings.
                continue
            extra.append(key)

        missing = sorted(desired - live_supported_keys)

        post_report["zones_total"] = int(post_report["zones_total"]) + 1
        post_report["extra_total"] = int(post_report["extra_total"]) + len(extra)
        post_report["missing_total"] = int(post_report["missing_total"]) + len(missing)
        post_report["unsupported_total"] = int(post_report["unsupported_total"]) + len(unsupported_live)
        post_report["zones"][zone] = {
            "extra": sorted(extra),
            "missing": missing,
            "unsupported_live": sorted(unsupported_live),
        }

    post_report["ignored_records"] = sorted(set(ignored_records))

    print_post_sync_report(post_report, args.post_sync_report_file)


if __name__ == "__main__":
    main()
