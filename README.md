# OpenCat iOS SDK

Open-source subscription management SDK for Swift. Drop-in alternative to RevenueCat — use your own OpenCat server or run standalone with StoreKit 2.

## Installation

Add via Swift Package Manager:

```
https://github.com/openrevenuecat/opencat-ios.git
```

Or in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/openrevenuecat/opencat-ios.git", from: "0.1.0")
]
```

## Quick Start

### Server Mode (recommended)

Connect to your OpenCat server for receipt validation, entitlement management, and product catalog sync.

```swift
import OpenCat

// Configure on app launch
OpenCat.configureWithServer(
    serverUrl: "https://your-server.com",
    apiKey: "your-api-key",
    appUserId: userId,
    appId: "your-app-id"  // from OpenCat dashboard
)

// Fetch product offerings (from server, enriched with StoreKit)
let offerings = try await OpenCat.getOfferings()

for offering in offerings {
    print("\(offering.displayName): \(offering.displayPrice)")
    print("Period: \(offering.subscriptionPeriod ?? "one-time")")
    print("Trial: \(offering.trialPeriod ?? "none")")
}

// Purchase
let transaction = try await OpenCat.purchase("com.yourapp.premium.annual")

// Check entitlements
if OpenCat.isEntitled("pro") {
    // unlock premium features
}

// Get full customer info
let info = try await OpenCat.getCustomerInfo()
```

### Standalone Mode

On-device only — no server needed. Uses StoreKit 2 directly.

```swift
import OpenCat

OpenCat.configureStandalone(appUserId: userId)

let offerings = try await OpenCat.getOfferings(productIds: [
    "com.yourapp.premium.annual",
    "com.yourapp.premium.monthly"
])

let transaction = try await OpenCat.purchase("com.yourapp.premium.annual")
```

## ProductOffering

The `ProductOffering` struct provides product metadata from the server:

| Property | Type | Description |
|----------|------|-------------|
| `storeProductId` | `String` | App Store product identifier |
| `productType` | `String` | "subscription", "consumable", "non_consumable" |
| `displayName` | `String` | Localized product name |
| `priceMicros` | `Int64` | Price in micros (e.g., 9990000 = $9.99) |
| `currency` | `String` | ISO currency code |
| `subscriptionPeriod` | `String?` | ISO 8601 duration (e.g., "P1M", "P1Y") |
| `trialPeriod` | `String?` | Free trial duration |
| `entitlements` | `[String]` | Entitlement identifiers granted |
| `price` | `Decimal` | Computed price from micros |
| `displayPrice` | `String` | Formatted price string |
| `storeProduct` | `Product?` | StoreKit Product (for purchasing) |

## Logging

```swift
OpenCat.setLogLevel(.debug)  // .off, .error, .warn, .info, .debug
```

## Requirements

- iOS 15+ / macOS 12+ / tvOS 15+ / watchOS 8+
- Swift 5.7+
- Xcode 14+

## License

MIT
