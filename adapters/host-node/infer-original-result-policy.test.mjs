// Actual private-map adapter with explicit compiler ports. These counters do
// not install a Source, Journal, physical Model or operational resource issuer.
import assert from 'node:assert/strict';
import test from 'node:test';
import {runtimeCore} from '../host-common/runtime-core.mjs';

function fixture({sourceFree = false, missing = false} = {}) {
  const prepared = {}, request = {}, environment = {}, graph = {}, raw = {}, definitionToken = {};
  const restoredPrepared = {}, restoredGraph = {}, restoredRaw = {}, materials = {};
  const restoredGraphs = [restoredGraph, {}], restoredExecutions = [{}, {}];
  const policy = Object.freeze({kind: 'data_policy', cid: sourceFree ? 'legacy-policy' : 'original-source-policy',
    wire: sourceFree ? '{"unknown_provenance":true}' : '{"classification":"internal","original_source":true}'});
  const tuple = value => value === undefined ? undefined : {_0: value.kind, _1: value.cid, _2: value.wire};
  const ok = value => ({$tag: 1, _0: value});
  let issues = 0, restores = 0, strictReads = 0, binds = 0;
  const moon = {
    strategyRemoteManagedOutputEvidenceKind: () => 'fixture',
    strategyPublicationAdmit: () => ok(definitionToken),
    strategyPublicationContractName: () => 'run_definition',
    strategyPublicationContractIdentityField: () => 'run_definition_cid',
    strategyPublicationContractIdentity: () => 'original-run',
    strategyPublicationContractJson: () => '{}',
    strategyRunEvidenceName: () => 'fixture',
    strategyRunEvidenceIdentity: () => 'evidence',
    strategyRunEvidenceJson: () => '{}',
    clientProgramCompileLocalInfer: (owner, selected) => {
      assert.strictEqual(owner, prepared); assert.strictEqual(selected, graph); return ok({});
    },
    clientProgramIssueTaskCompiledRun: () => ok(raw),
    clientProgramBindCompiledInferResultPolicy: (value, cid, wire) => {
      binds++;
      if (sourceFree && (cid !== policy.cid || wire !== policy.wire)) return {$tag: 0, _0: 'InvalidPolicy'};
      return ok(value);
    },
    clientProgramCompiledRunTemplate: () => ({}),
    clientProgramCompiledRunPlan: () => ({}),
    clientProgramCompiledRunPrepared: () => ({}),
    clientProgramCompiledRunAuthorization: () => ({}),
    clientProgramCompiledRunAdmission: () => ({}),
    clientProgramCompiledRunMatches: (value, owner) => value === raw && owner === prepared,
    clientProgramMatchesRequestIdentity: (owner, original) =>
      (owner === prepared || owner === restoredPrepared) && original === request,
    clientProgramCheckCompiledRunDefinition: (value, original) =>
      (value === raw || value === restoredRaw) && original === definitionToken,
    clientProgramCompiledRunSourceFreeResultPolicy: () => sourceFree ? tuple(policy) : undefined,
    clientProgramCompiledRunEvaluationPolicy: () => missing ? undefined : tuple(policy),
    clientProgramAdmitSourceFreeResultPolicyBody: () => { strictReads++; assert.fail('not an alternate policy issuer'); },
    clientProgramIssueInferRunMaterials: (value, original, env, parameters) => {
      issues++;
      assert.strictEqual(value, raw); assert.strictEqual(original, definitionToken);
      assert.strictEqual(env, environment); assert.equal(parameters, '{"threshold":1}');
      return ok('original-materials');
    },
    clientProgramAdmitInferRunMaterials: (wire, cid) => {
      restores++; assert.equal(wire, 'original-materials'); assert.equal(cid, 'original-run'); return ok(materials);
    },
    clientProgramInferRunMaterialsCompiled: value => { assert.strictEqual(value, materials); return ok(restoredRaw); },
    clientProgramInferRunMaterialsPrepared: () => restoredPrepared,
    clientProgramInferRunMaterialsGraph: () => restoredGraph,
  };
  const control = runtimeCore(moon).publicationControl;
  const limits = {maxWireBytes: 10000, maxNodes: 1000, maxDepth: 64};
  const definition = control.admit('run_definition', '{}', limits);
  const compiled = control.prepareCheckedClientCompiledRun(prepared, 'infer', {resultDataPolicy: policy}, graph);
  const evidence = {prepared: compiled.preparedEvidence.wire, authorization: compiled.authorization.wire};
  const capture = () => control.captureOriginalClientInferRun(compiled, prepared, definition, request,
    environment, '{"threshold":1}');
  const original = () => control.originalInferRunAdmissionEvidence(capture(), definition, request, evidence);
  const restore = saved => control.admitStoredClientInferRunOriginal(saved, definition, request, evidence,
    [false, false, true, false, false, false, false], limits);
  return {control, moon, policy, original, capture, restore, definition, request, prepared, compiled,
    restoredPrepared, restoredGraph, restoredGraphs, restoredExecutions, restoredRaw, evidence,
    counts: () => ({issues, restores, strictReads, binds})};
}

test('Source-backed Infer captures and restores the original complete checked policy without source-free admission', () => {
  const f = fixture(), saved = f.original();
  assert.deepEqual(saved.resultPolicyOriginal, f.policy);
  assert.ok(Object.isFrozen(saved.resultPolicyOriginal));
  const restored = f.restore(saved);
  assert.strictEqual(restored.prepared, f.restoredPrepared);
  assert.strictEqual(restored.graph, f.restoredGraph);
  assert.strictEqual(restored.runDefinition, f.definition);
  assert.deepEqual(f.control.compiledInferEvaluationPolicy(restored.compiled), f.policy);
  assert.deepEqual(f.counts(), {issues: 1, restores: 1, strictReads: 0, binds: 2});
});

test('saved Source policy cannot change CID or wire or replace missing original facts with unknown', () => {
  const f = fixture(), saved = f.original();
  for (const policy of [
    {...f.policy, cid: 'foreign-policy'}, {...f.policy, wire: '{"classification":"public"}'},
    {kind: 'data_policy', cid: 'legacy-policy', wire: '{"unknown_provenance":true}'},
  ]) assert.throws(() => f.restore({...saved, resultPolicyOriginal: policy}), /Foreign Client original Infer Result policy/u);
  f.moon.clientProgramCompiledRunEvaluationPolicy = () => undefined;
  assert.throws(() => f.restore(saved), /Foreign Client original Infer Result policy/u);
});

test('missing checked Result policy refuses first admission before materials issuance', () => {
  const f = fixture({missing: true});
  assert.throws(f.capture, /Missing Client original Infer Result policy/u);
  assert.equal(f.counts().issues, 0);
});

test('saved policy uses the closed original shape and existing wire bound before reconstructing materials', () => {
  const f = fixture(), saved = f.original();
  for (const policy of [undefined, null, {}, {...f.policy, extra: true}, {...f.policy, kind: 'egress'},
    {...f.policy, wire: ''}, {...f.policy, wire: 'x'.repeat(10001)}, {...f.policy, cid: 1}]) {
    assert.throws(() => f.restore({...saved, resultPolicyOriginal: policy}), /Invalid Client original Infer Result policy/u);
  }
  assert.equal(f.counts().restores, 0);
});

test('legacy source-free Infer retains the strict binder and identical saved policy', () => {
  const f = fixture({sourceFree: true}), saved = f.original();
  assert.deepEqual(saved.resultPolicyOriginal, f.policy);
  f.restore(saved);
  assert.throws(() => f.restore({...saved, resultPolicyOriginal: {...f.policy, cid: 'replacement'}}),
    {code: 'RunHostResultPolicyRejected'});
});

test('policy projection still refuses copied compilation and foreign original request or evidence', () => {
  const f = fixture(), selected = f.capture();
  assert.throws(() => f.control.compiledInferEvaluationPolicy({...f.compiled}), /Foreign/u);
  assert.throws(() => f.control.originalInferRunAdmissionEvidence({...selected}, f.definition, f.request, f.evidence), /Foreign/u);
  assert.throws(() => f.control.originalInferRunAdmissionEvidence(selected, f.definition, {}, f.evidence), /Foreign/u);
  const saved = f.control.originalInferRunAdmissionEvidence(selected, f.definition, f.request, f.evidence);
  assert.throws(() => f.control.admitStoredClientInferRunOriginal(saved, f.definition, {}, f.evidence,
    [false, false, true, false, false, false, false], {maxWireBytes: 10000, maxNodes: 1000, maxDepth: 64}), /Foreign/u);
});

test('plural saved Infer preserves each opaque graph and execution in a copied ordered inventory', () => {
  const f = fixture();
  f.moon.clientProgramInferRunMaterialsGraphs = () => f.restoredGraphs;
  f.moon.clientProgramCompiledInferOriginals = (raw, prepared) => {
    assert.strictEqual(raw, f.restoredRaw);
    return prepared === f.restoredPrepared
      ? f.restoredGraphs.map((graph, index) => ({_0: graph, _1: f.restoredExecutions[index]})) : undefined;
  };
  const restored = f.restore(f.original());
  assert.ok(Object.isFrozen(restored.graph));
  assert.notStrictEqual(restored.graph, f.restoredGraphs);
  assert.deepEqual(restored.graph, f.restoredGraphs);
  const originals = f.control.checkedClientCompiledInferOriginals(
    restored.compiled, f.restoredPrepared, f.definition);
  assert.ok(Object.isFrozen(originals));
  originals.forEach((original, index) => {
    assert.ok(Object.isFrozen(original));
    assert.strictEqual(original.graph, f.restoredGraphs[index]);
    assert.strictEqual(original.execution, f.restoredExecutions[index]);
  });
  f.restoredGraphs.push({});
  assert.equal(restored.graph.length, 2, 'the Core projection cannot mutate retained outer membership');
  assert.equal(originals.length, 2);
  assert.throws(() => f.control.checkedClientCompiledInferOriginals(
    {...restored.compiled}, f.restoredPrepared, f.definition), /Foreign/u);
  assert.throws(() => f.control.checkedClientCompiledInferOriginals(
    restored.compiled, {}, f.definition), /Foreign/u);
});

test('saved Infer rejects missing, empty and oversized graph inventories before retaining a restored owner', () => {
  const f = fixture(), saved = f.original();
  for (const graphs of [undefined, [], [undefined], [null], Array(129).fill({})]) {
    f.moon.clientProgramInferRunMaterialsGraphs = () => graphs;
    assert.throws(() => f.restore(saved), /Foreign Client original Infer materials/u);
  }
});
