pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Single source of truth for every color used across the shell — swapping
// accent color or dark/light mode here changes it everywhere, instead of
// hunting down hardcoded hex values in 14 different files (which is what
// this replaced). Persisted to disk (same pattern as the wallpaper/booru
// settings) since PersistentProperties doesn't survive a real restart.
//
// Plain strings, not `color`-typed properties — QML still accepts them
// fine anywhere a `color:` binding is expected (auto-converts at the
// point of use), but keeping them as strings means they can also be
// handed straight to hypr-theme-set/gtk-theme-set as clean "#rrggbb"
// text without a color-to-string round trip appending an alpha suffix.
Item {
    id: theme

    property bool dark: true
    property string accentName: "teal"

    readonly property var accentPalette: ({
        teal:   "#8fbcbb",
        blue:   "#61afef",
        green:  "#98c379",
        purple: "#c678dd",
        orange: "#d19a66",
        pink:   "#ff79c6",
        yellow: "#e5c07b"
    })
    readonly property var accentNames: ["teal", "blue", "green", "purple", "orange", "pink", "yellow"]

    readonly property string accent: theme.accentPalette[theme.accentName] || theme.accentPalette.teal
    readonly property string danger: "#e06c75"

    // Dark palette (the original, and still the default)
    readonly property string bgDark: "#0d0d0d"
    readonly property string bgAltDark: "#1a1a1a"
    readonly property string bgAlt2Dark: "#131313"
    readonly property string fgDark: "#e0e0e0"
    readonly property string fgDimDark: "#666666"
    readonly property string fgDim2Dark: "#999999"
    readonly property string borderDark: "#333333"
    readonly property string borderDimDark: "#262626"

    // Light palette
    readonly property string bgLight: "#f0f0f0"
    readonly property string bgAltLight: "#e2e2e2"
    readonly property string bgAlt2Light: "#d5d5d5"
    readonly property string fgLight: "#1a1a1a"
    readonly property string fgDimLight: "#666666"
    readonly property string fgDim2Light: "#888888"
    readonly property string borderLight: "#c4c4c4"
    readonly property string borderDimLight: "#d8d8d8"

    readonly property string bg: theme.dark ? theme.bgDark : theme.bgLight
    readonly property string bgAlt: theme.dark ? theme.bgAltDark : theme.bgAltLight
    readonly property string bgAlt2: theme.dark ? theme.bgAlt2Dark : theme.bgAlt2Light
    readonly property string fg: theme.dark ? theme.fgDark : theme.fgLight
    readonly property string fgDim: theme.dark ? theme.fgDimDark : theme.fgDimLight
    readonly property string fgDim2: theme.dark ? theme.fgDim2Dark : theme.fgDim2Light
    readonly property string border: theme.dark ? theme.borderDark : theme.borderLight
    readonly property string borderDim: theme.dark ? theme.borderDimDark : theme.borderDimLight

    property string stateFile: Quickshell.stateDir + "/theme-settings.json"

    function setAccent(name) {
        if (theme.accentPalette[name] === undefined) return;
        theme.accentName = name;
        theme.save();
        theme.syncSystem();
    }
    function setDark(isDark) {
        theme.dark = isDark;
        theme.save();
        theme.syncSystem();
    }
    function randomAccent() {
        var names = theme.accentNames;
        var pick = names[Math.floor(Math.random() * names.length)];
        theme.setAccent(pick);
    }

    function save() {
        var json = JSON.stringify({ dark: theme.dark, accentName: theme.accentName });
        saveProc.command = ["sh", "-c",
            "mkdir -p \"$(dirname \"$2\")\" && printf '%s' \"$1\" > \"$2\"",
            "--", json, theme.stateFile];
        saveProc.running = true;
    }

    // Pushes the current palette out to the two things that don't read
    // this file directly: Hyprland's window border colors (hardcoded in
    // hyprland.conf otherwise) and GTK apps like Thunar (which used to be
    // a static Nix-rebuild-only CSS file).
    function syncSystem() {
        hyprSyncProc.command = ["hypr-theme-set",
            theme.accent.replace("#", ""), theme.border.replace("#", "")];
        hyprSyncProc.running = true;

        gtkSyncProc.command = ["gtk-theme-set",
            theme.accent, theme.bg, theme.bgAlt, theme.fg, theme.fgDim, theme.border,
            theme.dark ? "1" : "0"];
        gtkSyncProc.running = true;

        kittySyncProc.command = ["kitty-theme-set",
            theme.accent, theme.bg, theme.bgAlt, theme.fg, theme.fgDim, theme.border];
        kittySyncProc.running = true;

        rofiSyncProc.command = ["rofi-theme-set",
            theme.accent, theme.bg, theme.bgAlt, theme.fg, theme.fgDim, theme.border,
            theme.dark ? "1" : "0"];
        rofiSyncProc.running = true;
    }

    Process { id: saveProc }
    Process { id: hyprSyncProc }
    Process { id: gtkSyncProc }
    Process { id: kittySyncProc }
    Process { id: rofiSyncProc }
    Process {
        id: loadProc
        command: ["cat", theme.stateFile]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var d = JSON.parse(text);
                    if (typeof d.dark === "boolean") theme.dark = d.dark;
                    if (d.accentName) theme.accentName = d.accentName;
                } catch (e) { /* no state file yet — defaults stand */ }
                // Always sync on load, even if the state file didn't
                // exist — Hyprland's border colors and GTK's CSS are
                // otherwise still whatever was last written (or the
                // hardcoded hyprland.conf default), independent of
                // whether Quickshell itself just restarted.
                theme.syncSystem();
            }
        }
    }
    Component.onCompleted: loadProc.running = true
}
