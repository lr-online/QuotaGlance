package com.liangrui.quotaglance.data

import android.content.Context
import android.util.Log
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import com.liangrui.quotaglance.core.AccountHealth
import com.liangrui.quotaglance.core.AccountSnapshot
import com.liangrui.quotaglance.core.ApiInfoDetails
import com.liangrui.quotaglance.core.CredentialKind
import com.liangrui.quotaglance.core.DailyUsage
import com.liangrui.quotaglance.core.MonetaryBalance
import com.liangrui.quotaglance.core.MonetaryValue
import com.liangrui.quotaglance.core.ModelUsage
import com.liangrui.quotaglance.core.Money
import com.liangrui.quotaglance.core.ProviderId
import com.liangrui.quotaglance.core.ProviderProfile
import com.liangrui.quotaglance.core.ProviderRegion
import com.liangrui.quotaglance.core.ProviderUsageSnapshot
import com.liangrui.quotaglance.core.QuotaAccount
import com.liangrui.quotaglance.core.QuotaWindow
import com.liangrui.quotaglance.core.SpendSummary
import com.liangrui.quotaglance.core.SpendingLimit
import com.liangrui.quotaglance.core.UsageCounters
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull

val Context.quotaGlanceDataStore: DataStore<Preferences> by preferencesDataStore("quotaglance")
private val accountMetadataKey = stringPreferencesKey("accountMetadata")
private const val snapshotPrefix = "snapshot."

/** JSON persistence codec for non-secret metadata and full provider snapshots. */
object StorageJsonCodec {
    private val json = Json { ignoreUnknownKeys = true }

    fun encodeAccounts(accounts: List<QuotaAccount>): String = JsonArray(accounts.map(::accountJson)).toString()

    fun decodeAccounts(raw: String): List<QuotaAccount> = runCatching {
        (json.parseToJsonElement(raw) as? JsonArray).orEmpty().mapNotNull { entry ->
            runCatching { account(entry as? JsonObject ?: return@runCatching null) }.getOrNull()
        }
    }.getOrDefault(emptyList())

    fun encodeSnapshot(snapshot: AccountSnapshot): String = JsonObject(buildMap {
        put("accountId", JsonPrimitive(snapshot.accountId))
        put("displayName", JsonPrimitive(snapshot.displayName))
        put("provider", JsonPrimitive(snapshot.provider.raw))
        snapshot.detectedProfile?.let { put("profile", profileJson(it)) }
        snapshot.lowBalanceThreshold?.let { put("lowBalanceThreshold", JsonPrimitive(it.toPlainString())) }
        snapshot.usage?.let { usage ->
            put("usage", JsonObject(usage.toFixtureJson().toMutableMap().apply {
                put("receivedAtMillis", JsonPrimitive(usage.receivedAtMillis))
            }))
        }
        put("health", healthJson(snapshot.health))
        snapshot.lastSuccessAtMillis?.let { put("lastSuccessAtMillis", JsonPrimitive(it)) }
    }).toString()

    fun decodeSnapshot(raw: String): AccountSnapshot? = runCatching {
        snapshot(json.parseToJsonElement(raw) as? JsonObject ?: return null)
    }.getOrNull()

    private fun account(raw: JsonObject): QuotaAccount = QuotaAccount(
        id = raw.requiredString("id"),
        displayName = raw.requiredString("displayName"),
        provider = ProviderId.fromRaw(raw.string("provider") ?: ProviderId.API_INFO.raw) ?: ProviderId.API_INFO,
        detectedProfile = raw.objectValue("profile")?.let(::profile),
        isEnabled = raw.bool("isEnabled", true),
        sortOrder = raw.long("sortOrder")?.toInt() ?: 0,
        lowBalanceThreshold = raw.string("lowBalanceThreshold")?.toBigDecimalOrNull(),
        alertEpisodeActive = raw.bool("alertEpisodeActive", false),
    )

    private fun accountJson(account: QuotaAccount): JsonObject = JsonObject(buildMap {
        put("id", JsonPrimitive(account.id))
        put("displayName", JsonPrimitive(account.displayName))
        put("provider", JsonPrimitive(account.provider.raw))
        account.detectedProfile?.let { put("profile", profileJson(it)) }
        put("isEnabled", JsonPrimitive(account.isEnabled))
        put("sortOrder", JsonPrimitive(account.sortOrder))
        account.lowBalanceThreshold?.let { put("lowBalanceThreshold", JsonPrimitive(it.toPlainString())) }
        put("alertEpisodeActive", JsonPrimitive(account.alertEpisodeActive))
    })

    private fun snapshot(raw: JsonObject): AccountSnapshot = AccountSnapshot(
        accountId = raw.requiredString("accountId"),
        displayName = raw.string("displayName") ?: "",
        provider = ProviderId.fromRaw(raw.string("provider") ?: ProviderId.API_INFO.raw) ?: ProviderId.API_INFO,
        detectedProfile = raw.objectValue("profile")?.let(::profile),
        lowBalanceThreshold = raw.string("lowBalanceThreshold")?.toBigDecimalOrNull(),
        usage = raw.objectValue("usage")?.let(::usage),
        health = raw.objectValue("health")?.let(::health) ?: AccountHealth.Unavailable("invalidResponse"),
        lastSuccessAtMillis = raw.long("lastSuccessAtMillis"),
    )

    private fun profileJson(profile: ProviderProfile): JsonObject = JsonObject(mapOf(
        "region" to JsonPrimitive(profile.region.raw),
        "credentialKind" to JsonPrimitive(profile.credentialKind.raw),
    ))

    private fun profile(raw: JsonObject): ProviderProfile = ProviderProfile(
        ProviderRegion.fromRaw(raw.requiredString("region")) ?: error("invalid profile region"),
        CredentialKind.fromRaw(raw.requiredString("credentialKind")) ?: error("invalid credential kind"),
    )

    private fun healthJson(health: AccountHealth): JsonObject = when (health) {
        AccountHealth.Healthy -> JsonObject(mapOf("kind" to JsonPrimitive("healthy")))
        AccountHealth.BelowThreshold -> JsonObject(mapOf("kind" to JsonPrimitive("belowThreshold")))
        is AccountHealth.Stale -> JsonObject(mapOf("kind" to JsonPrimitive("stale"), "reason" to JsonPrimitive(health.reason)))
        is AccountHealth.Unavailable -> JsonObject(mapOf("kind" to JsonPrimitive("unavailable"), "reason" to JsonPrimitive(health.reason)))
    }

    private fun health(raw: JsonObject): AccountHealth = when (raw.string("kind")) {
        "healthy" -> AccountHealth.Healthy
        "belowThreshold" -> AccountHealth.BelowThreshold
        "stale" -> AccountHealth.Stale(raw.string("reason") ?: "offline")
        else -> AccountHealth.Unavailable(raw.string("reason") ?: "invalidResponse")
    }

    private fun usage(raw: JsonObject): ProviderUsageSnapshot = ProviderUsageSnapshot(
        balances = raw.array("balances").map { balance ->
            val item = balance.objectValue()
            MonetaryBalance(
                label = item.requiredString("label"),
                available = money(item.getValue("available")),
                breakdown = item.array("breakdown").map { part ->
                    val partObject = part.objectValue()
                    MonetaryValue(partObject.requiredString("label"), money(partObject.getValue("value")))
                },
            )
        },
        spendingLimit = raw.objectValue("spendingLimit")?.let { limit ->
            SpendingLimit(
                label = limit.requiredString("label"),
                used = limit["used"]?.let(::money),
                limit = limit["limit"]?.let(::money),
                remaining = limit["remaining"]?.let(::money),
                resetDescription = limit.string("resetDescription"),
            )
        },
        spend = raw.objectValue("spend")?.let { spend ->
            SpendSummary(spend["today"]?.let(::money), spend["week"]?.let(::money), spend["month"]?.let(::money), spend["total"]?.let(::money))
        } ?: SpendSummary(),
        quotaWindows = raw.array("quotaWindows").map { item ->
            val window = item.objectValue()
            QuotaWindow(
                label = window.requiredString("label"),
                used = window.decimal("used"),
                limit = window.decimal("limit"),
                remaining = window.decimal("remaining"),
                unit = window.requiredString("unit"),
                resetsAtMillis = window.long("resetsAtMs"),
            )
        },
        today = raw.objectValue("today")?.let(::counters),
        total = raw.objectValue("total")?.let(::counters),
        dailyUsage = raw.array("dailyUsage").map { item ->
            val daily = item.objectValue()
            DailyUsage(daily.requiredString("date"), money(daily.getValue("actualCost")), daily.long("requests"), daily.long("totalTokens"))
        },
        modelUsage = raw.array("modelUsage").map { item ->
            val model = item.objectValue()
            ModelUsage(model.requiredString("model"), model["actualCost"]?.let(::money), model.long("requests"), model.long("totalTokens"))
        },
        apiInfoDetails = raw.objectValue("apiInfoDetails")?.let { details ->
            ApiInfoDetails(
                planName = details.string("planName"),
                mode = details.string("mode"),
                status = details.string("status"),
                reportedBalance = details["reportedBalance"]?.let(::money),
                isValid = details.booleanOrNull("isValid"),
                expiresAtMillis = details.long("expiresAtMs"),
                daysUntilExpiry = details.long("daysUntilExpiry"),
            )
        },
        providerStatus = raw.string("providerStatus"),
        metricsUnavailableReason = raw.string("metricsUnavailableReason"),
        receivedAtMillis = raw.long("receivedAtMillis") ?: 0,
    )

    private fun counters(raw: JsonObject): UsageCounters = UsageCounters(
        actualCost = raw["actualCost"]?.let(::money),
        requests = raw.long("requests"),
        inputTokens = raw.long("inputTokens"),
        outputTokens = raw.long("outputTokens"),
        cacheReadTokens = raw.long("cacheReadTokens"),
        cacheCreationTokens = raw.long("cacheCreationTokens"),
        totalTokens = raw.long("totalTokens"),
    )

    private fun money(raw: JsonElement): Money {
        val objectValue = raw.objectValue()
        return Money.fromString(objectValue.requiredString("amount"), objectValue.requiredString("currency"))
    }

    private fun JsonElement.objectValue(): JsonObject = this as? JsonObject ?: error("expected object")
    private fun JsonObject.objectValue(name: String): JsonObject? = this[name] as? JsonObject
    private fun JsonObject.array(name: String): JsonArray = this[name] as? JsonArray ?: JsonArray(emptyList())
    private fun JsonObject.string(name: String): String? = (this[name] as? JsonPrimitive)?.contentOrNull
    private fun JsonObject.requiredString(name: String): String = string(name) ?: error("missing $name")
    private fun JsonObject.bool(name: String, default: Boolean): Boolean =
        (this[name] as? JsonPrimitive)?.booleanOrNull ?: default
    private fun JsonObject.booleanOrNull(name: String): Boolean? =
        (this[name] as? JsonPrimitive)?.booleanOrNull
    private fun JsonObject.long(name: String): Long? = (this[name] as? JsonPrimitive)?.content?.toLongOrNull()
    private fun JsonObject.decimal(name: String): java.math.BigDecimal? = string(name)?.toBigDecimalOrNull()
}

class DataStoreAccountRepository(context: Context) : AccountRepository {
    private val store = context.applicationContext.quotaGlanceDataStore
    override val accounts: Flow<List<QuotaAccount>> = store.data.map { preferences ->
        StorageJsonCodec.decodeAccounts(preferences[accountMetadataKey] ?: "[]")
            .sortedWith(compareBy<QuotaAccount> { it.sortOrder }.thenBy { it.id })
    }

    override suspend fun list(): List<QuotaAccount> = accounts.first()

    override suspend fun upsert(account: QuotaAccount) {
        store.edit { preferences ->
            val items = StorageJsonCodec.decodeAccounts(preferences[accountMetadataKey] ?: "[]").toMutableList()
            val index = items.indexOfFirst { it.id == account.id }
            if (index >= 0) items[index] = account else items += account
            preferences[accountMetadataKey] = StorageJsonCodec.encodeAccounts(items)
        }
    }

    override suspend fun delete(accountId: String) {
        store.edit { preferences ->
            val items = StorageJsonCodec.decodeAccounts(preferences[accountMetadataKey] ?: "[]")
                .filterNot { it.id == accountId }
            preferences[accountMetadataKey] = StorageJsonCodec.encodeAccounts(items)
        }
    }
}

class DataStoreSnapshotRepository(context: Context) : SnapshotRepository {
    private val store = context.applicationContext.quotaGlanceDataStore
    override suspend fun read(accountId: String): AccountSnapshot? {
        val raw = store.data.first()[snapshotKey(accountId)] ?: return null
        return StorageJsonCodec.decodeSnapshot(raw)
    }

    override suspend fun all(): List<AccountSnapshot> = store.data.first().asMap().entries.mapNotNull { (key, value) ->
        if (!key.name.startsWith(snapshotPrefix)) return@mapNotNull null
        StorageJsonCodec.decodeSnapshot(value as? String ?: return@mapNotNull null)
    }

    override suspend fun write(snapshot: AccountSnapshot) {
        store.edit { it[snapshotKey(snapshot.accountId)] = StorageJsonCodec.encodeSnapshot(snapshot) }
    }

    override suspend fun delete(accountId: String) {
        store.edit { it.remove(snapshotKey(accountId)) }
    }

    private fun snapshotKey(accountId: String) = stringPreferencesKey("$snapshotPrefix$accountId")
}

/** API keys are stored separately from DataStore in Android Keystore-backed encrypted preferences. */
class KeystoreCredentialVault(context: Context) : CredentialVault {
    private val preferences = EncryptedSharedPreferences.create(
        context.applicationContext,
        "quotaglance.credentials",
        MasterKey.Builder(context.applicationContext).setKeyScheme(MasterKey.KeyScheme.AES256_GCM).build(),
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
    )

    override suspend fun read(accountId: String): String? = preferences.getString(accountId, null)
    override suspend fun write(accountId: String, apiKey: String) {
        try {
            check(preferences.edit().putString(accountId, apiKey).commit()) { "credential write failed" }
        } catch (error: Throwable) {
            Log.e(TAG, "credential_write_failed type=${error::class.simpleName ?: "Throwable"}")
            throw error
        }
    }
    override suspend fun delete(accountId: String) {
        check(preferences.edit().remove(accountId).commit()) { "credential delete failed" }
    }

    private companion object {
        const val TAG = "QuotaGlance/Storage"
    }
}
