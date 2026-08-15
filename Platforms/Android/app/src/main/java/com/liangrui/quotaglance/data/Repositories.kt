package com.liangrui.quotaglance.data

import com.liangrui.quotaglance.core.AccountSnapshot
import com.liangrui.quotaglance.core.QuotaAccount
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

interface AccountRepository {
    val accounts: Flow<List<QuotaAccount>>
    suspend fun list(): List<QuotaAccount>
    suspend fun upsert(account: QuotaAccount)
    suspend fun delete(accountId: String)
}

interface CredentialVault {
    suspend fun read(accountId: String): String?
    suspend fun write(accountId: String, apiKey: String)
    suspend fun delete(accountId: String)
}

interface SnapshotRepository {
    suspend fun read(accountId: String): AccountSnapshot?
    suspend fun all(): List<AccountSnapshot>
    suspend fun write(snapshot: AccountSnapshot)
    suspend fun delete(accountId: String)
}

class InMemoryAccountRepository(initial: List<QuotaAccount> = emptyList()) : AccountRepository {
    private val state = MutableStateFlow(initial.map { it.copy() })
    override val accounts = state.asStateFlow()

    override suspend fun list(): List<QuotaAccount> = state.value.map { it.copy() }

    override suspend fun upsert(account: QuotaAccount) {
        val values = state.value.toMutableList()
        val index = values.indexOfFirst { it.id == account.id }
        if (index >= 0) values[index] = account.copy() else values += account.copy()
        state.value = values
    }

    override suspend fun delete(accountId: String) {
        state.value = state.value.filterNot { it.id == accountId }
    }
}

class InMemoryCredentialVault(initial: Map<String, String> = emptyMap()) : CredentialVault {
    private val values = initial.toMutableMap()
    override suspend fun read(accountId: String): String? = values[accountId]
    override suspend fun write(accountId: String, apiKey: String) { values[accountId] = apiKey }
    override suspend fun delete(accountId: String) { values.remove(accountId) }
}

class InMemorySnapshotRepository(initial: Map<String, AccountSnapshot> = emptyMap()) : SnapshotRepository {
    private val values = initial.toMutableMap()
    override suspend fun read(accountId: String): AccountSnapshot? = values[accountId]
    override suspend fun all(): List<AccountSnapshot> = values.values.toList()
    override suspend fun write(snapshot: AccountSnapshot) { values[snapshot.accountId] = snapshot }
    override suspend fun delete(accountId: String) { values.remove(accountId) }
}

object AccountValidator {
    const val MAX_ACCOUNTS = 20

    enum class Error {
        EmptyDisplayName,
        DuplicateDisplayName,
        EmptyApiKey,
        AccountLimit,
    }

    data class Result(val normalizedDisplayName: String? = null, val error: Error? = null)

    fun validate(
        existing: List<QuotaAccount>,
        editingId: String?,
        displayName: String,
        replacementApiKey: String?,
    ): Result {
        val normalized = displayName.trim()
        if (normalized.isEmpty()) return Result(error = Error.EmptyDisplayName)
        if (replacementApiKey != null && replacementApiKey.isBlank()) return Result(error = Error.EmptyApiKey)
        if (existing.any { it.id != editingId && it.displayName.trim().equals(normalized, ignoreCase = true) }) {
            return Result(error = Error.DuplicateDisplayName)
        }
        if (editingId == null && existing.size >= MAX_ACCOUNTS) return Result(error = Error.AccountLimit)
        return Result(normalizedDisplayName = normalized)
    }
}

/** Owns account metadata plus the key and snapshot cleanup lifecycle. */
class AccountMutationService(
    private val accounts: AccountRepository,
    private val credentials: CredentialVault,
    private val snapshots: SnapshotRepository,
) {
    suspend fun save(account: QuotaAccount, replacementApiKey: String? = null): AccountValidator.Result {
        val existing = accounts.list()
        val validation = AccountValidator.validate(existing, account.id, account.displayName, replacementApiKey)
        val name = validation.normalizedDisplayName ?: return validation
        val previous = existing.firstOrNull { it.id == account.id }
        if (previous != null && previous.provider != account.provider && replacementApiKey.isNullOrBlank()) {
            return AccountValidator.Result(error = AccountValidator.Error.EmptyApiKey)
        }
        val saved = account.copy(
            displayName = name,
            alertEpisodeActive = account.alertEpisodeActive && account.isEnabled && account.lowBalanceThreshold != null,
        )
        accounts.upsert(saved)
        replacementApiKey?.let { credentials.write(saved.id, it) }
        return validation
    }

    suspend fun create(account: QuotaAccount, apiKey: String): AccountValidator.Result {
        val existing = accounts.list()
        val validation = AccountValidator.validate(existing, null, account.displayName, apiKey)
        val name = validation.normalizedDisplayName ?: return validation
        val nextSortOrder = existing.maxOfOrNull { it.sortOrder }?.let { it + 1 } ?: 0
        val saved = account.copy(displayName = name, sortOrder = nextSortOrder, alertEpisodeActive = false)
        credentials.write(account.id, apiKey)
        accounts.upsert(saved)
        return validation
    }

    suspend fun delete(accountId: String) {
        var failure: Throwable? = null
        try {
            credentials.delete(accountId)
        } catch (error: Throwable) {
            failure = error
        }
        try {
            snapshots.delete(accountId)
        } catch (error: Throwable) {
            if (failure == null) failure = error else failure.addSuppressed(error)
        }
        try {
            accounts.delete(accountId)
        } catch (error: Throwable) {
            if (failure == null) failure = error else failure.addSuppressed(error)
        }
        failure?.let { throw it }
    }
}
