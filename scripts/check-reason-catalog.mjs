// The public check catalog defines representation and presentation, not verdicts.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
export const checkReasonCatalogPath = new URL('../spec/contracts/actql-check-reason-catalog.json', import.meta.url);
const keys = (value, required, optional = []) => {
  assert(value && typeof value === 'object' && !Array.isArray(value));
  assert(required.every(key => Object.hasOwn(value, key)));
  assert(Object.keys(value).every(key => [...required, ...optional].includes(key)));
};
const text = value => assert(typeof value === 'string' && value.length > 0 && value.length <= 2048);
const presentation = value => {
  keys(value, ['key', 'english'], ['when']); text(value.key);
  assert(Array.isArray(value.english) && value.english.length === 2);
  value.english.forEach(text);
  if (value.when) {
    assert(Object.keys(value.when).length > 0);
    for (const [key, values] of Object.entries(value.when)) {
      assert(['issue', 'operation', 'document', 'constraint', 'domain', 'expected_type'].includes(key));
      (Array.isArray(values) ? values : [values]).forEach(text);
    }
  }
};
export function validateCheckReasonCatalog(catalog) {
  keys(catalog, ['version', 'revision', 'reason_schema', 'entries']);
  assert.equal(catalog.version, 'actql-check-reason-catalog/0.1');
  assert.match(catalog.revision, /^\d{4}-\d{2}-\d{2}\.\d+$/u);
  assert.equal(catalog.reason_schema.title, 'actql-check-reason-0.1');
  assert(Array.isArray(catalog.entries) && catalog.entries.length > 0);
  const codes = catalog.entries.map(entry => entry.code);
  assert.deepEqual(codes, [...new Set(codes)].sort());
  // Every explicit code-specific wire constraint needs catalog metadata.
  for (const rule of catalog.reason_schema.allOf) {
    const code = rule.if?.properties?.code;
    for (const known of code?.const ? [code.const] : code?.enum ?? []) {
      assert(codes.includes(known), `MissingCheckReasonCatalogCode:${known}`);
    }
  }
  for (const entry of catalog.entries) {
    keys(entry, ['code', 'condition', 'facts_schema', 'disclosure', 'locations',
      'default_severity', 'family', 'presentation', 'examples']);
    assert.match(entry.code, /^[a-z][a-z0-9_]{0,63}$/u); text(entry.condition); text(entry.disclosure);
    assert.equal(entry.facts_schema, '#/reason_schema');
    assert(['error', 'warning', 'info'].includes(entry.default_severity));
    assert(['input', 'requirement', 'limit', 'coverage'].includes(entry.family));
    assert(Array.isArray(entry.locations)); entry.locations.forEach(text);
    keys(entry.presentation, ['variants'], ['default']);
    if (entry.presentation.default) presentation(entry.presentation.default);
    assert(Array.isArray(entry.presentation.variants));
    entry.presentation.variants.forEach(presentation);
    assert(entry.presentation.default || entry.presentation.variants.length);
    assert(Array.isArray(entry.examples) && entry.examples.length > 0);
    for (const example of entry.examples) { keys(example, ['file', 'scenario']); text(example.file); text(example.scenario); }
  }
  return catalog;
}
export const readCheckReasonCatalog = () => validateCheckReasonCatalog(JSON.parse(readFileSync(checkReasonCatalogPath, 'utf8')));
export function checkReasonSchemaFromCatalog(catalog, parameterContractSchemaCid) {
  const schema = structuredClone(validateCheckReasonCatalog(catalog).reason_schema);
  // The existing declaration condition refers to the current checked contract.
  // Preserve the existing schema and its ordinary canonical preimage.
  for (const facts of schema.properties.facts.oneOf) {
    if (facts.properties.admission) facts.properties.admission.properties.contract_schema_cid.const = parameterContractSchemaCid;
  }
  return schema;
}
