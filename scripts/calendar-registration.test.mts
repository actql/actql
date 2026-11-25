import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {checkRegistration, operations} from './calendar-registration.mjs';

type Operation = (typeof operations)[number];
type Reference = {cid: string};
type RegistryEntry = {inputs: string[]; output: string; execution_contract: Reference};
type Registry = Record<string, unknown> & Record<Operation, RegistryEntry> & {
  'ACTQL.expression_fragment/0.1': RegistryEntry;
  'REL.derive': {execution_extensions: {ordered_bindings: Reference}};
  'REL.values': RegistryEntry;
  'BRIDGE.rows.to_graph': RegistryEntry;
};
type Endpoint = {oneOf?: unknown; pattern?: string};
type CalendarContract = {params_schema: {additionalProperties: boolean; required: string[]; allOf: unknown;
  properties: {
    unit: {enum: string[]}; week_start: {enum: string[]}; start: Endpoint; end: Endpoint;
    profile: {additionalProperties: boolean; required: string[];
      properties: {conversion_law: {const: string}; table_bytes_cid: {pattern: string}}};
  }};
  semantics: {authority: string; runtime: string}};
type ValueSchema = {$defs: {value_contract: {oneOf: {properties?: {type?: {const: string}}}[]}}};
type WithDependencies = {dependencies: Record<string, Reference>};
type AoA = Parameters<typeof checkRegistration>[0] & {
  execution_contracts: Record<Operation, CalendarContract> & {
    'ACTQL.expression_fragment/0.1': WithDependencies;
    'REL.derive.ordered': WithDependencies & {schemas: {context: ValueSchema; shape: ValueSchema};
      semantics: {value_weight: string}};
    'REL.values': WithDependencies & {params_schema: ValueSchema; semantics: {byte_values?: string}};
    'BRIDGE.rows.to_graph': WithDependencies & {params_schema: ValueSchema};
  };
  target_registry_requirements: Registry;
  local_family_execution_profile: {registry_operations: string[]};
  expression_contract_cid: string;
};
type History = {
  first_registered: {registry: Record<string, unknown>; registry_cid: string};
  prior_current: {aoa: AoA; aoa_cid: string; registry: Registry; registry_cid: string;
    series: CalendarContract; series_cid: string};
};

const read = <Value,>(path: string): Value => JSON.parse(readFileSync(path, 'utf8'));
const aoa = read<AoA>('spec/contracts/actql-aoa.json');
const registry = read<Registry>(aoa.pipeline_registry_file);
const original = read<object>('portability/fixtures/pipeline-registry-pre-calendar.json');
const history = read<History>('scripts/fixtures/calendar-registration-history.json');
// Independent ASCII-key machine preimage oracle, never product lowering output.
const canonical = (value: unknown): string => Array.isArray(value) ? `[${value.map(canonical).join(',')}]`
  : value !== null && typeof value === 'object'
    ? `{${Object.keys(value).sort().map(key => `${JSON.stringify(key)}:${canonical((value as Record<string, unknown>)[key])}`).join(',')}}`
    : JSON.stringify(value)!;
const cid = (value: unknown) => 'sha256:' + createHash('sha256').update(canonical(value)).digest('hex');

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
  assert.equal(cid(registry), 'sha256:52e62094b1162213605e27199aa9a0e4832ee7771bcc1be66124f2fefb0a01e7');
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
  for (const key of ['start', 'end'] as const) {
    assert.equal(series.properties[key].oneOf, undefined);
    const pattern = new RegExp(series.properties[key].pattern!);
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
  for (const endpoint of ['start', 'end'] as const)
    restoredSeries.params_schema.properties[endpoint] = prior.series.params_schema.properties[endpoint];
  assert.deepEqual(restoredSeries, prior.series);
  const restoredOwner = structuredClone(aoa);
  // Later expression-language changes rebind these exact dependency roles;
  // they do not replace this published Calendar transition or its preimages.
  restoredOwner.expression_contract_cid = prior.aoa.expression_contract_cid;
  for (const [name, roles] of [
    ['ACTQL.expression_fragment/0.1', ['expression_contract', 'fragment_schema']],
    ['REL.derive.ordered', ['expression_contract', 'expression_node', 'source_expression', 'value_contract']],
    ['REL.values', ['canonical_value_contract']],
    ['BRIDGE.rows.to_graph', ['canonical_value_contract']],
  ] as const) for (const role of roles) {
    const retained = prior.aoa.execution_contracts[name].dependencies[role];
    const current = restoredOwner.execution_contracts[name].dependencies[role];
    assert.deepEqual({...current, cid: retained.cid}, retained);
    current.cid = retained.cid;
  }
  // BYTES adds one closed arm and deterministic wire weight. Reverse the
  // current addition before comparing the whole published Calendar owner.
  const removeByteArm = (schema: ValueSchema) => {
    const alternatives = schema.$defs.value_contract.oneOf;
    const index = alternatives.findIndex(arm => arm.properties?.type?.const === 'bytes');
    assert.notEqual(index, -1);
    const [bytes] = alternatives.splice(index, 1);
    assert.deepEqual(bytes, {
      type: 'object', required: ['type', 'nullable'], additionalProperties: false,
      properties: {type: {const: 'bytes'}, nullable: {type: 'boolean'}},
    });
  };
  const ordered = restoredOwner.execution_contracts['REL.derive.ordered'];
  removeByteArm(ordered.schemas.context);
  removeByteArm(ordered.schemas.shape);
  const bytesWeight = '_and_canonical_base64_octets_of_bytes_values';
  assert.equal(ordered.semantics.value_weight.split(bytesWeight).length, 2);
  ordered.semantics.value_weight = ordered.semantics.value_weight.replace(bytesWeight, '');
  const values = restoredOwner.execution_contracts['REL.values'];
  removeByteArm(values.params_schema);
  assert.equal(values.semantics.byte_values, '^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/][AQgw]==|[A-Za-z0-9+/]{2}[AEIMQUYcgkosw048]=)?(?![\\s\\S])');
  delete values.semantics.byte_values;
  removeByteArm(restoredOwner.execution_contracts['BRIDGE.rows.to_graph'].params_schema);
  const fragmentCid = cid(restoredOwner.execution_contracts['ACTQL.expression_fragment/0.1']);
  const orderedCid = cid(restoredOwner.execution_contracts['REL.derive.ordered']);
  const restoredRegistry = structuredClone(registry);
  restoredRegistry['ACTQL.expression_fragment/0.1'].execution_contract.cid = fragmentCid;
  restoredRegistry['REL.derive'].execution_extensions.ordered_bindings.cid = orderedCid;
  restoredRegistry[operations[1]].execution_contract.cid = prior.series_cid;
  for (const name of ['REL.values', 'BRIDGE.rows.to_graph'] as const) {
    const retainedCid = cid(restoredOwner.execution_contracts[name]);
    restoredRegistry[name].execution_contract.cid = retainedCid;
    restoredOwner.target_registry_requirements[name].execution_contract.cid = retainedCid;
  }
  assert.deepEqual(restoredRegistry, prior.registry);
  restoredOwner.target_registry_requirements['ACTQL.expression_fragment/0.1'].execution_contract.cid = fragmentCid;
  restoredOwner.target_registry_requirements['REL.derive'].execution_extensions.ordered_bindings.cid = orderedCid;
  restoredOwner.execution_contracts[operations[1]] = prior.series;
  restoredOwner.target_registry_requirements[operations[1]].execution_contract.cid = prior.series_cid;
  restoredOwner.pipeline_registry_cid = prior.registry_cid;
  assert.deepEqual(restoredOwner, prior.aoa);
  assert.notEqual(cid(aoa), prior.aoa_cid);
  assert.throws(() => checkRegistration(prior.aoa, registry));
});

test('compiled Calendar endpoint grammar retains canonical exact fractions and rejects alternate spellings', () => {
  // Spelling only; actual date validity and selected TZDB execution remain separate.
  for (const field of ['start', 'end'] as const) {
    const pattern = new RegExp(aoa.execution_contracts[operations[1]].params_schema.properties[field].pattern!);
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
