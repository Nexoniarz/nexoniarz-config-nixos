#!/usr/bin/env bash
# Regenerates qt6ct's config + color scheme to match the current Quickshell
# theme, the Qt-side equivalent of gtk-theme-set. Qt apps (Gwenview, Ark,
# Kate, ...) had no working platform theme plugin at all before this — the
# QT_QPA_PLATFORMTHEME=qt6ct env var (hyprland.conf) was pointing at a
# plugin that wasn't even installed, so every Qt app fell back to
# whatever default style/palette it shipped with, ignoring the rest of
# the desktop entirely. style=Fusion (not a KDE/Breeze style) matters
# specifically: Fusion paints straight from QPalette, so a custom color
# scheme here is guaranteed to actually show — Breeze-family styles
# prefer reading colors from kdeglobals instead, which is a separate,
# static, unrelated leftover file on this machine.
set -euo pipefail

accent="${1:?usage: qt-theme-set <accent> <bg> <bgAlt> <fg> <fgDim> <border> <dark:1|0>}"
bg="${2:?bg required}"
bg_alt="${3:?bgAlt required}"
fg="${4:?fg required}"
fg_dim="${5:?fgDim required}"
border="${6:?border required}"
dark="${7:?dark required}"

dir="$HOME/.config/qt6ct"
mkdir -p "$dir/colors"

# qt6ct color scheme files store QPalette::ColorRole values as a fixed-
# order, comma-separated #aarrggbb list — order and format verified
# against the example schemes qt6ct itself ships
# (share/qt6ct/colors/darker.conf etc.), not guessed: WindowText, Button,
# Light, Midlight, Dark, Mid, Text, BrightText, ButtonText, Base, Window,
# Shadow, Highlight, HighlightedText, Link, LinkVisited, AlternateBase,
# NoRole, ToolTipBase, ToolTipText, PlaceholderText.
a() { printf '#ff%s' "${1#\#}"; }  # opaque
t() { printf '#80%s' "${1#\#}"; }  # translucent, for PlaceholderText

active="$(a "$fg"), $(a "$bg_alt"), $(a "$border"), $(a "$bg_alt"), $(a "$bg"), $(a "$border"), $(a "$fg"), $(a "$fg"), $(a "$fg"), $(a "$bg"), $(a "$bg"), $(a "$border"), $(a "$accent"), $(a "$bg"), $(a "$accent"), $(a "$accent"), $(a "$bg_alt"), $(a "$bg"), $(a "$bg_alt"), $(a "$fg"), $(t "$fg_dim")"
disabled="$(a "$fg_dim"), $(a "$bg_alt"), $(a "$border"), $(a "$bg_alt"), $(a "$bg"), $(a "$border"), $(a "$fg_dim"), $(a "$fg_dim"), $(a "$fg_dim"), $(a "$bg"), $(a "$bg"), $(a "$border"), $(a "$accent"), $(a "$fg_dim"), $(a "$accent"), $(a "$accent"), $(a "$bg_alt"), $(a "$bg"), $(a "$bg_alt"), $(a "$fg_dim"), $(t "$fg_dim")"

color_file="$dir/colors/quickshell-theme.conf"
cat > "$color_file" <<EOF
[ColorScheme]
active_colors=$active
disabled_colors=$disabled
inactive_colors=$active
EOF

icon_theme="Gruvbox-Plus-Light"
[ "$dark" = "1" ] && icon_theme="Gruvbox-Plus-Dark"

cat > "$dir/qt6ct.conf" <<EOF
[Appearance]
style=Fusion
icon_theme=$icon_theme
custom_palette=true
color_scheme_path=$color_file
standard_dialogs=default
EOF

# qt6ct's palette only reaches classic QWidget UI. Modern KDE apps
# (confirmed live: Gwenview) draw their toolbar/chrome with Kirigami/QML
# instead, which ignores QPalette entirely and reads kdeglobals' color
# groups directly via KColorScheme — so without this, qt6ct alone left
# exactly that chrome stuck on whatever this machine's stale leftover
# kdeglobals had (unrelated purple KDE colors from some earlier install),
# while everything else (dialogs, the actual image viewport, ...)
# correctly followed the theme.
rgb() {
    local hex="${1#\#}"
    printf '%d,%d,%d' "0x${hex:0:2}" "0x${hex:2:2}" "0x${hex:4:2}"
}

cat > "$HOME/.config/kdeglobals" <<EOF
[General]
ColorScheme=QuickshellTheme
widgetStyle=Fusion

[KDE]
widgetStyle=Fusion

[Colors:Window]
BackgroundNormal=$(rgb "$bg_alt")
ForegroundNormal=$(rgb "$fg")

[Colors:View]
BackgroundNormal=$(rgb "$bg")
ForegroundNormal=$(rgb "$fg")

[Colors:Button]
BackgroundNormal=$(rgb "$bg_alt")
ForegroundNormal=$(rgb "$fg")

[Colors:Selection]
BackgroundNormal=$(rgb "$accent")
ForegroundNormal=$(rgb "$bg")
DecorationFocus=$(rgb "$accent")
DecorationHover=$(rgb "$accent")

[Colors:Tooltip]
BackgroundNormal=$(rgb "$bg_alt")
ForegroundNormal=$(rgb "$fg")

[Colors:Header]
BackgroundNormal=$(rgb "$bg_alt")
ForegroundNormal=$(rgb "$fg")
EOF
