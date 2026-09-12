import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {checkSourceStateSchemas, sourceStateSchemas} from './source-state-schema.mjs';
import {verifyIdentity} from './check-canonical-json.mjs';

const read = path => JSON.parse(readFileSync(path, 'utf8'));
const registry = read('spec/contracts/actql-protocol-schemas.json');
const corpus = read('portability/corpus/source-state-requirement.json');

// Only this flat schema's keyword subset; fail on any unhandled keyword.
function valid(schema, value) {
  for (const key of Object.keys(schema)) assert.ok([
    'type', 'required', 'properties', 'additionalProperties', 'const', 'enum', 'minLength', 'pattern',
  ].includes(key), key);
  if (schema.type === 'object') {
    return value !== null && typeof value === 'object' && !Array.isArray(value)
      && schema.required.every(k => Object.hasOwn(value, k))
      && Object.entries(value).every(([k,v]) => Object.hasOwn(schema.properties,k) && valid(schema.properties[k],v));
  }
  return typeof value === 'string' && (!schema.const || value === schema.const)
    && (!schema.enum || schema.enum.includes(value))
    && [...value].length >= (schema.minLength ?? 0)
    && (!schema.pattern || new RegExp(schema.pattern, 'u').test(value));
}

test('source state requirements preserve Stage ownership in shape and identity', () => {
  checkSourceStateSchemas(registry);
  assert.equal(corpus.version, 'actql-source-state-requirement-vectors/0.1');
  const schema = sourceStateSchemas(registry)[0];
  for (const c of corpus.cases) {
    const preimage = {...corpus.base, ...c.changes};
    verifyIdentity(preimage, c.expected_cid);
    verifyIdentity(Object.fromEntries(Object.entries(preimage).reverse()), c.expected_cid);
    const envelope = {...preimage, requirement_cid:c.expected_cid};
    assert.ok(valid(schema,envelope));
    const missing = {...envelope}; delete missing.stage_id;
    for (const invalid of [missing, {...envelope,stage_id:''}, {...envelope,stage_id:0}, {...envelope,unknown:true}])
      assert.equal(valid(schema,invalid),false);
  }
  assert.notEqual(corpus.cases[0].expected_cid,corpus.cases[1].expected_cid);
  assert.throws(() => verifyIdentity({...corpus.base,...corpus.cases[1].changes},corpus.cases[0].expected_cid));
});
