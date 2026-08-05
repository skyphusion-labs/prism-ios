import Foundation

/// App Store Connect product catalog for Prism credit top-ups.
///
/// Live app id: `6798391677` (bundle `org.skyphusion.prism`).
/// Server-side redeem of purchases is still deferred on the control-plane contract
/// (store-receipt path parked). Product IDs and StoreKit Configuration are ready for
/// client purchase UI + local testing.
public enum StoreProducts {
  /// App Store Connect app resource id.
  public static let appStoreConnectAppId = "6798391677"

  /// Consumable credit packs (USD list price ≈ credit grant intent).
  public static let credit5 = "org.skyphusion.prism.credit.5"
  public static let credit20 = "org.skyphusion.prism.credit.20"
  public static let credit50 = "org.skyphusion.prism.credit.50"

  /// All known product ids (order: low → high).
  public static let allCreditPacks: [String] = [credit5, credit20, credit50]

  public struct CreditPack: Sendable, Equatable, Identifiable {
    public var id: String { productId }
    public let productId: String
    /// Intended prepaid credit in whole USD (matches product id suffix).
    public let creditUSD: Int
    public let referenceName: String

    public init(productId: String, creditUSD: Int, referenceName: String) {
      self.productId = productId
      self.creditUSD = creditUSD
      self.referenceName = referenceName
    }
  }

  public static let packs: [CreditPack] = [
    CreditPack(productId: credit5, creditUSD: 5, referenceName: "Credit 5 USD"),
    CreditPack(productId: credit20, creditUSD: 20, referenceName: "Credit 20 USD"),
    CreditPack(productId: credit50, creditUSD: 50, referenceName: "Credit 50 USD"),
  ]
}
