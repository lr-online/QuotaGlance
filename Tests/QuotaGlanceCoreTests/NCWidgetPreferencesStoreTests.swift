import Foundation
import Testing
@testable import QuotaGlanceCore

@Suite("NC widget preferences store")
struct NCWidgetPreferencesStoreTests {
    @Test("Sidecar round-trips default account id")
    func sidecarRoundTripsDefaultAccountID() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = NCWidgetPreferencesStore(
            fileURL: directory.appendingPathComponent(NCWidgetPreferencesStore.fileName)
        )
        let accountID = UUID()
        try store.write(
            NCWidgetPreferences(schemaVersion: 1, defaultAccountID: accountID)
        )

        #expect(try store.read().defaultAccountID == accountID)
    }

    @Test("Missing sidecar reads as unset default")
    func missingSidecarReadsAsUnsetDefault() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = NCWidgetPreferencesStore(
            fileURL: directory.appendingPathComponent(NCWidgetPreferencesStore.fileName)
        )
        #expect(try store.read().defaultAccountID == nil)
    }
}
