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

  # The third-party "Bouncing Popups" KWin effect (~/.local/share/kwin/effects)
  # stacks on top of Plasma's own slidingpopups/fadingpopups and forces blur
  # on every popup and the panel, making applet popups and panel settings
  # open sluggishly. [$i] locks the key so ~/.config/kwinrc can't re-enable it.
  environment.etc."xdg/kwinrc".text = ''
    [Plugins]
    bouncingPopupsEnabled[$i]=false
  '';

  # Breeze Dark as the default Plasma (panel/popup) theme. Avoid sparse
  # third-party themes like "Darkly" (18 files): every SVG they lack falls
  # back via an uncached search of all ~89 XDG_DATA_DIRS, which made applet
  # popups and panel settings take 2-6 s to open. Not locked, so the theme
  # can still be changed in System Settings.
  environment.etc."xdg/plasmarc".text = ''
    [Theme]
    name=breeze-dark
  '';

  environment.extraInit = ''
    export XDG_DATA_DIRS="$XDG_DATA_DIRS:${pkgs.gtk3}/share/gsettings-schemas/${pkgs.gtk3.name}"
  '';

  fonts.packages = with pkgs; [
    corefonts
    dejavu_fonts
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-color-emoji
    nerd-fonts.fira-code
    nerd-fonts.jetbrains-mono
    nerd-fonts.hack
    inter
    liberation_ttf
    roboto
  ];
}
