import MagpieKit
import SwiftUI

/// Type roles (notes/design/KIT.md "Type"). Views set fonts only through `.kitType(...)`.
enum KitType {
    case display, title, heading, cardTitle, body, label, labelStrong, meta, metaStrong, kind, mono

    var font: Font {
        switch self {
        case .display: .system(size: 28, weight: .bold)
        case .title: .system(size: 22, weight: .bold)
        case .heading: .system(size: 17, weight: .semibold)
        case .cardTitle: .system(size: 14, weight: .semibold)
        case .body: .system(size: 13)
        case .label: .system(size: 13, weight: .medium)
        case .labelStrong: .system(size: 13, weight: .semibold)
        case .meta: .system(size: 12)
        case .metaStrong: .system(size: 12, weight: .bold)
        case .kind: .system(size: 11, weight: .semibold)
        case .mono: .system(size: 11, design: .monospaced)
        }
    }

    var tracking: CGFloat {
        switch self {
        case .kind: 0.4
        case .mono: 0.6
        case .display, .title: -0.3
        default: 0
        }
    }
}

extension View {
    func kitType(_ type: KitType) -> some View {
        font(type.font).tracking(type.tracking)
    }
}

/// Every icon the app uses. Views name a KitIcon, never an SF Symbol string,
/// so the whole set changes in one place (notes/design/KIT.md "Icons").
enum KitIcon: String, CaseIterable {
    case add, search, sort, gallery, journal, sortInbox, luckyDip, close, pin, chevronDown, check
    case pileRead, pileWatch, pileListen, pileCook, pileVisit
    case rediscover, archive

    var symbol: String {
        switch self {
        case .add: "plus"
        case .search: "magnifyingglass"
        case .sort: "arrow.up.arrow.down"
        case .gallery: "square.grid.2x2"
        case .journal: "list.bullet"
        case .sortInbox: "scope"
        case .luckyDip: "die.face.5"
        case .close: "xmark"
        case .pin: "star"
        case .chevronDown: "chevron.down"
        case .check: "checkmark"
        case .pileRead: "book"
        case .pileWatch: "play.rectangle"
        case .pileListen: "music.note"
        case .pileCook: "fork.knife"
        case .pileVisit: "mappin.and.ellipse"
        case .rediscover: "clock.arrow.circlepath"
        case .archive: "archivebox"
        }
    }

    /// The filled form for selected states, when SF Symbols has one.
    var filledSymbol: String {
        switch self {
        case .pin, .gallery: symbol + ".fill"
        default: symbol
        }
    }
}

struct KitIconView: View {
    let icon: KitIcon
    var size: CGFloat = 14
    var filled = false

    var body: some View {
        Image(systemName: filled ? icon.filledSymbol : icon.symbol)
            .font(.system(size: size, weight: .medium))
            .frame(width: size + 4, height: size + 4)
            .accessibilityHidden(true)
    }
}

extension Pile {
    var icon: KitIcon {
        switch self {
        case .read: .pileRead
        case .watch: .pileWatch
        case .listen: .pileListen
        case .cook: .pileCook
        case .visit: .pileVisit
        }
    }
}
