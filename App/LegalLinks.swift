import Foundation

/// Public legal and source URLs for AGPL compliance + App Store review.
enum LegalLinks {
  static let privacyPolicy = URL(string: "https://skyphusion.org/privacy.html")!
  static let website = URL(string: "https://skyphusion.org")!
  static let playground = URL(string: "https://play.skyphusion.org")!
  // No status link. status.skyphusion.org (Gatus) was removed from the estate 2026-09-25 and
  // is NXDOMAIN; this constant shipped pointing at it from 0.8.1 through 1.0.0 (#62). There is
  // no replacement status surface, so the entry is gone rather than repointed: a link to a
  // page that does not exist yet is a promise, and a shipped client cannot make one. If a
  // status surface is ever published, add it back WITH the About row in SettingsView and the
  // host allowlist in Tests/PrismKitTests/LegalLinkHostsTests.swift.
  static let supportEmail = URL(string: "mailto:support@skyphusion.org")!

  /// Complete corresponding source for this AGPL client.
  static let sourceCode = URL(string: "https://github.com/skyphusion-labs/prism-ios")!
  /// License text on the public repo (canonical when network is available).
  static let licenseOnline = URL(
    string: "https://github.com/skyphusion-labs/prism-ios/blob/main/LICENSE"
  )!
  static let noticeOnline = URL(
    string: "https://github.com/skyphusion-labs/prism-ios/blob/main/NOTICE"
  )!

  /// Related AGPL components (inference + commercial plane).
  static let prismWorkerSource = URL(string: "https://github.com/skyphusion-labs/prism")!
  static let controlPlaneSource = URL(
    string: "https://github.com/skyphusion-labs/prism-control-plane"
  )!

  static let licenseShortName = "AGPL-3.0-only"
  static let copyrightLine = "Copyright SkyPhusion Labs. Prism is free software under the GNU Affero General Public License v3.0 only."
}
