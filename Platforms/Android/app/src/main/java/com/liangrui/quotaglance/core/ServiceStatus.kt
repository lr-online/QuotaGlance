package com.liangrui.quotaglance.core

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

enum class ServiceStatusLevel { Operational, Degraded, Outage, Unknown }
data class ServiceStatusComponent(val name: String, val status: ServiceStatusLevel)
data class ServiceStatusIncident(val title: String, val status: String, val url: String?)
data class OpenAIServiceStatus(
    val available: Boolean,
    val source: String = "openAI",
    val overall: ServiceStatusLevel? = null,
    val summary: String? = null,
    val affectedComponents: List<ServiceStatusComponent> = emptyList(),
    val activeIncidents: List<ServiceStatusIncident> = emptyList(),
)

fun parseOpenAIServiceStatus(body: String): OpenAIServiceStatus {
    val root = Json.parseToJsonElement(body) as? JsonObject ?: return OpenAIServiceStatus(false)
    val status = root["status"] as? JsonObject ?: return OpenAIServiceStatus(false)
    val summary = status.stringValue("description").trim()
    if (summary.isEmpty()) return OpenAIServiceStatus(false)
    val components = buildList {
        val values = root["components"] as? JsonArray ?: return@buildList
        for (componentElement in values) {
            val component = componentElement as? JsonObject ?: continue
            val level = componentLevel(component.stringValue("status"))
            if (level != ServiceStatusLevel.Operational) {
                add(ServiceStatusComponent(component.stringValue("name"), level))
            }
        }
    }
    val incidents = buildList {
        val values = root["incidents"] as? JsonArray ?: return@buildList
        for (incidentElement in values) {
            val incident = incidentElement as? JsonObject ?: continue
            val state = incident.stringValue("status")
            if (state.isNotBlank() && state != "resolved") {
                add(ServiceStatusIncident(
                    incident.stringValue("name"),
                    state,
                    incident.stringValue("shortlink").ifBlank { null },
                ))
            }
        }
    }
    return OpenAIServiceStatus(
        available = true,
        overall = overallLevel(status.stringValue("indicator")),
        summary = summary,
        affectedComponents = components,
        activeIncidents = incidents,
    )
}

private fun JsonObject.stringValue(key: String) = (this[key] as? JsonPrimitive)?.content.orEmpty()

private fun overallLevel(value: String) = when (value) {
    "none" -> ServiceStatusLevel.Operational
    "minor" -> ServiceStatusLevel.Degraded
    "major", "critical" -> ServiceStatusLevel.Outage
    else -> ServiceStatusLevel.Unknown
}

private fun componentLevel(value: String) = when (value) {
    "operational" -> ServiceStatusLevel.Operational
    "degraded_performance", "partial_outage" -> ServiceStatusLevel.Degraded
    "major_outage" -> ServiceStatusLevel.Outage
    else -> ServiceStatusLevel.Unknown
}
