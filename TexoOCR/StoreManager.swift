import Foundation
import StoreKit

@MainActor
class StoreManager: ObservableObject {
    static let shared = StoreManager()
    static let productID = "com.zclk9000.texoocr.pro"
    static let dailyLimit = 20

    @Published var isPro = false
    @Published var todayUsageCount = 0

    @AppStorage("usageDate") private var usageDate: String = ""
    @AppStorage("usageCount") private var storedUsageCount: Int = 0

    var remainingToday: Int {
        max(0, Self.dailyLimit - todayUsageCount)
    }

    var canUse: Bool {
        isPro || todayUsageCount < Self.dailyLimit
    }

    private init() {
        loadDailyUsage()
        Task { await checkEntitlement() }
        listenForTransactions()
    }

    // MARK: - Daily Usage

    private func todayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private func loadDailyUsage() {
        let today = todayString()
        if usageDate == today {
            todayUsageCount = storedUsageCount
        } else {
            // New day, reset counter
            usageDate = today
            storedUsageCount = 0
            todayUsageCount = 0
        }
    }

    func recordUsage() {
        let today = todayString()
        if usageDate != today {
            usageDate = today
            storedUsageCount = 0
            todayUsageCount = 0
        }
        storedUsageCount += 1
        todayUsageCount = storedUsageCount
    }

    // MARK: - StoreKit

    private func checkEntitlement() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.productID {
                isPro = true
                return
            }
        }
    }

    private func listenForTransactions() {
        Task.detached {
            for await result in Transaction.updates {
                if case .verified(let transaction) = result,
                   transaction.productID == Self.productID {
                    await MainActor.run { self.isPro = true }
                    await transaction.finish()
                }
            }
        }
    }

    func purchase() async throws {
        let products = try await Product.products(for: [Self.productID])
        guard let product = products.first else {
            throw StoreError.productNotFound
        }

        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            if case .verified(let transaction) = verification {
                isPro = true
                await transaction.finish()
            }
        case .userCancelled:
            break
        case .pending:
            break
        @unknown default:
            break
        }
    }

    func restorePurchases() async {
        try? await AppStore.sync()
        await checkEntitlement()
    }

    enum StoreError: LocalizedError {
        case productNotFound
        var errorDescription: String? { "Product not found" }
    }
}
