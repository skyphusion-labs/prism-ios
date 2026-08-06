import UIKit
import PrismKit

/// Hooks background URLSession redelivery so long-running gens (video/music)
/// can finish after lock or process suspension.
final class PrismAppDelegate: NSObject, UIApplicationDelegate {
  func application(
    _ application: UIApplication,
    handleEventsForBackgroundURLSession identifier: String,
    completionHandler: @escaping () -> Void
  ) {
    #if os(iOS)
    if identifier == LongRunningURLSession.identifier {
      LongRunningURLSession.shared.setBackgroundEventsCompletionHandler(completionHandler)
      return
    }
    #endif
    completionHandler()
  }
}
