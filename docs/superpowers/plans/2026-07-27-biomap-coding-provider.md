# BioMap Coding Provider Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a fixed BioMap Coding provider that maps authorized LiteLLM virtual-key spend and budget data and safely falls back to connection-only validation.

**Architecture:** A dedicated adapter calls BioMap's deployed LiteLLM `GET /key/info` contract without putting the key in the query string. It maps cumulative USD spend and spending cap independently from cash balances; only explicit management-route restrictions trigger a `/v1/models` connection fallback.

**Tech Stack:** Swift 6, Swift Testing, Foundation networking, LiteLLM 1.82.3 OpenAPI, existing capability-based presentation

---

### Task 1: Provider Identity

**Files:**
- Modify: `Sources/QuotaGlanceCore/Domain/Provider.swift`
- Modify: `Tests/QuotaGlanceCoreTests/DomainModelTests.swift`

- [ ] Add failing tests for `ProviderID.bioMapCoding`, display name, global profile label, and disabled low-balance threshold.
- [ ] Run `swift test --filter DomainModelTests` and confirm the new identity is missing.
- [ ] Add the provider identity and capability switches.
- [ ] Re-run the focused tests and confirm they pass.

### Task 2: LiteLLM Key Info Adapter

**Files:**
- Create: `Sources/QuotaGlanceCore/Providers/BioMapCodingProvider.swift`
- Create: `Tests/QuotaGlanceCoreTests/BioMapCodingProviderTests.swift`

- [ ] Add failing tests for nested key info, precise spend and cap mapping, no query key, missing metrics, blocked keys, typed HTTP failures, and fixed profile validation.
- [ ] Run `swift test --filter BioMapCodingProviderTests` and confirm the adapter is missing.
- [ ] Implement `GET /key/info` parsing and capability mapping.
- [ ] Re-run the focused tests and confirm they pass.

### Task 3: Restricted-Route Fallback And Registration

**Files:**
- Modify: `Sources/QuotaGlanceCore/Providers/BioMapCodingProvider.swift`
- Modify: `Tests/QuotaGlanceCoreTests/BioMapCodingProviderTests.swift`
- Modify: `App/AppModel.swift`

- [ ] Add failing tests that only 403/404/405 fall back to `/v1/models`, validate the model-list shape, and expose a connection-only notice.
- [ ] Run the focused provider tests and confirm fallback calls are missing.
- [ ] Implement fallback and register the provider in `AppModel`.
- [ ] Re-run provider tests and build the app.

### Task 4: Documentation And Verification

**Files:**
- Modify: `README.md`
- Modify: `docs/research/provider-capabilities.md`

- [ ] Document the fixed BioMap endpoint, LiteLLM version, USD spend semantics, and permission fallback.
- [ ] Run `swift test` and all script tests.
- [ ] Build and install the Release app, verify signing/process/Widget registration, and run the configured-key secret scan when a key is available.
- [ ] Run `git diff --check`, commit, and push `main`.

