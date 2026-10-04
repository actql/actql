// The installed Host's Effect Site hooks for a Salesforce Effect installation:
// the Host's capture and recovery facts projected onto the factory's inputs.
// This is the only place that names the Host's Effect Site fact shape; the
// factory keeps its own inputs.
import {checked} from '../../../host-common/runtime-result.mjs';
import {localContractLimits} from '../../../host-node/local-values-plan.mjs';
import {salesforceEffectUnit} from './installed-salesforce-effect.mjs';

export function salesforceEffectSiteHooks(effect) {
  if (typeof effect?.prepareCaptured !== 'function' ||
      typeof effect.prepareRecovered !== 'function' ||
      typeof effect.environmentWire !== 'string') {
    throw Object.assign(new Error('InvalidInstalledEffectHooks'),
      {code: 'InvalidInstalledEffectHooks'});
  }
  return Object.freeze({
    environmentWire: effect.environmentWire,
    targetReadAuthorization: effect.targetReadAuthorization,
    targetReadInventory: facts => effect.targetReadInventory({moon: facts.moon,
      prepared: facts.prepared,
      unit: salesforceEffectUnit(facts.moon, facts.compilation)}),
    prepareCaptured: facts => {
      const {moon, publicationPlan: plan, compilation} = facts;
      return effect.prepareCaptured({moon, control: facts.control,
        store: facts.store, execution: facts.execution,
        checkedHost: facts.checkedHost, prepared: facts.prepared,
        identity: facts.identity, plan,
        previewContext: {runDefinition: facts.definition,
          runInvocation: plan.invocationOwner,
          compiledPlan: checked(moon.strategyPublicationAdmit('compiled_plan',
            moon.clientProgramEffectCompilationCompiledPlanWire(compilation),
            plan.contractLimits.maxWireBytes, plan.contractLimits.maxNodes,
            plan.contractLimits.maxDepth))},
        unit: salesforceEffectUnit(moon, compilation), signal: facts.signal,
        targetReads: facts.targetReads});
    },
    prepareRecovered: facts => effect.prepareRecovered({moon: facts.moon,
      control: facts.control, store: facts.store, recovered: facts.recovered,
      continuation: facts.continuation, contractLimits: localContractLimits,
      signal: facts.signal, retainRecoveryOwner: facts.retainRecoveryOwner,
      targetReads: facts.targetReads}),
  });
}
