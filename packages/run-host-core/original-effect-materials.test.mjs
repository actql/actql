import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import test from 'node:test';
import {buildSync} from 'esbuild';
import {admitEnvironment, prepareEffect, compileEffect, effectExecutionShape,
  issueAllowedEffectRun, issueEffectRunDefinition, privateRunDefinition,
  privateEffectRunEvidence, privateEffectCompilationWires, prepareEffectRequest, requestFields,
  issuePreparedEffectRunMaterials, bindPreparedEffectRunMaterials, admitEffectRunMaterials,
  restoreEffectRunNormalization, sealRunEvidenceValue, effectSourceInputBinding,
  issueEffectSourceDispatch} from '@actql/run-host-core';

// Existing authoring inputs only. No normalization or execution fixture is
// supplied to the issuer: the actual original checked Owner proves its scope.
const read = name => readFileSync(new URL('./fixtures/' + name, import.meta.url), 'utf8').trimEnd();
const document = read('completion-free-effect.program.json');
const environmentWire = read('completion-free-effect.environment.json');
const profiles = {rela: true};
const environment = admitEnvironment(environmentWire,
  'sha256:cd4aeacdc39164df2cf7e7cb74faf349a157677a5927d9e84379d0d8df2d91e7', profiles);
const fixed = character => 'sha256:' + character.repeat(64);
const catalogCid = 'sha256:ea21a2a2ab522cbf960c5e97120648e351db7c127768101502210ed7d8fcfb38';
const journalCid = 'sha256:849788c9eede8ad674223eb06775c2dba2cf0ed1d02ceb0a5de6ccfeec2cb087';
const expectedJournal = {entries: [], journal_cid: journalCid,
  rule_catalog_cid: catalogCid, version: 'actql-normalization-journal/0.1'};

function issued(program = document, normalizationProfile) {
  const prepared = prepareEffect(program, 'json', environment);
  const compilation = compileEffect(prepared, {normalizationProfile});
  const allowed = issueAllowedEffectRun(prepared, compilation,
    {executionContextCid: fixed('a'), hostPolicyCid: fixed('b'),
      expiresAt: '2099-01-01T00:00:00.000Z'});
  const definition = issueEffectRunDefinition(allowed, 'original-scope', 'original-run',
    '2026-10-09T00:00:00.000Z', '2098-01-01T00:00:00.000Z');
  const request = prepareEffectRequest(prepared, compilation, fixed('c'), 'original-caller');
  return {prepared, compilation, allowed, definition, request};
}

function restore(original, wire, proof) {
  return admitEffectRunMaterials(wire, privateRunDefinition(original.definition).cid, profiles, proof);
}

test('original package issuer carries preparation-owned journal and exact original Run', () => {
  const original = issued();
  assert.deepEqual(effectExecutionShape(original.prepared, original.compilation),
    {taskCount: 2, acquisitionCount: 1, effectCount: 1});
  const proof = issuePreparedEffectRunMaterials(original.allowed, original.definition, original.request);
  const wire = proof.wire;
  assert.equal(issuePreparedEffectRunMaterials(original.allowed, original.definition, original.request).wire, wire);
  const body = JSON.parse(wire);
  assert.deepEqual(JSON.parse(body.normalization_journal_json), expectedJournal);
  assert.deepEqual(JSON.parse(body.program), JSON.parse(document));
  assert.deepEqual(JSON.parse(body.check_environment), JSON.parse(environmentWire));
  const evidence = privateEffectRunEvidence(original.allowed);
  assert.equal(body.prepared_invocation, evidence.preparedInvocationWire);
  assert.equal(body.run_authorization, evidence.authorizationWire);
  assert.equal(body.run_id, 'original-run');
  assert.equal(body.created_at, '2026-10-09T00:00:00.000Z');
  assert.equal(body.valid_until, '2098-01-01T00:00:00.000Z');
  const saved = restore(original, wire, proof);
  assert.deepEqual(privateRunDefinition(saved.definition), privateRunDefinition(original.definition));
  assert.deepEqual(requestFields(saved.request), requestFields(original.request));
  assert.deepEqual(privateEffectRunEvidence(saved.allowed), evidence);
  for (let count = 0; count < 2; count++) {
    const restored = restoreEffectRunNormalization(saved);
    assert.equal(restored.cid, journalCid);
    assert.equal(restored.wire, body.normalization_journal_json);
  }
  assert.throws(() => restoreEffectRunNormalization({...saved}), /ForeignRunHostHandle/u);
  assert.throws(() => restore(original, wire), {code: 'RunHostEffectRestorationRejected'});
  assert.throws(() => restore(original, wire, {...proof}), /ForeignRunHostHandle/u);
  assert.throws(() => restore(original, wire + ' ', proof), {code: 'RunHostEffectRestorationRejected'});
});

test('original package issuer rejects foreign Run and request without replacement input', () => {
  const original = issued();
  const changed = JSON.parse(document);
  changed.stages[0].steps[0].filter.gte[1].literal = 1;
  const other = issued(JSON.stringify(changed));
  assert.throws(() => issuePreparedEffectRunMaterials(original.allowed, other.definition, original.request),
    {code: 'RunHostEffectOriginalMaterialsRejected'});
  assert.throws(() => issuePreparedEffectRunMaterials(original.allowed, original.definition, other.request),
    {code: 'RunHostEffectOriginalMaterialsRejected'});
  assert.throws(() => issuePreparedEffectRunMaterials({...original.allowed}, original.definition),
    /ForeignRunHostHandle/u);
  assert.throws(() => issuePreparedEffectRunMaterials(original.allowed, original.definition, {...original.request}),
    /ForeignRunHostHandle/u);
  // Mutating authoring data after preparation cannot replace the retained input;
  // this API has no document/environment/parameter argument to re-prepare.
  const projected = JSON.parse(issuePreparedEffectRunMaterials(original.allowed, original.definition).wire);
  assert.deepEqual(JSON.parse(projected.program), JSON.parse(document));
});

test('actual sole-view completion and unsupported processing cannot take the empty package path', () => {
  const sole = JSON.parse(document);
  delete sole.stages[0].inputs.table.view;
  const completed = issued(JSON.stringify(sole));
  assert.throws(() => issuePreparedEffectRunMaterials(completed.allowed, completed.definition),
    {code: 'RunHostEffectOriginalMaterialsRejected'});
  const unsupported = JSON.parse(document);
  unsupported.stages[1].steps.push({take: 1});
  const other = issued(JSON.stringify(unsupported));
  assert.throws(() => issuePreparedEffectRunMaterials(other.allowed, other.definition),
    {code: 'RunHostEffectOriginalMaterialsRejected'});
});

test('package normalization restoration refuses absent and substituted saved evidence', () => {
  const original = issued();
  const body = JSON.parse(issuePreparedEffectRunMaterials(original.allowed, original.definition).wire);
  const without = {...body};
  delete without.normalization_journal_json;
  assert.throws(() => restoreEffectRunNormalization(restore(original, JSON.stringify(without))),
    {code: 'RunHostEffectNormalizationRejected'});
  const substituted = sealRunEvidenceValue('normalization_journal',
    JSON.stringify({version: 'actql-normalization-journal/0.1',
      rule_catalog_cid: fixed('f'), entries: []}),
    {maxWireBytes: 1024, maxNodes: 32, maxDepth: 8});
  body.normalization_journal_json = substituted.wire;
  assert.throws(() => restore(original, JSON.stringify(body)),
    {code: 'RunHostEffectRestorationRejected'});
});

test('original material and normalization exports remain Worker-portable', () => {
  const result = buildSync({stdin: {contents:
    "export {issuePreparedEffectRunMaterials, bindPreparedEffectRunMaterials, restoreEffectRunNormalization} from '@actql/run-host-core';",
  resolveDir: import.meta.dirname}, bundle: true, write: false, platform: 'browser',
  format: 'esm', target: 'es2022', metafile: true});
  const inputs = Object.keys(result.metafile.inputs);
  assert(inputs.some(path => path.endsWith('/dist/client_values_host_abi.js')));
  assert(inputs.every(path => !path.includes('host-node') &&
    !path.includes('local-node') && !path.startsWith('node:')));
});


test('original Run profile restores without a local issuance handle but preserves original request', () => {
  const original = issued(document, 'completion-free');
  const proof = issuePreparedEffectRunMaterials(original.allowed, original.definition, original.request);
  const root = privateRunDefinition(original.definition).cid;
  const template = JSON.parse(privateEffectCompilationWires(original.compilation).boundTemplate);
  assert.ok(template.required_profile_contracts.some(value =>
    value.profile_id === 'actql-resident-effect-completion-free/0.1' && value.contract_cid === catalogCid));
  const restored = admitEffectRunMaterials(proof.wire, root, profiles, undefined, original.request);
  assert.equal(restoreEffectRunNormalization(restored).cid, journalCid);
  assert.deepEqual(privateRunDefinition(restored.definition), privateRunDefinition(original.definition));
  assert.deepEqual(requestFields(restored.request), requestFields(original.request));
  assert.throws(() => admitEffectRunMaterials(proof.wire, root, profiles),
    {code: 'RunHostEffectRestorationRejected'});
  const otherRequest = prepareEffectRequest(original.prepared, original.compilation, fixed('c'), 'different-caller');
  assert.throws(() => admitEffectRunMaterials(proof.wire, root, profiles, undefined, otherRequest),
    {code: 'RunHostEffectRestorationRejected'});
  const changed = issuePreparedEffectRunMaterials(original.allowed, original.definition, otherRequest);
  assert.throws(() => admitEffectRunMaterials(changed.wire, root, profiles, undefined, original.request),
    {code: 'RunHostEffectRestorationRejected'});
  assert.throws(() => admitEffectRunMaterials(proof.wire + ' ', root, profiles, undefined, original.request),
    {code: 'RunHostEffectRestorationRejected'});
  const legacy = issued();
  const legacyProof = issuePreparedEffectRunMaterials(legacy.allowed, legacy.definition, legacy.request);
  assert.notEqual(root, privateRunDefinition(legacy.definition).cid);
  assert.throws(() => admitEffectRunMaterials(legacyProof.wire,
    privateRunDefinition(legacy.definition).cid, profiles, undefined, legacy.request),
    {code: 'RunHostEffectRestorationRejected'});
});


test('a separate process restores the Run-bound journal from independently retained original context', () => {
  const original = issued(document, 'completion-free');
  const proof = issuePreparedEffectRunMaterials(original.allowed, original.definition, original.request);
  // These are distinct durable inputs. The child never chooses an expected
  // Run/request by extracting them from the candidate materials body.
  const retained = {definitionCid: privateRunDefinition(original.definition).cid,
    request: requestFields(original.request), materialWire: proof.wire};
  const source = `import {readFileSync} from 'node:fs';
    import {admitRequestFields, admitEffectRunMaterials, restoreEffectRunNormalization,
      privateRunDefinition, requestFields} from '@actql/run-host-core';
    const saved = JSON.parse(readFileSync(0, 'utf8'));
    const expected = admitRequestFields(saved.request);
    const restored = admitEffectRunMaterials(saved.materialWire, saved.definitionCid,
      {rela:true}, undefined, expected);
    process.stdout.write(JSON.stringify({definitionCid:privateRunDefinition(restored.definition).cid,
      request:requestFields(restored.request), journal:restoreEffectRunNormalization(restored)}));`;
  const output = execFileSync(process.execPath, ['--input-type=module', '-e', source],
    {cwd: new URL('.', import.meta.url), input: JSON.stringify(retained),
      encoding: 'utf8', timeout: 20000, maxBuffer: 65536});
  const restored = JSON.parse(output);
  assert.equal(restored.definitionCid, retained.definitionCid);
  assert.deepEqual(restored.request, retained.request);
  assert.equal(restored.journal.cid, journalCid);
  assert.equal(restored.journal.wire, JSON.parse(proof.wire).normalization_journal_json);
});

test('finite-profile Source dispatch binds the independently issued original request', () => {
  const original = issued(document, 'completion-free');
  const binding = JSON.parse(effectSourceInputBinding(original.compilation, original.request));
  assert.equal(binding.version, 'actql-effect-source-input-binding/0.1');
  const request = JSON.parse(binding.original_request_json);
  assert.equal(request.caller_request_id, requestFields(original.request).requestId);
  assert.deepEqual(JSON.parse(binding.source_binding_json), {
    source_contract_cid: 'sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3',
    source_ref: 'connector://crm/main/r#v'});
  assert.throws(() => effectSourceInputBinding(original.compilation),
    {code: 'RunHostEffectSourceBindingRejected'});
  const other = prepareEffectRequest(original.prepared, original.compilation, fixed('c'), 'other-source-caller');
  assert.notEqual(effectSourceInputBinding(original.compilation, original.request),
    effectSourceInputBinding(original.compilation, other));
  const selection = {taskAttempt: 1, dispatchId: 'original-producer', siteKey: 'site',
    siteGeneration: 1, runtimeBundleCid: fixed('d'), connectorRegistration: 'local',
    connectorRevision: 'local/1', strategyRevision: 'strategy/1', obligationsCid: fixed('2'),
    budgetCid: fixed('3'), evidenceIssuerCapabilityCid: fixed('4'), grantCid: fixed('5')};
  assert.notEqual(issueEffectSourceDispatch(original.allowed, original.definition, original.request, selection).cid,
    issueEffectSourceDispatch(original.allowed, original.definition, other, selection).cid);
});


test('live package materials preserve the exact original handles and normalization', () => {
  const original = issued(document, 'completion-free');
  const proof = issuePreparedEffectRunMaterials(original.allowed, original.definition, original.request);
  const bound = bindPreparedEffectRunMaterials(original.allowed, original.definition, proof, original.request);
  assert.equal(bound.prepared, original.prepared);
  assert.equal(bound.compilation, original.compilation);
  assert.equal(bound.allowed, original.allowed);
  assert.equal(bound.definition, original.definition);
  assert.equal(bound.request, original.request);
  assert.equal(restoreEffectRunNormalization(bound).wire, JSON.parse(proof.wire).normalization_journal_json);
  assert.throws(() => restoreEffectRunNormalization({...bound}), /ForeignRunHostHandle/u);
  const again = bindPreparedEffectRunMaterials(original.allowed, original.definition, proof, original.request);
  assert.equal(again.prepared, original.prepared);
  assert.equal(again.compilation, original.compilation);
  assert.equal(restoreEffectRunNormalization(again).wire, restoreEffectRunNormalization(bound).wire);
});

test('live package material binding refuses copied and foreign original tuples', () => {
  const original = issued(document, 'completion-free');
  const proof = issuePreparedEffectRunMaterials(original.allowed, original.definition, original.request);
  const foreign = issued(document, 'completion-free');
  const foreignProof = issuePreparedEffectRunMaterials(foreign.allowed, foreign.definition, foreign.request);
  const foreignDefinition = issueEffectRunDefinition(foreign.allowed, 'foreign-scope', 'foreign-run',
    '2026-10-09T00:00:00.000Z', '2098-01-01T00:00:00.000Z');
  const wrongRequest = prepareEffectRequest(original.prepared, original.compilation, fixed('c'), 'other-request');
  // Run definitions are canonical contracts. A second genuine handle with
  // exactly the same Run wire is not a different Run or a new permission.
  assert.equal(privateRunDefinition(foreign.definition).wire, privateRunDefinition(original.definition).wire);
  const sameRun = bindPreparedEffectRunMaterials(original.allowed, foreign.definition, proof, original.request);
  assert.equal(sameRun.definition, foreign.definition);
  assert.equal(restoreEffectRunNormalization(sameRun).wire, JSON.parse(proof.wire).normalization_journal_json);
  for (const args of [
    [{...original.allowed}, original.definition, proof, original.request],
    [original.allowed, {...original.definition}, proof, original.request],
    [original.allowed, original.definition, {...proof}, original.request],
    [original.allowed, original.definition, proof, {...original.request}],
  ]) assert.throws(() => bindPreparedEffectRunMaterials(...args), /ForeignRunHostHandle/u);
  for (const args of [
    [foreign.allowed, original.definition, proof, original.request],
    [original.allowed, foreignDefinition, proof, original.request],
    [original.allowed, original.definition, foreignProof, original.request],
    [original.allowed, original.definition, proof, wrongRequest],
  ]) assert.throws(() => bindPreparedEffectRunMaterials(...args),
    {code: 'RunHostEffectOriginalMaterialsRejected'});
});
