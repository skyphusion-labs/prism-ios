import Foundation

/// Per-model video duration limits (mirror of plane `src/video-duration.ts`, CF docs 2026-08-06).
public struct VideoDurationLimits: Sendable, Equatable {
  public let min: Int
  public let max: Int
  public let defaultSeconds: Int
  /// When set, only these second values are legal (Veo, Hailuo, PixVerse v5.6).
  public let allowed: [Int]?

  public init(min: Int, max: Int, defaultSeconds: Int, allowed: [Int]? = nil) {
    self.min = min
    self.max = max
    self.defaultSeconds = defaultSeconds
    self.allowed = allowed
  }

  /// Discrete options for a UI picker (allowed list, or every second from min…max).
  public var pickerSeconds: [Int] {
    if let allowed, !allowed.isEmpty { return allowed.sorted() }
    // Cap continuous ranges at step 1; UI shows every second in range.
    if max - min > 20 {
      // Unlikely; still fine for 1–15/16.
    }
    return Array(min...max)
  }

  public func clamp(_ requested: Int?) -> Int {
    let base = requested ?? defaultSeconds
    if let allowed, !allowed.isEmpty {
      return allowed.min(by: { abs($0 - base) < abs($1 - base) }) ?? defaultSeconds
    }
    return Swift.min(max, Swift.max(min, base))
  }
}

public enum VideoDurationCatalog {
  /// Limits for a plane model id.
  public static func limits(for modelId: String) -> VideoDurationLimits {
    if modelId.hasPrefix("xai/grok-imagine-video") {
      return VideoDurationLimits(min: 1, max: 15, defaultSeconds: 5)
    }
    if modelId.hasPrefix("bytedance/seedance") {
      return VideoDurationLimits(min: 4, max: 12, defaultSeconds: 5)
    }
    if modelId.hasPrefix("google/veo") {
      return VideoDurationLimits(min: 4, max: 8, defaultSeconds: 8, allowed: [4, 6, 8])
    }
    if modelId.hasPrefix("minimax/hailuo") {
      return VideoDurationLimits(min: 6, max: 10, defaultSeconds: 6, allowed: [6, 10])
    }
    if modelId.hasPrefix("runwayml/") {
      return VideoDurationLimits(min: 2, max: 10, defaultSeconds: 5)
    }
    if modelId == "alibaba/hh1-t2v" || modelId == "alibaba/hh1-i2v"
      || modelId == "alibaba/hh1.1-t2v" || modelId == "alibaba/hh1.1-i2v"
    {
      return VideoDurationLimits(min: 3, max: 15, defaultSeconds: 5)
    }
    if modelId == "alibaba/wan-2.7-i2v" || modelId.hasPrefix("alibaba/wan") {
      return VideoDurationLimits(min: 2, max: 15, defaultSeconds: 5)
    }
    if modelId == "pixverse/v6" {
      return VideoDurationLimits(min: 1, max: 15, defaultSeconds: 5)
    }
    if modelId.hasPrefix("pixverse/") {
      return VideoDurationLimits(min: 5, max: 8, defaultSeconds: 5, allowed: [5, 8])
    }
    if modelId.hasPrefix("vidu/") {
      return VideoDurationLimits(min: 1, max: 16, defaultSeconds: 5)
    }
    return VideoDurationLimits(min: 1, max: 15, defaultSeconds: 5)
  }
}
