{ config, lib, pkgs, ... }:

{
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.limine = {
    enable = true;
    maxGenerations = 5;

    # Gruvbox, to match the icon theme.
    style = {
      wallpapers = [ ];   # Solid background; a path here would be used instead
      interface = {
        branding = "NixOS";
        brandingColor = "fabd2f";
        helpColor = "928374";
        helpColorBright = "d79921";
      };
      graphicalTerminal = {
        foreground = "ebdbb2";
        background = "00282828";
        brightForeground = "fbf1c7";
        palette = "282828;cc241d;98971a;d79921;458588;b16286;689d6a;a89984";
        brightPalette = "928374;fb4934;b8bb26;fabd2f;83a598;d3869b;8ec07c;ebdbb2";
        margin = 32;
      };
    };
  };
  boot.kernelPackages = pkgs.linuxPackages;
  boot.supportedFilesystems = [ "fuse" ];

  networking.hostName = "nixos";
  networking.networkmanager.enable = true;

  networking.firewall = {
    enable = true;
    allowPing = true;
    allowedTCPPortRanges = [ { from = 1714; to = 1764; } ];
    allowedUDPPortRanges = [ { from = 1714; to = 1764; } ];
    allowedTCPPorts = [ 80 443 ];
  };

  time.timeZone = "Europe/Warsaw";
  i18n.defaultLocale = "pl_PL.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "pl_PL.UTF-8";
    LC_IDENTIFICATION = "pl_PL.UTF-8";
    LC_MEASUREMENT = "pl_PL.UTF-8";
    LC_MONETARY = "pl_PL.UTF-8";
    LC_NAME = "pl_PL.UTF-8";
    LC_NUMERIC = "pl_PL.UTF-8";
    LC_PAPER = "pl_PL.UTF-8";
    LC_TELEPHONE = "pl_PL.UTF-8";
    LC_TIME = "pl_PL.UTF-8";
  };

  nix.settings.auto-optimise-store = true;
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
  };

  console.keyMap = "pl2";

  security.rtkit.enable = true;
  services.pulseaudio.enable = false;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings = {
      General = {
        Experimental = true;      # Battery level of connected devices
        FastConnectable = true;   # Faster reconnects, more power draw
      };
      Policy = {
        AutoEnable = true;
      };
    };
  };

  services.blueman.enable = true;

  programs.firejail = {
    enable = true;
  };

  programs.fuse.userAllowOther = true;

  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
    pinentryPackage = pkgs.pinentry-rofi;
  };

  security.sudo.extraConfig = ''
    Defaults pwfeedback
  '';

  services.printing.enable = true;

  nixpkgs.config.allowUnfree = true;

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

  # Lets non-Nix binaries (e.g. the Tor Browser bundle) find an FHS linker.
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    glib gtk3 gdk-pixbuf pango cairo atk
    dbus dbus-glib fontconfig freetype
    libx11 libxext libxrender libxtst
    libxi libxcomposite libxdamage libxfixes
    libxrandr libxcursor libxcb libxkbcommon
    alsa-lib mesa zlib stdenv.cc.cc
  ];
  environment.systemPackages = [ pkgs.file ];

  # --- Hardening ---

  # zram instead of disk swap: nothing sensitive is written to disk in
  # plaintext. systemd's gpt-auto-generator would otherwise re-activate the
  # old swap partition regardless of swapDevices, hence the kernel param.
  zramSwap.enable = true;
  swapDevices = lib.mkForce [ ];
  boot.kernelParams = [ "systemd.gpt_auto=0" ];

  boot.kernel.sysctl = {
    "kernel.kptr_restrict" = 2;
    "kernel.dmesg_restrict" = 1;
    "net.ipv4.conf.all.rp_filter" = 1;
    "net.ipv4.conf.default.rp_filter" = 1;
    "net.ipv4.conf.all.accept_redirects" = false;
    "net.ipv4.conf.default.accept_redirects" = false;
    "net.ipv6.conf.all.accept_redirects" = false;
    "net.ipv6.conf.default.accept_redirects" = false;
    "net.ipv4.conf.all.send_redirects" = false;
    "net.ipv4.conf.default.send_redirects" = false;
    # Only bites ad-hoc `gdb -p <pid>` on a non-child process.
    "kernel.yama.ptrace_scope" = 1;
    "net.ipv4.tcp_timestamps" = 0;
  };

  systemd.coredump.enable = false;
  security.protectKernelImage = true;

  networking.nameservers = [ "1.1.1.1#cloudflare-dns.com" "9.9.9.9#dns.quad9.net" ];
  services.resolved = {
    enable = true;
    settings.Resolve = {
      DNSSEC = "allow-downgrade";
      DNSOverTLS = "true";
    };
  };
  networking.networkmanager.dns = "systemd-resolved";

  # Ethernet stays "stable" (pseudonymous but consistent) so static DHCP
  # reservations on the router keep working; Wi-Fi is fully random.
  networking.networkmanager.wifi.macAddress = "random";
  networking.networkmanager.wifi.scanRandMacAddress = true;
  networking.networkmanager.ethernet.macAddress = "stable";

  # Disable NetworkManager's periodic captive-portal probe.
  networking.networkmanager.settings.connectivity = {
    uri = "";
    interval = 0;
  };

  services.geoclue2.enable = false;
}
