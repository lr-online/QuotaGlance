package com.liangrui.quotaglance.ui

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PermissionPolicyTest {
    @Test
    fun `does not request notification permission before Android 13`() {
        assertFalse(shouldRequestNotificationPermission(sdk = 32, granted = false))
    }

    @Test
    fun `does not request notification permission when granted on Android 15`() {
        assertFalse(shouldRequestNotificationPermission(sdk = 35, granted = true))
    }

    @Test
    fun `requests notification permission when denied on Android 13`() {
        assertTrue(shouldRequestNotificationPermission(sdk = 33, granted = false))
    }
}
