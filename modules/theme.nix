{ config, pkgs, lib, ... }:

{
  # Dark GTK theme (built into GTK3/4's Adwaita since 3.20) for Thunar and
  # other GTK apps, as a starting point. The actual palette (accent color,
  # dark/light) is no longer static here — it's generated at runtime by
  # gtk-theme-set (modules/scripts/gtk-theme-set.sh), called from the
  # Quickshell Theme picker (dotfiles/quickshell/Theme.qml) every time the
  # theme changes, so switching accent/mode there actually reaches GTK
  # apps instead of requiring a rebuild.
  environment.systemPackages = with pkgs; [
    gnome-themes-extra
    adwaita-icon-theme
    gruvbox-plus-icons
    dconf
    # Qt's side of the same live-theming pipeline as GTK above — see
    # qt-theme-set (modules/scripts/qt-theme-set.sh). Without this
    # installed, QT_QPA_PLATFORMTHEME=qt6ct (hyprland.conf) pointed at a
    # platform theme plugin that didn't exist, so every Qt app (Gwenview,
    # Ark, Kate, ...) silently fell back to its own default style/palette
    # instead of anything resembling the rest of the desktop.
    qt6Packages.qt6ct
    kdePackages.qqc2-desktop-style # QQC2 style needed for QT_QUICK_CONTROLS_STYLE=
                                     # org.kde.desktop (hyprland.conf) to actually
                                     # theme Kirigami-based apps' chrome
  ];

  # No environment.sessionVariables.GTK_THEME here on purpose: GTK_THEME
  # takes priority over settings.ini's gtk-theme-name for GTK3 apps, and
  # as a session env var it's fixed at login — it can't be changed live.
  # A leftover "Adwaita:dark" override here was silently overriding
  # whatever gtk-theme-set wrote to settings.ini, permanently forcing
  # dark mode and blocking the Theme picker from ever reaching Thunar.

  systemd.tmpfiles.rules = [
    "d /home/nexoniarz/.config/gtk-3.0 0755 nexoniarz users -"
    "d /home/nexoniarz/.config/gtk-4.0 0755 nexoniarz users -"
    "d /home/nexoniarz/.config/qt6ct 0755 nexoniarz users -"
    "d /home/nexoniarz/.config/qt6ct/colors 0755 nexoniarz users -"
    # `f`, not `L+`: created empty only if missing, never overwritten on
    # rebuild — gtk-theme-set/qt-theme-set own the actual content from
    # here on.
    "f /home/nexoniarz/.config/gtk-3.0/gtk.css 0644 nexoniarz users - -"
    "f /home/nexoniarz/.config/gtk-4.0/gtk.css 0644 nexoniarz users - -"
    "f /home/nexoniarz/.config/gtk-3.0/settings.ini 0644 nexoniarz users - -"
    "f /home/nexoniarz/.config/gtk-4.0/settings.ini 0644 nexoniarz users - -"
    "f /home/nexoniarz/.gtkrc-2.0 0644 nexoniarz users - -"
    "f /home/nexoniarz/.config/qt6ct/qt6ct.conf 0644 nexoniarz users - -"
  ];
}
