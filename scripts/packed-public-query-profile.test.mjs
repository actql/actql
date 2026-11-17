import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {configurePublicQueryEvidenceContracts} from './fixtures/public-query-cases.mjs';

const canonical = value => Array.isArray(value)
  ? '[' + value.map(canonical).join(',') + ']'
  : value !== null && typeof value === 'object'
    ? '{' + Object.keys(value).sort().map(key =>
      JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}'
    : JSON.stringify(value);
const pins = [
  ['actql-query-process-evidence',
    'sha256:2e9959187141ac09be2f4684ac2d0dc7a2819059c6764b1a527b48e0cee6a08d'],
  ['actql-query-two-receipt',
    'sha256:dcf4b1e2c8a078d96f9160a75a9f8279047e7448ea39b3b882588e18b9ab0929'],
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
  const environment = JSON.parse(readFileSync(new URL(
    '../adapters/host-node/fixtures/query-amount-environment.json', import.meta.url), 'utf8'));
  const before = structuredClone(environment);
  configurePublicQueryEvidenceContracts(environment);
  const expected = structuredClone(before);
  expected.connector_capabilities[0].capability_contract_cids = pins.map(([, cid]) => cid).sort();
  assert.deepEqual(JSON.parse(JSON.stringify(environment)), expected);
});
