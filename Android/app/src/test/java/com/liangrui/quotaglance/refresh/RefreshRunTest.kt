package com.liangrui.quotaglance.refresh

import com.liangrui.quotaglance.core.ProviderUsageSnapshot
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Test

class RefreshRunTest {
    @Test
    fun `delegates every refresh entry point to the engine`() = runTest {
        val engine = RecordingEntryPoints()
        val run = RefreshRun(engine)
        val usage = ProviderUsageSnapshot(receivedAtMillis = 42)

        assertEquals(RefreshBatchResult(2, 1), run.refreshAll())
        assertEquals(RefreshBatchResult(1, 0), run.refreshAccount("account-1"))
        run.recordSuccessfulSnapshot("account-1", usage)

        assertEquals(listOf("all", "account:account-1", "snapshot:account-1:42"), engine.calls)
    }

    private class RecordingEntryPoints : RefreshEntryPoints {
        val calls = mutableListOf<String>()

        override suspend fun refreshAll(): RefreshBatchResult {
            calls += "all"
            return RefreshBatchResult(successes = 2, failures = 1)
        }

        override suspend fun refreshAccount(accountId: String): RefreshBatchResult {
            calls += "account:$accountId"
            return RefreshBatchResult(successes = 1, failures = 0)
        }

        override suspend fun recordSuccessfulSnapshot(accountId: String, usage: ProviderUsageSnapshot) {
            calls += "snapshot:$accountId:${usage.receivedAtMillis}"
        }
    }
}
