package com.liangrui.quotaglance.refresh

import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.ExperimentalCoroutinesApi
import org.junit.Assert.assertEquals
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class ForegroundRefreshSchedulerTest {
    @Test
    fun `refreshes at the selected interval only while active`() = runTest {
        var refreshes = 0
        val scheduler = ForegroundRefreshScheduler(
            scope = this,
            onRefresh = { refreshes += 1 },
            minuteMillis = 100,
        )

        scheduler.start(intervalMinutes = 5)
        advanceTimeBy(499)
        runCurrent()
        assertEquals(0, refreshes)

        advanceTimeBy(1)
        runCurrent()
        assertEquals(1, refreshes)

        scheduler.stop()
        advanceTimeBy(500)
        runCurrent()
        assertEquals(1, refreshes)
    }

    @Test
    fun `changing the interval replaces the pending refresh`() = runTest {
        var refreshes = 0
        val scheduler = ForegroundRefreshScheduler(
            scope = this,
            onRefresh = { refreshes += 1 },
            minuteMillis = 100,
        )

        scheduler.start(intervalMinutes = 5)
        advanceTimeBy(100)
        scheduler.start(intervalMinutes = 1)
        advanceTimeBy(99)
        runCurrent()
        assertEquals(0, refreshes)

        advanceTimeBy(1)
        runCurrent()
        assertEquals(1, refreshes)

        scheduler.stop()
    }
}
