import SwiftUI

enum Theme {
    static let accent = Color(red: 0.89, green: 0.16, blue: 0.14)

    static func scheme(_ choice: String) -> ColorScheme? {
        switch choice {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}

extension TimeInterval {
    var durationText: String {
        let total = Int(self)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}
