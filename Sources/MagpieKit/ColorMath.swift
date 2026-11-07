import Foundation

/// An sRGB color as 0...1 components. Pure math, no AppKit, so it is unit-tested
/// and shared with the Share extension and the iPhone app later.
public struct RGB: Equatable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double

    public init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    /// 0xRRGGBB.
    public init(hex: UInt32) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
    }

    public var hex: UInt32 {
        func byte(_ v: Double) -> UInt32 { UInt32((min(max(v, 0), 1) * 255).rounded()) }
        return byte(r) << 16 | byte(g) << 8 | byte(b)
    }

    /// WCAG relative luminance.
    public var luminance: Double {
        func channel(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }

    /// WCAG contrast ratio between two colors, 1...21.
    public func contrast(with other: RGB) -> Double {
        let a = luminance + 0.05
        let b = other.luminance + 0.05
        return max(a, b) / min(a, b)
    }

    /// Linear mix: 0 gives self, 1 gives other.
    public func mixed(with other: RGB, amount: Double) -> RGB {
        let t = min(max(amount, 0), 1)
        return RGB(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t)
    }

    /// Hue in degrees 0..<360, or nil for greys (saturation below `greyBelow`).
    public func hue(greyBelow: Double = 0.08) -> Double? {
        let maxC = max(r, g, b), minC = min(r, g, b), d = maxC - minC
        guard d >= greyBelow else { return nil }
        var h: Double
        if maxC == r { h = ((g - b) / d).truncatingRemainder(dividingBy: 6) }
        else if maxC == g { h = (b - r) / d + 2 }
        else { h = (r - g) / d + 4 }
        h *= 60
        return h < 0 ? h + 360 : h
    }
}

/// Card backgrounds tinted with the main color of a block's image (S-064).
public enum CardTint {
    /// The dark mode card: the image color pushed toward the window background
    /// until `text` on it reads at `minContrast` or better.
    public static func dark(from color: RGB, background: RGB, text: RGB, minContrast: Double = 7) -> RGB {
        settle(color, toward: background, text: text, start: 0.82, minContrast: minContrast)
    }

    /// The light mode card: the image color washed toward white until `text` reads.
    public static func light(from color: RGB, text: RGB, minContrast: Double = 7) -> RGB {
        settle(color, toward: RGB(r: 1, g: 1, b: 1), text: text, start: 0.86, minContrast: minContrast)
    }

    private static func settle(_ color: RGB, toward base: RGB, text: RGB, start: Double, minContrast: Double) -> RGB {
        var amount = start
        var tint = color.mixed(with: base, amount: amount)
        while tint.contrast(with: text) < minContrast && amount < 1 {
            amount = min(amount + 0.02, 1)
            tint = color.mixed(with: base, amount: amount)
        }
        return tint
    }
}
