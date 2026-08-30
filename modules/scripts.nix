{ config, pkgs, ... }:

let
  # Wrap external shell scripts into system executables
  vaultToggle = pkgs.writeShellScriptBin "vault-toggle" (builtins.readFile ./scripts/vault-toggle.sh);
  stripMetadata = pkgs.writeShellScriptBin "strip-metadata" (builtins.readFile ./scripts/strip-metadata.sh);
  brightnessCtl = pkgs.writeShellScriptBin "brightness-ctl" (builtins.readFile ./scripts/brightness-ctl.sh);
  showDesktopToggle = pkgs.writeShellScriptBin "show-desktop-toggle" (builtins.readFile ./scripts/show-desktop-toggle.sh);
  wallpaperSet = pkgs.writeShellScriptBin "wallpaper-set" (builtins.readFile ./scripts/wallpaper-set.sh);
  wallpaperDelete = pkgs.writeShellScriptBin "wallpaper-delete" (builtins.readFile ./scripts/wallpaper-delete.sh);
  wallpaperRestore = pkgs.writeShellScriptBin "wallpaper-restore" (builtins.readFile ./scripts/wallpaper-restore.sh);
  displaySet = pkgs.writeShellScriptBin "display-set" (builtins.readFile ./scripts/display-set.sh);
  hyprThemeSet = pkgs.writeShellScriptBin "hypr-theme-set" (builtins.readFile ./scripts/hypr-theme-set.sh);
  gtkThemeSet = pkgs.writeShellScriptBin "gtk-theme-set" (builtins.readFile ./scripts/gtk-theme-set.sh);
  qtThemeSet = pkgs.writeShellScriptBin "qt-theme-set" (builtins.readFile ./scripts/qt-theme-set.sh);
  kittyThemeSet = pkgs.writeShellScriptBin "kitty-theme-set" (builtins.readFile ./scripts/kitty-theme-set.sh);
  rofiThemeSet = pkgs.writeShellScriptBin "rofi-theme-set" (builtins.readFile ./scripts/rofi-theme-set.sh);
  listCursorThemes = pkgs.writeShellScriptBin "list-cursor-themes" (builtins.readFile ./scripts/list-cursor-themes.sh);
  cursorPreviewAll = pkgs.writeShellScriptBin "cursor-preview-all" (builtins.readFile ./scripts/cursor-preview-all.sh);
  cursorSet = pkgs.writeShellScriptBin "cursor-set" (builtins.readFile ./scripts/cursor-set.sh);
  screenshot = pkgs.writeShellScriptBin "screenshot" (builtins.readFile ./scripts/screenshot.sh);
  hotspotStart = pkgs.writeShellScriptBin "hotspot-start" (builtins.readFile ./scripts/hotspot-start.sh);
in
{
  # Install CLI dependencies required by the scripts
  environment.systemPackages = with pkgs; [
    gocryptfs
    exiftool
    jq
    vaultToggle
    stripMetadata
    brightnessCtl
    showDesktopToggle
    wallpaperSet
    wallpaperDelete
    wallpaperRestore
    displaySet
    hyprThemeSet
    gtkThemeSet
    qtThemeSet
    kittyThemeSet
    rofiThemeSet
    listCursorThemes
    cursorPreviewAll
    cursorSet
    screenshot
    hotspotStart
  ];
}