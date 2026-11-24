import assert from 'node:assert/strict';
import {maxRecordUpdateFixtureTextUnits, recordUpdateFixtureSeed} from './cases.mjs';
import type {RecordMutationFixtureSeed} from './cases.mjs';
import type {Exchange} from '../../../adapters/site-node/https-exchange-fixture.mjs';
type FailureView = {name?: unknown; code?: unknown; message?: unknown} | undefined;

// Three finite fixture phases share one request history. The limit also bounds
// failed route observations and leaves room for a single overflow witness.
const maxRouteAttempts = 64;

export function createRecordUpdateProviderState<Fields extends Record<string, unknown>>(
  selection: RecordMutationFixtureSeed, initialFields: Fields, {allowCreate = false}: {allowCreate?: boolean} = {},
) {
  const seed = recordUpdateFixtureSeed(selection, {allowAbsent: allowCreate});
  const targetId = selection.recordId;
  const originalTarget = seed.target === null ? null : Object.freeze({...initialFields, ...seed.target});
  const control = Object.freeze({...initialFields, ...seed.control});
  let target: Readonly<Partial<Fields> & {id: string; name: string}> | null, writes: number,
    requests: {method: string; pathname: string; methodOverride?: Exchange['headers'][string] | null}[],
    failures: {name: unknown; code: unknown; message: unknown}[], attempts: number;
  function reset() {
    target = originalTarget;
    writes = 0;
    requests = [];
    failures = [];
    attempts = 0;
  }
  reset();

  function replaceTarget(name: string, fields: Partial<Fields>) {
    assert(typeof name === 'string' && name.length <= maxRecordUpdateFixtureTextUnits, 'InvalidRecordApprovalFixtureValue');
    assert.equal(writes, 0, 'Only one original physical write is expected');
    target = Object.freeze({...target, ...fields, id: targetId, name});
    writes++;
    return target;
  }

  function updateTarget(name: string, fields: Partial<Fields>) {
    assert(target !== null, 'The original UPDATE requires an existing target');
    return replaceTarget(name, fields);
  }

  function createTarget(name: string, fields: Partial<Fields>) {
    assert(allowCreate && target === null, 'The original CREATE requires an absent target');
    return replaceTarget(name, fields);
  }

  function deleteTarget() {
    assert(target !== null, 'The original DELETE requires an existing target');
    assert.equal(writes, 0, 'Only one original physical DELETE is expected');
    target = null;
    writes++;
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
        requests.push({method, pathname, ...(allowCreate
          ? {methodOverride: exchange.headers['x-http-method-override'] ?? null} : {})});
        return {body: action(exchange)};
      } catch (error) {
        const message = typeof (error as FailureView)?.message === 'string'
          ? ((error as FailureView)!.message as string).slice(0, 512) : undefined;
        failures.push({name: (error as FailureView)?.name, code: (error as FailureView)?.code, message});
        throw error;
      }
    }};
  }

  return Object.freeze({get target() {return target;}, control, route, updateTarget, createTarget, deleteTarget, reset,
    snapshot: () => structuredClone({writes, target, control, requests, failures})});
}
