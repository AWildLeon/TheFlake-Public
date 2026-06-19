{
  config,
  lib,
  pkgs,
  ...
}:
{

  config = lib.mkIf (config.lh.roleSystem.systemType == "router") {
    lh = {
      security.ssh.enable = lib.mkDefault true;
    };

    # Useful debugging and networking tools
    environment.systemPackages = with pkgs; [
      ethtool
      dig
      tcpdump
      termshark
      htop
      mtr
      nmap
      iperf3
      wireguard-tools
      conntrack-tools
    ];

    programs.arp-scan.enable = lib.mkDefault true;

    networking.nftables.enable = lib.mkDefault true;
    boot.kernel.sysctl =
      let
        net_core_mem = 16777216; # 16 MiB
        nf_conntrack_max = 1048576;
      in
      {
        "net.ipv4.ip_forward" = 1;
        "net.ipv6.conf.all.forwarding" = 1;
        "net.ipv6.conf.default.forwarding" = 1;

        "net.core.rmem_default" = net_core_mem;
        "net.core.rmem_max" = net_core_mem;
        "net.core.wmem_default" = net_core_mem;
        "net.core.wmem_max" = net_core_mem;
        "net.core.optmem_max" = 4194304;

        "net.netfilter.nf_conntrack_max" = nf_conntrack_max;
        "net.netfilter.nf_conntrack_buckets" = nf_conntrack_max / 4;
        "net.netfilter.nf_conntrack_acct" = 1;

        "net.ipv4.neigh.default.gc_thresh1" = 1024;
        "net.ipv4.neigh.default.gc_thresh2" = 4096;
        "net.ipv4.neigh.default.gc_thresh3" = 8192;

        "net.core.default_qdisc" = "fq_codel";
        "net.ipv4.tcp_congestion_control" = "bbr";

      };
  };
}
