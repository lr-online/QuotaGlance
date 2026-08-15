import Foundation
import Testing
@testable import QuotaGlanceCore

@Suite("Compatible system symbols")
struct CompatibleSystemSymbolTests {
    @Test("Status bar prefers the macOS 14 gauge and falls back for macOS 12")
    func statusBarCandidates() {
        #expect(
            CompatibleSystemSymbolNames.statusBar
                == ["gauge.with.dots.needle.50percent", "gauge"]
        )
    }

    @Test("Empty state prefers the macOS 14 gauge and falls back for macOS 12")
    func emptyStateCandidates() {
        #expect(
            CompatibleSystemSymbolNames.emptyState
                == ["gauge.open.with.lines.needle.33percent", "gauge"]
        )
    }
}
