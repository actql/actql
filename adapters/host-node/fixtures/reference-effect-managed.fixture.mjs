// The historical reference provider's real component work uses the SAME Plan
// and Ledger as its checked VALUES input. This qualifies the fixture's bounded
// in-process protocol, not an installed UPDATE provider or an HTTP transport.
import assert from 'node:assert/strict';
import {checked} from '../../host-common/runtime-result.mjs';
import {prepareInstalledPhysicalWritePlanRecipe, prepareInstalledEffectManagedPlan}
  from '../installed-effect-plan.mjs';

export function referenceEffectManagedFixture(runtime) {
  let recipe;
  const selected = moon => {
    if (recipe !== undefined) {assert.equal(moon, runtime);return recipe;}
    assert.equal(moon, runtime);
    // Its physical callback constructs two response records and an empty
    // Buffer, retaining the actual use CID. The common recipe separately
    // funds request/recovery/preview and Saved-control constructors.
    const zero = Object.freeze({nodes: 0n, text: 0n, wire: 0n});
    const response = Object.freeze({nodes: 3n, text: 71n, wire: 0n});
    recipe = prepareInstalledPhysicalWritePlanRecipe({moon, operation: 'reference.effect',
      inputLimits: {body: {maxBytes: 20000, maxNodes: 1000, maxDepth: 20},
        preview: {maxWireBytes: 20000, maxNodes: 1000, maxDepth: 20}},
      limits: {maxRequestBytes: 4096, maxRecoveryBytes: 4096, maxResponseBytes: 4096,
        maxOutcomeBytes: 4096, maxTransferBytes: 8192},
      construction: Object.freeze({retained: response, workspace: zero})});
    return recipe;
  };
  const original = run => {
    assert.equal(run.runtime, runtime);assert.equal(run.closed, false);
    assert.equal(checked(Reflect.apply(run.readPlan, runtime, [run.value, run.prepared, run.request])), run.operationPlan);
  };
  return Object.freeze({
    prepareManagedPlan(facts, inputs) {
      const recipe = selected(runtime);
      return prepareInstalledEffectManagedPlan({moon: runtime, facts, inputs,
        unit: {stageIndex: 0}, members: [{effectId: 'save'}], recipeFor: () => recipe});
    },
    async stage(facts, recovery, construct, aliasesRetired = () => true) {
      const run = facts.managedEffect, recipe = selected(facts.moon);
      original(run);
      const slot = recovery ? recipe.recoveryConstruction : recipe.captureConstruction;
      const operation = recipe.memberOperations[slot.operationIndex].operation;
      let token = checked(runtime.clientProgramInstalledEffectOperationConstructionRetain(
        run.value, run.prepared, run.request, run.operationPlan, 0, false,
        slot.operationIndex, 0, operation));
      let running = true, inputsReleased = false, disposed = false, active;
      const owner = Object.freeze({
        close() {
          if (token === undefined) return true;
          // A resolved callback does not acknowledge its returned payload,
          // physical ledger, or external receipt borrower. Common cuts those
          // SAME aliases before invoking this original retirement callback.
          if (running || !inputsReleased || !disposed || active !== undefined || !aliasesRetired()) return false;
          if (checked(runtime.clientProgramInstalledEffectOperationRetire(token, true)) !== true) return false;
          token = undefined;return true;
        },
        status: () => Object.freeze({pending: token !== undefined}),
      });
      facts.retainConstructionOwner(owner);
      checked(runtime.clientProgramInstalledEffectOperationConstructionBegin(token));
      const physical = async (row, invoke) => {
        original(run);assert.equal(active, undefined, 'the original apply loop awaits each reference row');
        const slot = recipe.physicalWrite, operation = recipe.rowOperations[slot.operationIndex].operation;
        const value = checked(runtime.clientProgramInstalledEffectOperationBorrow(run.value, run.prepared,
          run.request, run.operationPlan, row.memberIndex, true, slot.operationIndex, row.rowIndex, operation));
        active = {row, value, received: false};
        checked(runtime.clientProgramInstalledEffectOperationStart(value));
        const reply = await invoke();
        assert(Buffer.isBuffer(reply.observation.body));
        checked(runtime.clientProgramInstalledEffectOperationCharge(value, BigInt(reply.observation.body.byteLength)));
        active.received = true;return reply;
      };
      const completed = row => {
        assert.equal(active?.row.memberIndex, row.memberIndex);assert.equal(active?.row.rowIndex, row.rowIndex);
        assert.equal(active.received, true, 'only the actual received response can close physical custody');
        assert.equal(checked(runtime.clientProgramInstalledEffectOperationRetire(active.value, true)), true);
        active = undefined;
      };
      try {
        const stage = await construct({physical, completed, controlConstruction: run.controlConstruction});
        construct = facts = undefined;
        stage.referencePhysical = physical;stage.referenceCompleted = completed;
        let release = stage.releaseInputs, dispose = stage.dispose;
        stage.releaseInputs = async () => {
          if (inputsReleased) return;
          if (await release?.() === false) throw new Error('ReferenceEffectInputCleanupPending');
          release = undefined;inputsReleased = true;
        };
        stage.dispose = async () => {
          if (disposed) return;
          if (await dispose?.() === false) throw new Error('ReferenceEffectStageCleanupPending');
          dispose = undefined;disposed = true;
        };
        return stage;
      } finally {running = false;}
    },
  });
}
