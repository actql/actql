// Actual Common preparation/admission and original Host planning boundaries.
// These cases install no physical Provider and grant no resume or send authority.
import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {installNodeClientProgramPreparation} from './client-program-preparation.mjs';
import {restoreInferTaskRunAdmission} from './local-values-plan.mjs';
import {readInstalledModelExecution} from './installed-model.mjs';
import {originalModelRunWire} from './installed-model-originals.mjs';
import {openFundedClientPreparation} from './funded-client-preparation.fixture.mjs';
import {identity, configuration, program} from '../../scripts/fixtures/first-m1-common-materials.mjs';

const runtimeUrl = process.env.ACTQL_INFER_ORIGINAL_RUNTIME === undefined
  ? new URL('../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js', import.meta.url)
  : pathToFileURL(process.env.ACTQL_INFER_ORIGINAL_RUNTIME);
const moon = await import(runtimeUrl.href);
const control = runtimeCore(moon).publicationControl;
const base = JSON.parse(readFileSync(new URL('../../spec/local-check-environment.json', import.meta.url)));
const profiles = Object.freeze([false, false, true, false, false, false, false]);
const bounds = Object.freeze({maxWireBytes: 1000000, maxNodes: 100000, maxDepth: 64});
const cid = value => 'sha256:' + value.repeat(64);
const policyWire = '{"classification":"unknown","source_data_policy_cids":[],"source_response_policy_cids":[],"unknown_provenance":true,"version":"actql-effective-data-policy/0.1"}';

function original(parameters = null) {
  const installation = configuration(base);
  const environment = moon.clientProgramCheckEnvironment(installation.environmentWire,
    JSON.parse(installation.environmentWire).evidence_bundle_cid, ...profiles);
  assert.ok(environment);
  const prepare = installNodeClientProgramPreparation({moon, environment});
  const prepared = prepare({kind: 'program', input: program, parameters});
  return compileOriginal(prepare, prepared, environment, installation);
}

function compileOriginal(prepare, prepared, environment, installation) {
  const inputs = prepare.originalInputs(prepared);
  const {execution} = readInstalledModelExecution(moon, prepared, installation);
  const graph = checked(moon.clientProgramInstalledInferPlanGraph(prepared, 2, execution));
  const compiled = control.prepareCheckedClientCompiledRun(prepared, 'infer', {
    executionContextCid: cid('a'), hostPolicyCid: cid('b'), expiresAt: '2099-01-01T00:00:00.000Z',
    resultDataPolicy: {kind: 'data_policy', wire: policyWire, cid: identity(JSON.parse(policyWire))},
  }, graph);
  const definition = control.defineCheckedClientCompiledRun(compiled, {namespaceId: 'original',
    runId: 'original-host-infer', createdAt: '2026-10-18T00:00:00.000Z', validUntil: '2099-01-01T00:00:00.000Z'});
  const request = moon.clientProgramRequestIdentity(prepared, cid('c'), 'original-request',
    moon.clientProgramSourceFreeInputIntentCid());
  assert.ok(request);
  const evidence = Object.freeze({prepared: compiled.preparedEvidence.wire,
    authorization: compiled.authorization.wire, modelOriginalRunWire: originalModelRunWire(compiled, definition)});
  const ticket = control.captureOriginalClientInferRun(compiled, prepared, definition, request,
    inputs.environment, inputs.parameters);
  const materials = control.originalInferRunAdmissionEvidence(ticket, definition, request, evidence);
  const restore = () => control.admitStoredClientInferRunOriginal(materials, definition, request, evidence, profiles, bounds);
  return {prepare, prepared, inputs, environment, compiled, definition, request, evidence, graph, materials, restore};
}

test('Host preparation retains exact admitted Environment and original serialized Parameter Values once', () => {
  const parameters = {};
  const value = original(parameters);
  parameters.changedAfterPreparation = true;
  assert.strictEqual(value.inputs.environment, value.environment);
  assert.equal(value.inputs.parameters, '{}');
  assert.ok(Object.isFrozen(value.inputs));
  assert.strictEqual(value.prepare.originalInputs(value.prepared), value.inputs);
  assert.throws(() => value.prepare.originalInputs({...value.prepared}), {code: 'ClientProgramPreparationFailure'});
});

test('restored Host preparation uses saved Task materials even when current Environment has no such Task', () => {
  const value = original();
  const current = moon.clientProgramCheckEnvironment(JSON.stringify(base), base.evidence_bundle_cid, ...profiles);
  assert.ok(current);
  const prepare = installNodeClientProgramPreparation({moon, environment: current,
    restoreInferOriginal: (materials, definition, request, evidence) =>
      control.admitStoredClientInferRunOriginal(materials, definition, request, evidence, profiles, bounds)});
  assert.throws(() => prepare({kind: 'program', input: program, parameters: null}));
  const prepared = prepare.restoreInferOriginal(value.materials, value.definition, value.request, value.evidence);
  prepare.assertOwned(prepared);
  assert.equal(prepare.kindOf(prepared), 'effect_free');
  assert.throws(() => prepare.assertOwned(value.prepared), /Foreign/u);
  assert.throws(() => prepare.assertOwned({...prepared}), /Foreign/u);
  const restored = prepare.originalInferRun(prepared);
  assert.strictEqual(restored.prepared, prepared);
  assert.strictEqual(restored.runDefinition, value.definition);
  assert.equal(originalModelRunWire(restored.compiled, restored.runDefinition), value.evidence.modelOriginalRunWire);
  // A restored selection cannot mint a new first-admission input snapshot.
  assert.throws(() => prepare.originalInputs(prepared), {code: 'ClientProgramPreparationFailure'});
});

test('Common compiled Infer projection rejects foreign nominal preparation and copied compilation', () => {
  const value = original(), other = original();
  const selected = control.checkedClientCompiledInferOriginal(value.compiled, value.prepared, value.definition);
  assert.strictEqual(selected.graph, value.graph);
  assert.throws(() => control.checkedClientCompiledInferOriginal(value.compiled, other.prepared, value.definition), /Foreign/u);
  assert.throws(() => control.checkedClientCompiledInferOriginal({...value.compiled}, value.prepared, value.definition), /Foreign/u);
});

test('actual Common boxed plural originals retain fresh and restored compiler members', async t => {
  const installation = configuration(base);
  const environment = moon.clientProgramCheckEnvironment(installation.environmentWire,
    JSON.parse(installation.environmentWire).evidence_bundle_cid, ...profiles);
  assert.ok(environment);
  const funded = await openFundedClientPreparation({moon, environment});
  t.after(funded.close);
  const prepared = await funded.prepare({kind: 'program', input: program, parameters: null});
  const value = compileOriginal(funded.prepare, prepared, environment, installation);
  const restored = value.restore();
  for (const selected of [value, restored]) {
    const definition = selected.runDefinition ?? value.definition;
    const singular = control.checkedClientCompiledInferOriginal(selected.compiled, selected.prepared, definition);
    const plural = control.checkedClientCompiledInferOriginals(selected.compiled, selected.prepared, definition);
    assert.equal(plural.length, 1);
    assert.strictEqual(plural[0].graph, singular.graph);
    assert.strictEqual(plural[0].execution, singular.execution);
    assert.ok(Object.isFrozen(plural));
    assert.ok(Object.isFrozen(plural[0]));
    assert.throws(() => control.checkedClientCompiledInferOriginals(
      selected.compiled, {}, definition), /Foreign Client original Infer preparation/u);
    assert.throws(() => control.checkedClientCompiledInferOriginals(
      {...selected.compiled}, selected.prepared, definition), /Foreign/u);
  }
});

test('restored Infer plan retains original Run and never calls fresh compilation or definition issuers', () => {
  const value = original(), restored = value.restore();
  let issued = 0;
  const observed = Object.freeze({...control,
    prepareCheckedClientCompiledRun() {issued++; throw new Error('UnexpectedNewCompilation');},
    defineCheckedClientCompiledRun() {issued++; throw new Error('UnexpectedNewRun');}});
  const plan = restoreInferTaskRunAdmission({control: observed, preparedProgram: restored.prepared, restored});
  assert.equal(issued, 0);
  assert.strictEqual(plan.compiled, restored.compiled);
  assert.strictEqual(plan.runDefinition, value.definition);
  assert.strictEqual(plan.inferGraph, restored.graph);
  assert.equal(plan.createdAt, '2026-10-18T00:00:00.000Z');
  assert.equal(plan.preparedEvidence.wire, value.evidence.prepared);
  assert.equal(plan.authorization.wire, value.evidence.authorization);
  assert.equal(originalModelRunWire(plan.compiled, plan.runDefinition), value.evidence.modelOriginalRunWire);
});

test('restored Infer plan refuses equal-byte foreign graph or original caller preparation substitution', () => {
  const value = original(), restored = value.restore(), other = value.restore();
  assert.notStrictEqual(restored.graph, other.graph);
  assert.throws(() => restoreInferTaskRunAdmission({control, preparedProgram: value.prepared, restored}), /Foreign/u);
  assert.throws(() => restoreInferTaskRunAdmission({control, preparedProgram: restored.prepared,
    restored: {...restored, graph: other.graph}}), /Foreign/u);
  assert.throws(() => restoreInferTaskRunAdmission({control, preparedProgram: restored.prepared,
    restored: {...restored, runDefinition: other.runDefinition}}), /Foreign/u);
  assert.throws(() => restoreInferTaskRunAdmission({control, preparedProgram: restored.prepared,
    restored: {...restored}}), /Foreign/u);
});
