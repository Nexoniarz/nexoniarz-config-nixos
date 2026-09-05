{ config, pkgs, ... }:

let
  # Both SDR++ and rtl_433 default to supporting every radio ever made, which
  # drags in UHD (USRP firmware), BladeRF and LimeSuite — ~1.5 GB for hardware
  # we don't own. These two overrides cut that down to the RTL-SDR paths.
  soapysdrLean = pkgs.soapysdr.override {
    extraPackages = with pkgs; [ soapyrtlsdr soapyremote ];
  };

  rtl433Lean = pkgs.rtl_433.override { soapysdr-with-plugins = soapysdrLean; };

  # Leaves the RTL-SDR, rtl_tcp, file and network sources on.
  sdrppLean = pkgs.sdrpp.override {
    soapy_source = false;
    bladerf_source = false;
    limesdr_source = false;
    plutosdr_source = false;
    airspy_source = false;
    airspyhf_source = false;
    hermes_source = false;
    rfspace_source = false;
    dragonlabs_source = false;
    spectran_http_source = false;
  };
in
{
  users.users."nexoniarz".packages = with pkgs; [
    tumbler
    brightnessctl
    ddcutil
    lm_sensors                # sensors-detect helps ddcutil find the I2C buses
    networkmanager
    xdg-user-dirs             # Resolves localized folder names (Obrazy, not Pictures)

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
    sdrppLean
    rtl433Lean

    # Games
    prismlauncher
    osu-lazer-bin

    # Dev
    glibc
    musl
    cmake
    gnumake
    gcc
    python3
    openjdk25
    claude-code
  ];

  environment.systemPackages = with pkgs; [
    git
    gh
    vim
    fastfetch
    gparted
    efibootmgr
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
    kdePackages.kcalc
    kdePackages.okular
    kdePackages.elisa
    kdePackages.konsole
    kdePackages.dolphin
    kdePackages.plasma-systemmonitor
  ];
}
