#!/usr/bin/env bash

CIPHER_DIR="/run/media/nexoniarz/Lukas/.vault_cipher"
MOUNT_DIR="$HOME/Vault"

mkdir -p "$CIPHER_DIR" "$MOUNT_DIR"

if mountpoint -q "$MOUNT_DIR"; then
    echo "[*] Synchronizing buffers and unmounting Vault..."
    sync

    if fusermount -u "$MOUNT_DIR"; then
        echo "[+] Vault unmounted successfully."
    else
        echo "[!] Failed to unmount Vault. Check if any application is using $MOUNT_DIR"
        exit 1
    fi
else
    echo "[*] Mounting Vault..."
    if [ ! -f "$CIPHER_DIR/gocryptfs.conf" ]; then
        echo "[!] Container not initialized. Initializing new gocryptfs vault..."
        gocryptfs -init "$CIPHER_DIR" || exit 1
    fi
    if gocryptfs -allow_other "$CIPHER_DIR" "$MOUNT_DIR"; then
        echo "[+] Vault mounted successfully at $MOUNT_DIR"
    else
        echo "[!] Mount failed."
        exit 1
    fi
fi
