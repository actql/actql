import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {parameterPrograms} from './parameter-schema.mjs';
import {checkLocalInputSchemas} from './local-input-schema.mjs';

const registry = JSON.parse(readFileSync('spec/contracts/actql-protocol-schemas.json', 'utf8'));
test('both embedded Program input contracts exclude schema_ref', () => {
  checkLocalInputSchemas(registry);
  assert.equal(parameterPrograms(registry).length, 2);
});
test('each embedded input remains closed and cannot restore schema_ref', () => {
  for (let i = 0; i < 2; i++) {
    for (const mutate of [
      s => { s.properties.schema_ref = {type: 'string'}; },
      s => { s.additionalProperties = true; },
      s => { delete s.properties.schema; },
    ]) {
      const copy = structuredClone(registry);
      mutate(parameterPrograms(copy)[i].properties.inputs.additionalProperties.oneOf.find(s => s.properties?.carrier));
      assert.throws(() => checkLocalInputSchemas(copy));
    }
  }
});
