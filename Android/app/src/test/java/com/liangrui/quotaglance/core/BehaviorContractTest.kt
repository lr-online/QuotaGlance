package com.liangrui.quotaglance.core

import java.math.BigDecimal
import java.time.Instant
import java.time.ZoneOffset
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class BehaviorContractTest {
    @Test
    fun `every aggregation fixture matches the shared contract`() {
        AGGREGATION_CASES.forEach { name ->
            val input = fixture("Aggregation/$name-input.json").jsonObject
            val expected = fixture("Aggregation/$name-expected.json").jsonObject
            val result = SnapshotAggregator(ZoneOffset.UTC).aggregate(
                accounts = input.array("accounts").map(::account),
                snapshots = input.array("snapshots").map(::aggregateSnapshot),
                now = Instant.parse(input.string("now")),
            )

            expected["balances"]?.let { balances ->
                assertEquals("$name balances", balances.jsonArray.map(::money), result.balances)
            }
            expected.assertOptionalMoney("todayActualCost", result.todayActualCost, "$name today cost")
            expected.assertOptionalLong("todayRequests", result.todayRequests, "$name today requests")
            expected["dailyUsage"]?.jsonArray?.let { rows ->
                assertEquals("$name daily count", rows.size, result.dailyUsage.size)
                rows.zip(result.dailyUsage).forEachIndexed { index, (raw, actual) ->
                    val row = raw.jsonObject
                    assertEquals("$name daily $index date", row.string("date"), actual.date)
                    row["actualCost"]?.let { assertEquals("$name daily $index cost", money(it), actual.actualCost) }
                }
            }
            expected["accounts"]?.jsonArray?.let { rows ->
                assertEquals("$name account count", rows.size, result.accounts.size)
                rows.zip(result.accounts).forEachIndexed { index, (raw, actual) ->
                    val row = raw.jsonObject
                    assertEquals("$name account $index id", row.string("accountID"), actual.accountId)
                    row["displayName"]?.let { assertEquals("$name account $index name", it.jsonPrimitive.content, actual.displayName) }
                }
            }
            expected["isPartial"]?.let { assertEquals("$name partial", it.jsonPrimitive.boolean, result.isPartial) }
        }
    }

    @Test
    fun `every alert fixture matches the shared contract`() {
        ALERT_CASES.forEach { name ->
            val input = fixture("Alerts/$name-input.json").jsonObject
            val expected = fixture("Alerts/$name-expected.json").jsonObject
            val accounts = input.array("accounts").map(::account).toMutableList()
            val result = AlertEvaluator.evaluate(
                accounts = accounts,
                freshSnapshots = input.array("freshSnapshots").map(::alertSnapshot),
            )

            expected["didChange"]?.let { assertEquals("$name didChange", it.jsonPrimitive.boolean, result.didChange) }
            expected["notifications"]?.jsonArray?.let { rows ->
                assertEquals("$name notification count", rows.size, result.notifications.size)
                rows.zip(result.notifications).forEachIndexed { index, (raw, actual) ->
                    val row = raw.jsonObject
                    assertEquals("$name notification $index id", row.string("accountID"), actual.account.id)
                    row["remaining"]?.let { assertEquals("$name notification $index amount", money(it), actual.remaining) }
                }
            }
            expected["accounts"]?.jsonArray?.forEach { raw ->
                val row = raw.jsonObject
                val actual = checkNotNull(accounts.firstOrNull { it.id == row.string("accountID") })
                row["alertEpisodeActive"]?.let {
                    assertEquals("$name episode ${actual.id}", it.jsonPrimitive.boolean, actual.alertEpisodeActive)
                }
            }
        }
    }

    private fun fixture(path: String): JsonElement = json.parseToJsonElement(
        checkNotNull(javaClass.classLoader?.getResourceAsStream("contracts/$path")) { "missing fixture $path" }
            .bufferedReader()
            .use { it.readText() },
    )

    private fun account(raw: JsonElement): QuotaAccount {
        val item = raw.jsonObject
        return QuotaAccount(
            id = item.string("id"),
            displayName = item.string("displayName"),
            isEnabled = item["isEnabled"]?.jsonPrimitive?.booleanOrNull ?: true,
            sortOrder = item["sortOrder"]?.jsonPrimitive?.content?.toIntOrNull() ?: 0,
            lowBalanceThreshold = item["lowBalanceThreshold"]?.jsonPrimitive?.contentOrNull?.toBigDecimalOrNull(),
            alertEpisodeActive = item["alertEpisodeActive"]?.jsonPrimitive?.booleanOrNull ?: false,
        )
    }

    private fun aggregateSnapshot(raw: JsonElement): AccountSnapshot {
        val item = raw.jsonObject
        return AccountSnapshot(
            accountId = item.string("accountID"),
            health = health(item.getValue("health")),
            usage = item["usage"]?.jsonObject?.let(::usage),
        )
    }

    private fun alertSnapshot(raw: JsonElement): AccountSnapshot {
        val item = raw.jsonObject
        val remaining = item["remaining"]?.let(::money)
        return AccountSnapshot(
            accountId = item.string("accountID"),
            health = health(item.getValue("health")),
            usage = remaining?.let { ProviderUsageSnapshot(
                balances = listOf(MonetaryBalance("Balance", it)),
                receivedAtMillis = 0,
            ) },
        )
    }

    private fun usage(raw: JsonObject): ProviderUsageSnapshot = ProviderUsageSnapshot(
        balances = raw.array("balances").map { balance ->
            val item = balance.jsonObject
            MonetaryBalance(item.string("label"), money(item.getValue("available")))
        },
        today = raw["today"]?.jsonObject?.let { today ->
            UsageCounters(
                actualCost = today["actualCost"]?.let(::money),
                requests = today["requests"]?.jsonPrimitive?.content?.toLongOrNull(),
            )
        },
        dailyUsage = raw.array("dailyUsage").map { entry ->
            val item = entry.jsonObject
            DailyUsage(
                date = item.string("date"),
                actualCost = money(item.getValue("actualCost")),
                requests = item["requests"]?.jsonPrimitive?.content?.toLongOrNull(),
                totalTokens = item["totalTokens"]?.jsonPrimitive?.content?.toLongOrNull(),
            )
        },
        receivedAtMillis = 0,
    )

    private fun health(raw: JsonElement): AccountHealth = when (raw) {
        is JsonPrimitive -> when (raw.content) {
            "healthy" -> AccountHealth.Healthy
            "belowThreshold" -> AccountHealth.BelowThreshold
            else -> error("unknown health ${raw.content}")
        }
        is JsonObject -> when {
            "stale" in raw -> AccountHealth.Stale(raw.string("stale"))
            "unavailable" in raw -> AccountHealth.Unavailable(raw.string("unavailable"))
            else -> error("unknown health $raw")
        }
        else -> error("unknown health $raw")
    }

    private fun money(raw: JsonElement): Money {
        val item = raw.jsonObject
        return Money.fromString(item.string("amount"), item.string("currency"))
    }

    private fun JsonObject.assertOptionalMoney(name: String, actual: Money?, label: String) {
        if (name !in this) return
        val expected = this[name]
        if (expected == null || expected is kotlinx.serialization.json.JsonNull) assertNull(label, actual)
        else assertEquals(label, money(expected), actual)
    }

    private fun JsonObject.assertOptionalLong(name: String, actual: Long?, label: String) {
        if (name !in this) return
        val expected = this[name]
        if (expected == null || expected is kotlinx.serialization.json.JsonNull) assertNull(label, actual)
        else assertEquals(label, expected.jsonPrimitive.content.toLong(), actual)
    }

    private companion object {
        val json = Json { ignoreUnknownKeys = true }
        val AGGREGATION_CASES = listOf(
            "healthy-sum", "stale-partial", "disabled-excluded", "mixed-currency", "missing-metrics", "request-overflow",
        )
        val ALERT_CASES = listOf(
            "notify-on-low", "episode-debounce", "episode-reset", "stale-no-change", "batch-notify-and-reset", "no-alert-without-threshold",
        )
    }
}

private fun JsonObject.string(key: String): String = getValue(key).jsonPrimitive.content
private fun JsonObject.array(key: String): JsonArray = this[key] as? JsonArray ?: JsonArray(emptyList())
private val JsonElement.jsonArray: JsonArray get() = this as JsonArray
