/// PrismKit -- shared Swift package for Prism iOS (and macOS) clients.
///
/// Two backends:
/// - ``PrismClient`` -- playground Worker (public signup + session cookie, or Access headers)
/// - ``ControlPlaneClient`` -- commercial plane (`Bearer pcp_…` device key)
///
/// Package version tracks semantic releases of this library (not the Worker version).
public enum PrismKit {
  public static let name = "PrismKit"
  /// Library semver (keep in step with git tags / future releases).
  public static let version = "0.6.1"

  public static func health() -> String {
    "ok:\(name)"
  }
}
