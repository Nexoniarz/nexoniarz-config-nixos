{ config, pkgs, ... }:

{
  # System-wide config; fastfetch searches /etc/xdg/fastfetch/ after
  # ~/.config/fastfetch/, so a user config there would still win.
  environment.etc."xdg/fastfetch/config.jsonc".source = ../configs/fastfetch/config.jsonc;
}
