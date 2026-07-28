# QuotaGlance HarmonyOS Minimal Loop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在鸿蒙（HarmonyOS NEXT, ArkTS/ArkUI）上打通 QuotaGlance 最小闭环：DeepSeek 余额查询 → API Key 设备端安全存储 → 主页手动刷新 → 万能卡片 30 分钟定时刷新，调试签名直装本人手机自用。

**Architecture:** 纯客户端、无后端。macOS 端 SwiftUI 不动；鸿蒙端 ArkTS 全新实现（DevEco Studio 标准 Empty Ability 工程，位于 `HarmonyOS/`）。两端核心逻辑各自实现，靠共享契约 fixture（`Contracts/Providers/deepseek/` 下两个 JSON，两端唯一事实源）防漂移：Swift 侧 `ContractTests.swift` 直读仓库路径，鸿蒙侧 ohosTest 读 rawfile（由 `scripts/sync-contracts-to-harmonyos.sh` 单向同步）。Key 只存设备端：macOS Keychain / 鸿蒙 Asset Store Kit。

**Tech Stack:** Swift 6 / Swift Testing（现有，不动）；ArkTS + ArkUI（Stage 模型，API 12+）、@kit.NetworkKit（HTTP）、@kit.AssetStoreKit（key 存储）、@kit.ArkData preferences（快照共享）、@kit.FormKit（FormExtensionAbility 卡片）、Hypium（ohosTest）。

**显式排除（本计划不做）：** 屏保模式（应用内自定义屏保属第二阶段）；CI 接入鸿蒙构建（自用阶段不安排 GitHub Actions 任务）；DeepSeek 以外的 provider；AppGallery 上架。

**执行环境提醒：** 鸿蒙侧的 GUI 操作、构建与真机验证都在 macOS + DevEco Studio 上进行；撰写本会话所在的 Linux 环境只负责落盘文件。每个 Task 完成后按步骤中给出的完整命令 git commit（英文 conventional commits）。

**跨 Task 命名约定（前后必须一致）：**

- 契约文件：`Contracts/Providers/deepseek/balance-response.json`（响应原文）+ `balance-expected.json`（解析期望）；鸿蒙 rawfile 路径为 `contracts/deepseek/同名文件`。
- ArkTS 领域类型（`ets/providers/UsageSnapshot.ets`）：`Money`、`MonetaryValue`、`MonetaryBalance`、`UsageSnapshot`，字段名与 Swift 领域模型一致。
- `parseBalance(responseBody: string, receivedAtMs: number): UsageSnapshot`（`ets/providers/DeepSeekProvider.ets`，纯函数，不发 HTTP）。
- `fetchBalance(apiKey: string): Promise<string>`（`ets/network/HttpClient.ets`）。
- `KeyRepository.save(apiKey)` / `KeyRepository.load()` / `KeyRepository.clear()`（`ets/storage/KeyRepository.ets`，静态方法）。
- `SnapshotStore.create(context)` / `.save(snapshot)` / `.markStale()` / `.load()` 与 `formatSnapshotTexts(stored)`（`ets/storage/SnapshotStore.ets`）；返回文本键固定为 `balanceText` / `statusText` / `updatedAtText`（卡片 `@LocalStorageProp` 同名）。

---

## Task 1: 共享契约 fixture（两端唯一事实源）

响应原文对齐 `Sources/QuotaGlanceCore/Providers/DeepSeekProvider.swift` 的 `Response` 结构（snake_case 字段）；期望文件字段名对齐 `Sources/QuotaGlanceCore/Domain/UsageSnapshot.swift` 的领域模型（`balances[].label / available.{amount,currency} / breakdown[].{label,value}`、`providerStatus`）。金额统一用十进制字符串表示（两端都不做浮点运算）。fixture 故意包含两个边角：带空格小写币种（锁定 trim+uppercase 行为）和 JSON number 形式的金额（锁定 number-or-string 两种解码路径）。

**Files:**

- Create: `Contracts/Providers/deepseek/balance-response.json`
- Create: `Contracts/Providers/deepseek/balance-expected.json`

- [ ] **Step 1: 创建响应原文 fixture**

  写入 `Contracts/Providers/deepseek/balance-response.json`：

  ```json
  {
    "is_available": true,
    "balance_infos": [
      {
        "currency": " cny ",
        "total_balance": "12.34",
        "granted_balance": "2.34",
        "topped_up_balance": "10.00"
      },
      {
        "currency": "USD",
        "total_balance": 5.67,
        "granted_balance": 0,
        "topped_up_balance": 5.67
      }
    ]
  }
  ```

- [ ] **Step 2: 创建解析期望 fixture**

  写入 `Contracts/Providers/deepseek/balance-expected.json`（`receivedAt` 不进契约——它是调用方注入的时间戳，两端测试各自单独断言）：

  ```json
  {
    "balances": [
      {
        "label": "Balance",
        "available": { "amount": "12.34", "currency": "CNY" },
        "breakdown": [
          { "label": "Granted", "value": { "amount": "2.34", "currency": "CNY" } },
          { "label": "Topped up", "value": { "amount": "10.00", "currency": "CNY" } }
        ]
      },
      {
        "label": "Balance",
        "available": { "amount": "5.67", "currency": "USD" },
        "breakdown": [
          { "label": "Granted", "value": { "amount": "0", "currency": "USD" } },
          { "label": "Topped up", "value": { "amount": "5.67", "currency": "USD" } }
        ]
      }
    ],
    "providerStatus": "active"
  }
  ```

- [ ] **Step 3: 校验两个 JSON 合法**

  ```bash
  python3 -m json.tool Contracts/Providers/deepseek/balance-response.json > /dev/null && \
  python3 -m json.tool Contracts/Providers/deepseek/balance-expected.json > /dev/null && echo OK
  ```

  预期输出：`OK`

- [ ] **Step 4: Commit**

  ```bash
  git add Contracts/Providers/deepseek/ && \
  git commit -m "feat(contracts): add DeepSeek balance contract fixtures"
  ```

---

## Task 2: Swift 契约测试（characterization 测试）

这是对**现有** `DeepSeekProvider` 的 characterization 测试：预期写完即通过。若失败，说明 fixture 与既有 provider 行为不一致——**修 fixture，不改 provider 逻辑**（provider 是参考实现）。测试用 `#filePath` 相对路径直读 `Contracts/`，不放进 bundle resources（`Package.swift` 不动）。

**Files:**

- Test: `Tests/QuotaGlanceCoreTests/ContractTests.swift`

- [ ] **Step 1: 创建契约测试**

  写入 `Tests/QuotaGlanceCoreTests/ContractTests.swift`（stub HTTPClient 模式复用 `DeepSeekProviderTests.swift` 的形态）：

  ```swift
  import Foundation
  import Testing
  @testable import QuotaGlanceCore

  @Suite("DeepSeek contract fixtures")
  struct DeepSeekContractTests {
      private struct ExpectedMoney: Decodable {
          let amount: String
          let currency: String
      }

      private struct ExpectedBreakdownItem: Decodable {
          let label: String
          let value: ExpectedMoney
      }

      private struct ExpectedBalance: Decodable {
          let label: String
          let available: ExpectedMoney
          let breakdown: [ExpectedBreakdownItem]
      }

      private struct ExpectedSnapshot: Decodable {
          let balances: [ExpectedBalance]
          let providerStatus: String
      }

      private struct ContractStubHTTPClient: HTTPClient {
          let data: Data

          func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
              let response = HTTPURLResponse(
                  url: request.url!,
                  statusCode: 200,
                  httpVersion: "HTTP/1.1",
                  headerFields: nil
              )!
              return (data, response)
          }
      }

      private static func contractsDirectory() -> URL {
          URL(fileURLWithPath: #filePath)
              .deletingLastPathComponent() // QuotaGlanceCoreTests
              .deletingLastPathComponent() // Tests
              .deletingLastPathComponent() // repository root
              .appendingPathComponent("Contracts/Providers/deepseek", isDirectory: true)
      }

      @Test("DeepSeek provider output matches the shared contract fixture")
      func providerOutputMatchesContractFixture() async throws {
          let directory = Self.contractsDirectory()
          let responseData = try Data(
              contentsOf: directory.appendingPathComponent("balance-response.json")
          )
          let expectedData = try Data(
              contentsOf: directory.appendingPathComponent("balance-expected.json")
          )
          let expected = try JSONDecoder().decode(ExpectedSnapshot.self, from: expectedData)

          let provider = DeepSeekProvider(
              httpClient: ContractStubHTTPClient(data: responseData),
              now: { Date(timeIntervalSince1970: 123) }
          )
          let snapshot = try await provider.fetch(apiKey: "redacted-test-key")

          #expect(snapshot.providerStatus == expected.providerStatus)
          #expect(snapshot.balances.count == expected.balances.count)
          for (actual, expectedBalance) in zip(snapshot.balances, expected.balances) {
              #expect(actual.label == expectedBalance.label)
              #expect(
                  actual.available == Money(
                      amount: Decimal(string: expectedBalance.available.amount)!,
                      currency: expectedBalance.available.currency
                  )
              )
              #expect(actual.breakdown.count == expectedBalance.breakdown.count)
              for (actualItem, expectedItem) in zip(actual.breakdown, expectedBalance.breakdown) {
                  #expect(actualItem.label == expectedItem.label)
                  #expect(
                      actualItem.value == Money(
                          amount: Decimal(string: expectedItem.value.amount)!,
                          currency: expectedItem.value.currency
                      )
                  )
              }
          }
      }
  }
  ```

- [ ] **Step 2: 运行契约测试（characterization，预期直接通过）**

  ```bash
  swift test --filter DeepSeekContractTests
  ```

  预期输出含：

  ```
  ✔ Test "DeepSeek provider output matches the shared contract fixture" passed
  ◇ Test run with 1 test passed
  ```

  若失败：逐字段比对失败断言，修正 Task 1 的 fixture（通常是币种大小写、breakdown 标签、金额字符串格式），**不要**修改 `DeepSeekProvider.swift`。

- [ ] **Step 3: 跑全量 Swift 测试确认无回归**

  ```bash
  swift test
  ```

  预期输出：全部 suite passed，`0 failures`。

- [ ] **Step 4: Commit**

  ```bash
  git add Tests/QuotaGlanceCoreTests/ContractTests.swift && \
  git commit -m "test(core): add DeepSeek provider contract test against shared fixtures"
  ```

---

## Task 3: DevEco Studio 工程骨架（人工 GUI 步骤）

鸿蒙没有官方 CLI 建工程命令，本 Task 全部是 macOS 上 DevEco Studio 的 GUI 操作，最后用 hvigorw 验证骨架可构建后 commit。前置：已安装 DevEco Studio（含 API 12+ SDK）、已注册华为开发者账号并在 DevEco 登录。

**Files:**

- Create: `HarmonyOS/`（DevEco 生成的完整工程，含 `AppScope/app.json5`、`entry/src/main/module.json5`、`ets/entryability/EntryAbility.ets`、`ets/pages/Index.ets`、`ohosTest/` 模板等）
- Create: `HarmonyOS/.gitignore`（若模板未生成或不完整则补齐）

- [ ] **Step 1: 新建工程**

  打开 DevEco Studio → Welcome 页 **Create Project** → 模板选 **Empty Ability**（Stage 模型，ArkTS）→ Next，向导字段填：

  | 字段 | 值 |
  | --- | --- |
  | Project name | `HarmonyOS` |
  | Bundle name | `com.quotaglance.personal`（须在你的开发者账号下唯一；若 DevEco 提示冲突，换成任意唯一名并在后续所有配置中保持一致） |
  | Save location | 选仓库根目录 `QuotaGlance/`；DevEco 会在其下以 Project name 建子目录，工程最终落在 `QuotaGlance/HarmonyOS/` |
  | Compile SDK | API 12（HarmonyOS 5.0.0）或更新；**不得低于 API 12** |
  | Model | Stage（模板默认） |
  | Device type | Phone |
  | Enable Super Visual | 不勾选 |

  点 Finish，等待工程同步（oh_modules 安装）完成。

- [ ] **Step 2: 配置调试签名**

  手机开启「设置 → 关于手机 → 连点版本号」打开开发者模式并 USB 连接 → DevEco 菜单 **File → Project Structure → Project → Signing Configs** → 勾选 **Automatically generate signature**（需已登录华为开发者账号）→ Apply → OK。验证：Signing Configs 区域不再报红，显示生成的 certificate/profile。

- [ ] **Step 3: 补齐 .gitignore**

  检查 DevEco 是否已生成 `HarmonyOS/.gitignore`；无论是否已生成，确保其中包含以下条目（缺失则追加）：

  ```
  .hvigor/
  .idea/
  oh_modules/
  build/
  */build/
  local.properties
  .obfuscated/
  ```

- [ ] **Step 4: 验证骨架可构建**

  ```bash
  cd HarmonyOS && ./hvigorw assembleHap --mode module -p product=default -p module=entry@default
  ```

  预期输出结尾：

  ```
  BUILD SUCCESSFUL
  ```

  产物位于 `HarmonyOS/entry/build/default/outputs/default/` 下的 `.hap`。

- [ ] **Step 5: 真机冒烟（可选但强烈建议）**

  DevEco 工具栏选已连接手机 → Run 'entry'。预期：手机装上空白应用并显示 "Hello World"。

- [ ] **Step 6: Commit**

  ```bash
  git add HarmonyOS/ && \
  git commit -m "chore(harmonyos): scaffold DevEco Studio empty ability project"
  ```

---

## Task 4: ArkTS 领域类型 + DeepSeek 纯函数解析器 + Hypium 契约测试

先写同步脚本并运行（把 `Contracts/` 复制进 ohosTest rawfile——OHOS 测试只能读应用沙箱内资源，这是唯一同步方向），再写失败的契约测试，再实现解析器使其通过。契约 JSON 与 Task 1 是同一份文件。

**Files:**

- Create: `scripts/sync-contracts-to-harmonyos.sh`
- Create: `HarmonyOS/entry/src/main/ets/providers/UsageSnapshot.ets`
- Create: `HarmonyOS/entry/src/main/ets/providers/DeepSeekProvider.ets`
- Test: `HarmonyOS/entry/src/ohosTest/ets/test/DeepSeekContract.test.ets`
- Modify: `HarmonyOS/entry/src/ohosTest/ets/test/List.test.ets`
- Create（由同步脚本生成，随脚本运行产生）: `HarmonyOS/entry/src/ohosTest/resources/rawfile/contracts/deepseek/`

- [ ] **Step 1: 创建契约同步脚本**

  写入 `scripts/sync-contracts-to-harmonyos.sh`：

  ```bash
  #!/usr/bin/env bash
  # Sync shared contract fixtures into the HarmonyOS ohosTest rawfile directory.
  # One-way: Contracts/ -> HarmonyOS ohosTest resources. Swift reads Contracts/ directly.
  set -euo pipefail

  REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  SRC="$REPO_ROOT/Contracts/Providers"
  DST="$REPO_ROOT/HarmonyOS/entry/src/ohosTest/resources/rawfile/contracts"

  if [[ ! -d "$SRC" ]]; then
    echo "error: $SRC not found" >&2
    exit 1
  fi

  rm -rf "$DST"
  mkdir -p "$DST"
  cp -R "$SRC/." "$DST/"
  echo "Synced contracts -> $DST"
  ```

  赋可执行权限：

  ```bash
  chmod +x scripts/sync-contracts-to-harmonyos.sh
  ```

- [ ] **Step 2: 运行同步脚本**

  ```bash
  bash scripts/sync-contracts-to-harmonyos.sh
  ```

  预期输出：`Synced contracts -> <repo>/HarmonyOS/entry/src/ohosTest/resources/rawfile/contracts`，且 `HarmonyOS/entry/src/ohosTest/resources/rawfile/contracts/deepseek/` 下出现两个 JSON。

- [ ] **Step 3: 创建 ArkTS 领域类型**

  写入 `HarmonyOS/entry/src/main/ets/providers/UsageSnapshot.ets`（字段名与 Swift 领域模型一致；金额保持十进制字符串，不做浮点运算）：

  ```ts
  export interface Money {
    amount: string;
    currency: string;
  }

  export interface MonetaryValue {
    label: string;
    value: Money;
  }

  export interface MonetaryBalance {
    label: string;
    available: Money;
    breakdown: MonetaryValue[];
  }

  export interface UsageSnapshot {
    balances: MonetaryBalance[];
    providerStatus: string;
    receivedAtMs: number;
  }
  ```

- [ ] **Step 4: 写失败的契约测试（红）**

  写入 `HarmonyOS/entry/src/ohosTest/ets/test/DeepSeekContract.test.ets`（此时 `parseBalance` 尚不存在，预期编译失败）：

  ```ts
  import { describe, it, expect } from '@ohos/hypium';
  import { abilityDelegatorRegistry } from '@kit.TestKit';
  import { util } from '@kit.ArkTS';
  import { parseBalance } from '../../../main/ets/providers/DeepSeekProvider';

  interface ExpectedMoney {
    amount: string;
    currency: string;
  }

  interface ExpectedBreakdownItem {
    label: string;
    value: ExpectedMoney;
  }

  interface ExpectedBalance {
    label: string;
    available: ExpectedMoney;
    breakdown: ExpectedBreakdownItem[];
  }

  interface ExpectedSnapshot {
    balances: ExpectedBalance[];
    providerStatus: string;
  }

  function readRawFileString(path: string): string {
    const context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
    const bytes: Uint8Array = context.resourceManager.getRawFileContentSync(path);
    return util.TextDecoder.create('utf-8').decodeToString(bytes);
  }

  export default function deepSeekContractTest() {
    describe('DeepSeekContractTest', () => {
      it('parseBalanceMatchesContractFixture', 0, () => {
        const responseBody = readRawFileString('contracts/deepseek/balance-response.json');
        const expected = JSON.parse(
          readRawFileString('contracts/deepseek/balance-expected.json')
        ) as ExpectedSnapshot;

        const snapshot = parseBalance(responseBody, 0);

        expect(snapshot.providerStatus).assertEqual(expected.providerStatus);
        expect(snapshot.balances.length).assertEqual(expected.balances.length);
        for (let i = 0; i < expected.balances.length; i++) {
          const actualBalance = snapshot.balances[i];
          const expectedBalance = expected.balances[i];
          expect(actualBalance.label).assertEqual(expectedBalance.label);
          expect(actualBalance.available.amount).assertEqual(expectedBalance.available.amount);
          expect(actualBalance.available.currency).assertEqual(expectedBalance.available.currency);
          expect(actualBalance.breakdown.length).assertEqual(expectedBalance.breakdown.length);
          for (let j = 0; j < expectedBalance.breakdown.length; j++) {
            const actualItem = actualBalance.breakdown[j];
            const expectedItem = expectedBalance.breakdown[j];
            expect(actualItem.label).assertEqual(expectedItem.label);
            expect(actualItem.value.amount).assertEqual(expectedItem.value.amount);
            expect(actualItem.value.currency).assertEqual(expectedItem.value.currency);
          }
        }
      });

      it('rejectsEmptyBalanceInfos', 0, () => {
        let threw = false;
        try {
          parseBalance('{"is_available":true,"balance_infos":[]}', 0);
        } catch (error) {
          threw = true;
        }
        expect(threw).assertTrue();
      });
    });
  }
  ```

  修改 `HarmonyOS/entry/src/ohosTest/ets/test/List.test.ets`，注册测试套（保留模板自带的 `abilityTest`）：

  ```ts
  import abilityTest from './Ability.test';
  import deepSeekContractTest from './DeepSeekContract.test';

  export default function testsuite() {
    abilityTest();
    deepSeekContractTest();
  }
  ```

- [ ] **Step 5: 运行测试确认失败（红）**

  ```bash
  cd HarmonyOS && ./hvigorw assembleHap --mode module -p product=default -p module=entry@default
  ```

  预期：编译报错，提示 `main/ets/providers/DeepSeekProvider` 无法解析（模块不存在）。

- [ ] **Step 6: 实现 DeepSeek 纯函数解析器（绿）**

  写入 `HarmonyOS/entry/src/main/ets/providers/DeepSeekProvider.ets`（行为逐条对齐 Swift `DeepSeekProvider`：币种 trim+uppercase、金额接受 string 或 number、breakdown 标签固定 "Granted" / "Topped up"、`is_available` 映射 `active`/`unavailable`、空 `balance_infos` 抛错）：

  ```ts
  import { MonetaryBalance, MonetaryValue, Money, UsageSnapshot } from './UsageSnapshot';

  interface BalanceInfoPayload {
    currency: string;
    total_balance?: string | number;
    granted_balance?: string | number;
    topped_up_balance?: string | number;
  }

  interface BalanceResponsePayload {
    is_available: boolean;
    balance_infos?: BalanceInfoPayload[];
  }

  function decimalString(raw: string | number | undefined): string | null {
    if (raw === undefined) {
      return null;
    }
    if (typeof raw === 'number') {
      return Number.isFinite(raw) ? String(raw) : null;
    }
    const trimmed = raw.trim();
    if (trimmed.length === 0) {
      return null;
    }
    return Number.isFinite(Number(trimmed)) ? trimmed : null;
  }

  export function parseBalance(responseBody: string, receivedAtMs: number): UsageSnapshot {
    let payload: BalanceResponsePayload;
    try {
      payload = JSON.parse(responseBody) as BalanceResponsePayload;
    } catch (error) {
      throw new Error('invalidResponse');
    }

    const infos = payload.balance_infos;
    if (!infos || infos.length === 0) {
      throw new Error('invalidResponse');
    }

    const balances: MonetaryBalance[] = infos.map((info: BalanceInfoPayload) => {
      const currency = info.currency.trim().toUpperCase();
      const total = decimalString(info.total_balance);
      if (currency.length === 0 || total === null) {
        throw new Error('invalidResponse');
      }

      const breakdown: MonetaryValue[] = [];
      const granted = decimalString(info.granted_balance);
      if (granted !== null) {
        breakdown.push({ label: 'Granted', value: { amount: granted, currency: currency } });
      }
      const toppedUp = decimalString(info.topped_up_balance);
      if (toppedUp !== null) {
        breakdown.push({ label: 'Topped up', value: { amount: toppedUp, currency: currency } });
      }

      const available: Money = { amount: total, currency: currency };
      return { label: 'Balance', available: available, breakdown: breakdown };
    });

    return {
      balances: balances,
      providerStatus: payload.is_available ? 'active' : 'unavailable',
      receivedAtMs: receivedAtMs
    };
  }
  ```

- [ ] **Step 7: 运行契约测试确认通过（绿）**

  连接真机或启动模拟器，然后：

  ```bash
  cd HarmonyOS && ./hvigorw test --mode module -p product=default -p module=entry@ohosTest
  ```

  （等价 GUI 路径：DevEco 中右键 `entry/src/ohosTest/ets/test/List.test.ets` → Run。）

  预期：构建成功且 Hypium 报告 `DeepSeekContractTest` 两个用例全部 passed（运行面板/hilog 中 `OHOS_TEST_RESULT` 无 failure）。若失败：比对失败字段修 ArkTS 解析器；只有确认 fixture 本身与 Swift 行为冲突时才回到 Task 1 修 fixture 并同步重跑 Task 2。

- [ ] **Step 8: Commit**

  ```bash
  git add scripts/sync-contracts-to-harmonyos.sh \
    HarmonyOS/entry/src/main/ets/providers/ \
    HarmonyOS/entry/src/ohosTest/ && \
  git commit -m "feat(harmonyos): add DeepSeek balance parser with shared contract test"
  ```

---

## Task 5: KeyRepository（Asset Store Kit）+ SettingsPage 录入 UI

Asset Store Kit 是 macOS Keychain 的鸿蒙对应物，开放给普通三方应用（API 11+，无需特殊权限；本计划不用 `IS_PERSISTENT`，卸载即删）。Asset Store 不需要 context，故 `KeyRepository` 用静态方法。

**Files:**

- Create: `HarmonyOS/entry/src/main/ets/storage/KeyRepository.ets`
- Create: `HarmonyOS/entry/src/main/ets/pages/SettingsPage.ets`
- Modify: `HarmonyOS/entry/src/main/resources/base/profile/main_pages.json`

- [ ] **Step 1: 创建 KeyRepository**

  写入 `HarmonyOS/entry/src/main/ets/storage/KeyRepository.ets`（`save` 用 remove+add 实现幂等覆盖；`load` 对 `NOT_FOUND`(24000002) 返回 `null`；`ACCESSIBILITY` 用 `DEVICE_FIRST_UNLOCKED`，卡片进程在锁屏后也能读）：

  ```ts
  import { asset } from '@kit.AssetStoreKit';
  import { util } from '@kit.ArkTS';
  import { BusinessError } from '@kit.BasicServicesKit';

  const ALIAS = 'quotaglance_deepseek_api_key';
  const ERROR_NOT_FOUND = 24000002;

  function stringToArray(str: string): Uint8Array {
    return new util.TextEncoder().encodeInto(str);
  }

  function arrayToString(bytes: Uint8Array): string {
    return util.TextDecoder.create('utf-8').decodeToString(bytes);
  }

  export class KeyRepository {
    static async save(apiKey: string): Promise<void> {
      const query: asset.AssetMap = new Map();
      query.set(asset.Tag.ALIAS, stringToArray(ALIAS));
      try {
        await asset.remove(query);
      } catch (error) {
        if ((error as BusinessError).code !== ERROR_NOT_FOUND) {
          throw error;
        }
      }

      const attributes: asset.AssetMap = new Map();
      attributes.set(asset.Tag.ALIAS, stringToArray(ALIAS));
      attributes.set(asset.Tag.SECRET, stringToArray(apiKey));
      attributes.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
      await asset.add(attributes);
    }

    static async load(): Promise<string | null> {
      const query: asset.AssetMap = new Map();
      query.set(asset.Tag.ALIAS, stringToArray(ALIAS));
      query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
      try {
        const results = await asset.query(query);
        if (results.length === 0) {
          return null;
        }
        const secret = results[0].get(asset.Tag.SECRET) as Uint8Array;
        return arrayToString(secret);
      } catch (error) {
        if ((error as BusinessError).code === ERROR_NOT_FOUND) {
          return null;
        }
        throw error;
      }
    }

    static async clear(): Promise<void> {
      const query: asset.AssetMap = new Map();
      query.set(asset.Tag.ALIAS, stringToArray(ALIAS));
      try {
        await asset.remove(query);
      } catch (error) {
        if ((error as BusinessError).code !== ERROR_NOT_FOUND) {
          throw error;
        }
      }
    }
  }
  ```

- [ ] **Step 2: 创建 SettingsPage 录入 UI**

  写入 `HarmonyOS/entry/src/main/ets/pages/SettingsPage.ets`：

  ```ts
  import { router } from '@kit.ArkUI';
  import { KeyRepository } from '../storage/KeyRepository';

  @Entry
  @Component
  struct SettingsPage {
    @State apiKey: string = '';
    @State message: string = '';

    build() {
      Column({ space: 16 }) {
        Text('DeepSeek API Key')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)

        TextInput({ placeholder: 'sk-...' })
          .type(InputType.Password)
          .onChange((value: string) => {
            this.apiKey = value;
          })
          .width('100%')

        Button('保存')
          .enabled(this.apiKey.trim().length > 0)
          .onClick(async () => {
            await KeyRepository.save(this.apiKey.trim());
            router.back();
          })

        Button('清除已保存的 Key')
          .onClick(async () => {
            await KeyRepository.clear();
            this.message = '已清除';
          })

        Text(this.message)
          .fontSize(12)
          .fontColor('#999999')
      }
      .width('100%')
      .height('100%')
      .padding(24)
      .justifyContent(FlexAlign.Center)
    }
  }
  ```

- [ ] **Step 3: 注册页面路由**

  修改 `HarmonyOS/entry/src/main/resources/base/profile/main_pages.json`：

  ```json
  {
    "src": [
      "pages/Index",
      "pages/SettingsPage"
    ]
  }
  ```

- [ ] **Step 4: 编译验证**

  ```bash
  cd HarmonyOS && ./hvigorw assembleHap --mode module -p product=default -p module=entry@default
  ```

  预期输出结尾：`BUILD SUCCESSFUL`。（此时还没有入口跳到 SettingsPage，属于预期——主页在 Task 6 接入。）

- [ ] **Step 5: Commit**

  ```bash
  git add HarmonyOS/entry/src/main/ets/storage/KeyRepository.ets \
    HarmonyOS/entry/src/main/ets/pages/SettingsPage.ets \
    HarmonyOS/entry/src/main/resources/base/profile/main_pages.json && \
  git commit -m "feat(harmonyos): add DeepSeek API key storage and settings page"
  ```

---

## Task 6: HttpClient + SnapshotStore + 主页手动刷新（过期标记）

主页展示余额 + 手动刷新；刷新失败保留旧快照并标过期。快照用 preferences 持久化——EntryAbility 与 FormExtensionAbility 属同一应用沙箱，默认同进程，可直接共享（官方限制是多进程并发，不涉及本场景）。

**Files:**

- Create: `HarmonyOS/entry/src/main/ets/network/HttpClient.ets`
- Create: `HarmonyOS/entry/src/main/ets/storage/SnapshotStore.ets`
- Modify: `HarmonyOS/entry/src/main/ets/pages/Index.ets`
- Modify: `HarmonyOS/entry/src/main/module.json5`（加 INTERNET 权限）

- [ ] **Step 1: 创建 HttpClient**

  写入 `HarmonyOS/entry/src/main/ets/network/HttpClient.ets`（HTTP 错误映射与 Swift `ProviderHTTPStatus.validate` 对齐：401/403 → `invalidCredential`，429 → `rateLimited`，其余非 2xx → `httpStatus:<code>`）：

  ```ts
  import { http } from '@kit.NetworkKit';

  export const DEEPSEEK_BALANCE_ENDPOINT = 'https://api.deepseek.com/user/balance';

  export async function fetchBalance(apiKey: string): Promise<string> {
    const request = http.createHttp();
    try {
      const response = await request.request(DEEPSEEK_BALANCE_ENDPOINT, {
        method: http.RequestMethod.GET,
        header: {
          'Authorization': `Bearer ${apiKey}`,
          'Accept': 'application/json'
        },
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 10000,
        readTimeout: 10000
      });
      const code = response.responseCode;
      if (code === 401 || code === 403) {
        throw new Error('invalidCredential');
      }
      if (code === 429) {
        throw new Error('rateLimited');
      }
      if (code < 200 || code >= 300) {
        throw new Error(`httpStatus:${code}`);
      }
      return response.result as string;
    } finally {
      request.destroy();
    }
  }
  ```

- [ ] **Step 2: 声明网络权限**

  修改 `HarmonyOS/entry/src/main/module.json5`，在 `"module"` 对象内追加 `requestPermissions`（与 `abilities` 平级）：

  ```json
  "requestPermissions": [
    {
      "name": "ohos.permission.INTERNET"
    }
  ]
  ```

- [ ] **Step 3: 创建 SnapshotStore**

  写入 `HarmonyOS/entry/src/main/ets/storage/SnapshotStore.ets`（含卡片/主页共用的展示文本格式化，键名固定 `balanceText` / `statusText` / `updatedAtText`）：

  ```ts
  import { preferences } from '@kit.ArkData';
  import { common } from '@kit.AbilityKit';
  import { UsageSnapshot } from '../providers/UsageSnapshot';

  const STORE_NAME = 'quotaglance_store';
  const SNAPSHOT_KEY = 'deepseek_snapshot';
  const STALE_KEY = 'deepseek_snapshot_stale';

  export interface StoredSnapshot {
    snapshot: UsageSnapshot | null;
    isStale: boolean;
  }

  export class SnapshotStore {
    private readonly store: preferences.Preferences;

    private constructor(store: preferences.Preferences) {
      this.store = store;
    }

    static async create(context: common.Context): Promise<SnapshotStore> {
      const store = await preferences.getPreferences(context, { name: STORE_NAME });
      return new SnapshotStore(store);
    }

    async save(snapshot: UsageSnapshot): Promise<void> {
      await this.store.put(SNAPSHOT_KEY, JSON.stringify(snapshot));
      await this.store.put(STALE_KEY, false);
      await this.store.flush();
    }

    async markStale(): Promise<void> {
      await this.store.put(STALE_KEY, true);
      await this.store.flush();
    }

    async load(): Promise<StoredSnapshot> {
      const raw = await this.store.get(SNAPSHOT_KEY, '') as string;
      const isStale = await this.store.get(STALE_KEY, false) as boolean;
      if (raw.length === 0) {
        return { snapshot: null, isStale: false };
      }
      try {
        return { snapshot: JSON.parse(raw) as UsageSnapshot, isStale: isStale };
      } catch (error) {
        return { snapshot: null, isStale: false };
      }
    }
  }

  export function formatSnapshotTexts(stored: StoredSnapshot): Record<string, string> {
    if (!stored.snapshot) {
      return {
        'balanceText': '未配置',
        'statusText': '打开应用录入 DeepSeek API Key',
        'updatedAtText': ''
      };
    }
    const snapshot = stored.snapshot;
    const primary = snapshot.balances[0];
    const texts: Record<string, string> = {
      'balanceText': `${primary.available.amount} ${primary.available.currency}`,
      'statusText': '正常',
      'updatedAtText': formatTime(snapshot.receivedAtMs)
    };
    if (stored.isStale) {
      texts['statusText'] = '更新失败 · 数据过期';
    } else if (snapshot.providerStatus !== 'active') {
      texts['statusText'] = '服务不可用';
    }
    return texts;
  }

  function formatTime(ms: number): string {
    const date = new Date(ms);
    const hours = date.getHours().toString().padStart(2, '0');
    const minutes = date.getMinutes().toString().padStart(2, '0');
    return `更新于 ${hours}:${minutes}`;
  }
  ```

- [ ] **Step 4: 重写主页 Index.ets**

  覆盖 `HarmonyOS/entry/src/main/ets/pages/Index.ets`（替换模板 "Hello World"）：

  ```ts
  import { router } from '@kit.ArkUI';
  import { common } from '@kit.AbilityKit';
  import { fetchBalance } from '../network/HttpClient';
  import { parseBalance } from '../providers/DeepSeekProvider';
  import { KeyRepository } from '../storage/KeyRepository';
  import { SnapshotStore, formatSnapshotTexts } from '../storage/SnapshotStore';

  @Entry
  @Component
  struct Index {
    @State balanceText: string = '--';
    @State statusText: string = '';
    @State updatedAtText: string = '';
    @State isRefreshing: boolean = false;

    private async reloadFromStore(): Promise<void> {
      const context = getContext(this) as common.UIAbilityContext;
      const store = await SnapshotStore.create(context);
      const texts = formatSnapshotTexts(await store.load());
      this.balanceText = texts['balanceText'];
      this.statusText = texts['statusText'];
      this.updatedAtText = texts['updatedAtText'];
    }

    private async refresh(): Promise<void> {
      this.isRefreshing = true;
      const apiKey = await KeyRepository.load();
      if (!apiKey) {
        this.isRefreshing = false;
        this.statusText = '请先在设置中录入 API Key';
        return;
      }
      const context = getContext(this) as common.UIAbilityContext;
      const store = await SnapshotStore.create(context);
      try {
        const body = await fetchBalance(apiKey);
        const snapshot = parseBalance(body, Date.now());
        await store.save(snapshot);
      } catch (error) {
        await store.markStale();
      }
      this.isRefreshing = false;
      await this.reloadFromStore();
    }

    aboutToAppear(): void {
      this.reloadFromStore();
    }

    build() {
      Column({ space: 16 }) {
        Text('QuotaGlance')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)

        Text(this.balanceText)
          .fontSize(40)
          .fontWeight(FontWeight.Bold)

        Text(this.statusText)
          .fontSize(14)
          .fontColor('#666666')

        Text(this.updatedAtText)
          .fontSize(12)
          .fontColor('#999999')

        Button(this.isRefreshing ? '刷新中…' : '手动刷新')
          .enabled(!this.isRefreshing)
          .onClick(() => {
            this.refresh();
          })

        Button('设置')
          .onClick(() => {
            router.pushUrl({ url: 'pages/SettingsPage' });
          })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    }
  }
  ```

- [ ] **Step 5: 编译 + 真机验证**

  ```bash
  cd HarmonyOS && ./hvigorw assembleHap --mode module -p product=default -p module=entry@default
  ```

  预期输出结尾：`BUILD SUCCESSFUL`。

  真机验证（Run 'entry' 安装后）：
  1. 设置页录入真实 DeepSeek API Key → 保存返回。
  2. **杀掉应用进程，重新打开** → 主页点「手动刷新」→ 显示余额与「正常」+ 更新时间（key 从 Asset Store 读回，不丢）。
  3. 开启飞行模式 → 点「手动刷新」→ 状态变为「更新失败 · 数据过期」，旧余额仍在。

- [ ] **Step 6: Commit**

  ```bash
  git add HarmonyOS/entry/src/main/ets/network/HttpClient.ets \
    HarmonyOS/entry/src/main/ets/storage/SnapshotStore.ets \
    HarmonyOS/entry/src/main/ets/pages/Index.ets \
    HarmonyOS/entry/src/main/module.json5 && \
  git commit -m "feat(harmonyos): add balance fetch, snapshot store, and home page refresh"
  ```

---

## Task 7: EntryFormAbility + form_config + WidgetCard（30 分钟定时刷新卡片）

推荐用 DevEco 脚手架（右键 `entry` → **New → Service Widget**，名称 `QuotaBalanceWidget`，尺寸勾 2\*2 和 2\*4）自动生成 `EntryFormAbility.ets`、`WidgetCard.ets`、`form_config.json` 及 `module.json5` 注册项，再用下列内容覆盖/核对（避免手写注册漏字段）。`updateDuration: 1` = 30 分钟（单位为 30 分钟的自然数）。卡片刷新走 `onUpdateForm` → 拉取 → `formProvider.updateForm`；FormExtensionAbility 10 秒无操作即被回收，单次 GET 完全够用；`backgroundTaskManager` 在卡片内被官方禁止，不碰。

**Files:**

- Create: `HarmonyOS/entry/src/main/ets/entryformability/EntryFormAbility.ets`
- Create: `HarmonyOS/entry/src/main/ets/widget/pages/WidgetCard.ets`
- Create: `HarmonyOS/entry/src/main/resources/base/profile/form_config.json`
- Modify: `HarmonyOS/entry/src/main/module.json5`（注册 extensionAbilities）
- Modify: `HarmonyOS/entry/src/main/resources/base/element/string.json`（卡片名称/描述字符串）

- [ ] **Step 1: 用 DevEco 生成卡片脚手架**

  右键 `entry` → New → Service Widget → ArkTS 卡片，名称 `QuotaBalanceWidget`，supportDimensions 勾选 `2*2`、`2*4` → Finish。确认生成：`ets/entryformability/EntryFormAbility.ets`、`ets/widget/pages/WidgetCard.ets`、`resources/base/profile/form_config.json`，且 `module.json5` 出现 `extensionAbilities` 注册块。

- [ ] **Step 2: 覆盖 EntryFormAbility**

  覆盖 `HarmonyOS/entry/src/main/ets/entryformability/EntryFormAbility.ets`（`onAddForm` 必须同步返回，先给占位数据再异步触发真实刷新；`onUpdateForm` 为 30 分钟定时回调）：

  ```ts
  import { formBindingData, FormExtensionAbility, formProvider } from '@kit.FormKit';
  import { Want } from '@kit.AbilityKit';
  import { hilog } from '@kit.PerformanceAnalysisKit';
  import { fetchBalance } from '../network/HttpClient';
  import { parseBalance } from '../providers/DeepSeekProvider';
  import { KeyRepository } from '../storage/KeyRepository';
  import { SnapshotStore, formatSnapshotTexts } from '../storage/SnapshotStore';

  const TAG = 'EntryFormAbility';
  const DOMAIN_NUMBER = 0xFF00;
  const FORM_ID_PARAM = 'ohos.extra.param.key.form_identity';

  export default class EntryFormAbility extends FormExtensionAbility {
    onAddForm(want: Want): formBindingData.FormBindingData {
      const formId = want.parameters?.[FORM_ID_PARAM] as string;
      if (formId) {
        this.refreshForm(formId);
      }
      const placeholder: Record<string, string> = {
        'balanceText': '加载中…',
        'statusText': '',
        'updatedAtText': ''
      };
      return formBindingData.createFormBindingData(placeholder);
    }

    onUpdateForm(formId: string): void {
      this.refreshForm(formId);
    }

    onRemoveForm(formId: string): void {
      hilog.info(DOMAIN_NUMBER, TAG, `onRemoveForm: ${formId}`);
    }

    private async refreshForm(formId: string): Promise<void> {
      try {
        const store = await SnapshotStore.create(this.context);
        const apiKey = await KeyRepository.load();
        if (apiKey) {
          try {
            const body = await fetchBalance(apiKey);
            const snapshot = parseBalance(body, Date.now());
            await store.save(snapshot);
          } catch (error) {
            await store.markStale();
          }
        }
        const texts = formatSnapshotTexts(await store.load());
        const data = formBindingData.createFormBindingData(texts);
        await formProvider.updateForm(formId, data);
      } catch (error) {
        hilog.error(DOMAIN_NUMBER, TAG, `refreshForm failed: ${(error as Error).message}`);
      }
    }
  }
  ```

- [ ] **Step 3: 覆盖 WidgetCard**

  覆盖 `HarmonyOS/entry/src/main/ets/widget/pages/WidgetCard.ets`（`@LocalStorageProp` 键名与 `formatSnapshotTexts` 输出一致；按钮 `postCardAction` router 拉起应用主页）：

  ```ts
  @Entry
  @Component
  struct WidgetCard {
    @LocalStorageProp('balanceText') balanceText: string = '--';
    @LocalStorageProp('statusText') statusText: string = '';
    @LocalStorageProp('updatedAtText') updatedAtText: string = '';

    build() {
      Column({ space: 6 }) {
        Text(this.balanceText)
          .fontSize(26)
          .fontWeight(FontWeight.Bold)
          .maxLines(1)

        Text(this.statusText)
          .fontSize(12)
          .fontColor('#666666')
          .maxLines(1)

        Text(this.updatedAtText)
          .fontSize(10)
          .fontColor('#999999')
          .maxLines(1)

        Button('打开应用')
          .fontSize(12)
          .height(28)
          .onClick(() => {
            postCardAction(this, {
              action: 'router',
              abilityName: 'EntryAbility'
            });
          })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .padding(12)
    }
  }
  ```

- [ ] **Step 4: 核对/覆盖 form_config.json**

  覆盖 `HarmonyOS/entry/src/main/resources/base/profile/form_config.json`（`updateDuration: 1` 即 30 分钟定时刷新）：

  ```json
  {
    "forms": [
      {
        "name": "QuotaBalanceWidget",
        "displayName": "$string:widget_display_name",
        "description": "$string:widget_description",
        "src": "./ets/widget/pages/WidgetCard.ets",
        "uiSyntax": "arkts",
        "isDefault": true,
        "updateEnabled": true,
        "updateDuration": 1,
        "defaultDimension": "2*2",
        "supportDimensions": [
          "2*2",
          "2*4"
        ]
      }
    ]
  }
  ```

- [ ] **Step 5: 核对 module.json5 注册与字符串资源**

  确认 `HarmonyOS/entry/src/main/module.json5` 的 `"module"` 内存在如下注册块（脚手架已生成则逐项核对，缺失字段补上）：

  ```json
  "extensionAbilities": [
    {
      "name": "EntryFormAbility",
      "srcEntry": "./ets/entryformability/EntryFormAbility.ets",
      "label": "$string:EntryFormAbility_label",
      "description": "$string:EntryFormAbility_desc",
      "type": "form",
      "metadata": [
        {
          "name": "ohos.extension.form",
          "resource": "$profile:form_config"
        }
      ]
    }
  ]
  ```

  确认 `HarmonyOS/entry/src/main/resources/base/element/string.json` 包含以下条目（脚手架已生成前两条则核对值，缺哪条补哪条）：

  ```json
  {
    "string": [
      {
        "name": "EntryFormAbility_label",
        "value": "QuotaGlance 余额"
      },
      {
        "name": "EntryFormAbility_desc",
        "value": "显示 DeepSeek 账户余额"
      },
      {
        "name": "widget_display_name",
        "value": "QuotaGlance 余额"
      },
      {
        "name": "widget_description",
        "value": "显示 DeepSeek 账户余额，每 30 分钟刷新"
      }
    ]
  }
  ```

  （`string.json` 里模板已有的 `module_desc` / `EntryAbility_desc` / `EntryAbility_label` 保持不动。）

- [ ] **Step 6: 编译 + 真机验证卡片**

  ```bash
  cd HarmonyOS && ./hvigorw assembleHap --mode module -p product=default -p module=entry@default
  ```

  预期输出结尾：`BUILD SUCCESSFUL`。

  真机验证：先在应用内录入 key 并手动刷新成功一次，然后回桌面 → 长按桌面空白处 → 服务卡片 → 找到「QuotaGlance 余额」→ 添加到桌面。预期：
  1. 添加瞬间短暂显示「加载中…」，随后显示余额（`onAddForm` 触发的异步刷新）。
  2. 点卡片「打开应用」→ 拉起应用主页（`postCardAction` router）。
  3. 断网等待下一个 30 分钟定时刷新（或抓 hilog 过滤 `EntryFormAbility` 观察 `onUpdateForm` 触发）→ 卡片显示「更新失败 · 数据过期」且余额仍在。

- [ ] **Step 7: Commit**

  ```bash
  git add HarmonyOS/entry/src/main/ets/entryformability/ \
    HarmonyOS/entry/src/main/ets/widget/ \
    HarmonyOS/entry/src/main/resources/ \
    HarmonyOS/entry/src/main/module.json5 && \
  git commit -m "feat(harmonyos): add balance service widget with 30-minute periodic refresh"
  ```

---

## Task 8: 端到端验收 + README 更新

**Files:**

- Modify: `README.md`

- [ ] **Step 1: 端到端真机 checklist（逐项人工确认）**

  - [ ] 全新安装应用 → 打开 → 主页显示「未配置 / 打开应用录入 DeepSeek API Key」。
  - [ ] 设置页录入真实 DeepSeek API Key → 保存。
  - [ ] 杀掉应用进程 → 重开 → 主页「手动刷新」→ 显示余额 + 「正常」+ 更新时间。
  - [ ] 桌面添加 2×2 卡片 → 显示同一余额；再添加 2×4 卡片确认两种尺寸都可用。
  - [ ] 卡片点「打开应用」→ 拉起主页。
  - [ ] 等待 ≥ 30 分钟（或观察 hilog 中 `onUpdateForm` 触发）→ 卡片时间戳更新。
  - [ ] 断网后等下一次卡片定时刷新（或断网点主页「手动刷新」）→ 显示「更新失败 · 数据过期」，旧余额保留。
  - [ ] 恢复网络再刷新 → 过期标记消失，余额更新。
  - [ ] 改一个错误的 key 保存 → 刷新 → 标过期（401 被正确映射为失败而不是崩溃）。

- [ ] **Step 2: 回归两端契约测试**

  ```bash
  swift test --filter DeepSeekContractTests
  ```

  预期：`1 test passed`。

  ```bash
  cd HarmonyOS && ./hvigorw test --mode module -p product=default -p module=entry@ohosTest
  ```

  预期：`DeepSeekContractTest` 全部 passed（需连接真机/模拟器；或用 DevEco 右键运行 `List.test.ets`）。

- [ ] **Step 3: 更新 README**

  在 `README.md` 末尾追加一节（中文）：

  ```markdown
  ## HarmonyOS 版本（自用最小闭环）

  `HarmonyOS/` 是鸿蒙端工程（ArkTS/ArkUI，DevEco Studio 标准 Stage 工程），
  目前打通 DeepSeek 余额查询的最小闭环：API Key 录入（Asset Store Kit 设备端安全存储）、
  主页手动刷新（失败保留旧快照并标过期）、2×2 / 2×4 万能卡片（30 分钟定时刷新）。

  - 构建前提：DevEco Studio（Compile SDK API 12+）+ 华为开发者账号，
    Signing Configs 勾选 Automatically generate signature 后调试签名直装本人手机；
    自用定位，未上架 AppGallery。
  - 两端解析行为由 `Contracts/Providers/deepseek/` 下的共享契约 fixture 锁定：
    macOS 侧 `swift test` 直读契约文件；鸿蒙侧 ohosTest 读 rawfile，
    改动契约后需运行 `scripts/sync-contracts-to-harmonyos.sh` 同步，
    两端测试跑的是同一批 JSON。
  ```

- [ ] **Step 4: Commit**

  ```bash
  git add README.md && \
  git commit -m "docs: document HarmonyOS minimal loop in README"
  ```

---

## 已知约束与备注

- **30 分钟是平台下限**：卡片 `updateDuration` 以 30 分钟为单位；WorkScheduler 最低 2 小时，后台轮询不可行（见 `docs/research/harmonyos-integration.md` 第 5 节）。低于 30 分钟的刷新只有前台态才可能，属于屏保模式（第二阶段），不在本计划。
- **FormExtensionAbility 10 秒回收**：每次刷新必须是一次快速请求，不做重试风暴；`backgroundTaskManager` 在卡片内被官方禁止。
- **preferences 多进程限制**：官方说明 preferences 不保证进程并发安全；EntryAbility 与 FormExtensionAbility 默认同属应用主进程，本用法安全。若未来给卡片配置独立进程，需改用其他共享机制。
- **key 不留持久化卸载残留**：未申请 `ohos.permission.STORE_PERSISTENT_DATA`，卸载应用即删除 key，符合自用定位。
- **CI**：自用阶段不接入鸿蒙构建；macOS 侧现有 CI 跑 `swift test` 即可覆盖契约测试。
