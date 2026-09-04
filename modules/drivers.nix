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
  boot.kernelModules = [ "uinput" ];

  boot.extraModprobeConfig = ''
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
