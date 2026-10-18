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
const currentCid = 'sha256:8dddb2a590629efb451ee5c579798da0ec64a674980601b49a97ff6a79140505';

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
  assert.equal(hash(original), 'sha256:806cd2ad9e32c71ac2a5879c896385a55d9ce388e7b782cb79209d93e556c771');
  assert.deepEqual(body.schema_snapshots.map(item => item.source_ref), [
    'connector://crm/main/r#v', 'connector://crm/right/r#v',
  ]);
  assert.deepEqual(body.connector_capabilities.map(item => item.source_ref), [
    'connector://crm/main/r#v', 'connector://crm/right/r#v',
  ]);
  assert(hash(original.connector_capabilities[0]) > hash(original.connector_capabilities[1]));
});
