// Real JS control wrapper, with independent compiler-token stand-ins. These
// tests prove the adapter's nominal binding, not MoonBit compiler execution.
import assert from 'node:assert/strict';
import test from 'node:test';
import {createHash} from 'node:crypto';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {canonicalText} from '../../scripts/check-canonical-json.mjs';
import {request, definition, evidence, planOriginal} from './fixtures/original-plan-journal.mjs';

const limits = {maxWireBytes: 65536, maxNodes: 4096, maxDepth: 64};
const ok = _0 => ({$tag: 1, _0});
function fixture(changes = {}) {
  const owner = {}, compilation = {}, value = {};
  const counts = {compiles: 0, projects: 0, bindings: 0, planAdmissions: 0, mapAdmissions: 0};
  const plan = {name: 'compiled_plan', identity: JSON.parse(planOriginal.planViewWire).compiled_plan_cid,
    wire: planOriginal.compiledPlanWire};
  const prepared = {name: 'prepared_invocation', identity: 'prepared-id', wire: evidence.prepared};
  const authorization = {name: 'run_authorization', identity: 'authority-id', wire: evidence.authorization};
  const moon = {
    strategyRemoteManagedOutputEvidenceKind: () => 'unused-fixture-constructor',
    clientProgramCompileLocalValues(original) {assert.equal(original, owner); counts.compiles++; return ok(compilation);},
    clientProgramIssueValuesCompiledRun(original, selected) {assert.equal(original, owner); assert.equal(selected, compilation); return ok(value);},
    clientProgramCompiledRunTemplate: () => prepared,
    clientProgramCompiledRunPlan: () => plan,
    clientProgramCompiledRunPrepared: () => prepared,
    clientProgramCompiledRunAuthorization: () => authorization,
    clientProgramCompiledRunAdmission: () => ({}),
    clientProgramCompiledRunMatches: (selected, original) => selected === value && original === owner,
    clientProgramCheckCompiledRunDefinition: (selected, run) => selected === value && run.identity === definition.identity,
    clientProgramDefinitionCid: original => {assert.equal(original, owner); return request.programDefinitionCid;},
    clientProgramCompiledRunStaticPlanView(selected, original) {
      assert.equal(selected, value); assert.equal(original, owner); counts.projects++; return ok(planOriginal.planViewWire);
    },
    strategyPublicationContractName: token => token.name,
    strategyPublicationContractIdentityField: token => token.name + '_cid',
    strategyPublicationContractIdentity: token => token.identity,
    strategyPublicationContractJson: token => token.wire,
    strategyRunEvidenceName: token => token.name,
    strategyRunEvidenceIdentity: token => token.identity,
    strategyRunEvidenceJson: token => token.wire,
    strategyPublicationAdmit(name, wire) {
      if (name === 'compiled_plan') counts.planAdmissions++;
      return ok({name, wire, identity: JSON.parse(wire)[name + '_cid']});
    },
    strategyRunEvidenceAdmit(name, wire) {
      if (name === 'logical_map') counts.mapAdmissions++;
      const body = JSON.parse(wire), {self_cid, ...preimage} = body;
      const expected = `sha256:${createHash('sha256').update(canonicalText(preimage)).digest('hex')}`;
      return expected !== self_cid ? {$tag: 0, _0: 'independent CID mismatch'} :
        ok({name, wire, identity: self_cid});
    },
    clientProgramCheckLogicalMapBinding(map, compiled) {
      counts.bindings++; assert.equal(map.name, 'logical_map'); assert.equal(compiled.name, 'compiled_plan');
      assert.equal(JSON.parse(map.wire).compiled_plan_cid, compiled.identity); return ok(undefined);
    },
    ...changes,
  };
  const control = runtimeCore(moon).publicationControl;
  const compiled = control.prepareCheckedClientCompiledRun(owner, 'values', {});
  const run = control.admit('run_definition', definition.wire, limits);
  return {control, compiled, run, owner, moon, counts};
}

test('compiler-issued plan capture does not admit its own output as stored input', () => {
  const f = fixture();
  const selected = f.control.captureOriginalClientRunPlan(f.compiled, f.owner, f.run, limits);
  assert.deepEqual(f.control.originalRunPlanAdmissionEvidence(selected, f.run,
    request.programDefinitionCid, evidence), planOriginal);
  assert.deepEqual({plan: f.counts.planAdmissions, map: f.counts.mapAdmissions,
    bindings: f.counts.bindings}, {plan: 0, map: 0, bindings: 0});
  assert.equal(f.counts.compiles, 1);
  assert.equal(f.counts.projects, 1);
  f.control.readStoredRunPlanOriginal(planOriginal, f.run, request.programDefinitionCid, limits);
  assert.deepEqual({plan: f.counts.planAdmissions, map: f.counts.mapAdmissions,
    bindings: f.counts.bindings}, {plan: 1, map: 1, bindings: 1});
});

test('original map selection retains the actual compiler owner and performs no recompile on read', () => {
  const f = fixture();
  const selected = f.control.captureOriginalClientRunPlan(f.compiled, f.owner, f.run, limits);
  assert.equal(Object.keys(selected).length, 0);
  const original = f.control.originalRunPlanAdmissionEvidence(selected, f.run, request.programDefinitionCid, evidence);
  assert.deepEqual(original, planOriginal); assert.equal(Object.isFrozen(original), true);
  assert.equal(f.control.readStoredRunPlanOriginal(original, f.run, request.programDefinitionCid, limits), planOriginal.planViewWire);
  assert.equal(f.counts.compiles, 1); assert.equal(f.counts.projects, 1); assert.equal(f.counts.bindings, 1);
});

test('copied selections and foreign original Run or preparation are refused', () => {
  const f = fixture();
  assert.throws(() => f.control.captureOriginalClientRunPlan({...f.compiled}, f.owner, f.run, limits), TypeError);
  assert.throws(() => f.control.captureOriginalClientRunPlan(f.compiled, {}, f.run, limits), TypeError);
  assert.throws(() => f.control.captureOriginalClientRunPlan(f.compiled, f.owner, {...f.run}, limits), TypeError);
  const selected = f.control.captureOriginalClientRunPlan(f.compiled, f.owner, f.run, limits);
  for (const [ticket, run, programCid, admitted] of [
    [{}, f.run, request.programDefinitionCid, evidence],
    [selected, {...f.run}, request.programDefinitionCid, evidence],
    [selected, f.run, 'sha256:' + 'f'.repeat(64), evidence],
    [selected, f.run, request.programDefinitionCid, {...evidence, prepared: 'changed'}],
    [selected, f.run, request.programDefinitionCid, {...evidence, authorization: 'changed'}],
  ]) assert.throws(() => f.control.originalRunPlanAdmissionEvidence(ticket, run, programCid, admitted), TypeError);
});

test('restored map checks original Plan Program and self CID without another compilation', () => {
  const f = fixture();
  const changed = JSON.parse(planOriginal.planViewWire);
  changed.compiled_plan_cid = 'sha256:' + 'f'.repeat(64);
  assert.throws(() => f.control.readStoredRunPlanOriginal({...planOriginal,
    planViewWire: JSON.stringify(changed)}, f.run, request.programDefinitionCid, limits), TypeError);
  assert.throws(() => f.control.readStoredRunPlanOriginal(planOriginal, f.run,
    'sha256:' + 'f'.repeat(64), limits), TypeError);
  const tampered = JSON.parse(planOriginal.planViewWire);
  tampered.logical_map.steps[0].names = ['changed'];
  assert.throws(() => f.control.readStoredRunPlanOriginal({...planOriginal,
    planViewWire: JSON.stringify(tampered)}, f.run, request.programDefinitionCid, limits), {code: 'MoonBitHostFailure'});
  assert.equal(f.counts.compiles, 1); assert.equal(f.counts.projects, 0);
});

test('invalid bounds or missing installed projection never fall back to compilation', () => {
  const f = fixture();
  for (const bounds of [null, {...limits, maxWireBytes: 0}, {...limits, maxDepth: '64'}]) {
    assert.throws(() => f.control.captureOriginalClientRunPlan(f.compiled, f.owner, f.run, bounds), TypeError);
  }
  const absent = fixture({clientProgramCompiledRunStaticPlanView: undefined});
  assert.throws(() => absent.control.captureOriginalClientRunPlan(absent.compiled,
    absent.owner, absent.run, limits), {code: 'ClientOperationUnavailable'});
  assert.equal(f.counts.compiles, 1); assert.equal(f.counts.projects, 0);
  assert.equal(absent.counts.compiles, 1);
});

test('compiler-original capture preserves independent stored wire byte ceilings', () => {
  const plan = fixture({clientProgramCompiledRunPlan: () => ({name: 'compiled_plan',
    identity: JSON.parse(planOriginal.planViewWire).compiled_plan_cid,
    wire: 'x'.repeat(limits.maxWireBytes + 1)})});
  const view = fixture({clientProgramCompiledRunStaticPlanView: () =>
    ok('x'.repeat(limits.maxWireBytes + 1))});
  for (const f of [plan, view]) {
    assert.throws(() => f.control.captureOriginalClientRunPlan(f.compiled,
      f.owner, f.run, limits), TypeError);
    assert.equal(f.counts.planAdmissions, 0);
    assert.equal(f.counts.mapAdmissions, 0);
    assert.equal(f.counts.bindings, 0);
  }
});
