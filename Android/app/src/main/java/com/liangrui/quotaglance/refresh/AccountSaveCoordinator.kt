package com.liangrui.quotaglance.refresh

import com.liangrui.quotaglance.core.ProviderFailure as CoreProviderFailure
import com.liangrui.quotaglance.core.QuotaAccount
import com.liangrui.quotaglance.data.AccountMutationService
import com.liangrui.quotaglance.data.AccountRepository
import com.liangrui.quotaglance.data.AccountValidator
import com.liangrui.quotaglance.data.CredentialVault

sealed interface AccountSaveResult {
    data object Saved : AccountSaveResult
    data class ValidationFailure(val error: AccountValidator.Error) : AccountSaveResult
    data class ProviderFailure(val token: String) : AccountSaveResult
}

/** Validates keys against their provider before a new or replacement credential is persisted. */
class AccountSaveCoordinator(
    private val providers: ProviderRegistry,
    private val accounts: AccountRepository,
    private val credentials: CredentialVault,
    private val mutationService: AccountMutationService,
    private val refreshCoordinator: RefreshCoordinator,
    private val logger: AccountSaveLogger = NoopAccountSaveLogger,
) {
    suspend fun save(account: QuotaAccount, apiKeyText: String): AccountSaveResult {
        val existing = accounts.list()
        val previous = existing.firstOrNull { it.id == account.id }
        val replacementKey = apiKeyText.trim().takeIf { it.isNotEmpty() }
        logger.record(
            stage = "start",
            provider = account.provider,
            detail = "editing=${previous != null} key_present=${replacementKey != null}",
        )
        val validation = AccountValidator.validate(
            existing = existing,
            editingId = previous?.id,
            displayName = account.displayName,
            replacementApiKey = replacementKey,
        )
        validation.error?.let {
            logger.record("validation_failure", account.provider, "error=${it.name}")
            return AccountSaveResult.ValidationFailure(it)
        }
        if (previous == null && replacementKey == null) {
            logger.record("validation_failure", account.provider, "error=EmptyApiKey")
            return AccountSaveResult.ValidationFailure(AccountValidator.Error.EmptyApiKey)
        }
        if (previous != null && previous.provider != account.provider && replacementKey == null) {
            logger.record("validation_failure", account.provider, "error=EmptyApiKey")
            return AccountSaveResult.ValidationFailure(AccountValidator.Error.EmptyApiKey)
        }

        val normalized = account.copy(displayName = checkNotNull(validation.normalizedDisplayName))
        val requiresDetection = previous == null || previous.provider != normalized.provider || replacementKey != null
        return try {
            val provider = providers.provider(normalized.provider)
            if (requiresDetection) {
                logger.record("detect_start", normalized.provider, "required=true")
                val key = replacementKey ?: credentials.read(normalized.id)
                    ?: return AccountSaveResult.ValidationFailure(AccountValidator.Error.EmptyApiKey)
                val detection = provider.detect(key)
                logger.record("detect_success", normalized.provider, "profile=${detection.profile.region.raw}/${detection.profile.credentialKind.raw}")
                val detected = normalized.copy(
                    detectedProfile = detection.profile,
                    lowBalanceThreshold = normalized.lowBalanceThreshold.takeIf {
                        provider.descriptor.supportsLowBalanceThreshold(detection.profile)
                    },
                )
                logger.record("persist_start", detected.provider, "new_account=${previous == null}")
                persist(previous, detected, key, replacementKey)?.let { return it }
                logger.record("persist_success", detected.provider, "new_account=${previous == null}")
                refreshCoordinator.recordSuccessfulSnapshot(detected.id, detection.snapshot)
                logger.record("snapshot_success", detected.provider, "source=detect")
            } else {
                val profile = normalized.detectedProfile ?: previous?.detectedProfile
                val updated = normalized.copy(
                    detectedProfile = profile,
                    lowBalanceThreshold = normalized.lowBalanceThreshold.takeIf {
                        provider.descriptor.supportsLowBalanceThreshold(profile)
                    },
                )
                logger.record("persist_start", updated.provider, "new_account=false")
                persist(previous, updated, null, null)?.let { return it }
                logger.record("persist_success", updated.provider, "new_account=false")
                if (updated.isEnabled) refreshCoordinator.refreshAccount(updated.id)
            }
            AccountSaveResult.Saved
        } catch (error: Throwable) {
            logger.record("failure", normalized.provider, error.safeDiagnosticDetail())
            AccountSaveResult.ProviderFailure(error.token())
        }
    }

    private suspend fun persist(
        previous: QuotaAccount?,
        account: QuotaAccount,
        newAccountKey: String?,
        replacementKey: String?,
    ): AccountSaveResult.ValidationFailure? {
        val result = if (previous == null) {
            mutationService.create(account, checkNotNull(newAccountKey))
        } else {
            mutationService.save(account, replacementKey)
        }
        return result.error?.let(AccountSaveResult::ValidationFailure)
    }

    private fun Throwable.token(): String = when (this) {
        is CoreProviderFailure -> message ?: token
        else -> "offline"
    }

    private fun Throwable.safeDiagnosticDetail(): String = buildString {
        append("types=")
        append(
            generateSequence(this@safeDiagnosticDetail) { it.cause }
                .take(3)
                .joinToString("->") { it::class.simpleName ?: "Throwable" },
        )
        if (this@safeDiagnosticDetail is CoreProviderFailure) {
            append(" token=").append(token)
            statusCode?.let { append(" status=").append(it) }
        }
    }
}
