import Foundation

/// Configuration for standalone mode (no server, on-device only).
public struct StandaloneConfiguration {
    public let appUserId: String

    public init(appUserId: String) {
        self.appUserId = appUserId
    }
}

/// Configuration for server mode (full features via OpenCat server).
public struct ServerConfiguration {
    public let serverUrl: URL
    public let apiKey: String
    public let appUserId: String
    public let appId: String

    public init(serverUrl: String, apiKey: String, appUserId: String, appId: String = "") {
        guard let url = URL(string: serverUrl) else {
            fatalError("OpenCat: Invalid server URL: \(serverUrl)")
        }
        self.serverUrl = url
        self.apiKey = apiKey
        self.appUserId = appUserId
        self.appId = appId
    }
}

/// Internal unified configuration.
enum OpenCatMode {
    case standalone(StandaloneConfiguration)
    case server(ServerConfiguration)

    var appUserId: String {
        switch self {
        case .standalone(let config): return config.appUserId
        case .server(let config): return config.appUserId
        }
    }
}
