import './fixtures/structured-program-diagnostic-identities.mjs';
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {readCheckReasonCatalog, validateCheckReasonCatalog, checkReasonSchemaFromCatalog} from './check-reason-catalog.mjs';
import {buildCheckReasonCatalog, generateCheckReasonCatalog} from './generate-check-reason-catalog.mjs';
const registry = JSON.parse(readFileSync(new URL('../spec/contracts/actql-protocol-schemas.json', import.meta.url)));
const catalog = readCheckReasonCatalog();
const fixed = JSON.parse(readFileSync(new URL('./fixtures/check-domain-carrier-identities.json', import.meta.url)));
const canonicalPreimage = value => value && typeof value === 'object'
  ? Array.isArray(value) ? '[' + value.map(canonicalPreimage).join(',') + ']'
    : '{' + Object.keys(value).sort().map(key => JSON.stringify(key) + ':' + canonicalPreimage(value[key])).join(',') + '}'
  : JSON.stringify(value);
test('public Reason catalog retains the canonical Parameter schema pin without substitution', () => {
  const expected = 'sha256:' + createHash('sha256')
    .update(canonicalPreimage(registry.schemas.canonical_value_contract)).digest('hex');
  assert.equal(expected, fixed.canonicalValueContractCid);
  const declarations = catalog.reason_schema.properties.facts.oneOf.filter(facts => facts.properties.admission);
  assert.equal(declarations.length, 1);
  assert.equal(declarations[0].properties.admission.properties.contract_schema_cid.const, expected);
  assert.deepEqual(catalog.reason_schema, registry.artifact_schemas.check_reason);
  const stale = structuredClone(catalog);
  stale.reason_schema.properties.facts.oneOf.find(facts => facts.properties.admission)
    .properties.admission.properties.contract_schema_cid.const = 'sha256:' + '0'.repeat(64);
  assert.throws(() => checkReasonSchemaFromCatalog(stale, expected),
    {code: 'ERR_ASSERTION', operator: 'strictEqual', expected,
      actual: 'sha256:' + '0'.repeat(64), message: /^StaleCheckReasonParameterContractSchema(?:\n|$)/u});
  assert.throws(() => buildCheckReasonCatalog(stale, registry),
    {code: 'ERR_ASSERTION', operator: 'strictEqual', expected,
      actual: 'sha256:' + '0'.repeat(64), message: /^StaleCheckReasonParameterContractSchema(?:\n|$)/u});
});
test('catalog generates current facts wire, SDK metadata and reference outputs with independently fixed current pins', () => {
  assert.equal(registry.artifact_schema_cids.check_reason,
    fixed.checkSchemas.reason.cid);
  assert.equal(registry.artifact_schema_cids.check_outcome,
    fixed.checkSchemas.outcome.cid);
  // The public catalog already names the current checked grammar. Generation
  // validates the original body instead of substituting an old template pin.
  assert.deepEqual(catalog.reason_schema, registry.artifact_schemas.check_reason);
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
