package com.liangrui.quotaglance.data

import com.liangrui.quotaglance.core.AccountHealth
import com.liangrui.quotaglance.core.AccountSnapshot
import com.liangrui.quotaglance.core.CredentialKind
import com.liangrui.quotaglance.core.DailyUsage
import com.liangrui.quotaglance.core.MonetaryBalance
import com.liangrui.quotaglance.core.ModelUsage
import com.liangrui.quotaglance.core.Money
import com.liangrui.quotaglance.core.ProviderId
import com.liangrui.quotaglance.core.ProviderProfile
import com.liangrui.quotaglance.core.ProviderRegion
import com.liangrui.quotaglance.core.ProviderUsageSnapshot
import com.liangrui.quotaglance.core.QuotaAccount
import com.liangrui.quotaglance.core.QuotaWindow
import com.liangrui.quotaglance.core.SpendSummary
import com.liangrui.quotaglance.core.UsageCounters
import java.math.BigDecimal
import org.junit.Assert.assertEquals
import org.junit.Test

class StorageCodecTest {
    @Test
    fun `account metadata survives a JSON round trip without credentials`() {
        val accounts = listOf(
            QuotaAccount(
                id = "account-1",
                displayName = " Primary ",
                provider = ProviderId.OPEN_ROUTER,
                detectedProfile = ProviderProfile(ProviderRegion.GLOBAL, CredentialKind.MANAGEMENT),
                isEnabled = false,
                sortOrder = 4,
                lowBalanceThreshold = BigDecimal("10.00"),
                alertEpisodeActive = true,
            ),
        )

        val encoded = StorageJsonCodec.encodeAccounts(accounts)

        assertEquals(accounts, StorageJsonCodec.decodeAccounts(encoded))
        assertEquals(false, encoded.contains("secret", ignoreCase = true))
    }

    @Test
    fun `full provider snapshot and stale state survive a JSON round trip`() {
        val snapshot = AccountSnapshot(
            accountId = "account-1",
            displayName = "Primary",
            provider = ProviderId.MINI_MAX,
            detectedProfile = ProviderProfile(ProviderRegion.CHINA, CredentialKind.TOKEN_PLAN),
            lowBalanceThreshold = BigDecimal("2.5"),
            usage = ProviderUsageSnapshot(
                balances = listOf(MonetaryBalance("Balance", Money.fromString("12.00", "USD"))),
                spend = SpendSummary(today = Money.fromString("1.50", "USD")),
                quotaWindows = listOf(QuotaWindow("Five-hour", BigDecimal("50"), BigDecimal("100"), BigDecimal("50"), "%", 1000)),
                today = UsageCounters(Money.fromString("1.50", "USD"), requests = 20, totalTokens = 40),
                dailyUsage = listOf(DailyUsage("2026-08-03", Money.fromString("1.50", "USD"), requests = 20)),
                modelUsage = listOf(ModelUsage("M2", Money.fromString("1.50", "USD"), requests = 20)),
                providerStatus = "active",
                metricsUnavailableReason = "none",
                receivedAtMillis = 999,
            ),
            health = AccountHealth.Stale("offline"),
            lastSuccessAtMillis = 900,
        )

        assertEquals(snapshot, StorageJsonCodec.decodeSnapshot(StorageJsonCodec.encodeSnapshot(snapshot)))
    }
}
