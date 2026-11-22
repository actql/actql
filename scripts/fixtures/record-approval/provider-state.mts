import assert from 'node:assert/strict';
import {maxRecordUpdateFixtureTextUnits, recordUpdateFixtureSeed} from './cases.mjs';
import type {RecordApprovalSeed} from './cases.mjs';
import type {Exchange} from '../../../adapters/site-node/https-exchange-fixture.mjs';
type FailureView = {name?: unknown; code?: unknown; message?: unknown} | undefined;

// Three finite fixture phases share one request history. The limit also bounds
// failed route observations and leaves room for a single overflow witness.
const maxRouteAttempts = 64;

export function createRecordUpdateProviderState<Fields extends Record<string, unknown>>(
  selection: RecordApprovalSeed, initialFields: Fields,
) {
  const seed = recordUpdateFixtureSeed(selection);
  const originalTarget = Object.freeze({...initialFields, ...seed.target});
  const control = Object.freeze({...initialFields, ...seed.control});
  let target: typeof originalTarget, writes: number, requests: {method: string; pathname: string}[],
    failures: {name: unknown; code: unknown; message: unknown}[], attempts: number;
  function reset() {
    target = originalTarget;
    writes = 0;
    requests = [];
    failures = [];
    attempts = 0;
  }
  reset();

  function updateTarget(name: string, fields: Partial<Fields>) {
    assert(typeof name === 'string' && name.length <= maxRecordUpdateFixtureTextUnits, 'InvalidRecordApprovalFixtureValue');
    assert.equal(writes, 0, 'Only one original physical UPDATE is expected');
    target = Object.freeze({...target, ...fields, id: target.id, name});
    writes++;
    return target;
  }

  function route(method: string, pathname: string, action: (exchange: Exchange) => unknown) {
    return {method, pathname, handle(exchange: Exchange) {
      if (attempts >= maxRouteAttempts) {
        const error = new Error('RecordApprovalFixtureRequestLimit');
        if (attempts === maxRouteAttempts) {
          attempts++;
          failures.push({name: error.name, code: (error as NodeJS.ErrnoException).code, message: error.message});
        }
        throw error;
      }
      attempts++;
      try {
        assert.equal(exchange.method, method);
        assert.equal(exchange.pathname, pathname);
        assert.equal(exchange.authorized, true, 'The original credential header must be present');
        requests.push({method, pathname});
        return {body: action(exchange)};
      } catch (error) {
        const message = typeof (error as FailureView)?.message === 'string'
          ? ((error as FailureView)!.message as string).slice(0, 512) : undefined;
        failures.push({name: (error as FailureView)?.name, code: (error as FailureView)?.code, message});
        throw error;
      }
    }};
  }

  return Object.freeze({get target() {return target;}, control, route, updateTarget, reset,
    snapshot: () => structuredClone({writes, target, control, requests, failures})});
}
