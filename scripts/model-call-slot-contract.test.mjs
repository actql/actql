import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {join} from 'node:path';
import test from 'node:test';
import {canonicalText, verifyIdentity} from './check-canonical-json.mjs';
import {machineCid} from './actql-spec-family.mjs';
import {checkModelIdentitySchemas, modelIdentitySchemas,
  modelIdentityFields} from './model-call-slot-contract.mjs';

const hash = digit => `sha256:${digit.repeat(64)}`;
// Independent symbolic dependencies isolate these preimages. No compiler,
// provider, CompletedOutput or product identity emitter supplies expectations.
const effective = {version: 'actql-model-effective-inputs/0.1',
  parameter_values_cid: hash('1'), invocation_bindings_cid: hash('2'),
  input_artifacts: {}};
const artifact = {version: 'actql-model-input-artifact/0.1',
  program_definition_cid: hash('3'), unit_definition_cid: hash('4'),
  source_ordinal: 2, effective_inputs_cid: machineCid(effective),
  input_fragment_cid: hash('5'), logical_relation_cid: hash('6'),
  relation_schema_cid: hash('7'), ordered_rows_cid: hash('8'),
  completeness: 'complete'};
const key = {version: 'actql-model-input-key/0.1', components: [
  {field: 'id', value_contract_cid: hash('9'), value_cid: machineCid('a')},
]};
const slot = {version: 'actql-model-call-slot/0.1',
  program_definition_cid: artifact.program_definition_cid,
  unit_definition_cid: artifact.unit_definition_cid, source_ordinal: 2,
  effective_inputs_cid: machineCid(effective),
  input_artifact_cid: machineCid(artifact), input_key_cid: machineCid(key),
  model_task_cid: hash('a'), fixed_request_cid: hash('b')};
const bodies = [
  ['empty effective inputs', 'model_effective_inputs', effective],
  ['named upstream inputs', 'model_effective_inputs', {...effective,
    input_artifacts: {left: hash('c'), right: hash('d')}}],
  ['completed prefix artifact', 'model_input_artifact', artifact],
  ['typed string key', 'model_input_key', key],
  ['ordered compound key', 'model_input_key', {...key, components: [
    ...key.components,
    {field: 'partition', value_contract_cid: hash('e'), value_cid: machineCid(1)},
  ]}],
  ['call slot', 'model_call_slot', slot],
  ...Object.entries(slot).filter(([name]) => name !== 'version').map(
    ([name, value]) => [`changed ${name}`, 'model_call_slot',
      {...slot, [name]: name === 'source_ordinal' ? value + 1 : hash('f')}]),
];
const vectors = {version: 'actql-model-call-slot-vectors/0.1',
  cases: bodies.map(([id, kind, body]) => ({id, kind, body,
    expected_canonical_bytes: canonicalText(body), expected_cid: machineCid(body)}))};
const path = 'portability/corpus/model-call-slot.json';
if (process.argv.includes('--write')) {
  writeFileSync(path, JSON.stringify(vectors, null, 2) + '\n');
}
const moonPath = 'src/run_publication/model_call_slot.generated_test.mbt';
const moonSource = '// Generated independent model identity admission vectors.\n' +
  vectors.cases.map(fixture => `\n///|\ntest ${JSON.stringify('model identity: ' + fixture.id)} {\n` +
    `  let issued = seal_run_evidence_value(${JSON.stringify(fixture.kind)},\n` +
    `    ${JSON.stringify(fixture.expected_canonical_bytes)}, 10000, 1000, 20).unwrap()\n` +
    `  assert_eq(run_evidence_value_identity(issued), ${JSON.stringify(fixture.expected_cid)})\n` +
    `  let reconstructed = admit_run_evidence_value(${JSON.stringify(fixture.kind)},\n` +
    `    run_evidence_value_json(issued), 10000, 1000, 20).unwrap()\n` +
    `  assert_eq(run_evidence_value_identity(reconstructed), run_evidence_value_identity(issued))\n` +
    `}\n`).join('');
const moon = execFileSync(process.env.MOON_HOME
  ? join(process.env.MOON_HOME, 'bin/moonfmt') : 'moonfmt', ['-'],
{input: moonSource, encoding: 'utf8'});
if (process.argv.includes('--write')) writeFileSync(moonPath, moon);
assert.equal(readFileSync(moonPath, 'utf8'), moon);

test('model identity envelopes and artifact registry retain exact pins', () => {
  checkModelIdentitySchemas(JSON.parse(readFileSync(
    'spec/contracts/actql-protocol-schemas.json', 'utf8')));
});

test('independent preimages bind every call dependency and logical occurrence', () => {
  const fixed = JSON.parse(readFileSync(path, 'utf8'));
  assert.deepEqual(fixed, vectors);
  for (const fixture of fixed.cases) {
    verifyIdentity(fixture.body, fixture.expected_cid,
      fixture.expected_canonical_bytes);
  }
  const slots = fixed.cases.filter(c => c.kind === 'model_call_slot');
  assert.equal(new Set(slots.map(c => c.expected_cid)).size, slots.length);
  assert.equal(machineCid(JSON.parse(JSON.stringify(slot))), machineCid(slot));
  assert.notEqual(machineCid({...key, components: [...key.components,
    {field: 'other', value_contract_cid: hash('9'), value_cid: machineCid('a')}]}),
  machineCid(key));
  const compound = fixed.cases.find(c => c.id === 'ordered compound key').body;
  assert.notEqual(machineCid({...compound,
    components: compound.components.toReversed()}), machineCid(compound));
});

test('closed preimages exclude runtime positions, outcomes and self identities', () => {
  const schemas = modelIdentitySchemas();
  for (const [kind, schema] of Object.entries(schemas)) {
    assert.equal(schema.additionalProperties, false);
    for (const field of ['row_number', 'worker', 'attempt', 'retry_count',
      'response', 'stage_invocation_cid', 'observation_set_cid']) {
      assert.equal(Object.hasOwn(schema.properties, field), false);
    }
    for (const fixture of vectors.cases.filter(c => c.kind === kind)) {
      assert.deepEqual(Object.keys(fixture.body).sort(),
        schema.required.filter(k => k !== modelIdentityFields[kind]).sort());
    }
  }
  const {input_artifacts: ignored, ...missing} = effective;
  void ignored;
  assert.notEqual(machineCid(missing), machineCid(effective));
  assert.notEqual(machineCid({...effective, input_artifacts: null}),
    machineCid(effective));
});

// This oracle describes the registered-reference closure rule, not arbitrary
// recursive searches for CID-looking business strings or execution evidence.
test('interpreted dependencies cannot return indirectly to the call slot', () => {
  const closure = edges => {
    const active = new Set();
    const done = new Set();
    const visit = name => {
      assert.ok(!active.has(name), 'cyclic identity reference');
      if (done.has(name)) return;
      active.add(name);
      for (const dependency of edges[name] ?? []) visit(dependency);
      active.delete(name);
      done.add(name);
    };
    visit('slot');
    return done;
  };
  const edges = {slot: ['input', 'task', 'request'], input: ['prefix', 'upstream'],
    upstream: ['prior_capture'], task: ['prompt', 'schema']};
  assert.ok(closure(edges).has('prior_capture'));
  assert.throws(() => closure({...edges, schema: ['slot']}), /cyclic/);
  assert.throws(() => closure({...edges, upstream: ['invocation'],
    invocation: ['capture'], capture: ['slot']}), /cyclic/);
});
