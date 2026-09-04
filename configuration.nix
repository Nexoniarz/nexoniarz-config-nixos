# Main NixOS configuration file importing modular configurations.

{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix   # Generated hardware scan results
    ./modules/system.nix           # Bootloader, networking, time, sound, hardening, nix-ld
    ./modules/drivers.nix          # NVIDIA Open GPU kernel modules and graphics
    ./modules/desktop.nix          # Budgie desktop environment
    ./modules/users.nix            # User accounts and global configurations
    ./modules/apps.nix             # All installed packages: apps, CLI tools, dev toolchains
    ./modules/scripts.nix          # Custom system scripts and helpers
    ./modules/default-apps.nix     # Default app associations (terminal, image viewer, archives), LibreOffice
  ];

  # Do not change this value. Read documentation before updating.
  system.stateVersion = "26.05"; 
}
