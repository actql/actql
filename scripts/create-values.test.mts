import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {test} from 'node:test';
import {machineCid} from './actql-spec-family.mjs';
import {parameterPrograms, type ProgramRegistry} from './parameter-schema.mjs';
import {createValuesSchemas, createValuesSchema, withoutCreateValuesSchema,
  checkCreateValuesVectors} from './create-values.mjs';
type Program = Parameters<typeof withoutCreateValuesSchema>[0];
type Protocol = ProgramRegistry<Program>;
type Fixture = {stages: {effects: {save: {create: {payload: {Name: unknown; values: unknown}}}}}[]};
type Corpus = Parameters<typeof checkCreateValuesVectors>[0];
type Vectors = Omit<Corpus, 'programs'> & {previous_source: string; previous_program_grammar_cid: string;
  program_grammar_cid: string; create_body_cid: string; create_body: unknown;
  programs: (Corpus['programs'][number] & {program: Fixture; legacy?: boolean; header_issue?: string})[]};
type Create = {properties: {payload?: unknown; values?: {type: string | string[]; minProperties?: number;
  additionalProperties: {oneOf: {additionalProperties: boolean; properties: {field?: {minLength: number}}}[]}}};
  dependentRequired?: {values: string[]}; allOf: {oneOf: unknown[]}[]};

const read = <Value,>(path: string): Value => JSON.parse(readFileSync(path, 'utf8'));
const protocol = read<Protocol>('spec/contracts/actql-protocol-schemas.json');
const vectors = read<Vectors>('portability/corpus/create-values.json');
const create = (program: Program) => program.properties.effects.additionalProperties.oneOf
  .find(member => member.properties?.create)!.properties!.create! as Create;

test('both actual Program schemas add only the adopted closed values alternative and retain original create preimages', () => {
  createValuesSchemas(protocol);
  const original = (JSON.parse(execFileSync('git', ['show',
    vectors.previous_source + ':spec/contracts/actql-protocol-schemas.json'],
  {encoding: 'utf8', maxBuffer: 16 * 1024 * 1024})) as Protocol).artifact_schemas.executable_plan
    .properties.execution_material.properties.program;
  assert.equal(machineCid(original), vectors.previous_program_grammar_cid);
  assert.deepEqual(create(original), vectors.previous_create_body);
  // The complete historical Program pin retains its original type grammar.
  // Later independently adopted type constraints must not rewrite that vector.
  const historical = structuredClone(original);
  create(historical).properties.values = createValuesSchema();
  create(historical).dependentRequired = {values: ['from']};
  assert.equal(machineCid(historical), vectors.program_grammar_cid);
  assert.deepEqual(withoutCreateValuesSchema(historical), original);
  for (const program of parameterPrograms(protocol)) {
    assert.equal(machineCid(create(program)), vectors.create_body_cid);
    assert.deepEqual(create(program), vectors.create_body);
    assert.deepEqual(create(withoutCreateValuesSchema(program)), create(original),
      'Every legacy create field and alternative remains exact under the current type grammar');
    assert.deepEqual(create(program).properties.values, createValuesSchema());
    assert.equal(Object.hasOwn(create(program).properties.values!, 'minProperties'), false,
      'Mapping requirements own empty-map admission');
  }
});

test('normal schema gate refuses absent values, missing source relationship, weakened shape and changed old payload', () => {
  for (const mutate of [
    p => { delete create(p).properties.values; },
    p => { delete create(p).dependentRequired; },
    p => { create(p).dependentRequired!.values = []; },
    p => { create(p).properties.values!.type = ['object', 'null']; },
    p => { create(p).properties.values!.minProperties = 1; },
    p => { create(p).properties.values!.additionalProperties.oneOf[0].additionalProperties = true; },
    p => { create(p).properties.values!.additionalProperties.oneOf[1].properties.field!.minLength = 0; },
    p => { create(p).properties.payload = {}; },
    p => { create(p).allOf[1].oneOf = []; },
  ] satisfies ((p: Program) => void)[]) {
    const changed = structuredClone(protocol);
    mutate(parameterPrograms(changed)[0]);
    assert.throws(() => createValuesSchemas(changed));
  }
});

test('independent input-wire/header preimages and generated decisions preserve legacy raw business objects', () => {
  const text = checkCreateValuesVectors(vectors);
  assert.equal(readFileSync('src/stage_syntax/create_values.generated_test.mbt', 'utf8'), text);
  assert.equal(vectors.programs.length, 12);
  const legacy = vectors.programs.filter(value => value.legacy);
  assert.equal(legacy.length, 2);
  for (const value of legacy) assert.equal(Object.hasOwn(value.program.stages[0].effects.save.create, 'values'), false);
  const raw = legacy.find(value => value.name === 'legacy_raw_payload')!.program.stages[0].effects.save.create.payload;
  assert.deepEqual(raw.Name, {$param: 'business_data'});
  assert.deepEqual(raw.values, {field: 'opaque_business'});
  assert.notEqual(vectors.programs.find(value => value.name === 'legacy_from')!.input_wire_cid,
    vectors.programs.find(value => value.name === 'field_subset')!.input_wire_cid);
  assert.equal(vectors.programs.find(value => value.name === 'raw_payload_conflict')!.header_issue,
    'InvalidSourceResult');
});
