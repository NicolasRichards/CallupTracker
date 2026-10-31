import Foundation
import StoreKit

/// Loads and purchases the optional "buy us a coffee" tips.
///
/// The tips are consumable in-app purchases — nothing is unlocked, so there is
/// no entitlement to track. We just finish each transaction and show a thank-you.
@MainActor
@Observable
final class TipJar {
    static let productIDs = [
        "NickRichards.CallupTracker.tip.small",
        "NickRichards.CallupTracker.tip.medium",
        "NickRichards.CallupTracker.tip.large",
    ]

    /// Shared so the tip screen and the app-level transaction listener see the
    /// same state.
    static let shared = TipJar()

    /// Loaded products, sorted cheapest first.
    private(set) var products: [Product] = []
    private(set) var isLoading = false
    private(set) var purchasing: Product.ID?
    /// This session only: a tip unlocks nothing, so there's nothing to remember.
    private(set) var didTip = false
    /// Products whose purchase came back `.pending` (Ask to Buy) and await approval.
    private(set) var pendingApprovals: Set<Product.ID> = []
    /// The last purchase attempt threw or came back unverified — for example
    /// Screen Time blocks in-app purchases, or the connection dropped mid-purchase.
    private(set) var purchaseFailed = false
    private(set) var loadFailed = false

    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    var awaitingApproval: Bool { !pendingApprovals.isEmpty }

    private init() {
        // Older builds persisted didTip.
        UserDefaults.standard.removeObject(forKey: "tipJarDidTip")
    }

    /// Called each time the tip screen appears, and by its Retry button.
    func load() async {
        // A failure message belongs to the visit it happened in
        purchaseFailed = false
        guard products.count < Self.productIDs.count, !isLoading else { return }
        isLoading = true
        loadFailed = false
        defer { isLoading = false }
        do {
            let loaded = try await Product.products(for: Self.productIDs)
            if loaded.count >= products.count {
                products = loaded.sorted { $0.price < $1.price }
            }
            loadFailed = products.count < Self.productIDs.count
        } catch {
            loadFailed = true
        }
    }

    /// Starts the listener that finishes transactions completing outside the
    /// purchase call (Ask to Buy approvals, retries after an interruption).
    /// Called once from the App's init, so it lives as long as the app rather
    /// than a window, which matters on macOS where the app outlives its window.
    /// `Transaction` alone resolves to this app's own call-up transaction model,
    /// so StoreKit's has to be qualified here.
    func startListening() {
        guard updatesTask == nil else { return }
        updatesTask = Task {
            for await update in StoreKit.Transaction.updates {
                await handle(update)
            }
        }
    }

    private func handle(_ update: VerificationResult<StoreKit.Transaction>) async {
        let transaction = update.unsafePayloadValue
        // Finish unverified transactions too: a tip unlocks nothing, and an
        // unfinished transaction is redelivered on every launch.
        await transaction.finish()
        // Only thank someone waiting on an Ask to Buy approval. Anything else
        // here is a leftover StoreKit redelivered at launch, not a new tip.
        if case .verified = update, pendingApprovals.remove(transaction.productID) != nil {
            didTip = true
        }
    }

    func purchase(_ product: Product) async {
        guard purchasing == nil else { return }
        purchasing = product.id
        purchaseFailed = false
        defer { purchasing = nil }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                // Finished even if unverified, for the same reason as the listener.
                await verification.unsafePayloadValue.finish()
                if case .verified = verification {
                    pendingApprovals.remove(product.id)
                    didTip = true
                } else {
                    purchaseFailed = true
                }
            case .pending:
                pendingApprovals.insert(product.id)
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch StoreKitError.userCancelled {
            // Cancelling the Apple Account sign-in arrives as a thrown error
            // rather than a .userCancelled result; it isn't a failure either way
        } catch {
            purchaseFailed = true
        }
    }
}
