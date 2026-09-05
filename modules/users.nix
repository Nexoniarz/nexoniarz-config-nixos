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
}
