{ config, lib, pkgs, ... }:

# My machines working together at home: SSH (keys only) and ZeroVRAM's zvm_node (port 8080),
# both reachable from the home network only — not from other networks the laptop joins.
let
  homeLan = "192.168.1.0/24";
  homePorts = [ 22 8080 ];  # SSH, zvm_node
  rule = op: port: "iptables ${op} nixos-fw -p tcp -s ${homeLan} --dport ${toString port} -j nixos-fw-accept";
in
{
  # Fixed names for the machines (their addresses are reserved in the router). The router's own
  # *.lan names don't resolve here: DNS goes over TLS to public resolvers (networking.nix).
  networking.hosts = {
    "192.168.1.225" = [ "nexo-pc" ];
    "192.168.1.197" = [ "nexo-laptop" ];
  };

  services.openssh = {
    enable = true;
    openFirewall = false;  # opened below for the home network only
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
      AllowUsers = [ "nexoniarz" ];
    };
  };

  # Keys allowed to log in here. The laptop's key goes in this list once it has one
  # (ssh-keygen -t ed25519 on the laptop, then the line from ~/.ssh/id_ed25519.pub).
  users.users."nexoniarz".openssh.authorizedKeys.keys = [
  ];

  # Inserted at the top of the firewall chain (rules appended at the end would come after its
  # final reject); removed again when the firewall stops or reloads.
  networking.firewall.extraCommands = lib.concatMapStringsSep "\n" (rule "-I") homePorts;
  networking.firewall.extraStopCommands = lib.concatMapStringsSep "\n" (p: "${rule "-D" p} || true") homePorts;
}
