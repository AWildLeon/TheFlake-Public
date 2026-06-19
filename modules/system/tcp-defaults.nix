{ lib, ... }:
{
  # Global network defaults; hosts can still override if needed.
  boot.kernel.sysctl = {
    "net.ipv4.tcp_congestion_control" = lib.mkDefault "bbr";
    "net.core.default_qdisc" = lib.mkDefault "fq_codel";
  };
}
