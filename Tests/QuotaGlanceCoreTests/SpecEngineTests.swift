import Foundation
import Testing
@testable import QuotaGlanceCore

// Engine semantics unit tests: the closed value/condition sets, decimal
// canonicalization, status-branch ordering, gotoStep/onDemand,
// credentialKindDetection enforcement, regionFallback, profile validation,
// credential preprocessing, and spec load validation. Crafted minimal specs
// drive SpecDrivenProvider end to end; the real contract specs cover the
// provider-specific flows.

private func makeEngineSpecData(
    specVersion: Int = 1,
    credential: String = #"{"trimWhitespace": false}"#,
    supported: String = #"[{"region":"global","credentialKind":"standard"}]"#,
    detect: String = #"{"strategy":"fixedProfile","profile":{"region":"global","credentialKind":"standard"}}"#,
    steps: String
) -> Data {
    Data(
        """
        {
          "specVersion": \(specVersion),
          "id": "deepSeek",
          "displayName": "Engine Test",
          "descriptor": {
            "supportsLowBalanceThreshold": { "always": true },
            "profileDescription": {
              "undetected": { "l10nKey": "notDetected" },
              "detected": { "style": "regionCredential" }
            }
          },
          "credential": \(credential),
          "profiles": { "supported": \(supported) },
          "detect": \(detect),
          "fetch": { "steps": \(steps) }
        }
        """.utf8
    )
}

private func makeStep(
    name: String = "main",
    onDemand: Bool = false,
    url: String = #""https://engine.test/endpoint""#,
    onStatus: String = #"{"match":"2xx","action":"parse"},{"match":"default","action":"error","error":"httpStatus"}"#,
    parse: String = #"{"checks":[],"snapshot":{}}"#
) -> String {
    """
    {
      "name": "\(name)",
      "onDemand": \(onDemand),
      "request": {
        "method": "GET",
        "url": \(url),
        "headers": [
          { "name": "Authorization", "value": "Bearer ${apiKey}" },
          { "name": "Accept", "value": "application/json" }
        ]
      },
      "onStatus": [\(onStatus)],
      "parse": \(parse)
    }
    """
}

private func makeEngine(
    specData: Data,
    httpClient: ContractURLStubHTTPClient,
    preferredRegion: ProviderRegion? = nil
) throws -> SpecDrivenProvider {
    try SpecDrivenProvider(
        specData: specData,
        httpClient: httpClient,
        preferredRegion: preferredRegion,
        now: { Date(timeIntervalSince1970: 123) }
    )
}

private func contractSpecEngine(
    provider: String,
    httpClient: ContractURLStubHTTPClient,
    preferredRegion: ProviderRegion? = nil
) throws -> SpecDrivenProvider {
    try SpecDrivenProvider(
        specData: loadFixture(provider: provider, file: "spec.json"),
        httpClient: httpClient,
        preferredRegion: preferredRegion,
        now: { Date(timeIntervalSince1970: 123) }
    )
}

private func body(_ json: String) -> Data {
    Data(json.utf8)
}

private let globalStandard = ProviderProfile(region: .global, credentialKind: .standard)

@Suite("Spec engine value semantics")
struct SpecEngineValueTests {
    @Test("Decimal extraction accepts JSON numbers and numeric strings")
    func decimalAcceptsNumbersAndNumericStrings() async throws {
        let specData = makeEngineSpecData(steps: """
            [\(makeStep(parse: #"{"checks":[],"snapshot":{"balances":{"fixed":[{"label":{"literal":"Balance"},"available":{"money":{"amount":{"path":"amount","type":"decimal"},"currency":{"literal":"USD"}}}}]}}}"#))]
            """)

        let stringClient = ContractURLStubHTTPClient(responses: [
            "https://engine.test/endpoint": (body(#"{"amount": " 10.00 "}"#), 200),
        ])
        let stringSnapshot = try await makeEngine(
            specData: specData,
            httpClient: stringClient
        ).fetch(apiKey: "key", profile: globalStandard)
        #expect(
            stringSnapshot.balances.first?.available
                == Money(amount: Decimal(string: "10.00")!, currency: "USD")
        )

        let numberClient = ContractURLStubHTTPClient(responses: [
            "https://engine.test/endpoint": (body(#"{"amount": 5.5}"#), 200),
        ])
        let numberSnapshot = try await makeEngine(
            specData: specData,
            httpClient: numberClient
        ).fetch(apiKey: "key", profile: globalStandard)
        #expect(
            numberSnapshot.balances.first?.available
                == Money(amount: Decimal(string: "5.5")!, currency: "USD")
        )
    }

    @Test("An unparseable decimal resolves absent, failing required assembly")
    func unparseableDecimalResolvesAbsent() async {
        let specData = makeEngineSpecData(steps: """
            [\(makeStep(parse: #"{"checks":[],"snapshot":{"balances":{"fixed":[{"label":{"literal":"Balance"},"available":{"money":{"amount":{"path":"amount","type":"decimal"},"currency":{"literal":"USD"}}}}]}}}"#))]
            """)
        let httpClient = ContractURLStubHTTPClient(responses: [
            "https://engine.test/endpoint": (body(#"{"amount": "not-a-number"}"#), 200),
        ])
        await #expect(throws: ProviderError.invalidResponse) {
            try await makeEngine(specData: specData, httpClient: httpClient)
                .fetch(apiKey: "key", profile: globalStandard)
        }
    }

    @Test("Decimal canonicalization keeps string, number and subtract forms")
    func decimalCanonicalForms() {
        let stringSourced = SpecDecimal.fromString("  10.00  ")
        #expect(stringSourced?.value == Decimal(string: "10.00")!)
        #expect(stringSourced?.canonical == "10.00")

        let numberSourced = SpecDecimal.fromNumber(Decimal(string: "6655.90")!)
        #expect(numberSourced.canonical == "6655.9")
        #expect(SpecDecimal.fromNumber(Decimal(10)).canonical == "10")

        let difference = SpecDecimal.subtract(
            SpecDecimal.fromNumber(Decimal(25)),
            SpecDecimal.fromString("3.25")
        )
        #expect(difference?.value == Decimal(string: "21.75")!)
        #expect(difference?.canonical == "21.75")
        #expect(SpecDecimal.subtract(SpecDecimal.fromNumber(Decimal(1)), nil) == nil)
    }

    @Test("Subtract propagates null when either operand is absent")
    func subtractPropagatesNull() async throws {
        let specData = makeEngineSpecData(steps: """
            [\(makeStep(parse: #"{"checks":[],"values":{"currency":{"literal":"USD"}},"snapshot":{"spend":{"object":{"total":{"money":{"amount":{"op":"subtract","a":{"path":"total","type":"decimal"},"b":{"path":"used","type":"decimal"}},"currency":{"value":"currency"}}}}}}}"#))]
            """)

        let completeClient = ContractURLStubHTTPClient(responses: [
            "https://engine.test/endpoint": (body(#"{"total": 25, "used": "3.25"}"#), 200),
        ])
        let complete = try await makeEngine(specData: specData, httpClient: completeClient)
            .fetch(apiKey: "key", profile: globalStandard)
        #expect(complete.spend.total == Money(amount: Decimal(string: "21.75")!, currency: "USD"))

        let missingClient = ContractURLStubHTTPClient(responses: [
            "https://engine.test/endpoint": (body(#"{"total": 25}"#), 200),
        ])
        let missing = try await makeEngine(specData: specData, httpClient: missingClient)
            .fetch(apiKey: "key", profile: globalStandard)
        #expect(missing.spend.total == nil)
    }

    @Test("A missing key and an explicit null both resolve to absent")
    func missingKeyAndExplicitNullResolveAbsent() async throws {
        let specData = makeEngineSpecData(steps: """
            [\(makeStep(parse: #"{"checks":[],"snapshot":{"metricsUnavailableReason":{"when":{"path":"spend","exists":false},"value":{"literal":"none"}}}}"#))]
            """)

        for response in [body(#"{}"#), body(#"{"spend": null}"#)] {
            let httpClient = ContractURLStubHTTPClient(responses: [
                "https://engine.test/endpoint": (response, 200),
            ])
            let snapshot = try await makeEngine(specData: specData, httpClient: httpClient)
                .fetch(apiKey: "key", profile: globalStandard)
            #expect(snapshot.metricsUnavailableReason == "none")
        }

        let httpClient = ContractURLStubHTTPClient(responses: [
            "https://engine.test/endpoint": (body(#"{"spend": 1}"#), 200),
        ])
        let snapshot = try await makeEngine(specData: specData, httpClient: httpClient)
            .fetch(apiKey: "key", profile: globalStandard)
        #expect(snapshot.metricsUnavailableReason == nil)
    }
}

@Suite("Spec engine step orchestration")
struct SpecEngineOrchestrationTests {
    @Test("onStatus is first-match: a 403 rule ahead of 401 wins the branch")
    func onStatusIsFirstMatch() async throws {
        let onStatus = """
            {"match":"2xx","action":"parse"},
            {"match":[403],"action":"gotoStep","step":"fallback"},
            {"match":[401,403],"action":"error","error":"invalidCredential"},
            {"match":"default","action":"error","error":"httpStatus"}
            """
        let specData = makeEngineSpecData(steps: """
            [
              \(makeStep(
                  name: "primary",
                  url: #""https://engine.test/primary""#,
                  onStatus: onStatus,
                  parse: #"{"checks":[],"snapshot":{"providerStatus":{"literal":"primary"}}}"#
              )),
              \(makeStep(
                  name: "fallback",
                  onDemand: true,
                  url: #""https://engine.test/fallback""#,
                  parse: #"{"checks":[],"snapshot":{"providerStatus":{"literal":"fallback"}}}"#
              ))
            ]
            """)

        let gotoClient = ContractURLStubHTTPClient(responses: [
            "https://engine.test/primary": (body(#"{}"#), 403),
            "https://engine.test/fallback": (body(#"{}"#), 200),
        ])
        let snapshot = try await makeEngine(specData: specData, httpClient: gotoClient)
            .fetch(apiKey: "key", profile: globalStandard)
        #expect(snapshot.providerStatus == "fallback")
        #expect(await gotoClient.recorder.requests.count == 2)

        let errorClient = ContractURLStubHTTPClient(responses: [
            "https://engine.test/primary": (body(#"{}"#), 401),
        ])
        await #expect(throws: ProviderError.invalidCredential) {
            try await makeEngine(specData: specData, httpClient: errorClient)
                .fetch(apiKey: "key", profile: globalStandard)
        }
        #expect(await errorClient.recorder.requests.count == 1)
    }

    @Test("An onDemand step never runs in listed order without a gotoStep")
    func onDemandStepNeverRunsInListedOrder() async throws {
        let specData = makeEngineSpecData(steps: """
            [
              \(makeStep(
                  name: "primary",
                  url: #""https://engine.test/primary""#,
                  parse: #"{"checks":[],"snapshot":{"providerStatus":{"literal":"primary"}}}"#
              )),
              \(makeStep(
                  name: "fallback",
                  onDemand: true,
                  url: #""https://engine.test/fallback""#,
                  parse: #"{"checks":[],"snapshot":{"providerStatus":{"literal":"fallback"}}}"#
              ))
            ]
            """)
        let httpClient = ContractURLStubHTTPClient(responses: [
            "https://engine.test/primary": (body(#"{}"#), 200),
        ])

        let snapshot = try await makeEngine(specData: specData, httpClient: httpClient)
            .fetch(apiKey: "key", profile: globalStandard)

        #expect(snapshot.providerStatus == "primary")
        #expect(await httpClient.recorder.requests.count == 1)
    }
}

@Suite("Spec engine credential-kind detection")
struct SpecEngineCredentialKindTests {
    @Test("Fetch of a management key under a standard profile fails after /key")
    func fetchEnforcesDetectedKindBeforeLaterSteps() async throws {
        let httpClient = ContractURLStubHTTPClient(responses: [
            "https://openrouter.ai/api/v1/key":
                (try loadFixture(provider: "openrouter", file: "key-management-response.json"), 200),
        ])
        let provider = try contractSpecEngine(provider: "openrouter", httpClient: httpClient)

        await #expect(throws: ProviderError.profileMismatch) {
            try await provider.fetch(
                apiKey: "redacted-test-key",
                profile: ProviderProfile(region: .global, credentialKind: .standard)
            )
        }
        // The mismatch throws right after /key parses; /credits is never called.
        #expect(await httpClient.recorder.requests.count == 1)
    }

    @Test("Detect takes the credential kind from credentialKindDetection")
    func detectAdoptsDetectedKind() async throws {
        let httpClient = ContractURLStubHTTPClient(responses: [
            "https://openrouter.ai/api/v1/key":
                (try loadFixture(provider: "openrouter", file: "key-management-response.json"), 200),
            "https://openrouter.ai/api/v1/credits":
                (try loadFixture(provider: "openrouter", file: "key-management-response2.json"), 200),
        ])
        let provider = try contractSpecEngine(provider: "openrouter", httpClient: httpClient)

        let detection = try await provider.detect(apiKey: "redacted-test-key")

        #expect(
            detection.profile
                == ProviderProfile(region: .global, credentialKind: .management)
        )
        #expect(detection.snapshot.balances.count == 1)
        #expect(await httpClient.recorder.requests.count == 2)
    }
}

@Suite("Spec engine region fallback")
struct SpecEngineRegionFallbackTests {
    private func quotaPayload() -> Data {
        body(#"{"model_remains":[{"model_name":"general","remains":90,"total":100}],"base_resp":{"status_code":0}}"#)
    }

    @Test("Authentication rejection advances to the next region candidate")
    func authenticationRejectionFallsBack() async throws {
        let httpClient = ContractURLStubHTTPClient(responses: [
            "https://www.minimaxi.com/v1/token_plan/remains": (body(#"{}"#), 401),
            "https://www.minimax.io/v1/token_plan/remains": (quotaPayload(), 200),
        ])
        let provider = try contractSpecEngine(
            provider: "minimax",
            httpClient: httpClient,
            preferredRegion: .china
        )

        let detection = try await provider.detect(apiKey: "redacted-plan-key")

        #expect(
            detection.profile
                == ProviderProfile(region: .international, credentialKind: .tokenPlan)
        )
        #expect(await httpClient.recorder.requests.count == 2)
    }

    @Test("Embedded authentication rejections also fall back")
    func embeddedAuthenticationRejectionFallsBack() async throws {
        let httpClient = ContractURLStubHTTPClient(responses: [
            "https://www.minimaxi.com/v1/token_plan/remains":
                (body(#"{"base_resp":{"status_code":1004,"status_msg":"invalid api key"}}"#), 200),
            "https://www.minimax.io/v1/token_plan/remains": (quotaPayload(), 200),
        ])
        let provider = try contractSpecEngine(
            provider: "minimax",
            httpClient: httpClient,
            preferredRegion: .china
        )

        let detection = try await provider.detect(apiKey: "redacted-plan-key")

        #expect(detection.profile.region == .international)
        #expect(await httpClient.recorder.requests.count == 2)
    }

    @Test("Exhausting every region candidate throws the exhausted error")
    func exhaustedCandidatesThrowExhaustedError() async throws {
        let httpClient = ContractURLStubHTTPClient(responses: [
            "https://www.minimaxi.com/v1/token_plan/remains": (body(#"{}"#), 401),
            "https://www.minimax.io/v1/token_plan/remains":
                (body(#"{"base_resp":{"status_code":"1004"}}"#), 200),
        ])
        let provider = try contractSpecEngine(
            provider: "minimax",
            httpClient: httpClient,
            preferredRegion: .china
        )

        await #expect(throws: ProviderError.regionDetectionFailed) {
            try await provider.detect(apiKey: "redacted-plan-key")
        }
        #expect(await httpClient.recorder.requests.count == 2)
    }

    @Test("Errors outside fallbackOn do not probe another region")
    func nonFallbackErrorsPropagateImmediately() async throws {
        let httpClient = ContractURLStubHTTPClient(responses: [
            "https://www.minimaxi.com/v1/token_plan/remains": (body(#"{}"#), 429),
        ])
        let provider = try contractSpecEngine(
            provider: "minimax",
            httpClient: httpClient,
            preferredRegion: .china
        )

        await #expect(throws: ProviderError.rateLimited) {
            try await provider.detect(apiKey: "redacted-plan-key")
        }
        #expect(await httpClient.recorder.requests.count == 1)
    }
}

@Suite("Spec engine profile and credential rules")
struct SpecEngineProfileCredentialTests {
    @Test("Fetch rejects profiles outside the supported list before requesting")
    func unsupportedProfilesAreRejected() async throws {
        let deepSeekClient = ContractURLStubHTTPClient(responses: [:])
        let deepSeek = try contractSpecEngine(provider: "deepseek", httpClient: deepSeekClient)
        await #expect(throws: ProviderError.profileMismatch) {
            try await deepSeek.fetch(
                apiKey: "key",
                profile: ProviderProfile(region: .china, credentialKind: .standard)
            )
        }
        #expect(await deepSeekClient.recorder.requests.isEmpty)

        let openRouterClient = ContractURLStubHTTPClient(responses: [:])
        let openRouter = try contractSpecEngine(
            provider: "openrouter",
            httpClient: openRouterClient
        )
        await #expect(throws: ProviderError.profileMismatch) {
            try await openRouter.fetch(
                apiKey: "key",
                profile: ProviderProfile(region: .global, credentialKind: .tokenPlan)
            )
        }
        #expect(await openRouterClient.recorder.requests.isEmpty)
    }

    @Test("Rejected credential prefixes fail before any request")
    func rejectedCredentialPrefixesFailEarly() async throws {
        let httpClient = ContractURLStubHTTPClient(responses: [:])
        let provider = try contractSpecEngine(
            provider: "minimax",
            httpClient: httpClient,
            preferredRegion: .china
        )

        await #expect(throws: ProviderError.unsupportedCredential) {
            try await provider.detect(apiKey: "  sk-api-redacted  ")
        }
        #expect(await httpClient.recorder.requests.isEmpty)
    }

    @Test("Whitespace trimming applies before rejection rules and requests")
    func whitespaceTrimmingAppliesFirst() async throws {
        let httpClient = ContractURLStubHTTPClient(responses: [
            "https://www.minimaxi.com/v1/token_plan/remains":
                (body(#"{"model_remains":[{"model_name":"general","remains":90,"total":100}],"base_resp":{"status_code":0}}"#), 200),
        ])
        let provider = try contractSpecEngine(
            provider: "minimax",
            httpClient: httpClient,
            preferredRegion: .china
        )

        _ = try await provider.detect(apiKey: "  redacted-plan-key  ")

        let request = try #require(await httpClient.recorder.requests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer redacted-plan-key")
    }

    @Test("fixedProfile detect returns the declared profile")
    func fixedProfileDetectReturnsDeclaredProfile() async throws {
        let httpClient = ContractURLStubHTTPClient(responses: [
            "https://api.deepseek.com/user/balance":
                (try loadFixture(provider: "deepseek", file: "balance-response.json"), 200),
        ])
        let provider = try contractSpecEngine(provider: "deepseek", httpClient: httpClient)

        let detection = try await provider.detect(apiKey: "redacted-test-key")

        #expect(detection.profile == ProviderProfile(region: .global, credentialKind: .standard))
        #expect(detection.snapshot.balances.count == 2)
    }

    @Test("regionFallback detect starts from the injected preferred region")
    func regionFallbackDetectStartsFromPreferredRegion() async throws {
        let httpClient = ContractURLStubHTTPClient(responses: [
            "https://api.moonshot.cn/v1/users/me/balance":
                (try loadFixture(provider: "kimi", file: "china-response.json"), 200),
        ])
        let provider = try contractSpecEngine(
            provider: "kimi",
            httpClient: httpClient,
            preferredRegion: .china
        )

        let detection = try await provider.detect(apiKey: "redacted-test-key")

        #expect(detection.profile == ProviderProfile(region: .china, credentialKind: .standard))
        #expect(await httpClient.recorder.requests.count == 1)
    }
}

@Suite("Spec engine spec loading")
struct SpecEngineSpecLoadingTests {
    @Test("Specs declaring a newer schema version are rejected")
    func newerSpecVersionIsRejected() {
        let specData = makeEngineSpecData(specVersion: 2, steps: "[]")
        #expect(throws: ProviderSpecError.unsupportedSpecVersion(2)) {
            _ = try ProviderSpec(data: specData)
        }
    }

    @Test("Unknown named parse strategies are rejected at load")
    func unknownStrategyIsRejected() {
        let specData = makeEngineSpecData(steps: """
            [\(makeStep(parse: #"{"checks":[],"snapshot":{"quotaWindows":{"strategy":"bogus","path":"items"}}}"#))]
            """)
        #expect(throws: ProviderSpecError.unknownStrategy("bogus")) {
            _ = try ProviderSpec(data: specData)
        }
    }

    @Test("byRegion tables missing a supported region are rejected at load")
    func incompleteByRegionTableIsRejected() {
        let specData = makeEngineSpecData(
            supported: #"[{"region":"china","credentialKind":"standard"},{"region":"international","credentialKind":"standard"}]"#,
            detect: #"{"strategy":"fixedProfile","profile":{"region":"china","credentialKind":"standard"}}"#,
            steps: """
                [\(makeStep(url: #"{"byRegion":{"china":"https://engine.test/cn"}}"#))]
                """
        )
        #expect {
            try ProviderSpec(data: specData)
        } throws: { error in
            guard case let ProviderSpecError.invalidSpec(message) = error else { return false }
            return message.contains("international")
        }
    }
}

@Suite("Provider catalog wiring")
struct ProviderCatalogWiringTests {
    @Test("The catalog builds one spec-driven provider per known provider id")
    func catalogCoversEveryProviderID() {
        let providers = ProviderCatalog.all
        #expect(providers.count == ProviderID.allCases.count)
        #expect(Set(providers.map(\.id)) == Set(ProviderID.allCases))
        #expect(providers.allSatisfy { $0 is SpecDrivenProvider })
    }

    @Test("Catalog descriptors match the contract spec descriptors")
    func catalogDescriptorsMatchSpecs() throws {
        let httpClient = ContractURLStubHTTPClient(responses: [:])
        let profiles: [ProviderProfile?] = [
            nil,
            ProviderProfile(region: .global, credentialKind: .standard),
            ProviderProfile(region: .global, credentialKind: .management),
            ProviderProfile(region: .global, credentialKind: .tokenPlan),
            ProviderProfile(region: .china, credentialKind: .standard),
            ProviderProfile(region: .international, credentialKind: .standard),
            ProviderProfile(region: .china, credentialKind: .tokenPlan),
            ProviderProfile(region: .international, credentialKind: .tokenPlan),
        ]

        for id in ProviderID.allCases {
            let engine = try contractSpecEngine(
                provider: id.rawValue.lowercased(),
                httpClient: httpClient
            )
            let descriptor = ProviderCatalog.descriptor(for: id)
            #expect(descriptor.id == engine.descriptor.id)
            #expect(descriptor.displayName == engine.descriptor.displayName)
            for profile in profiles {
                #expect(
                    descriptor.supportsLowBalanceThreshold(profile)
                        == engine.descriptor.supportsLowBalanceThreshold(profile)
                )
                for language in AppLanguage.allCases {
                    #expect(
                        descriptor.profileDescription(profile, language)
                            == engine.descriptor.profileDescription(profile, language)
                    )
                }
            }
        }
    }
}
