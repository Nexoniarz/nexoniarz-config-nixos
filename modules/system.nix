{ config, lib, pkgs, ... }:

{
  # Bootloader & Kernel
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.configurationLimit = 5;
  boot.kernelPackages = pkgs.linuxPackages;
  boot.supportedFilesystems = [ "fuse" ];

  # Networking
  networking.hostName = "nixos";
  networking.networkmanager.enable = true;

  # Firewall Configuration
  networking.firewall = {
    enable = true;

    # Allow local ping diagnostic queries
    allowPing = true;

    allowedTCPPortRanges = [ { from = 1714; to = 1764; } ];
    allowedUDPPortRanges = [ { from = 1714; to = 1764; } ];
    allowedTCPPorts = [ 80 443 ];
    # allowedUDPPorts = [ ];
  };

  # Time zone and Internationalization
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

  # Console keymap
  console.keyMap = "pl2";

  # Sound and Audio (Pipewire)
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
        # Shows battery charge of connected devices on supported
        # Bluetooth adapters. Defaults to 'false'.
        Experimental = true;
        # When enabled other devices can connect faster to us, however
        # the tradeoff is increased power consumption. Defaults to
        # 'false'.
        FastConnectable = true;
      };
      Policy = {
        # Enable all controllers when they are found. This includes
        # adapters present on start as well as adapters that are plugged
        # in later on. Defaults to 'true'.
        AutoEnable = true;
      };
    };
  };

  services.blueman.enable = true;

  #Firejail
  programs.firejail = {
    enable = true;
  };

  #FUSE shit
  programs.fuse.userAllowOther = true;

  # Enable GnuPG Agent with GUI pinentry support
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
    pinentryPackage = pkgs.pinentry-rofi; # Reuses the Rofi theme, no extra toolkit
  };

  security.sudo.extraConfig = ''
    Defaults pwfeedback
  '';

  # Printing services
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

  # --- Loader shim for running non-Nix-packaged binaries (e.g. the official
  # Tor Browser bundle) that expect a standard FHS dynamic linker/libraries. ---
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

  # --- Hardening: swap, kernel sysctls, DNS, MAC randomization ---

  # Swap: replace disk swap with compressed in-RAM swap. Nothing sensitive
  # (decrypted vault contents, browser memory, GPG session data) ever gets
  # written to disk in plaintext via swap. Also faster than disk swap under
  # memory pressure.
  zramSwap.enable = true;
  swapDevices = lib.mkForce [ ];
  # systemd's gpt-auto-generator independently re-discovers and activates any
  # GPT partition tagged as Linux swap, regardless of the swapDevices list
  # above — this disables that auto-discovery so the old disk swap partition
  # actually stays off. Doesn't affect /, /home, /nix, /boot: those are
  # already explicitly declared in hardware-configuration.nix, not relying on
  # gpt-auto. Takes effect on next reboot.
  boot.kernelParams = [ "systemd.gpt_auto=0" ];

  # Kernel/system hardening sysctls
  boot.kernel.sysctl = {
    # Hide kernel pointers from unprivileged users (blocks a common
    # local info-leak used in exploit chains).
    "kernel.kptr_restrict" = 2;
    # Restrict dmesg access to root.
    "kernel.dmesg_restrict" = 1;
    # Reverse-path filtering: drop packets with spoofed source addresses.
    "net.ipv4.conf.all.rp_filter" = 1;
    "net.ipv4.conf.default.rp_filter" = 1;
    # Don't accept/send ICMP redirects (blocks a classic local MITM trick).
    "net.ipv4.conf.all.accept_redirects" = false;
    "net.ipv4.conf.default.accept_redirects" = false;
    "net.ipv6.conf.all.accept_redirects" = false;
    "net.ipv6.conf.default.accept_redirects" = false;
    "net.ipv4.conf.all.send_redirects" = false;
    "net.ipv4.conf.default.send_redirects" = false;
  };

  # Crash dumps can contain decrypted memory contents, passwords, keys —
  # never write them to disk.
  systemd.coredump.enable = false;

  # Blocks kexec-based kernel image tampering.
  security.protectKernelImage = true;

  # DNS-over-TLS system-wide (Tor Browser already routes its own DNS
  # through Tor, so this only affects everything else). Cloudflare + Quad9
  # both support DoT; "allow-downgrade" avoids hard failures on domains
  # with broken DNSSEC deployment.
  networking.nameservers = [ "1.1.1.1#cloudflare-dns.com" "9.9.9.9#dns.quad9.net" ];
  services.resolved = {
    enable = true;
    settings.Resolve = {
      DNSSEC = "allow-downgrade";
      DNSOverTLS = "true";
    };
  };
  networking.networkmanager.dns = "systemd-resolved";

  # MAC address randomization.
  # WiFi: fully random per connection (you're on ethernet now, but this
  # protects you if you ever use WiFi).
  # Ethernet: "stable" — a consistent pseudonymous MAC per connection
  # profile rather than your real hardware MAC, so it won't break any
  # static DHCP reservation/MAC filtering on your OpenWRT router, while
  # still not exposing your real hardware identity.
  networking.networkmanager.wifi.macAddress = "random";
  networking.networkmanager.wifi.scanRandMacAddress = true;
  networking.networkmanager.ethernet.macAddress = "stable";
}
