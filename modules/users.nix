{ config, pkgs, ... }:

{
  # Primary user account configuration (Access and settings only)
  users.users."nexoniarz" = {
    isNormalUser = true;
    description = "Nexoniarz";
    extraGroups = [ "networkmanager" "wheel" "fuse" "i2c" "video" ];
    shell = pkgs.zsh;
  };

  # Default shell (ZSH)
  programs.zsh.enable = true;

  # Web browser configuration
  programs.firefox.enable = true;

  # Enable Steam with optimized system configurations
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true;
  };

  # Enable Flatpak support
  services.flatpak.enable = true;
}
