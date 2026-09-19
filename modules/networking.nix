{ config, pkgs, ... }:

{
  networking.hostName = "nixos";
  networking.networkmanager.enable = true;

  networking.firewall = {
    enable = true;
    allowPing = true;
    allowedTCPPortRanges = [ { from = 1714; to = 1764; } ];
    allowedUDPPortRanges = [ { from = 1714; to = 1764; } ];
    allowedTCPPorts = [ 80 443 ];
  };

  # DNS-over-TLS via systemd-resolved; NetworkManager defers to it rather
  # than writing its own /etc/resolv.conf.
  networking.nameservers = [ "1.1.1.1#cloudflare-dns.com" "9.9.9.9#dns.quad9.net" ];
  services.resolved = {
    enable = true;
    settings.Resolve = {
      DNSSEC = "allow-downgrade";
      DNSOverTLS = "true";
    };
  };
  networking.networkmanager.dns = "systemd-resolved";

  # Ethernet stays "stable" (pseudonymous but consistent) so static DHCP
  # reservations on the router keep working; Wi-Fi is fully random.
  networking.networkmanager.wifi.macAddress = "random";
  networking.networkmanager.wifi.scanRandMacAddress = true;
  networking.networkmanager.ethernet.macAddress = "stable";

  # Disable NetworkManager's periodic captive-portal probe.
  networking.networkmanager.settings.connectivity = {
    uri = "";
    interval = 0;
  };
}
