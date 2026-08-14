package com.liangrui.quotaglance.ui

import com.liangrui.quotaglance.core.AccountHealth
import com.liangrui.quotaglance.core.AccountSnapshot
import com.liangrui.quotaglance.core.MonetaryBalance
import com.liangrui.quotaglance.core.Money
import com.liangrui.quotaglance.core.ProviderId
import com.liangrui.quotaglance.core.ProviderUsageSnapshot
import com.liangrui.quotaglance.core.QuotaAccount
import com.liangrui.quotaglance.core.QuotaWindow
import com.liangrui.quotaglance.core.SpendSummary
import com.liangrui.quotaglance.core.UsageCounters
import java.math.BigDecimal
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class OverviewPresentationTest {
    @Test
    fun `provider rows follow account sort order and first appearance`() {
        val accounts = listOf(
            account("deep-late", ProviderId.DEEP_SEEK, sortOrder = 8),
            account("kimi-first", ProviderId.KIMI, sortOrder = 1),
            account("deep-first", ProviderId.DEEP_SEEK, sortOrder = 1),
        )

        val rows = ProviderOverviewPresenter.present(accounts, emptyList())

        assertEquals(listOf(ProviderId.KIMI, ProviderId.DEEP_SEEK), rows.map { it.provider })
        assertEquals("Kimi", rows[0].displayName)
        assertEquals("DeepSeek", rows[1].displayName)
    }

    @Test
    fun `disabled accounts remain visible but do not contribute totals`() {
        val enabled = account("enabled", ProviderId.DEEP_SEEK, sortOrder = 0)
        val disabled = account("disabled", ProviderId.DEEP_SEEK, sortOrder = 1, enabled = false)
        val snapshots = listOf(
            snapshot(enabled, usage(balance = money("0.1", "USD"), cost = money("0.2", "USD"), requests = 2)),
            snapshot(disabled, usage(balance = money("999", "USD"), cost = money("999", "USD"), requests = 999)),
        )

        val row = ProviderOverviewPresenter.present(listOf(enabled, disabled), snapshots).single()

        assertEquals(1, row.enabledAccountCount)
        assertEquals(listOf(money("0.1", "USD")), row.balances)
        assertEquals(listOf(money("0.2", "USD")), row.todayCosts)
        assertEquals(2L, row.todayRequests)
        assertTrue(row.hasData)
        assertFalse(row.isStale)
    }

    @Test
    fun `same currency balances sum with exact decimal values`() {
        val first = account("first", ProviderId.API_INFO, sortOrder = 0)
        val second = account("second", ProviderId.API_INFO, sortOrder = 1)

        val rows = ProviderOverviewPresenter.present(
            listOf(first, second),
            listOf(
                snapshot(first, usage(balance = money("0.1", "USD"))),
                snapshot(second, usage(balance = money("0.2", "USD"))),
            ),
        )

        assertEquals(listOf(money("0.3", "USD")), rows.single().balances)
    }

    @Test
    fun `missing snapshots have no data while stale usage remains visible`() {
        val stale = account("stale", ProviderId.DEEP_SEEK, sortOrder = 0)
        val missing = account("missing", ProviderId.DEEP_SEEK, sortOrder = 1)
        val staleSnapshot = snapshot(
            stale,
            usage(balance = money("8.5", "USD"), cost = money("1.25", "USD"), requests = 7),
            health = AccountHealth.Stale("offline"),
        )

        val staleRow = ProviderOverviewPresenter.present(listOf(stale), listOf(staleSnapshot)).single()
        assertTrue(staleRow.hasData)
        assertTrue(staleRow.isStale)
        assertEquals(listOf(money("8.5", "USD")), staleRow.balances)
        assertEquals(listOf(money("1.25", "USD")), staleRow.todayCosts)

        val missingRow = ProviderOverviewPresenter.present(listOf(missing), emptyList()).single()
        assertFalse(missingRow.hasData)
        assertFalse(missingRow.isStale)
        assertTrue(missingRow.balances.isEmpty())
        assertTrue(missingRow.todayCosts.isEmpty())
    }

    @Test
    fun `unavailable snapshot has no data and is stale`() {
        val account = account("unavailable", ProviderId.KIMI, sortOrder = 0)
        val row = ProviderOverviewPresenter.present(
            listOf(account),
            listOf(snapshot(account, usage = null, health = AccountHealth.Unavailable("timeout"))),
        ).single()

        assertFalse(row.hasData)
        assertTrue(row.isStale)
        assertTrue(row.balances.isEmpty())
        assertTrue(row.todayCosts.isEmpty())
    }

    @Test
    fun `first available quota windows are exposed`() {
        val first = account("first", ProviderId.MINI_MAX, sortOrder = 0)
        val second = account("second", ProviderId.MINI_MAX, sortOrder = 1)
        val firstUsage = ProviderUsageSnapshot(
            quotaWindows = listOf(
                QuotaWindow("first window", remaining = BigDecimal("3"), unit = "requests"),
            ),
            receivedAtMillis = 1,
        )
        val secondUsage = ProviderUsageSnapshot(
            quotaWindows = listOf(
                QuotaWindow("second window", remaining = BigDecimal("4"), unit = "requests"),
            ),
            receivedAtMillis = 2,
        )

        val row = ProviderOverviewPresenter.present(
            listOf(first, second),
            listOf(snapshot(first, firstUsage), snapshot(second, secondUsage)),
        ).single()

        assertEquals(firstUsage.quotaWindows, row.quotaWindows)
    }

    @Test
    fun `request fractions normalize over available requests and are zero without requests`() {
        val first = account("first", ProviderId.DEEP_SEEK, sortOrder = 0)
        val second = account("second", ProviderId.KIMI, sortOrder = 1)
        val rows = ProviderOverviewPresenter.present(
            listOf(first, second),
            listOf(
                snapshot(first, usage(requests = 1)),
                snapshot(second, usage(requests = 3)),
            ),
        )

        assertEquals(0.25, rows[0].requestFraction, 0.000001)
        assertEquals(0.75, rows[1].requestFraction, 0.000001)

        val noRequests = ProviderOverviewPresenter.present(
            listOf(first, second),
            listOf(snapshot(first, usage()), snapshot(second, usage())),
        )
        assertEquals(0.0, noRequests[0].requestFraction, 0.0)
        assertEquals(0.0, noRequests[1].requestFraction, 0.0)
    }

    private fun account(id: String, provider: ProviderId, sortOrder: Int, enabled: Boolean = true) =
        QuotaAccount(id, id, provider = provider, isEnabled = enabled, sortOrder = sortOrder)

    private fun snapshot(
        account: QuotaAccount,
        usage: ProviderUsageSnapshot?,
        health: AccountHealth = AccountHealth.Healthy,
    ) = AccountSnapshot(
        accountId = account.id,
        displayName = account.displayName,
        provider = account.provider,
        usage = usage,
        health = health,
        lastSuccessAtMillis = usage?.receivedAtMillis,
    )

    private fun usage(
        balance: Money? = null,
        cost: Money? = null,
        requests: Long? = null,
    ) = ProviderUsageSnapshot(
        balances = balance?.let { listOf(MonetaryBalance("Balance", it)) }.orEmpty(),
        spend = SpendSummary(today = cost),
        today = if (cost == null && requests == null) null else UsageCounters(actualCost = cost, requests = requests),
        receivedAtMillis = 1,
    )

    private fun money(amount: String, currency: String) = Money.fromString(amount, currency)
}
