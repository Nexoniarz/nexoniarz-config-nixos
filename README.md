# nexoniarz-config-nixos

My personal NixOS system configuration.

## Overview

- **OS:** NixOS 26.05 (unstable channel)
- **Desktop:** KDE Plasma 6 on Wayland (KWin), SDDM
- **Bootloader:** Limine
- **Terminal:** Konsole
- **Shell:** Zsh
- **Audio:** PipeWire
- **GPU:** NVIDIA (open kernel modules)

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

---

*Made by **Nexoniarz***
