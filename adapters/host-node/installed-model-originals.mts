// Original Run admission bytes for fixed Model custody and cancellation.
// This packaging is not admission: the common Model original-Run reader
// re-admits every leaf and their exact linkage before the journal uses it.
import {canonicalJson} from '../../packages/sdk/host-port.mjs';
import {sourceAliasDataGeometry} from './source-alias-construction.mjs';

type UncheckedWire = {readonly wire?: unknown};
type UncheckedCompiled = {readonly template?: UncheckedWire; readonly preparedEvidence?: UncheckedWire; readonly authorization?: UncheckedWire; readonly compiledPlan?: UncheckedWire};

export function originalModelRunWire(compiled: unknown, runDefinition: unknown, maxBytes?: number) {
  const originals = {
    boundInvocationTemplateWire: (compiled as UncheckedCompiled | null | undefined)?.template?.wire,
    preparedInvocationWire: (compiled as UncheckedCompiled | null | undefined)?.preparedEvidence?.wire,
    runAuthorizationWire: (compiled as UncheckedCompiled | null | undefined)?.authorization?.wire,
    compiledPlanWire: (compiled as UncheckedCompiled | null | undefined)?.compiledPlan?.wire,
    runDefinitionWire: (runDefinition as UncheckedWire | null | undefined)?.wire,
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
