package com.liangrui.quotaglance.ui

import com.liangrui.quotaglance.core.AccountHealth
import com.liangrui.quotaglance.core.AccountSnapshot
import com.liangrui.quotaglance.core.Money
import com.liangrui.quotaglance.core.ProviderId
import com.liangrui.quotaglance.core.ProviderUsageSnapshot
import com.liangrui.quotaglance.core.QuotaAccount
import com.liangrui.quotaglance.core.QuotaWindow
import java.math.BigDecimal

data class ProviderOverview(
    val provider: ProviderId,
    val displayName: String,
    val enabledAccountCount: Int,
    val balances: List<Money>,
    val todayCosts: List<Money>,
    val todayRequests: Long?,
    val quotaWindows: List<QuotaWindow>,
    val hasData: Boolean,
    val isStale: Boolean,
    val requestFraction: Double,
)

object ProviderOverviewPresenter {
    private val displayNames = mapOf(
        ProviderId.API_INFO to "API Info",
        ProviderId.DEEP_SEEK to "DeepSeek",
        ProviderId.KIMI to "Kimi",
        ProviderId.OPEN_ROUTER to "OpenRouter",
        ProviderId.MINI_MAX to "MiniMax",
        ProviderId.BIO_MAP_CODING to "BioMap Coding",
    )

    fun present(
        accounts: List<QuotaAccount>,
        snapshots: List<AccountSnapshot>,
    ): List<ProviderOverview> {
        val snapshotsById = linkedMapOf<String, AccountSnapshot>()
        snapshots.forEach { snapshotsById.putIfAbsent(it.accountId, it) }

        val grouped = linkedMapOf<ProviderId, MutableList<QuotaAccount>>()
        accounts.withIndex()
            .sortedWith(compareBy<IndexedValue<QuotaAccount>> { it.value.sortOrder }.thenBy { it.index })
            .forEach { grouped.getOrPut(it.value.provider) { mutableListOf() }.add(it.value) }

        val rows = grouped.map { (provider, providerAccounts) ->
            makeRow(provider, providerAccounts, snapshotsById)
        }
        val totalRequests = rows.fold(BigDecimal.ZERO) { total, row ->
            row.todayRequests?.let { total + BigDecimal.valueOf(it) } ?: total
        }
        return if (totalRequests.signum() == 0) {
            rows
        } else {
            rows.map { row ->
                val fraction = row.todayRequests
                    ?.let { BigDecimal.valueOf(it).divide(totalRequests, 16, java.math.RoundingMode.HALF_UP).toDouble() }
                    ?: 0.0
                row.copy(requestFraction = fraction)
            }
        }
    }

    private fun makeRow(
        provider: ProviderId,
        providerAccounts: List<QuotaAccount>,
        snapshotsById: Map<String, AccountSnapshot>,
    ): ProviderOverview {
        val enabledAccounts = providerAccounts.filter { it.isEnabled }
        val enabledSnapshots = enabledAccounts.mapNotNull { snapshotsById[it.id] }
        val usages = enabledSnapshots.mapNotNull { it.usage }
        val balances = sumMoney(usages.flatMap { it.balances.map { balance -> balance.available } })
        val todayCosts = sumMoney(usages.mapNotNull { it.spend.today ?: it.today?.actualCost })
        val requestValues = usages.mapNotNull { it.today?.requests }.filter { it >= 0L }
        val todayRequests = sumLongs(requestValues)
        val quotaWindows = usages.firstOrNull { it.quotaWindows.isNotEmpty() }?.quotaWindows.orEmpty()
        val hasData = usages.any(::hasData)
        val isStale = enabledSnapshots.any { snapshot ->
            snapshot.health is AccountHealth.Stale || snapshot.health is AccountHealth.Unavailable
        }

        return ProviderOverview(
            provider = provider,
            displayName = displayNames[provider] ?: provider.raw,
            enabledAccountCount = enabledAccounts.size,
            balances = balances,
            todayCosts = todayCosts,
            todayRequests = todayRequests,
            quotaWindows = quotaWindows,
            hasData = enabledAccounts.isNotEmpty() && hasData,
            isStale = isStale,
            requestFraction = 0.0,
        )
    }

    private fun hasData(usage: ProviderUsageSnapshot): Boolean =
        usage.balances.isNotEmpty() ||
            usage.spendingLimit != null ||
            usage.spend.today != null ||
            usage.spend.week != null ||
            usage.spend.month != null ||
            usage.spend.total != null ||
            usage.quotaWindows.isNotEmpty() ||
            usage.today != null ||
            usage.total != null ||
            usage.dailyUsage.isNotEmpty() ||
            usage.modelUsage.isNotEmpty() ||
            usage.providerStatus != null ||
            usage.metricsUnavailableReason != null

    private fun sumMoney(values: List<Money>): List<Money> = values
        .groupBy { it.currency }
        .toSortedMap()
        .map { (currency, monies) ->
            val amount = monies.fold(BigDecimal.ZERO) { total, money -> total.add(money.value) }
            Money.fromString(amount.toPlainString(), currency)
        }

    private fun sumLongs(values: List<Long>): Long? {
        if (values.isEmpty()) return null
        return runCatching { values.fold(0L, Math::addExact) }.getOrNull()
    }
}
