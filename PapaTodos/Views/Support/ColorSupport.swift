import SwiftUI
import UIKit

extension Color {
    /// Builds a color from `#RRGGBB` (falling back to the default theme when invalid).
    init(hex: String) {
        let rgb = ThemeColor.rgb(fromHex: ThemeColor.effectiveHex(hex)) ?? (0, 143, 129)
        self.init(.sRGB, red: rgb.r / 255, green: rgb.g / 255, blue: rgb.b / 255)
    }

    /// `#RRGGBB` in sRGB, or nil when the color can't be resolved.
    var hexString: String? {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        return String(
            format: "#%02X%02X%02X",
            Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded())
        )
    }

    /// The per-person avatar tint: same hue on both platforms, light/dark aware.
    static func person(_ name: String?) -> Color {
        Color(uiColor: personUIColor(hue: CGFloat(PersonColor.hue(for: name)) / 360))
    }
}

/// Must be `nonisolated`: UIKit calls the dynamic-provider closure from SwiftUI's
/// render thread, and a closure created in a MainActor context traps its isolation
/// check there (the project defaults every declaration to MainActor).
private nonisolated func personUIColor(hue: CGFloat) -> UIColor {
    UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(hue: hue, saturation: 0.45, brightness: 0.40, alpha: 1)
            : UIColor(hue: hue, saturation: 0.30, brightness: 0.92, alpha: 1)
    }
}
