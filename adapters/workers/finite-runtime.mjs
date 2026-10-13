import {instantiate} from '../../_build/workers/modules/bridge.mjs';
import {bindWorkersFiniteHost} from './finite.mjs';
import {createAuthorizationGate} from '../host-common/authorization-gate.mjs';

// Trusted installation only. Every opaque handle and authorization gate in
// this assembly belongs to one explicitly seeded production MoonBit runtime.
// Programs and received run materials cannot choose a runtime or verifier.
export function createWorkersFiniteRuntime(hashSeed, configuration) {
  const runtime = instantiate(hashSeed);
  const host = bindWorkersFiniteHost(runtime, configuration);
  const core = host.core;
  return Object.freeze({
    host,
    core,
    createAuthorizationGate(options) {
      if (options === null || typeof options !== 'object' ||
          Array.isArray(options) || Object.hasOwn(options, 'runtime')) {
        throw new TypeError('InvalidWorkersFiniteAuthorizationOptions');
      }
      return createAuthorizationGate({...options, runtime});
    },
  });
}
