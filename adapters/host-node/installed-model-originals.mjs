// Original Run admission bytes for fixed Model custody and cancellation.
// This packaging is not admission: the common Model original-Run reader
// re-admits every leaf and their exact linkage before the journal uses it.
import {canonicalJson} from '../../packages/sdk/host-port.mjs';
import {sourceAliasDataGeometry} from './source-alias-construction.mjs';

export function originalModelRunWire(compiled, runDefinition, maxBytes) {
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
  // All keys here are fixed ASCII and canonicalJson preserves data strings,
  // so its sorted key order leaves the measured UTF-8 size unchanged.
  if (maxBytes !== undefined &&
      sourceAliasDataGeometry(Object.freeze(originals)).jsonBytes > BigInt(maxBytes)) return undefined;
  return canonicalJson(originals);
}
