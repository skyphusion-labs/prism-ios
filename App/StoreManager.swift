import Foundation
import PrismKit
import StoreKit

/// StoreKit 2 loader + purchase; redeems via control plane after verification.
@MainActor
final class StoreManager: ObservableObject {
  @Published private(set) var products: [Product] = []
  @Published private(set) var isLoading: Bool = false
  @Published private(set) var isPurchasing: Bool = false
  @Published var statusMessage: String?
  @Published var errorMessage: String?
  @Published private(set) var lastTransactionId: String?

  /// Injected when Settings attaches; used to redeem after purchase.
  var redeemHandler: ((String) async throws -> StoreRedeemResponse)?
  var onRedeemed: (() async -> Void)?

  private var updatesTask: Task<Void, Never>?

  init() {
    updatesTask = Task { await listenForTransactions() }
  }

  deinit {
    updatesTask?.cancel()
  }

  var sortedProducts: [Product] {
    products.sorted { a, b in a.price < b.price }
  }

  func loadProducts() async {
    isLoading = true
    errorMessage = nil
    defer { isLoading = false }
    do {
      let ids = Set(StoreProducts.allCreditPacks)
      let loaded = try await Product.products(for: ids)
      products = loaded
      if loaded.isEmpty {
        statusMessage =
          "No products returned. Use Configuration.storekit in the scheme for local testing, or wait for ASC products to clear review."
      } else {
        statusMessage = "\(loaded.count) credit pack(s) available"
      }
    } catch {
      errorMessage = prismUserFacingError(error)
      products = []
    }
  }

  @discardableResult
  func purchase(_ product: Product) async -> Bool {
    isPurchasing = true
    errorMessage = nil
    statusMessage = nil
    defer { isPurchasing = false }
    do {
      let result = try await product.purchase()
      switch result {
      case .success(let verification):
        let transaction = try checkVerified(verification)
        lastTransactionId = String(transaction.id)
        // JWS lives on VerificationResult (StoreKit 2), not Transaction.
        let ok = await redeemAndFinish(transaction, jws: verification.jwsRepresentation)
        return ok
      case .userCancelled:
        statusMessage = "Purchase cancelled"
        return false
      case .pending:
        statusMessage = "Purchase pending approval"
        return false
      @unknown default:
        statusMessage = "Unknown purchase result"
        return false
      }
    } catch {
      errorMessage = prismUserFacingError(error)
      return false
    }
  }

  private func redeemAndFinish(_ transaction: Transaction, jws: String) async -> Bool {
    guard let redeemHandler else {
      // No plane handler: finish so StoreKit does not loop; credit not applied.
      await transaction.finish()
      statusMessage =
        "Purchase recorded locally (tx \(transaction.id)) but control plane redeem is not attached. Open Settings on Control plane."
      return false
    }
    do {
      let res = try await redeemHandler(jws)
      await transaction.finish()
      let usd: String
      if let m = res.credit_granted_micro_usd, res.applied == true {
        usd = String(format: "$%.0f", Double(m) / 1_000_000.0)
      } else if let pack = StoreProducts.packs.first(where: { $0.productId == transaction.productID }) {
        usd = "\(pack.creditUSD) USD"
      } else {
        usd = transaction.productID
      }
      if res.applied == true {
        statusMessage = "Credit applied (\(usd)). Balance refresh…"
      } else {
        statusMessage = "Already redeemed (tx \(transaction.id)). Balance refresh…"
      }
      await onRedeemed?()
      return true
    } catch {
      // Do not finish on redeem failure — StoreKit will redeliver via Transaction.updates.
      errorMessage = prismUserFacingError(error)
      statusMessage = "Purchase verified; credit apply failed. Will retry."
      return false
    }
  }

  private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
    switch result {
    case .unverified(_, let error):
      throw error
    case .verified(let safe):
      return safe
    }
  }

  private func listenForTransactions() async {
    for await update in Transaction.updates {
      do {
        let transaction = try checkVerified(update)
        lastTransactionId = String(transaction.id)
        _ = await redeemAndFinish(transaction, jws: update.jwsRepresentation)
      } catch {
        // Leave unfinished if verification fails; StoreKit will retry.
      }
    }
  }

  func creditUSD(for productId: String) -> Int? {
    StoreProducts.packs.first { $0.productId == productId }?.creditUSD
  }
}
