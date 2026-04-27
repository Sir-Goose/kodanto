import SwiftUI

enum PlatformColors {
  static var background: Color {
    #if os(macOS)
      return Color(NSColor.windowBackgroundColor)
    #else
      return Color.white
    #endif
  }
}

extension Color {
  static var appBackground: Color { PlatformColors.background }
}
