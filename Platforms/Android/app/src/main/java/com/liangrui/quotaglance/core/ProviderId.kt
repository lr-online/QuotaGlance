package com.liangrui.quotaglance.core

/**
 * Persisted provider identifiers. Keep declaration order append-only: it is
 * shared with the Swift and ArkTS account stores and contract resources.
 */
enum class ProviderId(val raw: String) {
    API_INFO("apiInfo"),
    DEEP_SEEK("deepSeek"),
    KIMI("kimi"),
    OPEN_ROUTER("openRouter"),
    MINI_MAX("miniMax"),
    BIO_MAP_CODING("bioMapCoding"),
    ;

    companion object {
        fun fromRaw(value: String): ProviderId? = entries.firstOrNull { it.raw == value }
    }
}
