package com.liangrui.quotaglance.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.AccountBalance
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ArrowForward
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Code
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Language
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.ManageAccounts
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.Palette
import androidx.compose.material.icons.filled.Public
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.filled.Cloud
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.ScrollableTabRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Tab
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.liangrui.quotaglance.core.AccountHealth
import com.liangrui.quotaglance.core.AccountSnapshot
import com.liangrui.quotaglance.core.DailyUsage
import com.liangrui.quotaglance.core.Money
import com.liangrui.quotaglance.core.ModelUsage
import com.liangrui.quotaglance.core.ProviderId
import com.liangrui.quotaglance.core.QuotaAccount
import com.liangrui.quotaglance.core.UsageCounters
import com.liangrui.quotaglance.core.OpenAIServiceStatus
import com.liangrui.quotaglance.core.ServiceStatusLevel
import com.liangrui.quotaglance.data.AppLanguage
import com.liangrui.quotaglance.data.AppPreferences
import com.liangrui.quotaglance.data.AppThemeMode
import com.liangrui.quotaglance.data.RefreshInterval
import java.time.Instant
import java.math.BigDecimal
import java.math.RoundingMode
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun QuotaGlanceApp(
    viewModel: QuotaGlanceViewModel,
    notificationsGranted: Boolean,
    requestNotificationPermission: () -> Unit,
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val copy = appCopy(state.preferences.language)
    val dashboard = DashboardPresenter.present(state.accounts, state.snapshots, Instant.now(), state.route)
    val summaries = ProviderOverviewPresenter.present(state.accounts, state.snapshots)
    var overflowMenu by remember { mutableStateOf(false) }

    QuotaGlanceTheme(themeMode = state.preferences.themeMode) {
        Scaffold(
            containerColor = MaterialTheme.colorScheme.background,
            topBar = {
                TopAppBar(
                    title = {
                        Text(
                            if (state.section == AppSection.Overview) "QuotaGlance" else copy.section(state.section),
                            style = MaterialTheme.typography.titleLarge,
                        )
                    },
                    navigationIcon = {
                        if (state.section != AppSection.Overview) {
                            IconButton(onClick = { viewModel.setSection(AppSection.Overview) }) {
                                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = copy.back)
                            }
                        }
                    },
                    actions = {
                        if (state.section == AppSection.Overview) {
                            IconButton(onClick = viewModel::refreshAll, enabled = !state.refreshing) {
                                Icon(
                                    Icons.Default.Refresh,
                                    contentDescription = if (state.refreshing) copy.refreshing else copy.refresh,
                                )
                            }
                            IconButton(onClick = { viewModel.setSection(AppSection.Accounts) }) {
                                Icon(Icons.Default.ManageAccounts, contentDescription = copy.accounts)
                            }
                        }
                        Box {
                            IconButton(onClick = { overflowMenu = true }) {
                                Icon(Icons.Default.MoreVert, contentDescription = copy.more)
                            }
                            DropdownMenu(expanded = overflowMenu, onDismissRequest = { overflowMenu = false }) {
                                DropdownMenuItem(
                                    text = { Text(copy.settings) },
                                    leadingIcon = { Icon(Icons.Default.Settings, contentDescription = null) },
                                    onClick = {
                                        viewModel.setSection(AppSection.Settings)
                                        overflowMenu = false
                                    },
                                )
                                DropdownMenuItem(
                                    text = { Text(copy.themeTitle) },
                                    leadingIcon = { Icon(Icons.Default.Palette, contentDescription = null) },
                                    onClick = { overflowMenu = false },
                                )
                                AppThemeMode.entries.forEach { mode ->
                                    DropdownMenuItem(
                                        text = { Text("${copy.theme(mode)}${if (state.preferences.themeMode == mode) "  •" else ""}") },
                                        onClick = {
                                            viewModel.updatePreferences(state.preferences.copy(themeMode = mode))
                                            overflowMenu = false
                                        },
                                    )
                                }
                                DropdownMenuItem(
                                    text = { Text(copy.languageTitle) },
                                    leadingIcon = { Icon(Icons.Default.Language, contentDescription = null) },
                                    onClick = { overflowMenu = false },
                                )
                                AppLanguage.entries.forEach { language ->
                                    DropdownMenuItem(
                                        text = { Text("${copy.language(language)}${if (state.preferences.language == language) "  •" else ""}") },
                                        onClick = {
                                            viewModel.updatePreferences(state.preferences.copy(language = language))
                                            overflowMenu = false
                                        },
                                    )
                                }
                            }
                        }
                    },
                    colors = TopAppBarDefaults.topAppBarColors(
                        containerColor = MaterialTheme.colorScheme.background,
                        scrolledContainerColor = MaterialTheme.colorScheme.background,
                    ),
                )
            },
        ) { padding ->
            Column(modifier = Modifier.fillMaxSize().padding(padding)) {
                state.message?.let { message ->
                    ErrorBanner(message, copy, viewModel::clearMessage)
                }
                when (state.section) {
                    AppSection.Overview -> OverviewScreen(state, dashboard, summaries, copy, viewModel)
                    AppSection.Accounts -> AccountsScreen(state, copy, viewModel)
                    AppSection.Settings -> SettingsScreen(state, copy, viewModel, notificationsGranted, requestNotificationPermission)
                }
            }
        }
    }
}

@Composable
private fun ErrorBanner(message: String, copy: AppCopy, onDismiss: () -> Unit) {
    Surface(color = MaterialTheme.colorScheme.errorContainer, modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier.padding(horizontal = 20.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Icons.Default.Error, contentDescription = null, tint = MaterialTheme.colorScheme.onErrorContainer)
            Spacer(Modifier.width(10.dp))
            Text(
                localizedError(message, copy),
                color = MaterialTheme.colorScheme.onErrorContainer,
                style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.weight(1f),
            )
            TextButton(onClick = onDismiss) { Text(copy.dismiss) }
        }
    }
}

@Composable
private fun OverviewScreen(
    state: QuotaGlanceUiState,
    dashboard: DashboardState,
    summaries: List<ProviderOverview>,
    copy: AppCopy,
    viewModel: QuotaGlanceViewModel,
) {
    if (state.accounts.isEmpty()) {
        EmptyOverview(copy, viewModel)
        return
    }

    val selectedAccount = selectedAccountForRoute(state.route, state.accounts)
    val selectedIndex = selectedAccount?.let { account -> state.accounts.indexOfFirst { it.id == account.id } } ?: 0

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(start = 16.dp, top = 12.dp, end = 16.dp, bottom = 32.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        state.serviceStatus?.let { status -> item { ServiceStatusBanner(status) } }
        item { OverviewHero(dashboard, copy) }
        if (dashboard.aggregate.dailyUsage.isNotEmpty()) {
            item { DailyUsageSection(dashboard, copy) }
        }
        item {
            SectionHeading(copy.providers, copy.providerSummary(summaries.size))
        }
        items(summaries, key = { it.provider.raw }) { summary ->
            ProviderOverviewRow(summary, copy)
        }
        item {
            SectionHeading(copy.accounts, copy.accountSummary(state.accounts.size))
            Spacer(Modifier.height(8.dp))
            AccountTabs(state.accounts, selectedIndex, viewModel)
        }
        item {
            selectedAccount?.let { account ->
                val snapshot = state.snapshots.firstOrNull { it.accountId == account.id }
                AccountDetail(snapshot, account, copy)
            }
        }
    }
}

@Composable
private fun ServiceStatusBanner(status: OpenAIServiceStatus) {
    val color = when (status.overall) {
        ServiceStatusLevel.Operational -> Color(0xFF1B7F5A)
        ServiceStatusLevel.Degraded -> Color(0xFFB7791F)
        ServiceStatusLevel.Outage -> MaterialTheme.colorScheme.error
        else -> MaterialTheme.colorScheme.onSurfaceVariant
    }
    Surface(color = color.copy(alpha = 0.12f), modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(horizontal = 14.dp, vertical = 10.dp)) {
            Text("OpenAI service status", color = color, fontWeight = FontWeight.Medium)
            Text(status.summary ?: "Official status is temporarily unavailable", color = color, style = MaterialTheme.typography.bodySmall)
            if (status.affectedComponents.isNotEmpty()) Text(
                "Affected: " + status.affectedComponents.joinToString(", ") { it.name },
                color = color, style = MaterialTheme.typography.labelSmall,
            )
        }
    }
}

@Composable
private fun EmptyOverview(copy: AppCopy, viewModel: QuotaGlanceViewModel) {
    Column(
        modifier = Modifier.fillMaxSize().padding(horizontal = 32.dp, vertical = 48.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Surface(
            color = MaterialTheme.colorScheme.primaryContainer,
            shape = CircleShape,
            modifier = Modifier.size(72.dp),
        ) {
            Box(contentAlignment = Alignment.Center) {
                Icon(Icons.Default.AccountBalance, contentDescription = null, tint = MaterialTheme.colorScheme.onPrimaryContainer, modifier = Modifier.size(32.dp))
            }
        }
        Spacer(Modifier.height(22.dp))
        Text(copy.emptyTitle, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.SemiBold)
        Spacer(Modifier.height(8.dp))
        Text(copy.emptyOverview, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.height(24.dp))
        Button(onClick = { viewModel.setSection(AppSection.Accounts) }) {
            Icon(Icons.Default.Add, contentDescription = null)
            Spacer(Modifier.width(8.dp))
            Text(copy.addAccount)
        }
    }
}

@Composable
private fun OverviewHero(dashboard: DashboardState, copy: AppCopy) {
    Surface(
        color = MaterialTheme.colorScheme.primaryContainer,
        shape = MaterialTheme.shapes.extraLarge,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(modifier = Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(copy.availableBalance, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.72f))
                    Spacer(Modifier.height(4.dp))
                    if (dashboard.aggregate.balances.isEmpty()) {
                        Text(
                            if (dashboard.status == DashboardStatus.Empty) copy.emptyOverview else copy.noBalance,
                            style = MaterialTheme.typography.titleLarge,
                            color = MaterialTheme.colorScheme.onPrimaryContainer,
                        )
                    } else {
                        dashboard.aggregate.balances.forEach { balance ->
                            Text(
                                formatMoney(balance),
                                style = MaterialTheme.typography.headlineMedium,
                                color = MaterialTheme.colorScheme.onPrimaryContainer,
                                fontWeight = FontWeight.SemiBold,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                            )
                        }
                    }
                }
                StatusBadge(dashboard.status, copy)
            }
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                MetricTile(copy.today, dashboard.aggregate.todayActualCost?.let(::formatMoney) ?: "-", Modifier.weight(1f))
                MetricTile(copy.requests, dashboard.aggregate.todayRequests?.let(::formatCount) ?: "-", Modifier.weight(1f))
            }
        }
    }
}

@Composable
private fun MetricTile(label: String, value: String, modifier: Modifier = Modifier) {
    Surface(
        modifier = modifier,
        color = MaterialTheme.colorScheme.surface.copy(alpha = 0.74f),
        shape = MaterialTheme.shapes.small,
    ) {
        Column(modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp)) {
            Text(label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.height(2.dp))
            Text(value, style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.onSurface, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

@Composable
private fun SectionHeading(title: String, supporting: String? = null) {
    Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.Bottom) {
        Text(title, style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f))
        supporting?.let { Text(it, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant) }
    }
}

@Composable
private fun ProviderOverviewRow(summary: ProviderOverview, copy: AppCopy) {
    val balance = summary.balances.firstOrNull()?.let(::formatMoney)
    val stateLabel = when {
        summary.isStale -> copy.staleData
        !summary.hasData -> copy.notRefreshed
        else -> copy.status(DashboardStatus.Healthy)
    }
    Surface(
        modifier = Modifier.fillMaxWidth(),
        color = MaterialTheme.colorScheme.surfaceContainerLow,
        shape = MaterialTheme.shapes.medium,
    ) {
        Column(modifier = Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                ProviderGlyph(summary.provider)
                Spacer(Modifier.width(12.dp))
                Column(modifier = Modifier.weight(1f)) {
                    Text(summary.displayName, style = MaterialTheme.typography.titleMedium)
                    Text(
                        copy.accountSummary(summary.enabledAccountCount),
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Column(horizontalAlignment = Alignment.End) {
                    Text(balance ?: copy.noBalance, style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(stateLabel, style = MaterialTheme.typography.labelSmall, color = if (summary.isStale) MaterialTheme.colorScheme.tertiary else MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(20.dp)) {
                summary.todayRequests?.let { Text("${copy.requests}  ${formatCount(it)}", style = MaterialTheme.typography.bodySmall) }
                summary.todayCosts.firstOrNull()?.let { Text("${copy.today}  ${formatMoney(it)}", style = MaterialTheme.typography.bodySmall) }
                summary.quotaWindows.firstOrNull()?.let { window ->
                    Text("${copy.remaining}  ${window.remaining?.let(::formatQuantity) ?: "-"} ${window.unit}", style = MaterialTheme.typography.bodySmall)
                }
            }
            if (summary.requestFraction > 0.0) {
                LinearProgressIndicator(
                    progress = { summary.requestFraction.toFloat().coerceIn(0f, 1f) },
                    modifier = Modifier.fillMaxWidth().height(4.dp),
                    color = MaterialTheme.colorScheme.primary,
                    trackColor = MaterialTheme.colorScheme.surfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun ProviderGlyph(provider: ProviderId) {
    val icon = when (provider) {
        ProviderId.API_INFO -> Icons.Default.Cloud
        ProviderId.DEEP_SEEK -> Icons.Default.Public
        ProviderId.KIMI -> Icons.Default.AccountBalance
        ProviderId.OPEN_ROUTER -> Icons.AutoMirrored.Filled.ArrowForward
        ProviderId.MINI_MAX -> Icons.Default.Code
        ProviderId.BIO_MAP_CODING -> Icons.Default.Settings
    }
    Surface(color = MaterialTheme.colorScheme.surfaceVariant, shape = CircleShape, modifier = Modifier.size(40.dp)) {
        Box(contentAlignment = Alignment.Center) {
            Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(20.dp))
        }
    }
}

@Composable
private fun AccountTabs(accounts: List<QuotaAccount>, selectedIndex: Int, viewModel: QuotaGlanceViewModel) {
    ScrollableTabRow(selectedTabIndex = selectedIndex.coerceIn(0, accounts.lastIndex), edgePadding = 0.dp, divider = {}) {
        accounts.forEachIndexed { index, account ->
            Tab(
                selected = index == selectedIndex,
                onClick = { viewModel.routeTo(AppRoute.Account(account.id)) },
                text = {
                    Text(
                        account.displayName,
                        color = if (account.isEnabled) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                },
            )
        }
    }
}

@Composable
private fun StatusBadge(status: DashboardStatus, copy: AppCopy) {
    val (container, content) = when (status) {
        DashboardStatus.Healthy -> MaterialTheme.colorScheme.primary to MaterialTheme.colorScheme.onPrimary
        DashboardStatus.BelowThreshold -> MaterialTheme.colorScheme.tertiaryContainer to MaterialTheme.colorScheme.onTertiaryContainer
        DashboardStatus.Partial, DashboardStatus.Stale -> MaterialTheme.colorScheme.secondaryContainer to MaterialTheme.colorScheme.onSecondaryContainer
        DashboardStatus.Unavailable -> MaterialTheme.colorScheme.errorContainer to MaterialTheme.colorScheme.onErrorContainer
        DashboardStatus.Empty -> MaterialTheme.colorScheme.surfaceVariant to MaterialTheme.colorScheme.onSurfaceVariant
    }
    Surface(color = container, shape = CircleShape) {
        Text(copy.status(status), modifier = Modifier.padding(horizontal = 11.dp, vertical = 6.dp), color = content, style = MaterialTheme.typography.labelMedium)
    }
}

@Composable
private fun AccountDetail(snapshot: AccountSnapshot?, account: QuotaAccount, copy: AppCopy) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        color = MaterialTheme.colorScheme.surface,
        shape = MaterialTheme.shapes.extraLarge,
    ) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(account.displayName, style = MaterialTheme.typography.titleLarge)
                    Text(copy.providerName(account.provider), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                snapshot?.let { HealthBadge(it.health, copy) }
            }
            if (snapshot == null) {
                InlineEmpty(copy.notRefreshed, copy.notRefreshedDetail)
                return@Column
            }
            when (val health = snapshot.health) {
                is AccountHealth.Stale -> InlineState(Icons.Default.Warning, copy.staleData, localizedError(health.reason, copy), MaterialTheme.colorScheme.tertiary)
                is AccountHealth.Unavailable -> InlineState(Icons.Default.Error, copy.status(DashboardStatus.Unavailable), localizedError(health.reason, copy), MaterialTheme.colorScheme.error)
                AccountHealth.Healthy, AccountHealth.BelowThreshold -> Unit
            }
            snapshot.detectedProfile?.let { profile ->
                DetailLine(copy.profile, profileDescription(profile, copy))
            }
            snapshot.usage?.let { usage ->
                usage.balances.forEach { balance ->
                    BalanceSummary(balance, copy)
                }
                usage.spendingLimit?.let { limit ->
                    SpendingLimitSummary(limit, copy)
                }
                SpendSummary(usage, copy)
                if (usage.quotaWindows.isNotEmpty()) {
                    QuotaWindowsSummary(usage.quotaWindows, copy)
                }
                usage.today?.let { CountersSummary(copy.today, it, copy) }
                usage.total?.let { CountersSummary(copy.total, it, copy) }
                if (usage.dailyUsage.isNotEmpty()) {
                    DailyUsageChart(usage.dailyUsage, copy)
                    DailyRequestSummary(usage.dailyUsage, copy)
                }
                if (usage.modelUsage.isNotEmpty()) {
                    ModelUsageSummary(usage.modelUsage, copy)
                }
                usage.providerStatus?.let { DetailLine(copy.providerStatus, it) }
                usage.apiInfoDetails?.let { ApiInfoDetailsSummary(it, copy) }
                usage.metricsUnavailableReason?.let { DetailLine(copy.metricsUnavailable, it) }
                DetailLine(copy.lastUpdated, formatUpdatedAt(usage.receivedAtMillis))
            }
        }
    }
}

@Composable
private fun BalanceSummary(balance: com.liangrui.quotaglance.core.MonetaryBalance, copy: AppCopy) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        DetailSectionTitle(balance.label)
        Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.Bottom) {
            Text(copy.availableBalance, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.weight(1f))
            Text(formatMoney(balance.available), style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.SemiBold)
        }
        balance.breakdown.forEach { entry ->
            DetailLine(entry.label, formatMoney(entry.value))
        }
    }
}

@Composable
private fun SpendingLimitSummary(limit: com.liangrui.quotaglance.core.SpendingLimit, copy: AppCopy) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        DetailSectionTitle(limit.label)
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            SpendTile(copy.remaining, limit.remaining?.let(::formatMoney) ?: "-", Modifier.weight(1f), emphasize = true)
            SpendTile(copy.limit, limit.limit?.let(::formatMoney) ?: "-", Modifier.weight(1f))
        }
        limit.used?.let { DetailLine(copy.used, formatMoney(it)) }
        limit.resetDescription?.let { DetailLine(copy.reset, it) }
    }
}

@Composable
private fun SpendSummary(usage: com.liangrui.quotaglance.core.ProviderUsageSnapshot, copy: AppCopy) {
    val values = listOfNotNull(
        copy.today to usage.spend.today?.let(::formatMoney),
        copy.week to usage.spend.week?.let(::formatMoney),
        copy.month to usage.spend.month?.let(::formatMoney),
        copy.total to usage.spend.total?.let(::formatMoney),
    )
    if (values.isEmpty()) return
    DetailSectionTitle(copy.spend)
    values.chunked(2).forEach { row ->
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            row.forEach { (label, value) -> SpendTile(label, value ?: "-", Modifier.weight(1f)) }
            if (row.size == 1) Spacer(Modifier.weight(1f))
        }
    }
}

@Composable
private fun QuotaWindowsSummary(windows: List<com.liangrui.quotaglance.core.QuotaWindow>, copy: AppCopy) {
    DetailSectionTitle(copy.remaining)
    windows.forEach { window ->
        val remaining = window.remaining?.let(::formatQuantity) ?: "-"
        val limit = window.limit
        val used = limit?.let { maxLimit ->
            window.used ?: window.remaining?.let { maxLimit.subtract(it) }
        }
        val fraction = if (limit != null && limit.signum() > 0 && used != null) {
            used.divide(limit, 4, RoundingMode.HALF_UP).toFloat().coerceIn(0f, 1f)
        } else null
        Column(verticalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.fillMaxWidth()) {
            Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.Bottom) {
                Text(window.label, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
                Text("$remaining ${window.unit}", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            }
            if (limit != null && fraction != null) {
                LinearProgressIndicator(
                    progress = { fraction },
                    modifier = Modifier.fillMaxWidth().height(6.dp),
                    color = MaterialTheme.colorScheme.primary,
                    trackColor = MaterialTheme.colorScheme.surfaceVariant,
                )
            }
            if (limit != null) {
                Text("${copy.limit}: ${formatQuantity(limit)} ${window.unit}", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            window.resetsAtMillis?.let { Text("${copy.resetsAt}: ${formatUpdatedAt(it)}", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
        }
    }
}

@Composable
private fun CountersSummary(title: String, counters: UsageCounters, copy: AppCopy) {
    val fields = listOfNotNull(
        counters.actualCost?.let { copy.cost to formatMoney(it) },
        counters.requests?.let { copy.requests to formatCount(it) },
        counters.totalTokens?.let { copy.totalTokens to formatCount(it) },
        counters.inputTokens?.let { copy.inputTokens to formatCount(it) },
        counters.outputTokens?.let { copy.outputTokens to formatCount(it) },
        counters.cacheReadTokens?.let { copy.cacheReadTokens to formatCount(it) },
        counters.cacheCreationTokens?.let { copy.cacheCreationTokens to formatCount(it) },
    )
    if (fields.isEmpty()) return
    DetailSectionTitle(title)
    fields.chunked(3).forEach { row ->
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            row.forEach { (label, value) -> SpendTile(label, value, Modifier.weight(1f)) }
            repeat(3 - row.size) { Spacer(Modifier.weight(1f)) }
        }
    }
}

@Composable
private fun ModelUsageSummary(models: List<ModelUsage>, copy: AppCopy) {
    DetailSectionTitle(copy.models)
    models.forEachIndexed { index, model ->
        Row(modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(model.model, style = MaterialTheme.typography.bodyMedium, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
            model.actualCost?.let { Text(formatMoney(it), style = MaterialTheme.typography.bodySmall, fontWeight = FontWeight.SemiBold) }
            model.requests?.let { Text(formatCount(it), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(start = 10.dp)) }
            model.totalTokens?.let { Text("${formatCount(it)} ${copy.totalTokens}", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(start = 10.dp)) }
        }
        if (index < models.lastIndex) HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.6f))
    }
}

@Composable
private fun DailyRequestSummary(entries: List<DailyUsage>, copy: AppCopy) {
    val days = entries.takeLast(7).filter { it.requests != null || it.totalTokens != null }
    if (days.isEmpty()) return
    DetailSectionTitle(copy.dailyRequestDetails)
    days.reversed().forEach { day ->
        DetailLine(
            day.date,
            listOfNotNull(
                day.requests?.let { "${formatCount(it)} ${copy.requests}" },
                day.totalTokens?.let { "${formatCount(it)} ${copy.totalTokens}" },
            ).joinToString(" · "),
        )
    }
}

@Composable
private fun ApiInfoDetailsSummary(details: com.liangrui.quotaglance.core.ApiInfoDetails, copy: AppCopy) {
    DetailSectionTitle(copy.apiInfoAccount)
    details.planName?.let { DetailLine(copy.planName, it) }
    details.mode?.let { DetailLine(copy.billingMode, it) }
    details.status?.let { DetailLine(copy.keyStatus, it) }
    details.reportedBalance?.let { DetailLine(copy.reportedBalance, formatMoney(it)) }
    details.isValid?.let { DetailLine(copy.credentialStatus, if (it) copy.valid else copy.invalid) }
    details.expiresAtMillis?.let { DetailLine(copy.expiresAt, formatUpdatedAt(it)) }
    details.daysUntilExpiry?.let { DetailLine(copy.daysUntilExpiry, "$it") }
}

@Composable
private fun DailyUsageChart(entries: List<DailyUsage>, copy: AppCopy) {
    val points = entries.takeLast(7)
    if (points.isEmpty()) return
    val maxValue = points.maxOfOrNull { it.actualCost.value } ?: BigDecimal.ZERO
    val total = points.fold(BigDecimal.ZERO) { sum, entry -> sum.add(entry.actualCost.value) }
    Surface(
        modifier = Modifier.fillMaxWidth(),
        color = MaterialTheme.colorScheme.surfaceContainerLow,
        shape = MaterialTheme.shapes.medium,
    ) {
        Column(modifier = Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.Bottom) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(copy.recentUsage, style = MaterialTheme.typography.titleSmall)
                    Text(copy.lastSevenDays, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                Text(formatMoney(Money.fromNumber(total, points.first().actualCost.currency)), style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
            }
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.Bottom) {
                points.forEach { entry ->
                    val ratio = if (maxValue.signum() > 0) entry.actualCost.value.divide(maxValue, 4, RoundingMode.HALF_UP).toFloat() else 0f
                    val barHeight = (8f + 56f * ratio.coerceIn(0f, 1f)).dp
                    Column(modifier = Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
                        Box(modifier = Modifier.fillMaxWidth().height(64.dp), contentAlignment = Alignment.BottomCenter) {
                            Box(
                                modifier = Modifier.width(18.dp).height(barHeight)
                                    .background(MaterialTheme.colorScheme.primary, RoundedCornerShape(6.dp)),
                            )
                        }
                        Text(entry.date.takeLast(2), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
    }
}

private fun formatUpdatedAt(millis: Long): String {
    val date = java.time.ZonedDateTime.ofInstant(Instant.ofEpochMilli(millis), java.time.ZoneId.systemDefault())
    return "${date.monthValue.toString().padStart(2, '0')}-${date.dayOfMonth.toString().padStart(2, '0')} " +
        "${date.hour.toString().padStart(2, '0')}:${date.minute.toString().padStart(2, '0')}"
}

@Composable
private fun HealthBadge(health: AccountHealth, copy: AppCopy) {
    val (icon, tint) = when (health) {
        AccountHealth.Healthy -> Icons.Default.CheckCircle to MaterialTheme.colorScheme.primary
        AccountHealth.BelowThreshold -> Icons.Default.Warning to MaterialTheme.colorScheme.tertiary
        is AccountHealth.Stale -> Icons.Default.Warning to MaterialTheme.colorScheme.tertiary
        is AccountHealth.Unavailable -> Icons.Default.Error to MaterialTheme.colorScheme.error
    }
    Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(18.dp))
        Spacer(Modifier.width(5.dp))
        Text(copy.health(health), style = MaterialTheme.typography.labelMedium, color = tint)
    }
}

@Composable
private fun InlineState(icon: ImageVector, title: String, detail: String, tint: Color) {
    Surface(color = tint.copy(alpha = 0.12f), shape = MaterialTheme.shapes.small, modifier = Modifier.fillMaxWidth()) {
        Row(modifier = Modifier.padding(12.dp), verticalAlignment = Alignment.Top) {
            Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(8.dp))
            Column {
                Text(title, style = MaterialTheme.typography.labelLarge, color = tint)
                Text(detail, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@Composable
private fun InlineEmpty(title: String, detail: String) {
    Surface(color = MaterialTheme.colorScheme.surfaceContainerLow, shape = MaterialTheme.shapes.small, modifier = Modifier.fillMaxWidth()) {
        Row(modifier = Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Default.CalendarMonth, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.width(10.dp))
            Column {
                Text(title, style = MaterialTheme.typography.titleSmall)
                Text(detail, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@Composable
private fun DetailSectionTitle(title: String) {
    Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
        HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
        Text(title, style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun DetailLine(label: String, value: String, emphasized: Boolean = false) {
    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
        Text(label, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.weight(1f))
        Text(value, style = if (emphasized) MaterialTheme.typography.titleMedium else MaterialTheme.typography.bodyMedium, fontWeight = if (emphasized) FontWeight.SemiBold else FontWeight.Normal, modifier = Modifier.padding(start = 16.dp))
    }
}

@Composable
private fun SpendTile(label: String, value: String, modifier: Modifier, emphasize: Boolean = false) {
    Surface(modifier = modifier, color = MaterialTheme.colorScheme.surfaceContainerLow, shape = MaterialTheme.shapes.small) {
        Column(modifier = Modifier.padding(11.dp)) {
            Text(label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.height(3.dp))
            Text(
                value,
                style = if (emphasize) MaterialTheme.typography.titleMedium else MaterialTheme.typography.titleSmall,
                fontWeight = if (emphasize) FontWeight.SemiBold else FontWeight.Medium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

@Composable
private fun CountersDetail(title: String, counters: UsageCounters, copy: AppCopy) {
    val fields = listOfNotNull(
        counters.actualCost?.let { "${copy.cost}: ${formatMoney(it)}" },
        counters.requests?.let { "${copy.requests}: $it" },
        counters.inputTokens?.let { "${copy.inputTokens}: $it" },
        counters.outputTokens?.let { "${copy.outputTokens}: $it" },
        counters.cacheReadTokens?.let { "${copy.cacheReadTokens}: $it" },
        counters.cacheCreationTokens?.let { "${copy.cacheCreationTokens}: $it" },
        counters.totalTokens?.let { "${copy.totalTokens}: $it" },
    )
    if (fields.isNotEmpty()) {
        DetailSectionTitle(title)
        fields.forEach { field -> Text(field, style = MaterialTheme.typography.bodySmall) }
    }
}

@Composable
private fun DailyUsageSection(dashboard: DashboardState, copy: AppCopy) {
    DailyUsageChart(dashboard.aggregate.dailyUsage, copy)
}

@Composable
private fun AccountsScreen(state: QuotaGlanceUiState, copy: AppCopy, viewModel: QuotaGlanceViewModel) {
    var editing by rememberSaveable { mutableStateOf<String?>(null) }
    var editorVisible by rememberSaveable { mutableStateOf(false) }
    var name by rememberSaveable { mutableStateOf("") }
    var apiKey by rememberSaveable { mutableStateOf("") }
    var provider by rememberSaveable { mutableStateOf(ProviderId.API_INFO) }
    var threshold by rememberSaveable { mutableStateOf("") }
    var enabled by rememberSaveable { mutableStateOf(true) }
    var providerMenu by remember { mutableStateOf(false) }
    val originalAccount = state.accounts.firstOrNull { it.id == editing }
    val originalProvider = originalAccount?.provider
    val selectedProfile = originalAccount?.detectedProfile?.takeIf { originalProvider == provider }
    val supportsLowBalanceThreshold = viewModel.supportsLowBalanceThreshold(provider, selectedProfile)

    fun load(account: QuotaAccount?) {
        editing = account?.id
        name = account?.displayName.orEmpty()
        apiKey = ""
        provider = account?.provider ?: ProviderId.API_INFO
        threshold = account?.lowBalanceThreshold?.toPlainString().orEmpty()
        enabled = account?.isEnabled ?: true
    }

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(20.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        item {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(copy.accountManagement, style = MaterialTheme.typography.headlineSmall)
                Text(copy.accountManagementDetail, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        item {
            if (!editorVisible) {
                Button(onClick = { editorVisible = true; load(null) }, modifier = Modifier.fillMaxWidth()) {
                    Icon(Icons.Default.Add, contentDescription = null)
                    Spacer(Modifier.width(8.dp))
                    Text(copy.addAccount)
                }
            }
        }
        item {
            if (editorVisible) {
                Surface(
                    color = MaterialTheme.colorScheme.surface,
                    shape = MaterialTheme.shapes.large,
                    modifier = Modifier.fillMaxWidth().border(BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant), MaterialTheme.shapes.large),
                ) {
                    Column(modifier = Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Text(if (editing == null) copy.addAccount else copy.editAccount, style = MaterialTheme.typography.titleLarge)
                        OutlinedTextField(value = name, onValueChange = { name = it }, label = { Text(copy.accountName) }, modifier = Modifier.fillMaxWidth(), singleLine = true)
                        OutlinedTextField(
                            value = apiKey,
                            onValueChange = { apiKey = it },
                            label = {
                                Text(
                                    when {
                                        editing == null -> copy.apiKey
                                        originalProvider != null && originalProvider != provider -> copy.replaceKeyRequired
                                        else -> copy.replaceKey
                                    },
                                )
                            },
                            leadingIcon = { Icon(Icons.Default.Lock, contentDescription = null) },
                            modifier = Modifier.fillMaxWidth(),
                            singleLine = true,
                            visualTransformation = PasswordVisualTransformation(),
                        )
                        Box {
                            OutlinedButton(onClick = { providerMenu = true }, modifier = Modifier.fillMaxWidth()) {
                                Text("${copy.provider}: ${copy.providerName(provider)}", modifier = Modifier.weight(1f))
                                Icon(Icons.Default.ExpandMore, contentDescription = null)
                            }
                            DropdownMenu(expanded = providerMenu, onDismissRequest = { providerMenu = false }) {
                                ProviderId.entries.forEach { id ->
                                    DropdownMenuItem(text = { Text(copy.providerName(id)) }, onClick = { provider = id; providerMenu = false })
                                }
                            }
                        }
                        if (supportsLowBalanceThreshold) {
                            OutlinedTextField(value = threshold, onValueChange = { threshold = it }, label = { Text(copy.lowBalanceThreshold) }, modifier = Modifier.fillMaxWidth(), singleLine = true)
                        }
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Column(modifier = Modifier.weight(1f)) {
                                Text(copy.enabled, style = MaterialTheme.typography.titleSmall)
                                Text(copy.enabledDetail, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                            Switch(checked = enabled, onCheckedChange = { enabled = it })
                        }
                        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            Button(
                                onClick = {
                                    viewModel.saveAccount(editing, name, provider, apiKey, enabled, threshold)
                                    if (editing == null) {
                                        editorVisible = false
                                        load(null)
                                    }
                                },
                                modifier = Modifier.weight(1f),
                            ) { Text(copy.save) }
                            OutlinedButton(onClick = { editorVisible = false; load(null) }, modifier = Modifier.weight(1f)) { Text(copy.cancel) }
                        }
                    }
                }
            }
        }
        item { SectionHeading(copy.accounts, copy.accountSummary(state.accounts.size)) }
        if (state.accounts.isEmpty()) {
            item { InlineEmpty(copy.noAccountsYet, copy.emptyOverview) }
        }
        items(state.accounts.sortedBy { it.sortOrder }, key = { it.id }) { account ->
            AccountManagementRow(
                account = account,
                copy = copy,
                onEnabledChange = { viewModel.setEnabled(account, it) },
                onEdit = { editorVisible = true; load(account) },
                onDelete = {
                    viewModel.deleteAccount(account.id)
                    if (editing == account.id) {
                        editorVisible = false
                        load(null)
                    }
                },
            )
        }
    }
}

@Composable
private fun AccountManagementRow(
    account: QuotaAccount,
    copy: AppCopy,
    onEnabledChange: (Boolean) -> Unit,
    onEdit: () -> Unit,
    onDelete: () -> Unit,
) {
    Surface(
        color = if (account.isEnabled) MaterialTheme.colorScheme.surface else MaterialTheme.colorScheme.surfaceContainerLow,
        shape = MaterialTheme.shapes.medium,
        modifier = Modifier.fillMaxWidth().border(BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant), MaterialTheme.shapes.medium),
    ) {
        Row(modifier = Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
            ProviderGlyph(account.provider)
            Spacer(Modifier.width(12.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(account.displayName, style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(copy.providerName(account.provider), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Switch(checked = account.isEnabled, onCheckedChange = onEnabledChange)
            IconButton(onClick = onEdit) { Icon(Icons.Default.Edit, contentDescription = copy.edit) }
            IconButton(onClick = onDelete) { Icon(Icons.Default.Delete, contentDescription = copy.delete, tint = MaterialTheme.colorScheme.error) }
        }
    }
}

@Composable
private fun SettingsScreen(
    state: QuotaGlanceUiState,
    copy: AppCopy,
    viewModel: QuotaGlanceViewModel,
    notificationsGranted: Boolean,
    requestNotificationPermission: () -> Unit,
) {
    var defaultMenu by remember { mutableStateOf(false) }
    Column(
        modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(copy.settings, style = MaterialTheme.typography.headlineSmall)
            Text(copy.settingsDetail, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        SettingsGroup(copy.refreshInterval, Icons.Default.Refresh) {
            ChoiceChips(RefreshInterval.entries.map { "${it.minutes}m" }, RefreshInterval.entries.indexOf(state.preferences.refreshInterval)) { index ->
                viewModel.updatePreferences(state.preferences.copy(refreshInterval = RefreshInterval.entries[index]))
            }
            Text(copy.backgroundScheduling, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        SettingsGroup(copy.themeTitle, Icons.Default.Palette) {
            ChoiceChips(AppThemeMode.entries.map { copy.theme(it) }, AppThemeMode.entries.indexOf(state.preferences.themeMode)) { index ->
                viewModel.updatePreferences(state.preferences.copy(themeMode = AppThemeMode.entries[index]))
            }
        }
        SettingsGroup(copy.languageTitle, Icons.Default.Language) {
            ChoiceChips(AppLanguage.entries.map { copy.language(it) }, AppLanguage.entries.indexOf(state.preferences.language)) { index ->
                viewModel.updatePreferences(state.preferences.copy(language = AppLanguage.entries[index]))
            }
        }
        SettingsGroup(copy.defaultQuickView, Icons.Default.ManageAccounts) {
            Box {
                OutlinedButton(onClick = { defaultMenu = true }, modifier = Modifier.fillMaxWidth()) {
                    Text(state.accounts.firstOrNull { it.id == state.preferences.defaultQuickViewAccountId }?.displayName ?: copy.allAccounts, modifier = Modifier.weight(1f))
                    Icon(Icons.Default.ExpandMore, contentDescription = null)
                }
                DropdownMenu(expanded = defaultMenu, onDismissRequest = { defaultMenu = false }) {
                    DropdownMenuItem(text = { Text(copy.allAccounts) }, onClick = {
                        viewModel.updatePreferences(state.preferences.copy(defaultQuickViewAccountId = null)); defaultMenu = false
                    })
                    state.accounts.forEach { account ->
                        DropdownMenuItem(text = { Text(account.displayName) }, onClick = {
                            viewModel.updatePreferences(state.preferences.copy(defaultQuickViewAccountId = account.id)); defaultMenu = false
                        })
                    }
                }
            }
        }
        SettingsGroup(copy.notificationsTitle, Icons.Default.Notifications) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(if (notificationsGranted) copy.notificationsEnabled else copy.notificationsNeeded, style = MaterialTheme.typography.titleSmall)
                    Text(copy.notificationsDetail, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                if (!notificationsGranted) {
                    OutlinedButton(onClick = requestNotificationPermission) { Text(copy.enableNotifications) }
                } else {
                    Icon(Icons.Default.CheckCircle, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                }
            }
        }
    }
}

@Composable
private fun SettingsGroup(title: String, icon: ImageVector, content: @Composable () -> Unit) {
    Surface(
        color = MaterialTheme.colorScheme.surface,
        shape = MaterialTheme.shapes.large,
        modifier = Modifier.fillMaxWidth().border(BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant), MaterialTheme.shapes.large),
    ) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(20.dp))
                Spacer(Modifier.width(10.dp))
                Text(title, style = MaterialTheme.typography.titleMedium)
            }
            content()
        }
    }
}

@Composable
private fun ChoiceChips(labels: List<String>, selectedIndex: Int, onSelected: (Int) -> Unit) {
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        labels.forEachIndexed { index, label ->
            FilterChip(selected = index == selectedIndex, onClick = { onSelected(index) }, label = { Text(label) })
        }
    }
}

private fun formatMoney(money: Money): String = "${formatDecimal(money.value)} ${money.currency}"

private fun formatQuantity(value: BigDecimal): String = formatDecimal(value)

private fun formatDecimal(value: BigDecimal): String = value
    .setScale(2, RoundingMode.HALF_UP)
    .stripTrailingZeros()
    .toPlainString()

private fun formatCount(value: Long): String = java.text.NumberFormat
    .getIntegerInstance(Locale.getDefault())
    .format(value)

internal data class AppCopy(val preferredLanguage: AppLanguage) {
    val chinese get() = preferredLanguage == AppLanguage.Chinese
    val refresh get() = if (chinese) "刷新" else "Refresh"
    val refreshing get() = if (chinese) "刷新中" else "Refreshing"
    val dismiss get() = if (chinese) "关闭" else "Dismiss"
    val more get() = if (chinese) "更多" else "More"
    val accounts get() = if (chinese) "账户" else "Accounts"
    val providers get() = if (chinese) "服务商" else "Providers"
    val liveOverview get() = if (chinese) "实时用量概览" else "Live usage overview"
    val availableBalance get() = if (chinese) "可用余额" else "Available balance"
    val staleData get() = if (chinese) "数据可能已过期" else "Data may be stale"
    val back get() = if (chinese) "返回" else "Back"
    val today get() = if (chinese) "今日" else "Today"
    val requests get() = if (chinese) "请求数" else "Requests"
    val recentUsage get() = if (chinese) "最近 7 天" else "Last 7 days"
    val lastSevenDays get() = if (chinese) "按天查看" else "Daily"
    val emptyTitle get() = if (chinese) "先添加一个账户" else "Add your first account"
    val emptyOverview get() = if (chinese) "添加账户以查看 API 余额和配额。" else "Add an account to view API balances and quotas."
    val noBalance get() = if (chinese) "暂无可用余额" else "No available balance"
    val notRefreshed get() = if (chinese) "尚未刷新" else "Not refreshed"
    val notRefreshedDetail get() = if (chinese) "保存账户后刷新即可看到数据。" else "Refresh after saving the account to see its data."
    val details get() = if (chinese) "账户详情" else "Account details"
    val profile get() = if (chinese) "配置" else "Profile"
    val providerStatus get() = if (chinese) "服务状态" else "Provider status"
    val breakdown get() = if (chinese) "明细" else "Breakdown"
    val remaining get() = if (chinese) "剩余" else "Remaining"
    val used get() = if (chinese) "已用" else "Used"
    val limit get() = if (chinese) "上限" else "Limit"
    val spend get() = if (chinese) "花费" else "Spend"
    val reset get() = if (chinese) "重置" else "Reset"
    val resetsAt get() = if (chinese) "重置时间" else "Resets at"
    val lastUpdated get() = if (chinese) "最后更新" else "Last updated"
    val metricsUnavailable get() = if (chinese) "指标不可用" else "Metrics unavailable"
    val models get() = if (chinese) "模型用量" else "Model usage"
    val cost get() = if (chinese) "花费" else "Cost"
    val inputTokens get() = if (chinese) "输入 token" else "Input tokens"
    val outputTokens get() = if (chinese) "输出 token" else "Output tokens"
    val cacheReadTokens get() = if (chinese) "缓存读取 token" else "Cache-read tokens"
    val cacheCreationTokens get() = if (chinese) "缓存创建 token" else "Cache-creation tokens"
    val totalTokens get() = if (chinese) "总 token" else "Total tokens"
    val dailyRequestDetails get() = if (chinese) "每日请求明细" else "Daily request details"
    val apiInfoAccount get() = if (chinese) "API Info 账户信息" else "API Info account"
    val planName get() = if (chinese) "计划" else "Plan"
    val billingMode get() = if (chinese) "计费模式" else "Billing mode"
    val keyStatus get() = if (chinese) "Key 状态" else "Key status"
    val reportedBalance get() = if (chinese) "账户余额" else "Reported balance"
    val credentialStatus get() = if (chinese) "凭证状态" else "Credential status"
    val expiresAt get() = if (chinese) "到期时间" else "Expires at"
    val daysUntilExpiry get() = if (chinese) "剩余天数" else "Days remaining"
    val valid get() = if (chinese) "有效" else "Valid"
    val invalid get() = if (chinese) "无效" else "Invalid"
    val account get() = if (chinese) "账户" else "Account"
    val widget get() = if (chinese) "QuotaGlance 小组件" else "QuotaGlance widget"
    val useAppDefault get() = if (chinese) "使用应用默认值" else "Use app default"
    val week get() = if (chinese) "本周" else "Week"
    val month get() = if (chinese) "本月" else "Month"
    val total get() = if (chinese) "累计" else "Total"
    val addAccount get() = if (chinese) "添加账户" else "Add account"
    val editAccount get() = if (chinese) "编辑账户" else "Edit account"
    val accountManagement get() = if (chinese) "账户管理" else "Account management"
    val accountManagementDetail get() = if (chinese) "凭据保存在设备安全存储中。" else "Credentials stay in the device secure store."
    val noAccountsYet get() = if (chinese) "还没有账户" else "No accounts yet"
    val accountName get() = if (chinese) "账户名称" else "Account name"
    val apiKey get() = "API key"
    val replaceKey get() = if (chinese) "替换 API key（留空保持不变）" else "Replace API key (leave blank to keep)"
    val replaceKeyRequired get() = if (chinese) "切换服务商时必须替换 API key" else "Replacement API key is required when changing provider"
    val provider get() = if (chinese) "服务商" else "Provider"
    val lowBalanceThreshold get() = if (chinese) "低余额阈值" else "Low-balance threshold"
    val enabled get() = if (chinese) "启用账户" else "Enabled account"
    val enabledDetail get() = if (chinese) "停用后不会参与汇总或刷新。" else "Disabled accounts are excluded from refresh and totals."
    val save get() = if (chinese) "保存" else "Save"
    val cancel get() = if (chinese) "取消" else "Cancel"
    val edit get() = if (chinese) "编辑" else "Edit"
    val delete get() = if (chinese) "删除" else "Delete"
    val settings get() = if (chinese) "设置" else "Settings"
    val settingsDetail get() = if (chinese) "调整显示、刷新与快速查看行为。" else "Tune display, refresh, and quick-view behavior."
    val themeTitle get() = if (chinese) "主题" else "Theme"
    val refreshInterval get() = if (chinese) "刷新间隔" else "Refresh interval"
    val languageTitle get() = if (chinese) "语言" else "Language"
    val defaultQuickView get() = if (chinese) "默认快速查看" else "Default quick view"
    val allAccounts get() = if (chinese) "全部账户" else "All accounts"
    val choose get() = if (chinese) "选择" else "Choose"
    val notificationsTitle get() = if (chinese) "通知" else "Notifications"
    val enableNotifications get() = if (chinese) "允许" else "Allow"
    val notificationsEnabled get() = if (chinese) "低余额通知已允许" else "Low-balance notifications are allowed"
    val notificationsNeeded get() = if (chinese) "尚未允许低余额通知" else "Low-balance notifications are not allowed"
    val notificationsDetail get() = if (chinese) "仅在账户进入低余额状态时提醒。" else "Alerts are sent only when an account enters low balance."
    val backgroundScheduling get() = if (chinese) "后台刷新由 Android 系统调度，最短周期为 15 分钟。" else "Android schedules background refreshes; the shortest periodic interval is 15 minutes."

    fun providerSummary(count: Int): String = if (chinese) "$count 个服务商" else "$count providers"
    fun accountSummary(count: Int): String = if (chinese) "$count 个账户" else "$count accounts"
    fun section(section: AppSection): String = when (section) {
        AppSection.Overview -> if (chinese) "概览" else "Overview"
        AppSection.Accounts -> accounts
        AppSection.Settings -> settings
    }
    fun language(value: AppLanguage): String = when (value) {
        AppLanguage.System -> if (chinese) "跟随系统" else "System"
        AppLanguage.English -> "English"
        AppLanguage.Chinese -> "简体中文"
    }
    fun theme(value: AppThemeMode): String = when (value) {
        AppThemeMode.System -> if (chinese) "跟随系统" else "System"
        AppThemeMode.Light -> if (chinese) "浅色" else "Light"
        AppThemeMode.Dark -> if (chinese) "深色" else "Dark"
    }
    fun providerName(value: ProviderId): String = when (value) {
        ProviderId.API_INFO -> "API Info"
        ProviderId.DEEP_SEEK -> "DeepSeek"
        ProviderId.KIMI -> "Kimi"
        ProviderId.OPEN_ROUTER -> "OpenRouter"
        ProviderId.MINI_MAX -> "MiniMax"
        ProviderId.BIO_MAP_CODING -> "BioMap Coding"
    }
    fun status(status: DashboardStatus): String = when (status) {
        DashboardStatus.Empty -> if (chinese) "未配置" else "Not configured"
        DashboardStatus.Healthy -> if (chinese) "正常" else "Healthy"
        DashboardStatus.BelowThreshold -> if (chinese) "余额偏低" else "Low balance"
        DashboardStatus.Partial, DashboardStatus.Stale -> if (chinese) "数据过期" else "Stale data"
        DashboardStatus.Unavailable -> if (chinese) "不可用" else "Unavailable"
    }
    fun health(health: AccountHealth): String = when (health) {
        AccountHealth.Healthy -> status(DashboardStatus.Healthy)
        AccountHealth.BelowThreshold -> status(DashboardStatus.BelowThreshold)
        is AccountHealth.Stale -> status(DashboardStatus.Stale)
        is AccountHealth.Unavailable -> status(DashboardStatus.Unavailable)
    }
}

internal fun appCopy(language: AppLanguage): AppCopy = AppCopy(
    if (language == AppLanguage.System && Locale.getDefault().language.startsWith("zh", ignoreCase = true)) AppLanguage.Chinese else language,
)

private fun localizedError(message: String, copy: AppCopy): String = when {
    message == "EmptyDisplayName" -> if (copy.chinese) "请输入账户名称。" else "Enter an account name."
    message == "DuplicateDisplayName" -> if (copy.chinese) "账户名称已存在。" else "An account with this name already exists."
    message == "EmptyApiKey" -> if (copy.chinese) "请输入 API key。" else "Enter an API key."
    message == "InvalidThreshold" -> if (copy.chinese) "请输入有效的非负阈值。" else "Enter a valid non-negative threshold."
    message == "unauthorized" || message == "invalidCredential" -> if (copy.chinese) "API key 无效或没有访问权限。" else "The API key is invalid or is not authorized."
    message == "rateLimited" -> if (copy.chinese) "服务商当前限制了请求。" else "The provider is currently rate-limiting requests."
    message == "offline" || message == "network" || message.startsWith("network:") -> if (copy.chinese) "无法连接到服务商，请检查网络后重试。" else "Unable to connect to the provider. Check your network and try again."
    message.startsWith("httpStatus:") -> if (copy.chinese) "服务商返回 HTTP ${message.removePrefix("httpStatus:") }。" else "The provider returned HTTP ${message.removePrefix("httpStatus:") }."
    message == "AccountLimit" -> if (copy.chinese) "最多支持 20 个账户。" else "A maximum of 20 accounts is supported."
    else -> message
}

private fun profileDescription(profile: com.liangrui.quotaglance.core.ProviderProfile, copy: AppCopy): String {
    val region = when (profile.region) {
        com.liangrui.quotaglance.core.ProviderRegion.GLOBAL -> if (copy.chinese) "全球" else "Global"
        com.liangrui.quotaglance.core.ProviderRegion.CHINA -> if (copy.chinese) "中国" else "China"
        com.liangrui.quotaglance.core.ProviderRegion.INTERNATIONAL -> if (copy.chinese) "国际" else "International"
    }
    val credential = when (profile.credentialKind) {
        com.liangrui.quotaglance.core.CredentialKind.STANDARD -> if (copy.chinese) "标准 key" else "Standard key"
        com.liangrui.quotaglance.core.CredentialKind.MANAGEMENT -> if (copy.chinese) "管理 key" else "Management key"
        com.liangrui.quotaglance.core.CredentialKind.TOKEN_PLAN -> if (copy.chinese) "套餐 key" else "Token-plan key"
    }
    return "$region - $credential"
}
