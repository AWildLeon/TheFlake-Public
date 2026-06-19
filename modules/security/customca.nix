{
  lib,
  config,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.lh.security.customca;

  lhTrustRootCA = pkgs.writeText "lh-root-ca.pem" ''
    -----BEGIN CERTIFICATE-----
    MIIB8jCCAXigAwIBAgIQVrtg0t+o1A+wk6PzJXIpMTAKBggqhkjOPQQDAzA5MTcw
    NQYDVQQDEy5DTj1MZW9uIEh1YnJpY2ggUm9vdCBDQSxPPWxlb24taHVicmljaC5k
    ZSxDPURFMB4XDTI2MDQxNjEzNTg0NloXDTM2MDQxMzEzNTg0NVowOTE3MDUGA1UE
    AxMuQ049TGVvbiBIdWJyaWNoIFJvb3QgQ0EsTz1sZW9uLWh1YnJpY2guZGUsQz1E
    RTB2MBAGByqGSM49AgEGBSuBBAAiA2IABBndVCTCFUKFnu5bAw9Ok5TkKtL1zrrm
    oChvtBkoiaToG/KtMCVYcRcnq1XtVSKRYfRqnzOMKwNUTloRdR88j2ebXmeab272
    XxyvNbV5Nro9MdCIh7F2MGGzVLwBkpvwVaNFMEMwDgYDVR0PAQH/BAQDAgEGMBIG
    A1UdEwEB/wQIMAYBAf8CAQEwHQYDVR0OBBYEFDGaAo6j0LgvrZBZ1yB9ylehzuq6
    MAoGCCqGSM49BAMDA2gAMGUCMFtv2j7G8skQ78qLfVlchnq1mDF/jdrpq78NRqy0
    V0etdaL+KF489yqJGa8qea4SRQIxAMTe0JemMO6KLEh/NbVv5CbbuYhQI3VciLtX
    50ibABCAgDKCLrXqGLB5AgYBcdWGTg==
    -----END CERTIFICATE-----
  '';
in
{
  options.lh.security.customca = {
    enable = mkEnableOption "Enable LH custom certificate authority";

    includeRootCA = mkOption {
      type = types.bool;
      default = true;
      description = "Include LH-Trust Root CA certificate";
    };

    extraCertificates = mkOption {
      type = types.listOf types.path;
      default = [ ];
      description = "Additional custom certificate files to trust";
    };
  };

  config = mkIf cfg.enable {
    security.pki.certificateFiles = (optional cfg.includeRootCA lhTrustRootCA) ++ cfg.extraCertificates;
  };
}
