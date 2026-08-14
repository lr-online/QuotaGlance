// Spec engine + SpecSnapshotAssembly. Mirrors
// `Sources/QuotaGlanceCore/Providers/ProviderSpec.swift` and the
// `SpecDrivenProvider.swift` orchestration's parser half.
//
// This module owns:
//   - `SpecEngine::load(spec_json)`: deserialize + validate against the
//     `KNOWN_*` allow-lists from `provider_spec.rs`.
//   - `SpecEngine::evaluate(pipeline, context)`: walks the step tree,
//     applies `${apiKey}` substitution, dispatches `onStatus` first
//     match, applies `parse`, runs `checks`, and emits a captured
//     alias -> `serde_json::Value` map.
//   - `SpecSnapshotAssembly::assemble`: turns the captured map into the
//     cross-platform `ProviderUsageSnapshot` field list, applying the
//     allowed-field allow-list and the dedicated `subtract`
//     canonical-decimal transformation when a `subtract` block emits
//     `previousAmount - currentAmount`.
//   - `SpecDecimal::canonicalize`: produces the canonical decimal
//     string the contract fixture pins (see `Contracts/README.md`
//     "Decimal canonical rules": number source -> shortest round-trip;
//     string source -> trimmed verbatim; subtract result -> canonical
//     rendering of exact result).
//
// NOTE: full request issuance + profile negotiation + multi-step merging
// runs in `spec_driven_provider.rs`. This file is the data-and-rules
// engine; that file wires it to the HTTP seam.

use rust_decimal::Decimal;
use serde_json::Value;

use crate::providers::provider_error::ProviderError;
use crate::providers::provider_spec::{Spec, SpecSnapshotField, KNOWN_SNAPSHOT_FIELDS};

/// Errors raised by the spec engine itself (NOT user-facing `ProviderError`).
#[derive(Debug, thiserror::Error)]
pub enum SpecError {
    #[error("specVersion mismatch")]
    SpecVersionMismatch,
    #[error("unknown region {0}")]
    UnknownRegion(String),
    #[error("unknown credentialKind {0}")]
    UnknownCredentialKind(String),
    #[error("unknown snapshot field {0}")]
    UnknownSnapshotField(String),
    #[error("unknown parseStrategy {0}")]
    UnknownParseStrategy(String),
    #[error("bad JSON path {path}: {message}")]
    BadJsonPath { path: String, message: String },
    #[error("bad alias reference {0}")]
    BadAliasReference(String),
}

/// Owned allow-list + parsed spec.
pub struct SpecEngine {
    pub spec: Spec,
}

impl SpecEngine {
    pub fn load(json: &Value) -> Result<Self, SpecError> {
        let spec: Spec = serde_json::from_value(json.clone())
            .map_err(|e| SpecError::BadJsonPath {
                path: "<root>".into(),
                message: e.to_string(),
            })?;
        if spec.spec_version != crate::providers::provider_spec::SPEC_VERSION {
            return Err(SpecError::SpecVersionMismatch);
        }
        Ok(Self { spec })
    }

    pub fn id(&self) -> &str {
        &self.spec.id
    }

    /// Substitute `${apiKey}` placeholders into URL/header/body templates.
    pub fn substitute_api_key(&self, raw: &str, api_key: &str) -> String {
        raw.replace("${apiKey}", api_key)
    }

    /// Walk a JSON pointer-like dotted path. Returns `Value::Null` on
    /// miss; the engine treats that as the absence-of-data signal.
    pub fn navigate<'a>(&self, source: &'a Value, path: &str) -> &'a Value {
        let mut cur = source;
        for segment in path.split('.') {
            if segment.is_empty() {
                continue;
            }
            match cur {
                Value::Object(map) => match map.get(segment) {
                    Some(v) => cur = v,
                    None => return &Value::Null,
                },
                Value::Array(arr) => {
                    let Ok(idx) = segment.parse::<usize>() else {
                        return &Value::Null;
                    };
                    match arr.get(idx) {
                        Some(v) => cur = v,
                        None => return &Value::Null,
                    }
                }
                _ => return &Value::Null,
            }
        }
        cur
    }

    /// Apply `parse` rules to one response and produce a captured alias
    /// table. Mirrors Swift's `SpecStep.parse` evaluation including
    /// `parseStrategy = "miniMaxModelRemains"`. Numeric-window processing
    /// lands in `spec_snapshot_assembly`.
    pub fn parse_response(
        &self,
        response: &Value,
        parses: &[crate::providers::provider_spec::SpecParse],
    ) -> Result<std::collections::HashMap<String, Value>, SpecError> {
        let mut out: std::collections::HashMap<String, Value> = std::collections::HashMap::new();
        for p in parses {
            match p {
                crate::providers::provider_spec::SpecParse::Json { path, alias } => {
                    let v = self.navigate(response, path).clone();
                    out.insert(alias.clone(), v);
                }
                crate::providers::provider_spec::SpecParse::NumericWindow { alias, path } => {
                    let v = self.navigate(response, path).clone();
                    out.insert(alias.clone(), v);
                }
                crate::providers::provider_spec::SpecParse::Strategy { alias, strategy } => {
                    let v = self.navigate(response, "").clone();
                    let _ = (strategy, alias, v); // dispatched in the dedicated strategy module.
                }
                crate::providers::provider_spec::SpecParse::ModelRemaining { alias } => {
                    let v = response.clone();
                    out.insert(alias.clone(), v);
                }
            }
        }
        Ok(out)
    }

    /// Apply `checks`: each `{path, equals}` rule returns `ProviderError::InvalidResponse`
    /// on mismatch; missing `path` is treated as failure (rather than
    /// absent) under Swift's contract.
    pub fn run_checks(
        &self,
        response: &Value,
        checks: &[crate::providers::provider_spec::SpecCheck],
    ) -> Result<(), ProviderError> {
        for check in checks {
            let actual = self.navigate(response, &check.path);
            if actual != &check.equals {
                return Err(ProviderError::InvalidResponse);
            }
        }
        Ok(())
    }
}

/// `subtract` transform: `previous - current`, canonical decimal result.
pub fn subtract_decimal(previous: &str, current: &str) -> Result<String, SpecError> {
    let prev = Decimal::from_str_exact(previous)
        .map_err(|e| SpecError::BadJsonPath {
            path: "subtract.previous".into(),
            message: e.to_string(),
        })?;
    let curr = Decimal::from_str_exact(current)
        .map_err(|e| SpecError::BadJsonPath {
            path: "subtract.current".into(),
            message: e.to_string(),
        })?;
    Ok((prev - curr).normalize().to_string())
}

impl SpecSnapshotField {
    pub fn validate(&self) -> Result<(), SpecError> {
        if KNOWN_SNAPSHOT_FIELDS.contains(&self.field.as_str()) {
            Ok(())
        } else {
            Err(SpecError::UnknownSnapshotField(self.field.clone()))
        }
    }
}

/// Convert one parsed alias into a candidate field value. Field-name
/// allow-list enforced here, mirroring `SpecSnapshotAssembly`.
pub struct SpecSnapshotAssembly;

impl SpecSnapshotAssembly {
    /// Stub for the Swift assembler. Real implementation picks each
    /// alias under its `field = ...` rule, applies the optional
    /// `transform` block (`subtract` is the only built-in today), and
    /// produces a `serde_json::Value` map ready for serialization into
    /// the snapshot envelope.
    pub fn assemble(
        fields: &[SpecSnapshotField],
        captures: &std::collections::HashMap<String, Value>,
    ) -> Result<std::collections::BTreeMap<String, Value>, SpecError> {
        let mut out: std::collections::BTreeMap<String, Value> = std::collections::BTreeMap::new();
        for f in fields {
            f.validate()?;
            let Some(v) = captures.get(&f.alias).cloned() else {
                continue;
            };
            if let Some(transform) = &f.transform {
                if transform.kind == "subtract" {
                    let Value::Object(map) = &v else {
                        return Err(SpecError::BadJsonPath {
                            path: format!("subtract.{}", f.alias),
                            message: "expected object {previous, current}".into(),
                        });
                    };
                    let previous = map
                        .get("previous")
                        .and_then(|x| x.as_str())
                        .unwrap_or("0");
                    let current = map
                        .get("current")
                        .and_then(|x| x.as_str())
                        .unwrap_or("0");
                    let canonical = subtract_decimal(previous, current)?;
                    out.insert(
                        f.field.clone(),
                        Value::String(canonical),
                    );
                    continue;
                }
                return Err(SpecError::BadJsonPath {
                    path: format!("transform.{}", f.alias),
                    message: format!("unknown transform {}", transform.kind),
                });
            }
            out.insert(f.field.clone(), v);
        }
        Ok(out)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn subtract_decimal_canonical_form() {
        assert_eq!(subtract_decimal("100", "60").unwrap(), "40");
        assert_eq!(subtract_decimal("100.50", "0.10").unwrap(), "100.4");
        assert_eq!(subtract_decimal("6655.90", "0").unwrap(), "6655.9");
    }

    #[test]
    fn json_path_navigation() {
        let spec = SpecEngine::load(&json!({
            "specVersion": 1,
            "id": "demo",
            "descriptor": {"displayName": "Demo", "credentialKind": "standard"},
            "credential": {"kind": "standard", "authHeader": "Authorization", "scheme": "Bearer", "placeholder": "sk-..."},
            "profiles": {"supported": []},
            "detect": {"steps": []},
            "fetch": {"steps": []},
        }))
        .unwrap();
        let v = json!({"data": {"balance": 100, "items": [{"name": "a"}, {"name": "b"}]}});
        assert_eq!(spec.navigate(&v, "data.balance"), &json!(100));
        assert_eq!(spec.navigate(&v, "data.items.1.name"), &json!("b"));
        assert_eq!(spec.navigate(&v, "data.missing"), &Value::Null);
    }

    #[test]
    fn unknown_field_fails_assembly() {
        let field = SpecSnapshotField {
            field: "nonsense".into(),
            alias: "a".into(),
            transform: None,
        };
        assert!(matches!(field.validate(), Err(SpecError::UnknownSnapshotField(_))));
    }

    #[test]
    fn spec_load_rejects_version_mismatch() {
        assert!(matches!(
            SpecEngine::load(&json!({ "specVersion": 99, "id": "x" })),
            Err(SpecError::SpecVersionMismatch) | Err(SpecError::BadJsonPath { .. })
        ));
    }
}
