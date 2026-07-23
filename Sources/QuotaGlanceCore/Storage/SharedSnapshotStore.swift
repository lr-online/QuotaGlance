import Foundation

public enum SharedSnapshotStoreError: Error, Equatable, Sendable {
    case invalidFileURL
}

public enum QuotaGlanceShared {
    public static let appGroupIdentifier = "group.com.liangrui.QuotaGlance"
    public static let snapshotFileName = "quota-snapshot-v1.json"
    public static let certificateFreeSnapshotDirectory = URL(
        fileURLWithPath: "/Users/Shared/QuotaGlance",
        isDirectory: true
    )

    public static func snapshotStore() -> SharedSnapshotStore? {
#if QUOTAGLANCE_CERTIFICATE_FREE_STORAGE
        certificateFreeSnapshotStore()
#else
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            return nil
        }
        return SharedSnapshotStore(
            fileURL: containerURL.appendingPathComponent(snapshotFileName)
        )
#endif
    }

    public static func certificateFreeSnapshotStore() -> SharedSnapshotStore {
        SharedSnapshotStore(
            fileURL: certificateFreeSnapshotDirectory.appendingPathComponent(
                snapshotFileName
            )
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
        let temporaryURL = Self.temporaryFileURL(
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

    static func temporaryFileURL(for fileURL: URL, identifier: String) -> URL {
        fileURL.deletingLastPathComponent().appendingPathComponent(
            ".\(fileURL.lastPathComponent).\(identifier).tmp"
        )
    }
}
