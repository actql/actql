// The historical reference provider's real component work uses the SAME Plan
// and Ledger as its checked Program. This qualifies the fixture's bounded
// in-process protocol, not an installed UPDATE provider or an HTTP transport.
import assert from 'node:assert/strict';
import {checked} from '../../host-common/runtime-result.mjs';
import {prepareInstalledPhysicalWritePlanRecipe, prepareInstalledEffectManagedPlan}
  from '../installed-effect-plan.mjs';

export function referenceEffectManagedFixture(runtime, effectIds = ['save'], stageIndex = 0) {
  assert(Number.isSafeInteger(stageIndex) && stageIndex >= 0);
  assert(Array.isArray(effectIds) && effectIds.length > 0);
  assert(effectIds.every(id => typeof id === 'string' && id.length > 0));
  assert.equal(new Set(effectIds).size, effectIds.length);
  const members = Object.freeze(effectIds.map(effectId => Object.freeze({effectId})));
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
        unit: {stageIndex}, members, recipeFor: () => recipe});
    },
    async stage(facts, recovery, construct, aliasesRetired = () => true) {
      const run = facts.managedEffect, recipe = selected(facts.moon);
      original(run);
      const slot = recovery ? recipe.recoveryConstruction : recipe.captureConstruction;
      const operation = recipe.memberOperations[slot.operationIndex].operation;
      const tokens = [];
      let closed = false, started = false;
      let running = true, inputsReleased = false, disposed = false, active, physicalClosing = false;
      let release, dispose, releasing = false, disposing = false, closing = false;
      const retainInputCleanup = original => {
        assert.equal(typeof original, 'function');assert.equal(release, undefined);
        assert.equal(inputsReleased, false);release = original;
      };
      const retainStageCleanup = original => {
        assert.equal(typeof original, 'function');assert.equal(dispose, undefined);
        assert.equal(disposed, false);dispose = original;
      };
      const releaseInputs = async () => {
        if (running || releasing) return false;
        if (inputsReleased) return true;
        releasing = true;
        try {
          if (await release?.() === false) return false;
          release = undefined;inputsReleased = true;return true;
        } finally {releasing = false;}
      };
      const disposeStage = async () => {
        if (running || disposing) return false;
        if (disposed) return true;
        disposing = true;
        try {
          if (await dispose?.() === false) return false;
          dispose = undefined;disposed = true;return true;
        } finally {disposing = false;}
      };
      const owner = Object.freeze({
        releaseInputs,
        async close() {
          if (closed) return true;
          // A resolved callback does not acknowledge its returned payload,
          // physical ledger, or external receipt borrower. Common cuts those
          // SAME aliases before invoking this original retirement callback.
          if (running || closing || active !== undefined && !active.stopped || !aliasesRetired()) return false;
          closing = true;
          physicalClosing = true;
          try {
            if (!await releaseInputs() || !await disposeStage()) return false;
            if (active !== undefined) {
              // The local reference dispatch's actual flight ended, and its
              // input/ledger/Stage aliases are now cut. Unknown remains a
              // durable outcome; only this original physical child retires.
              active.row = undefined;
              if (checked(runtime.clientProgramInstalledEffectOperationRetire(active.value, true)) !== true) return false;
              active = undefined;
            }
            for (let index = 0; index < tokens.length; index++) {
              if (tokens[index] === undefined) continue;
              if (checked(runtime.clientProgramInstalledEffectOperationRetire(tokens[index], true)) !== true) return false;
              tokens[index] = undefined;
            }
            tokens.length = 0;closed = true;return true;
          } finally {closing = false;}
        },
        status: () => Object.freeze({pending: !closed}),
      });
      const physicalOwner = Object.freeze({
        close() {physicalClosing = true;},
        cleanup: () => physicalClosing && (active === undefined || active.stopped),
        cleanupPending: () => !physicalClosing || active !== undefined && !active.stopped,
      });
      facts.retainConstructionOwner(owner);
      const physical = async (row, invoke) => {
        assert.equal(physicalClosing, false);
        original(run);assert.equal(active, undefined, 'the original apply loop awaits each reference row');
        const slot = recipe.physicalWrite, operation = recipe.rowOperations[slot.operationIndex].operation;
        const value = checked(runtime.clientProgramInstalledEffectOperationBorrow(run.value, run.prepared,
          run.request, run.operationPlan, row.memberIndex, true, slot.operationIndex, row.rowIndex, operation));
        active = {row, value, received: false, stopped: false};
        checked(runtime.clientProgramInstalledEffectOperationStart(value));
        const reply = await invoke();
        assert(Buffer.isBuffer(reply.observation.body));
        checked(runtime.clientProgramInstalledEffectOperationCharge(value, BigInt(reply.observation.body.byteLength)));
        active.received = true;return reply;
      };
      const stopped = row => {
        if (active === undefined) return;
        assert.equal(active?.row.memberIndex, row.memberIndex);assert.equal(active?.row.rowIndex, row.rowIndex);
        active.stopped = true;
      };
      const completed = row => {
        assert.equal(active?.row.memberIndex, row.memberIndex);assert.equal(active?.row.rowIndex, row.rowIndex);
        assert.equal(active.received, true, 'only the actual received response can close physical custody');
        assert.equal(checked(runtime.clientProgramInstalledEffectOperationRetire(active.value, true)), true);
        active = undefined;
      };
      const beginConstruction = () => {
        assert.equal(started, false);started = true;
        original(run);
        // Original input metadata selects the actual row inventory first;
        // every member's body then precedes asynchronous export/Preview work.
        for (let memberIndex = 0; memberIndex < members.length; memberIndex++) {
          const token = checked(runtime.clientProgramInstalledEffectOperationConstructionRetain(
            run.value, run.prepared, run.request, run.operationPlan, memberIndex, false,
            slot.operationIndex, 0, operation));
          tokens.push(token);
          if (slot.inputExtent !== undefined) {
            const saved = facts.recovered.computation;
            const extent = slot.inputExtent(facts.control.effectComputationPreviewWire(saved.preview),
              saved.connectorRecovery, memberIndex);
            checked(runtime.clientProgramInstalledEffectOperationInputBegin(token, extent));
          } else checked(runtime.clientProgramInstalledEffectOperationConstructionBegin(token));
        }
      };
      try {
        if (recovery) {
          run.controlConstruction.retainRecoveredInputs(facts.control,
            run.definitionOriginal.allowed, run.definitionOriginal.definition,
            facts.recovered.computation.invocation, facts.recovered.computation.preview);
          beginConstruction();
        }
        const stage = await construct({physical, completed, stopped, physicalOwner, controlConstruction: run.controlConstruction,
          retainInputCleanup, retainStageCleanup, beginConstruction});
        assert.equal(started, true, 'actual capture must enter its original constructors before asynchronous capture work');
        // The original constructor has returned its Stage. Keep its retained
        // inputs/outputs and cleanup owner, but not completed decode workspace
        // while the later physical Effect uses this SAME Run.
        for (const token of tokens) {
          checked(runtime.clientProgramInstalledEffectOperationConstructionComplete(token));
        }
        stage.referencePhysical = physical;stage.referenceCompleted = completed;
        if (stage.releaseInputs !== undefined) {
          if (release === undefined) retainInputCleanup(stage.releaseInputs);
          else assert.equal(stage.releaseInputs, release);
        }
        if (stage.dispose !== undefined) {
          if (dispose === undefined) retainStageCleanup(stage.dispose);
          else assert.equal(stage.dispose, dispose);
        }
        stage.releaseInputs = async () => {
          if (!await releaseInputs()) throw new Error('ReferenceEffectInputCleanupPending');
        };
        stage.dispose = async () => {
          if (!await disposeStage()) throw new Error('ReferenceEffectStageCleanupPending');
        };
        return stage;
      } finally {construct = facts = undefined;running = false;}
    },
  });
}
