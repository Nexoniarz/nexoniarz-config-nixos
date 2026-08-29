{ config, pkgs, ... }:

{
  # --- Hyprland: Wayland compositor ---
  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
  };

  # --- greetd + tuigreet: minimal TUI login manager, launches Hyprland directly ---
  services.greetd = {
    enable = true;
    settings.default_session = {
      command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --remember-session --cmd Hyprland";
      user = "greeter";
    };
  };

  # --- XDG portals: screen share, file pickers, etc. ---
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-hyprland pkgs.xdg-desktop-portal-gtk ];
    config.common.default = [ "hyprland" "gtk" ];
  };

  security.polkit.enable = true;

  # Keyboard layout for console/XWayland/greetd; Hyprland's own input block
  # in hyprland/hyprland.conf mirrors this.
  services.xserver.xkb = {
    layout = "pl";
    variant = "";
  };

  # Thunar: thumbnails, trash/volume mount integration, settings storage
  services.tumbler.enable = true;
  services.gvfs.enable = true;
  programs.xfconf.enable = true;

  # Native Wayland backend for Electron/Chromium-based apps
  environment.sessionVariables.NIXOS_OZONE_WL = "1";

  # --- Dotfiles: symlink tracked configs into the user's home ---
  # Editing /etc/nixos/hyprland or /etc/nixos/dotfiles takes effect on the
  # next reload of the respective app (no rebuild needed for config-only
  # tweaks; a rebuild re-runs the symlink if the target path itself changes).
  systemd.tmpfiles.rules = [
    "d /home/nexoniarz/.config/hypr 0755 nexoniarz users -"
    "L+ /home/nexoniarz/.config/hypr/hyprland.conf - - - - /etc/nixos/hyprland/hyprland.conf"
    "L+ /home/nexoniarz/.config/hypr/hyprpaper.conf - - - - /etc/nixos/hyprland/hyprpaper.conf"

    "d /home/nexoniarz/.config/kitty 0755 nexoniarz users -"
    "L+ /home/nexoniarz/.config/kitty/kitty.conf - - - - /etc/nixos/dotfiles/kitty/kitty.conf"
    # Colors set live via the Quickshell Theme picker — see kitty.conf's
    # `include theme.conf`. Empty by default; kitty-theme-set writes to it.
    "f /home/nexoniarz/.config/kitty/theme.conf 0644 nexoniarz users - -"

    "d /home/nexoniarz/.config/rofi 0755 nexoniarz users -"
    "L+ /home/nexoniarz/.config/rofi/config.rasi - - - - /etc/nixos/dotfiles/rofi/config.rasi"
    # Colors set live via the Quickshell Theme picker — see config.rasi's
    # `@import "theme.rasi"`. Empty by default; rofi-theme-set writes to it.
    "f /home/nexoniarz/.config/rofi/theme.rasi 0644 nexoniarz users - -"

    "d /home/nexoniarz/.config/mako 0755 nexoniarz users -"
    "L+ /home/nexoniarz/.config/mako/config - - - - /etc/nixos/dotfiles/mako/config"

    # Quickshell is multi-file with relative imports, so the whole directory
    # is symlinked rather than a single file.
    "L+ /home/nexoniarz/.config/quickshell - - - - /etc/nixos/dotfiles/quickshell"

    # $HOME/Wallpapers, not $HOME/Pictures/Wallpapers — this system's locale
    # (pl_PL) means the real XDG Pictures dir is ~/Obrazy, not ~/Pictures.
    # Living directly under $HOME sidesteps that entirely.
    "d /home/nexoniarz/Wallpapers 0755 nexoniarz users -"
    "d /home/nexoniarz/Screenshots 0755 nexoniarz users -"

    # User-editable cursor theme choice (set live via the Quickshell cursor
    # picker) — created empty if missing, never overwritten if it already
    # has content, since it's runtime state rather than tracked config.
    "f /home/nexoniarz/.config/hypr/cursor.conf 0644 nexoniarz users - -"

    # Same deal for display settings (mode/scale/transform per monitor,
    # set via the Quickshell display picker) — without this file backing
    # them, they only ever applied live via hyprctl and got silently
    # reset by hyprland.conf's generic fallback monitor rule any time
    # Hyprland re-evaluated monitor state.
    "f /home/nexoniarz/.config/hypr/display.conf 0644 nexoniarz users - -"

    # Same deal for window border colors (accent/border, set live via the
    # Quickshell Theme picker) — without this file, they only ever applied
    # via hyprctl and would fall back to hyprland.conf's own general{}
    # defaults any time Hyprland re-evaluated its config.
    "f /home/nexoniarz/.config/hypr/theme.conf 0644 nexoniarz users - -"
  ];
}
