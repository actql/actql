import {instantiate} from '../../_build/workers/modules/bridge.mjs';
import {installStrategyContributions} from '../connectors-workers/strategy.generated.mjs';
import {bindWorkersFiniteHost} from './finite.mjs';
import {bindLocalJsHost} from '../host-common/local-js-host.mjs';

// Standard Local-only entry: no request-supplied implementations or verifiers.
export function createWorkersHost(hashSeed) {
  return bindWorkersHost(instantiate(hashSeed));
}

// Host-implementation assembly, never request data. Preparation and execution
// must be linked into this same MoonBit runtime, including its Error tag table.
// Snapshot trusted exports before any await; a request cannot swap callbacks.
export function bindWorkersHost(runtime) {
  return bindLocalJsHost(runtime, installStrategyContributions);
}

// Trusted source-free installation. The accepting request Owner links its
// admission and Ledger into this same runtime; see finite.mjs.
export {bindWorkersFiniteHost};
