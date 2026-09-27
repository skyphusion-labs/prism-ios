import Foundation

// Async plane jobs are PAID. Once the plane has accepted one, the job id is the only handle the
// client has on work that is already costing money, so the rule that governs this file is:
//
//   a pending job id may be discarded ONLY on a conclusive, terminal outcome.
//
// ios#65: `waitForJob` used to return the LAST JOB IT SAW when its deadline elapsed, which at the
// call site is indistinguishable from the FINAL job. Two callers (image, video) then made a
// terminal decision on an inconclusive result and cleared the id, so a job that finished later was
// billed with nobody holding its handle: no reconcile, no resume, and a Retry button that
// submitted -- and paid for -- a second one. Clearing the id is the irreversible step.
//
// The fix is a type, not a rule someone has to remember. `waitForJob` returns `JobWaitOutcome`, so
// "I gave up waiting" is not expressible as "it finished", and every caller has to say which case
// it is handling.

/// How a bounded wait on an async plane job ended.
///
/// The distinction is the point: `.finished` is a CONCLUSION from the plane, `.stillRunning` is the
/// client giving up on the clock. Only the first justifies discarding the job id.
public enum JobWaitOutcome: Sendable, Equatable {
  /// The plane reported a terminal status (`succeeded` or `failed`). This is a real answer.
  case finished(AsyncJobResponse)

  /// The deadline elapsed while the job was still running. Carries the last observed state, which
  /// is `nil` when the deadline passed before any poll was observed. NOT an answer, and never a
  /// failure: the plane is probably still working, and still billing.
  case stillRunning(last: AsyncJobResponse?)

  /// The terminal job, or `nil` when the wait was inconclusive.
  public var finishedJob: AsyncJobResponse? {
    if case .finished(let job) = self { return job }
    return nil
  }

  /// The last state seen, terminal or not. For status text only; never for a keep/clear decision.
  public var lastObserved: AsyncJobResponse? {
    switch self {
    case .finished(let job): return job
    case .stillRunning(let last): return last
    }
  }

  /// True only when the plane said `succeeded`. A timeout is never a success.
  public var isSuccess: Bool { finishedJob?.isSuccess ?? false }
}

/// What to do with the stored job id once a wait or a thrown error has been classified.
public enum PendingJobDisposition: Sendable, Equatable {
  /// The outcome was conclusive; the id has been spent and may be forgotten.
  case clear
  /// Inconclusive. The plane may still be working on paid work: KEEP the id so the next
  /// foreground force-sync can resume it.
  case keep
}

/// The keep/clear policy, in one place, as pure functions.
///
/// It lives in PrismKit rather than in the app so it is reachable from `swift test`. The bug this
/// replaces was a policy decision scattered across four call sites, where two of them got it right
/// (music, speech) and two got it wrong (image, video) and nothing could tell.
public enum PendingJobPolicy {
  /// A job id may be dropped only on a terminal outcome.
  public static func disposition(after outcome: JobWaitOutcome) -> PendingJobDisposition {
    switch outcome {
    case .finished: return .clear
    case .stillRunning: return .keep
    }
  }

  /// Disposition for a thrown error while a job was outstanding.
  ///
  /// Deliberately asymmetric, because the two mistakes do not cost the same. Dropping the id of a
  /// live paid job is unrecoverable and bills the user twice; keeping the id of a job that is
  /// genuinely gone costs one wasted `GET /v1/jobs/:id` on next foreground, which then resolves it.
  /// So anything not positively known to be terminal is kept.
  public static func disposition(afterError error: Error) -> PendingJobDisposition {
    if error is CancellationError { return .keep }
    if prismIsSuspendOrNetworkError(error) { return .keep }
    return .clear
  }

  /// Whether a NEW paid job may be submitted. False while an id is outstanding: that is the Retry
  /// double-charge. The caller should offer to check the existing job instead.
  public static func maySubmitNewJob(pendingId: String?) -> Bool {
    guard let id = pendingId else { return true }
    return id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}
