import {instantiate} from '../../_build/workers/modules/bridge.mjs';
import {bindWorkersFiniteHost} from './finite.mjs';
import {createAuthorizationGate} from '../host-common/authorization-gate.mjs';

import type {WorkersFiniteAuthorization, WorkersFiniteAuthorizationOptions, WorkersFiniteConfiguration,
  createWorkersFiniteRuntime as InstalledWorkersFiniteRuntime} from '../../packages/run-host-core/workers-finite.js';

// Trusted installation only. Every opaque handle and authorization gate in
// this assembly belongs to one invocation-created production MoonBit runtime
// driving one original Run. Do not cache the returned assembly across requests.
// Programs and received run materials cannot choose a runtime or verifier.
export function createWorkersFiniteRuntime(hashSeed: number, configuration: WorkersFiniteConfiguration): ReturnType<typeof InstalledWorkersFiniteRuntime> {
  const runtime = instantiate(hashSeed);
  const host = bindWorkersFiniteHost(runtime, configuration);
  const core = host.core;
  return Object.freeze({
    host,
    core,
    createAuthorizationGate(options: WorkersFiniteAuthorizationOptions) {
      if (options === null || typeof options !== 'object' ||
          Array.isArray(options) || Object.hasOwn(options, 'runtime')) {
        throw new TypeError('InvalidWorkersFiniteAuthorizationOptions');
      }
      return createAuthorizationGate({...options, runtime}) as WorkersFiniteAuthorization;
    },
  });
}
