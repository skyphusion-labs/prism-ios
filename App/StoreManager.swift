import Foundation
import PrismKit
import StoreKit

/// StoreKit 2 loader + purchase for control-plane credit packs.
///
/// Purchases are finished locally. Mapping a transaction to control-plane credit
/// is deferred until the plane store-receipt path is un-parked.
@MainActor
final class StoreManager: ObservableObject {
  @Published private(set) var products: [Product] = []
  @Published private(set) var isLoading: Bool = false
  @Published private(set) var isPurchasing: Bool = false
  @Published var statusMessage: String?
  @Published var errorMessage: String?
  @Published private(set) var lastTransactionId: String?

  private var updatesTask: Task<Void, Never>?

  init() {
    updatesTask = Task { await listenForTransactions() }
  }

  deinit {
    updatesTask?.cancel()
  }

  /// Products sorted low → high by display price when available.
  var sortedProducts: [Product] {
    products.sorted { a, b in
      a.price < b.price
    }
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
      errorMessage = error.localizedDescription
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
        await transaction.finish()
        let pack = StoreProducts.packs.first { $0.productId == product.id }
        let credit = pack.map { "\($0.creditUSD) USD intended" } ?? product.id
        statusMessage =
          "Purchase complete (\(credit)). Transaction \(transaction.id). Control-plane credit apply is not wired yet (plane receipt path deferred)."
        return true
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
      errorMessage = error.localizedDescription
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
        await transaction.finish()
      } catch {
        // Leave unfinished if verification fails; StoreKit will retry.
      }
    }
  }

  /// Intended credit USD for a product id, if known.
  func creditUSD(for productId: String) -> Int? {
    StoreProducts.packs.first { $0.productId == productId }?.creditUSD
  }
}
