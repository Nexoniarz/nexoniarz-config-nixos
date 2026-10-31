{ config, pkgs, ... }:

let
  # Firefox's own font setup: every system font except the Microsoft core
  # fonts. Sites measure which fonts are installed to fingerprint you, and
  # Comic Sans, Impact, Georgia, Verdana... made that list 1 in 9,000.
  # Only Firefox is affected: other apps still have corefonts. In Firefox,
  # Arial, Times New Roman and Courier New render as Liberation (same
  # letter widths), the rest fall back to Noto.
  firefoxFonts = pkgs.writeText "firefox-fonts.conf" ''
    <?xml version="1.0"?>
    <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
    <fontconfig>
      <include ignore_missing="no">/etc/fonts/fonts.conf</include>
      <selectfont>
        <rejectfont>
          <glob>${pkgs.corefonts}/*</glob>
        </rejectfont>
      </selectfont>
    </fontconfig>
  '';
in
{
  programs.firefox = {
    enable = true;
    # The wrapper sets FONTCONFIG_FILE when Firefox starts. (overrideAttrs
    # keeps the package overridable, so the autoConfig below still applies.)
    package = pkgs.firefox.overrideAttrs (old: {
      makeWrapperArgs = old.makeWrapperArgs ++ [ "--set" "FONTCONFIG_FILE" "${firefoxFonts}" ];
    });
    # Not locked: values are reapplied on every Firefox start, but can be
    # changed in the UI for the current session. (Read as text: the module
    # doesn't copy autoConfigFiles paths into the store.)
    autoConfig = builtins.readFile ../configs/firefox/prefs.js;
  };
}
