package com.liangrui.quotaglance.core

import org.json.JSONObject

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
    val root = JSONObject(body)
    val status = root.optJSONObject("status") ?: return OpenAIServiceStatus(false)
    val summary = status.optString("description").trim()
    if (summary.isEmpty()) return OpenAIServiceStatus(false)
    val components = buildList {
        val values = root.optJSONArray("components") ?: return@buildList
        for (index in 0 until values.length()) {
            val component = values.optJSONObject(index) ?: continue
            val level = componentLevel(component.optString("status"))
            if (level != ServiceStatusLevel.Operational) {
                add(ServiceStatusComponent(component.optString("name"), level))
            }
        }
    }
    val incidents = buildList {
        val values = root.optJSONArray("incidents") ?: return@buildList
        for (index in 0 until values.length()) {
            val incident = values.optJSONObject(index) ?: continue
            val state = incident.optString("status")
            if (state.isNotBlank() && state != "resolved") {
                add(ServiceStatusIncident(incident.optString("name"), state, incident.optString("shortlink").ifBlank { null }))
            }
        }
    }
    return OpenAIServiceStatus(
        available = true,
        overall = overallLevel(status.optString("indicator")),
        summary = summary,
        affectedComponents = components,
        activeIncidents = incidents,
    )
}

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
