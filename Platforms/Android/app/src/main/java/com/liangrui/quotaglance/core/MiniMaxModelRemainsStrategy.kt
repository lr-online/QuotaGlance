package com.liangrui.quotaglance.core

import java.math.BigDecimal
import kotlin.math.abs
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * Named parse strategy allowed by the provider contract for MiniMax token-plan
 * remains. It is deliberately shape-only: all provider policy remains in the
 * shared spec.
 */
internal object MiniMaxModelRemainsStrategy {
    fun windows(value: JsonElement?): List<QuotaWindow> =
        (value as? JsonArray).orEmpty().flatMap(::windowsFor)

    private fun windowsFor(entry: JsonElement): List<QuotaWindow> {
        directWindow(entry)?.let { return listOf(it) }
        return buildList {
            if (decimal(entry, "current_interval_status") != BigDecimal.ZERO) {
                intervalWindow(entry)?.let(::add)
            }
            if (decimal(entry, "current_weekly_status") != BigDecimal.ZERO) {
                weeklyWindow(entry)?.let(::add)
            }
        }
    }

    private fun directWindow(entry: JsonElement): QuotaWindow? {
        val limit = decimal(entry, "total")
        val suppliedUsed = decimal(entry, "used")
        val suppliedRemaining = decimal(entry, "remains")
        if (limit == null && suppliedUsed == null && suppliedRemaining == null) return null
        return QuotaWindow(
            label = normalizedLabel(string(entry, "label"))
                ?: "${normalizedModelName(string(entry, "model_name"))} quota",
            used = suppliedUsed ?: subtract(limit, suppliedRemaining),
            limit = limit,
            remaining = suppliedRemaining ?: subtract(limit, suppliedUsed),
            unit = normalizedLabel(string(entry, "unit")) ?: "requests",
            resetsAtMillis = providerDateMillis(decimal(entry, "reset_time") ?: decimal(entry, "end_time")),
        )
    }

    private fun intervalWindow(entry: JsonElement): QuotaWindow? {
        val label = if (isFiveHourWindow(decimal(entry, "start_time"), decimal(entry, "end_time"))) {
            "${normalizedModelName(string(entry, "model_name"))} 5-hour quota"
        } else {
            "${normalizedModelName(string(entry, "model_name"))} quota"
        }
        return countedOrPercentWindow(
            label = label,
            total = decimal(entry, "current_interval_total_count"),
            used = decimal(entry, "current_interval_usage_count"),
            remainingPercent = decimal(entry, "current_interval_remaining_percent"),
            resetsAt = decimal(entry, "end_time"),
        )
    }

    private fun weeklyWindow(entry: JsonElement): QuotaWindow? = countedOrPercentWindow(
        label = "${normalizedModelName(string(entry, "model_name"))} weekly quota",
        total = decimal(entry, "current_weekly_total_count"),
        used = decimal(entry, "current_weekly_usage_count"),
        remainingPercent = decimal(entry, "current_weekly_remaining_percent"),
        resetsAt = decimal(entry, "weekly_end_time"),
    )

    private fun countedOrPercentWindow(
        label: String,
        total: BigDecimal?,
        used: BigDecimal?,
        remainingPercent: BigDecimal?,
        resetsAt: BigDecimal?,
    ): QuotaWindow? {
        if (total?.compareTo(BigDecimal.ZERO) == 1 || used?.compareTo(BigDecimal.ZERO) == 1) {
            return QuotaWindow(
                label = label,
                used = used,
                limit = total,
                remaining = subtract(total, used),
                unit = "requests",
                resetsAtMillis = providerDateMillis(resetsAt),
            )
        }
        remainingPercent ?: return null
        val remaining = remainingPercent.coerceIn(BigDecimal.ZERO, BigDecimal(100))
        return QuotaWindow(
            label = label,
            used = BigDecimal(100).subtract(remaining),
            limit = BigDecimal(100),
            remaining = remaining,
            unit = "%",
            resetsAtMillis = providerDateMillis(resetsAt),
        )
    }

    private fun subtract(left: BigDecimal?, right: BigDecimal?): BigDecimal? =
        if (left == null || right == null) null else left.subtract(right)

    private fun normalizedLabel(value: String?): String? = value?.trim()?.takeIf(String::isNotEmpty)
    private fun normalizedModelName(value: String?): String = normalizedLabel(value) ?: "Token Plan"

    private fun providerDateMillis(value: BigDecimal?): Long? {
        value ?: return null
        return if (value.abs() > BigDecimal("10000000000")) exactLong(value)
        else exactLong(value.multiply(BigDecimal(1000)))
    }

    private fun isFiveHourWindow(start: BigDecimal?, end: BigDecimal?): Boolean {
        start ?: return false
        end ?: return false
        return abs(end.subtract(start).toDouble() - 18_000.0) < 1.0
    }

    private fun exactLong(value: BigDecimal): Long? = try {
        value.longValueExact()
    } catch (_: ArithmeticException) {
        null
    }

    private fun decimal(entry: JsonElement, key: String): BigDecimal? =
        DecimalValue.from((entry as? JsonObject)?.get(key))?.value

    private fun string(entry: JsonElement, key: String): String? =
        ((entry as? JsonObject)?.get(key) as? JsonPrimitive)?.takeIf { it.isString }?.content
}
