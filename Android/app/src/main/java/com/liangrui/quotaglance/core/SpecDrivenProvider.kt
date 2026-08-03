package com.liangrui.quotaglance.core

import java.util.Locale
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull

/** Executes the closed provider schema in Contracts/Providers. */
class SpecDrivenProvider(
    specJson: String,
    private val httpClient: RawHttpClient,
    private val nowMillis: () -> Long = { System.currentTimeMillis() },
    private val preferredRegion: ProviderRegion? = null,
) : UsageProvider {
    override val id: ProviderId
    override val descriptor: ProviderDescriptor

    private val spec: JsonObject

    init {
        spec = try {
            json.parseToJsonElement(specJson) as? JsonObject
                ?: throw IllegalArgumentException("provider spec must be an object")
        } catch (error: IllegalArgumentException) {
            throw error
        } catch (error: Exception) {
            throw IllegalArgumentException("provider spec decode failed", error)
        }
        id = ProviderId.fromRaw(spec.string("id") ?: error("provider spec misses id"))
            ?: error("unknown provider id '${spec.string("id")}'")
        validateSpec(spec)
        descriptor = descriptorFor(id, spec)
    }

    override suspend fun detect(apiKey: String): ProviderDetection {
        val key = preprocess(apiKey)
        val detect = spec.objectValue("detect") ?: invalidSpec("detect must be an object")
        return when (detect.string("strategy")) {
            "fixedProfile" -> {
                val profileRaw = detect.objectValue("profile") ?: invalidSpec("fixed profile missing profile")
                val region = profileRaw.region("region")
                val configuredKind = profileRaw.string("credentialKind") ?: invalidSpec("fixed profile missing kind")
                val result = runPipeline(key, ProviderProfile(region, CredentialKind.STANDARD), isFetch = false)
                val kind = if (configuredKind == "detected") {
                    result.detectedKind ?: throw ProviderFailure("invalidResponse")
                } else {
                    profileRaw.credentialKind("credentialKind")
                }
                ProviderDetection(ProviderProfile(region, kind), result.snapshot)
            }
            "regionFallback" -> {
                val fallbackOn = detect.stringList("fallbackOn").toSet()
                for (candidate in orderedCandidates(detect)) {
                    try {
                        return ProviderDetection(candidate, runPipeline(key, candidate, isFetch = false).snapshot)
                    } catch (error: Throwable) {
                        if (error !is ProviderFailure || error.token !in fallbackOn) throw error
                    }
                }
                throw ProviderFailure(detect.string("exhaustedError") ?: "regionDetectionFailed")
            }
            else -> invalidSpec("unknown detect strategy")
        }
    }

    override suspend fun fetch(apiKey: String, profile: ProviderProfile): ProviderUsageSnapshot {
        if (profile !in supportedProfiles()) throw ProviderFailure("profileMismatch")
        return runPipeline(preprocess(apiKey), profile, isFetch = true).snapshot
    }

    private suspend fun runPipeline(
        apiKey: String,
        profile: ProviderProfile,
        isFetch: Boolean,
    ): PipelineResult {
        val steps = fetchSteps()
        val bodies = linkedMapOf<String, JsonElement>()
        val merged = linkedMapOf<String, EvalValue>()
        var detectedKind: CredentialKind? = null
        for (step in steps) {
            if (step.bool("onDemand")) continue
            if ("when" in step && !SpecEngine.condition(step.getValue("when"), null, bodies)) continue
            val result = executeStep(step, apiKey, profile, bodies)
            bodies[step.string("name") ?: invalidSpec("step missing name")] = result.body
            merged.putAll(result.fields)
            result.detectedKind?.let { kind ->
                if (isFetch && kind != profile.credentialKind) throw ProviderFailure("profileMismatch")
                if (!isFetch) detectedKind = kind
            }
            if (result.replacesPipeline) break
        }
        return PipelineResult(SpecEngine.assembleSnapshot(merged, nowMillis()), detectedKind)
    }

    private suspend fun executeStep(
        step: JsonObject,
        apiKey: String,
        profile: ProviderProfile,
        stepBodies: Map<String, JsonElement>,
    ): StepResult {
        val request = step.objectValue("request") ?: invalidSpec("step request missing")
        val response = httpClient.execute(
            HttpRequest(
                method = request.string("method") ?: invalidSpec("request method missing"),
                url = requestUrl(request, profile),
                headers = requestHeaders(request, apiKey),
            ),
        )
        val branch = requestStatusBranch(step, response.statusCode)
            ?: throw ProviderFailure("httpStatus", response.statusCode)
        when (branch.string("action")) {
            "error" -> throw ProviderFailure(branch.string("error") ?: "invalidResponse", response.statusCode)
            "gotoStep" -> {
                val target = stepNamed(branch.string("step") ?: invalidSpec("goto target missing"))
                return executeStep(target, apiKey, profile, stepBodies).copy(replacesPipeline = true)
            }
            "parse" -> Unit
            else -> invalidSpec("unknown onStatus action")
        }

        val body = try {
            json.parseToJsonElement(response.body)
        } catch (_: Exception) {
            throw ProviderFailure("invalidResponse")
        }
        val parse = step.objectValue("parse")
        SpecEngine.runChecks(parse?.get("checks"), body)
        val scope = EvalScope(
            root = body,
            region = profile.region,
            steps = stepBodies,
            builders = parse?.objectValue("values") ?: JsonObject(emptyMap()),
        )
        val fields = linkedMapOf<String, EvalValue>()
        parse?.objectValue("snapshot")?.forEach { (name, builder) ->
            SpecEngine.evaluateBuilder(builder, scope)?.let { fields[name] = it }
        }
        val detectedKind = parse?.objectValue("credentialKindDetection")?.let { detection ->
            val key = scalarKey(SpecEngine.resolve(body, detection.string("path") ?: invalidSpec("kind path missing")))
                ?: throw ProviderFailure("invalidResponse")
            val rawKind = detection.objectValue("map")?.string(key) ?: throw ProviderFailure("invalidResponse")
            CredentialKind.fromRaw(rawKind) ?: throw ProviderFailure("invalidResponse")
        }
        return StepResult(body, fields, detectedKind)
    }

    private fun requestStatusBranch(step: JsonObject, statusCode: Int): JsonObject? =
        (step.get("onStatus") as? JsonArray).orEmpty().mapNotNull { it as? JsonObject }
            .firstOrNull { statusMatches(it["match"], statusCode) }

    private fun requestUrl(request: JsonObject, profile: ProviderProfile): String {
        val url = request["url"]
        if (url is JsonPrimitive && url.isString) return url.content
        return (url as? JsonObject)?.objectValue("byRegion")?.string(profile.region.raw)
            ?: invalidSpec("request url misses profile region")
    }

    private fun requestHeaders(request: JsonObject, apiKey: String): Map<String, String> = buildMap {
        (request["headers"] as? JsonArray).orEmpty().forEach { raw ->
            val header = raw as? JsonObject ?: invalidSpec("header must be an object")
            val name = header.string("name") ?: invalidSpec("header name missing")
            val value = header.string("value") ?: invalidSpec("header value missing")
            put(name, value.replace("\${apiKey}", apiKey))
        }
    }

    private fun preprocess(apiKey: String): String {
        val credential = spec.objectValue("credential") ?: JsonObject(emptyMap())
        val key = if (credential.bool("trimWhitespace")) apiKey.trim() else apiKey
        (credential["reject"] as? JsonArray).orEmpty().forEach { raw ->
            val rule = raw as? JsonObject ?: invalidSpec("credential reject rule must be an object")
            val prefix = rule.string("prefix") ?: invalidSpec("credential reject prefix missing")
            val matches = if (rule.bool("caseInsensitive")) key.startsWith(prefix, ignoreCase = true) else key.startsWith(prefix)
            if (matches) throw ProviderFailure(rule.string("error") ?: "invalidResponse")
        }
        return key
    }

    private fun fetchSteps(): List<JsonObject> =
        (spec.objectValue("fetch")?.get("steps") as? JsonArray).orEmpty().map { raw ->
            raw as? JsonObject ?: invalidSpec("step must be an object")
        }

    private fun stepNamed(name: String): JsonObject =
        fetchSteps().firstOrNull { it.string("name") == name } ?: invalidSpec("unknown goto step '$name'")

    private fun supportedProfiles(): List<ProviderProfile> =
        (spec.objectValue("profiles")?.get("supported") as? JsonArray).orEmpty().map { raw ->
            val profile = raw as? JsonObject ?: invalidSpec("profile must be an object")
            ProviderProfile(profile.region("region"), profile.credentialKind("credentialKind"))
        }

    private fun orderedCandidates(detect: JsonObject): List<ProviderProfile> {
        val candidates = (detect["candidates"] as? JsonArray).orEmpty().map { raw ->
            val candidate = raw as? JsonObject ?: invalidSpec("candidate must be an object")
            ProviderProfile(candidate.region("region"), candidate.credentialKind("credentialKind"))
        }.toMutableList()
        val preferred = preferredRegion?.takeIf { region -> candidates.any { it.region == region } }
            ?: if (Locale.getDefault().country.equals("CN", ignoreCase = true)) ProviderRegion.CHINA else ProviderRegion.INTERNATIONAL
        candidates.indexOfFirst { it.region == preferred }.takeIf { it > 0 }?.let { index ->
            candidates.add(0, candidates.removeAt(index))
        }
        return candidates
    }

    private data class StepResult(
        val body: JsonElement,
        val fields: Map<String, EvalValue>,
        val detectedKind: CredentialKind? = null,
        val replacesPipeline: Boolean = false,
    )

    private data class PipelineResult(
        val snapshot: ProviderUsageSnapshot,
        val detectedKind: CredentialKind? = null,
    )

    private fun descriptorFor(id: ProviderId, spec: JsonObject): ProviderDescriptor {
        val descriptor = spec.objectValue("descriptor") ?: invalidSpec("descriptor missing")
        val threshold = descriptor.objectValue("supportsLowBalanceThreshold") ?: invalidSpec("threshold missing")
        val description = descriptor.objectValue("profileDescription") ?: invalidSpec("description missing")
        val undetected = description.objectValue("undetected")?.string("l10nKey") ?: "notDetected"
        val detected = description.objectValue("detected") ?: invalidSpec("detected description missing")
        return ProviderDescriptor(
            id = id,
            displayName = spec.string("displayName") ?: id.raw,
            supportsLowBalanceThreshold = { profile ->
                if ("always" in threshold) threshold.bool("always")
                else if (profile == null) threshold.bool("undetected")
                else profile.credentialKind.raw in threshold.stringList("credentialKinds")
            },
            profileDescriptionToken = { profile ->
                if (profile == null) undetected
                else when (detected.string("style")) {
                    "regionCredential" -> "regionCredential:${profile.region.raw}:${profile.credentialKind.raw}"
                    "credentialKind" -> profile.credentialKind.raw
                    else -> detected.objectValue("byRegion")?.objectValue(profile.region.raw)?.let { entry ->
                        val token = entry.string("l10nKey") ?: undetected
                        if ("credentialKind" in entry.stringList("args")) "$token:${profile.credentialKind.raw}" else token
                    } ?: undetected
                }
            },
        )
    }

    private fun validateSpec(spec: JsonObject) {
        val version = (spec["specVersion"] as? JsonPrimitive)?.content?.toIntOrNull()
        if (version != 1) invalidSpec("unsupported spec version")
        if (spec.string("displayName").isNullOrBlank()) invalidSpec("displayName missing")
        if (spec.objectValue("profiles")?.get("supported") !is JsonArray) invalidSpec("profiles supported missing")
        if (spec.objectValue("detect") == null) invalidSpec("detect missing")
        if (fetchSteps().isEmpty()) invalidSpec("fetch steps missing")
        fetchSteps().forEach { step ->
            if (step.string("name").isNullOrBlank() || step.objectValue("request") == null || step["onStatus"] !is JsonArray) {
                invalidSpec("invalid fetch step")
            }
        }
    }

    private fun invalidSpec(message: String): Nothing = throw IllegalArgumentException("invalid provider spec: $message")

    private companion object {
        val json = Json { ignoreUnknownKeys = true }
    }
}

private fun JsonObject.objectValue(name: String): JsonObject? = this[name] as? JsonObject
private fun JsonObject.string(name: String): String? = (this[name] as? JsonPrimitive)?.contentOrNull
private fun JsonObject.bool(name: String): Boolean = (this[name] as? JsonPrimitive)?.booleanOrNull == true
private fun JsonObject.stringList(name: String): List<String> = (this[name] as? JsonArray).orEmpty().mapNotNull {
    (it as? JsonPrimitive)?.contentOrNull
}
private fun JsonObject.region(name: String): ProviderRegion = ProviderRegion.fromRaw(string(name) ?: "")
    ?: throw IllegalArgumentException("invalid provider region")
private fun JsonObject.credentialKind(name: String): CredentialKind = CredentialKind.fromRaw(string(name) ?: "")
    ?: throw IllegalArgumentException("invalid credential kind")
private fun scalarKey(value: JsonElement?): String? = when (value) {
    is JsonPrimitive -> when {
        value.booleanOrNull != null -> value.booleanOrNull.toString()
        value.isString -> value.content
        else -> DecimalValue.from(value)?.canonical
    }
    else -> null
}
private fun statusMatches(match: JsonElement?, statusCode: Int): Boolean = when (match) {
    is JsonPrimitive -> when (match.content) {
        "2xx" -> statusCode in 200..299
        "default" -> true
        else -> false
    }
    is JsonArray -> match.any { (it as? JsonPrimitive)?.content?.toIntOrNull() == statusCode }
    else -> false
}
