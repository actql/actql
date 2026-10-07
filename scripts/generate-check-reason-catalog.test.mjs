import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {readCheckReasonCatalog, validateCheckReasonCatalog} from './check-reason-catalog.mjs';
import {buildCheckReasonCatalog, generateCheckReasonCatalog} from './generate-check-reason-catalog.mjs';
const registry = JSON.parse(readFileSync(new URL('../spec/contracts/actql-protocol-schemas.json', import.meta.url)));
const catalog = readCheckReasonCatalog();
test('catalog generates current facts wire, SDK metadata and reference outputs with unchanged pins', () => {
  assert.equal(registry.artifact_schema_cids.check_reason,
    'sha256:672a0158dfe91c7525eb7d02efbcf80b0094a05ecfa2b42fe08df945dd26fa53');
  assert.equal(registry.artifact_schema_cids.check_outcome,
    'sha256:2ceacaa6c399d8020b76c14ebd27a7f2ca5d975137dcdaff6b1907c9b4ef6311');
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
