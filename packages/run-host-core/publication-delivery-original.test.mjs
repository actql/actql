import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import test from 'node:test';
import {canonicalText} from '../../scripts/check-canonical-json.mjs';
import {admitPublicationContract, openResultDeliveryControl} from './index.mjs';

const limits = {maxWireBytes: 100000, maxNodes: 10000, maxDepth: 64};
const fixed = digit => `sha256:${digit.repeat(64)}`;
const body = {
  version: 'actql-result-retention-policy/0.1',
  retention_contract_cid: fixed('b'), effective_data_policy_cid: fixed('a'),
  available_until: '2026-09-18T01:00:00.000Z',
  delete_by: '2026-09-18T02:00:00.000Z',
  extension_ceiling_at: '2026-09-18T03:00:00.000Z',
  metadata_retention_policy_cid: fixed('c'),
  metadata_delete_by: '2026-09-18T04:00:00.000Z',
  clock_contract_cid: fixed('d'),
};
const identity = `sha256:${createHash('sha256')
  .update(canonicalText(body)).digest('hex')}`;
const wire = canonicalText({...body, effective_retention_policy_cid: identity});

test('delivery reuses the original publication without JSON parsing', () => {
  const original = admitPublicationContract('result_retention_policy', wire, limits);
  const control = openResultDeliveryControl();
  const parse = JSON.parse;
  let parses = 0;
  JSON.parse = (...args) => { parses += 1; return Reflect.apply(parse, JSON, args); };
  let first, second;
  try {
    first = control.fromPublication(original);
    second = control.fromPublication(original);
  } finally { JSON.parse = parse; }
  assert.equal(parses, 0);
  assert.deepEqual(first, {name: 'result_retention_policy',
    identityField: 'effective_retention_policy_cid', identity, wire});
  assert.deepEqual(second, first);
  assert(Object.isFrozen(first));
  assert.equal(control.resultMetadataRetentionState(first,
    '2026-09-18T00:00:00.000Z'), 'retained');
  assert.equal(control.resultMetadataRetentionState(second,
    '2026-09-18T04:00:00.000Z'), 'delete_due');
});

test('delivery refuses copied and foreign publications before reading fields', async () => {
  const original = admitPublicationContract('result_retention_policy', wire, limits);
  const control = openResultDeliveryControl();
  const foreign = await import('./index.mjs?foreign-publication-delivery');
  let reads = 0;
  const proxy = new Proxy(original, {get() {
    reads += 1;
    throw new Error('CopiedPublicationFieldRead');
  }});
  for (const value of [undefined, null, {}, original.token, {...original},
    {...original, cid: fixed('e')}, {...original, wire: '{}'}, proxy,
    foreign.admitPublicationContract('result_retention_policy', wire, limits)]) {
    assert.throws(() => control.fromPublication(value),
      {name: 'TypeError', message: 'ForeignRunHostPublication'});
  }
  assert.equal(reads, 0);
  assert.equal(control.fromPublication(original).identity, identity);
});

test('delivery checks the requested kind using original nominal facts', () => {
  const original = admitPublicationContract('result_retention_policy', wire, limits);
  const control = openResultDeliveryControl();
  assert.equal(control.fromPublication(original, 'result_retention_policy').identity,
    identity);
  assert.throws(() => control.fromPublication(original, 'result_manifest'),
    {name: 'TypeError', message: 'RunHostPublicationKindMismatch'});
  assert.equal(control.fromPublication(original).identity, identity);
});
