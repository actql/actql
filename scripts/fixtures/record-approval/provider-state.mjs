import assert from 'node:assert/strict';
import {maxRecordUpdateFixtureTextUnits, recordUpdateFixtureSeed} from './cases.mjs';

// Three finite fixture phases share one request history. The limit also bounds
// failed route observations and leaves room for a single overflow witness.
const maxRouteAttempts = 64;

export function createRecordUpdateProviderState(selection, initialFields, {allowCreate = false} = {}) {
  const seed = recordUpdateFixtureSeed(selection, {allowAbsent: allowCreate});
  const targetId = selection.recordId;
  const originalTarget = seed.target === null ? null : Object.freeze({...initialFields, ...seed.target});
  const control = Object.freeze({...initialFields, ...seed.control});
  let target, writes, requests, failures, attempts;
  function reset() {
    target = originalTarget;
    writes = 0;
    requests = [];
    failures = [];
    attempts = 0;
  }
  reset();

  function replaceTarget(name, fields) {
    assert(typeof name === 'string' && name.length <= maxRecordUpdateFixtureTextUnits, 'InvalidRecordApprovalFixtureValue');
    assert.equal(writes, 0, 'Only one original physical write is expected');
    target = Object.freeze({...target, ...fields, id: targetId, name});
    writes++;
    return target;
  }

  function updateTarget(name, fields) {
    assert(target !== null, 'The original UPDATE requires an existing target');
    return replaceTarget(name, fields);
  }

  function createTarget(name, fields) {
    assert(allowCreate && target === null, 'The original CREATE requires an absent target');
    return replaceTarget(name, fields);
  }

  function route(method, pathname, action) {
    return {method, pathname, handle(exchange) {
      if (attempts >= maxRouteAttempts) {
        const error = new Error('RecordApprovalFixtureRequestLimit');
        if (attempts === maxRouteAttempts) {
          attempts++;
          failures.push({name: error.name, code: error.code, message: error.message});
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
        const message = typeof error?.message === 'string' ? error.message.slice(0, 512) : undefined;
        failures.push({name: error?.name, code: error?.code, message});
        throw error;
      }
    }};
  }

  return Object.freeze({get target() {return target;}, control, route, updateTarget, createTarget, reset,
    snapshot: () => structuredClone({writes, target, control, requests, failures})});
}
