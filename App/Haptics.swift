import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Lightweight haptic feedback for success / error / light taps.
enum Haptics {
  static func success() {
    #if canImport(UIKit)
    UINotificationFeedbackGenerator().notificationOccurred(.success)
    #endif
  }

  static func error() {
    #if canImport(UIKit)
    UINotificationFeedbackGenerator().notificationOccurred(.error)
    #endif
  }

  static func warning() {
    #if canImport(UIKit)
    UINotificationFeedbackGenerator().notificationOccurred(.warning)
    #endif
  }

  static func light() {
    #if canImport(UIKit)
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    #endif
  }
}
