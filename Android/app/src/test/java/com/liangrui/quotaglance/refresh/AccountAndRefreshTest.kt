package com.liangrui.quotaglance.refresh

import com.liangrui.quotaglance.core.AccountHealth
import com.liangrui.quotaglance.core.AccountSnapshot
import com.liangrui.quotaglance.core.CredentialKind
import com.liangrui.quotaglance.core.MonetaryBalance
import com.liangrui.quotaglance.core.Money
import com.liangrui.quotaglance.core.ProviderDescriptor
import com.liangrui.quotaglance.core.ProviderDetection
import com.liangrui.quotaglance.core.ProviderFailure
import com.liangrui.quotaglance.core.ProviderId
import com.liangrui.quotaglance.core.ProviderProfile
import com.liangrui.quotaglance.core.ProviderRegion
import com.liangrui.quotaglance.core.ProviderUsageSnapshot
import com.liangrui.quotaglance.core.QuotaAccount
import com.liangrui.quotaglance.core.UsageProvider
import com.liangrui.quotaglance.data.AccountMutationService
import com.liangrui.quotaglance.data.AccountValidator
import com.liangrui.quotaglance.data.InMemoryAccountRepository
import com.liangrui.quotaglance.data.InMemoryCredentialVault
import com.liangrui.quotaglance.data.InMemorySnapshotRepository
import java.math.BigDecimal
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AccountAndRefreshTest {
    @Test
    fun `validator trims names and rejects duplicate names empty replacement keys and account overflow`() {
        val existing = listOf(QuotaAccount("one", "Primary"))

        assertEquals(
            AccountValidator.Error.DuplicateDisplayName,
            AccountValidator.validate(existing, null, "  primary  ", "key").error,
        )
        assertEquals(
            AccountValidator.Error.EmptyApiKey,
            AccountValidator.validate(existing, null, "Second", "   ").error,
        )
        assertEquals(
            AccountValidator.Error.AccountLimit,
            AccountValidator.validate((1..20).map { QuotaAccount("$it", "Account $it") }, null, "Next", "key").error,
        )
        assertEquals("Second", AccountValidator.validate(existing, null, "  Second  ", "key").normalizedDisplayName)
    }

    @Test
    fun `delete removes account credential and cached snapshot together`() = runTest {
        val accounts = InMemoryAccountRepository(listOf(QuotaAccount("one", "Primary")))
        val credentials = InMemoryCredentialVault(mapOf("one" to "secret"))
        val snapshots = InMemorySnapshotRepository(mapOf("one" to healthySnapshot("one", "20")))
        val service = AccountMutationService(accounts, credentials, snapshots)

        service.delete("one")

        assertTrue(accounts.list().isEmpty())
        assertNull(credentials.read("one"))
        assertNull(snapshots.read("one"))
    }

    @Test
    fun `changing a provider requires a replacement API key`() = runTest {
        val accounts = InMemoryAccountRepository(
            listOf(QuotaAccount("one", "Primary", provider = ProviderId.API_INFO)),
        )
        val service = AccountMutationService(
            accounts,
            InMemoryCredentialVault(mapOf("one" to "api-info-key")),
            InMemorySnapshotRepository(),
        )

        val result = service.save(
            QuotaAccount("one", "Primary", provider = ProviderId.DEEP_SEEK),
            replacementApiKey = null,
        )

        assertEquals(AccountValidator.Error.EmptyApiKey, result.error)
        assertEquals(ProviderId.API_INFO, accounts.list().single().provider)
    }

    @Test
    fun `new accounts receive an increasing stable sort order`() = runTest {
        val accounts = InMemoryAccountRepository()
        val credentials = InMemoryCredentialVault()
        val service = AccountMutationService(accounts, credentials, InMemorySnapshotRepository())

        service.create(QuotaAccount("first", "First"), "first-key")
        service.create(QuotaAccount("second", "Second"), "second-key")

        assertEquals(listOf(0, 1), accounts.list().map { it.sortOrder })
    }

    @Test
    fun `disabling an account clears its active low-balance episode`() = runTest {
        val account = QuotaAccount(
            "one",
            "Primary",
            lowBalanceThreshold = BigDecimal("5"),
            alertEpisodeActive = true,
        )
        val accounts = InMemoryAccountRepository(listOf(account))
        val service = AccountMutationService(accounts, InMemoryCredentialVault(), InMemorySnapshotRepository())

        service.save(account.copy(isEnabled = false))

        assertFalse(accounts.list().single().alertEpisodeActive)
    }

    @Test
    fun `refresh isolates account failures retains old usage and persists alert episode`() = runTest {
        val healthy = QuotaAccount(
            id = "healthy",
            displayName = "Healthy",
            detectedProfile = ProviderProfile.globalStandard(),
            lowBalanceThreshold = BigDecimal("10"),
        )
        val failing = QuotaAccount(
            id = "failing",
            displayName = "Failing",
            provider = ProviderId.DEEP_SEEK,
            detectedProfile = ProviderProfile.globalStandard(),
        )
        val accounts = InMemoryAccountRepository(listOf(healthy, failing))
        val credentials = InMemoryCredentialVault(mapOf("healthy" to "key-1", "failing" to "key-2"))
        val snapshots = InMemorySnapshotRepository(mapOf("failing" to healthySnapshot("failing", "30", 50)))
        val notifications = RecordingNotifications()
        val coordinator = RefreshCoordinator(
            providers = TestProviderRegistry(
                mapOf(
                    ProviderId.API_INFO to FakeProvider(ProviderId.API_INFO, healthyUsage("5")),
                    ProviderId.DEEP_SEEK to FakeProvider(ProviderId.DEEP_SEEK, failure = ProviderFailure("rateLimited")),
                ),
            ),
            accounts = accounts,
            credentials = credentials,
            snapshots = snapshots,
            notifications = notifications,
            widgetRefresh = NoopWidgetRefresh,
            nowMillis = { 100L },
        )

        val result = coordinator.refreshAll()

        assertEquals(1, result.successes)
        assertEquals(1, result.failures)
        assertEquals(AccountHealth.BelowThreshold, snapshots.read("healthy")?.health)
        val stale = checkNotNull(snapshots.read("failing"))
        assertEquals(AccountHealth.Stale("rateLimited"), stale.health)
        assertEquals("30", stale.remaining?.canonicalAmount)
        assertEquals(1, notifications.notifications.size)
        assertTrue(checkNotNull(accounts.list().firstOrNull { it.id == "healthy" }).alertEpisodeActive)
        assertFalse(checkNotNull(accounts.list().firstOrNull { it.id == "failing" }).alertEpisodeActive)
    }

    private class FakeProvider(
        override val id: ProviderId,
        private val usage: ProviderUsageSnapshot? = null,
        private val failure: Throwable? = null,
    ) : UsageProvider {
        override val descriptor = ProviderDescriptor(id, id.raw, { true }, { "profile" })

        override suspend fun detect(apiKey: String): ProviderDetection =
            ProviderDetection(ProviderProfile.globalStandard(), fetch(apiKey, ProviderProfile.globalStandard()))

        override suspend fun fetch(apiKey: String, profile: ProviderProfile): ProviderUsageSnapshot {
            failure?.let { throw it }
            return checkNotNull(usage)
        }
    }

    private class RecordingNotifications : NotificationDispatcher {
        val notifications = mutableListOf<String>()
        override suspend fun notifyLowBalance(account: QuotaAccount, remaining: Money) {
            notifications += account.id
        }
    }

    private fun healthyUsage(amount: String): ProviderUsageSnapshot = ProviderUsageSnapshot(
        balances = listOf(MonetaryBalance("Balance", Money.fromString(amount, "USD"))),
        receivedAtMillis = 100,
    )

    private fun healthySnapshot(id: String, amount: String, at: Long = 0): AccountSnapshot = AccountSnapshot(
        accountId = id,
        usage = healthyUsage(amount),
        health = AccountHealth.Healthy,
        lastSuccessAtMillis = at,
    )
}
