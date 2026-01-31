import SwiftUI

// MARK: - Cross-Platform Color Support

extension Color {
    /// Background color for grouped content (works on both iOS and macOS)
    static var groupedBackground: Color {
        #if os(iOS)
        return Color(uiColor: .systemGroupedBackground)
        #else
        return Color(nsColor: .windowBackgroundColor)
        #endif
    }
    
    /// Secondary background color for grouped content
    static var secondaryGroupedBackground: Color {
        #if os(iOS)
        return Color(uiColor: .secondarySystemGroupedBackground)
        #else
        return Color(nsColor: .controlBackgroundColor)
        #endif
    }
    
    /// Gold color used for SDO 171
    static var gold: Color {
        Color(red: 1.0, green: 0.84, blue: 0.0)
    }

    /// Cyan color for solar instruments
    static var solarCyan: Color {
        Color(red: 0.0, green: 1.0, blue: 1.0)
    }
}
