# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Removed

- **The Inbox zero streak** (#7): the "N-day streak" pill is gone from the top bar, and the Inbox zero screen no longer counts days in a row. Sort Inbox is still in the menu bar and on ⌃⌘3. Lucky Dip's daily dip streak stays

### Fixed

- **Cards keep their shape whatever the picture** (#6, #8): a very wide picture (like a shop's logo) no longer stretches its card over the cards beside it and past the window edge, and a tall picture (like a fashion photo) no longer covers the top of the card's text. The picture fills its space at the top of the card and is cropped to fit. Picture tiles in Choose Picture… are cropped the same way

## [1.1.0] - 2026-11-09

### Added

- **Choose a link's picture** (#2): right-click a block → **Choose Picture…** (⌥⌘P), or **Picture → Choose…** in its details. Magpie shows the pictures on the page (its share images, its product or article images, and the large pictures on it); click one to use it. The card's color follows, and saving the link again keeps the picture you chose. Exports remember it too

### Changed

- **Lucky Dip picks from your collections.** Choose **Pick from**: Everything, or any collection (with the ones inside it), and how much time you have. Piles (Read, Watch, Listen, Cook, Visit) are gone, along with the Pile menu and the Pile row in the details panel; the start button still says what you'll do ("Start watching", "Cook it", "Go there") (#3)

## [1.0.2] - 2026-11-09

### Fixed

- **Quick Save reads Chrome, Arc, Brave, Edge and other Chromium browsers,** not only Safari, so in them it saves the page you're on instead of whatever link you copied last. In Firefox, which doesn't let other apps read its tabs, the panel says it's using the clipboard (#5)
- Deleting, renaming or recoloring a tag in the Collections panel shows right away, without closing and reopening it (#4)

## [1.0.1] - 2026-11-08

### Security

- A web page that forwards to another address is only followed to another web page, never to a file on your Mac
- Blocks only open web links and files. Any other kind of address (for example from an edited export or a link file) is refused

## [1.0.0] - 2026-11-08

### Added

- **Install with Homebrew** (`brew trust jleitaom/tap`, then `brew install --cask jleitaom/tap/magpie`) or from a `.dmg`, and **update checks** through GitHub: Magpie asks before it checks on its own, and Settings → General has *Check for updates automatically* and **Check Now** (also Magpie → Check for Updates…)
- **One right-click menu for every block,** wherever it shows (Gallery, Journal, Sort Inbox, Lucky Dip, Rediscover): Open, Quick Look, Copy Link, Show Details, Move to (nested collections), Tags (tick or untick, or a new one), Pile, Archive and Delete, each with its shortcut
- **Helpful empty pages.** The first launch, an empty collection, tag, Archive, Expired, a search with no results, the "I have 20 minutes" filter and an empty Lucky Dip pile each say what's going on and what to do next
- **Settings in two tabs.** General: appearance, how long new collections keep their blocks, Rediscover's count on the Dock icon, and where your library lives (with Show in Finder and Export). Shortcuts: Quick Save and screenshot shortcuts, and a card of the keys used inside Magpie
- **Export everything** (File → Export Library…, ⇧⌘E): a folder with `library.json` (every block, field, collection, tag and day), your pictures as plain files, and `bookmarks.html` that Safari, Chrome and Firefox can import, collections as folders. **File → Import Magpie Export…** (⌥⌘I) reads it back with nothing lost; what you already have is left alone
- **Rename while sorting the Inbox:** click the card's title, or press **R**. Return saves, Escape cancels; the sorting keys wait while you type
- **Drop onto the Dock icon:** links, pictures, files and Safari link files (.webloc) dropped on Magpie's Dock icon go to the Inbox, even when Magpie isn't open. A quick drop leaves you where you were, with "Saved to Inbox" shown above the Dock; hold the item on the icon until Magpie comes forward to open it instead
- **Save a screenshot** (⌃⌥S, anywhere, or File → Save Screenshot…): select part of the screen and it's saved to the Inbox as a picture whose text you can search. The first time, Magpie explains why macOS asks for Screen Recording. Turn the shortcut off in Settings → General
- **Import bookmarks** (File → Import Bookmarks…, ⇧⌘I): choose the file Safari (File ▸ Export ▸ Bookmarks), Chrome or Firefox exports. A preview shows the folder tree with counts; tick the folders you want. Folders become nested collections, links outside folders go to the Inbox, ones you already have are skipped and counted, and each keeps the date you bookmarked it. Previews load in the background, a few at a time
- **Your own order.** Drag a card (or a Journal row) onto another to put it there. The Sort menu gains **Manual**; dragging while sorted any other way switches to Manual and keeps what you see
- **Keyboard.** Arrow keys move between cards (up and down a column, left and right across), **Space** (or ⌘Y) opens Quick Look on a block's picture or file, and **⌘3–⌘7** open your pinned collections (⌘1 All, ⌘2 Inbox)
- **Quick Save** (⌃⌥Space, anywhere): a small panel saves Safari's front tab, or the clipboard when Safari isn't in front. Change the title, pick a collection (Inbox by default), add tags and a note, and press Return; Escape cancels. You stay in Safari. The first time, macOS asks whether Magpie may read Safari; if not, Quick Save uses the clipboard and says so. Choose another shortcut, or turn it off, in Settings → General
- **Search everything** (⌘F, or the magnifier in the top bar): titles, notes, links, sites, tags, collection names and the text in your images (read on your Mac with Apple's Vision). Ignores case and accents, matches the start of words, and includes the Archive. Matching words are highlighted
- **Video time and wishlist totals.** A collection with videos shows how much there is to watch ("1 h 5 min of video saved") and an **I have 20 minutes** filter; one with products shows the total, per currency ("€442 + $60")
- **Rediscover** (View → Rediscover, ⌃⌘5, or from the Inbox zero screen): five old saves a day, ones you haven't opened in two weeks, one big card at a time. **K** keeps it, **A** archives it, **→** skips it (it comes up less often), **Return** opens it. After five: "That's today's five. Come back tomorrow."
- **Archive.** Archive a block (⇧⌘A, the details panel, or right-click) to take it out of your collections without deleting it. Find it under Archive in the Collections panel (⌃⌘0), and **Unarchive** puts it back where it was
- **Collections that expire their blocks.** Right-click a collection → Expire Blocks After 7, 14, 30 or 90 days. Blocks added from then on show "expires in 2 d" when it's close, and expired ones move to **Expired** (archived, never deleted). **Keep** stops a block from expiring
- **Sort** any collection, the Inbox, All or a tag: Newest, Oldest, Quickest (shortest read or watch first), Title A–Z, Site, Color (by the picture's main color) or Shuffle (a new order each time you choose it). Use the Sort button in the top bar, View → Sort By (⌥⌘1–7), or click a Journal column header. Each place remembers its own order
- **Journal** (⌃⌘2, or the list button in the view switcher): your blocks as a dense numbered list with color, title, length or price, collection and date. ↑ and ↓ move, Return opens, Delete deletes. Each place remembers whether you last saw it as a Gallery or a Journal
- **Tags.** Tag any block from its details panel, or select a card and press **T** (⌘T): type a tag and press Return, or several at once with commas. Existing tags are suggested as you type (Tab takes the first). "Jazz" and "jazz" are one tag. Click a tag to see every block that has it, across collections; the Collections panel (⌘K) lists all your tags. Right-click a tag to rename it (renaming to another tag's name merges the two), change its color, or delete it (the blocks stay)
- **Lucky Dip** (⌃⌘4, or the dice in the view switcher). Can't decide what to read or watch? Pick a pile and how much time you have, press **Randomize** (⌘R), and after a short shuffle Magpie picks one block. You get **2 re-spins a day**, then you commit, or choose **Not today**. **Start reading** (or Start watching, Put it on, Cook it, Go there; ⌘Return) opens it and marks it In progress until you **Mark as finished**. Shows the pile's size and time, how many you finished this week, and your daily dip streak. Blocks you keep passing on come up less often, and after three passes their details ask "Still want this?"
- **Piles.** Blocks sort themselves into Read, Watch, Listen, Cook and Visit by what they are: articles to Read, videos to Watch, music links to Listen, recipes to Cook, places to Visit. Choose a different pile from the details panel
- **Copy a link.** Select a card and press ⌘C (Edit → Copy) to copy its link, or a note's text. Right-click the link in the details panel, or the big card in Sort Inbox, for Open and Copy Link
- **Videos, products and places are recognized.** A saved video shows its length ("13 min"), a shop page its price ("€189" or "189 €", in your Mac's format), and an article its read time. Read from the page's own data (schema.org and meta tags), Vimeo's oEmbed for Vimeo links, and Apple Maps and Google Maps links become places. Recipe pages are noted for the coming Cook pile
- **Sort Inbox** (⌃⌘3, or the third button in the view switcher, or **Start sorting** in the Inbox): your Inbox one block at a time, big, with a suggested collection. Press **M** to move it there, **D** to mark it done, **→** to skip it (it goes to the back of the queue), **⌫** to delete it, or click any collection. A progress bar shows how many are sorted and how many are left. The suggestion comes from the site and kind (a YouTube link goes to Watch later, a shop to Shopping), else from where that site's blocks went last
- **Inbox zero and a daily streak.** Sorting your last Inbox block shows "Inbox zero." with how many you sorted, kept, marked done and deleted. Each day you reach Inbox zero adds one to your streak, shown next to the window buttons with a ring that fills over a week. A day you saved nothing doesn't break it. Click the streak to start sorting
- **View → Gallery** (⌃⌘1) and **View → Sort Inbox** (⌃⌘3)
- **Nest and reorder collections.** In the Collections panel (⌘K), drag a collection onto another to put it inside, or onto the top or bottom edge of a row to reorder. Nested collections are indented under their parent
- **Rename, move and delete collections** from the right-click menu in the Collections panel or on a top bar tab (a top bar tab is renamed right in the tab, with the name selected so you can type over it), or from the new **Collection** menu: Rename (⇧⌘R), Move Up (⌥⌘↑), Move Down (⌥⌘↓), Move Into, Move to Top Level, and Delete (⇧⌘⌫). Deleting asks first, says how many blocks go back to the Inbox, and never deletes a block
- **View → Appearance** switches between Dark, Light and Match my Mac without opening Settings, and **⌃⌘T** flips between Dark and Light

### Fixed

- A crash when a block was deleted while its card was still fading out (for example ⌫ in Sort Inbox)
- Magpie's own checks no longer open pages in your browser
- Deleting a card no longer makes the other cards overlap while the Gallery rearranges
- Dropping onto the Dock icon now works for pictures, files, Safari link files and website links dragged from Chrome or Safari. Magpie never becomes your default app or browser for any of them
- The demo and test libraries no longer change how your real library is sorted
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
