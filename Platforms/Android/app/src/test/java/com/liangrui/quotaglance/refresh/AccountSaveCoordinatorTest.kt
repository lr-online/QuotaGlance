package com.liangrui.quotaglance.refresh

import com.liangrui.quotaglance.core.ProviderDescriptor
import com.liangrui.quotaglance.core.ProviderDetection
import com.liangrui.quotaglance.core.ProviderFailure
import com.liangrui.quotaglance.core.ProviderId
import com.liangrui.quotaglance.core.ProviderProfile
import com.liangrui.quotaglance.core.ProviderUsageSnapshot
import com.liangrui.quotaglance.core.QuotaAccount
import com.liangrui.quotaglance.core.UsageProvider
import com.liangrui.quotaglance.data.InMemoryAccountRepository
import com.liangrui.quotaglance.data.InMemoryCredentialVault
import com.liangrui.quotaglance.data.InMemorySnapshotRepository
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AccountSaveCoordinatorTest {
    @Test
    fun `a failed initial key detection does not persist the account or credential`() = runTest {
        val accounts = InMemoryAccountRepository()
        val credentials = InMemoryCredentialVault()
        val snapshots = InMemorySnapshotRepository()
        val provider = FailingProvider()
        val refresh = RefreshCoordinator(
            providers = TestProviderRegistry(mapOf(ProviderId.API_INFO to provider)),
            accounts = accounts,
            credentials = credentials,
            snapshots = snapshots,
            notifications = NoopNotifications,
            widgetRefresh = NoopWidgetRefresh,
        )
        val coordinator = AccountSaveCoordinator(
            providers = TestProviderRegistry(mapOf(ProviderId.API_INFO to provider)),
            accounts = accounts,
            credentials = credentials,
            mutationService = com.liangrui.quotaglance.data.AccountMutationService(accounts, credentials, snapshots),
            refreshCoordinator = refresh,
        )

        val result = coordinator.save(
            QuotaAccount("account-1", "Primary", provider = ProviderId.API_INFO),
            apiKeyText = "invalid-key",
        )

        assertEquals(AccountSaveResult.ProviderFailure("unauthorized"), result)
        assertTrue(accounts.list().isEmpty())
        assertNull(credentials.read("account-1"))
        assertNull(snapshots.read("account-1"))
    }

    @Test
    fun `unexpected detection failures log a bounded type chain without exception messages`() = runTest {
        val accounts = InMemoryAccountRepository()
        val credentials = InMemoryCredentialVault()
        val snapshots = InMemorySnapshotRepository()
        val provider = InitializerFailingProvider()
        val logger = CapturingLogger()
        val refresh = RefreshCoordinator(
            providers = TestProviderRegistry(mapOf(ProviderId.API_INFO to provider)),
            accounts = accounts,
            credentials = credentials,
            snapshots = snapshots,
            notifications = NoopNotifications,
            widgetRefresh = NoopWidgetRefresh,
        )
        val coordinator = AccountSaveCoordinator(
            providers = TestProviderRegistry(mapOf(ProviderId.API_INFO to provider)),
            accounts = accounts,
            credentials = credentials,
            mutationService = com.liangrui.quotaglance.data.AccountMutationService(accounts, credentials, snapshots),
            refreshCoordinator = refresh,
            logger = logger,
        )

        val result = coordinator.save(
            QuotaAccount("account-1", "Primary", provider = ProviderId.API_INFO),
            apiKeyText = "key",
        )

        assertEquals(AccountSaveResult.ProviderFailure("offline"), result)
        val failure = logger.entries.single { it.stage == "failure" }.detail
        assertEquals("types=ExceptionInInitializerError->IllegalArgumentException", failure)
        assertFalse(failure.contains("secret-message"))
    }

    private open class FailingProvider : UsageProvider {
        override val id = ProviderId.API_INFO
        override val descriptor = ProviderDescriptor(id, "API Info", { true }, { "profile" })

        override suspend fun detect(apiKey: String): ProviderDetection = throw ProviderFailure("unauthorized")

        override suspend fun fetch(apiKey: String, profile: ProviderProfile): ProviderUsageSnapshot =
            throw ProviderFailure("unauthorized")
    }

    private class InitializerFailingProvider : FailingProvider() {
        override suspend fun detect(apiKey: String): ProviderDetection =
            throw ExceptionInInitializerError(IllegalArgumentException("secret-message"))
    }

    private class CapturingLogger : AccountSaveLogger {
        data class Entry(val stage: String, val detail: String)

        val entries = mutableListOf<Entry>()

        override fun record(stage: String, provider: ProviderId, detail: String) {
            entries += Entry(stage, detail)
        }
    }

    private object NoopNotifications : NotificationDispatcher {
        override suspend fun notifyLowBalance(account: QuotaAccount, remaining: com.liangrui.quotaglance.core.Money) = Unit
    }
}
