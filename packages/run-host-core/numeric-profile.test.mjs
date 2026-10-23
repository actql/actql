import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {canonicalText} from '../../scripts/check-canonical-json.mjs';
import {admitEnvironment, admitProfileSelection, prepare, compileValues,
  issueAllowedRun, issueSourceFreeRunDefinition, issueSourceFreeRunMaterials,
  privateRunDefinition, prepareEffect, compileEffect, issueAllowedEffectRun,
  issueEffectRunDefinition, issueEffectRunMaterials, admitEffectRunMaterials,
  privateEffectCompilationWires} from './index.mjs';
import {createWorkersFiniteRuntime} from './dist/workers_finite.js';

const read = path => readFileSync(new URL(`../../${path}`, import.meta.url), 'utf8');
const environmentWire = read('packages/sdk/fixtures/values.environment.json').trimEnd();
const environmentCid = JSON.parse(environmentWire).evidence_bundle_cid;
// Independent installed profile identity, not a value observed from execution.
const numericProfileCid = 'sha256:d771391b2e4f3e52a3cf48810571a09c6c272df64fbb77c245dfabcf456be5df';
const selectedProfiles = {rela: true, numericProfileCid};
const document = (operation = 'sum') => JSON.stringify({version: 'actql/0.1',
  id: 'numeric-profile', stages: [{id: 'main', inputs: {}, steps: [
    {as: 'input', values: {schema: {x: {type: 'number', nullable: false}}, rows: [{x: 1}, {x: 2}]}},
    {as: 'grouped', from: 'input', group: {by: [], aggregates: {
      total: operation === 'count' ? {fn: 'count'} : {fn: operation, field: 'x'},
    }}},
  ], results: {rows: {from: 'grouped', fields: ['total']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}});

function configuration(profile) {
  const aoa = JSON.parse(read('spec/contracts/actql-aoa.json'));
  const valueLimits = {max_nodes: 10000, max_text_bytes: 100000, max_depth: 100, max_work: 100000};
  return {
    environment: {wire: environmentWire, cid: environmentCid,
      ...(profile === undefined ? {} : {numeric_profile_cid: profile}),
      expressions: {text_time: false, veca: false},
      operations: {rela: true, sga: false, tea: false, calendar: false, text_rank: false}},
    contracts: {registry: canonicalText(JSON.parse(read(aoa.pipeline_registry_file))),
      values: canonicalText(aoa.execution_contracts['REL.values']),
      grammar: canonicalText(JSON.parse(read('spec/manifests/actql-grammar-0.1.json'))),
      barriers: canonicalText(JSON.parse(read('spec/manifests/actql-barrier-contracts-0.1.json')))},
    sequence: {max_steps: 10, max_rows: 100, max_cells: 100,
      max_bindings: 10, max_name_bytes: 1000,
      expressions: {max_nodes: 100, max_work: 1000, max_depth: 10,
        max_literal_nodes: 100, max_literal_text_bytes: 1000}},
    execution: {rows: {max_rows: 100, metadata_entries: 1000, retained_entries: 1000,
      operation_entries: 1000, input_values: valueLimits, output_values: valueLimits},
      max_work: 100000, max_frames: 1000},
    measurement: {max_work: 100000, max_bytes: 100000, max_nodes: 10000, max_depth: 100},
    capacity: {contract_cid: 'sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f',
      max_rows: 100, max_value_bytes: 10000},
    search: {max_offers: 10, max_strategies: 10, max_work: 10000, max_revisions: 3},
    ledger: {planning_work: 10000, attempts: 10, holdings: 10, transfer_bytes: 300000n,
      retained_bytes: 32000000n, execution_bytes: 134217728n},
    milliseconds: 1n, max_work: 10000, max_entries: 100,
  };
}

test('numeric profile selection is explicit, closed and detached', () => {
  assert.equal(Object.hasOwn(admitProfileSelection({rela: true}), 'numericProfileCid'), false);
  const input = {...selectedProfiles}, selected = admitProfileSelection(input);
  input.numericProfileCid = 'sha256:' + 'a'.repeat(64);
  assert.equal(selected.numericProfileCid, numericProfileCid);
  assert.ok(Object.isFrozen(selected));
  assert.deepEqual(admitProfileSelection(selected), selected);
  let reads = 0;
  const accessor = {get numericProfileCid() { reads++; return reads === 1 ? numericProfileCid : 'changed'; }};
  assert.equal(admitProfileSelection(accessor).numericProfileCid, numericProfileCid);
  assert.equal(reads, 1, 'the admitted profile snapshots one original observation');
  assert.equal(Object.hasOwn(admitProfileSelection(Object.create({numericProfileCid})), 'numericProfileCid'), false);
  for (const profile of [undefined, null, true, '', 'sha256:123', 'sha256:' + 'A'.repeat(64)]) {
    assert.throws(() => admitProfileSelection({numericProfileCid: profile}), /InvalidRunHostProfileSelection/);
    assert.throws(() => admitEnvironment(environmentWire, environmentCid,
      {rela: true, numericProfileCid: profile}), /InvalidRunHostEnvironment/);
  }
});

test('SUM prepares and compiles only with the existing admitted numeric profile; COUNT needs none', () => {
  const plain = admitEnvironment(environmentWire, environmentCid, {rela: true});
  assert.throws(() => prepare(document(), 'json', plain), {code: 'RunHostPreparationRejected'});
  assert.ok(compileValues(prepare(document('count'), 'json', plain)));
  const selected = admitEnvironment(environmentWire, environmentCid, selectedProfiles);
  assert.ok(compileValues(prepare(document(), 'json', selected)));
  assert.throws(() => admitEnvironment(environmentWire, environmentCid,
    {rela: true, numericProfileCid: 'sha256:' + 'a'.repeat(64)}), {code: 'RunHostEnvironmentRejected'});
});

test('separate production Worker unit restores the original numeric Run only with its installed profile', () => {
  const environment = admitEnvironment(environmentWire, environmentCid, selectedProfiles);
  const text = document(), prepared = prepare(text, 'json', environment), compilation = compileValues(prepared);
  const allowed = issueAllowedRun(prepared, compilation, {executionContextCid: 'sha256:' + 'a'.repeat(64),
    hostPolicyCid: 'sha256:' + 'b'.repeat(64), expiresAt: '2099-01-01T00:00:00.000Z'});
  const definition = issueSourceFreeRunDefinition(prepared, compilation, allowed.admission,
    'numeric-original-scope', 'numeric-original-run', '2026-10-23T00:00:00.000Z', '2098-01-01T00:00:00.000Z');
  const wire = issueSourceFreeRunMaterials(prepared, compilation, allowed.admission,
    definition, {format: 'json', document: text, environment, environmentWire});
  const before = privateRunDefinition(definition);
  const configured = configuration(numericProfileCid);
  const host = createWorkersFiniteRuntime(19, configured).host;
  configured.environment.numeric_profile_cid = 'sha256:' + 'a'.repeat(64);
  assert.ok(host.prepare(text));
  const restored = host.admitMaterials(wire, before.cid);
  assert.ok(restored.preparation && restored.admission && restored.definition);
  assert.notEqual(restored.preparation.program, prepared, 'only serialized bytes cross link units');
  assert.throws(() => host.admitMaterials(wire, 'sha256:' + 'c'.repeat(64)), /MoonBitHostFailure/);
  const unavailable = createWorkersFiniteRuntime(20, configuration()).host;
  assert.ok(unavailable.prepare(document('count')));
  assert.throws(() => unavailable.prepare(text), /MoonBitHostFailure/);
  assert.throws(() => unavailable.admitMaterials(wire, before.cid), /MoonBitHostFailure/);
  assert.throws(() => createWorkersFiniteRuntime(21, configuration('sha256:' + 'a'.repeat(64))), /MoonBitHostFailure/);
  for (const malformed of [undefined, null, true, 'sha256:123', 'sha256:' + 'A'.repeat(64)]) {
    const invalid = configuration();
    invalid.environment.numeric_profile_cid = malformed;
    assert.throws(() => createWorkersFiniteRuntime(22, invalid), /InvalidWorkersFiniteInstallation/);
  }
  assert.deepEqual(privateRunDefinition(definition), before, 'restoration never changes the original Run');
});

test('Effect materials retain the same explicit numeric selection without issuing new authority', () => {
  const program = JSON.parse(read('packages/run-host-core/fixtures/source-compute-effect.program.json'));
  program.stages[1].steps.splice(1, 0, {as: 'summed', group: {by: ['id'],
    aggregates: {total: {fn: 'sum', field: 'id'}}}});
  const text = JSON.stringify(program);
  const wireEnvironment = read('packages/run-host-core/fixtures/source-compute-effect.environment.json').trimEnd();
  const cid = JSON.parse(wireEnvironment).evidence_bundle_cid;
  const plain = admitEnvironment(wireEnvironment, cid, {rela: true});
  assert.throws(() => prepareEffect(text, 'json', plain), {code: 'RunHostEffectPreparationRejected'});
  const environment = admitEnvironment(wireEnvironment, cid, selectedProfiles);
  const prepared = prepareEffect(text, 'json', environment), compilation = compileEffect(prepared);
  const allowed = issueAllowedEffectRun(prepared, compilation, {
    executionContextCid: 'sha256:' + 'a'.repeat(64), hostPolicyCid: 'sha256:' + 'b'.repeat(64),
    expiresAt: '2099-01-01T00:00:00.000Z'});
  const definition = issueEffectRunDefinition(allowed, 'numeric-effect-scope', 'original-effect-run',
    '2026-10-23T00:00:00.000Z', '2098-01-01T00:00:00.000Z');
  const retained = {format: 'json', document: text, environment, environmentWire: wireEnvironment};
  const materials = issueEffectRunMaterials(allowed, definition, retained);
  const original = privateRunDefinition(definition);
  const restored = admitEffectRunMaterials(materials, original.cid, admitProfileSelection(selectedProfiles));
  assert.deepEqual(privateRunDefinition(restored.definition), original);
  assert.deepEqual(privateEffectCompilationWires(restored.compilation), privateEffectCompilationWires(compilation));
  assert.equal(issueEffectRunMaterials(restored.allowed, restored.definition, retained), materials);
  for (const profiles of [{rela: true}, {rela: true, numericProfileCid: 'sha256:' + 'a'.repeat(64)}]) {
    assert.throws(() => admitEffectRunMaterials(materials, original.cid, profiles), {code: 'RunHostEffectRestorationRejected'});
  }
});
