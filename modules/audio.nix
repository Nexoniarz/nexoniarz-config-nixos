{ config, pkgs, ... }:

{
  security.rtkit.enable = true;
  services.pulseaudio.enable = false;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;

    # Bluetooth headphones are playback-only here (mic comes from the USB
    # codec). Disable HSP/HFP so they never drop to 8/16 kHz mono call mode.
    wireplumber.extraConfig."11-bluetooth-policy" = {
      "wireplumber.settings" = {
        "bluetooth.autoswitch-to-headset-profile" = false;
      };
      "monitor.bluez.properties" = {
        # PC only sends audio. Allowing a2dp_sink lets the Monitor II (which
        # also advertises an A2DP source) connect backwards as "audio gateway".
        "bluez5.roles" = [ "a2dp_source" ];
      };
    };
  };
}
