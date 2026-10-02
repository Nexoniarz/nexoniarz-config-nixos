{ config, pkgs, ... }:

{
  programs.firefox = {
    enable = true;
    # Not locked: values are reapplied on every Firefox start, but can be
    # changed in the UI for the current session. (Read as text: the module
    # doesn't copy autoConfigFiles paths into the store.)
    autoConfig = builtins.readFile ../configs/firefox/prefs.js;
  };
}
