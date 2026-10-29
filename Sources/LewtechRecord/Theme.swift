import SwiftUI
import AppKit
import CoreText

/// Tokens observed in lewtech.no/assets/index-C2tRvRSS.css.
enum LT {
    static let ink = Color(hex: 0x263A2E)
    static let dark = Color(hex: 0x25372C)
    static let paper = Color(hex: 0xEEEADE)
    static let muted = Color(hex: 0xC7CABC)
    static let accent = Color(hex: 0x925237)
    static let surface = Color(hex: 0xF7F5EF)
    static let border = Color(hex: 0x263A2E).opacity(0.13)
    static let secondary = Color(hex: 0x687064)

    private static let register: Void = {
        for name in ["Manrope-Regular", "Manrope-Medium", "Manrope-SemiBold"] {
            if let url = Bundle.appResources.url(forResource: name, withExtension: "ttf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }()

    static func registerFonts() { _ = register }

    static func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        registerFonts()
        let face: String
        switch weight {
        case .semibold, .bold, .heavy, .black: face = "Manrope-SemiBold"
        case .medium: face = "Manrope-Medium"
        default: face = "Manrope-Regular"
        }
        return .custom(face, size: size)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(LT.font(13, weight: .semibold))
            .padding(.horizontal, 18).padding(.vertical, 12)
            .foregroundStyle(LT.surface)
            .background(LT.ink.opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.4), in: RoundedRectangle(cornerRadius: 11))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

struct QuietButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(LT.font(13, weight: .medium))
            .padding(.horizontal, 14).padding(.vertical, 10)
            .foregroundStyle(LT.ink.opacity(isEnabled ? 1 : 0.4))
            .background(configuration.isPressed ? LT.paper : LT.surface, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(LT.border, lineWidth: 1))
    }
}

struct LewtechWordmark: View {
    var light = false
    var body: some View {
        Group {
            if let url = Bundle.appResources.url(forResource: "lewtech-logo", withExtension: "png"),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .renderingMode(.template)
                    .resizable().scaledToFit()
                    .frame(width: 236, height: 148)
                    .frame(width: 174, height: 48)
                    .clipped()
            } else {
                Text("lewtech").font(LT.font(29, weight: .semibold))
            }
        }
        .foregroundStyle(light ? LT.surface : LT.ink)
        .accessibilityLabel("Lewtech")
    }
}

extension Bundle {
    /// SwiftPM's generated accessor points at the build tree for executables.
    /// Prefer the resources inside the installed .app so it is self-contained.
    static let appResources: Bundle = {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("LewtechRecord_LewtechRecord.bundle"),
           let bundle = Bundle(url: url) { return bundle }
        return Bundle.module
    }()
}
