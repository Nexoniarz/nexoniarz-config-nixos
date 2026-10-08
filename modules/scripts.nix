{ config, pkgs, lib, ... }:

let
  vaultToggle = pkgs.writeShellScriptBin "vault-toggle" (builtins.readFile ./scripts/vault-toggle.sh);
  stripMetadata = pkgs.writeShellScriptBin "strip-metadata" (builtins.readFile ./scripts/strip-metadata.sh);

  nexopass = pkgs.writeShellApplication {
    name = "nexopass";
    runtimeInputs = with pkgs; [ libargon2 gnupg wl-clipboard keyutils coreutils gnused ];
    runtimeEnv.NEXOPASS_WORDLIST = "${./scripts/eff_large_wordlist.txt}";
    text = builtins.readFile ./scripts/nexopass.sh;
  };

  # NexoPass window (github.com/Nexoniarz/NexoPass). Shares accounts, site
  # lists and the app password with the nexopass command above.
  nexopassGuiVersion = "1.3.1";
  nexopassGuiJar = pkgs.fetchurl {
    url = "https://github.com/Nexoniarz/NexoPass/releases/download/v${nexopassGuiVersion}/NexoPass-linux-x64-${nexopassGuiVersion}.jar";
    hash = "sha256-WeUixuz+aLPsMDj+a0Gs09gfikMYYCf8uuZIN89CqVo=";
  };
  nexopassGuiLibs = with pkgs; [ libGL libx11 libxext libxrender libxtst libxi libxrandr libxcursor fontconfig freetype ];
  nexopassGuiDesktop = pkgs.makeDesktopItem {
    name = "nexopass";
    desktopName = "NexoPass";
    comment = "Passwords derived from a master";
    exec = "nexopass-gui";
    icon = "nexopass";
    categories = [ "Utility" "Security" ];
  };
  nexopassGui = pkgs.runCommand "nexopass-gui-${nexopassGuiVersion}" { nativeBuildInputs = [ pkgs.makeWrapper ]; } ''
    makeWrapper ${pkgs.jdk17}/bin/java $out/bin/nexopass-gui \
      --add-flags "-Xmx1g -jar ${nexopassGuiJar}" \
      --prefix LD_LIBRARY_PATH : /run/opengl-driver/lib:${lib.makeLibraryPath nexopassGuiLibs}
    install -Dm644 ${./scripts/nexopass.png} $out/share/icons/hicolor/512x512/apps/nexopass.png
    install -Dm644 ${nexopassGuiDesktop}/share/applications/nexopass.desktop $out/share/applications/nexopass.desktop
  '';
in
{
  environment.systemPackages = with pkgs; [
    gocryptfs
    exiftool
    vaultToggle
    stripMetadata
    nexopass
    nexopassGui
  ];
}
