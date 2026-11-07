# Security

## What the app can access

- **No special permissions.** Magpie doesn't ask for Accessibility, screen recording, contacts or
  anything else. It reads only what you paste or drop into its window.
- **Network: link previews only.** When you save a link, Magpie asks Apple's LinkPresentation
  framework to fetch that page's title, picture and site name, which is the same thing Messages
  does for a link. That request goes to the site you saved and nowhere else. Magpie has no server
  and no analytics.
- **No data collection.** Your library is stored locally in
  `~/Library/Application Support/Magpie/`. There is no account, and nothing is uploaded.

## Reporting a vulnerability

Please don't open a public issue. Use GitHub's
[private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability)
on this repository (Security tab → Report a vulnerability).
