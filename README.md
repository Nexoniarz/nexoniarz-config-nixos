# nexoniarz-config-nixos

My personal NixOS system configuration.

## Overview

- **OS:** NixOS 26.05 (unstable channel)
- **Desktop:** Budgie on Wayland (labwc), SDDM
- **Bootloader:** Limine
- **Terminal:** Konsole
- **Shell:** Zsh
- **Audio:** PipeWire
- **GPU:** NVIDIA (open kernel modules)

## Layout

| File | Contents |
|---|---|
| `configuration.nix` | Imports only |
| `modules/system.nix` | Boot, networking, locale, audio, hardening |
| `modules/drivers.nix` | GPU, tablet, I2C, RTL-SDR |
| `modules/desktop.nix` | Budgie, theming |
| `modules/users.nix` | Account, shell, Steam |
| `modules/apps.nix` | Installed packages |
| `modules/scripts.nix` | Custom scripts in `modules/scripts/` |
| `modules/default-apps.nix` | MIME associations |

---

*Made by **Nexoniarz***
