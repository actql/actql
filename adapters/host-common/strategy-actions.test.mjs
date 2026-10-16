import assert from 'node:assert/strict';
import test from 'node:test';
import {strategyAction} from './strategy-actions.mjs';

// Independent vectors for the existing Common numeric ABI, including invalid
// decisions. These are names for returned facts, not transition expectations.
const vectors = {
  holding: ['RetainedSiteStartClose', 'RetainedSiteAwaitClose',
    'RetainedSiteAwaitCleanup', 'RetainedSiteReleaseHolding',
    'RetainedSiteHoldingFinished', 'RetainedSiteHoldingInvalid'],
  close: ['RetainedSiteCloseStart', 'RetainedSiteCloseAwaitPhysical',
    'RetainedSiteCloseAwaitCleanup', 'RetainedSiteCloseFinished',
    'RetainedSiteCloseInvalid'],
  failure: ['FailedSiteAwaitStop', 'FailedSiteSettle', 'FailedSiteFinished'],
  taskSuccess: ['HostTaskCheckSiteCompletion', 'HostTaskRejectSiteCompletion',
    'HostTaskCheckCommonCompletion', 'HostTaskRejectCommonCompletion',
    'HostTaskRetainConnectorOutput', 'HostTaskRetainCoreOutput',
    'HostTaskSettleSiteOperation', 'HostTaskValidateManagedBinding',
    'HostTaskRejectManagedBinding', 'HostTaskSuccessFinished', 'HostTaskSuccessInvalid'],
  cleanup: ['HostCleanupRetryKnown', 'HostCleanupAwaitCloses', 'HostCleanupPending',
    'HostCleanupFailed', 'HostCleanupFinished'],
  outcome: ['HostTasksCompleted', 'HostTasksFailed', 'HostTaskRunInvalid'],
  managedFallback: ['ManagedCandidateLegacyAllowed', 'ManagedCandidateEstimateUnavailable',
    'ManagedCandidateTransferUnavailable', 'ManagedCandidateNoCompatibleStrategy'],
};

for (const [family, names] of Object.entries(vectors)) {
  test(`Common ${family} action names preserve the closed numeric ABI`, () => {
    assert.deepEqual(names.map((_, code) => strategyAction[family](code)), names);
    for (const unknown of [-1, names.length, 999, 0.5, NaN, Infinity,
      undefined, null, '0', 0n, true, {}, []]) {
      assert.throws(() => strategyAction[family](unknown));
    }
    // No invocation history: interpreting another result cannot change a name.
    assert.equal(strategyAction[family](0), names[0]);
  });
}
