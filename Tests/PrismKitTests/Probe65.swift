import XCTest
@testable import PrismKit
import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// TEMPORARY PROBE for ios#65, pushed on a throwaway branch to record the defect on `main` and
/// then deleted. It asserts the CONFLATION: when the poll deadline elapses with the job still
/// running, `waitForJob` returns a value that the app's own predicate cannot tell apart from a
/// failed job. This probe PASSING is the evidence the bug is real.
///
/// After the fix this test cannot be written at all: `waitForJob` returns `JobWaitOutcome`, so
/// there is no `.isSuccess` on a timeout to be wrong about.
final class Probe65Tests: XCTestCase {
  final class Counter: @unchecked Sendable { var n = 0 }

  override func tearDown() {
    MockURLProtocol.handler = nil
    super.tearDown()
  }

  private func makeClient() -> ControlPlaneClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)
    let http = HTTPClient(baseURL: URL(string: "https://proxy.example.com")!, session: session)
    return ControlPlaneClient(http: http, clientKey: "pcp_test")
  }

  func testTimeoutReturnsARunningJobThatLooksFailed() async throws {
    let polls = Counter()
    MockURLProtocol.handler = { _ in
      polls.n += 1
      let body = #"{"id":"job_1","kind":"image","model":"openai/gpt-image-2","status":"running"}"#
      return (200, body.data(using: .utf8)!, ["Content-Type": "application/json"])
    }
    let job = try await makeClient().waitForJob(id: "job_1", pollInterval: 0.05, timeout: 0.4)
    XCTAssertGreaterThan(polls.n, 1, "the probe must actually have polled more than once")
    XCTAssertFalse(job.isTerminal, "the job is still running on the plane")
    // THE DEFECT. This is the predicate AppState.finishImageJob branches on, and it is false for a
    // job that is merely still running -- so that branch clears the pending id and the paid job is
    // orphaned.
    XCTAssertFalse(job.isSuccess, "a still-running job is indistinguishable from a failed one here")
  }
}
