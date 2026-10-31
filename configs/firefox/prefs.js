// Nexoniarz's Firefox prefs (Firefox 157, "Nova" design)
//
// Loaded by NixOS (modules/firefox.nix) into Firefox's autoconfig. pref()
// sets the value on every Firefox start but doesn't lock it: you can still
// change things in Settings/about:config, they just reset on next start.
// To change a setting permanently, edit it here and nixos-rebuild.
// To stop managing a setting, delete its line (Firefox then keeps
// whatever value it last had).
//
// GPU video decoding also needs env vars set in modules/hardware.nix:
//   LIBVA_DRIVER_NAME=nvidia  NVD_BACKEND=direct  MOZ_DISABLE_RDD_SANDBOX=1

/*** PRIVACY: tracking & fingerprinting ***/

// Strict Enhanced Tracking Protection: blocks trackers, cryptominers and
// known fingerprinters, isolates cookies per site (Total Cookie Protection),
// strips tracking parameters from URLs, and turns on fingerprintingProtection
// (randomized canvas, fewer exposed hardware details).
// If a site breaks: click the shield in the address bar and turn it off
// for that site only.
pref("browser.contentblocking.category", "strict");

// Fingerprinting protection at full strength: everything resistFingerprinting
// does (a Windows user agent and platform that agree, UTC time, a fixed core
// count, the bundled font list, no precise GPU name, canvas noise...), but
// switched on through fingerprintingProtection, because only that one takes
// exceptions. The one exception: prefers-color-scheme isn't forced to light,
// so sites still get dark mode.
// To check it worked: coveryourtracks.eff.org should show Windows in both
// User Agent and Platform, and timezone UTC.
pref("privacy.resistFingerprinting", false);
pref("privacy.fingerprintingProtection", true);
pref("privacy.fingerprintingProtection.pbmode", true);
pref("privacy.fingerprintingProtection.overrides", "+AllTargets,-CSSPrefersColorScheme");

// Ask sites for English pages the way most English-speaking browsers do
// (en-US, en), so the language header doesn't stand out. en-GB would be
// rarer, and rarer is what gets you tracked.
pref("intl.accept_languages", "en-US, en");
pref("privacy.spoof_english", 2);

// Sites only see base system fonts, not the ones installed on top
// (the Microsoft core fonts made the font list 1 in 9,481).
pref("layout.css.font-visibility.standard", 1);
pref("layout.css.font-visibility.trackingprotection", 1);
pref("layout.css.font-visibility.private", 1);
pref("layout.css.font-visibility.resistFingerprinting", 1);

// WebGPU tells sites about the graphics card in detail. Off breaks some
// sites (3D, AI demos, some games); uncomment to turn it off.
// pref("dom.webgpu.enabled", false);

// First-party isolation stays ON. Every existing cookie in this profile was
// saved with a first-party tag; turning this off makes Firefox ignore them
// all (logged out everywhere). Works alongside Strict mode.
pref("privacy.firstparty.isolate", true);

// Cross-site requests only send the origin (https://site.com/), not the
// full page URL you came from.
pref("network.http.referer.XOriginTrimmingPolicy", 2);

// Tell sites not to sell/share your data (legally binding in some places).
pref("privacy.globalprivacycontrol.enabled", true);

// No WebRTC: stops IP leaks. Web video calls (Meet, Discord in-browser)
// need this set to true.
pref("media.peerconnection.enabled", false);

/*** PRIVACY: Mozilla data collection ***/

pref("datareporting.healthreport.uploadEnabled", false);
pref("datareporting.policy.dataSubmissionEnabled", false);
pref("datareporting.usage.uploadEnabled", false);
pref("toolkit.telemetry.enabled", false);
pref("toolkit.telemetry.unified", false);
pref("app.shield.optoutstudies.enabled", false);
pref("app.normandy.enabled", false);
pref("nimbus.rollouts.enabled", false);
pref("browser.discovery.enabled", false);

// Firefox Suggest launched in Poland with Firefox 157; it adds sponsored
// results to the address bar.
pref("browser.urlbar.quicksuggest.enabled", false);
pref("browser.urlbar.suggest.quicksuggest.sponsored", false);
pref("browser.urlbar.suggest.quicksuggest.nonsponsored", false);
pref("browser.newtabpage.activity-stream.showSponsored", false);
pref("browser.newtabpage.activity-stream.showSponsoredTopSites", false);

/*** SECURITY ***/

// HTTPS-Only: upgrade every site to HTTPS and warn before loading plain
// HTTP. Was enabled once, but it's off now.
pref("dom.security.https_only_mode", true);

// Safe Browsing back on for malware/phishing. It checks a local list and
// only sends a partial hash when a URL matches, never your history.
// The remote download check (which uploads file metadata to Google) stays off.
pref("browser.safebrowsing.malware.enabled", true);
pref("browser.safebrowsing.phishing.enabled", true);
pref("browser.safebrowsing.downloads.enabled", true);
pref("browser.safebrowsing.downloads.remote.enabled", false);

/*** NETWORK ***/

// DNS: use the system resolver (systemd-resolved with DNS-over-TLS) and
// never let Firefox switch itself to its own DNS-over-HTTPS provider.
pref("network.trr.mode", 5);

// No preloading pages or DNS you didn't ask for.
pref("network.dns.disablePrefetch", true);
pref("network.prefetch-next", false);
pref("network.http.speculative-parallel-limit", 0);
pref("browser.urlbar.speculativeConnect.enabled", false);
pref("network.captive-portal-service.enabled", false);
pref("network.connectivity-service.enabled", false);

/*** GPU VIDEO DECODING (RTX 3060 Ti, nvidia-vaapi-driver) ***/

// Firefox blocklists VA-API on NVIDIA; force it on. The 3060 Ti decodes
// H.264, VP9 and AV1 in hardware. (media.ffmpeg.vaapi.enabled is gone
// since Firefox 137; this pref replaced it.)
pref("media.hardware-video-decoding.force-enabled", true);
pref("media.rdd-ffmpeg.enabled", true);
pref("gfx.webrender.all", true);

/*** LOOK & FEEL ***/

// Compact mode (back in Firefox 157): thinner tabs and toolbars.
// Switch back via ☰ > More tools > Customize toolbar > Density.
pref("browser.compactmode.show", true);
pref("browser.uidensity", 1);

// Smoother, momentum-based scrolling, nicer at 240 Hz.
pref("general.smoothScroll.msdPhysics.enabled", true);

// Middle-click on a page to autoscroll (like on Windows).
pref("general.autoScroll", true);

// Closing the last tab doesn't close the window.
pref("browser.tabs.closeWindowWithLastTab", false);

// Show the full URL including https:// so you always see what site you're on.
pref("browser.urlbar.trimHttps", false);
pref("browser.urlbar.trimURLs", false);

// No "proceed with caution" page every time you open about:config.
pref("browser.aboutConfig.showWarning", false);
