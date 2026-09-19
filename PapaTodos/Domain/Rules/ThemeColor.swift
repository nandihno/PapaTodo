import Foundation

/// Profile theme color rules, ported from PapaBoard's `src/lib/theme.js`.
nonisolated enum ThemeColor {
    static let defaultHex = "#008F81"
    static let suggestedHexes = ["#008F81", "#2F6F46", "#4F46E5", "#C2410C", "#BE123C"]

    /// `#RRGGBB` uppercased, or nil when the value isn't a 6-digit hex color.
    /// A leading `#` is optional; 3-digit shorthand is rejected, as on the web.
    static func normalize(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard digits.count == 6, digits.allSatisfy(\.isHexDigit) else { return nil }
        return "#" + digits.uppercased()
    }

    static func effectiveHex(_ value: String?) -> String {
        normalize(value) ?? defaultHex
    }

    static func rgb(fromHex hex: String) -> (r: Double, g: Double, b: Double)? {
        guard let normalized = normalize(hex) else { return nil }
        let digits = normalized.dropFirst()
        func channel(_ start: Int) -> Double {
            let from = digits.index(digits.startIndex, offsetBy: start)
            let to = digits.index(from, offsetBy: 2)
            return Double(Int(digits[from..<to], radix: 16) ?? 0)
        }
        return (channel(0), channel(2), channel(4))
    }

    /// White or near-black, whichever has the higher WCAG contrast ratio against
    /// `hex`. Falls back to the default theme when `hex` is invalid.
    static func readableForegroundIsLight(on hex: String) -> Bool {
        let background = rgb(fromHex: normalize(hex) ?? defaultHex) ?? (0, 143, 129)
        let white = contrast(background, (255, 255, 255))
        let dark = contrast(background, (15, 19, 17))
        return white >= dark
    }

    /// Whether `hex` is readable enough (WCAG 3:1 for UI components) to tint controls on
    /// the given system background: white in light mode, black in dark mode. Pale
    /// themes fail in light mode and very dark ones in dark mode, so the app falls back
    /// to the default accent for controls rather than render unreadable buttons.
    static func isUsableAsTint(_ hex: String, darkMode: Bool) -> Bool {
        guard let color = rgb(fromHex: hex) else { return false }
        let background: (r: Double, g: Double, b: Double) = darkMode ? (0, 0, 0) : (255, 255, 255)
        return contrast(color, background) >= 3
    }

    private static func contrast(
        _ lhs: (r: Double, g: Double, b: Double),
        _ rhs: (r: Double, g: Double, b: Double)
    ) -> Double {
        let a = luminance(lhs), b = luminance(rhs)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    private static func luminance(_ color: (r: Double, g: Double, b: Double)) -> Double {
        func linear(_ channel: Double) -> Double {
            let value = channel / 255
            return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.r) + 0.7152 * linear(color.g) + 0.0722 * linear(color.b)
    }
}

/// Avatar URL validation, ported from `normalizeAvatarUrl` in PapaBoard's
/// `src/lib/profiles.js`: only http/https URLs with a host are accepted.
nonisolated enum AvatarURL {
    /// - Returns: `.some(nil)` for empty input (meaning "clear"), `.some(url)` for a valid
    ///   URL, and `nil` when the input is non-empty but not a valid http(s) URL.
    static func parse(_ input: String) -> URL?? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .some(nil) }
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host(), !host.isEmpty
        else { return nil }
        return .some(url)
    }

    static func isValid(_ input: String) -> Bool {
        parse(input) != nil
    }
}
