import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {runInNewContext} from 'node:vm';

const canonical = value => Array.isArray(value)
  ? '[' + value.map(canonical).join(',') + ']'
  : value !== null && typeof value === 'object'
    ? '{' + Object.keys(value).sort().map(key =>
      JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}'
    : JSON.stringify(value);
const pins = [
  ['actql-query-process-evidence',
    'sha256:cdaab753fd3c01709fbd9ae32022a8462bc8200edf1e9c93d533a293989f8a3b'],
  ['actql-query-two-receipt',
    'sha256:db7ce19477afd82a8488a9f64fd75697c850eaaccdc738995483cc138a06361a'],
];

test('packed query capability pins identify the authoritative contract bodies', () => {
  for (const [name, expected] of pins) {
    const body = JSON.parse(readFileSync(new URL(
      `../spec/contracts/${name}.json`, import.meta.url), 'utf8'));
    assert.equal('sha256:' + createHash('sha256').update(canonical(body)).digest('hex'),
      expected);
  }
});

test('packed query profile replaces obsolete capabilities with both current contracts', () => {
  const source = readFileSync(new URL('./fixtures/packed-public-query.mjs',
    import.meta.url), 'utf8');
  const start = source.indexOf('environment.connector_capabilities[0].capability_contract_cids');
  const end = source.indexOf('delete environment.evidence_bundle_cid;', start);
  assert.ok(start >= 0 && end > start, 'existing capability setup must be present');
  const environment = JSON.parse(readFileSync(new URL(
    '../adapters/host-node/fixtures/query-amount-environment.json', import.meta.url), 'utf8'));
  const before = structuredClone(environment);
  runInNewContext(source.slice(start, end), {environment}, {timeout: 1000});
  const expected = structuredClone(before);
  expected.connector_capabilities[0].capability_contract_cids = pins.map(([, cid]) => cid).sort();
  assert.deepEqual(JSON.parse(JSON.stringify(environment)), expected);
});
