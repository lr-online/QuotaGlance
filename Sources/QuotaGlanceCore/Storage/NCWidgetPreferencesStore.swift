import Foundation

public struct NCWidgetPreferences: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var defaultAccountID: UUID?

    public init(schemaVersion: Int, defaultAccountID: UUID?) {
        self.schemaVersion = schemaVersion
        self.defaultAccountID = defaultAccountID
    }
}

public struct NCWidgetPreferencesStore: Sendable {
    public static let fileName = "nc-widget-preferences-v1.json"

    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func write(_ preferences: NCWidgetPreferences) throws {
        let fileURL = try validatedFileURL()
        let parent = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: parent,
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder.quotaGlance.encode(preferences)
        let temporaryURL = SharedSnapshotStore.temporaryFileURL(
            for: fileURL,
            identifier: UUID().uuidString
        )
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        try data.write(to: temporaryURL, options: .withoutOverwriting)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: temporaryURL.path
        )
        if FileManager.default.fileExists(atPath: fileURL.path) {
            _ = try FileManager.default.replaceItemAt(
                fileURL,
                withItemAt: temporaryURL,
                backupItemName: nil,
                options: .usingNewMetadataOnly
            )
        } else {
            try FileManager.default.moveItem(at: temporaryURL, to: fileURL)
        }
    }

    public func read() throws -> NCWidgetPreferences {
        let fileURL = try validatedFileURL()
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return NCWidgetPreferences(
                schemaVersion: NCWidgetPreferences.currentSchemaVersion,
                defaultAccountID: nil
            )
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder.quotaGlance.decode(
            NCWidgetPreferences.self,
            from: data
        )
    }

    private func validatedFileURL() throws -> URL {
        guard fileURL.isFileURL, !fileURL.lastPathComponent.isEmpty else {
            throw SharedSnapshotStoreError.invalidFileURL
        }
        return fileURL.standardizedFileURL
    }
}
