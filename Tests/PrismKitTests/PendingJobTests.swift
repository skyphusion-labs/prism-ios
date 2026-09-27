import XCTest
@testable import PrismKit
import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// ios#65: a paid job orphaned on poll timeout, then paid for again by Retry.
///
/// The bar these tests answer: simulate a poll whose deadline elapses while the job is still
/// running, and assert the pending id SURVIVES and a new submit is refused.
///
/// On the timeout: the shipped deadline is 420s, which no test should sit through. What the code
/// actually branches on is "the deadline elapsed while status was still running", and a short
/// timeout reproduces that state exactly. The tests below assert they really did poll more than
/// once, so a zero-poll fast path cannot masquerade as a pass.
final class PendingJobWaitTests: XCTestCase {
  /// Reference type so the mock handler can count calls without capturing a mutable local.
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

  private func runningJobHandler(_ polls: Counter) {
    MockURLProtocol.handler = { _ in
      polls.n += 1
      let body = #"{"id":"job_1","kind":"image","model":"openai/gpt-image-2","status":"running"}"#
      return (200, body.data(using: .utf8)!, ["Content-Type": "application/json"])
    }
  }

  // MARK: - the wait itself

  func testDeadlineWithJobStillRunningIsStillRunningNotFinished() async throws {
    let polls = Counter()
    runningJobHandler(polls)
    let outcome = try await makeClient().waitForJob(id: "job_1", pollInterval: 0.05, timeout: 0.4)
    XCTAssertGreaterThan(polls.n, 1, "the wait must actually have polled; a no-poll pass proves nothing")
    guard case .stillRunning(let last) = outcome else {
      return XCTFail("a timed-out wait reported itself as finished, which is the whole defect")
    }
    XCTAssertEqual(last?.status, "running")
    // And it must not be able to pose as a success anywhere downstream.
    XCTAssertFalse(outcome.isSuccess)
    XCTAssertNil(outcome.finishedJob)
  }

  func testTerminalJobIsFinished() async throws {
    MockURLProtocol.handler = { _ in
      let body = #"{"id":"job_1","kind":"image","status":"succeeded","result":{"data":[{"url":"https://x/y.png"}]}}"#
      return (200, body.data(using: .utf8)!, ["Content-Type": "application/json"])
    }
    let outcome = try await makeClient().waitForJob(id: "job_1", pollInterval: 0.05, timeout: 5)
    guard case .finished(let job) = outcome else { return XCTFail("a succeeded job must be .finished") }
    XCTAssertTrue(job.isSuccess)
    XCTAssertTrue(outcome.isSuccess)
  }

  func testTerminalFailureIsAlsoFinished() async throws {
    MockURLProtocol.handler = { _ in
      let body = #"{"id":"job_1","kind":"image","status":"failed","error":{"code":"provider_error"}}"#
      return (200, body.data(using: .utf8)!, ["Content-Type": "application/json"])
    }
    let outcome = try await makeClient().waitForJob(id: "job_1", pollInterval: 0.05, timeout: 5)
    guard case .finished(let job) = outcome else { return XCTFail("a failed job is a CONCLUSION") }
    XCTAssertFalse(job.isSuccess)
    // A real failure is conclusive, so this is the one case where dropping the id is correct.
    XCTAssertEqual(PendingJobPolicy.disposition(after: outcome), .clear)
  }

  // MARK: - the policy: what may be forgotten

  func testTimeoutKeepsTheJobId() async throws {
    let polls = Counter()
    runningJobHandler(polls)
    let outcome = try await makeClient().waitForJob(id: "job_1", pollInterval: 0.05, timeout: 0.4)
    XCTAssertEqual(PendingJobPolicy.disposition(after: outcome), .keep)
  }

  func testInconclusiveErrorsKeepTheJobId() {
    XCTAssertEqual(PendingJobPolicy.disposition(afterError: CancellationError()), .keep)
    XCTAssertEqual(PendingJobPolicy.disposition(afterError: PrismError.cancelled), .keep)
    XCTAssertEqual(PendingJobPolicy.disposition(afterError: PrismError.transport("radio dropped")), .keep)
    // Built as an NSError rather than URLError so the domain/code are unambiguous on Linux CI,
    // where the classifier does its `as NSError` bridge through swift-corelibs Foundation.
    let connectionLost = NSError(domain: NSURLErrorDomain, code: NSURLErrorNetworkConnectionLost)
    XCTAssertEqual(
      PendingJobPolicy.disposition(afterError: connectionLost),
      .keep,
      "a dropped connection says nothing about the job on the plane"
    )
  }

  func testAConclusiveServerErrorClearsTheJobId() {
    XCTAssertEqual(
      PendingJobPolicy.disposition(afterError: PrismError.serverError("Image job failed")),
      .clear
    )
  }

  // MARK: - the end-to-end bar, against a real store

  /// The scenario from the issue, driven through the real client, the real policy and the real
  /// SecretStore: submit accepted, poll times out with the job still running, and afterwards the
  /// id is STILL THERE and a second paid submit is refused.
  func testOrphanScenarioKeepsIdAndRefusesASecondSubmit() async throws {
    let store = MemorySecretStore()
    let key = SecretStoreKeys.pendingImageJobId
    try store.set("job_1", for: key)

    let polls = Counter()
    runningJobHandler(polls)
    let outcome = try await makeClient().waitForJob(id: "job_1", pollInterval: 0.05, timeout: 0.4)

    // What the app does with the outcome, using the shared policy rather than a local guess.
    if PendingJobPolicy.disposition(after: outcome) == .clear {
      try store.set(nil, for: key)
    }

    XCTAssertGreaterThan(polls.n, 1)
    XCTAssertEqual(try store.get(key), "job_1", "the paid job id was thrown away; it is unrecoverable")
    XCTAssertFalse(
      PendingJobPolicy.maySubmitNewJob(pendingId: try store.get(key)),
      "Retry would submit a SECOND paid job while the first is still running"
    )
  }

  func testASucceededJobReleasesTheIdAndAllowsTheNextSubmit() async throws {
    let store = MemorySecretStore()
    let key = SecretStoreKeys.pendingImageJobId
    try store.set("job_1", for: key)

    MockURLProtocol.handler = { _ in
      let body = #"{"id":"job_1","kind":"image","status":"succeeded","result":{"data":[{"url":"https://x/y.png"}]}}"#
      return (200, body.data(using: .utf8)!, ["Content-Type": "application/json"])
    }
    let outcome = try await makeClient().waitForJob(id: "job_1", pollInterval: 0.05, timeout: 5)
    if PendingJobPolicy.disposition(after: outcome) == .clear {
      try store.set(nil, for: key)
    }
    XCTAssertNil(try store.get(key), "a collected job must not block the next one forever")
    XCTAssertTrue(PendingJobPolicy.maySubmitNewJob(pendingId: try store.get(key)))
  }

  func testSubmitGateTreatsBlankAsNoPendingJob() {
    XCTAssertTrue(PendingJobPolicy.maySubmitNewJob(pendingId: nil))
    XCTAssertTrue(PendingJobPolicy.maySubmitNewJob(pendingId: ""))
    XCTAssertTrue(PendingJobPolicy.maySubmitNewJob(pendingId: "   "))
    XCTAssertFalse(PendingJobPolicy.maySubmitNewJob(pendingId: "job_1"))
  }
}
