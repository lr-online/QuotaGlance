import Foundation

public enum SharedSnapshotStoreError: Error, Equatable, Sendable {
    case invalidFileURL
}

public enum QuotaGlanceShared {
    public static let appGroupIdentifier = "group.com.liangrui.QuotaGlance"
    public static let snapshotFileName = "quota-snapshot-v1.json"

    public static func snapshotStore() -> SharedSnapshotStore? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            return nil
        }
        return SharedSnapshotStore(
            fileURL: containerURL.appending(path: snapshotFileName)
        )
    }
}

public struct SharedSnapshotStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func write(_ snapshot: WidgetSnapshotEnvelope) throws {
        let fileURL = try validatedFileURL()
        let parent = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: parent,
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder.quotaGlance.encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
    }

    public func read() throws -> WidgetSnapshotEnvelope {
        let fileURL = try validatedFileURL()
        return try JSONDecoder.quotaGlance.decode(
            WidgetSnapshotEnvelope.self,
            from: Data(contentsOf: fileURL)
        )
    }

    private func validatedFileURL() throws -> URL {
        guard fileURL.isFileURL, !fileURL.lastPathComponent.isEmpty else {
            throw SharedSnapshotStoreError.invalidFileURL
        }
        return fileURL.standardizedFileURL
    }
}
