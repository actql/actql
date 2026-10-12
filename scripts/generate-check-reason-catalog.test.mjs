import './fixtures/structured-program-diagnostic-identities.mjs';
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {readCheckReasonCatalog, validateCheckReasonCatalog} from './check-reason-catalog.mjs';
import {buildCheckReasonCatalog, generateCheckReasonCatalog} from './generate-check-reason-catalog.mjs';
const registry = JSON.parse(readFileSync(new URL('../spec/contracts/actql-protocol-schemas.json', import.meta.url)));
const catalog = readCheckReasonCatalog();
test('catalog generates current facts wire, SDK metadata and reference outputs with independently fixed current pins', () => {
  assert.equal(registry.artifact_schema_cids.check_reason,
    'sha256:1aa2b591972a9cd816826b6500f62ea38f8a4f5282e016b0d1153f8bb68e0742');
  assert.equal(registry.artifact_schema_cids.check_outcome,
    'sha256:8963bb2355a4bd563f01695dcc7fc2900b15a219d7afd56375e127322bf9e03a');
  assert.deepEqual(catalog.reason_schema, registry.artifact_schemas.check_reason);
  assert.equal(buildCheckReasonCatalog(catalog, registry).size, 3);
  generateCheckReasonCatalog();
});
test('catalog rejects malformed authoring and schema drift before generation', () => {
  const duplicate = structuredClone(catalog); duplicate.entries.push(duplicate.entries[0]);
  assert.throws(() => validateCheckReasonCatalog(duplicate));
  const leaked = structuredClone(catalog); leaked.entries[0].private = 'provider-message';
  assert.throws(() => validateCheckReasonCatalog(leaked));
  const malformed = structuredClone(catalog); malformed.entries[0].presentation.default.english = [''];
  assert.throws(() => validateCheckReasonCatalog(malformed));
  const missingMatch = structuredClone(catalog);
  delete missingMatch.entries.find(entry => entry.presentation.variants.length).presentation.variants[0].when;
  assert.throws(() => validateCheckReasonCatalog(missingMatch));
  const changed = structuredClone(catalog); changed.reason_schema.required.push('severity');
  assert.throws(() => buildCheckReasonCatalog(changed, registry));
});
