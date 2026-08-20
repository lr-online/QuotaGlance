import Foundation

/// Evaluated form of a spec builder, before per-field assembly into the
/// typed `ProviderUsageSnapshot` model.
indirect enum SpecEvalValue: Equatable, Sendable {
    case decimal(SpecDecimal)
    case string(String)
    case int(Int64)
    case bool(Bool)
    case date(Date)
    case money(amount: SpecDecimal, currency: String)
    case object([String: SpecEvalValue])
    case array([SpecEvalValue])
}

/// Evaluation scope of one parse block (or one array item). Named values
/// (`values` / `itemValues`) are resolved lazily and memoized; item scopes
/// fall through to the enclosing step scope.
final class SpecEvaluationScope {
    let root: SpecJSONValue
    let region: ProviderRegion
    let steps: [String: SpecJSONValue]
    private let namedBuilders: [String: FieldBuilder]
    private let parent: SpecEvaluationScope?
    private var cache: [String: SpecEvalValue?] = [:]
    private var resolving: Set<String> = []

    init(
        root: SpecJSONValue,
        region: ProviderRegion,
        steps: [String: SpecJSONValue],
        namedBuilders: [String: FieldBuilder],
        parent: SpecEvaluationScope?
    ) {
        self.root = root
        self.region = region
        self.steps = steps
        self.namedBuilders = namedBuilders
        self.parent = parent
    }

    func namedValue(_ name: String) throws -> SpecEvalValue? {
        if let cached = cache[name] {
            return cached
        }
        guard let builder = namedBuilders[name] else {
            return try parent?.namedValue(name)
        }
        guard resolving.insert(name).inserted else {
            throw ProviderError.invalidResponse
        }
        let value = try SpecEngine.evaluate(builder, in: self)
        resolving.remove(name)
        cache[name] = value
        return value
    }
}

/// The closed evaluation semantics of the spec schema: dot-path resolution,
/// value expressions, conditions, checks, and error-token mapping.
enum SpecEngine {
    // MARK: Paths and scalar extraction

    /// Resolves a dot-separated path. A missing key, an explicit `null`, or a
    /// non-object intermediate all resolve to absent (nil), per the schema.
    static func resolve(_ root: SpecJSONValue?, _ path: String) -> SpecJSONValue? {
        var current = root
        for key in path.split(separator: ".") {
            guard case let .object(fields)? = current,
                  let next = fields[String(key)] else {
                return nil
            }
            current = next
        }
        if case .null? = current {
            return nil
        }
        return current
    }

    /// Decimal extraction, number-or-string (`ProviderDecimal` semantics).
    static func decimal(_ value: SpecJSONValue?) -> SpecDecimal? {
        switch value {
        case let .number(number)?:
            return .fromNumber(number)
        case let .string(string)?:
            return .fromString(string)
        default:
            return nil
        }
    }

    static func integer(_ value: SpecJSONValue?) -> Int64? {
        guard case let .number(number)? = value else { return nil }
        var original = number
        var rounded = Decimal()
        NSDecimalRound(&rounded, &original, 0, .plain)
        guard rounded == number else { return nil }
        guard number >= Decimal(-9_223_372_036_854_775_808),
              number <= Decimal(9_223_372_036_854_775_807) else {
            return nil
        }
        return NSDecimalNumber(decimal: number).int64Value
    }

    static func stringValue(_ value: SpecJSONValue?) -> String? {
        guard case let .string(string)? = value else { return nil }
        return string
    }

    static func boolValue(_ value: SpecJSONValue?) -> Bool? {
        guard case let .bool(bool)? = value else { return nil }
        return bool
    }

    static func dateValue(_ value: SpecJSONValue?) -> Date? {
        guard case let .string(string)? = value else { return nil }
        return ISO8601DateFormatter().date(from: string)
    }

    /// Renders a scalar for `map` lookups and `credentialKindDetection` keys:
    /// bools as "true"/"false", numbers in canonical decimal form, strings
    /// verbatim.
    static func scalarKey(_ value: SpecJSONValue?) -> String? {
        switch value {
        case let .bool(bool)?:
            return bool ? "true" : "false"
        case let .number(number)?:
            return SpecDecimal.fromNumber(number).canonical
        case let .string(string)?:
            return string
        default:
            return nil
        }
    }

    // MARK: Conditions

    static func evaluateCondition(
        _ condition: SpecCondition,
        root: SpecJSONValue?,
        steps: [String: SpecJSONValue]
    ) -> Bool {
        if let any = condition.any {
            return any.contains { evaluateCondition($0, root: root, steps: steps) }
        }
        if let all = condition.all {
            return all.allSatisfy { evaluateCondition($0, root: root, steps: steps) }
        }
        var base = root
        if let stepName = condition.step {
            base = steps[stepName]
        }
        let actual: SpecJSONValue?
        if let path = condition.path {
            actual = resolve(base, path)
        } else {
            switch base {
            case .null?:
                actual = nil
            default:
                actual = base
            }
        }
        if let expected = condition.exists {
            return (actual != nil) == expected
        }
        if let expected = condition.equals {
            return scalarEquals(actual, expected)
        }
        if let expected = condition.notEquals {
            return actual != nil && !scalarEquals(actual, expected)
        }
        if let bound = condition.lt {
            guard case let .number(limit) = bound,
                  let value = decimal(actual) else {
                return false
            }
            return value.value < limit
        }
        if let bound = condition.gt {
            guard case let .number(limit) = bound,
                  let value = decimal(actual) else {
                return false
            }
            return value.value > limit
        }
        return false
    }

    /// `equals` semantics: a numeric expectation parses the actual value as a
    /// decimal (number-or-string) and compares numerically; anything else is
    /// an exact scalar comparison. Absent actual is never equal.
    static func scalarEquals(_ actual: SpecJSONValue?, _ expected: SpecJSONValue) -> Bool {
        switch expected {
        case .null:
            return actual == nil
        case let .bool(expectedValue):
            return boolValue(actual) == expectedValue
        case let .number(expectedValue):
            return decimal(actual)?.value == expectedValue
        case let .string(expectedValue):
            guard case let .string(actualValue)? = actual else { return false }
            return actualValue == expectedValue
        case .array, .object:
            return false
        }
    }

    // MARK: Checks

    /// Evaluates a parse block's ordered `checks`; the first failing entry
    /// throws its named error (default `invalidResponse`).
    static func runChecks(_ checks: [SpecCheck], body: SpecJSONValue) throws {
        for check in checks {
            if let eachItem = check.eachItem {
                guard let resolved = resolve(body, eachItem.of) else { continue }
                guard case let .array(elements) = resolved else {
                    throw engineError(check.error)
                }
                for element in elements {
                    try requireValue(
                        resolve(element, eachItem.path),
                        type: eachItem.type,
                        transforms: eachItem.transforms ?? [],
                        required: eachItem.required ?? false,
                        nonEmpty: eachItem.nonEmpty ?? false,
                        error: check.error
                    )
                }
                continue
            }
            guard let path = check.path else {
                throw ProviderSpecError.invalidSpec("check entry without a path")
            }
            let raw = resolve(body, path)
            if check.required == true {
                try requireValue(
                    raw,
                    type: check.type,
                    transforms: check.transforms ?? [],
                    required: true,
                    nonEmpty: check.nonEmpty ?? false,
                    error: check.error
                )
            }
            if check.strict == true {
                // Optional but validated when present: absent is fine, a
                // present value that fails the type/nonEmpty rules throws.
                try requireValue(
                    raw,
                    type: check.type,
                    transforms: check.transforms ?? [],
                    required: false,
                    nonEmpty: check.nonEmpty ?? false,
                    error: check.error
                )
            }
            if let when = check.when,
               evaluateCondition(when, root: raw, steps: [:]) {
                throw engineError(check.error)
            }
        }
    }

    private static func requireValue(
        _ raw: SpecJSONValue?,
        type: String?,
        transforms: [String],
        required: Bool,
        nonEmpty: Bool,
        error token: String?
    ) throws {
        let failure = engineError(token)
        guard let raw else {
            if required { throw failure }
            return
        }
        if let type {
            let parseable: Bool
            switch type {
            case "decimal":
                parseable = decimal(raw) != nil
            case "string":
                parseable = stringValue(raw) != nil
            case "int":
                parseable = integer(raw) != nil
            case "bool":
                parseable = boolValue(raw) != nil
            case "date":
                parseable = dateValue(raw) != nil
            default:
                throw ProviderSpecError.invalidSpec("unknown value type '\(type)'")
            }
            guard parseable else { throw failure }
        }
        if nonEmpty {
            switch raw {
            case .string:
                guard let value = transformedString(raw, transforms: transforms),
                      !value.isEmpty else {
                    throw failure
                }
            case let .array(elements):
                guard !elements.isEmpty else { throw failure }
            default:
                break
            }
        }
    }

    private static func transformedString(
        _ raw: SpecJSONValue?,
        transforms: [String]
    ) -> String? {
        guard var value = stringValue(raw) else { return nil }
        for transform in transforms {
            switch transform {
            case "trim":
                value = value.trimmingCharacters(in: .whitespacesAndNewlines)
            case "uppercase":
                value = value.uppercased()
            default:
                break
            }
        }
        return value
    }

    // MARK: Value expressions and field builders

    static func evaluate(
        _ builder: FieldBuilder,
        in scope: SpecEvaluationScope
    ) throws -> SpecEvalValue? {
        if let when = builder.when,
           !evaluateCondition(when, root: scope.root, steps: scope.steps) {
            return nil
        }
        if let object = builder.object {
            var fields: [String: SpecEvalValue] = [:]
            for (key, nested) in object {
                if let value = try evaluate(nested, in: scope) {
                    fields[key] = value
                }
            }
            return .object(fields)
        }
        if let money = builder.money {
            guard let amountValue = try evaluate(money.amount.builder, in: scope),
                  let currencyValue = try evaluate(money.currency.builder, in: scope) else {
                return nil
            }
            guard case let .decimal(amount) = amountValue,
                  case let .string(currency) = currencyValue else {
                throw ProviderError.invalidResponse
            }
            return .money(amount: amount, currency: currency)
        }
        if let template = builder.template {
            return try renderTemplate(template, in: scope).map { .string($0) }
        }
        if let fromArray = builder.fromArray {
            return try evaluateArray(builder, path: fromArray, in: scope)
        }
        if let fixed = builder.fixed {
            return try evaluateFixed(fixed, in: scope)
        }
        if let strategy = builder.strategy {
            return try evaluateStrategy(builder, strategy: strategy, in: scope)
        }
        if let op = builder.op {
            switch op {
            case "subtract":
                guard let a = builder.a, let b = builder.b else {
                    throw ProviderError.invalidResponse
                }
                let aValue = try evaluate(a.builder, in: scope).flatMap(decimalValue)
                let bValue = try evaluate(b.builder, in: scope).flatMap(decimalValue)
                return SpecDecimal.subtract(aValue, bValue).map { .decimal($0) }
            case "count":
                guard let path = builder.path else {
                    throw ProviderError.invalidResponse
                }
                guard case let .array(elements)? = resolve(scope.root, path) else {
                    return nil
                }
                return .int(Int64(elements.count))
            default:
                throw ProviderSpecError.invalidSpec("unknown op '\(op)'")
            }
        }
        if let expression = builder.valueExpression {
            return try evaluate(expression.builder, in: scope)
        }
        if let reference = builder.valueReference {
            return try scope.namedValue(reference)
        }
        if let byRegion = builder.byRegion {
            guard let scalar = byRegion[scope.region.rawValue] else {
                throw ProviderSpecError.invalidSpec(
                    "byRegion table misses region '\(scope.region.rawValue)'"
                )
            }
            return try scalarValue(scalar)
        }
        if let literal = builder.literal {
            return try scalarValue(literal)
        }
        if let map = builder.map {
            guard let path = builder.path else {
                throw ProviderError.invalidResponse
            }
            guard let key = scalarKey(resolve(scope.root, path)) else { return nil }
            return map[key].map { .string($0) }
        }
        if builder.path != nil {
            return try evaluatePathBuilder(builder, in: scope)
        }
        throw ProviderError.invalidResponse
    }

    private static func evaluatePathBuilder(
        _ builder: FieldBuilder,
        in scope: SpecEvaluationScope
    ) throws -> SpecEvalValue? {
        guard let path = builder.path else {
            throw ProviderError.invalidResponse
        }
        let raw = resolve(scope.root, path)
        switch builder.type {
        case "decimal":
            guard let value = decimal(raw) else {
                if builder.required { throw ProviderError.invalidResponse }
                return nil
            }
            return .decimal(value)
        case "string":
            guard let value = transformedString(raw, transforms: builder.transforms) else {
                if builder.required { throw ProviderError.invalidResponse }
                return nil
            }
            if value.isEmpty {
                if builder.required, builder.nonEmpty {
                    throw ProviderError.invalidResponse
                }
                if builder.nullIfEmpty { return nil }
            }
            return .string(value)
        case "int":
            guard let value = integer(raw) else {
                if builder.required { throw ProviderError.invalidResponse }
                return nil
            }
            return .int(value)
        case "bool":
            guard let value = boolValue(raw) else {
                if builder.required { throw ProviderError.invalidResponse }
                return nil
            }
            return .bool(value)
        case "date":
            guard let value = dateValue(raw) else {
                if builder.required { throw ProviderError.invalidResponse }
                return nil
            }
            return .date(value)
        default:
            throw ProviderSpecError.invalidSpec(
                "unknown value type '\(builder.type ?? "")'"
            )
        }
    }

    private static func evaluateArray(
        _ builder: FieldBuilder,
        path: String,
        in scope: SpecEvaluationScope
    ) throws -> SpecEvalValue {
        guard let resolved = resolve(scope.root, path) else {
            return .array([])
        }
        guard case let .array(elements) = resolved else {
            throw ProviderError.invalidResponse
        }
        var results: [SpecEvalValue] = []
        for element in elements {
            guard case .object = element else {
                throw ProviderError.invalidResponse
            }
            let itemScope = SpecEvaluationScope(
                root: element,
                region: scope.region,
                steps: scope.steps,
                namedBuilders: builder.itemValues ?? [:],
                parent: scope
            )
            if let skipItemWhen = builder.skipItemWhen,
               evaluateCondition(skipItemWhen, root: element, steps: scope.steps) {
                continue
            }
            var fields: [String: SpecEvalValue] = [:]
            for (key, nested) in builder.item ?? [:] {
                if let value = try evaluate(nested, in: itemScope) {
                    fields[key] = value
                }
            }
            results.append(.object(fields))
        }
        return .array(results)
    }

    private static func evaluateFixed(
        _ entries: [FixedEntrySpec],
        in scope: SpecEvaluationScope
    ) throws -> SpecEvalValue {
        var results: [SpecEvalValue] = []
        for entry in entries {
            if let when = entry.when,
               !evaluateCondition(when, root: scope.root, steps: scope.steps) {
                continue
            }
            var fields: [String: SpecEvalValue] = [:]
            for (key, nested) in entry.fields {
                if let value = try evaluate(nested, in: scope) {
                    fields[key] = value
                }
            }
            results.append(.object(fields))
        }
        return .array(results)
    }

    private static func evaluateStrategy(
        _ builder: FieldBuilder,
        strategy: String,
        in scope: SpecEvaluationScope
    ) throws -> SpecEvalValue {
        guard strategy == "miniMaxModelRemains" else {
            throw ProviderSpecError.unknownStrategy(strategy)
        }
        let source = builder.path.flatMap { resolve(scope.root, $0) }
        let windows = MiniMaxModelRemainsStrategy.quotaWindows(from: source)
        if builder.requireNonEmpty, windows.isEmpty {
            throw ProviderError.invalidResponse
        }
        return quotaWindowsValue(windows)
    }

    private static func scalarValue(_ json: SpecJSONValue) throws -> SpecEvalValue? {
        switch json {
        case .null:
            return nil
        case let .bool(bool):
            return .bool(bool)
        case let .number(number):
            return .decimal(.fromNumber(number))
        case let .string(string):
            return .string(string)
        case .array, .object:
            throw ProviderError.invalidResponse
        }
    }

    private static func decimalValue(_ value: SpecEvalValue) -> SpecDecimal? {
        guard case let .decimal(decimal) = value else { return nil }
        return decimal
    }

    /// Interpolates `${name}` references against named values only; any
    /// unresolved or null reference nulls the whole template.
    private static func renderTemplate(
        _ template: String,
        in scope: SpecEvaluationScope
    ) throws -> String? {
        var result = ""
        var index = template.startIndex
        while let start = template.range(of: "${", range: index..<template.endIndex) {
            result += template[index..<start.lowerBound]
            guard let end = template.range(of: "}", range: start.upperBound..<template.endIndex) else {
                result += template[start.lowerBound...]
                return result
            }
            let name = String(template[start.upperBound..<end.lowerBound])
            guard let value = try scope.namedValue(name),
                  let rendered = renderScalar(value) else {
                return nil
            }
            result += rendered
            index = end.upperBound
        }
        result += template[index...]
        return result
    }

    private static func renderScalar(_ value: SpecEvalValue) -> String? {
        switch value {
        case let .string(string):
            return string
        case let .int(int):
            return String(int)
        case let .decimal(decimal):
            return decimal.canonical
        case let .bool(bool):
            return bool ? "true" : "false"
        case .date, .money, .object, .array:
            return nil
        }
    }

    private static func quotaWindowsValue(_ windows: [QuotaWindow]) -> SpecEvalValue {
        .array(windows.map { window in
            var fields: [String: SpecEvalValue] = [
                "label": .string(window.label),
                "unit": .string(window.unit),
            ]
            if let used = window.used {
                fields["used"] = .decimal(.fromNumber(used))
            }
            if let limit = window.limit {
                fields["limit"] = .decimal(.fromNumber(limit))
            }
            if let remaining = window.remaining {
                fields["remaining"] = .decimal(.fromNumber(remaining))
            }
            if let resetsAt = window.resetsAt {
                fields["resetsAt"] = .date(resetsAt)
            }
            return .object(fields)
        })
    }

    // MARK: Error tokens

    static func engineError(_ token: String?, statusCode: Int? = nil) -> ProviderError {
        switch token {
        case "invalidCredential":
            return .invalidCredential
        case "rateLimited":
            return .rateLimited
        case "httpStatus":
            return .httpStatus(statusCode ?? 0)
        case "providerInactive":
            return .providerInactive
        case "unsupportedCredential":
            return .unsupportedCredential
        case "regionDetectionFailed":
            return .regionDetectionFailed
        case "profileMismatch":
            return .profileMismatch
        default:
            return .invalidResponse
        }
    }

    static func errorToken(for error: ProviderError) -> String {
        switch error {
        case .invalidCredential:
            return "invalidCredential"
        case .rateLimited:
            return "rateLimited"
        case .httpStatus:
            return "httpStatus"
        case .invalidResponse:
            return "invalidResponse"
        case .providerInactive:
            return "providerInactive"
        case .unsupportedCredential:
            return "unsupportedCredential"
        case .regionDetectionFailed:
            return "regionDetectionFailed"
        case .profileMismatch:
            return "profileMismatch"
        case .providerUnavailable:
            return "providerUnavailable"
        }
    }
}

/// Assembles evaluated field values into the typed snapshot model. Structural
/// mismatches are `invalidResponse`, matching the hand-written providers'
/// catch-all for parse failures.
enum SpecSnapshotAssembly {
    static func string(_ value: SpecEvalValue?) throws -> String? {
        guard let value else { return nil }
        guard case let .string(string) = value else {
            throw ProviderError.invalidResponse
        }
        return string
    }

    static func decimal(_ value: SpecEvalValue?) throws -> Decimal? {
        guard let value else { return nil }
        guard case let .decimal(decimal) = value else {
            throw ProviderError.invalidResponse
        }
        return decimal.value
    }

    static func int(_ value: SpecEvalValue?) throws -> Int64? {
        guard let value else { return nil }
        guard case let .int(int) = value else {
            throw ProviderError.invalidResponse
        }
        return int
    }

    static func money(_ value: SpecEvalValue?) throws -> Money? {
        guard let value else { return nil }
        guard case let .money(amount, currency) = value else {
            throw ProviderError.invalidResponse
        }
        return Money(amount: amount.value, currency: currency)
    }

    static func object(_ value: SpecEvalValue) throws -> [String: SpecEvalValue] {
        guard case let .object(fields) = value else {
            throw ProviderError.invalidResponse
        }
        return fields
    }

    static func array(_ value: SpecEvalValue) throws -> [SpecEvalValue] {
        guard case let .array(elements) = value else {
            throw ProviderError.invalidResponse
        }
        return elements
    }

    static func balances(_ value: SpecEvalValue) throws -> [MonetaryBalance] {
        try array(value).map { item in
            let fields = try object(item)
            guard let label = try string(fields["label"]),
                  let available = try money(fields["available"]) else {
                throw ProviderError.invalidResponse
            }
            let breakdown = try fields["breakdown"].map(monetaryValues) ?? []
            return MonetaryBalance(label: label, available: available, breakdown: breakdown)
        }
    }

    static func monetaryValues(_ value: SpecEvalValue) throws -> [MonetaryValue] {
        try array(value).map { item in
            let fields = try object(item)
            guard let label = try string(fields["label"]),
                  let itemValue = try money(fields["value"]) else {
                throw ProviderError.invalidResponse
            }
            return MonetaryValue(label: label, value: itemValue)
        }
    }

    static func spendingLimit(_ value: SpecEvalValue) throws -> SpendingLimit {
        let fields = try object(value)
        guard let label = try string(fields["label"]) else {
            throw ProviderError.invalidResponse
        }
        return SpendingLimit(
            label: label,
            used: try money(fields["used"]),
            limit: try money(fields["limit"]),
            remaining: try money(fields["remaining"]),
            resetDescription: try string(fields["resetDescription"])
        )
    }

    static func spend(_ value: SpecEvalValue) throws -> SpendSummary {
        let fields = try object(value)
        return SpendSummary(
            today: try money(fields["today"]),
            week: try money(fields["week"]),
            month: try money(fields["month"]),
            total: try money(fields["total"])
        )
    }

    static func counters(_ value: SpecEvalValue) throws -> UsageCounters {
        let fields = try object(value)
        return UsageCounters(
            actualCost: try money(fields["actualCost"]),
            requests: try int(fields["requests"]),
            inputTokens: try int(fields["inputTokens"]),
            outputTokens: try int(fields["outputTokens"]),
            cacheReadTokens: try int(fields["cacheReadTokens"]),
            cacheCreationTokens: try int(fields["cacheCreationTokens"]),
            totalTokens: try int(fields["totalTokens"])
        )
    }

    static func dailyUsage(_ value: SpecEvalValue) throws -> [DailyUsage] {
        try array(value).compactMap { item in
            let fields = try object(item)
            guard let date = try string(fields["date"]) else {
                throw ProviderError.invalidResponse
            }
            // DailyUsage.actualCost is non-optional; entries the spec did not
            // already filter out but that still lack a cost are dropped, like
            // the hand-written compactMap.
            guard let actualCost = try money(fields["actualCost"]) else {
                return nil
            }
            return DailyUsage(
                date: date,
                actualCost: actualCost,
                requests: try int(fields["requests"]),
                totalTokens: try int(fields["totalTokens"])
            )
        }
    }

    static func modelUsage(_ value: SpecEvalValue) throws -> [ModelUsage] {
        try array(value).map { item in
            let fields = try object(item)
            guard let model = try string(fields["model"]) else {
                throw ProviderError.invalidResponse
            }
            return ModelUsage(
                model: model,
                actualCost: try money(fields["actualCost"]),
                requests: try int(fields["requests"]),
                totalTokens: try int(fields["totalTokens"])
            )
        }
    }

    static func quotaWindows(_ value: SpecEvalValue) throws -> [QuotaWindow] {
        try array(value).map { item in
            let fields = try object(item)
            guard let label = try string(fields["label"]),
                  let unit = try string(fields["unit"]) else {
                throw ProviderError.invalidResponse
            }
            var resetsAt: Date?
            if let raw = fields["resetsAt"] {
                guard case let .date(date) = raw else {
                    throw ProviderError.invalidResponse
                }
                resetsAt = date
            }
            return QuotaWindow(
                label: label,
                used: try decimal(fields["used"]),
                limit: try decimal(fields["limit"]),
                remaining: try decimal(fields["remaining"]),
                unit: unit,
                resetsAt: resetsAt
            )
        }
    }
}

/// A `UsageProvider` executing a declarative provider spec
/// (Contracts/Providers/<id>/spec.json) instead of hand-written per-provider
/// code. See Contracts/README.md ("Provider spec schema (draft v1)") for the
/// execution semantics this engine implements.
public struct SpecDrivenProvider: UsageProvider {
    public let id: ProviderID
    public let descriptor: ProviderDescriptor

    private let spec: ProviderSpec
    private let httpClient: any HTTPClient
    private let preferredRegion: ProviderRegion?
    private let now: @Sendable () -> Date

    public init(
        spec: ProviderSpec,
        httpClient: any HTTPClient = URLSessionHTTPClient(),
        preferredRegion: ProviderRegion? = nil,
        now: @escaping @Sendable () -> Date = { .now }
    ) throws {
        try spec.validate()
        guard let id = ProviderID(rawValue: spec.id) else {
            throw ProviderSpecError.invalidSpec("unknown provider id '\(spec.id)'")
        }
        self.spec = spec
        self.id = id
        self.httpClient = httpClient
        self.preferredRegion = preferredRegion
        self.now = now
        self.descriptor = Self.makeDescriptor(id: id, spec: spec)
    }

    public init(
        specData: Data,
        httpClient: any HTTPClient = URLSessionHTTPClient(),
        preferredRegion: ProviderRegion? = nil,
        now: @escaping @Sendable () -> Date = { .now }
    ) throws {
        try self.init(
            spec: ProviderSpec(data: specData),
            httpClient: httpClient,
            preferredRegion: preferredRegion,
            now: now
        )
    }

    // MARK: UsageProvider

    public func detect(apiKey: String) async throws -> ProviderDetection {
        let key = try preprocess(apiKey)
        switch spec.detect.strategy {
        case "fixedProfile":
            guard let declared = spec.detect.profile,
                  let region = ProviderRegion(rawValue: declared.region) else {
                throw ProviderSpecError.invalidSpec("fixedProfile detect needs a profile")
            }
            let concreteKind = ProviderCredentialKind(rawValue: declared.credentialKind)
            let pipelineProfile = ProviderProfile(
                region: region,
                credentialKind: concreteKind ?? .standard
            )
            let result = try await runPipeline(
                apiKey: key,
                profile: pipelineProfile,
                entryPoint: .detect
            )
            let kind: ProviderCredentialKind
            if let concreteKind {
                kind = concreteKind
            } else if let detected = result.detectedKind {
                kind = detected
            } else {
                throw ProviderError.invalidResponse
            }
            return ProviderDetection(
                profile: ProviderProfile(region: region, credentialKind: kind),
                snapshot: result.snapshot
            )
        case "regionFallback":
            let fallbackTokens = Set(spec.detect.fallbackOn ?? [])
            for candidate in orderedCandidates() {
                do {
                    let result = try await runPipeline(
                        apiKey: key,
                        profile: candidate,
                        entryPoint: .detect
                    )
                    return ProviderDetection(profile: candidate, snapshot: result.snapshot)
                } catch let error as ProviderError {
                    // Only failures whose token is in fallbackOn advance to the
                    // next candidate; anything else propagates immediately.
                    guard fallbackTokens.contains(SpecEngine.errorToken(for: error)) else {
                        throw error
                    }
                    continue
                }
            }
            throw SpecEngine.engineError(spec.detect.exhaustedError)
        default:
            throw ProviderSpecError.invalidSpec(
                "unknown detect strategy '\(spec.detect.strategy)'"
            )
        }
    }

    public func fetch(
        apiKey: String,
        profile: ProviderProfile
    ) async throws -> ProviderUsageSnapshot {
        let key = try preprocess(apiKey)
        let supported = spec.profiles.supported.contains {
            $0.region == profile.region.rawValue
                && $0.credentialKind == profile.credentialKind.rawValue
        }
        guard supported else {
            throw ProviderError.profileMismatch
        }
        return try await runPipeline(apiKey: key, profile: profile, entryPoint: .fetch)
            .snapshot
    }

    // MARK: Pipeline

    private enum EntryPoint {
        case detect
        case fetch
    }

    private struct StepResult {
        let body: SpecJSONValue
        let fields: [String: SpecEvalValue]
        let detectedKind: ProviderCredentialKind?
        /// Set by a `gotoStep` branch: the pipeline stops and this step's
        /// result becomes the fetch result.
        var replacesPipeline = false
    }

    /// Engine steps 3–6 of the fetch semantics: ordered steps with first-match
    /// status branches, per-step checks/values/snapshot merge, and
    /// credential-kind enforcement immediately after a step parses.
    private func runPipeline(
        apiKey: String,
        profile: ProviderProfile,
        entryPoint: EntryPoint
    ) async throws -> (snapshot: ProviderUsageSnapshot, detectedKind: ProviderCredentialKind?) {
        var stepBodies: [String: SpecJSONValue] = [:]
        var merged: [String: SpecEvalValue] = [:]
        var detectedKind: ProviderCredentialKind?

        for step in spec.fetch.steps {
            if step.onDemand {
                continue
            }
            if let when = step.when,
               !SpecEngine.evaluateCondition(when, root: nil, steps: stepBodies) {
                continue
            }
            let result = try await executeStep(
                step,
                apiKey: apiKey,
                profile: profile,
                steps: stepBodies
            )
            stepBodies[step.name] = result.body
            for (field, value) in result.fields {
                merged[field] = value
            }
            if let kind = result.detectedKind {
                switch entryPoint {
                case .detect:
                    detectedKind = kind
                case .fetch:
                    guard kind == profile.credentialKind else {
                        throw ProviderError.profileMismatch
                    }
                }
            }
            if result.replacesPipeline {
                break
            }
        }
        return (try assembleSnapshot(merged: merged), detectedKind)
    }

    /// Executes one step: request, first-match status branch, then parse.
    /// A `gotoStep` branch abandons the step and recursively executes the
    /// target, whose result becomes the fetch result (`replacesPipeline`).
    private func executeStep(
        _ step: StepSpec,
        apiKey: String,
        profile: ProviderProfile,
        steps: [String: SpecJSONValue]
    ) async throws -> StepResult {
        let request = try buildRequest(step, apiKey: apiKey, profile: profile)
        let (data, response) = try await httpClient.data(for: request)

        guard let branch = step.onStatus.first(where: {
            matches($0.match, statusCode: response.statusCode)
        }) else {
            throw ProviderError.httpStatus(response.statusCode)
        }
        switch branch.action {
        case "error":
            throw SpecEngine.engineError(branch.error, statusCode: response.statusCode)
        case "gotoStep":
            guard let target = spec.fetch.steps.first(where: { $0.name == branch.step }) else {
                throw ProviderSpecError.invalidSpec("unknown gotoStep target")
            }
            var result = try await executeStep(
                target,
                apiKey: apiKey,
                profile: profile,
                steps: steps
            )
            result.replacesPipeline = true
            return result
        default:
            break
        }

        let body: SpecJSONValue
        do {
            body = try JSONDecoder().decode(SpecJSONValue.self, from: data)
        } catch {
            throw ProviderError.invalidResponse
        }
        let parse = step.parse
        try SpecEngine.runChecks(parse?.checks ?? [], body: body)
        let scope = SpecEvaluationScope(
            root: body,
            region: profile.region,
            steps: steps,
            namedBuilders: parse?.values ?? [:],
            parent: nil
        )
        var fields: [String: SpecEvalValue] = [:]
        for (field, builder) in parse?.snapshot ?? [:] {
            if let value = try SpecEngine.evaluate(builder, in: scope) {
                fields[field] = value
            }
        }
        var detectedKind: ProviderCredentialKind?
        if let detection = parse?.credentialKindDetection {
            guard let key = SpecEngine.scalarKey(SpecEngine.resolve(body, detection.path)),
                  let kindName = detection.map[key],
                  let kind = ProviderCredentialKind(rawValue: kindName) else {
                throw ProviderError.invalidResponse
            }
            detectedKind = kind
        }
        return StepResult(body: body, fields: fields, detectedKind: detectedKind)
    }

    private func matches(_ match: StatusMatchSpec, statusCode: Int) -> Bool {
        switch match {
        case .twoXX:
            return (200..<300).contains(statusCode)
        case let .codes(codes):
            return codes.contains(statusCode)
        case .default:
            return true
        }
    }

    private func buildRequest(
        _ step: StepSpec,
        apiKey: String,
        profile: ProviderProfile
    ) throws -> URLRequest {
        let urlString: String
        switch step.request.url {
        case let .fixed(url):
            urlString = url
        case let .byRegion(table):
            guard let url = table[profile.region.rawValue] else {
                throw ProviderSpecError.invalidSpec(
                    "request url byRegion table misses region '\(profile.region.rawValue)'"
                )
            }
            urlString = url
        }
        guard let url = URL(string: urlString) else {
            throw ProviderSpecError.invalidSpec("invalid request url '\(urlString)'")
        }
        var request = URLRequest(url: url)
        request.httpMethod = step.request.method
        for header in step.request.headers {
            request.setValue(
                header.value.replacingOccurrences(of: "${apiKey}", with: apiKey),
                forHTTPHeaderField: header.name
            )
        }
        return request
    }

    private func assembleSnapshot(
        merged: [String: SpecEvalValue]
    ) throws -> ProviderUsageSnapshot {
        var snapshot = ProviderUsageSnapshot(receivedAt: now())
        for (field, value) in merged {
            switch field {
            case "balances":
                snapshot.balances = try SpecSnapshotAssembly.balances(value)
            case "spendingLimit":
                snapshot.spendingLimit = try SpecSnapshotAssembly.spendingLimit(value)
            case "spend":
                snapshot.spend = try SpecSnapshotAssembly.spend(value)
            case "quotaWindows":
                snapshot.quotaWindows = try SpecSnapshotAssembly.quotaWindows(value)
            case "today":
                snapshot.today = try SpecSnapshotAssembly.counters(value)
            case "total":
                snapshot.total = try SpecSnapshotAssembly.counters(value)
            case "dailyUsage":
                snapshot.dailyUsage = try SpecSnapshotAssembly.dailyUsage(value)
            case "modelUsage":
                snapshot.modelUsage = try SpecSnapshotAssembly.modelUsage(value)
            case "providerStatus":
                snapshot.providerStatus = try SpecSnapshotAssembly.string(value)
            case "metricsUnavailableReason":
                snapshot.metricsUnavailableReason = try SpecSnapshotAssembly.string(value)
            default:
                throw ProviderSpecError.invalidSpec("unknown snapshot field '\(field)'")
            }
        }
        return snapshot
    }

    // MARK: Credential preprocessing and region fallback

    /// `credential.trimWhitespace`, then the `reject` rules in order; applied
    /// at the top of both detect and fetch, before anything else.
    private func preprocess(_ apiKey: String) throws -> String {
        var key = apiKey
        if spec.credential.trimWhitespace {
            key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for rule in spec.credential.reject {
            let matches = rule.caseInsensitive
                ? key.lowercased().hasPrefix(rule.prefix.lowercased())
                : key.hasPrefix(rule.prefix)
            if matches {
                throw SpecEngine.engineError(rule.error)
            }
        }
        return key
    }

    /// regionFallback candidates with the runtime-preferred region moved to
    /// the front. The injected preference is clamped to the candidate set; an
    /// unsupported (or absent) injection falls back to the locale default
    /// (`CN` → china, else international).
    private func orderedCandidates() -> [ProviderProfile] {
        let candidates = (spec.detect.candidates ?? []).compactMap { candidate in
            ProviderRegion(rawValue: candidate.region).flatMap { region in
                ProviderCredentialKind(rawValue: candidate.credentialKind).map { kind in
                    ProviderProfile(region: region, credentialKind: kind)
                }
            }
        }
        let candidateRegions = Set(candidates.map { $0.region })
        let preferred = preferredRegion.flatMap { candidateRegions.contains($0) ? $0 : nil }
            ?? Self.localePreferredRegion()
        var ordered = candidates
        if let index = ordered.firstIndex(where: { $0.region == preferred }) {
            let candidate = ordered.remove(at: index)
            ordered.insert(candidate, at: 0)
        }
        return ordered
    }

    private static func localePreferredRegion() -> ProviderRegion {
        let regionCode: String?
        if #available(macOS 13, *) {
            regionCode = Locale.current.region?.identifier
        } else {
            regionCode = Locale.current.regionCode
        }
        return regionCode?.uppercased() == "CN" ? .china : .international
    }

    // MARK: Descriptor

    private static func makeDescriptor(id: ProviderID, spec: ProviderSpec) -> ProviderDescriptor {
        let thresholdSpec = spec.descriptor.supportsLowBalanceThreshold
        let supportsThreshold: @Sendable (ProviderProfile?) -> Bool
        if let always = thresholdSpec.always {
            supportsThreshold = { _ in always }
        } else {
            let undetected = thresholdSpec.undetected ?? false
            let kinds = Set(
                (thresholdSpec.credentialKinds ?? []).compactMap {
                    ProviderCredentialKind(rawValue: $0)
                }
            )
            supportsThreshold = { profile in
                guard let profile else { return undetected }
                return kinds.contains(profile.credentialKind)
            }
        }

        let descriptionSpec = spec.descriptor.profileDescription
        let undetectedKey = L10nKey(rawValue: descriptionSpec.undetected.l10nKey)
            ?? .notDetected
        let detected = descriptionSpec.detected
        let profileDescription: @Sendable (ProviderProfile?, AppLanguage) -> String = {
            profile, language in
            guard let profile else {
                return L10n.string(undetectedKey, language: language)
            }
            switch detected.style {
            case "regionCredential":
                return L10n.string(
                    .regionCredential,
                    language: language,
                    profile.region.displayName(language: language),
                    profile.credentialKind.displayName(language: language)
                )
            case "credentialKind":
                return profile.credentialKind.displayName(language: language)
            default:
                break
            }
            if let byRegion = detected.byRegion,
               let entry = byRegion[profile.region.rawValue],
               let key = L10nKey(rawValue: entry.l10nKey) {
                if entry.args?.contains("credentialKind") == true {
                    return L10n.string(
                        key,
                        language: language,
                        profile.credentialKind.displayName(language: language)
                    )
                }
                return L10n.string(key, language: language)
            }
            return L10n.string(undetectedKey, language: language)
        }

        return ProviderDescriptor(
            id: id,
            displayName: spec.displayName,
            supportsLowBalanceThreshold: supportsThreshold,
            profileDescription: profileDescription
        )
    }
}
