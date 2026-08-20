package com.liangrui.quotaglance.core

import java.math.BigDecimal
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

enum class ProviderRegion(val raw: String) {
    GLOBAL("global"),
    CHINA("china"),
    INTERNATIONAL("international"),
    ;

    companion object {
        fun fromRaw(value: String): ProviderRegion? = entries.firstOrNull { it.raw == value }
    }
}

enum class CredentialKind(val raw: String) {
    STANDARD("standard"),
    MANAGEMENT("management"),
    TOKEN_PLAN("tokenPlan"),
    ;

    companion object {
        fun fromRaw(value: String): CredentialKind? = entries.firstOrNull { it.raw == value }
    }
}

data class ProviderProfile(
    val region: ProviderRegion,
    val credentialKind: CredentialKind,
) {
    companion object {
        fun globalStandard() = ProviderProfile(ProviderRegion.GLOBAL, CredentialKind.STANDARD)
    }
}

class Money private constructor(
    val value: BigDecimal,
    val canonicalAmount: String,
    val currency: String,
) {
    companion object {
        fun fromString(amount: String, currency: String): Money {
            val canonical = amount.trim()
            return Money(BigDecimal(canonical), canonical, currency.uppercase())
        }

        fun fromNumber(amount: BigDecimal, currency: String): Money =
            Money(amount, canonicalNumber(amount), currency.uppercase())

        fun canonicalNumber(amount: BigDecimal): String =
            amount.stripTrailingZeros().toPlainString().let { if (it == "-0") "0" else it }
    }

    override fun equals(other: Any?): Boolean =
        other is Money && value.compareTo(other.value) == 0 && currency == other.currency

    override fun hashCode(): Int = 31 * value.stripTrailingZeros().hashCode() + currency.hashCode()

    override fun toString(): String = "$canonicalAmount $currency"

    fun toFixtureJson() = JsonObject(
        mapOf("amount" to JsonPrimitive(canonicalAmount), "currency" to JsonPrimitive(currency)),
    )
}

data class MonetaryValue(val label: String, val value: Money)

data class MonetaryBalance(
    val label: String,
    val available: Money,
    val breakdown: List<MonetaryValue> = emptyList(),
)

data class SpendingLimit(
    val label: String,
    val used: Money? = null,
    val limit: Money? = null,
    val remaining: Money? = null,
    val resetDescription: String? = null,
)

data class SpendSummary(
    val today: Money? = null,
    val week: Money? = null,
    val month: Money? = null,
    val total: Money? = null,
)

data class QuotaWindow(
    val label: String,
    val used: BigDecimal? = null,
    val limit: BigDecimal? = null,
    val remaining: BigDecimal? = null,
    val unit: String,
    val resetsAtMillis: Long? = null,
)

data class ApiInfoDetails(
    val planName: String? = null,
    val mode: String? = null,
    val status: String? = null,
    val reportedBalance: Money? = null,
    val isValid: Boolean? = null,
    val expiresAtMillis: Long? = null,
    val daysUntilExpiry: Long? = null,
)

data class UsageCounters(
    val actualCost: Money? = null,
    val requests: Long? = null,
    val inputTokens: Long? = null,
    val outputTokens: Long? = null,
    val cacheReadTokens: Long? = null,
    val cacheCreationTokens: Long? = null,
    val totalTokens: Long? = null,
)

data class DailyUsage(
    val date: String,
    val actualCost: Money,
    val requests: Long? = null,
    val totalTokens: Long? = null,
)

data class ModelUsage(
    val model: String,
    val actualCost: Money? = null,
    val requests: Long? = null,
    val totalTokens: Long? = null,
)

data class ProviderUsageSnapshot(
    val balances: List<MonetaryBalance> = emptyList(),
    val spendingLimit: SpendingLimit? = null,
    val spend: SpendSummary = SpendSummary(),
    val quotaWindows: List<QuotaWindow> = emptyList(),
    val today: UsageCounters? = null,
    val total: UsageCounters? = null,
    val dailyUsage: List<DailyUsage> = emptyList(),
    val modelUsage: List<ModelUsage> = emptyList(),
    val apiInfoDetails: ApiInfoDetails? = null,
    val providerStatus: String? = null,
    val metricsUnavailableReason: String? = null,
    val receivedAtMillis: Long,
) {
    val remaining: Money? get() = balances.firstOrNull()?.available

    fun toFixtureJson(): JsonObject = JsonObject(buildMap {
        put("balances", JsonArray(balances.map { balance ->
            JsonObject(buildMap {
                put("label", JsonPrimitive(balance.label))
                put("available", balance.available.toFixtureJson())
                put("breakdown", JsonArray(balance.breakdown.map { item ->
                    JsonObject(mapOf("label" to JsonPrimitive(item.label), "value" to item.value.toFixtureJson()))
                }))
            })
        }))
        spendingLimit?.let { limit ->
            put("spendingLimit", JsonObject(buildMap {
                put("label", JsonPrimitive(limit.label))
                limit.used?.let { put("used", it.toFixtureJson()) }
                limit.limit?.let { put("limit", it.toFixtureJson()) }
                limit.remaining?.let { put("remaining", it.toFixtureJson()) }
                limit.resetDescription?.let { put("resetDescription", JsonPrimitive(it)) }
            }))
        }
        put("spend", JsonObject(buildMap {
            spend.today?.let { put("today", it.toFixtureJson()) }
            spend.week?.let { put("week", it.toFixtureJson()) }
            spend.month?.let { put("month", it.toFixtureJson()) }
            spend.total?.let { put("total", it.toFixtureJson()) }
        }))
        put("quotaWindows", JsonArray(quotaWindows.map { window ->
            JsonObject(buildMap {
                put("label", JsonPrimitive(window.label))
                window.used?.let { put("used", JsonPrimitive(it)) }
                window.limit?.let { put("limit", JsonPrimitive(it)) }
                window.remaining?.let { put("remaining", JsonPrimitive(it)) }
                put("unit", JsonPrimitive(window.unit))
                window.resetsAtMillis?.let { put("resetsAtMs", JsonPrimitive(it)) }
            })
        }))
        today?.let { put("today", it.toFixtureJson()) }
        total?.let { put("total", it.toFixtureJson()) }
        put("dailyUsage", JsonArray(dailyUsage.map { it.toFixtureJson() }))
        put("modelUsage", JsonArray(modelUsage.map { it.toFixtureJson() }))
        apiInfoDetails?.let { details ->
            put("apiInfoDetails", JsonObject(buildMap {
                details.planName?.let { put("planName", JsonPrimitive(it)) }
                details.mode?.let { put("mode", JsonPrimitive(it)) }
                details.status?.let { put("status", JsonPrimitive(it)) }
                details.reportedBalance?.let { put("reportedBalance", it.toFixtureJson()) }
                details.isValid?.let { put("isValid", JsonPrimitive(it)) }
                details.expiresAtMillis?.let { put("expiresAtMs", JsonPrimitive(it)) }
                details.daysUntilExpiry?.let { put("daysUntilExpiry", JsonPrimitive(it)) }
            }))
        }
        providerStatus?.let { put("providerStatus", JsonPrimitive(it)) }
        metricsUnavailableReason?.let { put("metricsUnavailableReason", JsonPrimitive(it)) }
    })
}

private fun UsageCounters.toFixtureJson() = JsonObject(buildMap {
    actualCost?.let { put("actualCost", it.toFixtureJson()) }
    requests?.let { put("requests", JsonPrimitive(it)) }
    inputTokens?.let { put("inputTokens", JsonPrimitive(it)) }
    outputTokens?.let { put("outputTokens", JsonPrimitive(it)) }
    cacheReadTokens?.let { put("cacheReadTokens", JsonPrimitive(it)) }
    cacheCreationTokens?.let { put("cacheCreationTokens", JsonPrimitive(it)) }
    totalTokens?.let { put("totalTokens", JsonPrimitive(it)) }
})

private fun DailyUsage.toFixtureJson() = JsonObject(buildMap {
    put("date", JsonPrimitive(date))
    put("actualCost", actualCost.toFixtureJson())
    requests?.let { put("requests", JsonPrimitive(it)) }
    totalTokens?.let { put("totalTokens", JsonPrimitive(it)) }
})

private fun ModelUsage.toFixtureJson() = JsonObject(buildMap {
    put("model", JsonPrimitive(model))
    actualCost?.let { put("actualCost", it.toFixtureJson()) }
    requests?.let { put("requests", JsonPrimitive(it)) }
    totalTokens?.let { put("totalTokens", JsonPrimitive(it)) }
})
