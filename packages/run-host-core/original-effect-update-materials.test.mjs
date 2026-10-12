import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {admitEnvironment, admitRequestFields, prepareEffect, compileEffect,
  prepareEffectRequest, requestFields, privateEffectCompilationWires,
  issueAllowedEffectRun, issueEffectRunDefinition, privateRunDefinition,
  privateEffectRunEvidence, issuePreparedEffectRunMaterials, admitEffectRunMaterials,
  restoreEffectRunNormalization, effectSourceInputBinding} from '@actql/run-host-core';

// Authored inputs retained from the existing Core update/Source fixture.
// No product output, candidate journal or current permission is supplied.
const read = name => readFileSync(new URL('./fixtures/' + name, import.meta.url), 'utf8').trimEnd();
const document = read('completion-free-update-source.program.json');
const environmentWire = read('completion-free-update-source.environment.json');
const profiles = {rela: true};
const environment = admitEnvironment(environmentWire,
  'sha256:8d4ce402b0b54632daceba146a82fb96125483f78abb5d99c7e716f055a18d26', profiles);
const fixed = character => 'sha256:' + character.repeat(64);
const catalogCid = 'sha256:9ba6d5dff43cd54b0d61d6923fd4cb3143e1a5e238bad20b297133393d783468';
const journalCid = 'sha256:e9f69915b6368e0c8e1669b010e57e65f633bd5a8d589d3b3575c2b043f4b44d';
const expectedJournal = {entries: [], journal_cid: journalCid,
  rule_catalog_cid: catalogCid, version: 'actql-normalization-journal/0.1'};

function issued(program = document, options = {normalizationProfile: 'completion-free'}) {
  const prepared = prepareEffect(program, 'json', environment);
  const compilation = compileEffect(prepared, options);
  const request = prepareEffectRequest(prepared, compilation, fixed('c'), 'original-update-caller');
  const allowed = issueAllowedEffectRun(prepared, compilation,
    {executionContextCid: fixed('a'), hostPolicyCid: fixed('b'),
      expiresAt: '2099-01-01T00:00:00.000Z'});
  const definition = issueEffectRunDefinition(allowed, 'original-update-scope', 'original-update-run',
    '2026-10-09T00:00:00.000Z', '2098-01-01T00:00:00.000Z');
  return {prepared, compilation, request, allowed, definition};
}

function independentlyRetained(original) {
  return admitRequestFields(requestFields(original.request));
}

test('the installed supplier uses the original update proof for compilation and material issuance', () => {
  const original = issued();
  const template = JSON.parse(privateEffectCompilationWires(original.compilation).boundTemplate);
  assert.ok(template.required_profile_contracts.some(value =>
    value.profile_id === 'actql-local-update-completion-free/0.1' && value.contract_cid === catalogCid));
  assert.ok(template.required_profile_contracts.every(value =>
    value.profile_id !== 'actql-resident-effect-completion-free/0.1'));
  const proof = issuePreparedEffectRunMaterials(original.allowed, original.definition, original.request);
  assert.equal(issuePreparedEffectRunMaterials(original.allowed, original.definition, original.request).wire, proof.wire);
  const body = JSON.parse(proof.wire);
  assert.deepEqual(JSON.parse(body.normalization_journal_json), expectedJournal);
  const restored = admitEffectRunMaterials(proof.wire, privateRunDefinition(original.definition).cid,
    profiles, undefined, independentlyRetained(original));
  assert.deepEqual(privateRunDefinition(restored.definition), privateRunDefinition(original.definition));
  assert.deepEqual(requestFields(restored.request), requestFields(original.request));
  assert.deepEqual(privateEffectRunEvidence(restored.allowed), privateEffectRunEvidence(original.allowed));
  assert.equal(restoreEffectRunNormalization(restored).cid, journalCid);
  assert.equal(restoreEffectRunNormalization(restored).wire, body.normalization_journal_json);
  const binding = JSON.parse(effectSourceInputBinding(original.compilation, original.request));
  assert.equal(JSON.parse(binding.original_request_json).caller_request_id, 'original-update-caller');
});

test('update materials refuse copied or foreign original handles and an independent foreign Request', () => {
  const original = issued();
  const changed = JSON.parse(document);
  changed.stages[0].steps[0].filter.gte[1].literal = 1;
  const other = issued(JSON.stringify(changed));
  const proof = issuePreparedEffectRunMaterials(original.allowed, original.definition, original.request);
  const root = privateRunDefinition(original.definition).cid;
  // A separately admitted equal definition is the same content-addressed Run,
  // not a foreign identity. Use a changed checked Program for refusal below.
  const equivalent = issued();
  assert.equal(issuePreparedEffectRunMaterials(original.allowed, equivalent.definition, original.request).wire,
    proof.wire);
  assert.throws(() => issuePreparedEffectRunMaterials({...original.allowed}, original.definition, original.request),
    /ForeignRunHostHandle/u);
  assert.throws(() => issuePreparedEffectRunMaterials(original.allowed, other.definition, original.request),
    {code: 'RunHostEffectOriginalMaterialsRejected'});
  assert.throws(() => issuePreparedEffectRunMaterials(original.allowed, original.definition, other.request),
    {code: 'RunHostEffectOriginalMaterialsRejected'});
  const foreign = prepareEffectRequest(original.prepared, original.compilation, fixed('c'), 'foreign-update-caller');
  assert.throws(() => admitEffectRunMaterials(proof.wire, root, profiles, undefined, foreign),
    {code: 'RunHostEffectRestorationRejected'});
  assert.throws(() => admitEffectRunMaterials(proof.wire, root, profiles),
    {code: 'RunHostEffectRestorationRejected'});
  assert.throws(() => effectSourceInputBinding(original.compilation),
    {code: 'RunHostEffectSourceBindingRejected'});
});

test('the original update profile refuses a substituted mapped-create journal or unprofiled Run', () => {
  const original = issued();
  const body = JSON.parse(issuePreparedEffectRunMaterials(original.allowed, original.definition, original.request).wire);
  body.normalization_journal_json = JSON.stringify({entries: [],
    journal_cid: 'sha256:849788c9eede8ad674223eb06775c2dba2cf0ed1d02ceb0a5de6ccfeec2cb087',
    rule_catalog_cid: 'sha256:ea21a2a2ab522cbf960c5e97120648e351db7c127768101502210ed7d8fcfb38',
    version: 'actql-normalization-journal/0.1'});
  assert.throws(() => admitEffectRunMaterials(JSON.stringify(body),
    privateRunDefinition(original.definition).cid, profiles, undefined, independentlyRetained(original)),
  {code: 'RunHostEffectRestorationRejected'});
  const unprofiled = issued(document, {});
  assert.throws(() => issuePreparedEffectRunMaterials(unprofiled.allowed, unprofiled.definition, unprofiled.request),
    {code: 'RunHostEffectOriginalMaterialsRejected'});
});

test('the installed update supplier refuses original implicit sole-view completion', () => {
  const implicit = JSON.parse(document);
  delete implicit.stages[0].inputs.table.view;
  const prepared = prepareEffect(JSON.stringify(implicit), 'json', environment);
  assert.throws(() => compileEffect(prepared, {normalizationProfile: 'completion-free'}),
    {code: 'RunHostEffectCompilationRejected'});
});

test('a separate process restores the original update Run and journal from independent retained metadata', () => {
  const original = issued();
  const proof = issuePreparedEffectRunMaterials(original.allowed, original.definition, original.request);
  const retained = {definitionCid: privateRunDefinition(original.definition).cid,
    request: requestFields(original.request), materialWire: proof.wire};
  const source = `import {readFileSync} from 'node:fs';
    import {admitRequestFields, admitEffectRunMaterials, restoreEffectRunNormalization,
      privateRunDefinition, requestFields} from '@actql/run-host-core';
    const saved = JSON.parse(readFileSync(0, 'utf8'));
    const expected = admitRequestFields(saved.request);
    const restored = admitEffectRunMaterials(saved.materialWire, saved.definitionCid,
      {rela:true}, undefined, expected);
    process.stdout.write(JSON.stringify({definition:privateRunDefinition(restored.definition),
      request:requestFields(restored.request), journal:restoreEffectRunNormalization(restored)}));`;
  const output = execFileSync(process.execPath, ['--input-type=module', '-e', source],
    {cwd: new URL('.', import.meta.url), input: JSON.stringify(retained),
      encoding: 'utf8', timeout: 20000, maxBuffer: 65536});
  const restored = JSON.parse(output);
  assert.deepEqual(restored.definition, privateRunDefinition(original.definition));
  assert.deepEqual(restored.request, retained.request);
  assert.equal(restored.journal.cid, journalCid);
  assert.equal(restored.journal.wire, JSON.parse(proof.wire).normalization_journal_json);
});
