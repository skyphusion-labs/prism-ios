import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Incremental SSE reader for chat streams.
public enum SSEStream {
  /// Consume an SSE body as it arrives and yield parsed ``ChatStreamEvent``s.
  ///
  /// On Apple platforms uses `URLSession.bytes`. On Linux (CI) falls back to a
  /// full-body read then parse (FoundationNetworking has no async bytes API).
  public static func chatEvents(
    session: URLSession,
    request: URLRequest
  ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          #if canImport(Darwin)
          try await streamApple(session: session, request: request, continuation: continuation)
          #else
          try await streamBuffered(session: session, request: request, continuation: continuation)
          #endif
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  #if canImport(Darwin)
  private static func streamApple(
    session: URLSession,
    request: URLRequest,
    continuation: AsyncThrowingStream<ChatStreamEvent, Error>.Continuation
  ) async throws {
    let (bytes, response) = try await session.bytes(for: request)
    if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
      var data = Data()
      for try await b in bytes { data.append(b) }
      let message = HTTPClient.extractErrorMessage(data)
      if http.statusCode == 401 { throw PrismError.unauthenticated }
      throw PrismError.httpStatus(http.statusCode, message: message)
    }

    var carry = ""
    for try await line in bytes.lines {
      if Task.isCancelled { break }
      if line.isEmpty {
        let events = SSEParser.parseChatEvents(from: carry + "\n\n")
        carry = ""
        for e in events {
          continuation.yield(e)
          if case .error(let m) = e {
            throw PrismError.serverError(m)
          }
        }
        continue
      }
      if carry.isEmpty {
        carry = line
      } else {
        carry += "\n" + line
      }
      // Incomplete frame: keep accumulating until blank line.
      if line.hasPrefix("data:") == false, !line.hasPrefix(":"), !line.hasPrefix("event:") {
        // still accumulate
      }
    }
    if !carry.isEmpty {
      for e in SSEParser.parseChatEvents(from: carry + "\n\n") {
        continuation.yield(e)
      }
    }
  }
  #endif

  private static func streamBuffered(
    session: URLSession,
    request: URLRequest,
    continuation: AsyncThrowingStream<ChatStreamEvent, Error>.Continuation
  ) async throws {
    let (data, response): (Data, URLResponse) = try await withCheckedThrowingContinuation { cont in
      let task = session.dataTask(with: request) { data, response, error in
        if let error { cont.resume(throwing: error); return }
        guard let data, let response else {
          cont.resume(throwing: URLError(.badServerResponse))
          return
        }
        cont.resume(returning: (data, response))
      }
      task.resume()
    }
    if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
      let message = HTTPClient.extractErrorMessage(data)
      if http.statusCode == 401 { throw PrismError.unauthenticated }
      throw PrismError.httpStatus(http.statusCode, message: message)
    }
    let text = String(data: data, encoding: .utf8) ?? ""
    for e in SSEParser.parseChatEvents(from: text) {
      continuation.yield(e)
      if case .error(let m) = e {
        throw PrismError.serverError(m)
      }
    }
  }
}
