import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {checkRegistration, operations} from './calendar-registration.mjs';

const read = path => JSON.parse(readFileSync(path, 'utf8'));
const aoa = read('spec/contracts/actql-aoa.json');
const registry = read(aoa.pipeline_registry_file);
const original = read('portability/fixtures/pipeline-registry-pre-calendar.json');
const predecessor = read('scripts/fixtures/calendar-exact-utc/predecessor.json');
const currentPredecessor = read('scripts/fixtures/calendar-exact-utc/ac53-predecessor.json');
// Independent ASCII-key machine preimage oracle, never product lowering output.
const canonical = value => Array.isArray(value) ? `[${value.map(canonical).join(',')}]`
  : value !== null && typeof value === 'object'
    ? `{${Object.keys(value).sort().map(key => `${JSON.stringify(key)}:${canonical(value[key])}`).join(',')}}`
    : JSON.stringify(value);
const cid = value => 'sha256:' + createHash('sha256').update(canonical(value)).digest('hex');

test('Calendar extends the exact original registry without rewriting its identity', () => {
  assert.equal(cid(original), 'sha256:79aa0a847874d3f277b0fab929ed8d6bd4173ad0f032d60413e3c279487f50b4');
  // Reconstruct the original Calendar introduction, not the later live registry.
  const introduced = {...original};
  for (const operation of operations) introduced[operation] = predecessor.registry[operation];
  assert.equal(cid(introduced), 'sha256:ee56c009fc4983ae885fb6f7ed414f12de46b6b68de38ebe52d95d33dd931cb7');
  assert.notEqual(cid(registry), cid(original));
  assert.equal(aoa.pipeline_registry_cid, cid(registry));
  for (const operation of operations) assert(!Object.hasOwn(original, operation));
});

test('Calendar opcodes and arities match the existing normative mapping', () => {
  assert.deepEqual(operations, ['TEA.calendar.bucket', 'TEA.calendar.series']);
  const language = readFileSync('docs/spec/language.md', 'utf8');
  assert(language.includes('`TEA.calendar.bucket` / `TEA.calendar.series`'));
  checkRegistration(aoa, registry);
  assert.equal(cid(registry), 'sha256:f6f017a119e5a24f0c36a64cd7f2b4fd67ea533679945098375d854af644f642');
  assert.equal(cid(aoa.execution_contracts[operations[0]]), 'sha256:8cbb70e4edcd1dd29deee777b44b3f09b9cee337b5495944ca895fa3065b6227');
  assert.equal(cid(aoa.execution_contracts[operations[1]]), 'sha256:8070a5fa9b6177df0d407b474a2b34aff2ecde9cf9c5b726191f7bd908a4dc83');
  assert.deepEqual(registry[operations[0]].inputs, ['relation']);
  assert.deepEqual(registry[operations[1]].inputs, []);
  for (const operation of operations) assert.equal(registry[operation].output, 'relation');
  assert(!registry['TEA.calendar_bucket']);
  assert(!registry['TEA.calendar_series']);
});

test('Compiled Calendar parameters retain closed original profile and literal week rules', () => {
  for (const operation of operations) {
    const schema = aoa.execution_contracts[operation].params_schema;
    assert.equal(schema.additionalProperties, false);
    assert(schema.required.includes('profile'));
    assert.deepEqual(schema.properties.unit.enum, ['day', 'week', 'month', 'quarter', 'year']);
    assert.deepEqual(schema.properties.week_start.enum, ['monday', 'sunday']);
    assert.deepEqual(schema.allOf, [{
      if: {properties: {unit: {const: 'week'}}, required: ['unit']},
      then: {required: ['week_start']}, else: {not: {required: ['week_start']}},
    }]);
    const profile = schema.properties.profile;
    assert.equal(profile.additionalProperties, false);
    assert.deepEqual(profile.required, ['conversion_law', 'table_bytes_cid', 'tzdb_version']);
    assert.equal(profile.properties.conversion_law.const, 'actql-calendar-boundaries/0.1');
    assert.deepEqual(Object.keys(profile.properties).sort(), ['conversion_law', 'table_bytes_cid', 'tzdb_version']);
    assert(new RegExp(profile.properties.table_bytes_cid.pattern).test('sha256:' + 'a'.repeat(64)));
    assert(!new RegExp(profile.properties.table_bytes_cid.pattern).test('sha256:' + 'a'.repeat(63)));
  }
  const series = aoa.execution_contracts[operations[1]].params_schema;
  assert.deepEqual(series.required, ['start', 'end', 'unit', 'timezone', 'profile']);
  for (const key of ['start', 'end']) {
    assert.equal(series.properties[key].oneOf, undefined);
    const pattern = new RegExp(series.properties[key].pattern);
    assert(pattern.test('0001-01-01T00:00:00.000Z'));
    assert(!pattern.test('0000-01-01T00:00:00.000Z'));
    assert(!pattern.test('2000-01-01T00:00:00Z'));
  }
  const bucket = aoa.execution_contracts[operations[0]].params_schema;
  assert.deepEqual(bucket.required, ['time', 'into', 'unit', 'timezone', 'profile']);
});

test('Changed arity or profile contract cannot be admitted by rehashing its registration', () => {
  for (const operation of operations) {
    const changed = structuredClone(registry);
    changed[operation].inputs = ['relation', 'relation'];
    assert.throws(() => checkRegistration(aoa, changed));
    const altered = structuredClone(aoa);
    altered.execution_contracts[operation].params_schema.properties.profile.additionalProperties = true;
    altered.target_registry_requirements[operation].execution_contract.cid = cid(altered.execution_contracts[operation]);
    assert.throws(() => checkRegistration(altered, registry));
  }
});

test('Registration does not advertise Calendar as an installed execution capability', () => {
  for (const operation of operations) {
    assert(!aoa.local_family_execution_profile.registry_operations.includes(operation));
    assert.match(aoa.execution_contracts[operation].semantics.authority, /not_executable_Plan/);
    assert.match(aoa.execution_contracts[operation].semantics.runtime, /no_ambient_timezone_or_fixed_milliseconds/);
  }
});


test('exact UTC changes only the original Calendar endpoint grammar and its registry pin', () => {
  assert.equal(cid(predecessor), 'sha256:8c23f6663bc995467d14f7d83ed21c0ddef267e637f34a7b363d868d388481d5');
  assert.equal(cid(predecessor.registry), 'sha256:33e430c0df46632f1d45949397dfccef2502542f2b762bdbef75eb3dc472ee35');
  assert.equal(cid(predecessor.series_contract), 'sha256:040129c2ff63394a6b4804daf3a7c0641e2bdae4b524389d3c8c362e7e4dc13f');
  assert.equal(cid(currentPredecessor), 'sha256:4314c1b6f5225bb7353dfd1f2b33f5c7d3fc81481f92705e398185faf3236233');
  assert.equal(cid(currentPredecessor.registry), 'sha256:0ff18ae5087aa79d90acdf8fe25ce7534dec0b0687c2f350894ce0c960f9f505');
  assert.deepEqual(currentPredecessor.series_contract, predecessor.series_contract);
  const expected = structuredClone(currentPredecessor.series_contract);
  // Independently apply the adopted scalar law, without calling eventSchemas.
  for (const endpoint of ['start', 'end']) {
    expected.params_schema.properties[endpoint].pattern =
      expected.params_schema.properties[endpoint].pattern.replace('[0-9]{3}Z', '(?:[0-9]{3}|[0-9]{3,8}[1-9])Z');
    const pattern = new RegExp(expected.params_schema.properties[endpoint].pattern);
    for (const fraction of ['000', '123', '0001', '123456789']) assert(pattern.test(`2000-01-01T00:00:00.${fraction}Z`));
    for (const fraction of ['00', '0000', '1230', '1234567891']) assert(!pattern.test(`2000-01-01T00:00:00.${fraction}Z`));
  }
  assert.deepEqual(aoa.execution_contracts['TEA.calendar.series'], expected);
  const expectedRegistry = structuredClone(currentPredecessor.registry);
  expectedRegistry['TEA.calendar.series'].execution_contract.cid = cid(expected);
  assert.deepEqual(registry, expectedRegistry);
});
