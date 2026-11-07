import Foundation
import SwiftData

// The data. Written to CloudKit's rules so iCloud sync can be turned on later
// without a migration: every property has a default or is optional, every
// relationship is optional with an inverse, no unique constraints (duplicates
// are found in code by `normalizedURL`), order is a Double.

enum BlockKind: String, CaseIterable, Codable {
    case link, video, place, image, file, note, checklist

    var label: String {
        switch self {
        case .link: "Link"
        case .video: "Video"
        case .place: "Place"
        case .image: "Image"
        case .file: "File"
        case .note: "Note"
        case .checklist: "Checklist"
        }
    }
}

enum BlockStatus: String, Codable {
    case inbox, kept, done, archived
}

/// Where a block's preview stands: waiting for the network, filled in, or given up on.
enum EnrichState: String, Codable {
    case pending, done, failed
}

struct ChecklistItem: Codable, Hashable, Identifiable {
    var id = UUID()
    var text: String
    var done = false
}

@Model
final class Block {
    var uid: UUID = UUID()
    var kindRaw: String = BlockKind.link.rawValue
    var urlString: String?
    var normalizedURL: String?
    var title: String = ""
    var siteName: String = ""
    var note: String = ""
    /// A note's text.
    var bodyText: String = ""
    var checklistData: Data?
    @Attribute(.externalStorage) var thumbnail: Data?
    /// Width / height of the thumbnail, for laying out the Gallery before images load.
    var thumbnailAspect: Double = 0
    /// The thumbnail's main color as 0xRRGGBB (stored as Int for SwiftData).
    var colorHex: Int?
    var statusRaw: String = BlockStatus.inbox.rawValue
    var enrichRaw: String = EnrichState.done.rawValue
    var createdAt: Date = Date.now
    var openedAt: Date?
    var collection: BlockCollection?

    init(kind: BlockKind, title: String = "") {
        self.kindRaw = kind.rawValue
        self.title = title
    }

    var kind: BlockKind {
        get { BlockKind(rawValue: kindRaw) ?? .link }
        set { kindRaw = newValue.rawValue }
    }

    var status: BlockStatus {
        get { BlockStatus(rawValue: statusRaw) ?? .inbox }
        set { statusRaw = newValue.rawValue }
    }

    var enrich: EnrichState {
        get { EnrichState(rawValue: enrichRaw) ?? .done }
        set { enrichRaw = newValue.rawValue }
    }

    var url: URL? { urlString.flatMap(URL.init(string:)) }

    var checklist: [ChecklistItem] {
        get { checklistData.flatMap { try? JSONDecoder().decode([ChecklistItem].self, from: $0) } ?? [] }
        set { checklistData = try? JSONEncoder().encode(newValue) }
    }

    var tint: UInt32? { colorHex.map { UInt32(truncatingIfNeeded: $0) } }
}

/// A named place for blocks (Watch later, Shopping…). Called BlockCollection in code
/// because Swift already has a `Collection`.
@Model
final class BlockCollection {
    var uid: UUID = UUID()
    var name: String = ""
    var colorHex: Int = 0x7FD9D3
    var sortIndex: Double = 0
    var isPinned: Bool = false
    var pinIndex: Int = 0
    var createdAt: Date = Date.now
    @Relationship(deleteRule: .nullify, inverse: \Block.collection) var blocks: [Block]? = []

    init(name: String, colorHex: Int, sortIndex: Double) {
        self.name = name
        self.colorHex = colorHex
        self.sortIndex = sortIndex
    }
}

/// Colors offered for new collections, from the mockup.
enum CollectionColors {
    static let all: [Int] = [0x7FD9D3, 0xE8A27A, 0xE8CF8A, 0xA8D5A2, 0x8FB5E8, 0xC9A8E8, 0xE88FB0, 0xA1A1A8]
}
