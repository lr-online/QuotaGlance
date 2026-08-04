package com.liangrui.quotaglance.refresh

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.pm.PackageManager
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.liangrui.quotaglance.core.HttpRequest
import com.liangrui.quotaglance.core.HttpResponse
import com.liangrui.quotaglance.core.Money
import com.liangrui.quotaglance.core.ProviderId
import com.liangrui.quotaglance.core.ProviderFailure
import com.liangrui.quotaglance.core.QuotaAccount
import com.liangrui.quotaglance.core.RawHttpClient
import com.liangrui.quotaglance.core.SpecDrivenProvider
import com.liangrui.quotaglance.data.AppLanguage
import com.liangrui.quotaglance.data.PreferencesRepository
import com.liangrui.quotaglance.widget.QuotaGlanceWidget
import java.util.Locale
import java.util.concurrent.TimeUnit
import java.io.IOException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request

class OkHttpRawHttpClient(private val client: OkHttpClient = OkHttpClient()) : RawHttpClient {
    // The protocol exposes this for deterministic fixture transports. Production
    // deliberately does not retain requests or credentials after execution.
    override val requests: MutableList<HttpRequest> = mutableListOf()

    override suspend fun execute(request: HttpRequest): HttpResponse = withContext(Dispatchers.IO) {
        try {
            val httpRequest = Request.Builder().url(request.url).method(request.method, null).apply {
                request.headers.forEach { (name, value) -> header(name, value) }
            }.build()
            client.newCall(httpRequest).execute().use { response ->
                HttpResponse(response.code, response.body?.string().orEmpty())
            }
        } catch (error: IOException) {
            // Keep the UI actionable without ever including URLs, headers, or keys.
            throw ProviderFailure("network", error::class.simpleName ?: "io")
        }
    }
}

/** Loads every production provider from the synced contract assets. */
class AssetProviderRegistry(
    context: Context,
    httpClient: RawHttpClient = OkHttpRawHttpClient(),
) : ProviderRegistry {
    private val appContext = context.applicationContext
    private val providers: Map<ProviderId, SpecDrivenProvider> by lazy {
        ProviderId.entries.associateWith { id ->
            val spec = appContext.assets.open("providerspecs/${id.raw}.json").bufferedReader().use { it.readText() }
            SpecDrivenProvider(spec, httpClient)
        }
    }

    override fun provider(id: ProviderId) = providers[id] ?: error("missing provider ${id.raw}")
}

class AndroidNotificationDispatcher(
    private val context: Context,
    private val preferences: PreferencesRepository,
) : NotificationDispatcher {
    override suspend fun notifyLowBalance(account: QuotaAccount, remaining: Money) {
        if (android.os.Build.VERSION.SDK_INT >= 33 && ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.POST_NOTIFICATIONS,
            ) != PackageManager.PERMISSION_GRANTED
        ) return
        val language = preferences.preferences.first().language
        val chinese = language == AppLanguage.Chinese ||
            (language == AppLanguage.System && Locale.getDefault().language.startsWith("zh", ignoreCase = true))
        val channelName = if (chinese) "低余额提醒" else "Low-balance alerts"
        val content = if (chinese) {
            "剩余 ${remaining.canonicalAmount} ${remaining.currency}"
        } else {
            "${remaining.canonicalAmount} ${remaining.currency} remaining"
        }
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(CHANNEL_ID, channelName, NotificationManager.IMPORTANCE_DEFAULT))
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentTitle(account.displayName)
            .setContentText(content)
            .setAutoCancel(true)
            .build()
        manager.notify(account.id.hashCode(), notification)
    }

    private companion object {
        const val CHANNEL_ID = "low_balance"
    }
}

class AndroidWidgetRefresh(private val context: Context) : WidgetRefresh {
    override suspend fun refresh() = QuotaGlanceWidget.refreshAll(context)
}

class RefreshScheduler(private val context: Context) {
    fun schedule(intervalMinutes: Long) {
        val interval = intervalMinutes.coerceAtLeast(15)
        val request = PeriodicWorkRequestBuilder<RefreshWorker>(interval, TimeUnit.MINUTES)
            .setConstraints(backgroundConstraints)
            .build()
        WorkManager.getInstance(context).enqueueUniquePeriodicWork(
            PERIODIC_WORK,
            ExistingPeriodicWorkPolicy.UPDATE,
            request,
        )
    }

    fun refreshNow() {
        val request = androidx.work.OneTimeWorkRequestBuilder<RefreshWorker>()
            .setConstraints(backgroundConstraints)
            .build()
        WorkManager.getInstance(context).enqueueUniqueWork(MANUAL_WORK, ExistingWorkPolicy.REPLACE, request)
    }

    companion object {
        const val PERIODIC_WORK = "quotaglance.periodic.refresh"
        const val MANUAL_WORK = "quotaglance.manual.refresh"

        private val backgroundConstraints = Constraints.Builder()
            .setRequiredNetworkType(NetworkType.CONNECTED)
            .setRequiresBatteryNotLow(true)
            .build()
    }
}

/** Refreshes only while an Activity is visible; background cadence remains WorkManager-owned. */
class ForegroundRefreshScheduler(
    private val scope: CoroutineScope,
    private val onRefresh: suspend () -> Unit,
    private val minuteMillis: Long = TimeUnit.MINUTES.toMillis(1),
) {
    private var job: Job? = null

    fun start(intervalMinutes: Long) {
        require(intervalMinutes > 0) { "interval must be positive" }
        stop()
        job = scope.launch {
            while (isActive) {
                delay(intervalMinutes * minuteMillis)
                if (isActive) runCatching { onRefresh() }
            }
        }
    }

    fun stop() {
        job?.cancel()
        job = null
    }
}

class RefreshWorker(
    appContext: Context,
    parameters: WorkerParameters,
) : CoroutineWorker(appContext, parameters) {
    override suspend fun doWork(): Result = try {
        (applicationContext as QuotaGlanceApplication).container.refreshCoordinator.refreshAll()
        Result.success()
    } catch (_: Exception) {
        Result.retry()
    }
}
