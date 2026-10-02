{ config, lib, pkgs, ... }:

{
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    modesetting.enable = true;
    open = true;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };

  # Hardware video decoding in Firefox via nvidia-vaapi-driver (installed by
  # hardware.nvidia.videoAcceleration). libva needs the driver named
  # explicitly; the "direct" backend is the working one on driver 525+.
  # Firefox's decoder (RDD) sandbox blocks the driver, so it's disabled:
  # trade-off accepted for GPU decode. Prefs live in the profile's user.js.
  environment.sessionVariables = {
    LIBVA_DRIVER_NAME = "nvidia";
    NVD_BACKEND = "direct";
    MOZ_DISABLE_RDD_SANDBOX = "1";
  };

  hardware.opentabletdriver.enable = true;
  hardware.uinput.enable = true;
  boot.kernelModules = [ "uinput" ];

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
  # Plasma ships its own Bluetooth UI (Bluedevil); blueman just duplicated it.

  boot.extraModprobeConfig = ''
    # DualSense/PS4 pads pair over Bluetooth then drop instantly; broken
    # ERTM in many adapters. Disabling it is the standard fix.
    options bluetooth disable_ertm=1
  '';

  # Blog V4 needs the rtlsdrblog fork of librtlsdr, which is what
  # pkgs.rtl-sdr already is here. Also blacklists the DVB-T drivers.
  hardware.rtl-sdr.enable = true;

  # For ddcutil — no laptop backlight here, only external DisplayPort.
  hardware.i2c.enable = true;

  services.hardware.openrgb = {
    enable = true;
    motherboard = "amd";
  };

  services.udev.extraRules = ''
    # OpenRGB
    SUBSYSTEM=="i2c-dev", GROUP="i2c", MODE="0660"
  '';

  services.printing.enable = true;
}
