{ config, pkgs, ... }:

{
  # Budgie ships only a Wayland session here (labwc); xserver stays on for
  # Xwayland and for the xkb layout below.
  services.xserver.enable = true;
  services.desktopManager.budgie.enable = true;

  # SDDM replaces lightdm: Qt, and it actually launches Wayland sessions.
  # Its own greeter runs on weston, not kwin, so no KDE compositor tags along.
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

  # Budgie's module installs GTK/MATE apps that duplicate the Qt ones in
  # apps.nix. Excluding gnome-terminal also flips programs.gnome-terminal.enable
  # off — the module gates that on this same list.
  environment.budgie.excludePackages = with pkgs; [
    nemo                 # -> dolphin
    gnome-terminal       # -> konsole
    eom                  # -> gwenview
    pluma                # -> kate
    atril                # -> okular
    engrampa             # -> ark
    mate-calc            # -> kcalc
    mate-system-monitor  # -> plasma-systemmonitor
  ];

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
