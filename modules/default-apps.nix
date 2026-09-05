{ config, pkgs, lib, ... }:

{
  environment.systemPackages = with pkgs; [
    libreoffice-qt6
  ];

  # GIO picks the terminal from here for "Open Terminal" style actions.
  environment.etc."xdg/xdg-terminals.list".text = ''
    org.kde.konsole.desktop
  '';

  # System-level fallbacks. Per the XDG spec these are only consulted for a
  # mimetype the user's own ~/.config/mimeapps.list doesn't already claim,
  # so any "Open With" choice you make later still wins over this.
  #
  # One mimetype=desktopfile pair per line. The semicolon only separates
  # multiple candidates for the SAME key — it does not chain separate pairs,
  # and parsers match by scanning for a line starting with "mimetype=", so
  # cramming several onto one line silently hides all but the first.
  environment.etc."xdg/mimeapps.list".text =
    let
      gwenviewMimes = [
        "image/avif" "image/gif" "image/heif" "image/jpeg"
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
      okularMimes = [
        "application/pdf" "application/x-pdf" "image/vnd.djvu" "application/epub+zip"
        "application/x-fictionbook+xml" "application/x-mobipocket-ebook"
        "image/x-portable-document" "application/x-cbr" "application/x-cbz"
        "application/x-cbt" "application/x-cb7" "application/postscript"
      ];
      vlcMimes = [
        "video/mp4" "video/x-matroska" "video/webm" "video/x-msvideo"
        "video/quicktime" "video/mpeg" "video/x-ms-wmv" "video/x-flv"
        "video/3gpp" "video/ogg" "video/x-theora+ogg" "video/x-ogm+ogg"
        "application/x-matroska" "application/vnd.rn-realmedia"
      ];
      elisaMimes = [
        "audio/mpeg" "audio/flac" "audio/x-flac" "audio/ogg" "audio/x-vorbis+ogg"
        "audio/opus" "audio/x-opus+ogg" "audio/mp4" "audio/aac" "audio/x-wav"
        "audio/wav" "audio/x-ms-wma" "audio/x-aiff" "audio/x-musepack"
      ];
      kateMimes = [
        "text/plain" "text/markdown" "text/x-csrc" "text/x-c++src" "text/x-chdr"
        "text/x-c++hdr" "text/x-python" "text/x-java" "text/x-shellscript"
        "text/x-nix" "text/css" "text/html" "text/xml" "application/json"
        "application/x-yaml" "application/toml" "application/javascript"
        "application/x-shellscript" "text/x-log"
      ];
      line = desktop: mime: "${mime}=${desktop}";
    in
    ''
      [Default Applications]
      inode/directory=org.kde.dolphin.desktop
      ${lib.concatMapStringsSep "\n" (line "org.kde.gwenview.desktop") gwenviewMimes}
      ${lib.concatMapStringsSep "\n" (line "org.kde.ark.desktop") arkMimes}
      ${lib.concatMapStringsSep "\n" (line "org.kde.okular.desktop") okularMimes}
      ${lib.concatMapStringsSep "\n" (line "vlc.desktop") vlcMimes}
      ${lib.concatMapStringsSep "\n" (line "org.kde.elisa.desktop") elisaMimes}
      ${lib.concatMapStringsSep "\n" (line "org.kde.kate.desktop") kateMimes}
    '';
}
