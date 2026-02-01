import Foundation
import StoreKit

// MARK: - Errors

/// Typed errors for OpenCat SDK operations.
public enum OpenCatError: Error, Sendable {
    case notConfigured
    case purchaseCancelled
    case purchaseFailed(String)
    case networkError(String)
    case storeError(String)
}

// MARK: - Log Level

public enum OpenCatLogLevel: Int, Sendable {
    case off = 0
    case error = 1
    case warn = 2
    case info = 3
    case debug = 4
}

// MARK: - Main SDK

/// OpenCat iOS SDK — the main entry point.
///
/// Configure once at app launch with either `configureStandalone()` or `configureWithServer()`,
/// then use the static methods to manage purchases and entitlements.
public final class OpenCat: @unchecked Sendable {

    // MARK: - Singleton internals

    private static let shared = OpenCat()

    private let purchaseManager = PurchaseManager()
    private let entitlementEngine = EntitlementEngine()
    private let cache = LocalCache()

    private var mode: OpenCatMode?
    private var backendConnector: BackendConnector?
    private var cachedCustomerInfo: CustomerInfo?
    private var customerInfoListeners: [(CustomerInfo) -> Void] = []
    private var logLevel: OpenCatLogLevel = .off

    private let lock = NSLock()

    private init() {}

    // MARK: - Configuration

    /// Configure the SDK in standalone mode (on-device only, no server).
    public static func configureStandalone(appUserId: String) {
        let config = StandaloneConfiguration(appUserId: appUserId)
        let instance = shared
        instance.lock.lock()
        instance.mode = .standalone(config)
        instance.backendConnector = nil
        instance.lock.unlock()

        instance.log(.info, "Configured in standalone mode for user: \(appUserId)")
        instance.startListening()
        instance.loadCachedInfo()
    }

    /// Configure the SDK in server mode (full features via OpenCat server).
    public static func configureWithServer(serverUrl: String, apiKey: String, appUserId: String, appId: String = "") {
        let config = ServerConfiguration(serverUrl: serverUrl, apiKey: apiKey, appUserId: appUserId, appId: appId)
        let instance = shared
        instance.lock.lock()
        instance.mode = .server(config)
        instance.backendConnector = BackendConnector(serverUrl: config.serverUrl, apiKey: config.apiKey)
        instance.lock.unlock()

        instance.log(.info, "Configured in server mode for user: \(appUserId)")
        instance.startListening()
        instance.loadCachedInfo()
    }

    // MARK: - Public API

    /// Fetch available product offerings.
    /// In server mode: fetches from OpenCat server, enriches with StoreKit Products when available.
    /// In standalone mode: fetches directly from StoreKit.
    public static func getOfferings(productIds: [String] = []) async throws -> [ProductOffering] {
        let instance = shared
        try instance.ensureConfigured()

        guard let mode = instance.getMode() else { throw OpenCatError.notConfigured }

        switch mode {
        case .server(let config):
            // If appId is configured, fetch offerings from server and enrich with StoreKit
            if !config.appId.isEmpty, let connector = instance.backendConnector {
                do {
                    var offerings = try await connector.getOfferings(appId: config.appId)

                    // Try to enrich with StoreKit products (for purchasing)
                    let storeProductIds = offerings.map { $0.storeProductId }
                    if let storeProducts = try? await instance.purchaseManager.getProducts(productIds: storeProductIds) {
                        let productMap = Dictionary(uniqueKeysWithValues: storeProducts.map { ($0.id, $0) })
                        for i in offerings.indices {
                            offerings[i].storeProduct = productMap[offerings[i].storeProductId]
                        }
                    }

                    return offerings
                } catch {
                    instance.log(.warn, "Server offerings fetch failed, falling back to StoreKit: \(error)")
                }
            }

            // Fallback: fetch directly from StoreKit (same as standalone)
            let products = try await instance.purchaseManager.getProducts(productIds: productIds)
            return products.map { product in
                var offering = ProductOffering(
                    storeProductId: product.id,
                    productType: product.subscription != nil ? "subscription" : "non_consumable",
                    displayName: product.displayName,
                    description: product.description,
                    priceMicros: Int64(truncating: (product.price * 1_000_000) as NSDecimalNumber),
                    currency: "USD",
                    subscriptionPeriod: nil,
                    trialPeriod: nil,
                    entitlements: []
                )
                offering.storeProduct = product
                return offering
            }

        case .standalone:
            let products = try await instance.purchaseManager.getProducts(productIds: productIds)
            return products.map { product in
                var offering = ProductOffering(
                    storeProductId: product.id,
                    productType: product.subscription != nil ? "subscription" : "non_consumable",
                    displayName: product.displayName,
                    description: product.description,
                    priceMicros: Int64(truncating: (product.price * 1_000_000) as NSDecimalNumber),
                    currency: "USD",
                    subscriptionPeriod: nil,
                    trialPeriod: nil,
                    entitlements: []
                )
                offering.storeProduct = product
                return offering
            }
        }
    }

    /// Purchase a product by its identifier.
    @discardableResult
    public static func purchase(_ productId: String) async throws -> TransactionInfo {
        let instance = shared
        try instance.ensureConfigured()

        let transaction = try await instance.purchaseManager.purchase(productId: productId)
        instance.log(.info, "Purchase succeeded for \(productId)")

        // Process the transaction based on mode
        let customerInfo = try await instance.processTransaction(transaction)
        instance.updateCachedInfo(customerInfo)

        return await instance.entitlementEngine.transactionInfo(from: transaction)
    }

    /// Restore previous purchases.
    public static func restorePurchases() async throws -> CustomerInfo {
        let instance = shared
        try instance.ensureConfigured()

        await instance.purchaseManager.restorePurchases()
        instance.log(.info, "Restore purchases completed")

        let customerInfo = try await instance.refreshCustomerInfo()
        instance.updateCachedInfo(customerInfo)
        return customerInfo
    }

    /// Check if the user has an active entitlement. Synchronous — reads from cache.
    public static func isEntitled(_ entitlementId: String) -> Bool {
        let instance = shared
        instance.lock.lock()
        let info = instance.cachedCustomerInfo
        instance.lock.unlock()

        guard let info = info,
              let entitlement = info.activeEntitlements[entitlementId] else {
            return false
        }
        if !entitlement.isActive { return false }
        if let exp = entitlement.expirationDate, exp <= Date() { return false }
        return true
    }

    /// Fetch fresh CustomerInfo (from server in server mode, from StoreKit in standalone).
    public static func getCustomerInfo() async throws -> CustomerInfo {
        let instance = shared
        try instance.ensureConfigured()

        let info = try await instance.refreshCustomerInfo()
        instance.updateCachedInfo(info)
        return info
    }

    /// Register a listener for CustomerInfo changes.
    public static func onCustomerInfoUpdate(_ listener: @escaping (CustomerInfo) -> Void) {
        let instance = shared
        instance.lock.lock()
        instance.customerInfoListeners.append(listener)
        instance.lock.unlock()
    }

    /// Set the log level for SDK diagnostics.
    public static func setLogLevel(_ level: OpenCatLogLevel) {
        shared.logLevel = level
    }

    // MARK: - Internal

    private func ensureConfigured() throws {
        lock.lock()
        let configured = mode != nil
        lock.unlock()
        guard configured else { throw OpenCatError.notConfigured }
    }

    private func getMode() -> OpenCatMode? {
        lock.lock()
        defer { lock.unlock() }
        return mode
    }

    private func startListening() {
        Task {
            await purchaseManager.startTransactionListener { [weak self] transaction in
                guard let self = self else { return }
                self.log(.debug, "Transaction update received for \(transaction.productID)")
                if let info = try? await self.processTransaction(transaction) {
                    self.updateCachedInfo(info)
                }
            }
        }
    }

    private func loadCachedInfo() {
        guard let mode = getMode() else { return }
        Task {
            if let cached = await cache.load(appUserId: mode.appUserId) {
                updateCachedInfo(cached)
                log(.debug, "Loaded cached CustomerInfo")
            }
        }
    }

    private func processTransaction(_ transaction: Transaction) async throws -> CustomerInfo {
        guard let mode = getMode() else { throw OpenCatError.notConfigured }

        switch mode {
        case .standalone:
            return await entitlementEngine.resolveFromCurrentEntitlements(appUserId: mode.appUserId)

        case .server:
            guard let connector = backendConnector else { throw OpenCatError.notConfigured }
            let jws = await purchaseManager.getJWSRepresentation(for: transaction.productID)
            guard let jws = jws else {
                throw OpenCatError.storeError("Could not get JWS for \(transaction.productID)")
            }
            return try await connector.postTransaction(
                appUserId: mode.appUserId,
                productId: transaction.productID,
                jwsRepresentation: jws
            )
        }
    }

    private func refreshCustomerInfo() async throws -> CustomerInfo {
        guard let mode = getMode() else { throw OpenCatError.notConfigured }

        switch mode {
        case .standalone:
            return await entitlementEngine.resolveFromCurrentEntitlements(appUserId: mode.appUserId)
        case .server:
            guard let connector = backendConnector else { throw OpenCatError.notConfigured }
            do {
                return try await connector.getCustomerInfo(appUserId: mode.appUserId)
            } catch {
                // Fallback to cache on network failure
                lock.lock()
                let cached = cachedCustomerInfo
                lock.unlock()
                if let cached = cached {
                    log(.warn, "Network error, returning cached CustomerInfo")
                    return cached
                }
                throw error
            }
        }
    }

    private func updateCachedInfo(_ info: CustomerInfo) {
        lock.lock()
        cachedCustomerInfo = info
        let listeners = customerInfoListeners
        lock.unlock()

        Task { await cache.save(info) }

        for listener in listeners {
            listener(info)
        }
    }

    private func log(_ level: OpenCatLogLevel, _ message: String) {
        guard level.rawValue <= logLevel.rawValue else { return }
        let prefix: String
        switch level {
        case .off: return
        case .error: prefix = "[OpenCat ERROR]"
        case .warn: prefix = "[OpenCat WARN]"
        case .info: prefix = "[OpenCat INFO]"
        case .debug: prefix = "[OpenCat DEBUG]"
        }
        print("\(prefix) \(message)")
    }
}
