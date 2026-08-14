package com.liangrui.quotaglance.refresh

/**
 * The host-level refresh seam shared by foreground, background, widget, and
 * account-editor triggers. The coordinator remains the provider/snapshot
 * engine; this gateway gives every host path one invocation surface.
 */
interface RefreshEntryPoints {
    suspend fun refreshAll(): RefreshBatchResult
    suspend fun refreshAccount(accountId: String): RefreshBatchResult
    suspend fun recordSuccessfulSnapshot(accountId: String, usage: com.liangrui.quotaglance.core.ProviderUsageSnapshot)
}

class RefreshRun(private val coordinator: RefreshEntryPoints) : RefreshEntryPoints {
    override suspend fun refreshAll(): RefreshBatchResult = coordinator.refreshAll()

    override suspend fun refreshAccount(accountId: String): RefreshBatchResult =
        coordinator.refreshAccount(accountId)

    override suspend fun recordSuccessfulSnapshot(
        accountId: String,
        usage: com.liangrui.quotaglance.core.ProviderUsageSnapshot,
    ) = coordinator.recordSuccessfulSnapshot(accountId, usage)
}
