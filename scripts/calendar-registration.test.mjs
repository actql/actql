import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {checkRegistration, operations} from './calendar-registration.mjs';

const read = path => JSON.parse(readFileSync(path, 'utf8'));
const aoa = read('spec/contracts/actql-aoa.json');
const registry = read(aoa.pipeline_registry_file);
const original = read('portability/fixtures/pipeline-registry-pre-calendar.json');
const history = read('scripts/fixtures/calendar-registration-history.json');
// Independent ASCII-key machine preimage oracle, never product lowering output.
const canonical = value => Array.isArray(value) ? `[${value.map(canonical).join(',')}]`
  : value !== null && typeof value === 'object'
    ? `{${Object.keys(value).sort().map(key => `${JSON.stringify(key)}:${canonical(value[key])}`).join(',')}}`
    : JSON.stringify(value);
const cid = value => 'sha256:' + createHash('sha256').update(canonical(value)).digest('hex');

test('Calendar extends the exact original registry without rewriting its identity', () => {
  assert.equal(cid(original), 'sha256:79aa0a847874d3f277b0fab929ed8d6bd4173ad0f032d60413e3c279487f50b4');
  const registered = history.first_registered.registry;
  assert.equal(cid(registered), history.first_registered.registry_cid);
  assert.equal(cid(registered), 'sha256:ee56c009fc4983ae885fb6f7ed414f12de46b6b68de38ebe52d95d33dd931cb7');
  const retained = {...registered};
  for (const operation of operations) delete retained[operation];
  assert.deepEqual(retained, original);
  assert.notEqual(cid(registry), cid(original));
  assert.equal(aoa.pipeline_registry_cid, cid(registry));
  for (const operation of operations) assert(!Object.hasOwn(original, operation));
});

test('Calendar opcodes and arities match the existing normative mapping', () => {
  assert.deepEqual(operations, ['TEA.calendar.bucket', 'TEA.calendar.series']);
  const language = readFileSync('docs/spec/language.md', 'utf8');
  assert(language.includes('`TEA.calendar.bucket` / `TEA.calendar.series`'));
  checkRegistration(aoa, registry);
  assert.equal(cid(registry), 'sha256:204fd80c64c2bff246015f06ae50d0044aa566f197922f14cd15ecf0b3285fdb');
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


test('current Calendar registration preserves complete old bodies and changes only declared identities', () => {
  const prior = history.prior_current;
  assert.equal(cid(prior.aoa), prior.aoa_cid);
  assert.equal(prior.aoa_cid, 'sha256:8c46b1546e27c1d7c5a62825a49d2acb0600c9cc53ecfda1f45d9d39cf267568');
  assert.equal(cid(prior.registry), prior.registry_cid);
  assert.equal(prior.registry_cid, 'sha256:09353058f3feff94698f4707cc17c0eb6e142198d058c09b278b92b3f942271e');
  assert.equal(cid(prior.series), prior.series_cid);
  assert.equal(prior.series_cid, 'sha256:040129c2ff63394a6b4804daf3a7c0641e2bdae4b524389d3c8c362e7e4dc13f');
  const currentSeries = aoa.execution_contracts[operations[1]];
  const restoredSeries = structuredClone(currentSeries);
  for (const endpoint of ['start', 'end'])
    restoredSeries.params_schema.properties[endpoint] = prior.series.params_schema.properties[endpoint];
  assert.deepEqual(restoredSeries, prior.series);
  const restoredRegistry = structuredClone(registry);
  restoredRegistry[operations[1]].execution_contract.cid = prior.series_cid;
  assert.deepEqual(restoredRegistry, prior.registry);
  const restoredOwner = structuredClone(aoa);
  restoredOwner.execution_contracts[operations[1]] = prior.series;
  restoredOwner.target_registry_requirements[operations[1]].execution_contract.cid = prior.series_cid;
  restoredOwner.pipeline_registry_cid = prior.registry_cid;
  assert.deepEqual(restoredOwner, prior.aoa);
  assert.notEqual(cid(aoa), prior.aoa_cid);
  assert.throws(() => checkRegistration(prior.aoa, registry));
});

test('compiled Calendar endpoint grammar retains canonical exact fractions and rejects alternate spellings', () => {
  // Spelling only; actual date validity and selected TZDB execution remain separate.
  for (const field of ['start', 'end']) {
    const pattern = new RegExp(aoa.execution_contracts[operations[1]].params_schema.properties[field].pattern);
    for (const fraction of ['000', '123', '0001', '1234', '123456789', '000000001'])
      assert(pattern.test('2024-01-01T00:00:00.' + fraction + 'Z'), fraction);
    for (const value of [
      '2024-01-01T00:00:00.00Z', '2024-01-01T00:00:00.0000Z',
      '2024-01-01T00:00:00.123400Z', '2024-01-01T00:00:00.1234567890Z',
      '0000-01-01T00:00:00.000Z', '2024-01-01T00:00:00.123+00:00',
      '2024-01-01T00:00:00.123Z\n',
    ]) assert(!pattern.test(value), value);
  }
});
