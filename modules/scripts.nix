{ config, pkgs, ... }:

let
  vaultToggle = pkgs.writeShellScriptBin "vault-toggle" (builtins.readFile ./scripts/vault-toggle.sh);
  stripMetadata = pkgs.writeShellScriptBin "strip-metadata" (builtins.readFile ./scripts/strip-metadata.sh);
in
{
  environment.systemPackages = with pkgs; [
    gocryptfs
    exiftool
    vaultToggle
    stripMetadata
  ];
}
