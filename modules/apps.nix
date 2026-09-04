{ config, pkgs, ... }:

{
  # Every installed package — GUI apps, CLI tools, and dev toolchains alike.
  # If it's "install X", it goes here.
  users.users."nexoniarz".packages = with pkgs; [
    tumbler                   # Thumbnails (paired with services.tumbler.enable; also used by Nemo)
    gnome-screenshot          # Screenshot capture (X11)
    imv                       # Image viewer
    brightnessctl             # Backlight brightness (laptop panels)
    ddcutil                   # DDC/CI brightness (external monitors)
    lm_sensors                # sensors-detect helps ddcutil find I2C buses
    networkmanager            # nmcli, for the Wi-Fi hotspot toggle
    xdg-user-dirs             # Resolves localized folder names (Obrazy, not Pictures, on pl_PL)
    playerctl                  # MPRIS media control, for the function-key media binds

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
    obs-studio
    easyeffects                # Real-time mic/output effects (pitch, EQ, ...) — auto-creates a
                                # selectable "Easy Effects Source" virtual mic once an Input effect
                                # is added, no manual PipeWire routing needed
    qpwgraph                   # Patchbay GUI — wires EasyEffects'/Soundux's output into the
                                # standalone "Virtual Microphone Sink" (see system.nix)
    # Soundux (soundboard) isn't packaged in this nixpkgs channel anymore —
    # installed via Flatpak instead (io.github.Soundux).

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
    gh # GitHub CLI — was only installed ad-hoc before (login didn't survive)
    vim
    fastfetch
    gparted
    firejail
    gnupg
    lmstudio
    kdePackages.ark
    p7zip
    unzip
    unrar
    kdePackages.gwenview
    kdePackages.kate
    kdePackages.qqc2-desktop-style
    linphonePackages.linphone-desktop
    kdePackages.kcalc            # Calculator (nothing filled this role before)
    kdePackages.okular           # Document/PDF viewer (nothing filled this role before)
    kdePackages.elisa            # Audio player (vlc/ffmpeg cover video already; nothing dedicated for audio)
    kdePackages.konsole          # Terminal (replaces kitty)
    kdePackages.dolphin          # File manager (replaces Thunar, alongside Budgie's default Nemo)
  ];
}
