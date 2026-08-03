package com.liangrui.quotaglance.core

import java.math.BigDecimal
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/** Persisted account metadata. API keys intentionally live outside this type. */
data class QuotaAccount(
    val id: String,
    var displayName: String,
    val provider: ProviderId = ProviderId.API_INFO,
    var detectedProfile: ProviderProfile? = null,
    var isEnabled: Boolean = true,
    var sortOrder: Int = 0,
    var lowBalanceThreshold: BigDecimal? = null,
    var alertEpisodeActive: Boolean = false,
)

sealed interface AccountHealth {
    data object Healthy : AccountHealth
    data object BelowThreshold : AccountHealth
    data class Stale(val reason: String) : AccountHealth
    data class Unavailable(val reason: String) : AccountHealth
}

data class AccountSnapshot(
    val accountId: String,
    var displayName: String = "",
    var provider: ProviderId = ProviderId.API_INFO,
    var detectedProfile: ProviderProfile? = null,
    var lowBalanceThreshold: BigDecimal? = null,
    val usage: ProviderUsageSnapshot? = null,
    val health: AccountHealth,
    val lastSuccessAtMillis: Long? = null,
) {
    val remaining: Money? get() = usage?.remaining
}

data class AggregateSnapshot(
    val balances: List<Money> = emptyList(),
    val todayActualCost: Money? = null,
    val todayRequests: Long? = null,
    val dailyUsage: List<DailyUsage> = emptyList(),
    val accounts: List<AccountSnapshot> = emptyList(),
    val isPartial: Boolean = false,
) {
    val remaining: Money? get() = balances.singleOrNull()
}

/** Cross-account aggregation matching the shared aggregation fixtures. */
class SnapshotAggregator(private val zoneId: ZoneId = ZoneId.systemDefault()) {
    fun aggregate(
        accounts: List<QuotaAccount>,
        snapshots: List<AccountSnapshot>,
        now: Instant,
    ): AggregateSnapshot {
        val enabled = accounts.filter { it.isEnabled }.sortedWith(
            compareBy<QuotaAccount> { it.sortOrder }.thenBy { it.id },
        )
        val snapshotsById = linkedMapOf<String, AccountSnapshot>()
        snapshots.forEach { snapshotsById.putIfAbsent(it.accountId, it) }
        val ordered = enabled.mapNotNull { account ->
            snapshotsById[account.id]?.copy(
                displayName = account.displayName,
                provider = account.provider,
                detectedProfile = account.detectedProfile,
                lowBalanceThreshold = account.lowBalanceThreshold,
            )
        }

        val balances = sumMoneyByCurrency(ordered.flatMap { it.usage?.balances.orEmpty().map(MonetaryBalance::available) })
        val costs = ordered.mapNotNull { it.usage?.spend?.today ?: it.usage?.today?.actualCost }
        val todayCost = if (costs.size == ordered.size) sumMoney(costs) else null
        val requestValues = ordered.mapNotNull { it.usage?.today?.requests }
        val allRequestValuesPresent = requestValues.size == ordered.size
        val todayRequests = if (allRequestValuesPresent) sumLongs(requestValues) else null
        val requestsOverflowed = allRequestValuesPresent && requestValues.isNotEmpty() && todayRequests == null
        val partial = ordered.size != enabled.size || requestsOverflowed || ordered.any {
            it.health is AccountHealth.Stale || it.health is AccountHealth.Unavailable
        }
        return AggregateSnapshot(
            balances = balances,
            todayActualCost = todayCost,
            todayRequests = todayRequests,
            dailyUsage = dailyUsage(ordered, balances.singleOrNull()?.currency, now),
            accounts = ordered,
            isPartial = partial,
        )
    }

    private fun sumMoneyByCurrency(values: List<Money>): List<Money> = values
        .groupBy { it.currency }
        .toSortedMap()
        .values
        .mapNotNull(::sumMoney)

    private fun sumMoney(values: List<Money>): Money? {
        val first = values.firstOrNull() ?: return null
        if (values.any { it.currency != first.currency }) return null
        val sum = values.fold(BigDecimal.ZERO) { total, money -> total.add(money.value) }
        return Money.fromString(sum.toPlainString(), first.currency)
    }

    private fun sumLongs(values: List<Long>): Long? {
        if (values.isEmpty()) return null
        return try {
            values.fold(0L, Math::addExact)
        } catch (_: ArithmeticException) {
            null
        }
    }

    private fun dailyUsage(
        snapshots: List<AccountSnapshot>,
        fallbackCurrency: String?,
        now: Instant,
    ): List<DailyUsage> {
        val entries = snapshots.flatMap { it.usage?.dailyUsage.orEmpty() }
        if (entries.isEmpty()) return emptyList()
        val currency = entries.firstOrNull()?.actualCost?.currency ?: fallbackCurrency ?: return emptyList()
        if (entries.any { it.actualCost.currency != currency }) return emptyList()
        val parsed = entries.mapNotNull { entry ->
            runCatching { LocalDate.parse(entry.date) }.getOrNull()?.let { it to entry }
        }
        if (parsed.isEmpty()) return emptyList()
        val today = now.atZone(zoneId).toLocalDate()
        val end = maxOf(parsed.maxOf { it.first }, today)
        val grouped = parsed.groupBy({ it.first }, { it.second })
        return (-6..0).map { offset ->
            val date = end.plusDays(offset.toLong())
            val values = grouped[date].orEmpty()
            val amount = values.fold(BigDecimal.ZERO) { total, entry -> total.add(entry.actualCost.value) }
            DailyUsage(
                date = date.toString(),
                actualCost = Money.fromString(amount.toPlainString(), currency),
                requests = sumLongs(values.mapNotNull { it.requests }),
                totalTokens = sumLongs(values.mapNotNull { it.totalTokens }),
            )
        }
    }
}

data class PendingLowBalanceNotification(
    val account: QuotaAccount,
    val remaining: Money,
)

data class AlertBatchEvaluation(
    val didChange: Boolean,
    val notifications: List<PendingLowBalanceNotification>,
)

/** Episode-aware low-balance evaluation. Stale and unavailable snapshots never mutate state. */
object AlertEvaluator {
    fun evaluate(
        accounts: MutableList<QuotaAccount>,
        freshSnapshots: List<AccountSnapshot>,
    ): AlertBatchEvaluation {
        val snapshotsById = linkedMapOf<String, AccountSnapshot>()
        freshSnapshots.forEach { snapshotsById.putIfAbsent(it.accountId, it) }
        val notifications = mutableListOf<PendingLowBalanceNotification>()
        var didChange = false
        accounts.forEach { account ->
            val snapshot = snapshotsById[account.id] ?: return@forEach
            val remaining = snapshot.remaining ?: return@forEach
            when (evaluate(account, snapshot)) {
                AlertAction.Notify -> {
                    didChange = true
                    notifications += PendingLowBalanceNotification(account.copy(), remaining)
                }
                AlertAction.Reset -> didChange = true
                AlertAction.None -> Unit
            }
        }
        return AlertBatchEvaluation(didChange, notifications)
    }

    fun evaluate(account: QuotaAccount, freshSnapshot: AccountSnapshot): AlertAction {
        if (freshSnapshot.accountId != account.id) return AlertAction.None
        return when (freshSnapshot.health) {
            AccountHealth.Healthy, AccountHealth.BelowThreshold -> evaluate(account, freshSnapshot.remaining?.value)
            is AccountHealth.Stale, is AccountHealth.Unavailable -> AlertAction.None
        }
    }

    fun evaluate(account: QuotaAccount, freshRemaining: BigDecimal?): AlertAction {
        val threshold = account.lowBalanceThreshold
        if (!account.isEnabled || threshold == null || freshRemaining == null) return AlertAction.None
        if (freshRemaining <= threshold) {
            if (account.alertEpisodeActive) return AlertAction.None
            account.alertEpisodeActive = true
            return AlertAction.Notify
        }
        if (!account.alertEpisodeActive) return AlertAction.None
        account.alertEpisodeActive = false
        return AlertAction.Reset
    }
}

enum class AlertAction { None, Notify, Reset }
