# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- **Copy a link.** Select a card and press ⌘C (Edit → Copy) to copy its link, or a note's text. Right-click the link in the details panel, or the big card in Sort Inbox, for Open and Copy Link
- **Videos, products and places are recognized.** A saved video shows its length ("13 min"), a shop page its price ("€189" or "189 €", in your Mac's format), and an article its read time. Read from the page's own data (schema.org and meta tags), Vimeo's oEmbed for Vimeo links, and Apple Maps and Google Maps links become places. Recipe pages are noted for the coming Cook pile
- **Sort Inbox** (⌃⌘3, or the third button in the view switcher, or **Start sorting** in the Inbox): your Inbox one block at a time, big, with a suggested collection. Press **M** to move it there, **D** to mark it done, **→** to skip it (it goes to the back of the queue), **⌫** to delete it, or click any collection. A progress bar shows how many are sorted and how many are left. The suggestion comes from the site and kind (a YouTube link goes to Watch later, a shop to Shopping), else from where that site's blocks went last
- **Inbox zero and a daily streak.** Sorting your last Inbox block shows "Inbox zero." with how many you sorted, kept, marked done and deleted. Each day you reach Inbox zero adds one to your streak, shown next to the window buttons with a ring that fills over a week. A day you saved nothing doesn't break it. Click the streak to start sorting
- **View → Gallery** (⌃⌘1) and **View → Sort Inbox** (⌃⌘3)
- **Nest and reorder collections.** In the Collections panel (⌘K), drag a collection onto another to put it inside, or onto the top or bottom edge of a row to reorder. Nested collections are indented under their parent
- **Rename, move and delete collections** from the right-click menu in the Collections panel or on a top bar tab (a top bar tab is renamed right in the tab, with the name selected so you can type over it), or from the new **Collection** menu: Rename (⇧⌘R), Move Up (⌥⌘↑), Move Down (⌥⌘↓), Move Into, Move to Top Level, and Delete (⇧⌘⌫). Deleting asks first, says how many blocks go back to the Inbox, and never deletes a block
- **View → Appearance** switches between Dark, Light and Match my Mac without opening Settings, and **⌃⌘T** flips between Dark and Light

### Fixed

- YouTube videos show the video's title, not the channel's name, and Vimeo videos their real title too
- Google Maps and Apple Maps links are named after the place ("Torre de Belém") and show the mini map instead of a generic picture
- Pages that forward you with a redirect in their HTML (like inkandswitch.com) get their title, picture and read time
- Saving a link you already have refreshes its title, picture, length and price

- The Collections panel and the + New block menu have a solid background, so the cards behind them no longer show through the text

## [0.1.0] - 2026-11-07

### Added

- Paste (⇧⌘V), drop or add (⌘O) a link, image, file or text to save it as a **Block**. Links get their title, picture and site name filled in on their own
- Make a note (⌘N) or a checklist (⇧⌘N) by hand
- **Gallery** of image-first cards, each tinted with its picture's color
- **Details panel**: click a Block to see its link, note, collection and when you saved it, then open or delete it
- **Collections**: create them, move Blocks into them, and pin up to 5 to the top bar. "N more" opens a panel with the rest
- New Blocks land in the **Inbox**, with a count in the top bar
- Dark by default, with Light or Match my Mac in Settings
- App icon: an iridescent magpie feather
