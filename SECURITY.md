# Security

## What the app can access

- **One optional permission.** Quick Save asks once to control Safari (Automation), only to read the
  address and title of Safari's front tab when you press its shortcut. Say no and Quick Save uses the
  clipboard instead. Magpie doesn't ask for Accessibility, screen recording, contacts or anything else.
  The Quick Save shortcut uses the system's hot key service, which needs no permission.
- **Screen Recording, only for screenshots.** ⌃⌥S runs macOS's own screenshot tool to save the area
  you select. macOS asks for Screen Recording permission the first time. The picture stays in your
  library, and its text is read on your Mac with Apple's Vision. Turn the shortcut off in Settings.
- **Network: link previews and update checks.** When you save a link, Magpie asks Apple's LinkPresentation
  framework to fetch that page's title, picture and site name, which is the same thing Messages
  does for a link. It also downloads the page once to read a video's length, a product's price or
  an article's length. For YouTube and Vimeo links it also asks that site's public oEmbed address for the video's real title. These
  requests go to the site you saved and nowhere else. Magpie has no server and no analytics.
- **Update checks.** Magpie also connects to GitHub to see whether there's a newer release (the
  `appcast.xml` attached to the latest release), using [Sparkle](https://sparkle-project.org).
  Sparkle asks before it checks on its own, it checks at most once a day, and you can turn it off
  in Settings → General → *Check for updates automatically*. The request carries Magpie's and
  Sparkle's version numbers and nothing else: no system profile, no identifiers.
- **Only web links and files open.** A page that forwards to another address is only followed to
  another web page, never to a file on your Mac. Opening a block only opens web links (in your
  browser) and files you saved (in their app); any other kind of address, for example one in an
  edited export, is refused.
- **Dock drops.** So that links and files can be dropped on its Dock icon, Magpie tells macOS it can
  open web links, pictures and files, at the lowest rank. It never becomes the default app or browser
  for any of them.
- **No data collection.** Your library is stored locally in
  `~/Library/Application Support/Magpie/`. There is no account, and nothing is uploaded.

## Verifying a download

Releases are built by GitHub Actions directly from the tagged source code. They are not notarized
by Apple (the project doesn't use a paid developer account), so you can verify them yourself:

```sh
# 1. Check the file was built by this repo's release workflow
gh attestation verify Magpie-1.0.0.dmg --repo jleitaom/magpie

# 2. Or compare the checksum with SHA256SUMS.txt from the release page
shasum -a 256 Magpie-1.0.0.dmg
```

Or skip downloads entirely and build from source with `./build.sh`.

## Code signing

Releases are signed with the project's self-signed certificate, `Magpie Self-Signed`, so every
version has the same code identity and keeps the Safari and Screen Recording access you granted.
To check a downloaded app:

```sh
codesign -dr - /Applications/Magpie.app
# designated => identifier "com.jleitaom.magpie" and certificate leaf = H"3c0d7df33d8eccb464d9ec0fd77e6a58958887a6"
```

If a release ever shows a different certificate hash, don't install it and report it as below.

Updates are checked twice before they're installed: Sparkle only accepts an archive signed with
the project's EdDSA key (its public half is `SUPublicEDKey` in `Info.plist`), and the new app
must be signed with the same certificate as the one you have.

The app is signed with the hardened runtime and two entitlements:

- `com.apple.security.automation.apple-events`, so Quick Save can ask Safari for its front tab.
  macOS still asks you before it allows it.
- `com.apple.security.cs.disable-library-validation`, so the hardened runtime can load
  `Sparkle.framework`, which is signed with the same self-signed certificate. That certificate
  has no Apple Team ID, and library validation requires one.

## Reporting a vulnerability

Please don't open a public issue. Use GitHub's
[private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability)
on this repository (Security tab → Report a vulnerability).
