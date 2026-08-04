package com.liangrui.quotaglance.refresh

import com.liangrui.quotaglance.core.AccountHealth
import com.liangrui.quotaglance.core.AccountSnapshot
import com.liangrui.quotaglance.core.AlertEvaluator
import com.liangrui.quotaglance.core.Money
import com.liangrui.quotaglance.core.ProviderFailure
import com.liangrui.quotaglance.core.ProviderId
import com.liangrui.quotaglance.core.ProviderUsageSnapshot
import com.liangrui.quotaglance.core.QuotaAccount
import com.liangrui.quotaglance.core.UsageProvider
import com.liangrui.quotaglance.data.AccountRepository
import com.liangrui.quotaglance.data.CredentialVault
import com.liangrui.quotaglance.data.SnapshotRepository
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.supervisorScope

interface ProviderRegistry {
    fun provider(id: ProviderId): UsageProvider
}

class TestProviderRegistry(private val providers: Map<ProviderId, UsageProvider>) : ProviderRegistry {
    override fun provider(id: ProviderId): UsageProvider = providers[id] ?: throw ProviderFailure("providerUnavailable")
}

interface NotificationDispatcher {
    suspend fun notifyLowBalance(account: QuotaAccount, remaining: Money)
}

interface WidgetRefresh {
    suspend fun refresh()
}

object NoopWidgetRefresh : WidgetRefresh {
    override suspend fun refresh() = Unit
}

data class RefreshBatchResult(
    val successes: Int,
    val failures: Int,
)

private data class RefreshAttempt(
    val accountId: String,
    val snapshot: AccountSnapshot?,
    val succeeded: Boolean,
)

/** Per-account refresh orchestration. One failing provider never blocks another account. */
class RefreshCoordinator(
    private val providers: ProviderRegistry,
    private val accounts: AccountRepository,
    private val credentials: CredentialVault,
    private val snapshots: SnapshotRepository,
    private val notifications: NotificationDispatcher,
    private val widgetRefresh: WidgetRefresh,
    private val nowMillis: () -> Long = { System.currentTimeMillis() },
) {
    suspend fun refreshAll(): RefreshBatchResult = supervisorScope {
        val attempts = accounts.list().filter { it.isEnabled }.map { account ->
            async { refresh(account) }
        }.awaitAll()
        evaluateAlerts(attempts.filter { it.succeeded && it.snapshot != null }.mapNotNull { it.snapshot })
        runCatching { widgetRefresh.refresh() }
        RefreshBatchResult(
            successes = attempts.count { it.succeeded },
            failures = attempts.count { !it.succeeded },
        )
    }

    suspend fun refreshAccount(accountId: String): RefreshBatchResult {
        val account = accounts.list().firstOrNull { it.id == accountId } ?: return RefreshBatchResult(0, 1)
        if (!account.isEnabled) return RefreshBatchResult(0, 0)
        val attempt = refresh(account)
        if (attempt.succeeded && attempt.snapshot != null) evaluateAlerts(listOf(attempt.snapshot))
        runCatching { widgetRefresh.refresh() }
        return RefreshBatchResult(if (attempt.succeeded) 1 else 0, if (attempt.succeeded) 0 else 1)
    }

    /** Publishes the snapshot returned by account-editor detection without issuing a second request. */
    suspend fun recordSuccessfulSnapshot(accountId: String, usage: ProviderUsageSnapshot) {
        val account = accounts.list().firstOrNull { it.id == accountId } ?: return
        val attempt = success(account, usage)
        evaluateAlerts(listOf(checkNotNull(attempt.snapshot)))
        runCatching { widgetRefresh.refresh() }
    }

    private suspend fun refresh(account: QuotaAccount): RefreshAttempt {
        val apiKey = credentials.read(account.id)
        if (apiKey.isNullOrEmpty()) return failure(account, "missingCredential")
        return try {
            val provider = providers.provider(account.provider)
            val usage = if (account.detectedProfile == null) {
                val detection = provider.detect(apiKey)
                account.detectedProfile = detection.profile
                accounts.upsert(account)
                detection.snapshot
            } else {
                provider.fetch(apiKey, account.detectedProfile!!)
            }
            success(account, usage)
        } catch (error: Throwable) {
            failure(account, error.token())
        }
    }

    private suspend fun success(account: QuotaAccount, usage: ProviderUsageSnapshot): RefreshAttempt {
        val remaining = usage.remaining?.value
        val health = if (account.lowBalanceThreshold != null && remaining != null && remaining <= account.lowBalanceThreshold) {
            AccountHealth.BelowThreshold
        } else {
            AccountHealth.Healthy
        }
        val snapshot = AccountSnapshot(
            accountId = account.id,
            displayName = account.displayName,
            provider = account.provider,
            detectedProfile = account.detectedProfile,
            lowBalanceThreshold = account.lowBalanceThreshold,
            usage = usage,
            health = health,
            lastSuccessAtMillis = usage.receivedAtMillis,
        )
        snapshots.write(snapshot)
        return RefreshAttempt(account.id, snapshot, true)
    }

    private suspend fun failure(account: QuotaAccount, reason: String): RefreshAttempt {
        val previous = snapshots.read(account.id)
        val health = if (previous?.usage == null) AccountHealth.Unavailable(reason) else AccountHealth.Stale(reason)
        val snapshot = AccountSnapshot(
            accountId = account.id,
            displayName = account.displayName,
            provider = account.provider,
            detectedProfile = account.detectedProfile,
            lowBalanceThreshold = account.lowBalanceThreshold,
            usage = previous?.usage,
            health = health,
            lastSuccessAtMillis = previous?.lastSuccessAtMillis,
        )
        snapshots.write(snapshot)
        return RefreshAttempt(account.id, snapshot, false)
    }

    private suspend fun evaluateAlerts(freshSnapshots: List<AccountSnapshot>) {
        if (freshSnapshots.isEmpty()) return
        val latest = accounts.list().toMutableList()
        val evaluation = AlertEvaluator.evaluate(latest, freshSnapshots)
        if (evaluation.didChange) {
            for (account in latest) {
                accounts.upsert(account)
            }
        }
        evaluation.notifications.forEach { notification ->
            runCatching { notifications.notifyLowBalance(notification.account, notification.remaining) }
        }
    }

    private fun Throwable.token(): String = when (this) {
        is ProviderFailure -> message ?: token
        else -> "offline"
    }
}
