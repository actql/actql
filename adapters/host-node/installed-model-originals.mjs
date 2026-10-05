// Original Run admission bytes for fixed Model custody and cancellation.
// This packaging is not admission: the common Model original-Run reader
// re-admits every leaf and their exact linkage before the journal uses it.
import {canonicalJson} from './local-account-config.mjs';

export function originalModelRunWire(compiled, runDefinition) {
  const originals = {
    boundInvocationTemplateWire: compiled?.template?.wire,
    preparedInvocationWire: compiled?.preparedEvidence?.wire,
    runAuthorizationWire: compiled?.authorization?.wire,
    compiledPlanWire: compiled?.compiledPlan?.wire,
    runDefinitionWire: runDefinition?.wire,
  };
  if (Object.values(originals).some(wire => typeof wire !== 'string' || wire === '')) {
    throw new TypeError('InstalledModelOriginalRunUnavailable');
  }
  return canonicalJson(originals);
}
