import Foundation

/// Errors thrown while loading or validating a provider spec. Load-time
/// validation rejects every spec the engine cannot execute, per
/// Contracts/README.md ("Provider spec schema (draft v1)").
public enum ProviderSpecError: Error, Equatable, Sendable {
    /// The spec declares a schema version newer than this engine implements.
    case unsupportedSpecVersion(Int)
    /// A snapshot field references an unknown named parse strategy.
    case unknownStrategy(String)
    /// Any other structural violation; the associated value describes it.
    case invalidSpec(String)
    /// `ProviderSpecLoader` found no spec resource for the provider id.
    case specNotFound(String)
}

/// Arbitrary JSON value, used for provider response bodies and spec literals.
/// Keeps the string/number distinction so decimal canonicalization can tell a
/// string-sourced decimal from a number-sourced one.
enum SpecJSONValue: Decodable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Decimal)
    case string(String)
    case array([SpecJSONValue])
    case object([String: SpecJSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Decimal.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: SpecJSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([SpecJSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value."
            )
        }
    }

    var isNumber: Bool {
        if case .number = self { return true }
        return false
    }
}

/// Decimal value carrying the canonical string form mandated by
/// Contracts/README.md ("Decimal and Money canonicalization"): string sources
/// are preserved verbatim after trimming, number sources use the shortest
/// round-trip rendering, and `subtract` renders the exact result canonically.
/// Swift compares amounts numerically, so the canonical form is pinned by the
/// ArkTS fixtures; both engines share these rules.
struct SpecDecimal: Equatable, Sendable {
    let value: Decimal
    let canonical: String

    /// Parses a numeric string (trimmed; `ProviderDecimal` semantics). The
    /// trimmed text is preserved verbatim as the canonical form.
    static func fromString(_ raw: String) -> SpecDecimal? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Decimal(
            string: trimmed,
            locale: Locale(identifier: "en_US_POSIX")
        ) else {
            return nil
        }
        return SpecDecimal(value: value, canonical: trimmed)
    }

    /// Wraps a JSON number; the canonical form is the shortest round-trip
    /// rendering (`6655.90` → "6655.9", `10` → "10").
    static func fromNumber(_ value: Decimal) -> SpecDecimal {
        SpecDecimal(
            value: value,
            canonical: NSDecimalNumber(decimal: value).stringValue
        )
    }

    /// Exact `a - b`, null-propagating; the result is rendered canonically.
    static func subtract(_ a: SpecDecimal?, _ b: SpecDecimal?) -> SpecDecimal? {
        guard let a, let b else { return nil }
        let result = a.value - b.value
        return SpecDecimal(
            value: result,
            canonical: NSDecimalNumber(decimal: result).stringValue
        )
    }
}

/// Coding key for the dynamically-keyed spec objects (value expressions,
/// conditions, fixed array entries).
struct SpecCodingKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }

    init(_ stringValue: String) {
        self.stringValue = stringValue
    }

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        return nil
    }
}

// MARK: - Spec model

struct ProfileSpec: Decodable, Sendable {
    let region: String
    let credentialKind: String
}

struct ProfilesSpec: Decodable, Sendable {
    let supported: [ProfileSpec]
}

struct ThresholdSpec: Decodable, Sendable {
    let always: Bool?
    let undetected: Bool?
    let credentialKinds: [String]?
}

struct UndetectedDescriptionSpec: Decodable, Sendable {
    let l10nKey: String
}

struct RegionDescriptionSpec: Decodable, Sendable {
    let l10nKey: String
    let args: [String]?
}

struct DetectedDescriptionSpec: Decodable, Sendable {
    let style: String?
    let byRegion: [String: RegionDescriptionSpec]?
}

struct ProfileDescriptionSpec: Decodable, Sendable {
    let undetected: UndetectedDescriptionSpec
    let detected: DetectedDescriptionSpec
}

struct DescriptorSpec: Decodable, Sendable {
    let supportsLowBalanceThreshold: ThresholdSpec
    let profileDescription: ProfileDescriptionSpec
}

struct RejectRuleSpec: Decodable, Sendable {
    let prefix: String
    let caseInsensitive: Bool
    let error: String

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: SpecCodingKey.self)
        prefix = try container.decode(String.self, forKey: SpecCodingKey("prefix"))
        caseInsensitive = try container.decodeIfPresent(
            Bool.self,
            forKey: SpecCodingKey("caseInsensitive")
        ) ?? false
        error = try container.decode(String.self, forKey: SpecCodingKey("error"))
    }
}

struct CredentialSpec: Decodable, Sendable {
    let trimWhitespace: Bool
    let reject: [RejectRuleSpec]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: SpecCodingKey.self)
        trimWhitespace = try container.decodeIfPresent(
            Bool.self,
            forKey: SpecCodingKey("trimWhitespace")
        ) ?? false
        reject = try container.decodeIfPresent(
            [RejectRuleSpec].self,
            forKey: SpecCodingKey("reject")
        ) ?? []
    }
}

struct DetectSpec: Decodable, Sendable {
    let strategy: String
    let profile: ProfileSpec?
    let candidates: [ProfileSpec]?
    let fallbackOn: [String]?
    let exhaustedError: String?
}

struct HeaderSpec: Decodable, Sendable {
    let name: String
    let value: String
}

/// Request URL: a fixed string, or a per-region table resolved by the region
/// the executing step runs under.
enum URLSpec: Decodable, Equatable, Sendable {
    case fixed(String)
    case byRegion([String: String])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let url = try? container.decode(String.self) {
            self = .fixed(url)
        } else if let table = try? container.decode([String: String].self) {
            self = .byRegion(table)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected a URL string or a byRegion table."
            )
        }
    }
}

struct RequestSpec: Decodable, Sendable {
    let method: String
    let url: URLSpec
    let headers: [HeaderSpec]
}

/// Status matcher of an `onStatus` branch: `2xx`, an exact code list, or the
/// catch-all `default`. First match wins, in array order.
enum StatusMatchSpec: Decodable, Equatable, Sendable {
    case twoXX
    case codes([Int])
    case `default`

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            switch text {
            case "2xx":
                self = .twoXX
            case "default":
                self = .default
            default:
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unknown status match '\(text)'."
                )
            }
        } else if let codes = try? container.decode([Int].self) {
            self = .codes(codes)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected \"2xx\", \"default\" or a code list."
            )
        }
    }
}

struct OnStatusSpec: Decodable, Sendable {
    let match: StatusMatchSpec
    let action: String
    let error: String?
    let step: String?
}

/// Boolean test of the closed condition set (`exists` / `equals` /
/// `notEquals` / `lt` / `gt` / `any` / `all`). A `step` field re-roots the
/// condition at an earlier step's parsed body.
struct SpecCondition: Decodable, Sendable {
    let step: String?
    let path: String?
    let exists: Bool?
    let equals: SpecJSONValue?
    let notEquals: SpecJSONValue?
    let lt: SpecJSONValue?
    let gt: SpecJSONValue?
    let any: [SpecCondition]?
    let all: [SpecCondition]?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: SpecCodingKey.self)
        step = try container.decodeIfPresent(String.self, forKey: SpecCodingKey("step"))
        path = try container.decodeIfPresent(String.self, forKey: SpecCodingKey("path"))
        exists = try container.decodeIfPresent(Bool.self, forKey: SpecCodingKey("exists"))
        if container.contains(SpecCodingKey("equals")) {
            equals = try container.decode(SpecJSONValue.self, forKey: SpecCodingKey("equals"))
        } else {
            equals = nil
        }
        if container.contains(SpecCodingKey("notEquals")) {
            notEquals = try container.decode(SpecJSONValue.self, forKey: SpecCodingKey("notEquals"))
        } else {
            notEquals = nil
        }
        if container.contains(SpecCodingKey("lt")) {
            lt = try container.decode(SpecJSONValue.self, forKey: SpecCodingKey("lt"))
        } else {
            lt = nil
        }
        if container.contains(SpecCodingKey("gt")) {
            gt = try container.decode(SpecJSONValue.self, forKey: SpecCodingKey("gt"))
        } else {
            gt = nil
        }
        any = try container.decodeIfPresent([SpecCondition].self, forKey: SpecCodingKey("any"))
        all = try container.decodeIfPresent([SpecCondition].self, forKey: SpecCodingKey("all"))
    }
}

struct EachItemCheckSpec: Decodable, Sendable {
    let of: String
    let path: String
    let type: String?
    let transforms: [String]?
    let required: Bool?
    let nonEmpty: Bool?
}

/// Ordered validation / error-mapping entry of a parse block's `checks`
/// array; the first failing entry throws. `strict` marks an optional value
/// that must still parse as `type` when present (a present-but-unparseable
/// optional rejects the payload, like a Swift optional `Decodable` field).
struct SpecCheck: Decodable, Sendable {
    let path: String?
    let type: String?
    let required: Bool?
    let nonEmpty: Bool?
    let strict: Bool?
    let transforms: [String]?
    let when: SpecCondition?
    let error: String?
    let eachItem: EachItemCheckSpec?
}

/// Reference box so `FieldBuilder` can nest (value types cannot directly
/// contain themselves).
final class BuilderBox: Decodable, @unchecked Sendable {
    let builder: FieldBuilder

    init(from decoder: Decoder) throws {
        builder = try FieldBuilder(from: decoder)
    }
}

struct MoneyBuilderSpec: Decodable, Sendable {
    let amount: BuilderBox
    let currency: BuilderBox
}

/// Entry of a `fixed` array builder: an optional `when` gate plus named
/// per-field builders, evaluated in the enclosing scope.
struct FixedEntrySpec: Decodable, Sendable {
    let when: SpecCondition?
    let fields: [String: FieldBuilder]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: SpecCodingKey.self)
        var when: SpecCondition?
        var fields: [String: FieldBuilder] = [:]
        for key in container.allKeys {
            if key.stringValue == "when" {
                when = try container.decode(SpecCondition.self, forKey: key)
            } else {
                fields[key.stringValue] = try container.decode(FieldBuilder.self, forKey: key)
            }
        }
        self.when = when
        self.fields = fields
    }
}

/// A snapshot field builder / value expression. Exactly one of the forms of
/// the closed set in Contracts/README.md ("Value expressions", "Snapshot
/// builders") is present; `when` optionally gates any of them.
struct FieldBuilder: Decodable, Sendable {
    let path: String?
    let type: String?
    let required: Bool
    let nonEmpty: Bool
    let transforms: [String]
    let nullIfEmpty: Bool
    let literal: SpecJSONValue?
    let valueReference: String?
    let valueExpression: BuilderBox?
    let byRegion: [String: SpecJSONValue]?
    let op: String?
    let a: BuilderBox?
    let b: BuilderBox?
    let when: SpecCondition?
    let object: [String: FieldBuilder]?
    let money: MoneyBuilderSpec?
    let template: String?
    let map: [String: String]?
    let fromArray: String?
    let itemValues: [String: FieldBuilder]?
    let item: [String: FieldBuilder]?
    let skipItemWhen: SpecCondition?
    let fixed: [FixedEntrySpec]?
    let strategy: String?
    let requireNonEmpty: Bool

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: SpecCodingKey.self)
        path = try container.decodeIfPresent(String.self, forKey: SpecCodingKey("path"))
        type = try container.decodeIfPresent(String.self, forKey: SpecCodingKey("type"))
        required = try container.decodeIfPresent(
            Bool.self,
            forKey: SpecCodingKey("required")
        ) ?? false
        nonEmpty = try container.decodeIfPresent(
            Bool.self,
            forKey: SpecCodingKey("nonEmpty")
        ) ?? false
        transforms = try container.decodeIfPresent(
            [String].self,
            forKey: SpecCodingKey("transforms")
        ) ?? []
        nullIfEmpty = try container.decodeIfPresent(
            Bool.self,
            forKey: SpecCodingKey("nullIfEmpty")
        ) ?? false
        if container.contains(SpecCodingKey("literal")) {
            literal = try container.decode(SpecJSONValue.self, forKey: SpecCodingKey("literal"))
        } else {
            literal = nil
        }
        if let reference = try? container.decode(String.self, forKey: SpecCodingKey("value")) {
            valueReference = reference
            valueExpression = nil
        } else {
            valueReference = nil
            valueExpression = try container.decodeIfPresent(
                BuilderBox.self,
                forKey: SpecCodingKey("value")
            )
        }
        byRegion = try container.decodeIfPresent(
            [String: SpecJSONValue].self,
            forKey: SpecCodingKey("byRegion")
        )
        op = try container.decodeIfPresent(String.self, forKey: SpecCodingKey("op"))
        a = try container.decodeIfPresent(BuilderBox.self, forKey: SpecCodingKey("a"))
        b = try container.decodeIfPresent(BuilderBox.self, forKey: SpecCodingKey("b"))
        when = try container.decodeIfPresent(SpecCondition.self, forKey: SpecCodingKey("when"))
        object = try container.decodeIfPresent(
            [String: FieldBuilder].self,
            forKey: SpecCodingKey("object")
        )
        money = try container.decodeIfPresent(MoneyBuilderSpec.self, forKey: SpecCodingKey("money"))
        template = try container.decodeIfPresent(String.self, forKey: SpecCodingKey("template"))
        map = try container.decodeIfPresent([String: String].self, forKey: SpecCodingKey("map"))
        fromArray = try container.decodeIfPresent(String.self, forKey: SpecCodingKey("fromArray"))
        itemValues = try container.decodeIfPresent(
            [String: FieldBuilder].self,
            forKey: SpecCodingKey("itemValues")
        )
        item = try container.decodeIfPresent(
            [String: FieldBuilder].self,
            forKey: SpecCodingKey("item")
        )
        skipItemWhen = try container.decodeIfPresent(
            SpecCondition.self,
            forKey: SpecCodingKey("skipItemWhen")
        )
        fixed = try container.decodeIfPresent([FixedEntrySpec].self, forKey: SpecCodingKey("fixed"))
        strategy = try container.decodeIfPresent(String.self, forKey: SpecCodingKey("strategy"))
        requireNonEmpty = try container.decodeIfPresent(
            Bool.self,
            forKey: SpecCodingKey("requireNonEmpty")
        ) ?? false
    }
}

struct CredentialKindDetectionSpec: Decodable, Sendable {
    let path: String
    let map: [String: String]
}

struct ParseSpec: Decodable, Sendable {
    let checks: [SpecCheck]?
    let values: [String: FieldBuilder]?
    let snapshot: [String: FieldBuilder]?
    let credentialKindDetection: CredentialKindDetectionSpec?
}

struct StepSpec: Decodable, Sendable {
    let name: String
    let when: SpecCondition?
    let onDemand: Bool
    let request: RequestSpec
    let onStatus: [OnStatusSpec]
    let parse: ParseSpec?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: SpecCodingKey.self)
        name = try container.decode(String.self, forKey: SpecCodingKey("name"))
        when = try container.decodeIfPresent(SpecCondition.self, forKey: SpecCodingKey("when"))
        onDemand = try container.decodeIfPresent(
            Bool.self,
            forKey: SpecCodingKey("onDemand")
        ) ?? false
        request = try container.decode(RequestSpec.self, forKey: SpecCodingKey("request"))
        onStatus = try container.decode([OnStatusSpec].self, forKey: SpecCodingKey("onStatus"))
        parse = try container.decodeIfPresent(ParseSpec.self, forKey: SpecCodingKey("parse"))
    }
}

struct FetchSpec: Decodable, Sendable {
    let steps: [StepSpec]
}

/// A decoded and validated provider spec (Contracts/Providers/<id>/spec.json).
/// The only way to build one is `init(data:)`, which decodes and validates.
public struct ProviderSpec: Decodable, Sendable {
    /// Highest `specVersion` this engine implements.
    public static let supportedSpecVersion = 1

    static let knownErrorTokens: Set<String> = [
        "invalidCredential",
        "rateLimited",
        "httpStatus",
        "invalidResponse",
        "providerInactive",
        "unsupportedCredential",
        "regionDetectionFailed",
        "profileMismatch",
    ]
    static let knownTransforms: Set<String> = ["trim", "uppercase"]
    static let knownStrategies: Set<String> = ["miniMaxModelRemains"]
    static let knownSnapshotFields: Set<String> = [
        "balances",
        "spendingLimit",
        "spend",
        "quotaWindows",
        "today",
        "total",
        "dailyUsage",
        "modelUsage",
        "providerStatus",
        "metricsUnavailableReason",
    ]

    let specVersion: Int
    let id: String
    let displayName: String
    let descriptor: DescriptorSpec
    let credential: CredentialSpec
    let profiles: ProfilesSpec
    let detect: DetectSpec
    let fetch: FetchSpec

    public init(data: Data) throws {
        let spec: ProviderSpec
        do {
            spec = try JSONDecoder().decode(ProviderSpec.self, from: data)
        } catch {
            throw ProviderSpecError.invalidSpec("spec decode failed: \(error)")
        }
        try spec.validate()
        self = spec
    }
}

// MARK: - Validation

extension ProviderSpec {
    func validate() throws {
        guard specVersion >= 1 else {
            throw ProviderSpecError.invalidSpec("specVersion must be a positive integer")
        }
        guard specVersion <= Self.supportedSpecVersion else {
            throw ProviderSpecError.unsupportedSpecVersion(specVersion)
        }
        guard ProviderID(rawValue: id) != nil else {
            throw ProviderSpecError.invalidSpec("unknown provider id '\(id)'")
        }
        for profile in profiles.supported {
            try Self.validateRegion(profile.region)
            try Self.validateCredentialKind(profile.credentialKind)
        }
        try validateDescriptor()
        for rule in credential.reject {
            try Self.validateErrorToken(rule.error)
        }
        let regions = try validateDetect()
        try validateFetch(regions: regions)
    }

    private func validateDescriptor() throws {
        let threshold = descriptor.supportsLowBalanceThreshold
        let hasAlways = threshold.always != nil
        let hasRule = threshold.undetected != nil || threshold.credentialKinds != nil
        guard hasAlways != hasRule else {
            throw ProviderSpecError.invalidSpec(
                "descriptor.supportsLowBalanceThreshold needs exactly one form"
            )
        }
        for kind in threshold.credentialKinds ?? [] {
            try Self.validateCredentialKind(kind)
        }
        try Self.validateL10nKey(descriptor.profileDescription.undetected.l10nKey)
        let detected = descriptor.profileDescription.detected
        if let style = detected.style {
            guard style == "regionCredential" || style == "credentialKind" else {
                throw ProviderSpecError.invalidSpec(
                    "unknown profileDescription style '\(style)'"
                )
            }
        } else if let byRegion = detected.byRegion {
            for (region, entry) in byRegion {
                try Self.validateRegion(region)
                try Self.validateL10nKey(entry.l10nKey)
                for arg in entry.args ?? [] {
                    guard arg == "credentialKind" else {
                        throw ProviderSpecError.invalidSpec(
                            "unknown profileDescription arg '\(arg)'"
                        )
                    }
                }
            }
        } else {
            throw ProviderSpecError.invalidSpec(
                "descriptor.profileDescription.detected needs a style or byRegion table"
            )
        }
    }

    /// Validates the detect block; returns the region set every `byRegion`
    /// table in the spec must cover.
    private func validateDetect() throws -> Set<String> {
        var regions = Set(profiles.supported.map { $0.region })
        switch detect.strategy {
        case "fixedProfile":
            guard let profile = detect.profile else {
                throw ProviderSpecError.invalidSpec("fixedProfile detect needs a profile")
            }
            try Self.validateRegion(profile.region)
            if profile.credentialKind != "detected" {
                try Self.validateCredentialKind(profile.credentialKind)
            }
            regions.insert(profile.region)
        case "regionFallback":
            guard let candidates = detect.candidates, !candidates.isEmpty else {
                throw ProviderSpecError.invalidSpec("regionFallback detect needs candidates")
            }
            for candidate in candidates {
                try Self.validateRegion(candidate.region)
                try Self.validateCredentialKind(candidate.credentialKind)
                regions.insert(candidate.region)
            }
            guard let fallbackOn = detect.fallbackOn, !fallbackOn.isEmpty else {
                throw ProviderSpecError.invalidSpec("regionFallback detect needs fallbackOn")
            }
            for token in fallbackOn {
                try Self.validateErrorToken(token)
            }
            guard let exhaustedError = detect.exhaustedError else {
                throw ProviderSpecError.invalidSpec("regionFallback detect needs exhaustedError")
            }
            try Self.validateErrorToken(exhaustedError)
        default:
            throw ProviderSpecError.invalidSpec("unknown detect strategy '\(detect.strategy)'")
        }
        return regions
    }

    private func validateFetch(regions: Set<String>) throws {
        guard !fetch.steps.isEmpty else {
            throw ProviderSpecError.invalidSpec("fetch needs at least one step")
        }
        var stepNames = Set<String>()
        for (index, step) in fetch.steps.enumerated() {
            guard stepNames.insert(step.name).inserted else {
                throw ProviderSpecError.invalidSpec("duplicate step name '\(step.name)'")
            }
            guard index > 0 || step.when == nil else {
                throw ProviderSpecError.invalidSpec("the first step must not have a when clause")
            }
        }
        for step in fetch.steps {
            try validateStep(step, stepNames: stepNames, regions: regions)
        }
    }

    private func validateStep(
        _ step: StepSpec,
        stepNames: Set<String>,
        regions: Set<String>
    ) throws {
        let context = "step '\(step.name)'"
        if let when = step.when {
            try Self.validateCondition(when, stepNames: stepNames, context: context)
        }
        if case let .byRegion(table) = step.request.url {
            for region in regions {
                guard table[region] != nil else {
                    throw ProviderSpecError.invalidSpec(
                        "\(context): request url byRegion table misses region '\(region)'"
                    )
                }
            }
        }
        guard !step.onStatus.isEmpty else {
            throw ProviderSpecError.invalidSpec("\(context): onStatus must not be empty")
        }
        for branch in step.onStatus {
            switch branch.action {
            case "parse":
                break
            case "error":
                guard let token = branch.error else {
                    throw ProviderSpecError.invalidSpec("\(context): error branch needs an error")
                }
                try Self.validateErrorToken(token)
            case "gotoStep":
                guard let target = branch.step, stepNames.contains(target) else {
                    throw ProviderSpecError.invalidSpec(
                        "\(context): gotoStep targets an unknown step"
                    )
                }
            default:
                throw ProviderSpecError.invalidSpec(
                    "\(context): unknown onStatus action '\(branch.action)'"
                )
            }
        }
        guard let parse = step.parse else { return }
        for check in parse.checks ?? [] {
            try Self.validateCheck(check, stepNames: stepNames, context: context)
        }
        for (name, builder) in parse.values ?? [:] {
            try Self.validateBuilder(
                builder,
                regions: regions,
                stepNames: stepNames,
                context: "\(context) value '\(name)'"
            )
        }
        for (field, builder) in parse.snapshot ?? [:] {
            guard Self.knownSnapshotFields.contains(field) else {
                throw ProviderSpecError.invalidSpec(
                    "\(context): unknown snapshot field '\(field)'"
                )
            }
            if builder.strategy != nil, field != "quotaWindows" {
                throw ProviderSpecError.invalidSpec(
                    "\(context): named strategies are only valid for quotaWindows"
                )
            }
            try Self.validateBuilder(
                builder,
                regions: regions,
                stepNames: stepNames,
                context: "\(context) snapshot field '\(field)'"
            )
        }
        if let detection = parse.credentialKindDetection {
            for kind in detection.map.values {
                try Self.validateCredentialKind(kind)
            }
        }
    }

    private static func validateCheck(
        _ check: SpecCheck,
        stepNames: Set<String>,
        context: String
    ) throws {
        if let eachItem = check.eachItem {
            for transform in eachItem.transforms ?? [] {
                try validateTransform(transform, context: context)
            }
        } else {
            guard check.path != nil else {
                throw ProviderSpecError.invalidSpec("\(context): check entry needs a path")
            }
            for transform in check.transforms ?? [] {
                try validateTransform(transform, context: context)
            }
            if check.required != true, check.when == nil, check.strict != true {
                throw ProviderSpecError.invalidSpec(
                    "\(context): check entry needs required, strict, or when"
                )
            }
            if check.strict == true, check.type == nil {
                throw ProviderSpecError.invalidSpec(
                    "\(context): strict check needs a type"
                )
            }
        }
        if let when = check.when {
            try validateCondition(when, stepNames: stepNames, context: context)
        }
        if let type = check.type ?? check.eachItem?.type {
            try validateValueType(type, context: context)
        }
        if let error = check.error {
            try validateErrorToken(error)
        }
    }

    private static func validateBuilder(
        _ builder: FieldBuilder,
        regions: Set<String>,
        stepNames: Set<String>,
        context: String
    ) throws {
        let hasForm = builder.object != nil
            || builder.money != nil
            || builder.template != nil
            || builder.fromArray != nil
            || builder.fixed != nil
            || builder.strategy != nil
            || builder.op != nil
            || builder.valueExpression != nil
            || builder.valueReference != nil
            || builder.byRegion != nil
            || builder.literal != nil
            || builder.map != nil
            || builder.path != nil
        guard hasForm else {
            throw ProviderSpecError.invalidSpec("\(context): empty builder")
        }
        for transform in builder.transforms {
            try validateTransform(transform, context: context)
        }
        if builder.path != nil,
           builder.map == nil,
           builder.op == nil,
           builder.strategy == nil {
            guard let type = builder.type else {
                throw ProviderSpecError.invalidSpec("\(context): path builder needs a type")
            }
            try validateValueType(type, context: context)
        }
        if let when = builder.when {
            try validateCondition(when, stepNames: stepNames, context: context)
        }
        if let object = builder.object {
            for (name, nested) in object {
                try validateBuilder(
                    nested,
                    regions: regions,
                    stepNames: stepNames,
                    context: "\(context).\(name)"
                )
            }
        }
        if let money = builder.money {
            try validateBuilder(
                money.amount.builder,
                regions: regions,
                stepNames: stepNames,
                context: "\(context).amount"
            )
            try validateBuilder(
                money.currency.builder,
                regions: regions,
                stepNames: stepNames,
                context: "\(context).currency"
            )
        }
        if builder.fromArray != nil {
            for (name, nested) in builder.itemValues ?? [:] {
                try validateBuilder(
                    nested,
                    regions: regions,
                    stepNames: stepNames,
                    context: "\(context).itemValues.\(name)"
                )
            }
            guard let item = builder.item else {
                throw ProviderSpecError.invalidSpec("\(context): fromArray needs an item builder")
            }
            for (name, nested) in item {
                try validateBuilder(
                    nested,
                    regions: regions,
                    stepNames: stepNames,
                    context: "\(context).item.\(name)"
                )
            }
            if let skipItemWhen = builder.skipItemWhen {
                try validateCondition(skipItemWhen, stepNames: stepNames, context: context)
            }
        }
        if let fixed = builder.fixed {
            for entry in fixed {
                if let when = entry.when {
                    try validateCondition(when, stepNames: stepNames, context: context)
                }
                for (name, nested) in entry.fields {
                    try validateBuilder(
                        nested,
                        regions: regions,
                        stepNames: stepNames,
                        context: "\(context).\(name)"
                    )
                }
            }
        }
        if let strategy = builder.strategy {
            guard knownStrategies.contains(strategy) else {
                throw ProviderSpecError.unknownStrategy(strategy)
            }
            guard builder.path != nil else {
                throw ProviderSpecError.invalidSpec("\(context): strategy needs a path")
            }
        }
        if let op = builder.op {
            switch op {
            case "subtract":
                guard let a = builder.a, let b = builder.b else {
                    throw ProviderSpecError.invalidSpec("\(context): subtract needs a and b")
                }
                try validateBuilder(
                    a.builder,
                    regions: regions,
                    stepNames: stepNames,
                    context: "\(context).a"
                )
                try validateBuilder(
                    b.builder,
                    regions: regions,
                    stepNames: stepNames,
                    context: "\(context).b"
                )
            case "count":
                guard builder.path != nil else {
                    throw ProviderSpecError.invalidSpec("\(context): count needs a path")
                }
            default:
                throw ProviderSpecError.invalidSpec("\(context): unknown op '\(op)'")
            }
        }
        if let valueExpression = builder.valueExpression {
            try validateBuilder(
                valueExpression.builder,
                regions: regions,
                stepNames: stepNames,
                context: context
            )
        }
        if let byRegion = builder.byRegion {
            for region in regions {
                guard byRegion[region] != nil else {
                    throw ProviderSpecError.invalidSpec(
                        "\(context): byRegion table misses region '\(region)'"
                    )
                }
            }
            for value in byRegion.values {
                try validateScalar(value, context: context)
            }
        }
        if let literal = builder.literal {
            try validateScalar(literal, context: context)
        }
        if builder.map != nil {
            guard builder.path != nil else {
                throw ProviderSpecError.invalidSpec("\(context): map needs a path")
            }
        }
    }

    private static func validateCondition(
        _ condition: SpecCondition,
        stepNames: Set<String>,
        context: String
    ) throws {
        if let any = condition.any {
            guard !any.isEmpty else {
                throw ProviderSpecError.invalidSpec("\(context): any needs at least one condition")
            }
            for nested in any {
                try validateCondition(nested, stepNames: stepNames, context: context)
            }
            return
        }
        if let all = condition.all {
            guard !all.isEmpty else {
                throw ProviderSpecError.invalidSpec("\(context): all needs at least one condition")
            }
            for nested in all {
                try validateCondition(nested, stepNames: stepNames, context: context)
            }
            return
        }
        if let step = condition.step {
            guard stepNames.contains(step) else {
                throw ProviderSpecError.invalidSpec(
                    "\(context): condition references unknown step '\(step)'"
                )
            }
        }
        let operators = [
            condition.exists != nil,
            condition.equals != nil,
            condition.notEquals != nil,
            condition.lt != nil,
            condition.gt != nil,
        ].filter { $0 }.count
        guard operators == 1 else {
            throw ProviderSpecError.invalidSpec(
                "\(context): condition needs exactly one operator"
            )
        }
        if let bound = condition.lt, !bound.isNumber {
            throw ProviderSpecError.invalidSpec("\(context): lt expects a JSON number")
        }
        if let bound = condition.gt, !bound.isNumber {
            throw ProviderSpecError.invalidSpec("\(context): gt expects a JSON number")
        }
    }

    private static func validateScalar(_ value: SpecJSONValue, context: String) throws {
        switch value {
        case .null, .bool, .number, .string:
            return
        case .array, .object:
            throw ProviderSpecError.invalidSpec("\(context): expected a JSON scalar")
        }
    }

    private static func validateRegion(_ region: String) throws {
        guard ProviderRegion(rawValue: region) != nil else {
            throw ProviderSpecError.invalidSpec("unknown region '\(region)'")
        }
    }

    private static func validateCredentialKind(_ kind: String) throws {
        guard ProviderCredentialKind(rawValue: kind) != nil else {
            throw ProviderSpecError.invalidSpec("unknown credential kind '\(kind)'")
        }
    }

    private static func validateErrorToken(_ token: String) throws {
        guard knownErrorTokens.contains(token) else {
            throw ProviderSpecError.invalidSpec("unknown error token '\(token)'")
        }
    }

    private static func validateL10nKey(_ key: String) throws {
        guard L10nKey(rawValue: key) != nil else {
            throw ProviderSpecError.invalidSpec("unknown L10n key '\(key)'")
        }
    }

    private static func validateTransform(_ transform: String, context: String) throws {
        guard knownTransforms.contains(transform) else {
            throw ProviderSpecError.invalidSpec("\(context): unknown transform '\(transform)'")
        }
    }

    private static func validateValueType(_ type: String, context: String) throws {
        guard ["decimal", "string", "int", "bool"].contains(type) else {
            throw ProviderSpecError.invalidSpec("\(context): unknown value type '\(type)'")
        }
    }
}

// MARK: - Resource loading

/// Loads spec resources bundled with the core target. `scripts/sync-specs-to-core.sh`
/// copies `Contracts/Providers/<dir>/spec.json` into
/// `Sources/QuotaGlanceCore/Resources/ProviderSpecs/<id>.json` (camelCase id),
/// which SwiftPM ships through `.process("Resources")`; tests can also load
/// `Contracts/Providers/<id>/spec.json` directly through `ProviderSpec(data:)`.
public enum ProviderSpecLoader {
    /// Reads `<id>.json` from the core target's resource bundle
    /// (`Bundle.module`) and returns the validated spec.
    public static func spec(for id: ProviderID) throws -> ProviderSpec {
        try spec(for: id, in: .module)
    }

    /// Reads `<id>.json` (camelCase provider id) from the bundle's
    /// `ProviderSpecs` resource directory and returns the validated spec.
    public static func spec(for id: ProviderID, in bundle: Bundle) throws -> ProviderSpec {
        try ProviderSpec(data: specData(for: id, in: bundle))
    }

    /// Reads `<id>.json` (camelCase provider id) from the bundle's
    /// `ProviderSpecs` resource directory.
    public static func specData(for id: ProviderID, in bundle: Bundle) throws -> Data {
        let name = id.rawValue
        guard let url = bundle.url(
            forResource: name,
            withExtension: "json",
            subdirectory: "ProviderSpecs"
        ) else {
            throw ProviderSpecError.specNotFound(name)
        }
        return try Data(contentsOf: url)
    }
}
