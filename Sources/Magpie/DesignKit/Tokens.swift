import AppKit
import MagpieKit
import SwiftUI

// Magpie design tokens, in three layers (notes/design/KIT.md):
//   Palette  raw colors. Only this file reads it.
//   Ink      meaning, with a light and a dark value. Parts read only this.
//   Metric, Motion, KitType (KitType.swift)  scales.
// A rebrand changes Palette; a light or dark fix changes Ink. Neither touches a part.

enum Palette {
    static let night950: UInt32 = 0x0E0F11
    static let night900: UInt32 = 0x17181B
    static let night800: UInt32 = 0x22242A
    static let snow50: UInt32 = 0xECECEE
    static let fog400: UInt32 = 0xA1A1A8
    static let fog600: UInt32 = 0x6E6E75
    static let paper50: UInt32 = 0xF4F5F2
    static let paper0: UInt32 = 0xFFFFFF
    static let paper100: UInt32 = 0xECEEEA
    static let ink900: UInt32 = 0x1C1D1B
    static let ink600: UInt32 = 0x55584F
    static let ink400: UInt32 = 0x8A8D86
    static let teal300: UInt32 = 0x7FD9D3
    static let teal600: UInt32 = 0x127A76
    static let teal700: UInt32 = 0x0E6662
    static let teal950: UInt32 = 0x132322
    static let teal50: UInt32 = 0xE3F2F1
    static let amber300: UInt32 = 0xE8CF8A
    static let amber700: UInt32 = 0x8A6A12
}

enum Ink {
    static let window = Color(light: Palette.paper50, dark: Palette.night950)
    static let surface = Color(light: Palette.paper0, dark: Palette.night900)
    static let control = Color(light: Palette.paper100, dark: Palette.night800)
    static let text = Color(light: Palette.ink900, dark: Palette.snow50)
    static let secondary = Color(light: Palette.ink600, dark: Palette.fog400)
    static let tertiary = Color(light: Palette.ink400, dark: Palette.fog600)
    static let hairline = Color(lightAlpha: (0x000000, 0.08), darkAlpha: (0xFFFFFF, 0.08))
    static let hover = Color(lightAlpha: (0x000000, 0.05), darkAlpha: (0xFFFFFF, 0.06))
    static let accent = Color(hex: Palette.teal600)
    static let accentText = Color(light: Palette.teal700, dark: Palette.teal300)
    static let onAccent = Color(hex: Palette.paper0)
    static let chosen = Color(light: Palette.ink900, dark: Palette.snow50)
    static let onChosen = Color(light: Palette.paper0, dark: Palette.night950)
    static let suggest = Color(light: Palette.teal50, dark: Palette.teal950)
    static let noteLabel = Color(light: Palette.amber700, dark: Palette.amber300)
    static let shadow = Color(lightAlpha: (0x000000, 0.10), darkAlpha: (0x000000, 0.50))
    static let mapGround = Color(light: 0xDCE6E0, dark: 0x1C2A24)
    static let mapRoad = Color(light: 0xC3D3CA, dark: 0x2E4A3E)
    static let mapGrid = Color(lightAlpha: (0x000000, 0.06), darkAlpha: (0xFFFFFF, 0.06))
    static let badge = Color.black.opacity(0.66)
    static let onBadge = Color.white

    /// A card background from an image's main color (KIT.md "Card"): text on it reads at 7:1 in both modes.
    static func card(tint hex: UInt32?) -> Color {
        guard let hex else { return surface }
        let color = RGB(hex: hex)
        let dark = CardTint.dark(from: color, background: RGB(hex: Palette.night950), text: RGB(hex: Palette.snow50))
        let light = CardTint.light(from: color, text: RGB(hex: Palette.ink900))
        return Color(light: light.hex, dark: dark.hex)
    }

    /// A raw image color for thumbnails and placeholder art (not a theme color).
    static func swatch(_ hex: UInt32) -> Color { Color(hex: hex) }
}

enum Metric {
    static let barHeight: CGFloat = 56
    static let control: CGFloat = 32
    static let controlLarge: CGFloat = 44
    static let roundButton: CGFloat = 36
    static let segmentWidth: CGFloat = 34
    static let segmentHeight: CGFloat = 30
    static let radiusField: CGFloat = 10
    static let radius: CGFloat = 12
    static let radiusCard: CGFloat = 16
    static let radiusPanel: CGFloat = 20
    static let radiusBadge: CGFloat = 6
    static let radiusCheck: CGFloat = 4
    static let menuRowHeight: CGFloat = 40
    static let menuRowRadius: CGFloat = 9
    static let cardGap: CGFloat = 16
    static let cardPadding: CGFloat = 14
    static let panelWidth: CGFloat = 340
    static let popoverWidth: CGFloat = 270
    static let check: CGFloat = 14
    static let swatch: CGFloat = 10
    static let progressHeight: CGFloat = 6
    static let ring: CGFloat = 16
    static let ringStroke: CGFloat = 2.4
    static let pillInset: CGFloat = 4
    /// Small values measured from the mockup; named so views never hard-code them.
    static let inlineGap: CGFloat = 6        // icon + label, kind label to title
    static let trackInset: CGFloat = 3       // segment track padding
    static let rowInset: CGFloat = 10        // menu rows, fields, chip-like capsules
    static let fieldVertical: CGFloat = 7
    static let badgePadding = EdgeInsets(top: 3, leading: 7, bottom: 3, trailing: 7)
    static let badgeInset: CGFloat = 10      // badge distance from the thumbnail corner
    static let segmentRadius: CGFloat = 9
    static let swatchRadius: CGFloat = 3
    static let dividerHeight: CGFloat = 18
    static let popoverPadding: CGFloat = 6
    static let treeIndent: CGFloat = 16      // one nesting level in the Collections panel
    static let dropLine: CGFloat = 2         // where a dragged row will land
    static let collectionsWidth: CGFloat = 400
    static let collectionsMaxHeight: CGFloat = 360
    static let keyCap: CGFloat = 24
    static let streakPill: CGFloat = 28
    static let tagChip: CGFloat = 24
    static let searchWidth: CGFloat = 560
    static let journalRow: CGFloat = 48
    static let journalHeader: CGFloat = 36
    static let journalNumber: CGFloat = 40
    static let journalLength: CGFloat = 96
    static let journalCollection: CGFloat = 128
    static let journalSaved: CGFloat = 72
    static let tagDot: CGFloat = 8
    /// The streak pill's distance from the window's left edge, clear of the traffic lights.
    static let streakInset: CGFloat = 88
    static let celebrationRing: CGFloat = 120
    static let celebrationWidth: CGFloat = 520
    static let dipSidebar: CGFloat = 332      // Lucky Dip's pile column
    static let dipPickMaxWidth: CGFloat = 760
    static let dipPickHero: CGFloat = 280     // the pick's picture, on its left
    static let dipPickMinHeight: CGFloat = 280          // the key in a key button
    static let sortWidth: CGFloat = 560      // Sort Inbox's card and progress line
    static let sortHero: CGFloat = 232       // the big card's picture
    static let radiusSortCard: CGFloat = 22
    static let stackStep: CGFloat = 12       // how far each card behind the big one is inset and lowered
    static let mapRoad: CGFloat = 10
    static let tabPadding: CGFloat = 14
    static let chipPadding: CGFloat = 12
    static let buttonPadding: CGFloat = 14
    static let focusRing: CGFloat = 2
    static let barShadowRadius: CGFloat = 15
    static let pressScale: CGFloat = 0.97
    static let windowDefault = CGSize(width: 1200, height: 800)
    static let windowMinimum = CGSize(width: 1040, height: 560)
    /// Traffic lights: center of the close button, and the distance between buttons.
    static let trafficLights = CGPoint(x: 28, y: 28)
    static let trafficLightSpacing: CGFloat = 20
}

enum Motion {
    static let hover = Animation.easeOut(duration: 0.12)
    static let press = Animation.spring(response: 0.25, dampingFraction: 0.7)
    static let panel = Animation.spring(response: 0.35, dampingFraction: 0.85)
    static let progress = Animation.easeInOut(duration: 0.3)
}

extension View {
    /// The kit's environment for every scene root: accent tint and no system focus ring
    /// (kit parts draw their own).
    func kitScene() -> some View {
        tint(Ink.accentText).focusEffectDisabled()
    }
}

// MARK: - Color helpers

extension Color {
    init(hex: UInt32) {
        self.init(nsColor: NSColor(hex: hex))
    }

    /// A color with a light and a dark value.
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(hex: dark) : NSColor(hex: light)
        })
    }

    /// A translucent color with a light and a dark value: (hex, alpha).
    init(lightAlpha: (UInt32, CGFloat), darkAlpha: (UInt32, CGFloat)) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let (hex, alpha) = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? darkAlpha : lightAlpha
            return NSColor(hex: hex).withAlphaComponent(alpha)
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}
