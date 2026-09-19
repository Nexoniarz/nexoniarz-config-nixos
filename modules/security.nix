{ config, pkgs, ... }:

{
  security.polkit.enable = true;

  security.sudo.extraConfig = ''
    Defaults pwfeedback
  '';

  programs.firejail.enable = true;

  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
    pinentryPackage = pkgs.pinentry-rofi;
  };

  boot.kernel.sysctl = {
    "kernel.kptr_restrict" = 2;
    "kernel.dmesg_restrict" = 1;
    "net.ipv4.conf.all.rp_filter" = 1;
    "net.ipv4.conf.default.rp_filter" = 1;
    "net.ipv4.conf.all.accept_redirects" = false;
    "net.ipv4.conf.default.accept_redirects" = false;
    "net.ipv6.conf.all.accept_redirects" = false;
    "net.ipv6.conf.default.accept_redirects" = false;
    "net.ipv4.conf.all.send_redirects" = false;
    "net.ipv4.conf.default.send_redirects" = false;
    # Only bites ad-hoc `gdb -p <pid>` on a non-child process.
    "kernel.yama.ptrace_scope" = 1;
    "net.ipv4.tcp_timestamps" = 0;
  };

  systemd.coredump.enable = false;
  security.protectKernelImage = true;

  services.geoclue2.enable = false;
}
