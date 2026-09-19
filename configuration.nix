{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix

    # Core system
    ./modules/boot.nix
    ./modules/networking.nix
    ./modules/locale.nix
    ./modules/nix-settings.nix
    ./modules/security.nix

    # Hardware
    ./modules/hardware.nix
    ./modules/audio.nix

    # Desktop & user
    ./modules/desktop.nix
    ./modules/users.nix
    ./modules/apps.nix
    ./modules/default-apps.nix
    ./modules/scripts.nix
  ];

  # Do not change this value. Read documentation before updating.
  system.stateVersion = "26.05";
}
