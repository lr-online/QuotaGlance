package com.liangrui.quotaglance.core

import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Test

class ProviderContractTest {
    @Test
    fun `request templates interpolate the supplied api key`() = runTest {
        val transport = FixtureTransport("apiinfo", "usage", listOf(200))
        val provider = SpecDrivenProvider(
            specJson = resource("contracts/Providers/apiinfo/spec.json"),
            httpClient = transport,
            nowMillis = { 0L },
        )

        provider.fetch("actual-secret", ProviderProfile.globalStandard())

        assertEquals("Bearer actual-secret", transport.requests.single().headers["Authorization"])
    }

    @Test
    fun `every provider fixture produces its expected snapshot and request sequence`() = runTest {
        CONTRACT_CASES.forEach { case ->
            val directory = case.provider.raw.lowercase()
            val expectedRequests = json.parseToJsonElement(
                resource("contracts/Providers/$directory/${case.name}-requests.json"),
            ).jsonArray
            val transport = FixtureTransport(directory, case.name, case.statuses)
            val provider = SpecDrivenProvider(
                specJson = resource("contracts/Providers/$directory/spec.json"),
                httpClient = transport,
                nowMillis = { 0L },
            )

            val actual = provider.fetch("fixture-key", case.profile)
            assertSubset(
                json.parseToJsonElement(
                    resource("contracts/Providers/$directory/${case.name}-expected.json"),
                ),
                actual.toFixtureJson(),
                "${case.provider.raw}/${case.name}",
            )
            assertRequests(expectedRequests, transport.requests, "${case.provider.raw}/${case.name}")
        }
    }

    private fun resource(path: String): String =
        checkNotNull(javaClass.classLoader?.getResourceAsStream(path)) { "missing fixture $path" }
            .bufferedReader()
            .use { it.readText() }

    private fun assertRequests(expected: JsonArray, actual: List<HttpRequest>, label: String) {
        assertEquals("$label request count", expected.size, actual.size)
        expected.zip(actual).forEachIndexed { index, (raw, request) ->
            val item = raw.jsonObject
            assertEquals("$label request $index method", item.string("method"), request.method)
            assertEquals("$label request $index url", item.string("url"), request.url)
            item.jsonObject("headers").forEach { (name, rawPattern) ->
                val pattern = rawPattern.jsonPrimitive.content
                val actualValue = request.headers[name]
                if (pattern == "Bearer") {
                    check(actualValue?.startsWith("Bearer ") == true) {
                        "$label request $index header $name must use Bearer"
                    }
                } else {
                    assertEquals("$label request $index header $name", pattern, actualValue)
                }
            }
        }
    }

    private fun assertSubset(expected: JsonElement, actual: JsonElement, path: String) {
        when (expected) {
            is JsonObject -> {
                val actualObject = actual as? JsonObject
                    ?: error("$path expected object, got $actual")
                expected.forEach { (key, value) ->
                    assertSubset(value, checkNotNull(actualObject[key]) { "$path missing $key" }, "$path.$key")
                }
            }
            is JsonArray -> {
                val actualArray = actual as? JsonArray
                    ?: error("$path expected array, got $actual")
                assertEquals("$path item count", expected.size, actualArray.size)
                expected.zip(actualArray).forEachIndexed { index, (left, right) ->
                    assertSubset(left, right, "$path[$index]")
                }
            }
            is JsonPrimitive -> assertEquals("$path", expected, actual)
        }
    }

    private class FixtureTransport(
        private val directory: String,
        private val caseName: String,
        private val statuses: List<Int>,
    ) : RawHttpClient {
        override val requests = mutableListOf<HttpRequest>()

        override suspend fun execute(request: HttpRequest): HttpResponse {
            val index = requests.size
            requests += request
            val suffix = if (index == 0) "" else (index + 1).toString()
            val body = checkNotNull(javaClass.classLoader?.getResourceAsStream(
                "contracts/Providers/$directory/$caseName-response$suffix.json",
            )) { "missing response step $index" }.bufferedReader().use { it.readText() }
            return HttpResponse(statuses[index], body)
        }
    }

    private data class ContractCase(
        val provider: ProviderId,
        val name: String,
        val profile: ProviderProfile,
        val statuses: List<Int> = listOf(200),
    )

    private companion object {
        val json = Json { ignoreUnknownKeys = true }
        val CONTRACT_CASES = listOf(
            ContractCase(ProviderId.API_INFO, "usage", ProviderProfile.globalStandard()),
            ContractCase(ProviderId.DEEP_SEEK, "balance", ProviderProfile.globalStandard()),
            ContractCase(ProviderId.KIMI, "china", ProviderProfile(ProviderRegion.CHINA, CredentialKind.STANDARD)),
            ContractCase(ProviderId.OPEN_ROUTER, "key-standard", ProviderProfile.globalStandard()),
            ContractCase(ProviderId.OPEN_ROUTER, "key-management", ProviderProfile(ProviderRegion.GLOBAL, CredentialKind.MANAGEMENT), listOf(200, 200)),
            ContractCase(ProviderId.MINI_MAX, "remains", ProviderProfile(ProviderRegion.CHINA, CredentialKind.TOKEN_PLAN)),
            ContractCase(ProviderId.BIO_MAP_CODING, "budget", ProviderProfile.globalStandard()),
            ContractCase(ProviderId.BIO_MAP_CODING, "fallback", ProviderProfile.globalStandard(), listOf(403, 200)),
        )
    }
}

private fun JsonObject.string(key: String): String = getValue(key).jsonPrimitive.content

private fun JsonObject.jsonObject(key: String): JsonObject = getValue(key) as JsonObject

private val JsonElement.jsonArray: JsonArray
    get() = this as JsonArray
