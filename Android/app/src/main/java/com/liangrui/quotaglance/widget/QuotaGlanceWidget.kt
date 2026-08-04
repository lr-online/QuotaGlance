package com.liangrui.quotaglance.widget

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.provideContent
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box as GlanceBox
import androidx.glance.layout.Column as GlanceColumn
import androidx.glance.layout.fillMaxSize as glanceFillMaxSize
import androidx.glance.layout.fillMaxWidth as glanceFillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding as glancePadding
import androidx.glance.layout.Row as GlanceRow
import androidx.glance.layout.width
import androidx.glance.text.Text as GlanceText
import androidx.glance.text.TextStyle
import androidx.glance.text.FontWeight as GlanceFontWeight
import androidx.glance.unit.ColorProvider
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.lifecycleScope
import com.liangrui.quotaglance.core.Money
import com.liangrui.quotaglance.MainActivity
import com.liangrui.quotaglance.data.AppPreferences
import com.liangrui.quotaglance.data.AppThemeMode
import com.liangrui.quotaglance.data.WidgetSelectionStore
import com.liangrui.quotaglance.refresh.QuotaGlanceApplication
import com.liangrui.quotaglance.ui.AppCopy
import com.liangrui.quotaglance.ui.AppRoute
import com.liangrui.quotaglance.ui.DashboardPresenter
import com.liangrui.quotaglance.ui.DashboardStatus
import com.liangrui.quotaglance.ui.QuickViewSelection
import com.liangrui.quotaglance.ui.QuotaGlanceTheme
import com.liangrui.quotaglance.ui.appCopy
import java.time.Instant
import java.math.BigDecimal
import java.math.RoundingMode
import kotlinx.coroutines.launch

class QuotaGlanceWidget : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val app = context.applicationContext as QuotaGlanceApplication
        val widgetId = GlanceAppWidgetManager(context).getAppWidgetId(id)
        val selection = WidgetSelectionStore(context).read(widgetId)
        val accounts = app.container.accounts.list()
        val preferences = app.container.preferences.current()
        val copy = appCopy(preferences.language)
        val state = DashboardPresenter.present(
            accounts = accounts,
            snapshots = app.container.snapshots.all(),
            now = Instant.now(),
            requestedRoute = selection.resolve(preferences.defaultQuickViewAccountId, accounts),
        )
        val routeIntent = Intent(context, MainActivity::class.java).setData(Uri.parse(routeUri(state.route)))
        val systemDark = (context.resources.configuration.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK) == android.content.res.Configuration.UI_MODE_NIGHT_YES
        val palette = widgetPalette(preferences, systemDark)
        val daily = state.aggregate.dailyUsage.takeLast(7)
        val maxDaily = daily.maxOfOrNull { it.actualCost.value } ?: BigDecimal.ZERO
        provideContent {
            GlanceColumn(
                modifier = GlanceModifier.glanceFillMaxSize()
                    .background(ColorProvider(palette.background))
                    .glancePadding(14.dp)
                    .clickable(actionStartActivity(routeIntent)),
                verticalAlignment = Alignment.Vertical.Top,
            ) {
                GlanceRow(modifier = GlanceModifier.glanceFillMaxWidth()) {
                    GlanceColumn(modifier = GlanceModifier.width(112.dp)) {
                        GlanceText(
                            "QuotaGlance",
                            style = TextStyle(color = ColorProvider(palette.primary), fontSize = 13.sp, fontWeight = GlanceFontWeight.Bold),
                        )
                        GlanceText(
                            widgetTitle(state.route, state.aggregate.accounts.firstOrNull()?.displayName, copy),
                            style = TextStyle(color = ColorProvider(palette.secondary), fontSize = 11.sp),
                        )
                    }
                    GlanceText(
                        widgetStatus(state.status, copy),
                        style = TextStyle(color = ColorProvider(palette.primary), fontSize = 10.sp),
                    )
                }
                GlanceText(
                    state.aggregate.balances.joinToString("  ") { formatMoney(it) }.ifBlank { copy.noBalance },
                    style = TextStyle(color = ColorProvider(palette.primary), fontSize = 22.sp, fontWeight = GlanceFontWeight.Bold),
                    modifier = GlanceModifier.glanceFillMaxWidth().glancePadding(top = 8.dp),
                )
                GlanceRow(
                    modifier = GlanceModifier.glanceFillMaxWidth().glancePadding(top = 8.dp),
                    verticalAlignment = Alignment.Vertical.CenterVertically,
                ) {
                    WidgetMetric(
                        label = copy.today,
                        value = state.aggregate.todayActualCost?.let(::formatMoney) ?: "-",
                        palette = palette,
                    )
                    WidgetMetric(
                        label = copy.requests,
                        value = state.aggregate.todayRequests?.let(::formatCount) ?: "-",
                        palette = palette,
                    )
                }
                if (daily.isNotEmpty()) {
                    GlanceRow(
                        modifier = GlanceModifier.glanceFillMaxWidth().glancePadding(top = 10.dp),
                        verticalAlignment = Alignment.Vertical.Bottom,
                    ) {
                        daily.forEach { entry ->
                            val ratio = if (maxDaily.signum() > 0) entry.actualCost.value.divide(maxDaily, 4, RoundingMode.HALF_UP).toFloat() else 0f
                            GlanceBox(
                                modifier = GlanceModifier.width(14.dp).height((8f + 34f * ratio.coerceIn(0f, 1f)).dp)
                                    .background(ColorProvider(palette.primary)),
                            ) {}
                        }
                    }
                }
                val footer = listOfNotNull(
                    state.aggregate.dailyUsage.lastOrNull()?.date,
                    if (state.aggregate.isPartial) copy.staleData else null,
                ).joinToString("  ")
                if (footer.isNotBlank()) {
                    GlanceText(footer, style = TextStyle(color = ColorProvider(palette.secondary), fontSize = 9.sp), modifier = GlanceModifier.glancePadding(top = 6.dp))
                }
            }
        }
    }

    companion object {
        suspend fun refreshAll(context: Context) {
            val manager = GlanceAppWidgetManager(context)
            manager.getGlanceIds(QuotaGlanceWidget::class.java).forEach { id ->
                QuotaGlanceWidget().update(context, id)
            }
        }
    }
}

class QuotaGlanceWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = QuotaGlanceWidget()
}

class QuotaGlanceWidgetConfigurationActivity : ComponentActivity() {
    private var widgetId: Int = AppWidgetManager.INVALID_APPWIDGET_ID

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        widgetId = intent?.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
            ?: AppWidgetManager.INVALID_APPWIDGET_ID
        setResult(RESULT_CANCELED)
        if (widgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            finish()
            return
        }
        val app = application as QuotaGlanceApplication
        setContent {
            val accounts by app.container.accounts.accounts.collectAsStateWithLifecycle(emptyList())
            val preferences by app.container.preferences.preferences.collectAsStateWithLifecycle(AppPreferences())
            val copy = appCopy(preferences.language)
            QuotaGlanceTheme(themeMode = preferences.themeMode) {
                Column(
                    modifier = Modifier.fillMaxSize().padding(24.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Text(copy.widget)
                    Button(onClick = { finishWith(QuickViewSelection.All) }) { Text(copy.allAccounts) }
                    Button(onClick = { finishWith(QuickViewSelection.Default) }) { Text(copy.useAppDefault) }
                    accounts.forEach { account ->
                        Button(onClick = { finishWith(QuickViewSelection.Account(account.id)) }) { Text(account.displayName) }
                    }
                }
            }
        }
    }

    private fun finishWith(selection: QuickViewSelection) {
        lifecycleScope.launch {
            WidgetSelectionStore(this@QuotaGlanceWidgetConfigurationActivity).write(widgetId, selection)
            QuotaGlanceWidget.refreshAll(this@QuotaGlanceWidgetConfigurationActivity)
            setResult(RESULT_OK, Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId))
            finish()
        }
    }
}

private data class WidgetPalette(val background: androidx.compose.ui.graphics.Color, val primary: androidx.compose.ui.graphics.Color, val secondary: androidx.compose.ui.graphics.Color, val tile: androidx.compose.ui.graphics.Color)

private fun widgetPalette(preferences: AppPreferences, systemDark: Boolean): WidgetPalette = when {
    preferences.themeMode == AppThemeMode.Dark || (preferences.themeMode == AppThemeMode.System && systemDark) -> WidgetPalette(
        background = androidx.compose.ui.graphics.Color(0xFF111816),
        primary = androidx.compose.ui.graphics.Color(0xFF9AE4D4),
        secondary = androidx.compose.ui.graphics.Color(0xFFB8C9C3),
        tile = androidx.compose.ui.graphics.Color(0xFF24312D),
    )
    else -> WidgetPalette(
        background = androidx.compose.ui.graphics.Color(0xFFF7FAF8),
        primary = androidx.compose.ui.graphics.Color(0xFF176B5F),
        secondary = androidx.compose.ui.graphics.Color(0xFF5B6B65),
        tile = androidx.compose.ui.graphics.Color(0xFFE7F1ED),
    )
}

@Composable
private fun WidgetMetric(label: String, value: String, palette: WidgetPalette) {
    GlanceColumn(
        modifier = GlanceModifier.width(76.dp).background(ColorProvider(palette.tile)).glancePadding(8.dp),
    ) {
        GlanceText(label, style = TextStyle(color = ColorProvider(palette.secondary), fontSize = 9.sp))
        GlanceText(value, style = TextStyle(color = ColorProvider(palette.primary), fontSize = 12.sp, fontWeight = GlanceFontWeight.Bold))
    }
}

private fun formatMoney(money: Money): String = "${formatDecimal(money.value)} ${money.currency}"

private fun formatDecimal(value: BigDecimal): String = value.setScale(2, RoundingMode.HALF_UP).stripTrailingZeros().toPlainString()

private fun formatCount(value: Long): String = java.text.NumberFormat.getIntegerInstance().format(value)
private fun widgetTitle(route: AppRoute, name: String?, copy: AppCopy): String =
    if (route is AppRoute.Account) name ?: copy.account else copy.allAccounts
private fun routeUri(route: AppRoute): String = when (route) {
    AppRoute.All -> "quotaglance://all"
    is AppRoute.Account -> "quotaglance://account/${route.id}"
}
private fun widgetStatus(status: DashboardStatus, copy: AppCopy): String = copy.status(status)
