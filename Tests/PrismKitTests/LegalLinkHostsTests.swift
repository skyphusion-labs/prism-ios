import XCTest
import Foundation

/// Every host the shipped client can send a user to is a reviewed host (#62).
///
/// WHY THIS FILE EXISTS. `status.skyphusion.org` shipped in the About menu from 0.8.1 through 1.0.0.
/// The host was removed from the estate 2026-09-25 and is NXDOMAIN, so a tap opened a browser on
/// nothing. Nothing in this repo could see that: `.github/workflows/ci.yml` runs `swift test`, and
/// the SwiftPM package is `Sources/PrismKit` only, so **no gate in this repo has ever observed the
/// app target's link surface at all.** CLAUDE.md says as much ("package only"). This test closes
/// that specific gap by reading the app-target files as text, the way a linter would.
///
/// WHAT IT CANNOT SEE, stated here rather than left implied, because the difference decides whether
/// this file is a guard or decoration:
///
///   It CANNOT detect a host DYING. That is what actually happened in #62: the host was correct
///   when it was written and the estate changed underneath it. Detecting that needs a liveness
///   probe against the live internet, which does not belong in a per-PR gate (it would go red on a
///   network blip and teach everyone to ignore it). The right home for that is the external
///   monitor, `skyphusion-labs/skyphusion-monitor`, which already probes public surfaces on a
///   Cloudflare cron and alerts; the clients' linked hosts belong in its probe list.
///
///   So: this test catches a host being ADDED or CHANGED in a shipped legal surface without review.
///   It does not catch the failure mode of #62, and claiming otherwise would be the more expensive
///   mistake.
final class LegalLinkHostsTests: XCTestCase {
  /// Repo root, derived from this file's own path so it works under `swift test` on any checkout.
  private static var repoRoot: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // PrismKitTests
      .deletingLastPathComponent()  // Tests
      .deletingLastPathComponent()  // repo root
  }

  private func source(_ relativePath: String) throws -> String {
    let url = Self.repoRoot.appendingPathComponent(relativePath)
    return try String(contentsOf: url, encoding: .utf8)
  }

  /// Hosts of every `http(s)` URL written as a string literal. Comments are not literals, so a
  /// note that names a retired host in prose does not register as a link.
  private func linkedHosts(in source: String) -> Set<String> {
    let pattern = "\"(https?://[^\"]+)\""
    guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
    let ns = source as NSString
    var hosts: Set<String> = []
    for m in re.matches(in: source, range: NSRange(location: 0, length: ns.length)) {
      let raw = ns.substring(with: m.range(at: 1))
      if let host = URL(string: raw)?.host { hosts.insert(host) }
    }
    return hosts
  }

  // MARK: - Controls

  func testControlExtractorDiscriminates() {
    // Positive half: it finds a literal.
    let found = linkedHosts(in: #"let a = URL(string: "https://example.org/x")!"#)
    XCTAssertEqual(found, ["example.org"])

    // Negative halves, and these are the ones that matter. A host named in a COMMENT must not
    // count as a link, or the retirement note in LegalLinks.swift would fail this suite forever
    // and the only way to green it would be to delete the explanation.
    XCTAssertEqual(linkedHosts(in: "// status.skyphusion.org was removed from the estate"), [])
    XCTAssertEqual(linkedHosts(in: "let s = \"not a url at all\""), [])
    XCTAssertEqual(linkedHosts(in: "mailto:support@skyphusion.org"), [])
  }

  func testControlTheFilesWereActuallyRead() throws {
    // The denominator. If a rename made these reads return empty, every assertion below would pass
    // for the wrong reason: an empty file names no bad host.
    let links = try source("App/LegalLinks.swift")
    let settings = try source("App/SettingsView.swift")
    XCTAssertGreaterThan(links.count, 500)
    XCTAssertGreaterThan(settings.count, 500)
    XCTAssertTrue(links.contains("enum LegalLinks"))
    XCTAssertTrue(settings.contains("LegalLinks."))
    // And the extractor really does see this file's own links, so a zero below is a real zero.
    XCTAssertTrue(linkedHosts(in: links).contains("skyphusion.org"))
  }

  // MARK: - The invariant

  func testEveryLinkedSkyphusionHostIsReviewed() throws {
    let source = try self.source("App/LegalLinks.swift")
    let hosts = linkedHosts(in: source)

    // The reviewed set, as measured live on 2026-09-26:
    //   skyphusion.org        200  (and /privacy.html 307 -> /privacy 200)
    //   play.skyphusion.org   200
    // Adding a host here is the review moment. It is not a list to grow without probing it first.
    let reviewed: Set<String> = ["skyphusion.org", "play.skyphusion.org"]
    let skyphusionHosts = hosts.filter { $0 == "skyphusion.org" || $0.hasSuffix(".skyphusion.org") }

    XCTAssertEqual(
      Set(skyphusionHosts), reviewed,
      "LegalLinks names \(hosts.count) hosts in total; the skyphusion.org ones must match the "
        + "reviewed set. Unreviewed: \(Set(skyphusionHosts).subtracting(reviewed)). "
        + "Missing: \(reviewed.subtracting(Set(skyphusionHosts)))."
    )
  }

  func testTheRetiredStatusHostIsGoneFromEveryUserFacingSurface() throws {
    // The named regression. Checked on both surfaces, because the constant and the row that renders
    // it were two separate edits and removing only one leaves either a dead tap or dead code.
    for path in ["App/LegalLinks.swift", "App/SettingsView.swift"] {
      let source = try self.source(path)
      XCTAssertFalse(
        linkedHosts(in: source).contains("status.skyphusion.org"),
        "\(path) still links status.skyphusion.org, which is NXDOMAIN"
      )
      XCTAssertFalse(
        source.contains("LegalLinks.status"),
        "\(path) still references LegalLinks.status"
      )
    }
  }
}
