import './fixtures/structured-program-diagnostic-identities.mjs';
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {readCheckReasonCatalog, validateCheckReasonCatalog, checkReasonSchemaFromCatalog} from './check-reason-catalog.mjs';
import {buildCheckReasonCatalog, generateCheckReasonCatalog} from './generate-check-reason-catalog.mjs';
const registry = JSON.parse(readFileSync(new URL('../spec/contracts/actql-protocol-schemas.json', import.meta.url)));
const catalog = readCheckReasonCatalog();
const fixed = JSON.parse(readFileSync(new URL('./fixtures/check-domain-carrier-identities.json', import.meta.url)));
test('catalog generates current facts wire, SDK metadata and reference outputs with independently fixed current pins', () => {
  assert.equal(registry.artifact_schema_cids.check_reason,
    fixed.checkSchemas.reason.cid);
  assert.equal(registry.artifact_schema_cids.check_outcome,
    fixed.checkSchemas.outcome.cid);
  // The retained catalog template is specialized by its existing owner for
  // the current checked grammar; do not rewrite its original template pin.
  assert.deepEqual(checkReasonSchemaFromCatalog(catalog,
    fixed.canonicalValueContractCid),
    registry.artifact_schemas.check_reason);
  assert.deepEqual(registry.artifact_schemas.check_reason, fixed.checkSchemas.reason.body);
  assert.deepEqual(registry.artifact_schemas.check_outcome, fixed.checkSchemas.outcome.body);
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
