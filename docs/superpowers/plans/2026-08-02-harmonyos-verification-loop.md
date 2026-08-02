# HarmonyOS Verification Loop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Align ArkTS contract request assertions with Swift (method / URL / headers) and fail CI when `CONTRACT_CASES` drifts from fixture cases—without adding device ohosTest to GitHub Actions.

**Architecture:** Extend `Contract.test.ets` so the stub fetcher records full request triples and asserts header patterns identically to Swift `expectRequests`. Extend `scripts/verify-provider-parity.sh` with coverage + step-URL checks; Quality / CI / HarmonyOS already invoke that script. Add a red-path case to `ProviderParityTests.sh`.

**Tech Stack:** Bash (`verify-provider-parity.sh`, ScriptTests), ArkTS Hypium (`Contract.test.ets`), existing GitHub workflows (no new YAML).

**Spec:** `docs/superpowers/specs/2026-08-02-harmonyos-i18n-and-verification-design.md` Part B.

**Sibling plan:** `docs/superpowers/plans/2026-08-02-harmonyos-i18n.md` (Part A). Ship this plan first; it is independent of i18n.

## Global Constraints

- Do **not** add ohosTest / emulator / Hypium steps to any `.github/workflows/*.yml`.
- Do **not** auto-discover or generate `CONTRACT_CASES`; only gate that they stay complete.
- New bash must pass ShellCheck `--shell=bash --severity=warning` (Quality `static` job).
- Header assertion rules must match Swift: `"Bearer"` ⇒ prefix `Bearer `; any other fixture value ⇒ exact match; unlisted headers unchecked.
- Skip request assertions when `<case>-requests.json` is absent.

---

### Task 1: ArkTS harness asserts request headers

**Files:**
- Modify: `HarmonyOS/entry/src/ohosTest/ets/test/Contract.test.ets`
- Modify: `Contracts/README.md` (header-assertion paragraph only)
- Modify: `HarmonyOS/AGENTS.md` (whitelist #4 + CI note for coverage—coverage lands in Task 2; update #4 here)

**Interfaces:**
- Consumes: existing `ExpectedRequest`, `loadExpectedRequests`, stub `HttpFetcher` signature `(url, headers) => Promise<RawJsonResponse>`
- Produces: `assertRequests(actual: RecordedRequest[], expected: ExpectedRequest[] | undefined): void` where `RecordedRequest = { method: string; url: string; headers: Record<string, string> }`

- [ ] **Step 1: Add `RecordedRequest` and rewrite assertion helpers**

Replace the URL-only helpers near the bottom of `Contract.test.ets` with:

```typescript
interface RecordedRequest {
  method: string;
  url: string;
  headers: Record<string, string>;
}

// Asserts the recorded request sequence against a requests fixture.
// Semantics match Swift expectRequests in ContractTests.swift:
// count/order/method/url exact; header values are patterns ("Bearer" =
// scheme prefix; any other string = exact match). Headers absent from
// the fixture are unchecked. Missing fixture => no-op.
function assertRequests(
  actual: RecordedRequest[],
  expected: ExpectedRequest[] | undefined
): void {
  if (expected === undefined) {
    return;
  }
  expect(actual.length).assertEqual(expected.length);
  for (let i = 0; i < expected.length; i++) {
    expect(actual[i].method).assertEqual(expected[i].method);
    expect(actual[i].url).assertEqual(expected[i].url);
    const patterns = expected[i].headers;
    const keys = Object.keys(patterns);
    for (let k = 0; k < keys.length; k++) {
      const field = keys[k];
      const pattern = patterns[field];
      const value = actual[i].headers[field];
      if (pattern === 'Bearer') {
        expect(value !== undefined && value.indexOf('Bearer ') === 0).assertTrue();
      } else {
        expect(value).assertEqual(pattern);
      }
    }
  }
}
```

Update the comments on `ExpectedRequest` / requests-fixture schema to say both platforms assert headers (delete the “HarmonyOS only asserts URL” wording).

- [ ] **Step 2: Record full triples in the stub fetcher**

In the contract `it` body, replace URL-only recording with:

```typescript
const recorded: RecordedRequest[] = [];
const fetcher: HttpFetcher =
  (url: string, headers: Record<string, string>): Promise<RawJsonResponse> => {
    recorded.push({ method: 'GET', url: url, headers: headers });
    const step = stepsByUrl.get(url);
    if (step === undefined) {
      return Promise.reject(new Error(`unstubbedUrl:${url}`));
    }
    const response: RawJsonResponse = {
      code: step.code ?? 200,
      body: readRawFileString(`contracts/${dir}/${step.file}`)
    };
    return Promise.resolve(response);
  };
// ...
assertSnapshot(snapshot, expected);
assertRequests(recorded, loadExpectedRequests(dir, contractCase.name));
```

Delete `assertRequestUrls` entirely.

- [ ] **Step 3: Update docs for harness parity**

In `Contracts/README.md`, replace the paragraph that says ArkTS only asserts URL/GET with: both Swift and ArkTS harnesses assert count, order, method, URL, and header patterns (`Bearer` = scheme prefix).

In `HarmonyOS/AGENTS.md` whitelist item 4, rewrite to: request assertion granularity is now aligned (method/url/headers); remove “逐 header 断言尚未实现”.

- [ ] **Step 4: Sanity-check locally (no device required for compile of test file)**

Run:

```bash
# Static review: ripgrep must show assertRequests and Bearer handling
rg -n "assertRequests|Bearer " HarmonyOS/entry/src/ohosTest/ets/test/Contract.test.ets
# If a simulator/device is available:
#   run ohosTest ContractTest via DevEco / hvigor test task
```

Expected: `assertRequests` and `Bearer ` present; `assertRequestUrls` gone.

- [ ] **Step 5: Commit**

```bash
git add HarmonyOS/entry/src/ohosTest/ets/test/Contract.test.ets Contracts/README.md HarmonyOS/AGENTS.md
git commit -m "$(cat <<'EOF'
test(harmonyos): assert contract request headers like Swift

EOF
)"
```

---

### Task 2: Parity script covers `CONTRACT_CASES` + step URLs

**Files:**
- Modify: `scripts/verify-provider-parity.sh`
- Modify: `AGENTS.md` (mention coverage check in verification / parity section)
- Modify: `HarmonyOS/AGENTS.md` (CI note: static coverage gate; ohosTest still local-only)

**Interfaces:**
- Consumes: `Contracts/Providers/*/…-expected.json`, `…-requests.json`, `HarmonyOS/entry/src/ohosTest/ets/test/Contract.test.ets` `CONTRACT_CASES`
- Produces: new checks `check_contract_case_registration` and `check_contract_case_step_urls` invoked before the final error tally

- [ ] **Step 1: Add helpers to extract registered cases**

Append helpers near the other extractors in `verify-provider-parity.sh`:

```bash
CONTRACT_TEST_FILE="$REPO_ROOT/HarmonyOS/entry/src/ohosTest/ets/test/Contract.test.ets"

# Prints "providerId caseName" lines from CONTRACT_CASES object literals.
# Relies on each case listing provider: '…' then name: '…' (order as today).
extract_contract_cases() {
  awk '
    /provider: '\''[^'\'']+'\''/ {
      if (match($0, /provider: '\''([^'\'']+)'\''/, m)) provider=m[1]
    }
    /name: '\''[^'\'']+'\''/ {
      if (provider != "" && match($0, /name: '\''([^'\'']+)'\''/, m)) {
        print provider, m[1]
        provider=""
      }
    }
  ' "$CONTRACT_TEST_FILE"
}
```

If the local `awk` lacks GNU `match(..., m)`, use a portable alternative:

```bash
extract_contract_cases() {
  # Emit provider/name pairs by scanning the CONTRACT_CASES array region.
  sed -n '/^const CONTRACT_CASES/,/^];/p' "$CONTRACT_TEST_FILE" \
    | awk '
        /provider:/ {
          gsub(/.*provider: '\''/, ""); gsub(/'\''.*/, "");
          provider=$0
        }
        /name:/ {
          gsub(/.*name: '\''/, ""); gsub(/'\''.*/, "");
          if (provider != "") { print provider, $0; provider="" }
        }
      '
}
```

- [ ] **Step 2: Implement coverage check**

```bash
check_contract_case_registration() {
  [[ -f "$CONTRACT_TEST_FILE" ]] || { fail "missing $CONTRACT_TEST_FILE"; return; }
  [[ -d "$CONTRACTS_DIR" ]] || { fail "missing $CONTRACTS_DIR"; return; }

  local registered
  registered="$(extract_contract_cases | sort -u)"

  local dir provider case_name key
  for dir in "$CONTRACTS_DIR"/*/; do
    provider="$(basename "$dir")"
    # Map directory name (lowercased id) to camelCase ProviderID used in CONTRACT_CASES
    # by reading spec.json "id".
    local spec_id
    spec_id="$(extract_spec_id "$dir/spec.json")"
    for expected in "$dir"*-expected.json; do
      [[ -f "$expected" ]] || continue
      case_name="$(basename "$expected" | sed -E 's/-expected\.json$//')"
      key="$spec_id $case_name"
      if ! grep -Fxq "$key" <<< "$registered"; then
        fail "CONTRACT_CASES missing case '$case_name' for provider '$spec_id' (from Contracts/Providers/$provider)"
      fi
    done
  done
}
```

- [ ] **Step 3: Implement step-URL sync check**

Parse each `CONTRACT_CASES` entry’s `steps: [{ url: '...' }, ...]` in order and compare to the URLs array in `Contracts/Providers/<dir>/<name>-requests.json` when that file exists.

Practical approach: for each registered `spec_id case_name`, locate directory via case-insensitive match of provider folder / `spec.id`, load requests fixture with `python3`, extract URLs; extract step URLs from the matching object in `Contract.test.ets` with a focused python/awk parser. Prefer a small embedded Python block for reliability:

```bash
check_contract_case_step_urls() {
  python3 - "$REPO_ROOT" <<'PY'
import json, re, sys
from pathlib import Path
root = Path(sys.argv[1])
test = (root / "HarmonyOS/entry/src/ohosTest/ets/test/Contract.test.ets").read_text()
# Grab CONTRACT_CASES array body
m = re.search(r"const CONTRACT_CASES: ContractCase\[\] = \[([\s\S]*?)\n\];", test)
if not m:
    print("error: could not find CONTRACT_CASES", file=sys.stderr)
    sys.exit(2)
body = m.group(1)
# Split rough case objects on "}," boundaries after steps blocks — use brace walk
cases = []
i = 0
while True:
    start = body.find("{", i)
    if start < 0:
        break
    depth = 0
    for j, ch in enumerate(body[start:], start):
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                block = body[start:j+1]
                i = j + 1
                break
    else:
        break
    prov = re.search(r"provider:\s*'([^']+)'", block)
    name = re.search(r"name:\s*'([^']+)'", block)
    urls = re.findall(r"url:\s*'([^']+)'", block)
    if prov and name:
        cases.append((prov.group(1), name.group(1), urls))

errors = 0
providers = root / "Contracts/Providers"
for spec_id, case_name, step_urls in cases:
    # find dir whose spec.json id matches
    match_dir = None
    for d in providers.iterdir():
        if not d.is_dir():
            continue
        spec = d / "spec.json"
        if not spec.exists():
            continue
        if json.load(open(spec))["id"] == spec_id:
            match_dir = d
            break
    if match_dir is None:
        print(f"error: CONTRACT_CASES provider '{spec_id}' has no Contracts/Providers spec", file=sys.stderr)
        errors += 1
        continue
    req = match_dir / f"{case_name}-requests.json"
    if not req.exists():
        continue
    expected_urls = [row["url"] for row in json.load(open(req))]
    if step_urls != expected_urls:
        print(
            f"error: CONTRACT_CASES {spec_id}/{case_name} steps urls {step_urls} != requests fixture {expected_urls}",
            file=sys.stderr,
        )
        errors += 1
sys.exit(1 if errors else 0)
PY
  local status=$?
  if (( status == 2 )); then
    fail "could not parse CONTRACT_CASES for step URL check"
  elif (( status != 0 )); then
    # python already printed error: lines; count as failures
    fail "CONTRACT_CASES step URLs out of sync with *-requests.json fixtures (see errors above)"
  fi
}
```

Wire both into the main sequence:

```bash
check_contract_case_registration
check_contract_case_step_urls
```

And add OK echo lines at the end.

- [ ] **Step 4: Run green + intentional red**

```bash
bash scripts/verify-provider-parity.sh
# Expected: exit 0, including new OK lines

# Temporary red: comment out one CONTRACT_CASES entry, re-run, expect fail, then restore
```

- [ ] **Step 5: ShellCheck**

```bash
shellcheck --shell=bash --severity=warning scripts/verify-provider-parity.sh
```

Expected: no warnings (fix any introduced issues).

- [ ] **Step 6: Update AGENTS docs**

Root `AGENTS.md`: in the parity / verification description, note that `verify-provider-parity.sh` also requires every Providers fixture case to appear in ArkTS `CONTRACT_CASES` with matching step URLs.

`HarmonyOS/AGENTS.md` CI paragraph: static coverage gate in parity script; ohosTest still local-only.

- [ ] **Step 7: Commit**

```bash
git add scripts/verify-provider-parity.sh AGENTS.md HarmonyOS/AGENTS.md
git commit -m "$(cat <<'EOF'
ci: gate ArkTS CONTRACT_CASES coverage in provider parity

EOF
)"
```

---

### Task 3: Negative ScriptTest for coverage gate

**Files:**
- Modify: `Tests/ScriptTests/ProviderParityTests.sh`

**Interfaces:**
- Consumes: Task 2 `check_contract_case_registration`
- Produces: `test_missing_contract_case_registration_is_red` using existing backup/trap pattern

- [ ] **Step 1: Extend cleanup to restore Contract.test.ets**

Add `CONTRACT_TEST` path and include it in the backup list for the new test (mirror how spec copies are backed up). Prefer a dedicated backup for this one file:

```bash
CONTRACT_TEST="$ROOT_DIR/HarmonyOS/entry/src/ohosTest/ets/test/Contract.test.ets"

test_missing_contract_case_registration_is_red() {
  /bin/cp "$CONTRACT_TEST" "$TEST_ROOT/Contract.test.ets.bak"
  # Drop the deepSeek balance case object (unique name marker).
  /usr/bin/python3 - "$CONTRACT_TEST" <<'PY'
from pathlib import Path
import re, sys
path = Path(sys.argv[1])
text = path.read_text()
# Remove the first case object that has name: 'balance' and provider deepSeek
pattern = re.compile(
    r"\s*\{\s*provider:\s*'deepSeek',\s*name:\s*'balance',[\s\S]*?\},",
    re.M,
)
new, n = pattern.subn("\n", text, count=1)
if n != 1:
    raise SystemExit("could not remove deepSeek balance CONTRACT_CASES entry")
path.write_text(new)
PY
  assert_fails /bin/bash "$PARITY_SCRIPT"
  /bin/cp "$TEST_ROOT/Contract.test.ets.bak" "$CONTRACT_TEST"
  /bin/bash "$PARITY_SCRIPT" >/dev/null \
    || fail "verify-provider-parity.sh still failing after restoring CONTRACT_CASES"
}
```

Call it after the existing green/tamper tests.

- [ ] **Step 2: Run ScriptTest**

```bash
bash Tests/ScriptTests/ProviderParityTests.sh
```

Expected: `Provider parity tests passed`

- [ ] **Step 3: Commit**

```bash
git add Tests/ScriptTests/ProviderParityTests.sh
git commit -m "$(cat <<'EOF'
test: assert parity fails when CONTRACT_CASES omits a fixture

EOF
)"
```

---

### Task 4: Roadmap note for verification (docs only)

**Files:**
- Modify: `docs/roadmap.md`

- [ ] **Step 1: Update roadmap**

Under Completed (or a short Quality note): mark GitHub Actions + Quality workflow as landed; mention verification-loop harness/header parity + `CONTRACT_CASES` coverage gate as done when this plan finishes (write after Tasks 1–3 land). Keep HarmonyOS i18n as open / point to sibling plan.

- [ ] **Step 2: Commit**

```bash
git add docs/roadmap.md
git commit -m "$(cat <<'EOF'
docs: record verification-loop and Quality CI progress on roadmap

EOF
)"
```

---

## Verification plan self-check

| Spec Part B requirement | Task |
| --- | --- |
| B.1 harness header assertions | Task 1 |
| B.2 coverage + step URLs | Task 2 |
| B.3 ProviderParityTests red path, no new workflow, ShellCheck | Tasks 2–3 |
| B.4 Contracts README + AGENTS + roadmap | Tasks 1, 2, 4 |
| Acceptance 6–8 (verification) | Tasks 1–3 |
