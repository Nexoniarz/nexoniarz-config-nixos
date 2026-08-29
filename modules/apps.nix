{ config, pkgs, ... }:

let
  # hyprpolkitagent only ships its binary under libexec/, not bin/, so it
  # never lands on $PATH — wrap it so `exec-once = hyprpolkitagent` in
  # hyprland.conf can find it.
  hyprpolkitagentBin = pkgs.writeShellScriptBin "hyprpolkitagent"
    "exec ${pkgs.hyprpolkitagent}/libexec/hyprpolkitagent";
in
{
  # Every installed package — GUI apps, CLI tools, and dev toolchains alike.
  # If it's "install X", it goes here.
  users.users."nexoniarz".packages = with pkgs; [
    # Hyprland desktop toolchain (Wayland-native, lightweight, squared theme)
    kitty                     # Terminal
    thunar                    # File manager
    thunar-archive-plugin
    thunar-volman
    tumbler                   # Thumbnails (paired with services.tumbler.enable)
    rofi                      # Launcher (Wayland support built in since 2.0)
    quickshell                # Bar / UI shell
    imv                       # Image viewer
    mako                      # Notification daemon
    grim                      # Screenshot capture
    slurp                     # Screenshot region select
    wl-clipboard               # Wayland clipboard
    hyprpolkitagentBin        # Polkit authentication agent (wrapped, see `let` above)
    hyprlock                  # Screen locker (power menu)
    brightnessctl             # Backlight brightness (laptop panels)
    ddcutil                   # DDC/CI brightness (external monitors)
    lm_sensors                # sensors-detect helps ddcutil find I2C buses
    hyprpaper                 # Wallpaper daemon, driven by the Quickshell picker (static images)
    mpvpaper                  # Wallpaper daemon for video-loop (animated) wallpapers
    networkmanager            # nmcli, for the Wi-Fi hotspot toggle
    xdg-user-dirs             # Resolves localized folder names (Obrazy, not Pictures, on pl_PL)
    bibata-cursors            # Cursor theme(s) for the cursor picker
    xcur2png                  # Renders Xcursor files to PNG for the cursor picker's previews
    imagemagick                # `identify`, used to pick the right cursor-preview size

    # Apps
    blender
    gimp
    inkscape
    vesktop
    tor-browser
    ffmpeg-full
    vlc
    filezilla
    chromium

    # Games
    prismlauncher
    pkgs.osu-lazer-bin

    # Dev: compilers, runtimes, languages
    glibc
    musl
    cmake
    gnumake # Provides the 'make' command
    gcc
    python3
    openjdk25
    claude-code # AI Developer Assistant
  ];

  # Global command-line utilities available everywhere
  environment.systemPackages = with pkgs; [
    git
    vim
    fastfetch
    gparted
    firejail
    gnupg
    lmstudio
  ];
}
