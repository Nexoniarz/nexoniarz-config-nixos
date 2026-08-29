#!/usr/bin/env bash
# Removes a wallpaper by moving it to the freedesktop.org trash
# (~/.local/share/Trash), the same mechanism Thunar's own delete uses —
# so it shows up in Thunar's Trash and can be restored from there,
# instead of `rm` permanently destroying it with no way back.
set -euo pipefail

path="${1:?usage: wallpaper-delete <path>}"
[ -e "$path" ] || exit 0

trash_dir="$HOME/.local/share/Trash"
mkdir -p "$trash_dir/files" "$trash_dir/info"

name="$(basename "$path")"
dest="$trash_dir/files/$name"
info="$trash_dir/info/$name.trashinfo"
n=1
while [ -e "$dest" ] || [ -e "$info" ]; do
    dest="$trash_dir/files/${name}.$n"
    info="$trash_dir/info/${name}.$n.trashinfo"
    n=$((n + 1))
done

cat > "$info" <<EOF
[Trash Info]
Path=$path
DeletionDate=$(date +%Y-%m-%dT%H:%M:%S)
EOF

mv "$path" "$dest"
