import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {
  checkResultPublicationTargetSchemas,
  planLimitTargetSchemas,
} from './result-publication-binding-schema.mjs';

const registry = JSON.parse(readFileSync('spec/contracts/actql-protocol-schemas.json', 'utf8'));

function accepts(schema, value) {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) return false;
  if (Object.keys(value).some(key => !Object.hasOwn(schema.properties, key))) return false;
  if (schema.required.some(key => !Object.hasOwn(value, key))) return false;
  return Object.entries(value).every(([key, field]) => {
    const rule = schema.properties[key];
    if (rule.const !== undefined) return field === rule.const;
    if (rule.enum !== undefined) return rule.enum.includes(field);
    return typeof field === rule.type && field.length >= (rule.minLength ?? 0)
      && (!rule.pattern || new RegExp(rule.pattern, 'u').test(field));
  });
}

test('both private Plan forms accept exactly an owned Result publication target', () => {
  checkResultPublicationTargetSchemas(registry);
  const targets = planLimitTargetSchemas(registry);
  const owned = {
    kind: 'result_publication',
    unit_definition_cid: `sha256:${'a'.repeat(64)}`,
    result_name: 'a~/b',
    measure: 'rows',
  };
  for (const target of targets) {
    const schema = target.oneOf.find(item => item.properties.kind.const === 'result_publication');
    assert.ok(accepts(schema, owned));
    assert.ok(accepts(schema, {...owned, measure: 'bytes'}));
    for (const invalid of [
      {...owned, result_name: ''},
      {...owned, unit_definition_cid: 'sha256:short'},
      {...owned, measure: 'nodes'},
      {...owned, stage_id: 'stage_0'},
      {kind: owned.kind, result_name: owned.result_name, measure: owned.measure},
    ]) assert.equal(accepts(schema, invalid), false);
  }
});
