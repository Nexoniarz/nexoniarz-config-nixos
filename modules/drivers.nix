{ config, lib, pkgs, ... }:

{
  # Enable graphics driver support and 32-bit acceleration (for Steam/gaming)
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  #OpenTabletDriver
  hardware.opentabletdriver.enable = true;
  hardware.uinput.enable = true;
  boot.kernelModules = [ "uinput" "v4l2loopback" ];

  # Virtual webcam device so ffmpeg (fed by the GoPro's stream) can appear
  # as a normal camera to apps like Discord. exclusive_caps=1 is required
  # for Chromium/WebRTC-based apps to recognize it as a real capture device.
  boot.extraModulePackages = [ config.boot.kernelPackages.v4l2loopback ];
  boot.extraModprobeConfig = ''
    options v4l2loopback devices=1 video_nr=10 card_label="GoPro Webcam" exclusive_caps=1
    # PS4/PS5 controllers (e.g. DualSense) connect over Bluetooth then
    # immediately disconnect — a well-known Linux Bluetooth stack issue
    # where many adapters' Enhanced Retransmission Mode implementation is
    # broken. Disabling ERTM is the standard, widely-documented fix.
    options bluetooth disable_ertm=1
  '';

  # I2C bus, for DDC/CI monitor control (brightness) via ddcutil — this
  # machine has no laptop backlight, only external DisplayPort monitors.
  hardware.i2c.enable = true;

  # Load NVIDIA driver for X11 and Wayland
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    # Required settings
    modesetting.enable = true;

    # Enable NVIDIA Open GPU Kernel Modules (Turing architecture or newer)
    open = true;

    # Enable the NVIDIA settings menu
    nvidiaSettings = true;

    # Use the stable driver package matching current kernel
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };
}
