import { hilog } from '@kit.PerformanceAnalysisKit';
import { Account } from '../storage/AccountStore';

const DOMAIN = 0x0000;
const TAG = 'QuotaGlance';

// Batch refresh coordinator. Mirrors
// Sources/QuotaGlanceCore/Refresh/RefreshCoordinator.swift semantics:
// - Only enabled accounts are refreshed, in the caller's account order
//   (Promise.all preserves input order like Swift's orderedSnapshots pass).
// - Per-account failure isolation: one failure never aborts the batch; the
//   account's snapshot store state (stale marking, preserved old data) is
//   owned by the injected refreshAccount seam (AccountService.refreshAccount).
// - Concurrent refreshes coalesce into one provider call per account: while
//   an account's fetch is in flight, later batches covering it await the same
//   promise instead of duplicating the request (Swift achieves this by
//   awaiting the in-flight Task; ArkTS cannot cancel promises, so a
//   *different* account set simply shares the overlapping per-account work
//   rather than superseding — the old batch still completes).
// - Outcome mirrors Swift RefreshOutcome: fresh when every enabled account
//   succeeded (vacuously true for an empty set), allFailed when none did,
//   partial otherwise.
// - Each completed run is reported once to the injected completion seam. The
//   host maps that outcome to overview, card and alert effects.
//
// Seams are injected as plain functions so tests can drive the coordinator
// without stores or providers (the Swift suite injects registry/credential
// store/aggregator the same way).
export type RefreshOutcome = 'fresh' | 'partial' | 'allFailed';

export interface RefreshResult {
  outcome: RefreshOutcome;
  // Account ids in caller order, split by per-account success. `succeeded`
  // feeds Index's once-per-launch pre-marking (markAccountsRefreshedThisLaunch).
  succeeded: string[];
  failed: string[];
}

export interface RefreshCoordinatorDeps {
  // Loads the persisted account list (AccountStore.load).
  loadAccounts: () => Promise<Account[]>;
  // Fetches one account through its provider and persists the outcome
  // (fresh snapshot save, or stale marking on failure). Throws on failure.
  refreshAccount: (account: Account) => Promise<void>;
  // Completed-run hook. AccountService maps it to host effects exactly once
  // for every outcome, including allFailed where stale state is observable.
  // The implementation must swallow its own asynchronous effect errors.
  onCompleted: (result: RefreshResult) => void;
}

export class RefreshCoordinator {
  private readonly deps: RefreshCoordinatorDeps;
  // accountId -> in-flight fetch promise. The dedup window closes when the
  // fetch settles (success or failure).
  private readonly inFlight: Map<string, Promise<boolean>> = new Map();

  constructor(deps: RefreshCoordinatorDeps) {
    this.deps = deps;
  }

  // All enabled accounts from the persisted list (the cold-launch, manual
  // refresh-all and background-scheduler path).
  async refreshAllEnabled(): Promise<RefreshResult> {
    return this.refreshAccounts(await this.deps.loadAccounts());
  }

  async refreshAccounts(accounts: Account[]): Promise<RefreshResult> {
    const enabled: Account[] = accounts.filter((account: Account) => account.isEnabled);
    const results: boolean[] = await Promise.all(
      enabled.map((account: Account) => this.refreshOne(account))
    );
    const succeeded: string[] = [];
    const failed: string[] = [];
    for (let i = 0; i < enabled.length; i++) {
      if (results[i]) {
        succeeded.push(enabled[i].id);
      } else {
        failed.push(enabled[i].id);
      }
    }
    let outcome: RefreshOutcome = 'partial';
    if (succeeded.length === enabled.length) {
      outcome = 'fresh';
    } else if (succeeded.length === 0) {
      outcome = 'allFailed';
    }
    hilog.info(DOMAIN, TAG, 'refresh batch %{public}s: %{public}d/%{public}d ok',
      outcome, succeeded.length, enabled.length);
    const result: RefreshResult = { outcome: outcome, succeeded: succeeded, failed: failed };
    this.deps.onCompleted(result);
    return result;
  }

  // Per-account dedup: an account already being fetched coalesces onto the
  // in-flight promise, so overlapping batches never duplicate a provider call.
  private refreshOne(account: Account): Promise<boolean> {
    const existing = this.inFlight.get(account.id);
    if (existing !== undefined) {
      hilog.info(DOMAIN, TAG, 'refresh coalesced: %{public}s', account.id);
      return existing;
    }
    const promise = this.runOne(account);
    this.inFlight.set(account.id, promise);
    promise.finally(() => {
      this.inFlight.delete(account.id);
    });
    return promise;
  }

  // Never throws: the boolean is the batch's per-account verdict. The seam
  // already persisted the stale marking before throwing.
  private async runOne(account: Account): Promise<boolean> {
    try {
      await this.deps.refreshAccount(account);
      return true;
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'refresh failed: %{public}s %{public}s', account.id, (error as Error).message);
      return false;
    }
  }
}
