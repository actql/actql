import assert from 'node:assert/strict';
import test from 'node:test';
import {installNodeClientRequestLookup} from './client-request-lookup.mjs';

const authorityScopeCid = `sha256:${'a'.repeat(64)}`;
const ref = {namespaceId: 'namespace-a', authorityScopeCid,
  runDefinitionCid: `sha256:${'b'.repeat(64)}`};
const control = {clientRequestAdmitRecord() {}};
const request = {principalId: 'principal-a', requestId: 'saved-request',
  connection: {mode: 'local', owner: 'local'}};

test('request lookup uses the authorized scope and projects retained Run',
  async () => {
    const selected = {namespaceId: 'namespace-a', authorityScopeCid};
    const observed = [];
    const lookup = installNodeClientRequestLookup({control,
      authorizedScope: async () => selected,
      journal: {lookup(key) {
        observed.push(key);
        return {ref, durability: 'durable',
          lookupExpiresAt: '2099-01-01T00:00:00.000Z'};
      }},
    });
    assert.deepEqual(await lookup(request), {kind: 'found',
      requestId: 'saved-request', ref, durability: 'durable',
      lookupExpiresAt: '2099-01-01T00:00:00.000Z'});
    assert.deepEqual(observed, [{namespaceId: 'namespace-a',
      authorityScopeCid, requestId: 'saved-request'}]);
  });

test('request lookup separates absent, unavailable, and denied', async () => {
  const selected = {namespaceId: 'namespace-a', authorityScopeCid};
  const install = (journal, authorizedScope = () => selected) =>
    installNodeClientRequestLookup({journal, control, authorizedScope});
  assert.deepEqual(await install({lookup: () => undefined})(request),
    {kind: 'not_found'});
  assert.deepEqual(await install({lookup() { throw new Error('store down'); }})
    (request), {kind: 'unknown', reason: 'request_store_unavailable'});
  await assert.rejects(install({lookup() {
    assert.fail('denied lookup reached the journal');
  }}, () => undefined)(request), /ClientRequestLookupDenied/u);
});
