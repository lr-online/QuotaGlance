//! Runtime for the normative provider spec schema in `Contracts/Providers`.
//!
//! This is deliberately data-driven: it evaluates the closed value,
//! condition, request and snapshot-builder vocabulary from Contracts rather
//! than adding provider-specific adapters. `miniMaxModelRemains` remains the
//! single named parse strategy.

use std::collections::HashMap;
use std::sync::Arc;

use async_trait::async_trait;
use chrono::Utc;
use rust_decimal::Decimal;
use serde_json::{Map, Value};

use crate::domain::{
    ProviderCredentialKind, ProviderID, ProviderProfile, ProviderRegion, ProviderUsageSnapshot,
    QuotaWindow,
};
use crate::providers::http_client::HttpClient;
use crate::providers::provider_error::ProviderError;
use crate::providers::usage_provider::{ProviderDescriptor, ProviderDetection, UsageProvider};

pub struct ContractProvider {
    id: ProviderID,
    spec: Value,
    descriptor: ProviderDescriptor,
    http: Arc<dyn HttpClient>,
}

impl ContractProvider {
    pub fn new(id: ProviderID, spec: Value, http: Arc<dyn HttpClient>) -> Result<Self, String> {
        let spec_id = spec.get("id").and_then(Value::as_str).ok_or("spec missing id")?;
        if spec_id != id.raw_value() {
            return Err(format!("spec id {spec_id} does not match {}", id.raw_value()));
        }
        if spec.get("specVersion").and_then(Value::as_u64) != Some(1) {
            return Err(format!("{} has unsupported specVersion", id.raw_value()));
        }
        let supports = spec
            .pointer("/descriptor/supportsLowBalanceThreshold/always")
            .and_then(Value::as_bool)
            .or_else(|| {
                spec.pointer("/descriptor/supportsLowBalanceThreshold/credentialKinds")
                    .and_then(Value::as_array)
                    .map(|kinds| !kinds.is_empty())
            })
            .unwrap_or(false);
        Ok(Self {
            id,
            spec,
            descriptor: ProviderDescriptor { supports_low_balance_threshold: supports },
            http,
        })
    }

    async fn detect_spec(&self, api_key: &str) -> Result<ProviderDetection, ProviderError> {
        let api_key = self.prepare_credential(api_key)?;
        let detect = self.spec.get("detect").ok_or(ProviderError::InvalidResponse)?;
        match detect.get("strategy").and_then(Value::as_str) {
            Some("fixedProfile") => {
                let raw = detect.get("profile").ok_or(ProviderError::InvalidResponse)?;
                let region = region_from(raw.get("region"))?;
                // OpenRouter discovers its credential kind from the first response.
                let requested_kind = raw.get("credentialKind").and_then(Value::as_str);
                let provisional = ProviderProfile::new(region, ProviderCredentialKind::Standard);
                let run = self.run_fetch(&api_key, provisional).await?;
                let kind = match requested_kind {
                    Some("detected") => run.detected_credential_kind.unwrap_or(ProviderCredentialKind::Standard),
                    Some(value) => credential_kind_from_str(value)?,
                    None => return Err(ProviderError::InvalidResponse),
                };
                Ok(ProviderDetection::new(ProviderProfile::new(region, kind), run.snapshot))
            }
            Some("regionFallback") => {
                let candidates = detect
                    .get("candidates")
                    .and_then(Value::as_array)
                    .ok_or(ProviderError::InvalidResponse)?;
                let fallback_on = detect
                    .get("fallbackOn")
                    .and_then(Value::as_array)
                    .cloned()
                    .unwrap_or_default();
                for candidate in candidates {
                    let profile = profile_from(candidate)?;
                    match self.run_fetch(&api_key, profile).await {
                        Ok(run) => return Ok(ProviderDetection::new(profile, run.snapshot)),
                        Err(error) if fallback_on.iter().any(|token| token.as_str() == Some(error.token())) => continue,
                        Err(error) => return Err(error),
                    }
                }
                Err(token_error(
                    detect.get("exhaustedError").and_then(Value::as_str).unwrap_or("regionDetectionFailed"),
                    0,
                ))
            }
            _ => Err(ProviderError::InvalidResponse),
        }
    }

    async fn fetch_spec(
        &self,
        api_key: &str,
        profile: ProviderProfile,
    ) -> Result<ProviderUsageSnapshot, ProviderError> {
        let api_key = self.prepare_credential(api_key)?;
        let is_supported = self
            .spec
            .pointer("/profiles/supported")
            .and_then(Value::as_array)
            .map(|profiles| profiles.iter().any(|candidate| profile_from(candidate).ok() == Some(profile)))
            .unwrap_or(false);
        if !is_supported {
            return Err(ProviderError::ProfileMismatch);
        }
        Ok(self.run_fetch(&api_key, profile).await?.snapshot)
    }

    fn prepare_credential(&self, raw: &str) -> Result<String, ProviderError> {
        let credential = self.spec.get("credential").ok_or(ProviderError::InvalidResponse)?;
        let key = if credential.get("trimWhitespace").and_then(Value::as_bool) == Some(true) {
            raw.trim().to_string()
        } else {
            raw.to_string()
        };
        if key.is_empty() {
            return Err(ProviderError::InvalidCredential);
        }
        for reject in credential.get("reject").and_then(Value::as_array).into_iter().flatten() {
            let Some(prefix) = reject.get("prefix").and_then(Value::as_str) else { continue };
            let insensitive = reject.get("caseInsensitive").and_then(Value::as_bool).unwrap_or(false);
            let matches = if insensitive {
                key.to_ascii_lowercase().starts_with(&prefix.to_ascii_lowercase())
            } else {
                key.starts_with(prefix)
            };
            if matches {
                return Err(token_error(reject.get("error").and_then(Value::as_str).unwrap_or("invalidResponse"), 0));
            }
        }
        Ok(key)
    }

    async fn run_fetch(&self, api_key: &str, profile: ProviderProfile) -> Result<RunResult, ProviderError> {
        let steps = self
            .spec
            .pointer("/fetch/steps")
            .and_then(Value::as_array)
            .ok_or(ProviderError::InvalidResponse)?;
        let mut index = 0usize;
        let mut forced_step = None;
        let mut bodies: HashMap<String, Value> = HashMap::new();
        let mut snapshot = ProviderUsageSnapshot { received_at: Utc::now(), ..Default::default() };
        let mut detected_credential_kind = None;

        while index < steps.len() {
            let step = &steps[index];
            let name = step.get("name").and_then(Value::as_str).ok_or(ProviderError::InvalidResponse)?;
            let is_forced = forced_step == Some(index);
            forced_step = None;
            if step.get("onDemand").and_then(Value::as_bool) == Some(true) && !is_forced {
                index += 1;
                continue;
            }
            if let Some(condition) = step.get("when") {
                if !condition_matches_step(condition, &bodies)? {
                    index += 1;
                    continue;
                }
            }

            let request = step.get("request").ok_or(ProviderError::InvalidResponse)?;
            if request.get("method").and_then(Value::as_str) != Some("GET") {
                return Err(ProviderError::InvalidResponse);
            }
            let url = resolve_url(request.get("url"), profile, api_key)?;
            let headers = request
                .get("headers")
                .and_then(Value::as_array)
                .ok_or(ProviderError::InvalidResponse)?
                .iter()
                .filter_map(|header| {
                    Some((
                        header.get("name")?.as_str()?.to_string(),
                        header.get("value")?.as_str()?.replace("${apiKey}", api_key),
                    ))
                })
                .collect::<Vec<_>>();
            let header_refs = headers.iter().map(|(name, value)| (name.as_str(), value.as_str())).collect::<Vec<_>>();
            let response = self.http.get_json(&url, &header_refs).await.map_err(|error| match error {
                crate::providers::provider_error::TransportError::Timeout => ProviderError::HttpStatus(0),
                crate::providers::provider_error::TransportError::Offline => ProviderError::HttpStatus(0),
                _ => ProviderError::InvalidResponse,
            })?;

            let action = status_action(step.get("onStatus"), response.status)?;
            match action {
                StatusAction::Parse => {}
                StatusAction::Error(token) => return Err(token_error(&token, response.status)),
                StatusAction::Goto(target) => {
                    index = steps
                        .iter()
                        .position(|candidate| candidate.get("name").and_then(Value::as_str) == Some(target.as_str()))
                        .ok_or(ProviderError::InvalidResponse)?;
                    forced_step = Some(index);
                    continue;
                }
            }

            let parse = step.get("parse").ok_or(ProviderError::InvalidResponse)?;
            run_checks(parse.get("checks"), &response.body)?;
            let values = parse_values(parse.get("values"), &response.body, profile, None)?;
            if let Some(kind_detection) = parse.get("credentialKindDetection") {
                detected_credential_kind = detect_credential_kind(kind_detection, &response.body)?;
            }
            if let Some(fields) = parse.get("snapshot").and_then(Value::as_object) {
                apply_snapshot(&mut snapshot, fields, &response.body, &values, profile)?;
            }
            bodies.insert(name.to_string(), response.body);
            index += 1;
        }

        Ok(RunResult { snapshot, detected_credential_kind })
    }
}

#[async_trait]
impl UsageProvider for ContractProvider {
    fn id(&self) -> ProviderID { self.id }
    fn descriptor(&self) -> &ProviderDescriptor { &self.descriptor }
    async fn detect(&self, api_key: &str) -> Result<ProviderDetection, ProviderError> { self.detect_spec(api_key).await }
    async fn fetch(&self, api_key: &str, profile: ProviderProfile) -> Result<ProviderUsageSnapshot, ProviderError> {
        self.fetch_spec(api_key, profile).await
    }
}

struct RunResult {
    snapshot: ProviderUsageSnapshot,
    detected_credential_kind: Option<ProviderCredentialKind>,
}

enum StatusAction { Parse, Error(String), Goto(String) }

fn status_action(branches: Option<&Value>, status: u16) -> Result<StatusAction, ProviderError> {
    let branches = branches.and_then(Value::as_array).ok_or(ProviderError::InvalidResponse)?;
    for branch in branches {
        let matches = match branch.get("match") {
            Some(Value::String(value)) if value == "2xx" => (200..300).contains(&status),
            Some(Value::String(value)) if value == "default" => true,
            Some(Value::Array(values)) => values.iter().any(|value| value.as_u64() == Some(status.into())),
            _ => false,
        };
        if !matches { continue; }
        return match branch.get("action").and_then(Value::as_str) {
            Some("parse") => Ok(StatusAction::Parse),
            Some("error") => Ok(StatusAction::Error(branch.get("error").and_then(Value::as_str).unwrap_or("invalidResponse").to_string())),
            Some("gotoStep") => Ok(StatusAction::Goto(branch.get("step").and_then(Value::as_str).ok_or(ProviderError::InvalidResponse)?.to_string())),
            _ => Err(ProviderError::InvalidResponse),
        };
    }
    Err(ProviderError::InvalidResponse)
}

fn resolve_url(raw: Option<&Value>, profile: ProviderProfile, api_key: &str) -> Result<String, ProviderError> {
    let value = match raw {
        Some(Value::String(value)) => value.clone(),
        Some(Value::Object(map)) => map
            .get("byRegion")
            .and_then(Value::as_object)
            .and_then(|regions| regions.get(profile.region.raw_value()))
            .and_then(Value::as_str)
            .map(str::to_string)
            .ok_or(ProviderError::InvalidResponse)?,
        _ => return Err(ProviderError::InvalidResponse),
    };
    Ok(value.replace("${apiKey}", api_key))
}

fn run_checks(raw: Option<&Value>, body: &Value) -> Result<(), ProviderError> {
    for check in raw.and_then(Value::as_array).into_iter().flatten() {
        if let Some(each) = check.get("eachItem").and_then(Value::as_object) {
            let items = value_at(body, each.get("of").and_then(Value::as_str).unwrap_or(""));
            let Some(items) = items.and_then(Value::as_array) else { return Err(token_error(check.get("error").and_then(Value::as_str).unwrap_or("invalidResponse"), 0)); };
            for item in items {
                let value = value_at(item, each.get("path").and_then(Value::as_str).unwrap_or(""));
                ensure_check(value, each, check.get("error").and_then(Value::as_str).unwrap_or("invalidResponse"))?;
            }
        } else {
            let value = value_at(body, check.get("path").and_then(Value::as_str).unwrap_or(""));
            ensure_check(value, check.as_object().ok_or(ProviderError::InvalidResponse)?, check.get("error").and_then(Value::as_str).unwrap_or("invalidResponse"))?;
        }
    }
    Ok(())
}

fn ensure_check(value: Option<&Value>, check: &Map<String, Value>, fallback_error: &str) -> Result<(), ProviderError> {
    let parsed = match (value, check.get("type").and_then(Value::as_str)) {
        (Some(value), Some(kind)) => parse_typed(value, kind),
        (Some(value), None) => Some(value.clone()),
        (None, _) => None,
    };
    if check.get("required").and_then(Value::as_bool) == Some(true) && parsed.is_none() {
        return Err(token_error(fallback_error, 0));
    }
    if check.get("strict").and_then(Value::as_bool) == Some(true) && value.is_some() && parsed.is_none() {
        return Err(token_error(fallback_error, 0));
    }
    if check.get("nonEmpty").and_then(Value::as_bool) == Some(true) && parsed.as_ref().is_some_and(is_empty) {
        return Err(token_error(fallback_error, 0));
    }
    if let (Some(condition), Some(parsed)) = (check.get("when"), parsed.as_ref()) {
        if condition_matches_value(condition, parsed)? {
            return Err(token_error(fallback_error, 0));
        }
    }
    Ok(())
}

fn parse_values(
    raw: Option<&Value>,
    body: &Value,
    profile: ProviderProfile,
    inherited_values: Option<&HashMap<String, Value>>,
) -> Result<HashMap<String, Value>, ProviderError> {
    let mut values = inherited_values.cloned().unwrap_or_default();
    for (name, expr) in raw.and_then(Value::as_object).into_iter().flatten() {
        if let Some(value) = build_value(expr, body, &values, profile)? {
            values.insert(name.clone(), value);
        }
    }
    Ok(values)
}

fn apply_snapshot(
    snapshot: &mut ProviderUsageSnapshot,
    fields: &Map<String, Value>,
    body: &Value,
    values: &HashMap<String, Value>,
    profile: ProviderProfile,
) -> Result<(), ProviderError> {
    for (field, builder) in fields {
        let Some(value) = build_value(builder, body, values, profile)? else { continue };
        let normalized = snake_case_json(value);
        match field.as_str() {
            "balances" => snapshot.balances = serde_json::from_value(normalized).map_err(|_| ProviderError::InvalidResponse)?,
            "spendingLimit" => snapshot.spending_limit = serde_json::from_value(normalized).map_err(|_| ProviderError::InvalidResponse)?,
            "spend" => snapshot.spend = serde_json::from_value(normalized).map_err(|_| ProviderError::InvalidResponse)?,
            "quotaWindows" => snapshot.quota_windows = serde_json::from_value(normalized).map_err(|_| ProviderError::InvalidResponse)?,
            "today" => snapshot.today = serde_json::from_value(normalized).map_err(|_| ProviderError::InvalidResponse)?,
            "total" => snapshot.total = serde_json::from_value(normalized).map_err(|_| ProviderError::InvalidResponse)?,
            "dailyUsage" => snapshot.daily_usage = serde_json::from_value(normalized).map_err(|_| ProviderError::InvalidResponse)?,
            "modelUsage" => snapshot.model_usage = serde_json::from_value(normalized).map_err(|_| ProviderError::InvalidResponse)?,
            "providerStatus" => snapshot.provider_status = normalized.as_str().map(str::to_string),
            "metricsUnavailableReason" => snapshot.metrics_unavailable_reason = normalized.as_str().map(str::to_string),
            _ => return Err(ProviderError::InvalidResponse),
        }
    }
    Ok(())
}

fn build_value(
    expr: &Value,
    body: &Value,
    values: &HashMap<String, Value>,
    profile: ProviderProfile,
) -> Result<Option<Value>, ProviderError> {
    let Some(map) = expr.as_object() else { return Ok(Some(expr.clone())); };
    if let Some(condition) = map.get("when") {
        if !condition_matches_value(condition, body)? { return Ok(None); }
        if let Some(value) = map.get("value") { return build_value(value, body, values, profile); }
        if let Some(object) = map.get("object") { return build_object(object, body, values, profile); }
    }
    if let Some(money) = map.get("money").and_then(Value::as_object) {
        let amount = money.get("amount").and_then(|value| build_value(value, body, values, profile).transpose()).transpose()?;
        let currency = money.get("currency").and_then(|value| build_value(value, body, values, profile).transpose()).transpose()?;
        let (Some(amount), Some(currency)) = (amount, currency) else { return Ok(None); };
        return Ok(Some(serde_json::json!({ "amount": amount, "currency": currency })));
    }
    if let Some(template) = map.get("template").and_then(Value::as_str) {
        let mut output = template.to_string();
        for (name, value) in values {
            output = output.replace(&format!("${{{name}}}"), &display_value(value));
        }
        return if output.contains("${") { Ok(None) } else { Ok(Some(Value::String(output))) };
    }
    if let Some(mapped) = map.get("map").and_then(Value::as_object) {
        let source = map.get("path").and_then(Value::as_str).and_then(|path| value_at(body, path));
        return Ok(source.and_then(|value| mapped.get(&value_key(value))).cloned());
    }
    if let Some(items_path) = map.get("fromArray").and_then(Value::as_str) {
        let mut out = Vec::new();
        for item in value_at(body, items_path).and_then(Value::as_array).into_iter().flatten() {
            if map.get("skipItemWhen").is_some_and(|condition| condition_matches_value(condition, item).unwrap_or(false)) { continue; }
            let item_values = parse_values(map.get("itemValues"), item, profile, Some(values))?;
            if let Some(value) = build_object(map.get("item").ok_or(ProviderError::InvalidResponse)?, item, &item_values, profile)? {
                out.push(value);
            }
        }
        return Ok(Some(Value::Array(out)));
    }
    if let Some(fixed) = map.get("fixed").and_then(Value::as_array) {
        let mut out = Vec::new();
        for item in fixed {
            if let Some(value) = build_object(item, body, values, profile)? { out.push(value); }
        }
        return Ok(Some(Value::Array(out)));
    }
    if map.get("strategy").and_then(Value::as_str) == Some("miniMaxModelRemains") {
        let source = value_at(body, map.get("path").and_then(Value::as_str).unwrap_or(""));
        let Some(source) = source else { return Err(ProviderError::InvalidResponse); };
        if map.get("requireNonEmpty").and_then(Value::as_bool) == Some(true) && source.as_array().is_some_and(Vec::is_empty) {
            return Err(ProviderError::InvalidResponse);
        }
        let windows = mini_max_quota_windows(source)?;
        return serde_json::to_value(windows).map(Some).map_err(|_| ProviderError::InvalidResponse);
    }
    if map.get("object").is_some() { return build_object(map.get("object").unwrap(), body, values, profile); }
    eval_expression(map, body, values, profile)
}

fn build_object(
    raw: &Value,
    body: &Value,
    values: &HashMap<String, Value>,
    profile: ProviderProfile,
) -> Result<Option<Value>, ProviderError> {
    let map = raw.as_object().ok_or(ProviderError::InvalidResponse)?;
    if let Some(condition) = map.get("when") {
        if !condition_matches_value(condition, body)? { return Ok(None); }
    }
    let mut out = Map::new();
    for (name, expr) in map {
        if name == "when" { continue; }
        if let Some(value) = build_value(expr, body, values, profile)? { out.insert(name.clone(), value); }
    }
    Ok(Some(Value::Object(out)))
}

fn eval_expression(
    map: &Map<String, Value>,
    body: &Value,
    values: &HashMap<String, Value>,
    profile: ProviderProfile,
) -> Result<Option<Value>, ProviderError> {
    if let Some(value) = map.get("literal") { return Ok(Some(value.clone())); }
    if let Some(name) = map.get("value").and_then(Value::as_str) { return Ok(values.get(name).cloned()); }
    if let Some(regions) = map.get("byRegion").and_then(Value::as_object) {
        return Ok(regions.get(profile.region.raw_value()).cloned());
    }
    if map.get("op").and_then(Value::as_str) == Some("count") {
        let count = map.get("path").and_then(Value::as_str).and_then(|path| value_at(body, path)).and_then(Value::as_array).map(|items| items.len() as i64);
        return Ok(count.map(serde_json::Number::from).map(Value::Number));
    }
    if map.get("op").and_then(Value::as_str) == Some("subtract") {
        let a = map.get("a").and_then(|value| build_value(value, body, values, profile).transpose()).transpose()?;
        let b = map.get("b").and_then(|value| build_value(value, body, values, profile).transpose()).transpose()?;
        let (Some(a), Some(b)) = (a, b) else { return Ok(None); };
        let a = decimal_from_value(&a).ok_or(ProviderError::InvalidResponse)?;
        let b = decimal_from_value(&b).ok_or(ProviderError::InvalidResponse)?;
        return Ok(Some(Value::String((a - b).normalize().to_string())));
    }
    if let Some(path) = map.get("path").and_then(Value::as_str) {
        let value = value_at(body, path).and_then(|value| {
            map.get("type").and_then(Value::as_str).map_or_else(|| Some(value.clone()), |kind| parse_typed(value, kind))
        });
        if value.is_none() && map.get("required").and_then(Value::as_bool) == Some(true) {
            return Err(ProviderError::InvalidResponse);
        }
        let value = value.map(|value| apply_transforms(value, map.get("transforms")));
        if map.get("nonEmpty").and_then(Value::as_bool) == Some(true) && value.as_ref().is_some_and(is_empty) {
            return Err(ProviderError::InvalidResponse);
        }
        if map.get("nullIfEmpty").and_then(Value::as_bool) == Some(true) && value.as_ref().is_some_and(is_empty) { return Ok(None); }
        return Ok(value);
    }
    Ok(None)
}

fn condition_matches_step(condition: &Value, bodies: &HashMap<String, Value>) -> Result<bool, ProviderError> {
    let step = condition.get("step").and_then(Value::as_str).ok_or(ProviderError::InvalidResponse)?;
    condition_matches_value(condition, bodies.get(step).ok_or(ProviderError::InvalidResponse)?)
}

fn condition_matches_value(condition: &Value, body: &Value) -> Result<bool, ProviderError> {
    let map = condition.as_object().ok_or(ProviderError::InvalidResponse)?;
    if let Some(items) = map.get("any").and_then(Value::as_array) {
        return Ok(items.iter().any(|item| condition_matches_value(item, body).unwrap_or(false)));
    }
    if let Some(items) = map.get("all").and_then(Value::as_array) {
        return Ok(items.iter().all(|item| condition_matches_value(item, body).unwrap_or(false)));
    }
    let value = map
        .get("path")
        .and_then(Value::as_str)
        .and_then(|path| value_at(body, path))
        .or_else(|| (!body.is_object()).then_some(body));
    if let Some(exists) = map.get("exists").and_then(Value::as_bool) { return Ok(value.is_some() == exists); }
    let Some(value) = value else { return Ok(false); };
    if let Some(expected) = map.get("equals") { return Ok(values_equal(value, expected)); }
    if let Some(expected) = map.get("notEquals") { return Ok(!values_equal(value, expected)); }
    if let Some(expected) = map.get("lt").and_then(decimal_from_value) { return Ok(decimal_from_value(value).is_some_and(|actual| actual < expected)); }
    if let Some(expected) = map.get("gt").and_then(decimal_from_value) { return Ok(decimal_from_value(value).is_some_and(|actual| actual > expected)); }
    Ok(false)
}

fn detect_credential_kind(raw: &Value, body: &Value) -> Result<Option<ProviderCredentialKind>, ProviderError> {
    let source = raw.get("path").and_then(Value::as_str).and_then(|path| value_at(body, path));
    let Some(source) = source else { return Ok(None); };
    let kind = raw.get("map").and_then(Value::as_object).and_then(|map| map.get(&value_key(source))).and_then(Value::as_str);
    kind.map(credential_kind_from_str).transpose()
}

fn value_at<'a>(value: &'a Value, path: &str) -> Option<&'a Value> {
    if path.is_empty() { return Some(value); }
    let mut current = value;
    for segment in path.split('.') {
        current = current.as_object()?.get(segment)?;
        if current.is_null() { return None; }
    }
    Some(current)
}

fn parse_typed(value: &Value, kind: &str) -> Option<Value> {
    match kind {
        "decimal" => canonical_decimal(value).map(Value::String),
        "string" => value.as_str().map(|value| Value::String(value.to_string())),
        "int" => value.as_i64().or_else(|| value.as_str()?.trim().parse().ok()).map(serde_json::Number::from).map(Value::Number),
        "bool" => value.as_bool().map(Value::Bool),
        _ => None,
    }
}

fn canonical_decimal(value: &Value) -> Option<String> {
    match value {
        Value::String(value) if Decimal::from_str_exact(value.trim()).is_ok() => Some(value.trim().to_string()),
        Value::Number(value) if Decimal::from_str_exact(&value.to_string()).is_ok() => Some(value.to_string()),
        _ => None,
    }
}

fn decimal_from_value(value: &Value) -> Option<Decimal> {
    canonical_decimal(value).and_then(|value| Decimal::from_str_exact(&value).ok())
}

fn apply_transforms(value: Value, raw: Option<&Value>) -> Value {
    let Some(mut text) = value.as_str().map(str::to_string) else { return value; };
    for transform in raw.and_then(Value::as_array).into_iter().flatten().filter_map(Value::as_str) {
        match transform {
            "trim" => text = text.trim().to_string(),
            "uppercase" => text = text.to_uppercase(),
            _ => {}
        }
    }
    Value::String(text)
}

fn is_empty(value: &Value) -> bool {
    value.as_str().is_some_and(|value| value.is_empty()) || value.as_array().is_some_and(Vec::is_empty)
}

fn value_key(value: &Value) -> String {
    match value { Value::Bool(value) => value.to_string(), Value::String(value) => value.clone(), _ => value.to_string() }
}

fn display_value(value: &Value) -> String {
    value.as_str().map(str::to_string).unwrap_or_else(|| value.to_string())
}

fn values_equal(actual: &Value, expected: &Value) -> bool {
    if actual == expected { return true; }
    match (decimal_from_value(actual), decimal_from_value(expected)) { (Some(a), Some(b)) => a == b, _ => false }
}

fn token_error(token: &str, status: u16) -> ProviderError {
    match token {
        "invalidCredential" => ProviderError::InvalidCredential,
        "rateLimited" => ProviderError::RateLimited,
        "httpStatus" => ProviderError::HttpStatus(status),
        "providerInactive" => ProviderError::ProviderInactive,
        "unsupportedCredential" => ProviderError::UnsupportedCredential,
        "regionDetectionFailed" => ProviderError::RegionDetectionFailed,
        "profileMismatch" => ProviderError::ProfileMismatch,
        _ => ProviderError::InvalidResponse,
    }
}

fn region_from(value: Option<&Value>) -> Result<ProviderRegion, ProviderError> {
    match value.and_then(Value::as_str) {
        Some("global") => Ok(ProviderRegion::Global),
        Some("china") => Ok(ProviderRegion::China),
        Some("international") => Ok(ProviderRegion::International),
        _ => Err(ProviderError::InvalidResponse),
    }
}

fn credential_kind_from_str(value: &str) -> Result<ProviderCredentialKind, ProviderError> {
    match value {
        "standard" => Ok(ProviderCredentialKind::Standard),
        "management" => Ok(ProviderCredentialKind::Management),
        "tokenPlan" => Ok(ProviderCredentialKind::TokenPlan),
        _ => Err(ProviderError::InvalidResponse),
    }
}

fn profile_from(value: &Value) -> Result<ProviderProfile, ProviderError> {
    Ok(ProviderProfile::new(region_from(value.get("region"))?, credential_kind_from_str(value.get("credentialKind").and_then(Value::as_str).ok_or(ProviderError::InvalidResponse)?)?))
}

fn snake_case_json(value: Value) -> Value {
    match value {
        Value::Array(items) => Value::Array(items.into_iter().map(snake_case_json).collect()),
        Value::Object(items) => Value::Object(items.into_iter().map(|(key, value)| (snake_case(&key), snake_case_json(value))).collect()),
        value => value,
    }
}

fn snake_case(value: &str) -> String {
    let mut out = String::new();
    for (index, character) in value.chars().enumerate() {
        if character.is_ascii_uppercase() {
            if index > 0 { out.push('_'); }
            out.push(character.to_ascii_lowercase());
        } else { out.push(character); }
    }
    out
}

fn mini_max_quota_windows(source: &Value) -> Result<Vec<QuotaWindow>, ProviderError> {
    let items = source.as_array().ok_or(ProviderError::InvalidResponse)?;
    if items.is_empty() { return Err(ProviderError::InvalidResponse); }
    let mut windows = Vec::new();
    for item in items {
        let Some(object) = item.as_object() else { return Err(ProviderError::InvalidResponse); };
        if let (Some(model), Some(used), Some(limit), Some(end)) = (
            object.get("model_name").and_then(Value::as_str),
            object.get("current_interval_usage_count").and_then(decimal_from_value),
            object.get("current_interval_total_count").and_then(decimal_from_value),
            object.get("end_time").and_then(Value::as_i64),
        ) {
            let (used, limit, remaining, unit) = if limit.is_zero() {
                let remaining = object.get("current_interval_remaining_percent").and_then(decimal_from_value).ok_or(ProviderError::InvalidResponse)?;
                (Decimal::from(100) - remaining, Decimal::from(100), remaining, "%")
            } else {
                (used, limit, limit - used, "requests")
            };
            windows.push(QuotaWindow {
                label: format!("{model} 5-hour quota"), used: Some(used), limit: Some(limit), remaining: Some(remaining), unit: unit.to_string(),
                resets_at: chrono::DateTime::from_timestamp(end, 0),
            });
        }
        if object.get("current_weekly_status").and_then(Value::as_i64) == Some(1) {
            let model = object.get("model_name").and_then(Value::as_str).ok_or(ProviderError::InvalidResponse)?;
            let used = object.get("current_weekly_usage_count").and_then(decimal_from_value).ok_or(ProviderError::InvalidResponse)?;
            let limit = object.get("current_weekly_total_count").and_then(decimal_from_value).ok_or(ProviderError::InvalidResponse)?;
            let reset = object.get("weekly_end_time").and_then(Value::as_i64).and_then(chrono::DateTime::from_timestamp_millis);
            windows.push(QuotaWindow { label: format!("{model} weekly quota"), used: Some(used), limit: Some(limit), remaining: Some(limit - used), unit: "requests".to_string(), resets_at: reset });
        }
        if let (Some(label), Some(limit), Some(remaining)) = (
            object.get("label").and_then(Value::as_str), object.get("total").and_then(decimal_from_value), object.get("remains").and_then(decimal_from_value),
        ) {
            let reset = object.get("reset_time").and_then(Value::as_i64).and_then(|seconds| chrono::DateTime::from_timestamp(seconds, 0));
            windows.push(QuotaWindow { label: label.to_string(), used: Some(limit - remaining), limit: Some(limit), remaining: Some(remaining), unit: object.get("unit").and_then(Value::as_str).unwrap_or("requests").to_string(), resets_at: reset });
        }
    }
    if windows.is_empty() { Err(ProviderError::InvalidResponse) } else { Ok(windows) }
}

pub fn provider_catalog(http: Arc<dyn HttpClient>) -> Result<HashMap<ProviderID, Arc<dyn UsageProvider>>, String> {
    let sources = [
        (ProviderID::ApiInfo, include_str!("../../assets/providerspecs/apiInfo.json")),
        (ProviderID::DeepSeek, include_str!("../../assets/providerspecs/deepSeek.json")),
        (ProviderID::Kimi, include_str!("../../assets/providerspecs/kimi.json")),
        (ProviderID::OpenRouter, include_str!("../../assets/providerspecs/openRouter.json")),
        (ProviderID::MiniMax, include_str!("../../assets/providerspecs/miniMax.json")),
        (ProviderID::BioMapCoding, include_str!("../../assets/providerspecs/bioMapCoding.json")),
    ];
    let mut providers: HashMap<ProviderID, Arc<dyn UsageProvider>> = HashMap::new();
    for (id, source) in sources {
        let spec = serde_json::from_str(source).map_err(|error| format!("{} spec JSON: {error}", id.raw_value()))?;
        providers.insert(id, Arc::new(ContractProvider::new(id, spec, http.clone())?));
    }
    Ok(providers)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::providers::http_client::{RawResponse, ReqwestHttpClient};

    #[derive(Clone)]
    struct StubHttpClient {
        response: RawResponse,
    }

    #[async_trait::async_trait]
    impl HttpClient for StubHttpClient {
        async fn get_json(
            &self,
            _url: &str,
            _headers: &[(&str, &str)],
        ) -> Result<RawResponse, crate::providers::provider_error::TransportError> {
            Ok(self.response.clone())
        }
    }

    #[tokio::test]
    async fn api_info_array_items_inherit_step_values() {
        let response = serde_json::from_str(include_str!(
            "../../assets/contracts/Providers/apiinfo/usage-response.json"
        ))
        .expect("parse API Info contract fixture");
        let http = Arc::new(StubHttpClient {
            response: RawResponse { status: 200, body: response },
        });
        let spec: Value = serde_json::from_str(include_str!("../../assets/providerspecs/apiInfo.json"))
            .expect("parse API Info spec");
        let provider = ContractProvider::new(ProviderID::ApiInfo, spec, http)
            .expect("create API Info provider");

        let snapshot = provider
            .fetch(
                "redacted-test-key",
                ProviderProfile::new(ProviderRegion::Global, ProviderCredentialKind::Standard),
            )
            .await
            .expect("API Info contract fixture must parse");

        assert_eq!(snapshot.daily_usage.len(), 2);
        assert_eq!(snapshot.daily_usage[0].actual_cost.amount, "12.34");
        assert_eq!(snapshot.model_usage.len(), 2);
        assert_eq!(snapshot.model_usage[0].actual_cost.as_ref().map(|cost| cost.currency.as_str()), Some("USD"));
    }

    #[tokio::test]
    #[ignore = "requires QUOTAGLANCE_API_INFO_TEST_KEY and live network access"]
    async fn api_info_live_response_matches_contract() {
        let api_key = std::env::var("QUOTAGLANCE_API_INFO_TEST_KEY")
            .expect("set QUOTAGLANCE_API_INFO_TEST_KEY before running this ignored smoke test");
        let http = Arc::new(ReqwestHttpClient::new().expect("create HTTP transport"));
        let spec: Value = serde_json::from_str(include_str!("../../assets/providerspecs/apiInfo.json"))
            .expect("parse API Info spec");
        let provider = ContractProvider::new(ProviderID::ApiInfo, spec, http.clone())
            .expect("create API Info provider");
        let profile = ProviderProfile::new(ProviderRegion::Global, ProviderCredentialKind::Standard);

        let detection = provider
            .detect(&api_key)
            .await
            .expect("API Info live response must satisfy its contract");

        assert_eq!(detection.profile, profile);
        assert_eq!(detection.snapshot.balances.len(), 1);
        assert!(!detection.snapshot.balances[0].available.amount.is_empty());
    }
}
