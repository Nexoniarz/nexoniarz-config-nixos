{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./modules/system.nix
    ./modules/drivers.nix
    ./modules/desktop.nix
    ./modules/users.nix
    ./modules/apps.nix
    ./modules/scripts.nix
    ./modules/default-apps.nix
  ];

  # Do not change this value. Read documentation before updating.
  system.stateVersion = "26.05";
}
