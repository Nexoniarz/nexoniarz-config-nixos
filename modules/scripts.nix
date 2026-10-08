{ config, pkgs, ... }:

let
  vaultToggle = pkgs.writeShellScriptBin "vault-toggle" (builtins.readFile ./scripts/vault-toggle.sh);
  stripMetadata = pkgs.writeShellScriptBin "strip-metadata" (builtins.readFile ./scripts/strip-metadata.sh);
  nexopass = pkgs.writeShellApplication {
    name = "nexopass";
    runtimeInputs = with pkgs; [ libargon2 gnupg wl-clipboard keyutils coreutils gnused ];
    runtimeEnv.NEXOPASS_WORDLIST = "${./scripts/eff_large_wordlist.txt}";
    text = builtins.readFile ./scripts/nexopass.sh;
  };
in
{
  environment.systemPackages = with pkgs; [
    gocryptfs
    exiftool
    vaultToggle
    stripMetadata
    nexopass
  ];
}
