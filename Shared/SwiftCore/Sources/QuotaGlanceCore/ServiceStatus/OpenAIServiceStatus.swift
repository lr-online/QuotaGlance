import Foundation

public enum ServiceStatusLevel: String, Codable, Equatable, Sendable {
    case operational
    case degraded
    case outage
    case unknown
}

public struct ServiceStatusComponent: Codable, Equatable, Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let status: ServiceStatusLevel

    public init(name: String, status: ServiceStatusLevel) {
        self.name = name
        self.status = status
    }
}

public struct ServiceStatusIncident: Codable, Equatable, Identifiable, Sendable {
    public var id: String { "\(title)-\(status)" }
    public let title: String
    public let status: String
    public let url: URL?

    public init(title: String, status: String, url: URL?) {
        self.title = title
        self.status = status
        self.url = url
    }
}

public struct OpenAIServiceStatus: Codable, Equatable, Sendable {
    public let source: String
    public let overall: ServiceStatusLevel
    public let summary: String
    public let affectedComponents: [ServiceStatusComponent]
    public let activeIncidents: [ServiceStatusIncident]

    public init(
        source: String = "openAI",
        overall: ServiceStatusLevel,
        summary: String,
        affectedComponents: [ServiceStatusComponent],
        activeIncidents: [ServiceStatusIncident]
    ) {
        self.source = source
        self.overall = overall
        self.summary = summary
        self.affectedComponents = affectedComponents
        self.activeIncidents = activeIncidents
    }
}

public struct OpenAIServiceStatusClient: Sendable {
    public static let summaryURL = URL(string: "https://status.openai.com/api/v2/summary.json")!

    private let httpClient: any HTTPClient

    public init(httpClient: any HTTPClient = URLSessionHTTPClient()) {
        self.httpClient = httpClient
    }

    public func fetch() async throws -> OpenAIServiceStatus {
        var request = URLRequest(url: Self.summaryURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await httpClient.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            throw ProviderError.httpStatus(response.statusCode)
        }
        return try Self.parse(data)
    }

    public static func parse(_ data: Data) throws -> OpenAIServiceStatus {
        let response = try JSONDecoder().decode(SummaryResponse.self, from: data)
        let summary = response.status.description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty else { throw ProviderError.invalidResponse }
        return OpenAIServiceStatus(
            overall: overall(for: response.status.indicator),
            summary: summary,
            affectedComponents: response.components.compactMap { component in
                let level = componentLevel(for: component.status)
                guard level != .operational else { return nil }
                return ServiceStatusComponent(name: component.name, status: level)
            },
            activeIncidents: response.incidents.compactMap { incident in
                guard incident.status != "resolved" else { return nil }
                return ServiceStatusIncident(
                    title: incident.name,
                    status: incident.status,
                    url: incident.shortlink.flatMap(URL.init(string:))
                )
            }
        )
    }

    private static func overall(for indicator: String) -> ServiceStatusLevel {
        switch indicator {
        case "none": .operational
        case "minor": .degraded
        case "major", "critical": .outage
        default: .unknown
        }
    }

    private static func componentLevel(for status: String) -> ServiceStatusLevel {
        switch status {
        case "operational": .operational
        case "degraded_performance", "partial_outage": .degraded
        case "major_outage": .outage
        default: .unknown
        }
    }

    private struct SummaryResponse: Decodable {
        let status: Status
        let components: [Component]
        let incidents: [Incident]
    }

    private struct Status: Decodable { let description: String; let indicator: String }
    private struct Component: Decodable { let name: String; let status: String }
    private struct Incident: Decodable { let name: String; let status: String; let shortlink: String? }
}
