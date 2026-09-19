{ config, pkgs, ... }:

{
  users.users."nexoniarz" = {
    isNormalUser = true;
    description = "Nexoniarz";
    extraGroups = [ "networkmanager" "wheel" "fuse" "i2c" "video" "plugdev" ];
    shell = pkgs.zsh;
  };

  programs.zsh.enable = true;
  programs.firefox.enable = true;

  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true;
  };

  services.flatpak.enable = true;

  # Flatpak's exported .desktop files aren't on XDG_DATA_DIRS by default,
  # so Bottles would otherwise not show up in the launcher.
  systemd.tmpfiles.rules = [
    "L+ /var/lib/flatpak/exports/share/applications - - - - /var/lib/flatpak/app/com.usebottles.bottles/current/active/export/share/applications"
  ];
}
