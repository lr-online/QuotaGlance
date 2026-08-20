use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub enum ServiceStatusLevel { Operational, Degraded, Outage, Unknown }

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ServiceStatusComponent { pub name: String, pub status: ServiceStatusLevel }

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ServiceStatusIncident { pub title: String, pub status: String, pub url: Option<String> }

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct OpenAIServiceStatus {
    pub source: String,
    pub available: bool,
    pub overall: Option<ServiceStatusLevel>,
    pub summary: Option<String>,
    pub affected_components: Vec<ServiceStatusComponent>,
    pub active_incidents: Vec<ServiceStatusIncident>,
}

pub fn parse(body: &serde_json::Value) -> OpenAIServiceStatus {
    let status = body.get("status");
    let summary = status.and_then(|s| s.get("description")).and_then(|v| v.as_str()).map(str::trim).filter(|v| !v.is_empty()).map(str::to_owned);
    let Some(summary) = summary else { return unavailable(); };
    let overall = status.and_then(|s| s.get("indicator")).and_then(|v| v.as_str()).map(overall_level);
    let affected_components = body.get("components").and_then(|v| v.as_array()).into_iter().flatten().filter_map(|component| {
        let name = component.get("name")?.as_str()?.trim();
        let level = component.get("status").and_then(|v| v.as_str()).map(component_level).unwrap_or(ServiceStatusLevel::Unknown);
        (level != ServiceStatusLevel::Operational).then(|| ServiceStatusComponent { name: name.to_owned(), status: level })
    }).collect();
    let active_incidents = body.get("incidents").and_then(|v| v.as_array()).into_iter().flatten().filter_map(|incident| {
        let title = incident.get("name")?.as_str()?.to_owned();
        let status = incident.get("status")?.as_str()?.to_owned();
        if status == "resolved" { return None; }
        Some(ServiceStatusIncident { title, status, url: incident.get("shortlink").and_then(|v| v.as_str()).map(str::to_owned) })
    }).collect();
    OpenAIServiceStatus { source: "openAI".into(), available: true, overall, summary: Some(summary), affected_components, active_incidents }
}

fn unavailable() -> OpenAIServiceStatus { OpenAIServiceStatus { source: "openAI".into(), available: false, overall: None, summary: None, affected_components: vec![], active_incidents: vec![] } }
fn overall_level(value: &str) -> ServiceStatusLevel { match value { "none" => ServiceStatusLevel::Operational, "minor" => ServiceStatusLevel::Degraded, "major" | "critical" => ServiceStatusLevel::Outage, _ => ServiceStatusLevel::Unknown } }
fn component_level(value: &str) -> ServiceStatusLevel { match value { "operational" => ServiceStatusLevel::Operational, "degraded_performance" | "partial_outage" => ServiceStatusLevel::Degraded, "major_outage" => ServiceStatusLevel::Outage, _ => ServiceStatusLevel::Unknown } }

pub async fn fetch() -> OpenAIServiceStatus {
    let client = match reqwest::Client::builder().timeout(std::time::Duration::from_secs(10)).build() { Ok(client) => client, Err(_) => return unavailable() };
    let response = match client.get("https://status.openai.com/api/v2/summary.json").header("Accept", "application/json").send().await { Ok(response) => response, Err(_) => return unavailable() };
    if !response.status().is_success() { return unavailable(); }
    match response.json::<serde_json::Value>().await { Ok(body) => parse(&body), Err(_) => unavailable() }
}

#[cfg(test)]
mod tests { use super::*; #[test] fn maps_degraded_fixture() { let body: serde_json::Value = serde_json::from_str(include_str!("../assets/contracts/servicestatus/openai-degraded-response.json")).unwrap(); let status = parse(&body); assert_eq!(status.overall, Some(ServiceStatusLevel::Degraded)); assert_eq!(status.affected_components.len(), 2); assert_eq!(status.active_incidents.len(), 1); } }
