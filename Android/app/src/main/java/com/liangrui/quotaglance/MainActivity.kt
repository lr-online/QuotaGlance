package com.liangrui.quotaglance

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.core.content.ContextCompat
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.liangrui.quotaglance.refresh.QuotaGlanceApplication
import com.liangrui.quotaglance.ui.AppRoute
import com.liangrui.quotaglance.ui.QuotaGlanceApp
import com.liangrui.quotaglance.ui.QuotaGlanceViewModel
import com.liangrui.quotaglance.ui.QuotaGlanceViewModelFactory

class MainActivity : ComponentActivity() {
    private var notificationsGranted by mutableStateOf(false)
    private val notificationPermission = registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        notificationsGranted = granted
    }
    private val viewModel: QuotaGlanceViewModel by viewModels {
        QuotaGlanceViewModelFactory(
            (application as QuotaGlanceApplication).container,
            AppRoute.parse(intent?.dataString),
        )
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        notificationsGranted = hasNotificationPermission()
        setContent {
            QuotaGlanceApp(viewModel, notificationsGranted, ::requestNotificationPermission)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        viewModel.routeTo(AppRoute.parse(intent.dataString))
    }

    override fun onResume() {
        super.onResume()
        notificationsGranted = hasNotificationPermission()
        viewModel.refreshAll()
        viewModel.startForegroundRefresh()
    }

    override fun onPause() {
        viewModel.stopForegroundRefresh()
        super.onPause()
    }

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= 33 && ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            notificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }

    private fun hasNotificationPermission(): Boolean =
        Build.VERSION.SDK_INT < 33 || ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
}
