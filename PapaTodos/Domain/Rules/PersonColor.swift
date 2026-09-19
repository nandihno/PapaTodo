import Foundation

/// Deterministic per-person hue and initials, ported from PapaBoard's
/// `src/lib/personColor.js` and `ProfileAvatar.jsx` so each family member reads
/// as the same color across both clients.
nonisolated enum PersonColor {
    static let defaultSeed = "PapaBoard"

    /// 0..<360. Same hash as the web: `hash = hash * 31 + charCode` over UTF-16
    /// code units, kept in a uint32.
    static func hue(for seed: String?) -> Int {
        let value = (seed?.isEmpty == false) ? seed! : defaultSeed
        var hash: UInt32 = 0
        for unit in value.utf16 {
            hash = hash &* 31 &+ UInt32(unit)
        }
        return Int(hash % 360)
    }
}

nonisolated enum ProfileInitials {
    /// Up to two initials from the name, ignoring anything after an `@` and
    /// splitting on whitespace, `.` and `-`. "PB" when there is nothing usable.
    static func make(from name: String?) -> String {
        var value = name ?? ""
        if let at = value.firstIndex(of: "@") {
            value = String(value[..<at])
        }
        let parts = value
            .split(whereSeparator: { $0.isWhitespace || $0 == "." || $0 == "-" })
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return "PB" }
        return parts.prefix(2).compactMap { $0.first }.map { String($0) }.joined().uppercased()
    }
}
