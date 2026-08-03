package com.liangrui.quotaglance.ui

import com.liangrui.quotaglance.core.AccountHealth
import com.liangrui.quotaglance.core.AccountSnapshot
import com.liangrui.quotaglance.core.MonetaryBalance
import com.liangrui.quotaglance.core.Money
import com.liangrui.quotaglance.core.ProviderUsageSnapshot
import com.liangrui.quotaglance.core.QuotaAccount
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PresentationContractTest {
    @Test
    fun `routes support all account and account uuid deep links`() {
        assertEquals(AppRoute.All, AppRoute.parse("quotaglance://all"))
        assertEquals(AppRoute.Account("abc"), AppRoute.parse("quotaglance://account/abc"))
        assertEquals(AppRoute.Account("deleted"), AppRoute.parse("quotaglance://account/deleted"))
        assertEquals(AppRoute.All, AppRoute.parse("https://example.com"))
    }

    @Test
    fun `deleted account selection falls back to all accounts`() {
        val accounts = listOf(QuotaAccount("one", "Primary"))
        assertEquals(AppRoute.All, AppRoute.resolve(AppRoute.Account("deleted"), accounts))
        assertEquals(AppRoute.Account("one"), AppRoute.resolve(AppRoute.Account("one"), accounts))
    }

    @Test
    fun `quick view resolves default and deleted selections to a valid route`() {
        val accounts = listOf(QuotaAccount("one", "Primary"))
        assertEquals(AppRoute.Account("one"), QuickViewSelection.Default.resolve("one", accounts))
        assertEquals(AppRoute.All, QuickViewSelection.Default.resolve("deleted", accounts))
        assertEquals(AppRoute.All, QuickViewSelection.Account("deleted").resolve(null, accounts))
        assertEquals(AppRoute.All, QuickViewSelection.All.resolve("one", accounts))
    }

    @Test
    fun `dashboard presents empty healthy and partial states`() {
        val now = Instant.parse("2026-08-03T12:00:00Z")
        assertEquals(
            DashboardStatus.Empty,
            DashboardPresenter.present(emptyList(), emptyList(), now, AppRoute.All).status,
        )
        val account = QuotaAccount("one", "Primary")
        val healthy = AccountSnapshot(
            accountId = "one",
            health = AccountHealth.Healthy,
            usage = ProviderUsageSnapshot(
                balances = listOf(MonetaryBalance("Balance", Money.fromString("10", "USD"))),
                receivedAtMillis = 100,
            ),
        )
        assertEquals(
            DashboardStatus.Healthy,
            DashboardPresenter.present(listOf(account), listOf(healthy), now, AppRoute.All).status,
        )
        val stale = healthy.copy(health = AccountHealth.Stale("offline"))
        val state = DashboardPresenter.present(listOf(account), listOf(stale), now, AppRoute.All)
        assertEquals(DashboardStatus.Partial, state.status)
        assertTrue(state.aggregate.isPartial)
    }
}
