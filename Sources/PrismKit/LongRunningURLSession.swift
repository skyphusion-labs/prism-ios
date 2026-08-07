import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Best-effort system-managed transfers for long non-chat POSTs on iOS.
///
/// A normal `URLSession` data task dies when the process suspends after
/// `beginBackgroundTask` expires (~30s on lock/home). A **background** session
/// can continue **active** transfers under the OS. That helps brief
/// backgrounding and real upload/download progress; it does **not** make a
/// multi-minute **idle** server wait (sync video/music generation) reliably
/// lock-safe. True lock survival needs async jobs + poll on the plane.
///
/// Not available on Linux CI; callers fall back to the foreground session.
/// Background sessions reject custom `URLProtocol` mocks -- tests keep
/// `preferBackground: false` (default).
#if os(iOS)
public final class LongRunningURLSession: NSObject, URLSessionTaskDelegate, URLSessionDataDelegate,
  URLSessionDownloadDelegate, @unchecked Sendable
{
  public static let shared = LongRunningURLSession()

  /// Stable identifier; must match `handleEventsForBackgroundURLSession` in the app.
  public static let identifier = "org.skyphusion.prism.longrun"

  private var session: URLSession!
  private struct Pending {
    var chunks = Data()
    var response: URLResponse?
    var bodyFileURL: URL?
    var continuation: CheckedContinuation<(Data, URLResponse), Error>?
  }

  private var pending: [Int: Pending] = [:]
  private let lock = NSLock()
  private var backgroundEventsCompletion: (() -> Void)?

  private override init() {
    super.init()
    // Body files are unlinked in `didCompleteWithError`, which reads the URL out of `pending`.
    // A process killed mid-transfer comes back with `pending` empty, so that unlink never runs
    // and the file -- prompt plus any base64 reference image -- stays in `tmp/`. Nothing else
    // ever removes it, so the sweep has to happen on the way in. See prism-ios#49 F4.
    LongRunBodyFiles.purgeStale(in: FileManager.default.temporaryDirectory)
    let config = URLSessionConfiguration.background(withIdentifier: Self.identifier)
    // User-initiated gens: start immediately, do not wait for "optimal" conditions.
    config.isDiscretionary = false
    config.sessionSendsLaunchEvents = true
    config.shouldUseExtendedBackgroundIdleMode = true
    config.waitsForConnectivity = true
    // Plane nonchat hard max is 360s; music + rehost can push a bit past that.
    config.timeoutIntervalForRequest = 420
    config.timeoutIntervalForResource = 900
    config.httpAdditionalHeaders = ["Accept": "application/json"]
    let queue = OperationQueue()
    queue.name = "org.skyphusion.prism.longrun"
    queue.maxConcurrentOperationCount = 1
    session = URLSession(configuration: config, delegate: self, delegateQueue: queue)
  }

  /// Called from `UIApplicationDelegate.application(_:handleEventsForBackgroundURLSession:)`.
  public func setBackgroundEventsCompletionHandler(_ handler: @escaping () -> Void) {
    lock.lock()
    backgroundEventsCompletion = handler
    lock.unlock()
  }

  /// Perform a request via background upload (body) or download (no body).
  public func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
    var req = request
    // Background sessions require file-based upload bodies (not in-memory httpBody).
    var bodyFile: URL?
    if let body = req.httpBody, !body.isEmpty {
      let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(LongRunBodyFiles.newFileName())
      try body.write(to: url, options: .atomic)
      bodyFile = url
      req.httpBody = nil
    }

    return try await withCheckedThrowingContinuation { cont in
      let task: URLSessionTask
      if let bodyFile {
        task = session.uploadTask(with: req, fromFile: bodyFile)
      } else {
        // GET/DELETE etc.: download task (background-safe).
        task = session.downloadTask(with: req)
      }
      lock.lock()
      pending[task.taskIdentifier] = Pending(
        bodyFileURL: bodyFile,
        continuation: cont
      )
      lock.unlock()
      task.resume()
    }
  }

  // MARK: - URLSessionDataDelegate (upload response body)

  public func urlSession(
    _ session: URLSession,
    dataTask: URLSessionDataTask,
    didReceive response: URLResponse,
    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
  ) {
    lock.lock()
    pending[dataTask.taskIdentifier]?.response = response
    lock.unlock()
    completionHandler(.allow)
  }

  public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    lock.lock()
    pending[dataTask.taskIdentifier]?.chunks.append(data)
    lock.unlock()
  }

  // MARK: - URLSessionDownloadDelegate (no-body requests)

  public func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    let data = (try? Data(contentsOf: location)) ?? Data()
    lock.lock()
    if var p = pending[downloadTask.taskIdentifier] {
      p.chunks = data
      p.response = downloadTask.response
      pending[downloadTask.taskIdentifier] = p
    }
    lock.unlock()
  }

  // MARK: - URLSessionTaskDelegate

  public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    lock.lock()
    guard let p = pending.removeValue(forKey: task.taskIdentifier) else {
      lock.unlock()
      return
    }
    lock.unlock()

    if let bodyFile = p.bodyFileURL {
      try? FileManager.default.removeItem(at: bodyFile)
    }

    if let error {
      p.continuation?.resume(throwing: error)
      return
    }
    let response = p.response ?? task.response
    guard let response else {
      p.continuation?.resume(throwing: URLError(.badServerResponse))
      return
    }
    p.continuation?.resume(returning: (p.chunks, response))
  }

  public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    lock.lock()
    let handler = backgroundEventsCompletion
    backgroundEventsCompletion = nil
    lock.unlock()
    if let handler {
      DispatchQueue.main.async { handler() }
    }
  }
}
#endif
