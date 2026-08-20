package com.liangrui.quotaglance.core

import java.math.BigDecimal
import java.time.Instant
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.longOrNull

internal data class DecimalValue(val value: BigDecimal, val canonical: String) {
    companion object {
        fun from(element: JsonElement?): DecimalValue? {
            val primitive = element as? JsonPrimitive ?: return null
            if (primitive.booleanOrNull != null) return null
            val raw = primitive.contentOrNull?.trim().orEmpty()
            if (raw.isEmpty()) return null
            val number = raw.toBigDecimalOrNull() ?: return null
            return DecimalValue(
                number,
                if (primitive.isString) raw else Money.canonicalNumber(number),
            )
        }

        fun subtract(left: DecimalValue?, right: DecimalValue?): DecimalValue? {
            if (left == null || right == null) return null
            val value = left.value.subtract(right.value)
            return DecimalValue(value, Money.canonicalNumber(value))
        }
    }
}

internal sealed interface EvalValue {
    data class Decimal(val value: DecimalValue) : EvalValue
    data class Text(val value: String) : EvalValue
    data class Integer(val value: Long) : EvalValue
    data class Bool(val value: Boolean) : EvalValue
    data class DateMillis(val value: Long) : EvalValue
    data class MoneyValue(val amount: DecimalValue, val currency: String) : EvalValue
    data class ObjectValue(val fields: Map<String, EvalValue>) : EvalValue
    data class ArrayValue(val values: List<EvalValue>) : EvalValue
}

internal class EvalScope(
    val root: JsonElement,
    val region: ProviderRegion,
    val steps: Map<String, JsonElement>,
    private val builders: JsonObject,
    private val parent: EvalScope? = null,
) {
    private val values = mutableMapOf<String, EvalValue?>()
    private val resolving = mutableSetOf<String>()

    fun namedValue(name: String): EvalValue? {
        if (values.containsKey(name)) return values[name]
        val builder = builders[name] ?: return parent?.namedValue(name)
        check(resolving.add(name)) { "cyclic spec value: $name" }
        try {
            return SpecEngine.evaluateBuilder(builder, this).also { values[name] = it }
        } finally {
            resolving.remove(name)
        }
    }
}

internal object SpecEngine {
    private val template = Regex("\\$\\{([^}]+)\\}")

    fun resolve(root: JsonElement?, path: String): JsonElement? {
        if (path.isEmpty()) return root?.takeUnless { it is JsonNull }
        var current = root
        for (part in path.split('.')) {
            current = (current as? JsonObject)?.get(part)
            if (current == null || current is JsonNull) return null
        }
        return current
    }

    fun condition(raw: JsonElement, root: JsonElement?, steps: Map<String, JsonElement>): Boolean {
        val condition = raw.objOrNull() ?: return false
        condition.array("any")?.let { return it.any { condition(it, root, steps) } }
        condition.array("all")?.let { return it.all { condition(it, root, steps) } }
        val base = condition.string("step")?.let { steps[it] } ?: root
        val actual = condition.string("path")?.let { resolve(base, it) } ?: base?.takeUnless { it is JsonNull }
        when {
            "exists" in condition -> return (actual != null) == condition.bool("exists")
            "equals" in condition -> return scalarEquals(actual, condition.getValue("equals"))
            "notEquals" in condition -> return actual != null && !scalarEquals(actual, condition.getValue("notEquals"))
            "lt" in condition -> return DecimalValue.from(actual)?.value?.let { value ->
                DecimalValue.from(condition.getValue("lt"))?.value?.let { value < it }
            } ?: false
            "gt" in condition -> return DecimalValue.from(actual)?.value?.let { value ->
                DecimalValue.from(condition.getValue("gt"))?.value?.let { value > it }
            } ?: false
            else -> return false
        }
    }

    fun runChecks(raw: JsonElement?, body: JsonElement) {
        val checks = raw as? JsonArray ?: return
        checks.forEach { entry ->
            val check = entry.objOrNull() ?: invalidResponse()
            val error = check.string("error") ?: "invalidResponse"
            check.objOrNull("eachItem")?.let { each ->
                val elements = resolve(body, each.string("of") ?: invalidResponse())
                if (elements == null) return@let
                val array = elements as? JsonArray ?: throw failure(error)
                array.forEach { item ->
                    requireValue(
                        resolve(item, each.string("path") ?: invalidResponse()),
                        each.stringList("transforms"),
                        each.bool("required"),
                        each.bool("nonEmpty"),
                        each.string("type"),
                        error,
                    )
                }
                return@forEach
            }
            val path = check.string("path") ?: invalidResponse()
            val value = resolve(body, path)
            if (check.bool("required")) {
                requireValue(value, check.stringList("transforms"), true, check.bool("nonEmpty"), check.string("type"), error)
            }
            if (check.bool("strict")) {
                requireValue(value, check.stringList("transforms"), false, check.bool("nonEmpty"), check.string("type"), error)
            }
            check["when"]?.let { whenRaw ->
                if (condition(whenRaw, value, emptyMap())) throw failure(error)
            }
        }
    }

    fun evaluateBuilder(raw: JsonElement, scope: EvalScope): EvalValue? {
        val builder = raw.objOrNull() ?: invalidResponse()
        builder["when"]?.let { if (!condition(it, scope.root, scope.steps)) return null }
        builder.objOrNull("object")?.let { fields ->
            return EvalValue.ObjectValue(fields.mapNotNull { (name, value) ->
                evaluateBuilder(value, scope)?.let { name to it }
            }.toMap())
        }
        builder.objOrNull("money")?.let { money ->
            val amount = evaluateBuilder(money.getValue("amount"), scope) as? EvalValue.Decimal ?: return null
            val currency = evaluateBuilder(money.getValue("currency"), scope) as? EvalValue.Text ?: return null
            return EvalValue.MoneyValue(amount.value, currency.value.uppercase())
        }
        builder.string("template")?.let { return renderTemplate(it, scope)?.let(EvalValue::Text) }
        builder.string("fromArray")?.let { return evaluateFromArray(builder, it, scope) }
        builder.array("fixed")?.let { return evaluateFixed(it, scope) }
        builder.string("strategy")?.let { strategy ->
            return when (strategy) {
                "miniMaxModelRemains" -> {
                    val path = builder.string("path") ?: invalidResponse()
                    val windows = MiniMaxModelRemainsStrategy.windows(resolve(scope.root, path))
                    if (builder.bool("requireNonEmpty") && windows.isEmpty()) invalidResponse()
                    EvalValue.ArrayValue(windows.map { it.toEvalValue() })
                }
                else -> invalidResponse()
            }
        }
        builder.string("op")?.let { op ->
            return when (op) {
                "subtract" -> {
                    val left = evaluateBuilder(builder.getValue("a"), scope) as? EvalValue.Decimal
                    val right = evaluateBuilder(builder.getValue("b"), scope) as? EvalValue.Decimal
                    DecimalValue.subtract(left?.value, right?.value)?.let(EvalValue::Decimal)
                }
                "count" -> (resolve(scope.root, builder.string("path") ?: invalidResponse()) as? JsonArray)
                    ?.size?.toLong()?.let(EvalValue::Integer)
                else -> invalidResponse()
            }
        }
        if ("value" in builder) {
            return when (val value = builder.getValue("value")) {
                is JsonPrimitive -> scope.namedValue(value.content)
                else -> evaluateBuilder(value, scope)
            }
        }
        builder.objOrNull("byRegion")?.let { table ->
            val rawValue = table[scope.region.raw] ?: invalidResponse()
            return scalar(rawValue)
        }
        if ("literal" in builder) return scalar(builder.getValue("literal"))
        builder.objOrNull("map")?.let { map ->
            val key = scalarKey(resolve(scope.root, builder.string("path") ?: invalidResponse())) ?: return null
            return (map[key] as? JsonPrimitive)?.contentOrNull?.let(EvalValue::Text)
        }
        builder.string("path")?.let { path -> return evaluatePath(builder, path, scope) }
        invalidResponse()
    }

    private fun evaluatePath(builder: JsonObject, path: String, scope: EvalScope): EvalValue? {
        val raw = resolve(scope.root, path)
        val required = builder.bool("required")
        return when (builder.string("type") ?: invalidResponse()) {
            "decimal" -> DecimalValue.from(raw)?.let(EvalValue::Decimal) ?: requiredOrNull(required)
            "string" -> transformedString(raw, builder.stringList("transforms"))?.let { text ->
                when {
                    text.isEmpty() && required && builder.bool("nonEmpty") -> invalidResponse()
                    text.isEmpty() && builder.bool("nullIfEmpty") -> null
                    else -> EvalValue.Text(text)
                }
            } ?: requiredOrNull(required)
            "int" -> integer(raw)?.let(EvalValue::Integer) ?: requiredOrNull(required)
            "bool" -> (raw as? JsonPrimitive)?.booleanOrNull?.let(EvalValue::Bool) ?: requiredOrNull(required)
            "date" -> dateMillis(raw)?.let(EvalValue::DateMillis) ?: requiredOrNull(required)
            else -> invalidResponse()
        }
    }

    private fun evaluateFromArray(builder: JsonObject, path: String, scope: EvalScope): EvalValue.ArrayValue {
        val elements = resolve(scope.root, path) ?: return EvalValue.ArrayValue(emptyList())
        val array = elements as? JsonArray ?: invalidResponse()
        val itemBuilders = builder.objOrNull("item") ?: JsonObject(emptyMap())
        val itemValues = builder.objOrNull("itemValues") ?: JsonObject(emptyMap())
        return EvalValue.ArrayValue(array.mapNotNull { item ->
            if (item !is JsonObject) invalidResponse()
            builder["skipItemWhen"]?.let { if (condition(it, item, scope.steps)) return@mapNotNull null }
            val child = EvalScope(item, scope.region, scope.steps, itemValues, scope)
            EvalValue.ObjectValue(itemBuilders.mapNotNull { (name, nested) ->
                evaluateBuilder(nested, child)?.let { name to it }
            }.toMap())
        })
    }

    private fun evaluateFixed(entries: JsonArray, scope: EvalScope): EvalValue.ArrayValue =
        EvalValue.ArrayValue(entries.mapNotNull { raw ->
            val entry = raw.objOrNull() ?: invalidResponse()
            entry["when"]?.let { if (!condition(it, scope.root, scope.steps)) return@mapNotNull null }
            EvalValue.ObjectValue(entry.filterKeys { it != "when" }.mapNotNull { (name, nested) ->
                evaluateBuilder(nested, scope)?.let { name to it }
            }.toMap())
        })

    fun assembleSnapshot(fields: Map<String, EvalValue>, nowMillis: Long): ProviderUsageSnapshot {
        return ProviderUsageSnapshot(
            balances = (fields["balances"] as? EvalValue.ArrayValue)?.values?.map(::balance) ?: emptyList(),
            spendingLimit = (fields["spendingLimit"] as? EvalValue.ObjectValue)?.let(::spendingLimit),
            spend = (fields["spend"] as? EvalValue.ObjectValue)?.let(::spend) ?: SpendSummary(),
            quotaWindows = (fields["quotaWindows"] as? EvalValue.ArrayValue)?.values?.map(::quotaWindow) ?: emptyList(),
            today = (fields["today"] as? EvalValue.ObjectValue)?.let(::counters),
            total = (fields["total"] as? EvalValue.ObjectValue)?.let(::counters),
            dailyUsage = (fields["dailyUsage"] as? EvalValue.ArrayValue)?.values?.mapNotNull(::dailyUsage) ?: emptyList(),
            modelUsage = (fields["modelUsage"] as? EvalValue.ArrayValue)?.values?.map(::modelUsage) ?: emptyList(),
            apiInfoDetails = (fields["apiInfoDetails"] as? EvalValue.ObjectValue)?.let(::apiInfoDetails),
            providerStatus = (fields["providerStatus"] as? EvalValue.Text)?.value,
            metricsUnavailableReason = (fields["metricsUnavailableReason"] as? EvalValue.Text)?.value,
            receivedAtMillis = nowMillis,
        )
    }

    private fun balance(value: EvalValue): MonetaryBalance {
        val fields = (value as? EvalValue.ObjectValue)?.fields ?: invalidResponse()
        return MonetaryBalance(
            label = fields.text("label") ?: invalidResponse(),
            available = fields.money("available") ?: invalidResponse(),
            breakdown = (fields["breakdown"] as? EvalValue.ArrayValue)?.values?.map { item ->
                val nested = (item as? EvalValue.ObjectValue)?.fields ?: invalidResponse()
                MonetaryValue(nested.text("label") ?: invalidResponse(), nested.money("value") ?: invalidResponse())
            } ?: emptyList(),
        )
    }

    private fun spendingLimit(value: EvalValue.ObjectValue): SpendingLimit = SpendingLimit(
        label = value.fields.text("label") ?: invalidResponse(),
        used = value.fields.money("used"),
        limit = value.fields.money("limit"),
        remaining = value.fields.money("remaining"),
        resetDescription = value.fields.text("resetDescription"),
    )

    private fun spend(value: EvalValue.ObjectValue): SpendSummary = SpendSummary(
        today = value.fields.money("today"), week = value.fields.money("week"),
        month = value.fields.money("month"), total = value.fields.money("total"),
    )

    private fun quotaWindow(value: EvalValue): QuotaWindow {
        val fields = (value as? EvalValue.ObjectValue)?.fields ?: invalidResponse()
        return QuotaWindow(
            label = fields.text("label") ?: invalidResponse(),
            used = fields.decimal("used"), limit = fields.decimal("limit"), remaining = fields.decimal("remaining"),
            unit = fields.text("unit") ?: invalidResponse(), resetsAtMillis = fields.long("resetsAt"),
        )
    }

    private fun counters(value: EvalValue.ObjectValue): UsageCounters = UsageCounters(
        actualCost = value.fields.money("actualCost"), requests = value.fields.long("requests"),
        inputTokens = value.fields.long("inputTokens"), outputTokens = value.fields.long("outputTokens"),
        cacheReadTokens = value.fields.long("cacheReadTokens"), cacheCreationTokens = value.fields.long("cacheCreationTokens"),
        totalTokens = value.fields.long("totalTokens"),
    )

    private fun dailyUsage(value: EvalValue): DailyUsage? {
        val fields = (value as? EvalValue.ObjectValue)?.fields ?: invalidResponse()
        val cost = fields.money("actualCost") ?: return null
        return DailyUsage(fields.text("date") ?: invalidResponse(), cost, fields.long("requests"), fields.long("totalTokens"))
    }

    private fun modelUsage(value: EvalValue): ModelUsage {
        val fields = (value as? EvalValue.ObjectValue)?.fields ?: invalidResponse()
        return ModelUsage(fields.text("model") ?: invalidResponse(), fields.money("actualCost"), fields.long("requests"), fields.long("totalTokens"))
    }

    private fun apiInfoDetails(value: EvalValue.ObjectValue): ApiInfoDetails = ApiInfoDetails(
        planName = value.fields.text("planName"),
        mode = value.fields.text("mode"),
        status = value.fields.text("status"),
        reportedBalance = value.fields.money("reportedBalance"),
        isValid = (value.fields["isValid"] as? EvalValue.Bool)?.value,
        expiresAtMillis = value.fields.long("expiresAtMs"),
        daysUntilExpiry = value.fields.long("daysUntilExpiry"),
    )

    private fun requireValue(
        value: JsonElement?, transforms: List<String>, required: Boolean, nonEmpty: Boolean,
        type: String?, error: String,
    ) {
        if (value == null) {
            if (required) throw failure(error)
            return
        }
        val valid = when (type) {
            null -> true
            "decimal" -> DecimalValue.from(value) != null
            "string" -> value is JsonPrimitive && value.isString
            "int" -> integer(value) != null
            "bool" -> (value as? JsonPrimitive)?.booleanOrNull != null
            "date" -> dateMillis(value) != null
            else -> false
        }
        if (!valid) throw failure(error)
        if (nonEmpty) {
            val empty = when (value) {
                is JsonArray -> value.isEmpty()
                else -> transformedString(value, transforms)?.isEmpty() == true
            }
            if (empty) throw failure(error)
        }
    }

    private fun renderTemplate(raw: String, scope: EvalScope): String? {
        var missing = false
        val rendered = template.replace(raw) { match ->
            val value = scope.namedValue(match.groupValues[1])
            if (value == null) {
                missing = true
                ""
            } else {
                scalarText(value)
            }
        }
        return if (missing) null else rendered
    }

    private fun scalar(raw: JsonElement): EvalValue? = when (raw) {
        is JsonPrimitive -> when {
            raw.booleanOrNull != null -> EvalValue.Bool(raw.boolean)
            raw.isString -> EvalValue.Text(raw.content)
            else -> DecimalValue.from(raw)?.let(EvalValue::Decimal)
        }
        else -> null
    }

    private fun scalarText(value: EvalValue): String = when (value) {
        is EvalValue.Decimal -> value.value.canonical
        is EvalValue.Text -> value.value
        is EvalValue.Integer -> value.value.toString()
        is EvalValue.Bool -> value.value.toString()
        is EvalValue.DateMillis -> value.value.toString()
        else -> invalidResponse()
    }

    private fun scalarKey(value: JsonElement?): String? = when (value) {
        is JsonPrimitive -> when {
            value.booleanOrNull != null -> value.boolean.toString()
            value.isString -> value.content
            else -> DecimalValue.from(value)?.canonical
        }
        else -> null
    }

    private fun scalarEquals(actual: JsonElement?, expected: JsonElement): Boolean {
        val expectedPrimitive = expected as? JsonPrimitive ?: return false
        return when {
            expectedPrimitive.booleanOrNull != null -> (actual as? JsonPrimitive)?.booleanOrNull == expectedPrimitive.boolean
            expectedPrimitive.isString -> (actual as? JsonPrimitive)?.takeIf { it.isString }?.content == expectedPrimitive.content
            else -> DecimalValue.from(actual)?.value?.compareTo(DecimalValue.from(expectedPrimitive)?.value) == 0
        }
    }

    private fun transformedString(raw: JsonElement?, transforms: List<String>): String? {
        var text = (raw as? JsonPrimitive)?.takeIf { it.isString }?.content ?: return null
        transforms.forEach { transform ->
            text = when (transform) { "trim" -> text.trim(); "uppercase" -> text.uppercase(); else -> invalidResponse() }
        }
        return text
    }

    private fun integer(raw: JsonElement?): Long? {
        val primitive = raw as? JsonPrimitive ?: return null
        if (primitive.isString || primitive.booleanOrNull != null) return null
        return primitive.longOrNull
    }

    private fun requiredOrNull(required: Boolean): EvalValue? = if (required) invalidResponse() else null
    private fun invalidResponse(): Nothing = throw ProviderFailure("invalidResponse")
    private fun failure(token: String): ProviderFailure = ProviderFailure(if (token == "httpStatus") "invalidResponse" else token)
}

private fun JsonElement.objOrNull(): JsonObject? = this as? JsonObject
private fun JsonObject.objOrNull(name: String): JsonObject? = this[name] as? JsonObject
private fun JsonObject.array(name: String): JsonArray? = this[name] as? JsonArray
private fun JsonObject.string(name: String): String? = (this[name] as? JsonPrimitive)?.contentOrNull
private fun JsonObject.bool(name: String): Boolean = (this[name] as? JsonPrimitive)?.booleanOrNull == true
private fun JsonObject.stringList(name: String): List<String> = array(name)?.mapNotNull { (it as? JsonPrimitive)?.contentOrNull } ?: emptyList()
private fun Map<String, EvalValue>.text(name: String): String? = (this[name] as? EvalValue.Text)?.value
private fun Map<String, EvalValue>.decimal(name: String): BigDecimal? = (this[name] as? EvalValue.Decimal)?.value?.value
private fun Map<String, EvalValue>.long(name: String): Long? = when (val value = this[name]) {
    is EvalValue.Integer -> value.value
    is EvalValue.DateMillis -> value.value
    is EvalValue.Decimal -> value.value.value.toLongExactOrNull()
    else -> null
}
private fun dateMillis(value: JsonElement?): Long? =
    (value as? JsonPrimitive)?.contentOrNull?.let { raw ->
        runCatching { Instant.parse(raw).toEpochMilli() }.getOrNull()
    }
private fun Map<String, EvalValue>.money(name: String): Money? = (this[name] as? EvalValue.MoneyValue)?.let {
    Money.fromString(it.amount.canonical, it.currency)
}
private fun BigDecimal.toLongExactOrNull(): Long? = try { longValueExact() } catch (_: ArithmeticException) { null }
private fun QuotaWindow.toEvalValue(): EvalValue.ObjectValue = EvalValue.ObjectValue(buildMap {
    put("label", EvalValue.Text(label))
    used?.let { put("used", EvalValue.Decimal(DecimalValue(it, Money.canonicalNumber(it)))) }
    limit?.let { put("limit", EvalValue.Decimal(DecimalValue(it, Money.canonicalNumber(it)))) }
    remaining?.let { put("remaining", EvalValue.Decimal(DecimalValue(it, Money.canonicalNumber(it)))) }
    put("unit", EvalValue.Text(unit))
    resetsAtMillis?.let { put("resetsAt", EvalValue.Integer(it)) }
})
