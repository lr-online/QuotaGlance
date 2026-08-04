package com.liangrui.quotaglance.data

import android.content.Context
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import com.liangrui.quotaglance.ui.QuickViewSelection
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map

enum class RefreshInterval(val minutes: Int) {
    One(1), Five(5), Fifteen(15), Thirty(30), Sixty(60),
    ;

    companion object {
        fun fromMinutes(value: Int?): RefreshInterval = entries.firstOrNull { it.minutes == value } ?: Five
    }
}

enum class AppLanguage(val raw: String) {
    System("system"), English("en"), Chinese("zh"),
    ;

    companion object {
        fun fromRaw(value: String?): AppLanguage = entries.firstOrNull { it.raw == value } ?: System
    }
}

enum class AppThemeMode(val raw: String) {
    System("system"), Light("light"), Dark("dark"),
    ;

    companion object {
        fun fromRaw(value: String?): AppThemeMode = entries.firstOrNull { it.raw == value } ?: System
    }
}

data class AppPreferences(
    val refreshInterval: RefreshInterval = RefreshInterval.Five,
    val language: AppLanguage = AppLanguage.System,
    val themeMode: AppThemeMode = AppThemeMode.System,
    val defaultQuickViewAccountId: String? = null,
)

interface PreferencesRepository {
    val preferences: Flow<AppPreferences>
    suspend fun update(value: AppPreferences)
}

class DataStorePreferencesRepository(context: Context) : PreferencesRepository {
    private val store = context.applicationContext.quotaGlanceDataStore
    override val preferences: Flow<AppPreferences> = store.data.map { values ->
        AppPreferences(
            refreshInterval = RefreshInterval.fromMinutes(values[refreshIntervalKey]),
            language = AppLanguage.fromRaw(values[languageKey]),
            themeMode = AppThemeMode.fromRaw(values[themeModeKey]),
            defaultQuickViewAccountId = values[defaultQuickViewKey],
        )
    }

    override suspend fun update(value: AppPreferences) {
        store.edit { values ->
            values[refreshIntervalKey] = value.refreshInterval.minutes
            values[languageKey] = value.language.raw
            values[themeModeKey] = value.themeMode.raw
            value.defaultQuickViewAccountId?.let { values[defaultQuickViewKey] = it }
                ?: values.remove(defaultQuickViewKey)
        }
    }

    suspend fun current(): AppPreferences = preferences.first()

    private companion object {
        val refreshIntervalKey = intPreferencesKey("refreshIntervalMinutes")
        val languageKey = stringPreferencesKey("language")
        val themeModeKey = stringPreferencesKey("themeMode")
        val defaultQuickViewKey = stringPreferencesKey("defaultQuickViewAccountId")
    }
}

class WidgetSelectionStore(context: Context) {
    private val store = context.applicationContext.quotaGlanceDataStore

    suspend fun read(widgetId: Int): QuickViewSelection =
        QuickViewSelection.fromStorage(store.data.first()[selectionKey(widgetId)])

    suspend fun write(widgetId: Int, selection: QuickViewSelection) {
        store.edit { it[selectionKey(widgetId)] = selection.storageValue() }
    }

    private fun selectionKey(widgetId: Int) = stringPreferencesKey("widgetSelection.$widgetId")
}
