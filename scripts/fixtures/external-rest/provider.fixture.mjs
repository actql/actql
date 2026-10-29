// Independent response DATA and row oracle only. The existing HTTPS fixture
// owns server/auth/transport and the actual Host owns every read lifecycle.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const original = JSON.parse(readFileSync(new URL('./connector.json', import.meta.url), 'utf8'));
const rows = Object.freeze([
  Object.freeze({id: 'alpha', amount: 7, note: 'e\u0301'}),
  Object.freeze({id: 'beta', amount: 2, note: '東京'}),
  Object.freeze({id: 'gamma', amount: 11, note: ''}),
]);

export function externalRestDefinition(origin) {
  const definition = structuredClone(original);
  definition.origin = origin;
  return definition;
}

export function externalRestProgram(connectorId) {
  return {version: 'actql/0.1', id: 'external-rest-read', stages: [{id: 'read',
    inputs: {customers: {connector: connectorId, resource: 'customers'}},
    steps: [{select: ['id', 'amount', 'note'], as: 'selected'}],
    results: {rows: {from: 'selected', fields: ['id', 'amount', 'note']}}}],
    results: {rows: {from: {stage: 'read', result: 'rows'}}}};
}

export function externalRestProvider({mode = 'paged'} = {}) {
  if (!['empty', 'one', 'paged', 'provider-error', 'cursor-cycle', 'oversized'].includes(mode)) {
    throw new Error('UnknownExternalRestFixtureMode');
  }
  const requests = [];
  return Object.freeze({
    handle({method, target}) {
      assert.equal(method, 'GET');
      const url = new URL(target, 'https://fixture.invalid');
      assert.equal(url.pathname, '/v1/customers');
      const query = [...url.searchParams];
      assert(query.length === 0 || query.length === 1 && query[0][0] === 'after' && query[0][1] === 'page-2');
      requests.push({method, target});
      if (mode === 'provider-error') return {status: 503, body: {error: 'unavailable'}};
      if (mode === 'empty') return {body: {data: [], next_cursor: null}};
      if (mode === 'one') return {body: {data: [rows[0]], next_cursor: null}};
      if (mode === 'oversized') return {body: ' '.repeat(257)};
      if (url.searchParams.has('after')) return {body: {data: [rows[2]],
        next_cursor: mode === 'cursor-cycle' ? 'page-2' : null}};
      return {body: {data: rows.slice(0, 2), next_cursor: 'page-2'}};
    },
    requests() { return requests.map(value => ({...value})); },
    assertRows(actual) {
      assert(!['provider-error', 'cursor-cycle', 'oversized'].includes(mode),
        'Refusal/failure fixtures have no success-row oracle');
      assert.deepEqual(actual, mode === 'empty' ? [] : mode === 'one' ? [rows[0]] : rows);
    },
  });
}
