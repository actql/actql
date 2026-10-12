import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';

// Hash normative JSON and independently authored preimages, not product output.
const read = path => readFileSync(path, 'utf8');
const json = path => JSON.parse(read(path));
const canonical = value => Array.isArray(value) ? '[' + value.map(canonical).join(',') + ']'
  : value !== null && typeof value === 'object' ? '{' + Object.keys(value).sort()
    .map(key => JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}' : JSON.stringify(value);
const cid = value => 'sha256:' + createHash('sha256').update(canonical(value)).digest('hex');
const hasPin = (path, expected) => assert.ok(read(path).includes('"' + expected + '"'), path);
const fixtureBody = (path, name) => {
  const match = read(path).match(new RegExp('let ' + name + ' : String =\\s*\\n\\s*#\\|([^\\n]+)'));
  assert.ok(match, name);
  return JSON.parse(match[1]);
};

test('current Catalog dependency fixtures pin the normative environment grammar', () => {
  const expected = cid(json('spec/contracts/actql-check-environment.json'));
  assert.equal(expected, 'sha256:2edbaec105871702a061b1e21f0ff929cc7c76f4010bcd3f681e0d7ad89b43fb');
  for (const name of ['catalog_body_dependencies_test', 'lookup_body_dependencies_test']) {
    hasPin('src/check_environment/' + name + '.mbt', expected);
  }
});

test('current Program roots pin the normative closed source schema', () => {
  const body = json('spec/contracts/actql-protocol-schemas.json').artifact_schemas
    .executable_plan.properties.execution_material.properties.program;
  const expected = cid(body);
  assert.equal(expected, 'sha256:1e63d8fb2cdfb0a8b54811762a96091ce2b7bc107089fd1682a76b1dbd57919b');
  hasPin('src/pipeline_check_context/core_contracts_test.mbt', expected);
});

test('managed completion fixture pins the complete normative profile', () => {
  const expected = cid(json('spec/contracts/actql-managed-retained-execution.json'));
  assert.equal(expected, 'sha256:4fbaedc48f7386a6b379b8190d9526c8950ea505defe24115baad2cce7810077');
  hasPin('src/execution_relation/managed_completion_wbtest.mbt', expected);
});

test('INSTR and STRPOS fixtures retain the independent complete-fragment preimages', () => {
  const fixture = json('portability/corpus/translate-instr-identities.json');
  assert.equal(fixture.cases.length, 4);
  for (const item of fixture.cases) {
    assert.equal(cid(item.body), item.cid);
    assert.equal(canonical(item.body), item.canonical);
    assert.equal(Buffer.byteLength(item.canonical), item.bytes);
    hasPin('src/execution_relation/translate_instr_identity_wbtest.mbt', item.cid);
  }
});

for (const [path, prefix] of [
  ['src/platform_native/remote_resident_host/effect_source_fixture_wbtest.mbt', 'resident_effect_source'],
  ['src/platform_native/remote_standard_host/retained_task_source_wbtest.mbt', 'retained_source'],
]) test(prefix + ' uses the complete normative fragment and matching registered CID', () => {
  const body = fixtureBody(path, prefix + '_fragment');
  const normative = json('spec/contracts/actql-aoa.json').execution_contracts['ACTQL.expression_fragment/0.1'];
  const expressions = json('spec/contracts/actql-expressions.json');
  assert.deepEqual(body, normative);
  assert.equal(body.dependencies.expression_contract.cid, cid(expressions));
  assert.equal(body.dependencies.fragment_schema.cid, cid(expressions.schemas.fragment));
  const registry = fixtureBody(path, prefix + '_registry');
  assert.equal(registry['ACTQL.expression_fragment/0.1'].execution_contract.cid, cid(body));
});
