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
      # Taken from Okular's own .desktop file, same as the other two lists.
      okularMimes = [
        "application/pdf" "application/x-pdf" "image/vnd.djvu" "application/epub+zip"
        "application/x-fictionbook+xml" "application/x-mobipocket-ebook"
        "image/x-portable-document" "application/x-cbr" "application/x-cbz"
        "application/x-cbt" "application/x-cb7" "application/postscript"
      ];
      line = desktop: mime: "${mime}=${desktop}";
    in
    ''
      [Default Applications]
      ${lib.concatMapStringsSep "\n" (line "org.kde.gwenview.desktop") gwenviewMimes}
      ${lib.concatMapStringsSep "\n" (line "org.kde.ark.desktop") arkMimes}
      ${lib.concatMapStringsSep "\n" (line "org.kde.okular.desktop") okularMimes}
    '';
}
