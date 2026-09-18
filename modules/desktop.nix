{ config, pkgs, ... }:

{
  # Plasma ships a proper Wayland session (KWin) with solid Xwayland
  # support; xserver stays on for that Xwayland layer and for the xkb
  # layout below, not because the session itself needs it.
  services.xserver.enable = true;
  services.desktopManager.plasma6.enable = true;

  # SDDM is KDE's own greeter — Qt-based, and launches Wayland sessions
  # natively, Plasma included.
  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
  };

  security.polkit.enable = true;

  services.xserver.xkb = {
    layout = "pl";
    variant = "";
  };

  services.tumbler.enable = true;
  services.gvfs.enable = true;

  # xserver.nix installs xterm unconditionally; Konsole is the terminal here.
  services.xserver.excludePackages = [ pkgs.xterm ];

  # Icon/cursor theme packages. Plasma has no gsettings-style declarative
  # knob for this the way Budgie did — pick them in System Settings, or
  # bring in plasma-manager later for a fully declarative setup.
  environment.systemPackages = [
    pkgs.gruvbox-plus-icons
    pkgs.bibata-cursors
  ];
}
