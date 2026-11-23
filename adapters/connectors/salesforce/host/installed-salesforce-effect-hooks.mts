// The installed Host's Effect Site hooks for a Salesforce Effect installation:
// the Host's capture and recovery facts projected onto the factory's inputs.
// This is the only place that names the Host's Effect Site fact shape; the
// factory keeps its own inputs.
import {checked} from '../../../host-common/runtime-result.mjs';
import {localContractLimits} from '../../../host-node/local-values-plan.mjs';
import {salesforceEffectUnit} from './installed-salesforce-effect.mjs';

import type {loadInstalledSalesforceEffect} from './installed-salesforce-effect.mjs';

type Installed = Awaited<ReturnType<typeof loadInstalledSalesforceEffect>>;
type Effect = Pick<Installed, 'environmentWire' | 'prepareManagedPlan' | 'targetReadAuthorization' |
  'targetReadInventory' | 'prepareCaptured' | 'prepareRecovered'>;
type Inventory = Parameters<Effect['targetReadInventory']>[0];
type Moon = Parameters<typeof salesforceEffectUnit>[0] & Readonly<{
  strategyPublicationAdmit(kind: 'compiled_plan', wire: string, maxBytes: number, maxNodes: number,
    maxDepth: number): unknown;
  clientProgramEffectCompilationCompiledPlanWire(compilation: unknown): string;
}>;
type Continuation = Readonly<{assertContinuationCurrent?: () => unknown; signal?: AbortSignal;
  targetReads?: unknown; control: unknown; store: unknown; managedEffect: unknown}>;
type Selection = Pick<Inventory, 'updateTargetSelections' | 'assertUpdateSelectionCurrent'>;
type TargetFacts = Selection & Readonly<{moon: Parameters<typeof salesforceEffectUnit>[0];
  prepared: unknown; compilation: unknown}>;
type CaptureFacts = Omit<TargetFacts, 'moon'> & Continuation & Readonly<{moon: Moon;
  publicationPlan: Readonly<{invocationOwner: unknown; contractLimits: Readonly<{
    maxWireBytes: number; maxNodes: number; maxDepth: number}>}>;
  execution: unknown; checkedHost: unknown; identity: unknown; definition: unknown}>;
type RecoveryFacts = Continuation & Readonly<{moon: unknown; recovered: Selection;
  continuation: unknown; retainRecoveryOwner?: unknown}>;

export function salesforceEffectSiteHooks(effect: Effect) {
  if (typeof effect?.prepareCaptured !== 'function' ||
      typeof effect.prepareRecovered !== 'function' ||
      typeof effect.environmentWire !== 'string') {
    throw Object.assign(new Error('InvalidInstalledEffectHooks'),
      {code: 'InvalidInstalledEffectHooks'});
  }
  return Object.freeze({
    environmentWire: effect.environmentWire,
    prepareManagedPlan: effect.prepareManagedPlan,
    targetReadAuthorization: effect.targetReadAuthorization,
    targetReadInventory: (facts: TargetFacts) => effect.targetReadInventory({moon: facts.moon,
      prepared: facts.prepared,
      updateTargetSelections: facts.updateTargetSelections,
      assertUpdateSelectionCurrent: facts.assertUpdateSelectionCurrent,
      unit: salesforceEffectUnit(facts.moon, facts.compilation)}),
    prepareCaptured: (facts: CaptureFacts) => {
      const {moon, publicationPlan: plan, compilation} = facts;
      const current = facts.assertContinuationCurrent;
      return effect.prepareCaptured({moon, control: facts.control,
        store: facts.store, execution: facts.execution,
        managedEffect: facts.managedEffect,
        checkedHost: facts.checkedHost, prepared: facts.prepared,
        identity: facts.identity, plan,
        previewContext: {runDefinition: facts.definition,
          runInvocation: plan.invocationOwner,
          compiledPlan: checked(moon.strategyPublicationAdmit('compiled_plan',
            moon.clientProgramEffectCompilationCompiledPlanWire(compilation),
            plan.contractLimits.maxWireBytes, plan.contractLimits.maxNodes,
            plan.contractLimits.maxDepth))},
        unit: salesforceEffectUnit(moon, compilation), signal: facts.signal,
        targetReads: facts.targetReads,
        assertContinuationCurrent: current === undefined ? undefined
          : () => Reflect.apply(current, facts, []),
        updateTargetSelections: facts.updateTargetSelections,
        assertUpdateSelectionCurrent: facts.assertUpdateSelectionCurrent});
    },
    prepareRecovered: (facts: RecoveryFacts) => {
      const current = facts.assertContinuationCurrent;
      return effect.prepareRecovered({moon: facts.moon,
      control: facts.control, store: facts.store, recovered: facts.recovered,
      managedEffect: facts.managedEffect,
      continuation: facts.continuation, contractLimits: localContractLimits,
      signal: facts.signal, retainRecoveryOwner: facts.retainRecoveryOwner,
      targetReads: facts.targetReads,
      assertContinuationCurrent: current === undefined ? undefined
        : () => Reflect.apply(current, facts, []),
      updateTargetSelections: facts.recovered.updateTargetSelections,
      assertUpdateSelectionCurrent: facts.recovered.assertUpdateSelectionCurrent});
    },
  });
}
