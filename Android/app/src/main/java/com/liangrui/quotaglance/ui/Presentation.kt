package com.liangrui.quotaglance.ui

import com.liangrui.quotaglance.core.AccountHealth
import com.liangrui.quotaglance.core.AccountSnapshot
import com.liangrui.quotaglance.core.AggregateSnapshot
import com.liangrui.quotaglance.core.QuotaAccount
import com.liangrui.quotaglance.core.SnapshotAggregator
import java.net.URI
import java.time.Instant

sealed interface AppRoute {
    data object All : AppRoute
    data class Account(val id: String) : AppRoute

    companion object {
        fun parse(raw: String?): AppRoute {
            val uri = runCatching { URI(raw ?: "") }.getOrNull() ?: return All
            if (uri.scheme != "quotaglance") return All
            if (uri.host == "all") return All
            if (uri.host == "account") {
                val id = uri.path.orEmpty().trim('/').substringBefore('/')
                if (id.isNotBlank()) return Account(id)
            }
            return All
        }

        fun resolve(route: AppRoute, accounts: List<QuotaAccount>): AppRoute = when (route) {
            All -> All
            is Account -> if (accounts.any { it.id == route.id }) route else All
        }
    }
}

/** Returns the account shown in the detail pane for a route, with a stable fallback for All. */
internal fun selectedAccountForRoute(route: AppRoute, accounts: List<QuotaAccount>): QuotaAccount? = when (route) {
    AppRoute.All -> accounts.firstOrNull { it.isEnabled } ?: accounts.firstOrNull()
    is AppRoute.Account -> accounts.firstOrNull { it.id == route.id }
}

sealed interface QuickViewSelection {
    data object All : QuickViewSelection
    data object Default : QuickViewSelection
    data class Account(val id: String) : QuickViewSelection

    fun resolve(defaultAccountId: String?, accounts: List<QuotaAccount>): AppRoute = when (this) {
        All -> AppRoute.All
        Default -> defaultAccountId?.let { AppRoute.resolve(AppRoute.Account(it), accounts) } ?: AppRoute.All
        is Account -> AppRoute.resolve(AppRoute.Account(id), accounts)
    }

    fun storageValue(): String = when (this) {
        All -> "all"
        Default -> "default"
        is Account -> "account:$id"
    }

    companion object {
        fun fromStorage(raw: String?): QuickViewSelection = when {
            raw == "all" -> All
            raw == "default" || raw == null -> Default
            raw.startsWith("account:") -> Account(raw.removePrefix("account:"))
            else -> Default
        }
    }
}

enum class DashboardStatus { Empty, Healthy, BelowThreshold, Partial, Stale, Unavailable }

data class DashboardState(
    val status: DashboardStatus,
    val aggregate: AggregateSnapshot,
    val route: AppRoute,
)

object DashboardPresenter {
    fun present(
        accounts: List<QuotaAccount>,
        snapshots: List<AccountSnapshot>,
        now: Instant,
        requestedRoute: AppRoute,
    ): DashboardState {
        val route = AppRoute.resolve(requestedRoute, accounts)
        val selectedAccounts = when (route) {
            AppRoute.All -> accounts
            is AppRoute.Account -> accounts.filter { it.id == route.id }
        }
        if (selectedAccounts.none { it.isEnabled }) {
            return DashboardState(DashboardStatus.Empty, AggregateSnapshot(), route)
        }
        val aggregate = SnapshotAggregator().aggregate(selectedAccounts, snapshots, now)
        val selected = aggregate.accounts
        val status = when {
            selected.isEmpty() -> DashboardStatus.Empty
            selected.all { it.health is AccountHealth.Unavailable } -> DashboardStatus.Unavailable
            selected.any { it.health is AccountHealth.Stale } -> DashboardStatus.Partial
            aggregate.isPartial -> DashboardStatus.Partial
            selected.any { it.health is AccountHealth.BelowThreshold } -> DashboardStatus.BelowThreshold
            else -> DashboardStatus.Healthy
        }
        return DashboardState(status, aggregate, route)
    }
}
