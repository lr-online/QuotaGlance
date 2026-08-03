package com.liangrui.quotaglance.refresh

import android.app.Application
import com.liangrui.quotaglance.data.DataStoreAccountRepository
import com.liangrui.quotaglance.data.DataStoreSnapshotRepository
import com.liangrui.quotaglance.data.DataStorePreferencesRepository
import com.liangrui.quotaglance.data.KeystoreCredentialVault
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

class QuotaGlanceApplication : Application() {
    lateinit var container: AndroidAppContainer
        private set

    override fun onCreate() {
        super.onCreate()
        container = AndroidAppContainer(this)
        CoroutineScope(SupervisorJob() + Dispatchers.Default).launch {
            RefreshScheduler(this@QuotaGlanceApplication).schedule(container.preferences.current().refreshInterval.minutes.toLong())
        }
    }
}

class AndroidAppContainer(application: Application) {
    val application = application
    val accounts = DataStoreAccountRepository(application)
    val credentials = KeystoreCredentialVault(application)
    val snapshots = DataStoreSnapshotRepository(application)
    val preferences = DataStorePreferencesRepository(application)
    val providers = AssetProviderRegistry(application)
    val notificationDispatcher = AndroidNotificationDispatcher(application, preferences)
    val refreshCoordinator = RefreshCoordinator(
        providers = providers,
        accounts = accounts,
        credentials = credentials,
        snapshots = snapshots,
        notifications = notificationDispatcher,
        widgetRefresh = AndroidWidgetRefresh(application),
    )
}
