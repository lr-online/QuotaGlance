package com.liangrui.quotaglance.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.liangrui.quotaglance.core.AccountSnapshot
import com.liangrui.quotaglance.core.ProviderId
import com.liangrui.quotaglance.core.QuotaAccount
import com.liangrui.quotaglance.core.OpenAIServiceStatus
import com.liangrui.quotaglance.data.AppPreferences
import com.liangrui.quotaglance.data.RefreshInterval
import com.liangrui.quotaglance.data.AccountMutationService
import com.liangrui.quotaglance.refresh.AccountSaveCoordinator
import com.liangrui.quotaglance.refresh.AccountSaveResult
import com.liangrui.quotaglance.refresh.AndroidAppContainer
import com.liangrui.quotaglance.refresh.ForegroundRefreshScheduler
import com.liangrui.quotaglance.refresh.RefreshScheduler
import java.util.UUID
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

enum class AppSection { Overview, Accounts, Settings }

data class QuotaGlanceUiState(
    val accounts: List<QuotaAccount> = emptyList(),
    val snapshots: List<AccountSnapshot> = emptyList(),
    val preferences: AppPreferences = AppPreferences(),
    val route: AppRoute = AppRoute.All,
    val section: AppSection = AppSection.Overview,
    val refreshing: Boolean = false,
    val message: String? = null,
    val serviceStatus: OpenAIServiceStatus? = null,
)

class QuotaGlanceViewModel(
    private val container: AndroidAppContainer,
    initialRoute: AppRoute,
) : ViewModel() {
    private val mutationService = AccountMutationService(container.accounts, container.credentials, container.snapshots)
    private val accountSaveCoordinator = AccountSaveCoordinator(
        providers = container.providers,
        accounts = container.accounts,
        credentials = container.credentials,
        mutationService = mutationService,
        refreshCoordinator = container.refreshRun,
        logger = container.accountSaveLogger,
    )
    private val mutableState = MutableStateFlow(QuotaGlanceUiState(route = initialRoute))
    private val refreshMutex = Mutex()
    private val foregroundRefreshScheduler = ForegroundRefreshScheduler(viewModelScope, ::refreshAllInternal)
    private var foregroundRefreshActive = false
    val state = mutableState.asStateFlow()

    init {
        viewModelScope.launch {
            container.accounts.accounts.collect { accounts ->
                mutableState.value = mutableState.value.copy(
                    accounts = accounts,
                    route = AppRoute.resolve(mutableState.value.route, accounts),
                )
            }
        }
        viewModelScope.launch {
            container.preferences.preferences.collect { preferences ->
                mutableState.value = mutableState.value.copy(preferences = preferences)
                if (foregroundRefreshActive) foregroundRefreshScheduler.start(preferences.refreshInterval.minutes.toLong())
            }
        }
        reloadSnapshots()
        viewModelScope.launch { mutableState.value = mutableState.value.copy(serviceStatus = container.serviceStatus.fetch()) }
    }

    fun setSection(section: AppSection) {
        mutableState.value = mutableState.value.copy(section = section)
    }

    fun routeTo(route: AppRoute) {
        mutableState.value = mutableState.value.copy(route = AppRoute.resolve(route, mutableState.value.accounts), section = AppSection.Overview)
    }

    fun refreshAll() = viewModelScope.launch { refreshAllInternal() }

    fun startForegroundRefresh() {
        foregroundRefreshActive = true
        foregroundRefreshScheduler.start(mutableState.value.preferences.refreshInterval.minutes.toLong())
    }

    fun stopForegroundRefresh() {
        foregroundRefreshActive = false
        foregroundRefreshScheduler.stop()
    }

    fun saveAccount(
        editingId: String?,
        displayName: String,
        provider: ProviderId,
        apiKey: String,
        enabled: Boolean,
        threshold: String,
    ) = viewModelScope.launch {
        val existing = mutableState.value.accounts.firstOrNull { it.id == editingId }
        val parsedThreshold = threshold.trim().let { value ->
            when {
                value.isEmpty() -> null
                else -> value.toBigDecimalOrNull()?.takeIf { it.signum() >= 0 }
            }
        }
        if (threshold.isNotBlank() && parsedThreshold == null) {
            mutableState.value = mutableState.value.copy(message = "InvalidThreshold")
            return@launch
        }
        val account = (existing ?: QuotaAccount(UUID.randomUUID().toString(), displayName, provider)).copy(
            displayName = displayName,
            provider = provider,
            detectedProfile = if (existing?.provider == provider) existing.detectedProfile else null,
            isEnabled = enabled,
            lowBalanceThreshold = parsedThreshold,
        )
        when (val result = accountSaveCoordinator.save(account, apiKey)) {
            AccountSaveResult.Saved -> {
                reloadSnapshotsInternal()
                mutableState.value = mutableState.value.copy(message = null)
            }
            is AccountSaveResult.ValidationFailure -> {
                mutableState.value = mutableState.value.copy(message = result.error.name)
            }
            is AccountSaveResult.ProviderFailure -> {
                mutableState.value = mutableState.value.copy(message = result.token)
            }
        }
    }

    fun deleteAccount(accountId: String) = viewModelScope.launch {
        mutationService.delete(accountId)
        if (mutableState.value.preferences.defaultQuickViewAccountId == accountId) {
            container.preferences.update(mutableState.value.preferences.copy(defaultQuickViewAccountId = null))
        }
        reloadSnapshotsInternal()
    }

    fun setEnabled(account: QuotaAccount, enabled: Boolean) = viewModelScope.launch {
        mutationService.save(account.copy(isEnabled = enabled))
        if (enabled) container.refreshRun.refreshAccount(account.id)
        reloadSnapshotsInternal()
    }

    fun updatePreferences(value: AppPreferences) = viewModelScope.launch {
        container.preferences.update(value)
        RefreshScheduler(container.application).schedule(value.refreshInterval.minutes.toLong())
    }

    fun clearMessage() {
        mutableState.value = mutableState.value.copy(message = null)
    }

    fun supportsLowBalanceThreshold(provider: ProviderId, profile: com.liangrui.quotaglance.core.ProviderProfile?): Boolean =
        container.providers.provider(provider).descriptor.supportsLowBalanceThreshold(profile)

    override fun onCleared() {
        foregroundRefreshScheduler.stop()
        super.onCleared()
    }

    private fun reloadSnapshots() = viewModelScope.launch { reloadSnapshotsInternal() }

    private suspend fun reloadSnapshotsInternal() {
        mutableState.value = mutableState.value.copy(snapshots = container.snapshots.all())
    }

    private suspend fun refreshAllInternal() = refreshMutex.withLock {
        mutableState.value = mutableState.value.copy(refreshing = true, message = null)
        val serviceStatus = container.serviceStatus.fetch()
        runCatching { container.refreshRun.refreshAll() }
            .onFailure { mutableState.value = mutableState.value.copy(message = it.message ?: "Refresh failed") }
        reloadSnapshotsInternal()
        mutableState.value = mutableState.value.copy(refreshing = false)
        mutableState.value = mutableState.value.copy(serviceStatus = serviceStatus)
    }
}

class QuotaGlanceViewModelFactory(
    private val container: AndroidAppContainer,
    private val initialRoute: AppRoute,
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T =
        QuotaGlanceViewModel(container, initialRoute) as T
}
