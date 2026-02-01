import Foundation
import StoreKit

// MARK: - Product Offering

/// Product offering returned by the OpenCat server.
public struct ProductOffering: Codable, Sendable {
    public let storeProductId: String
    public let productType: String
    public let displayName: String
    public let description: String?
    public let priceMicros: Int64
    public let currency: String
    public let subscriptionPeriod: String?
    public let trialPeriod: String?
    public let entitlements: [String]

    /// StoreKit Product, attached after fetching from StoreKit (nil if StoreKit unavailable)
    public var storeProduct: Product?

    public init(
        storeProductId: String,
        productType: String,
        displayName: String,
        description: String?,
        priceMicros: Int64,
        currency: String,
        subscriptionPeriod: String?,
        trialPeriod: String?,
        entitlements: [String]
    ) {
        self.storeProductId = storeProductId
        self.productType = productType
        self.displayName = displayName
        self.description = description
        self.priceMicros = priceMicros
        self.currency = currency
        self.subscriptionPeriod = subscriptionPeriod
        self.trialPeriod = trialPeriod
        self.entitlements = entitlements
    }

    enum CodingKeys: String, CodingKey {
        case storeProductId, productType, displayName, description
        case priceMicros, currency, subscriptionPeriod, trialPeriod, entitlements
    }

    /// Price as Decimal (from micros)
    public var price: Decimal {
        Decimal(priceMicros) / 1_000_000
    }

    /// Formatted price string
    public var displayPrice: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        return formatter.string(from: price as NSDecimalNumber) ?? "$\(price)"
    }
}

public struct OfferingsResponse: Codable, Sendable {
    public let offerings: [ProductOffering]
}

// MARK: - Backend Connector

/// HTTP client for communicating with the OpenCat server in server mode.
actor BackendConnector {
    private let serverUrl: URL
    private let apiKey: String
    private let session: URLSession

    init(serverUrl: URL, apiKey: String) {
        self.serverUrl = serverUrl
        self.apiKey = apiKey
        self.session = URLSession(configuration: .default)
    }

    /// Post a JWS transaction to the server for verification.
    func postTransaction(
        appUserId: String,
        productId: String,
        jwsRepresentation: String
    ) async throws -> CustomerInfo {
        let url = serverUrl.appendingPathComponent("/v1/receipts")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "app_user_id": appUserId,
            "product_id": productId,
            "platform": "apple",
            "jws_representation": jwsRepresentation
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

        return try JSONDecoder.openCat.decode(CustomerInfo.self, from: data)
    }

    /// Fetch customer info from the server.
    func getCustomerInfo(appUserId: String) async throws -> CustomerInfo {
        let url = serverUrl.appendingPathComponent("/v1/customers/\(appUserId)")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

        return try JSONDecoder.openCat.decode(CustomerInfo.self, from: data)
    }

    /// Fetch product offerings from the OpenCat server.
    func getOfferings(appId: String) async throws -> [ProductOffering] {
        let url = serverUrl.appendingPathComponent("/v1/apps/\(appId)/offerings")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

        let decoded = try JSONDecoder.openCat.decode(OfferingsResponse.self, from: data)
        return decoded.offerings
    }

    private func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenCatError.networkError("Invalid response")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw OpenCatError.networkError("Server returned status \(httpResponse.statusCode)")
        }
    }
}

private extension JSONDecoder {
    static let openCat: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}
