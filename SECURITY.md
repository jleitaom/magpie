# Security

## What the app can access

- **One optional permission.** Quick Save asks once to control Safari (Automation), only to read the
  address and title of Safari's front tab when you press its shortcut. Say no and Quick Save uses the
  clipboard instead. Magpie doesn't ask for Accessibility, screen recording, contacts or anything else.
  The Quick Save shortcut uses the system's hot key service, which needs no permission.
- **Screen Recording, only for screenshots.** ⌃⌥S runs macOS's own screenshot tool to save the area
  you select. macOS asks for Screen Recording permission the first time. The picture stays in your
  library, and its text is read on your Mac with Apple's Vision. Turn the shortcut off in Settings.
- **Network: link previews only.** When you save a link, Magpie asks Apple's LinkPresentation
  framework to fetch that page's title, picture and site name, which is the same thing Messages
  does for a link. It also downloads the page once to read a video's length, a product's price or
  an article's length. For Vimeo links it asks Vimeo's public oEmbed address instead. These
  requests go to the site you saved and nowhere else. Magpie has no server and no analytics.
- **Dock drops.** So that links and files can be dropped on its Dock icon, Magpie tells macOS it can
  open web links, pictures and files, at the lowest rank. It never becomes the default app or browser
  for any of them.
- **No data collection.** Your library is stored locally in
  `~/Library/Application Support/Magpie/`. There is no account, and nothing is uploaded.

## Reporting a vulnerability

Please don't open a public issue. Use GitHub's
[private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability)
on this repository (Security tab → Report a vulnerability).
