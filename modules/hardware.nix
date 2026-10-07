{ config, lib, pkgs, ... }:

{
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  # PRIME offload: the 5700G's Radeon Vega 8 iGPU runs the desktop (monitors
  # plugged into the motherboard), the RTX 3060 Ti only wakes up for games
  # and LLMs. Needs in the BIOS: Integrated Graphics = Forced/Enabled and
  # primary display = IGD/iGPU. KWin then picks the iGPU as the boot VGA.
  # amdgpu loads by itself; hardware.graphics provides Mesa (RADV, radeonsi).
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    modesetting.enable = true;
    open = true;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;

    prime = {
      offload.enable = true;
      offload.enableOffloadCmd = true;   # `nvidia-offload <app>` runs it on the RTX
      amdgpuBusId = "PCI:7:0:0";
      nvidiaBusId = "PCI:1:0:0";
    };
  };

  # Everything Steam launches (games, Proton/DXVK) renders on the RTX. Same
  # variables nvidia-offload sets; CUDA apps (LM Studio) don't need them.
  programs.steam.package = pkgs.steam.override {
    extraEnv = {
      __NV_PRIME_RENDER_OFFLOAD = "1";
      __NV_PRIME_RENDER_OFFLOAD_PROVIDER = "NVIDIA-G0";
      __GLX_VENDOR_LIBRARY_NAME = "nvidia";
      __VK_LAYER_NV_optimus = "NVIDIA_only";
    };
  };

  environment.systemPackages = with pkgs; [
    vulkan-tools   # vulkaninfo --summary: check both GPUs are visible
    amdgpu_top     # usage monitor for the iGPU
  ];

  # Firefox video decoding runs on the iGPU through Mesa's radeonsi VA-API
  # driver, which libva finds on its own: no env vars, and Firefox's decoder
  # (RDD) sandbox stays on. Vega 8 decodes H.264, HEVC and VP9; AV1 falls
  # back to the CPU.

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
