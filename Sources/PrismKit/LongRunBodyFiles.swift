import Foundation

/// Naming and cleanup for the temp files that carry a background upload's request body.
///
/// A background `URLSession` cannot take an in-memory `httpBody`, so `LongRunningURLSession`
/// writes the body -- prompt text, and the base64 reference image when there is one -- to a file
/// under `tmp/` and unlinks it in `didCompleteWithError`. That unlink reads the URL out of the
/// in-memory `pending` dictionary, so when the app is killed mid-transfer the resurrected session
/// has no entry for the task, returns early, and the file is never removed.
///
/// Deleting on the way OUT cannot fix that: at the moment it matters there is no process left to
/// do the deleting. So the sweep happens on the way IN, when the session is constructed, with an
/// age floor.
///
/// This lives outside the `#if os(iOS)` session class deliberately. The session cannot be
/// compiled on Linux, and a fix nothing can compile is a fix nothing can test; splitting the
/// filesystem half out gives CI something real to run.
public enum LongRunBodyFiles {
  public static let prefix = "prism-longrun-"
  public static let fileExtension = "body"

  /// Anything older than this cannot belong to a live transfer: the session sets
  /// `timeoutIntervalForResource = 900`, so an hour is well past the last moment a body file can
  /// still be in use. The asymmetry is deliberate -- erring long costs a little disk, erring
  /// short deletes the body out from under a running upload.
  public static let staleAfter: TimeInterval = 3600

  /// Name for a fresh body file. One definition, so the sweep cannot drift from the writer.
  public static func newFileName(id: String = UUID().uuidString) -> String {
    "\(prefix)\(id).\(fileExtension)"
  }

  /// Whether `name` is one of ours. Deliberately anchored at both ends: a prefix test alone would
  /// also claim files some future feature names similarly.
  public static func isBodyFile(_ name: String) -> Bool {
    name.hasPrefix(prefix) && name.hasSuffix(".\(fileExtension)")
  }

  /// Delete orphaned body files in `directory` last modified more than `olderThan` before `now`.
  ///
  /// Returns the names removed, so a caller or a test can assert on the population rather than on
  /// the absence of a complaint: a sweep that reports nothing is indistinguishable from a sweep
  /// that matched nothing.
  @discardableResult
  public static func purgeStale(
    in directory: URL,
    olderThan: TimeInterval = staleAfter,
    now: Date = Date(),
    fileManager: FileManager = .default
  ) -> [String] {
    guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else {
      return []
    }
    var removed: [String] = []
    for name in names where isBodyFile(name) {
      let path = directory.appendingPathComponent(name).path
      guard
        let attrs = try? fileManager.attributesOfItem(atPath: path),
        let modified = attrs[.modificationDate] as? Date,
        now.timeIntervalSince(modified) > olderThan
      else { continue }
      do {
        try fileManager.removeItem(atPath: path)
        removed.append(name)
      } catch {
        continue
      }
    }
    return removed.sorted()
  }
}
