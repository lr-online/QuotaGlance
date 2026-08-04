package com.liangrui.quotaglance.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Language
import androidx.compose.material.icons.filled.ManageAccounts
import androidx.compose.material.icons.filled.Palette
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
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
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.liangrui.quotaglance.core.AccountHealth
import com.liangrui.quotaglance.core.AccountSnapshot
import com.liangrui.quotaglance.core.Money
import com.liangrui.quotaglance.core.ProviderId
import com.liangrui.quotaglance.core.QuotaAccount
import com.liangrui.quotaglance.core.UsageCounters
import com.liangrui.quotaglance.data.AppLanguage
import com.liangrui.quotaglance.data.AppPreferences
import com.liangrui.quotaglance.data.AppThemeMode
import com.liangrui.quotaglance.data.RefreshInterval
import java.time.Instant
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
    var themeMenu by remember { mutableStateOf(false) }
    var languageMenu by remember { mutableStateOf(false) }
    QuotaGlanceTheme(themeMode = state.preferences.themeMode) {
        Scaffold(
            topBar = {
                TopAppBar(
                    title = { Text(if (state.section == AppSection.Overview) "QuotaGlance" else copy.section(state.section)) },
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
                                Icon(Icons.Default.Refresh, contentDescription = if (state.refreshing) copy.refreshing else copy.refresh)
                            }
                            ToolbarMenu(
                                expanded = themeMenu,
                                onExpandedChange = { themeMenu = it },
                                icon = { Icon(Icons.Default.Palette, contentDescription = copy.themeTitle) },
                            ) {
                                AppThemeMode.entries.forEach { mode ->
                                    DropdownMenuItem(text = { Text(copy.theme(mode)) }, onClick = {
                                        viewModel.updatePreferences(state.preferences.copy(themeMode = mode))
                                        themeMenu = false
                                    })
                                }
                            }
                            ToolbarMenu(
                                expanded = languageMenu,
                                onExpandedChange = { languageMenu = it },
                                icon = { Icon(Icons.Default.Language, contentDescription = copy.languageTitle) },
                            ) {
                                AppLanguage.entries.forEach { language ->
                                    DropdownMenuItem(text = { Text(copy.language(language)) }, onClick = {
                                        viewModel.updatePreferences(state.preferences.copy(language = language))
                                        languageMenu = false
                                    })
                                }
                            }
                            IconButton(onClick = { viewModel.setSection(AppSection.Accounts) }) {
                                Icon(Icons.Default.ManageAccounts, contentDescription = copy.accounts)
                            }
                            IconButton(onClick = { viewModel.setSection(AppSection.Settings) }) {
                                Icon(Icons.Default.Settings, contentDescription = copy.settings)
                            }
                        }
                    },
                )
            },
        ) { padding ->
            Column(
                modifier = Modifier.fillMaxSize().padding(padding),
            ) {
                state.message?.let { message ->
                    Surface(color = MaterialTheme.colorScheme.errorContainer, modifier = Modifier.fillMaxWidth()) {
                        Row(modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                            Text(localizedError(message, copy), color = MaterialTheme.colorScheme.onErrorContainer, modifier = Modifier.weight(1f))
                            TextButton(onClick = viewModel::clearMessage) { Text(copy.dismiss) }
                        }
                    }
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
private fun ToolbarMenu(
    expanded: Boolean,
    onExpandedChange: (Boolean) -> Unit,
    icon: @Composable () -> Unit,
    content: @Composable () -> Unit,
) {
    androidx.compose.foundation.layout.Box {
        IconButton(onClick = { onExpandedChange(true) }) { icon() }
        DropdownMenu(expanded = expanded, onDismissRequest = { onExpandedChange(false) }) { content() }
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
        Column(
            modifier = Modifier.fillMaxSize().padding(32.dp),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            StatusChip(DashboardStatus.Empty, copy)
            Spacer(Modifier.height(12.dp))
            Text(copy.emptyOverview, style = MaterialTheme.typography.bodyLarge)
            Spacer(Modifier.height(16.dp))
            Button(onClick = { viewModel.setSection(AppSection.Accounts) }) { Text(copy.addAccount) }
        }
        return
    }
    val selectedAccount = selectedAccountForRoute(state.route, state.accounts)
    val selectedIndex = selectedAccount?.let { account -> state.accounts.indexOfFirst { it.id == account.id } } ?: 0
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                StatusChip(dashboard.status, copy)
                if (dashboard.aggregate.balances.isEmpty()) {
                    Text(if (dashboard.status == DashboardStatus.Empty) copy.emptyOverview else copy.noBalance, style = MaterialTheme.typography.bodyLarge)
                } else {
                    dashboard.aggregate.balances.forEach { Text(formatMoney(it), style = MaterialTheme.typography.headlineMedium) }
                }
                dashboard.aggregate.todayActualCost?.let { Text("${copy.today}: ${formatMoney(it)}") }
                dashboard.aggregate.todayRequests?.let { Text("${copy.requests}: $it") }
            }
        }
        item {
            Text(copy.providers, style = MaterialTheme.typography.titleMedium)
        }
        items(summaries, key = { it.provider.raw }) { summary ->
            ProviderOverviewRow(summary, copy)
        }
        item {
            ScrollableTabRow(selectedTabIndex = selectedIndex.coerceIn(0, state.accounts.lastIndex)) {
                state.accounts.forEachIndexed { index, account ->
                    Tab(
                        selected = index == selectedIndex,
                        onClick = { viewModel.routeTo(AppRoute.Account(account.id)) },
                        text = {
                            Text(
                                account.displayName,
                                color = if (account.isEnabled) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        },
                    )
                }
            }
        }
        item {
            selectedAccount?.let { account ->
                val snapshot = state.snapshots.firstOrNull { it.accountId == account.id }
                AccountDetail(snapshot, account, copy)
            }
        }
        if (dashboard.aggregate.dailyUsage.isNotEmpty()) {
            item {
                Text(copy.recentUsage, style = MaterialTheme.typography.titleMedium)
                HorizontalDivider(modifier = Modifier.padding(top = 6.dp))
            }
            items(dashboard.aggregate.dailyUsage) { entry ->
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text(entry.date)
                    Text(formatMoney(entry.actualCost))
                }
            }
        }
    }
}

@Composable
private fun ProviderOverviewRow(summary: ProviderOverview, copy: AppCopy) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow),
    ) {
        Column(modifier = Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(5.dp)) {
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text(summary.displayName, style = MaterialTheme.typography.titleMedium)
                Text("${summary.enabledAccountCount} ${copy.accounts.lowercase()}", style = MaterialTheme.typography.labelMedium)
            }
            if (summary.balances.isEmpty()) {
                Text(copy.noBalance, style = MaterialTheme.typography.bodyMedium)
            } else {
                summary.balances.forEach { Text(formatMoney(it), style = MaterialTheme.typography.bodyLarge) }
            }
            if (summary.todayCosts.isNotEmpty()) {
                Text("${copy.today}: ${summary.todayCosts.joinToString { formatMoney(it) }}", style = MaterialTheme.typography.bodySmall)
            }
            summary.todayRequests?.let { requests ->
                Text("${copy.requests}: $requests (${(summary.requestFraction * 100).toInt()}%)", style = MaterialTheme.typography.bodySmall)
            }
            summary.quotaWindows.firstOrNull()?.let { window ->
                Text("${window.label}: ${window.remaining?.toPlainString() ?: "-"}/${window.limit?.toPlainString() ?: "-"} ${window.unit}", style = MaterialTheme.typography.bodySmall)
            }
            if (!summary.hasData) Text(copy.notRefreshed, style = MaterialTheme.typography.bodySmall)
            if (summary.isStale) Text(copy.staleData, color = MaterialTheme.colorScheme.tertiary, style = MaterialTheme.typography.bodySmall)
        }
    }
}

@Composable
private fun StatusChip(status: DashboardStatus, copy: AppCopy) {
    val color = when (status) {
        DashboardStatus.Healthy -> MaterialTheme.colorScheme.primaryContainer
        DashboardStatus.BelowThreshold -> MaterialTheme.colorScheme.tertiaryContainer
        DashboardStatus.Partial, DashboardStatus.Stale -> MaterialTheme.colorScheme.secondaryContainer
        DashboardStatus.Unavailable -> MaterialTheme.colorScheme.errorContainer
        DashboardStatus.Empty -> MaterialTheme.colorScheme.surfaceVariant
    }
    Surface(color = color, shape = MaterialTheme.shapes.small) {
        Text(copy.status(status), modifier = Modifier.padding(horizontal = 10.dp, vertical = 5.dp), style = MaterialTheme.typography.labelLarge)
    }
}

@Composable
private fun AccountDetail(snapshot: AccountSnapshot?, account: QuotaAccount, copy: AppCopy) {
    Column(modifier = Modifier.fillMaxWidth().padding(top = 8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(account.displayName, style = MaterialTheme.typography.titleMedium)
            Text(account.provider.raw, style = MaterialTheme.typography.labelMedium)
        }
        if (snapshot == null) {
            Text(copy.notRefreshed, style = MaterialTheme.typography.bodyMedium)
            return@Column
        }
        Text(copy.details, style = MaterialTheme.typography.titleMedium)
        Text(copy.health(snapshot.health), style = MaterialTheme.typography.bodySmall)
        snapshot.detectedProfile?.let { Text("${copy.profile}: ${profileDescription(it, copy)}") }
        snapshot.usage?.let { usage ->
            usage.providerStatus?.let { Text("${copy.providerStatus}: $it") }
            usage.balances.forEach { balance ->
                Text("${balance.label}: ${formatMoney(balance.available)}")
                balance.breakdown.forEach { entry ->
                    Text("${copy.breakdown} - ${entry.label}: ${formatMoney(entry.value)}", style = MaterialTheme.typography.bodySmall)
                }
            }
            usage.spendingLimit?.let { limit ->
                Text("${limit.label}: ${limit.used?.let(::formatMoney) ?: "-"} / ${limit.limit?.let(::formatMoney) ?: "-"}")
                limit.remaining?.let { Text("${copy.remaining}: ${formatMoney(it)}", style = MaterialTheme.typography.bodySmall) }
                limit.resetDescription?.let { Text("${copy.reset}: $it", style = MaterialTheme.typography.bodySmall) }
            }
            usage.spend.today?.let { Text("${copy.today}: ${formatMoney(it)}") }
            usage.spend.week?.let { Text("${copy.week}: ${formatMoney(it)}") }
            usage.spend.month?.let { Text("${copy.month}: ${formatMoney(it)}") }
            usage.spend.total?.let { Text("${copy.total}: ${formatMoney(it)}") }
            usage.quotaWindows.forEach { window ->
                Text("${window.label}: ${window.used?.toPlainString() ?: "-"}/${window.limit?.toPlainString() ?: "-"} ${window.unit}")
                window.remaining?.let { Text("${copy.remaining}: ${it.toPlainString()} ${window.unit}", style = MaterialTheme.typography.bodySmall) }
                window.resetsAtMillis?.let { Text("${copy.resetsAt}: ${Instant.ofEpochMilli(it)}", style = MaterialTheme.typography.bodySmall) }
            }
            usage.today?.let { CountersDetail(copy.today, it, copy) }
            usage.total?.let { CountersDetail(copy.total, it, copy) }
            if (usage.dailyUsage.isNotEmpty()) {
                Text(copy.recentUsage)
                usage.dailyUsage.forEach { entry ->
                    Text("${entry.date}: ${formatMoney(entry.actualCost)}${entry.requests?.let { " | ${copy.requests}: $it" }.orEmpty()}", style = MaterialTheme.typography.bodySmall)
                }
            }
            if (usage.modelUsage.isNotEmpty()) {
                Text(copy.models)
                usage.modelUsage.forEach { model ->
                    val fields = listOfNotNull(
                        model.actualCost?.let(::formatMoney),
                        model.requests?.let { "${copy.requests}: $it" },
                        model.totalTokens?.let { "${copy.totalTokens}: $it" },
                    )
                    Text("${model.model}: ${fields.joinToString(" | ")}", style = MaterialTheme.typography.bodySmall)
                }
            }
            usage.metricsUnavailableReason?.let { Text("${copy.metricsUnavailable}: $it", style = MaterialTheme.typography.bodySmall) }
            Text("${copy.lastUpdated}: ${Instant.ofEpochMilli(usage.receivedAtMillis)}", style = MaterialTheme.typography.bodySmall)
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
    if (fields.isNotEmpty()) Text("$title: ${fields.joinToString(" | ")}", style = MaterialTheme.typography.bodySmall)
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
        contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item {
            if (!editorVisible) {
                Button(onClick = { editorVisible = true; load(null) }) {
                    Text(copy.addAccount)
                }
            }
        }
        item {
            Text(copy.accounts, style = MaterialTheme.typography.titleMedium)
        }
        item {
            if (editorVisible) Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
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
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true,
                    visualTransformation = PasswordVisualTransformation(),
                )
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(copy.provider, modifier = Modifier.weight(1f))
                    TextButton(onClick = { providerMenu = true }) { Text(provider.raw) }
                    DropdownMenu(expanded = providerMenu, onDismissRequest = { providerMenu = false }) {
                        ProviderId.entries.forEach { id ->
                            DropdownMenuItem(text = { Text(id.raw) }, onClick = { provider = id; providerMenu = false })
                        }
                    }
                }
                if (supportsLowBalanceThreshold) {
                    OutlinedTextField(
                        value = threshold,
                        onValueChange = { threshold = it },
                        label = { Text(copy.lowBalanceThreshold) },
                        modifier = Modifier.fillMaxWidth(),
                        singleLine = true,
                    )
                }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(copy.enabled, modifier = Modifier.weight(1f))
                    Switch(checked = enabled, onCheckedChange = { enabled = it })
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(onClick = {
                        viewModel.saveAccount(editing, name, provider, apiKey, enabled, threshold)
                        if (editing == null) {
                            editorVisible = false
                            load(null)
                        }
                    }) { Text(copy.save) }
                    OutlinedButton(onClick = { editorVisible = false; load(null) }) { Text(copy.cancel) }
                }
            }
        }
        item { HorizontalDivider() }
        items(state.accounts.sortedBy { it.sortOrder }, key = { it.id }) { account ->
            Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(account.displayName, style = MaterialTheme.typography.titleMedium)
                    Text(account.provider.raw, style = MaterialTheme.typography.bodySmall)
                }
                Switch(checked = account.isEnabled, onCheckedChange = { viewModel.setEnabled(account, it) })
                TextButton(onClick = { editorVisible = true; load(account) }) { Text(copy.edit) }
                TextButton(onClick = {
                    viewModel.deleteAccount(account.id)
                    if (editing == account.id) {
                        editorVisible = false
                        load(null)
                    }
                }) { Text(copy.delete) }
            }
            HorizontalDivider()
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
        modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text(copy.settings, style = MaterialTheme.typography.titleLarge)
        Text(copy.refreshInterval, style = MaterialTheme.typography.titleMedium)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            RefreshInterval.entries.forEach { interval ->
                FilterChip(
                    selected = state.preferences.refreshInterval == interval,
                    onClick = { viewModel.updatePreferences(state.preferences.copy(refreshInterval = interval)) },
                    label = { Text("${interval.minutes}m") },
                )
            }
        }
        Text(copy.themeTitle, style = MaterialTheme.typography.titleMedium)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            AppThemeMode.entries.forEach { mode ->
                FilterChip(
                    selected = state.preferences.themeMode == mode,
                    onClick = { viewModel.updatePreferences(state.preferences.copy(themeMode = mode)) },
                    label = { Text(copy.theme(mode)) },
                )
            }
        }
        Text(copy.languageTitle, style = MaterialTheme.typography.titleMedium)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            AppLanguage.entries.forEach { language ->
                FilterChip(
                    selected = state.preferences.language == language,
                    onClick = { viewModel.updatePreferences(state.preferences.copy(language = language)) },
                    label = { Text(copy.language(language)) },
                )
            }
        }
        Text(copy.defaultQuickView, style = MaterialTheme.typography.titleMedium)
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(state.accounts.firstOrNull { it.id == state.preferences.defaultQuickViewAccountId }?.displayName ?: copy.allAccounts, modifier = Modifier.weight(1f))
            TextButton(onClick = { defaultMenu = true }) { Text(copy.choose) }
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
        Text(if (notificationsGranted) copy.notificationsEnabled else copy.notificationsNeeded, style = MaterialTheme.typography.bodyMedium)
        if (!notificationsGranted) OutlinedButton(onClick = requestNotificationPermission) { Text(copy.enableNotifications) }
        Text(copy.backgroundScheduling, style = MaterialTheme.typography.bodySmall)
    }
}

private fun formatMoney(money: Money): String = "${money.canonicalAmount} ${money.currency}"

internal data class AppCopy(val preferredLanguage: AppLanguage) {
    val chinese get() = preferredLanguage == AppLanguage.Chinese
    val refresh get() = if (chinese) "刷新" else "Refresh"
    val refreshing get() = if (chinese) "刷新中" else "Refreshing"
    val dismiss get() = if (chinese) "关闭" else "Dismiss"
    val accounts get() = if (chinese) "账户" else "Accounts"
    val providers get() = if (chinese) "服务商概览" else "Provider overview"
    val staleData get() = if (chinese) "数据可能已过期" else "Data may be stale"
    val back get() = if (chinese) "返回" else "Back"
    val today get() = if (chinese) "今日" else "Today"
    val requests get() = if (chinese) "请求数" else "Requests"
    val recentUsage get() = if (chinese) "最近 7 天" else "Last 7 days"
    val emptyOverview get() = if (chinese) "添加账户以查看 API 余额和配额。" else "Add an account to view API balances and quotas."
    val noBalance get() = if (chinese) "暂无可用余额" else "No available balance"
    val notRefreshed get() = if (chinese) "尚未刷新" else "Not refreshed"
    val details get() = if (chinese) "账户详情" else "Account details"
    val profile get() = if (chinese) "配置" else "Profile"
    val providerStatus get() = if (chinese) "服务状态" else "Provider status"
    val breakdown get() = if (chinese) "明细" else "Breakdown"
    val remaining get() = if (chinese) "剩余" else "Remaining"
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
    val account get() = if (chinese) "账户" else "Account"
    val widget get() = if (chinese) "QuotaGlance 小组件" else "QuotaGlance widget"
    val useAppDefault get() = if (chinese) "使用应用默认值" else "Use app default"
    val week get() = if (chinese) "本周" else "Week"
    val month get() = if (chinese) "本月" else "Month"
    val total get() = if (chinese) "累计" else "Total"
    val addAccount get() = if (chinese) "添加账户" else "Add account"
    val editAccount get() = if (chinese) "编辑账户" else "Edit account"
    val accountName get() = if (chinese) "账户名称" else "Account name"
    val apiKey get() = "API key"
    val replaceKey get() = if (chinese) "替换 API key（留空保持不变）" else "Replace API key (leave blank to keep)"
    val replaceKeyRequired get() = if (chinese) "切换服务商时必须替换 API key" else "Replacement API key is required when changing provider"
    val provider get() = if (chinese) "服务商" else "Provider"
    val lowBalanceThreshold get() = if (chinese) "低余额阈值" else "Low-balance threshold"
    val enabled get() = if (chinese) "启用" else "Enabled"
    val save get() = if (chinese) "保存" else "Save"
    val cancel get() = if (chinese) "取消" else "Cancel"
    val edit get() = if (chinese) "编辑" else "Edit"
    val delete get() = if (chinese) "删除" else "Delete"
    val settings get() = if (chinese) "设置" else "Settings"
    val themeTitle get() = if (chinese) "主题" else "Theme"
    val refreshInterval get() = if (chinese) "刷新间隔" else "Refresh interval"
    val languageTitle get() = if (chinese) "语言" else "Language"
    val defaultQuickView get() = if (chinese) "默认快速查看" else "Default quick view"
    val allAccounts get() = if (chinese) "全部账户" else "All accounts"
    val choose get() = if (chinese) "选择" else "Choose"
    val enableNotifications get() = if (chinese) "允许低余额通知" else "Allow low-balance notifications"
    val notificationsEnabled get() = if (chinese) "低余额通知已允许" else "Low-balance notifications are allowed"
    val notificationsNeeded get() = if (chinese) "尚未允许低余额通知" else "Low-balance notifications are not allowed"
    val backgroundScheduling get() = if (chinese) "后台刷新由 Android 系统调度，最短周期为 15 分钟。" else "Android schedules background refreshes; the shortest periodic interval is 15 minutes."

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

private fun localizedError(message: String, copy: AppCopy): String = when (message) {
    "EmptyDisplayName" -> if (copy.chinese) "请输入账户名称。" else "Enter an account name."
    "DuplicateDisplayName" -> if (copy.chinese) "账户名称已存在。" else "An account with this name already exists."
    "EmptyApiKey" -> if (copy.chinese) "请输入 API key。" else "Enter an API key."
    "InvalidThreshold" -> if (copy.chinese) "请输入有效的非负阈值。" else "Enter a valid non-negative threshold."
    "unauthorized", "invalidCredential" -> if (copy.chinese) "API key 无效或没有访问权限。" else "The API key is invalid or is not authorized."
    "rateLimited" -> if (copy.chinese) "服务商当前限制了请求。" else "The provider is currently rate-limiting requests."
    "offline", "network" -> if (copy.chinese) "无法连接到服务商。" else "Unable to connect to the provider."
    "AccountLimit" -> if (copy.chinese) "最多支持 20 个账户。" else "A maximum of 20 accounts is supported."
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
