import CoreText
import SwiftUI

#if canImport(UIKit)
    import UIKit
    typealias PlatformFont = UIFont
#else
    import AppKit
    typealias PlatformFont = NSFont
#endif

// DESIGN_SYSTEM §1.2 and §5.4. Fonts ship in Resources/Fonts (SIL OFL 1.1, see OFL.txt).

public enum TextRole: CaseIterable, Sendable {
    case display, title, title2, header, buttonL, button, buttonS, nav, badge, body, rowTitle, secondary, caption,
        label, code
    // Additions used by the mockups: chip 12, compact nav 11.5, stat value 20, compact header 17, compact display 31.
    case chip, navSmall, stat, headerCompact, displayCompact

    struct Spec {
        let face: String, size: CGFloat, style: Font.TextStyle, uiStyle: PlatformFont.TextStyle
        var tracking: CGFloat = 0, uppercase = false, lineSpacing: CGFloat = 0, boldFace: String? = nil
    }

    var spec: Spec {
        switch self {
        case .display: Spec(face: Face.pixelBold, size: 34, style: .largeTitle, uiStyle: .largeTitle)
        case .displayCompact: Spec(face: Face.pixelBold, size: 31, style: .largeTitle, uiStyle: .largeTitle)
        case .title: Spec(face: Face.pixelSemi, size: 26, style: .title, uiStyle: .title1, lineSpacing: 2)
        case .title2: Spec(face: Face.pixelSemi, size: 21, style: .title2, uiStyle: .title2)
        case .header: Spec(face: Face.pixelSemi, size: 22, style: .headline, uiStyle: .headline)
        case .headerCompact: Spec(face: Face.pixelSemi, size: 17, style: .headline, uiStyle: .headline)
        case .buttonL: Spec(face: Face.pixelMedium, size: 19, style: .body, uiStyle: .body)
        case .button: Spec(face: Face.pixelMedium, size: 15, style: .body, uiStyle: .body)
        case .buttonS: Spec(face: Face.pixelMedium, size: 13, style: .subheadline, uiStyle: .subheadline)
        case .chip: Spec(face: Face.pixelMedium, size: 12, style: .subheadline, uiStyle: .subheadline)
        case .nav: Spec(face: Face.pixelMedium, size: 16, style: .body, uiStyle: .body)
        case .navSmall: Spec(face: Face.pixelMedium, size: 11.5, style: .caption, uiStyle: .caption1)
        case .stat: Spec(face: Face.pixelBold, size: 20, style: .title3, uiStyle: .title3)
        case .badge:
            Spec(
                face: Face.pixelMedium, size: 11, style: .caption2, uiStyle: .caption2, tracking: 0.33, uppercase: true)
        case .body:
            Spec(
                face: Face.geist, size: 15, style: .subheadline, uiStyle: .subheadline, lineSpacing: 8,
                boldFace: Face.geistMedium)
        case .rowTitle:
            Spec(face: Face.geistMedium, size: 14, style: .subheadline, uiStyle: .subheadline, boldFace: Face.geistSemi)
        case .secondary:
            Spec(
                face: Face.geist, size: 13, style: .footnote, uiStyle: .footnote, lineSpacing: 6,
                boldFace: Face.geistMedium)
        case .caption: Spec(face: Face.geist, size: 11, style: .caption, uiStyle: .caption1, boldFace: Face.geistMedium)
        case .label:
            Spec(
                face: Face.mono, size: 11, style: .caption2, uiStyle: .caption2, tracking: 0.77, uppercase: true,
                boldFace: Face.monoMedium)
        case .code:
            Spec(
                face: Face.mono, size: 11, style: .caption, uiStyle: .caption1, lineSpacing: 7,
                boldFace: Face.monoMedium)
        }
    }

    /// Roles that change size with the container (§1.2: display 31 compact · 34 regular, header 17 bar · 22 column).
    func adapted(to width: WidthClass) -> TextRole {
        guard width == .compact else { return self }
        switch self {
        case .display: return .displayCompact
        default: return self
        }
    }
}

enum Face {
    static let pixelMedium = "PixelifySans-Medium", pixelSemi = "PixelifySans-SemiBold", pixelBold = "PixelifySans-Bold"
    static let geist = "Geist-Regular", geistMedium = "Geist-Medium", geistSemi = "Geist-SemiBold"
    static let mono = "GeistMono-Regular", monoMedium = "GeistMono-Medium"
}

public enum CofreFonts {
    /// Registers the bundled fonts for this process. Safe to call more than once. Air's Info.plist stays untouched.
    @discardableResult
    public static func register() -> Bool { registered }

    private static let registered: Bool = {
        guard let dir = Bundle.module.url(forResource: "Fonts", withExtension: nil),
            let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return false }
        var ok = true
        for url in files where url.pathExtension == "ttf" {
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                // Already registered is fine; anything else falls back to system fonts.
                let code = (error?.takeRetainedValue()).map { CFErrorGetCode($0) } ?? 0
                if code != CTFontManagerError.alreadyRegistered.rawValue { ok = false }
            }
        }
        return ok
    }()

    /// URL of the bundled OFL text, for About → Licenses.
    public static var licenseURL: URL? {
        Bundle.module.url(forResource: "OFL", withExtension: "txt", subdirectory: "Fonts")
    }
}

extension Font {
    /// Custom font for a role, scaled for `typeSize` like `Font.custom(_:size:relativeTo:)`.
    /// Ligatures and contextual alternates are off, as in the mockups (Pixelify's "fi" ligature breaks the pixel grid).
    public static func cofre(_ role: TextRole, bold: Bool = false, typeSize: DynamicTypeSize = .large) -> Font {
        let s = role.spec
        #if canImport(UIKit)
            let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(typeSize))
            let size = UIFontMetrics(forTextStyle: s.uiStyle).scaledValue(for: s.size, compatibleWith: traits)
        #else
            let size = s.size  // macOS has no Dynamic Type.
        #endif
        return Font(CofreFonts.ctFont(bold ? (s.boldFace ?? s.face) : s.face, size: size))
    }
}

#if canImport(UIKit)
    extension UIFont {
        /// Same role for UIKit, scaled with `UIFontMetrics`.
        public static func cofre(_ role: TextRole) -> UIFont {
            let s = role.spec
            let name = UIAccessibility.isBoldTextEnabled ? (s.boldFace ?? s.face) : s.face
            let base = CofreFonts.ctFont(name, size: s.size) as UIFont
            return UIFontMetrics(forTextStyle: s.uiStyle).scaledFont(for: base)
        }
    }
#endif

extension CofreFonts {
    private static let cache = NSCache<NSString, CTFont>()

    static func ctFont(_ name: String, size: CGFloat) -> CTFont {
        register()
        let key = "\(name)@\(size)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let off = ["liga", "clig", "calt"].map {
            [kCTFontOpenTypeFeatureTag: $0, kCTFontOpenTypeFeatureValue: 0] as [CFString: Any]
        }
        let desc = CTFontDescriptorCreateWithAttributes(
            [kCTFontNameAttribute: name, kCTFontFeatureSettingsAttribute: off] as CFDictionary)
        let font = CTFontCreateWithFontDescriptor(desc, size, nil)
        cache.setObject(font, forKey: key)
        return font
    }
}

struct CofreFontModifier: ViewModifier {
    let role: TextRole
    @Environment(\.widthClass) private var width
    @Environment(\.legibilityWeight) private var weight
    @Environment(\.dynamicTypeSize) private var typeSize

    func body(content: Content) -> some View {
        let r = role.adapted(to: width)
        let s = r.spec
        content
            .font(.cofre(r, bold: weight == .bold, typeSize: typeSize))
            .tracking(s.tracking)
            .textCase(s.uppercase ? .uppercase : nil)
            .lineSpacing(s.lineSpacing)
    }
}

extension View {
    /// Applies a type role, its tracking and case, Bold Text, and the compact size where the role has one.
    public func cofreFont(_ role: TextRole) -> some View { modifier(CofreFontModifier(role: role)) }
}
