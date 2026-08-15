package com.liangrui.quotaglance.ui

internal fun shouldRequestNotificationPermission(sdk: Int, granted: Boolean): Boolean = sdk >= 33 && !granted
