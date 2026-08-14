import Foundation
import Testing
@testable import QuotaGlanceCore

@Suite("Deep link routing")
struct DeepLinkRouterTests {
    @Test("A known account URL selects that account")
    func knownAccountURL() throws {
        let accountID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let url = try #require(
            URL(string: "quotaglance://account/\(accountID.uuidString)")
        )

        #expect(
            DeepLinkRouter.destination(
                for: url,
                knownAccountIDs: [accountID]
            ) == .account(accountID)
        )
    }

    @Test("All Accounts and deleted accounts route to aggregate")
    func aggregateFallback() throws {
        let deletedID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let allURL = try #require(URL(string: "quotaglance://all"))
        let deletedURL = try #require(
            URL(string: "quotaglance://account/\(deletedID.uuidString)")
        )

        #expect(
            DeepLinkRouter.destination(for: allURL, knownAccountIDs: [])
                == .allAccounts
        )
        #expect(
            DeepLinkRouter.destination(for: deletedURL, knownAccountIDs: [])
                == .allAccounts
        )
    }

    @Test("Invalid URLs are ignored")
    func invalidURLsAreIgnored() throws {
        let invalidURLs = try [
            #require(URL(string: "https://account/123")),
            #require(URL(string: "quotaglance://account/not-a-uuid")),
            #require(URL(string: "quotaglance://unknown")),
        ]

        for url in invalidURLs {
            #expect(
                DeepLinkRouter.destination(for: url, knownAccountIDs: []) == nil
            )
        }
    }
}
