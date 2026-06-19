# Technitium Zone Sync

`technitium_zone_sync.py` imports rendered zone files into Technitium DNS and then deletes records that are not defined in your local zones.

The cleanup phase keeps:

- records present in local zone files
- DNSSEC/system-generated records (`RRSIG`, `NSEC*`, `DNSKEY`, `CDS`, `CDNSKEY`)
- records matching your ignore patterns

## Usage

Dry run:

```bash
python3 tools/dns/technitium_zone_sync.py \
  --server http://127.0.0.1:5380 \
  --token "$TECHNITIUM_TOKEN" \
  --dry-run
```

Dry run with mismatch diff output:

```bash
python3 tools/dns/technitium_zone_sync.py \
  --server http://127.0.0.1:5380 \
  --token "$TECHNITIUM_TOKEN" \
  --diff
```

`--diff` is always read-only and implies `--dry-run`.
In dry-run, records that would be overwritten by import are suppressed from delete output and counted as `would_be_replaced_by_import`.

If Technitium import fails with a CNAME coexistence error, the tool auto-removes conflicting records for that name and retries import once. The count is shown as `cname_conflicts_removed` in the summary.

After sync, the tool runs a post-sync scan and prints a consistency report with:

- `extra` records still present on server
- `missing` records expected from desired zone data
- `unsupported_live` record types that cannot be canonicalized by this tool
- `ignored records` that matched your ignore rules

Supported record compare/delete types include: `A`, `AAAA`, `NS`, `CNAME`, `ANAME`, `PTR`, `MX`, `TXT`, `SRV`, `SOA` (serial ignored), `CAA`, and `HTTPS`.

Zonefile parsing follows RFC1035 master-file behavior for:

- comments (`;`) outside quoted strings
- multiline RRs via parentheses
- owner inheritance when a line starts with whitespace
- `$ORIGIN` handling
- `@` and relative-name resolution against origin

The parser is strict by default: unparsed/malformed RR entries fail the run to avoid accidental deletes.
Use `--allow-unparsed` only if you explicitly accept that risk.

`$TTL` is supported as a directive. `$INCLUDE` is rejected (not expanded) to keep parser behavior deterministic.

You can also write the report to JSON:

```bash
python3 tools/dns/technitium_zone_sync.py \
  --server http://127.0.0.1:5380 \
  --token-file /path/to/technitium.token \
  --post-sync-report-file /tmp/technitium-post-sync-report.json
```

Sync all zones:

```bash
python3 tools/dns/technitium_zone_sync.py \
  --server http://127.0.0.1:5380 \
  --token "$TECHNITIUM_TOKEN"
```

Using token file (recommended to avoid shell history leaks):

```bash
python3 tools/dns/technitium_zone_sync.py \
  --server http://127.0.0.1:5380 \
  --token-file /path/to/technitium.token
```

Sync a single zone:

```bash
python3 tools/dns/technitium_zone_sync.py \
  --server http://127.0.0.1:5380 \
  --token "$TECHNITIUM_TOKEN" \
  --zone example.com
```

The script defaults to running `nix build .#dns-zones --out-link result`.  
If you already have zone files, pass `--zones-dir`.

## Ignore Patterns

Ignore keys use the format:

`zone|name|type|data`

Rules behave like `.gitignore` in order:

- `#` starts a comment
- `!pattern` re-includes a previously ignored match
- `\#` or `\!` matches a literal leading `#` / `!`
- Glob matching is done with `fnmatch`

Examples:

- `example.com|home.dyn.example.com|A|*`
- `*|_acme-challenge.*|TXT|*`
- `!*|_acme-challenge.api.example.com|TXT|*`

You can pass rules inline (`--ignore`) and/or from a file (`--ignore-file`).

If `--ignore-file` is not set, the script auto-loads these files when present:

- `.technitiumignore`
- `dns/.technitiumignore`
