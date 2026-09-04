{ config, pkgs, ... }:

{
  # --- Budgie: X11 desktop environment, lightdm login manager ---
  services.xserver.enable = true;
  services.xserver.displayManager.lightdm.enable = true;
  services.desktopManager.budgie.enable = true;

  security.polkit.enable = true;

  # Keyboard layout for console/X11/lightdm
  services.xserver.xkb = {
    layout = "pl";
    variant = "";
  };

  # Thumbnails + trash/volume mount integration for Dolphin and Budgie's
  # default Nemo file manager alike.
  services.tumbler.enable = true;
  services.gvfs.enable = true;

  # Drop the xterm fallback terminal xserver.nix installs unconditionally —
  # Konsole is the real terminal here.
  services.xserver.excludePackages = [ pkgs.xterm ];

  # GTK/Qt themselves stay at their stock defaults (no forced dark mode, no
  # custom CSS) — only the icon and cursor theme are picked explicitly, via
  # Budgie's own GSettings-override hook rather than a custom script.
  # (extraGSettingsOverridePackages is for packages that ship their own
  # gsettings-schema overrides, e.g. plugins — not theme packages, which
  # just need to be on the system path for their icons/cursors to resolve.)
  environment.systemPackages = [
    pkgs.gruvbox-plus-icons
    pkgs.bibata-cursors
  ];
  services.desktopManager.budgie.extraGSettingsOverrides = ''
    [org.gnome.desktop.interface]
    icon-theme='Gruvbox-Plus-Dark'
    cursor-theme='Bibata-Modern-Classic'
  '';
}
