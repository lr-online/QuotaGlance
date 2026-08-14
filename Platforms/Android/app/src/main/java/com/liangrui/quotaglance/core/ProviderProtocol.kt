package com.liangrui.quotaglance.core

data class HttpRequest(
    val method: String,
    val url: String,
    val headers: Map<String, String>,
)

data class HttpResponse(val statusCode: Int, val body: String)

interface RawHttpClient {
    val requests: MutableList<HttpRequest>
    suspend fun execute(request: HttpRequest): HttpResponse
}

data class ProviderDetection(
    val profile: ProviderProfile,
    val snapshot: ProviderUsageSnapshot,
)

data class ProviderDescriptor(
    val id: ProviderId,
    val displayName: String,
    val supportsLowBalanceThreshold: (ProviderProfile?) -> Boolean,
    val profileDescriptionToken: (ProviderProfile?) -> String,
)

interface UsageProvider {
    val id: ProviderId
    val descriptor: ProviderDescriptor
    suspend fun detect(apiKey: String): ProviderDetection
    suspend fun fetch(apiKey: String, profile: ProviderProfile): ProviderUsageSnapshot
}

class ProviderFailure(
    val token: String,
    val statusCode: Int? = null,
    val detail: String? = null,
) : Exception(
    when {
        token == "httpStatus" -> "httpStatus:${statusCode ?: 0}"
        token == "network" && !detail.isNullOrBlank() -> "network:$detail"
        else -> token
    },
)

fun Throwable.providerToken(): String =
    message?.substringBefore(':') ?: "invalidResponse"
