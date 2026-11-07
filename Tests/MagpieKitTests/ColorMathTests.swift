import Testing
@testable import MagpieKit

struct ColorMathTests {
    let darkBackground = RGB(hex: 0x0E0F11)
    let darkText = RGB(hex: 0xECECEE)
    let lightText = RGB(hex: 0x1C1D1B)

    @Test func hexRoundTrips() {
        #expect(RGB(hex: 0x127A76).hex == 0x127A76)
    }

    @Test func contrastMatchesWCAG() {
        let black = RGB(hex: 0x000000), white = RGB(hex: 0xFFFFFF)
        #expect(abs(black.contrast(with: white) - 21) < 0.01)
        #expect(abs(white.contrast(with: white) - 1) < 0.01)
    }

    @Test("Card tints keep text readable", arguments: [0xF3D9BD, 0x1F3A5F, 0xF2DE9B, 0xFFFFFF, 0x000000, 0xC8553D, 0x168C88] as [UInt32])
    func tintsReadable(hex: UInt32) {
        let color = RGB(hex: hex)
        #expect(CardTint.dark(from: color, background: darkBackground, text: darkText).contrast(with: darkText) >= 7)
        #expect(CardTint.light(from: color, text: lightText).contrast(with: lightText) >= 7)
    }

    @Test func tintKeepsSomeColor() {
        // A warm image gives a warm card, not plain grey.
        let tint = CardTint.dark(from: RGB(hex: 0xC8553D), background: darkBackground, text: darkText)
        #expect(tint.r > tint.b)
    }

    @Test func hueOfGreyIsNil() {
        #expect(RGB(hex: 0x808080).hue() == nil)
        #expect(abs((RGB(hex: 0xFF0000).hue() ?? -1) - 0) < 0.5)
        #expect(abs((RGB(hex: 0x0000FF).hue() ?? -1) - 240) < 0.5)
    }
}
