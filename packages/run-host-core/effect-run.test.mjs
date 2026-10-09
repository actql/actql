import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {buildSync} from 'esbuild';
import {admitEnvironment, prepare, compileValues, prepareEffect, compileEffect,
  prepareRequest, requestFields,
  effectExecutionShape, privateEffectCompilationWires, issueAllowedEffectRun,
  privateEffectRunEvidence, issueEffectRunDefinition, privateRunDefinition,
  issueEffectRunMaterials, admitEffectRunMaterials, effectRunStartCurrent} from '@actql/run-host-core';

// Original authoring fixture used by the resident Source/Effect boundary.
// This suite admits and restores real Owners; it does not run physical I/O.
const read = name => readFileSync(new URL('./fixtures/' + name, import.meta.url), 'utf8').trimEnd();
const document = read('source-compute-effect.program.json');
const environmentWire = read('source-compute-effect.environment.json');
const profiles = {rela: true};
const environment = admitEnvironment(environmentWire,
  JSON.parse(environmentWire).evidence_bundle_cid, profiles);
const fixed = character => 'sha256:' + character.repeat(64);
const originalPolicy = {executionContextCid: fixed('a'), hostPolicyCid: fixed('b'),
  expiresAt: '2099-01-01T00:00:00.000Z'};

function issued() {
  const prepared = prepareEffect(document, 'json', environment);
  const compilation = compileEffect(prepared);
  const allowed = issueAllowedEffectRun(prepared, compilation, originalPolicy);
  const definition = issueEffectRunDefinition(allowed, 'resident-effect', 'original-run',
    '2026-10-09T00:00:00.000Z', '2098-01-01T00:00:00.000Z');
  const retained = {document, format: 'json', environment, environmentWire};
  const wire = issueEffectRunMaterials(allowed, definition, retained);
  return {prepared, compilation, allowed, definition, retained, wire};
}

test('formal Effect preparation retains the two-task owner and pure refusal', () => {
  const prepared = prepareEffect(document, 'json', environment);
  const compilation = compileEffect(prepared);
  assert.deepEqual(effectExecutionShape(prepared, compilation),
    {taskCount: 2, acquisitionCount: 1, effectCount: 1});
  assert.throws(() => prepare(document, 'json', environment),
    {code: 'RunHostPreparationRejected'});
  assert.throws(() => compileValues(prepared), /ForeignRunHostHandle/u);
  assert.throws(() => compileEffect({...prepared}), /ForeignRunHostHandle/u);
  const second = prepareEffect(document, 'json', environment);
  assert.throws(() => effectExecutionShape(second, compilation), /ForeignRunHostCompilation/u);
  assert.throws(() => issueAllowedEffectRun(second, compilation, originalPolicy), /ForeignRunHostCompilation/u);
});

test('saved Effect materials restore the original Run, evidence and expiry', () => {
  const original = issued();
  const definition = privateRunDefinition(original.definition);
  const savedEvidence = privateEffectRunEvidence(original.allowed);
  const body = JSON.parse(original.wire);
  assert.equal(body.program, document);
  assert.equal(body.check_environment, environmentWire);
  assert.equal(body.prepared_invocation, savedEvidence.preparedInvocationWire);
  assert.equal(body.run_authorization, savedEvidence.authorizationWire);
  assert.equal(body.run_id, 'original-run');
  assert.equal(body.created_at, '2026-10-09T00:00:00.000Z');
  assert.equal(body.valid_until, '2098-01-01T00:00:00.000Z');
  const restored = admitEffectRunMaterials(original.wire, definition.cid, profiles);
  assert.deepEqual(privateRunDefinition(restored.definition), definition);
  assert.deepEqual(privateEffectRunEvidence(restored.allowed), savedEvidence);
  assert.deepEqual(privateEffectCompilationWires(restored.compilation),
    privateEffectCompilationWires(original.compilation));
  assert.deepEqual(effectExecutionShape(restored.prepared, restored.compilation),
    {taskCount: 2, acquisitionCount: 1, effectCount: 1});
  assert.equal(issueEffectRunMaterials(restored.allowed, restored.definition, original.retained), original.wire);
  assert.equal(effectRunStartCurrent(restored.allowed, restored.definition, '2026-10-09T00:01:00.000Z'), true);
  assert.equal(effectRunStartCurrent(restored.allowed, restored.definition, '2098-01-01T00:00:01.000Z'), false);
});

test('Effect materials reject foreign Run, changed original value and expiry', () => {
  const original = issued();
  const cid = privateRunDefinition(original.definition).cid;
  assert.throws(() => admitEffectRunMaterials(original.wire, fixed('c'), profiles),
    {code: 'RunHostEffectRestorationRejected'});
  const program = JSON.parse(document);
  program.stages[1].steps[0].filter = 'id > 1';
  assert.throws(() => issueEffectRunMaterials(original.allowed, original.definition,
    {...original.retained, document: JSON.stringify(program)}),
  {code: 'RunHostEffectRunMaterialsRejected'});
  for (const alter of [
    body => { body.run_id = 'another-run'; },
    body => { body.valid_until = '2099-01-01T00:00:00.000Z'; },
    body => { body.program = JSON.stringify(program); },
    body => { body.run_authorization = body.run_authorization.replace(fixed('b'), fixed('d')); },
  ]) {
    const body = JSON.parse(original.wire);
    alter(body);
    assert.notDeepEqual(body, JSON.parse(original.wire));
    assert.throws(() => admitEffectRunMaterials(JSON.stringify(body), cid, profiles),
      {code: 'RunHostEffectRestorationRejected'});
  }
  assert.throws(() => admitEffectRunMaterials(original.wire, cid, {rela: false}),
    {code: 'RunHostEffectRestorationRejected'});
});

test('shared input parsing preserves a pure Values caller and supplied parameters', () => {
  const fixture = name => readFileSync(new URL('../sdk/fixtures/' + name,
    import.meta.url), 'utf8');
  const wire = fixture('values.environment.json').trimEnd();
  const pureEnvironment = admitEnvironment(wire, JSON.parse(wire).evidence_bundle_cid, profiles);
  const program = fixture('parameter-values.json');
  const prepareFields = parameters => requestFields(prepareRequest(
    prepare(program, 'json', pureEnvironment, parameters), fixed('c'),
    'parameter-run', fixed('d')));
  assert.deepEqual(prepareFields('{"n":3}'), prepareFields(' { "n" : 3 } '));
  assert.notDeepEqual(prepareFields('{"n":3}'), prepareFields('{"n":4}'));
  compileValues(prepare(program, 'json', pureEnvironment, '{"n":3}'));
});

test('Effect input parsing preserves the bounded Parameter Values rejection', () => {
  for (const parameters of ['{', JSON.stringify({n: 'x'.repeat(65536)})]) {
    assert.throws(() => prepareEffect(document, 'json', environment, parameters),
      {code: 'RunHostEffectPreparationRejected'});
    assert.throws(() => prepare(document, 'json', environment, parameters),
      {code: 'RunHostPreparationRejected'});
  }
  assert.throws(() => prepareEffect(document, 'sql', environment), /InvalidRunHostPreparation/u);
  assert.throws(() => admitEffectRunMaterials('{}', fixed('a'), {unknown: true}), /InvalidRunHostProfiles/u);
});

test('formal Effect exports bundle for a Worker without a physical runtime', () => {
  const result = buildSync({stdin: {contents:
    "export {prepareEffect, compileEffect, admitEffectRunMaterials} from '@actql/run-host-core';",
  resolveDir: import.meta.dirname}, bundle: true, write: false,
  platform: 'browser', format: 'esm', target: 'es2022', metafile: true});
  const inputs = Object.keys(result.metafile.inputs);
  assert(inputs.some(path => path.endsWith('/dist/client_values_host_abi.js')));
  assert(inputs.every(path => !path.includes('host-node') &&
    !path.includes('local-node') && !path.startsWith('node:')));
});
