# nexoniarz-config-nixos

My personal NixOS system configuration.

## Overview

- **OS:** NixOS 26.05 (unstable channel)
- **Desktop:** KDE Plasma 6 on Wayland (KWin), SDDM
- **Bootloader:** Limine
- **Terminal:** Konsole
- **Shell:** Zsh
- **Audio:** PipeWire
- **GPU:** Radeon Vega 8 iGPU for the desktop, NVIDIA RTX 3060 Ti (open kernel modules) via PRIME offload for games and LLMs

## Layout

| File | Contents |
|---|---|
| `configuration.nix` | Imports only |
| `modules/boot.nix` | Limine, kernel, zram/swap |
| `modules/networking.nix` | NetworkManager, firewall, DNS-over-TLS, MAC randomization |
| `modules/locale.nix` | Timezone, locale, console keymap |
| `modules/nix-settings.nix` | Nix features, GC, unfree |
| `modules/security.nix` | sysctl hardening, sudo, firejail, GnuPG, polkit |
| `modules/hardware.nix` | GPU, tablet, Bluetooth, I2C, RTL-SDR, OpenRGB, printing |
| `modules/audio.nix` | PipeWire |
| `modules/desktop.nix` | Plasma, SDDM, fonts, theming |
| `modules/users.nix` | Account, shell, Steam, Flatpak |
| `modules/apps.nix` | Installed packages, nix-ld |
| `modules/default-apps.nix` | MIME associations |
| `modules/scripts.nix` | Custom scripts in `modules/scripts/` |
| `modules/fastfetch.nix` | Installs `configs/fastfetch/config.jsonc` system-wide |
| `modules/firefox.nix` | Firefox, with prefs from `configs/firefox/prefs.js` (reapplied each start, not locked) |
| `configs/` | Plain app config files (Firefox prefs, fastfetch) used by the modules |

## NexoPass

`nexopass` (in `modules/scripts/`) derives site passwords from a master with Argon2id, so no password is ever stored. You can have several accounts, each with its own master and an encrypted site list (current versions plus an archive of old ones) in `~/.local/share/nexopass/accounts/`. One app password or PIN unlocks them all; a master is only typed to create or recover an account.

Passwords of 5-15 words or 12-64 characters, "did you mean" for typos, "stay unlocked" for a few minutes (kernel keyring), encrypted export/import shared with the NexoPass Android app, and `nexopass settings`. Run `nexopass help` for everything else. Apache License 2.0.

---

*Made by **Nexoniarz***
