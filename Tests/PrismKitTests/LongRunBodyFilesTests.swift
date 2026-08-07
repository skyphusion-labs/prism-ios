import XCTest
@testable import PrismKit
import Foundation

/// prism-ios#49 F4.
///
/// These run on Linux CI against a real temp directory, not a stub: the defect is a file that
/// outlives its transfer, so the subject has to be a file.
final class LongRunBodyFilesTests: XCTestCase {
  private var dir: URL!

  override func setUpWithError() throws {
    dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("prism-longrun-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: dir)
  }

  private func write(_ name: String, ageSeconds: TimeInterval) throws {
    let url = dir.appendingPathComponent(name)
    try Data("body".utf8).write(to: url)
    try FileManager.default.setAttributes(
      [.modificationDate: Date().addingTimeInterval(-ageSeconds)],
      ofItemAtPath: url.path
    )
  }

  private func names() throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
  }

  /// The writer and the sweeper must agree on what a body file is called. If this fails, the
  /// sweep is looking for files nothing produces, which is a matcher anchored to nothing.
  func testTheWritersNameIsRecognisedBySweeper() {
    let name = LongRunBodyFiles.newFileName()
    XCTAssertTrue(LongRunBodyFiles.isBodyFile(name), "sweeper does not recognise \(name)")
    XCTAssertTrue(name.hasPrefix("prism-longrun-"))
    XCTAssertTrue(name.hasSuffix(".body"))
    XCTAssertNotEqual(LongRunBodyFiles.newFileName(), LongRunBodyFiles.newFileName())
  }

  /// POSITIVE CONTROL for every "nothing was removed" assertion below: the sweep can remove.
  func testStaleBodyFileIsRemoved() throws {
    try write(LongRunBodyFiles.newFileName(id: "orphan"), ageSeconds: 7200)
    let removed = LongRunBodyFiles.purgeStale(in: dir)
    XCTAssertEqual(removed, ["prism-longrun-orphan.body"])
    XCTAssertEqual(try names(), [])
  }

  /// The failure that would matter: deleting the body of a transfer still running.
  func testFreshBodyFileIsLeftAlone() throws {
    try write(LongRunBodyFiles.newFileName(id: "inflight"), ageSeconds: 60)
    let removed = LongRunBodyFiles.purgeStale(in: dir)
    XCTAssertEqual(removed, [])
    XCTAssertEqual(try names(), ["prism-longrun-inflight.body"])
  }

  func testUnrelatedFilesAreNeverTouched() throws {
    try write("some-other-cache.body", ageSeconds: 7200)
    try write("prism-longrun-notours.tmp", ageSeconds: 7200)
    try write(LongRunBodyFiles.newFileName(id: "mine"), ageSeconds: 7200)
    let removed = LongRunBodyFiles.purgeStale(in: dir)
    XCTAssertEqual(removed, ["prism-longrun-mine.body"])
    XCTAssertEqual(try names(), ["prism-longrun-notours.tmp", "some-other-cache.body"])
  }

  func testAgeBoundaryUsesTheSuppliedClock() throws {
    try write(LongRunBodyFiles.newFileName(id: "edge"), ageSeconds: 1000)
    XCTAssertEqual(LongRunBodyFiles.purgeStale(in: dir, olderThan: 2000), [])
    XCTAssertEqual(LongRunBodyFiles.purgeStale(in: dir, olderThan: 500), ["prism-longrun-edge.body"])
  }

  /// A missing directory must return empty rather than trap; the sweep runs at session
  /// construction, where throwing would take the whole feature down.
  func testMissingDirectoryIsEmptyNotFatal() {
    let gone = dir.appendingPathComponent("does-not-exist")
    XCTAssertEqual(LongRunBodyFiles.purgeStale(in: gone), [])
  }
}
