{ config, pkgs, lib, ... }:

{
  environment.systemPackages = with pkgs; [
    libreoffice-qt6 # Qt6-styled build — fits the Qt theming work in theme.nix
                     # better than the default GTK3 build would.
  ];

  # System-level fallback defaults (XDG spec: only consulted for a
  # mimetype the user's own ~/.config/mimeapps.list doesn't already
  # claim), so a future "Open With" choice always wins over this without
  # needing to touch it. Mimetype lists taken directly from Gwenview's
  # and Ark's own .desktop files, not guessed.
  #
  # One mimetype=desktopfile pair per line: the semicolon only separates
  # multiple desktop-file candidates for the SAME key, it doesn't chain
  # separate mimetype=value pairs on one line — mimeapps.list parsers
  # (verified against xdg-utils' own xdg-mime script) match by scanning
  # for a line that STARTS WITH "mimetype=", so cramming several pairs
  # onto one semicolon-joined line silently hides every key after the
  # first from ever being found.
  environment.etc."xdg/mimeapps.list".text =
    let
      gwenviewMimes = [
        "inode/directory" "image/avif" "image/gif" "image/heif" "image/jpeg"
        "image/jxl" "image/png" "image/bmp" "image/x-eps" "image/x-icns"
        "image/x-ico" "image/x-portable-bitmap" "image/x-portable-graymap"
        "image/x-portable-pixmap" "image/x-xbitmap" "image/x-xpixmap"
        "image/tiff" "image/x-psd" "image/x-webp" "image/webp" "image/x-tga"
        "image/x-xcf" "image/openraster" "image/svg+xml" "image/svg+xml-compressed"
      ];
      arkMimes = [
        "application/x-cd-image" "application/x-bcpio" "application/x-cpio"
        "application/x-cpio-compressed" "application/x-rpm" "application/x-compress"
        "application/gzip" "application/x-bzip" "application/x-bzip2"
        "application/x-lzma" "application/x-xz" "application/zstd" "application/x-lz4"
        "application/x-source-rpm" "application/vnd.debian.binary-package"
        "application/vnd.ms-cab-compressed" "application/x-archive" "application/x-tar"
        "application/x-compressed-tar" "application/x-bzip-compressed-tar"
        "application/x-bzip2-compressed-tar" "application/x-tarz"
        "application/x-xz-compressed-tar" "application/x-lzma-compressed-tar"
        "application/x-7z-compressed" "application/vnd.rar" "application/zip"
        "application/x-java-archive" "application/x-arj"
      ];
      line = desktop: mime: "${mime}=${desktop}";
    in
    ''
      [Default Applications]
      ${lib.concatMapStringsSep "\n" (line "org.kde.gwenview.desktop") gwenviewMimes}
      ${lib.concatMapStringsSep "\n" (line "org.kde.ark.desktop") arkMimes}
    '';

  # Thunar's own "Open Terminal Here" custom action (Edit > Configure
  # Custom Actions) shipped pointing at `exo-open --launch
  # TerminalEmulator` — exo isn't installed on this system at all (no
  # XFCE session, so its helpers.rc mechanism has nothing to resolve
  # against), so the action silently did nothing. `f`, not `w`: only
  # creates this baseline for a fresh account — once it exists, further
  # edits made through Thunar's own UI (adding more custom actions) are
  # never overwritten by a rebuild.
  systemd.tmpfiles.rules = [
    "d /home/nexoniarz/.config/Thunar 0755 nexoniarz users -"
    ''f /home/nexoniarz/.config/Thunar/uca.xml 0644 nexoniarz users - <?xml version="1.0" encoding="UTF-8"?><actions><action><icon>utilities-terminal</icon><name>Open Terminal Here</name><submenu></submenu><unique-id>1788014825097143-1</unique-id><command>kitty --working-directory %f</command><description>Open a terminal in this folder</description><range></range><patterns>*</patterns><startup-notify/><directories/></action></actions>''
  ];
}
