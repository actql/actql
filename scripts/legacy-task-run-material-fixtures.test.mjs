import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {test} from 'node:test';
import {canonicalText} from './check-canonical-json.mjs';

const fixture = readFileSync(new URL('../src/run_publication_host/client_multi_source_wbtest.mbt', import.meta.url), 'utf8');
const resident = readFileSync(new URL('../src/run_publication_host/client_resident_source_wbtest.mbt', import.meta.url), 'utf8');
const wire = fixture.split('\n').find(line => line.startsWith('  #|')).slice(4);
const environment = JSON.parse(wire);
const hash = value => 'sha256:' + createHash('sha256').update(canonicalText(value)).digest('hex');
const currentCid = 'sha256:e1dc91d1c0f04c71dbe7ee5627e6928eb3cfc501592ed903fdd75287709c9117';

test('legacy Source fixture pins canonical ordered evidence with independent hashes', () => {
  assert.equal(wire, canonicalText(environment));
  const {evidence_bundle_cid: cid, ...body} = environment;
  assert.equal(cid, currentCid);
  assert.equal(hash(body), currentCid);
  for (const [section, entries] of Object.entries(body)) {
    if (!Array.isArray(entries)) continue;
    const hashes = entries.map(hash);
    assert.deepEqual(hashes, [...hashes].sort(), section);
  }
  assert(fixture.includes(`"${currentCid}",`));
  assert.equal(resident.match(new RegExp(currentCid, 'gu')).length, 2);
});

test('original refusal is only reversed capability evidence, not substituted Source contracts', () => {
  const {evidence_bundle_cid: _cid, ...body} = environment;
  assert.equal(body.connector_capabilities.length, 2);
  const original = {...body, connector_capabilities: [...body.connector_capabilities].reverse()};
  assert.equal(hash(original), 'sha256:adc1a3c4860fc608b843161e2d6940af7b30466b3fe6f798fdb6593511ed25de');
  // Reconstruct the pre-Bytes refusal with its own capability identities.
  const previous = structuredClone(body);
  for (const entry of previous.connector_capabilities) entry.capability_contract_cids = [
    'sha256:2e9959187141ac09be2f4684ac2d0dc7a2819059c6764b1a527b48e0cee6a08d',
    'sha256:dcf4b1e2c8a078d96f9160a75a9f8279047e7448ea39b3b882588e18b9ab0929',
  ];
  previous.connector_capabilities.sort((a,b) => hash(a) < hash(b) ? 1 : -1);
  assert.equal(hash(previous), 'sha256:ffdbff2b01c462b11cef68339cd18440d7547db44c17c6223e5d76a2e507ff8c');
  // Retain the earlier refusal preimage with its original dependency roles.
  const retained = structuredClone(body);
  // The retained wire predates this current Host policy declaration. Keep
  // its exact earlier preimage and member-order refusal independent.
  delete retained.host_policy_profile.text_time_evaluation;
  for (const entry of retained.connector_capabilities) entry.capability_contract_cids = [
    'sha256:cdaab753fd3c01709fbd9ae32022a8462bc8200edf1e9c93d533a293989f8a3b',
    'sha256:db7ce19477afd82a8488a9f64fd75697c850eaaccdc738995483cc138a06361a',
  ];
  retained.connector_capabilities.sort((a,b) => hash(a) < hash(b) ? -1 : 1);
  assert.equal(hash(retained), 'sha256:8dddb2a590629efb451ee5c579798da0ec64a674980601b49a97ff6a79140505');
  retained.connector_capabilities.reverse();
  assert.equal(hash(retained), 'sha256:806cd2ad9e32c71ac2a5879c896385a55d9ce388e7b782cb79209d93e556c771');
  assert.deepEqual(body.schema_snapshots.map(item => item.source_ref), [
    'connector://crm/main/r#v', 'connector://crm/right/r#v',
  ]);
  assert.deepEqual(body.connector_capabilities.map(item => item.source_ref), [
    'connector://crm/main/r#v', 'connector://crm/right/r#v',
  ]);
  for (const item of body.connector_capabilities) {
    assert.deepEqual(item.capability_contract_cids, [...item.capability_contract_cids].sort());
  }
  assert(hash(original.connector_capabilities[0]) > hash(original.connector_capabilities[1]));
});
