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
import androidx.glance.layout.Column as GlanceColumn
import androidx.glance.layout.fillMaxSize as glanceFillMaxSize
import androidx.glance.layout.padding as glancePadding
import androidx.glance.text.Text as GlanceText
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.lifecycleScope
import com.liangrui.quotaglance.core.Money
import com.liangrui.quotaglance.MainActivity
import com.liangrui.quotaglance.data.AppPreferences
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
        provideContent {
            GlanceColumn(
                modifier = GlanceModifier.glanceFillMaxSize()
                    .background(ColorProvider(androidx.compose.ui.graphics.Color(0xFFF8FAFA)))
                    .glancePadding(12.dp)
                    .clickable(actionStartActivity(routeIntent)),
                verticalAlignment = Alignment.Vertical.CenterVertically,
            ) {
                GlanceText("QuotaGlance", style = TextStyle(color = ColorProvider(androidx.compose.ui.graphics.Color(0xFF006A6A))))
                GlanceText(widgetTitle(state.route, state.aggregate.accounts.firstOrNull()?.displayName, copy))
                GlanceText(state.aggregate.balances.joinToString("  ") { formatMoney(it) }.ifBlank { copy.noBalance })
                GlanceText(widgetStatus(state.status, copy))
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

private fun formatMoney(money: Money): String = "${money.canonicalAmount} ${money.currency}"
private fun widgetTitle(route: AppRoute, name: String?, copy: AppCopy): String =
    if (route is AppRoute.Account) name ?: copy.account else copy.allAccounts
private fun routeUri(route: AppRoute): String = when (route) {
    AppRoute.All -> "quotaglance://all"
    is AppRoute.Account -> "quotaglance://account/${route.id}"
}
private fun widgetStatus(status: DashboardStatus, copy: AppCopy): String = copy.status(status)
