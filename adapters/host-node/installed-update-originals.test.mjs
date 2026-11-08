import assert from 'node:assert/strict';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {canonicalJson as valueJson} from '../../packages/sdk/host-port.mjs';
import {createInstalledRowEffect, installedRowEffectOwnerBinding} from './installed-row-effect.mjs';
import {installUpdateTargetOriginals} from './installed-update-originals.mjs';
import {updateTargetPreparedOriginalShape as preparedShape,
  updateTargetRunOriginalShape as runShape, updateTargetSelectionsCid as selectionsCid} from './update-target-original-shape.mjs';
import {pathToFileURL} from 'node:url';
const dataOwner = await import(process.env.ACTQL_TEST_UPDATE_ORIGINAL_RUNTIME === undefined
  ? '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js'
  : pathToFileURL(process.env.ACTQL_TEST_UPDATE_ORIGINAL_RUNTIME).href);

import {recoverAdmittedEffectRun} from './effect-run-recovery.mjs';
import {installNodeClientEffectRun} from './client-effect-run.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const ok = value => ({$tag: 1, _0: value});
const limits = {maxWireBytes: 1000000, maxNodes: 100000, maxDepth: 100};
const expectedOwnerCid = 'sha256:82b29228f604437218a51df3d6504e813219649a14e80c4b7c24f505eea6c1e9';
const updateTargetPreparedOriginalShape = value => preparedShape(value, dataOwner);
const updateTargetRunOriginalShape = (value, evidence) => runShape(value, evidence, dataOwner);
const updateTargetSelectionsCid = value => selectionsCid(value, dataOwner);
// Only bounded DATA checks use the actual compiled Owner here. The explicit
// nominal ports below remain composition doubles, not execution evidence.
const dataPorts = Object.fromEntries([
  'clientProgramIssueEffectTargetInstallation', 'clientProgramEffectTargetInstallationsShape',
  'clientProgramEffectTargetPreparedOriginalShape', 'clientProgramEffectTargetRunOriginalShape',
  'clientProgramEffectTargetOriginalDataEqual', 'clientProgramEffectTargetSelectionDataCid',
  'clientProgramEffectTargetRunSelectionCid',
].map(name => [name, dataOwner[name]]));

function runInstallationFixture() {
  const calls = [];
  const forbidden = name => () => {
    calls.push(name);
    assert.fail(`Installation or absent selection must not call ${name}`);
  };
  const moon = {
    clientProgramEffectTargetSelectionOriginal(value) {
      assert.equal(this.clientProgramEffectTargetSelections(value), undefined);
      return [];
    },
    clientProgramEffectCompilationIssueCode: () => undefined,
    clientProgramEffectRunStartCurrent: forbidden('run currency'),
    clientRunStartAction: forbidden('start action'),
    clientRequestAuthorityScopeCid: forbidden('request scope'),
    clientRequestCallerId: forbidden('request caller'),
    clientProgramCompileLocalEffects() { calls.push('compile'); return ok({}); },
  };
  const control = {admit: forbidden('publication admission')};
  const originals = installUpdateTargetOriginals({moon, control, limits});
  return {moon, originals, calls, options: {moon, publicationControl: control,
    journal: {lookupDefinition: forbidden('journal lookup'),
      originalSubmittedIntent: forbidden('original submitted content lookup'),
      reserveDispatch: forbidden('dispatch reservation'),
      reservePhysicalStart: forbidden('physical start reservation')},
    authorizeRequest: forbidden('request authorization'),
    authorizeRunStart: forbidden('start authorization'),
    prepareExecution: forbidden('provider preparation'),
    execute: forbidden('provider execution')}};
}

test('installed original custody rejects a missing selection accessor before any work', () => {
  for (const accessor of [undefined, null, false, 'old runtime export']) {
    const f = runInstallationFixture();
    if (accessor !== undefined) f.moon.clientProgramEffectTargetSelections = accessor;
    assert.throws(() => installNodeClientEffectRun({...f.options,
      updateTargetOriginals: f.originals}),
    {name: 'TypeError', message: 'InvalidClientEffectRunInstallation'});
    assert.deepEqual(f.calls, []);
  }
});

test('a current selection accessor may return no context without original or provider work', () => {
  const f = runInstallationFixture();
  f.moon.clientProgramEffectTargetSelections = () => {
    f.calls.push('read selections'); return undefined;
  };
  const run = installNodeClientEffectRun({...f.options, updateTargetOriginals: f.originals});
  assert.equal(run.capturePreparedOriginal({}), undefined);
  assert.deepEqual(f.calls, ['compile', 'read selections']);
});

test('an Effect Run without installed original custody does not require the accessor', () => {
  const f = runInstallationFixture();
  assert.equal(typeof installNodeClientEffectRun(f.options).checkSupported, 'function');
  assert.deepEqual(f.calls, []);
});

test('an Effect Run requires its original journal content port before installation work', () => {
  const f = runInstallationFixture();
  delete f.options.journal.originalSubmittedIntent;
  assert.throws(() => installNodeClientEffectRun(f.options),
    {name: 'TypeError', message: 'InvalidClientEffectRunInstallation'});
  assert.deepEqual(f.calls, []);
});

// This is a Node composition fixture with the real private row factory. Core
// admission is a deliberately strict fake; MoonBit custody tests separately
// establish that body restoration is authentic, canonical and Run-bound.
async function fixture(t) {
  const root = await mkdtemp(join(tmpdir(), 'actql-update-originals-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const prepared = {}, compilation = {}, allowed = {}, definition = {};
  const originalSelection = Object.freeze({});
  let originalInstallation;
  const calls = [];
  const selections = [{stage_index: 0, effect_id: 'update', target_ref: 'connector://crm/account',
    mapping_ref: 'mapping:crm.account', mapping_cid: cid('a'), check_environment_cid: cid('b'),
    installation_binding_cid: cid('c'), installation_owner_cid: expectedOwnerCid}];
  const selectionWire = valueJson(selections, {dataKeys: true});
  const runDefinition = {identity: cid('2'),
    wire: JSON.stringify({effect_target_selections_cid: updateTargetSelectionsCid(selections)})};
  const preparedWire = valueJson({original: 'concrete program and environment', selectionWire});
  const materialsWire = valueJson({version: 'actql-remote-run-materials/0.1',
    prepared_invocation: 'prepared invocation', run_authorization: 'authorization',
    effect_target_selections_json: selectionWire});
  const moon = {
    ...dataPorts,
    clientProgramEffectTargetSelectionOriginal(value) {
      return this.clientProgramEffectTargetSelections(value) === undefined ? [] : [originalSelection];
    },
    clientProgramEffectTargetSelectionMatchesPrepared(original, value) {
      return original === originalSelection && value === prepared;
    },
    clientProgramEffectTargetSelectionWire(original) {
      assert.equal(original, originalSelection); return selectionWire;
    },
    clientProgramEffectTargetSelectionCid(original) {
      assert.equal(original, originalSelection); return updateTargetSelectionsCid(selections);
    },
    clientProgramEffectTargetSelectionMatchesRun(original, value, run) {
      return original === originalSelection && value === prepared && run === definition;
    },
    clientProgramEffectTargetSelectionCurrent(original, value, wire) {
      if (original !== originalSelection || value !== prepared) return false;
      assert.deepEqual(JSON.parse(wire), [{installation: originalInstallation,
        update: true, mappings: [{target: 'connector://crm/account',
          mappingRef: 'mapping:crm.account', mappingCid: cid('a'), update: true}]}]);
      return true;
    },
    clientProgramEffectTargetSelectionMembersCurrent(original, value, wire) {
      if (original !== originalSelection || value !== prepared) return false;
      assert.deepEqual(JSON.parse(wire), selections.map(({stage_index, effect_id,
        target_ref, mapping_ref, mapping_cid}) =>
      ({stage_index, effect_id, target_ref, mapping_ref, mapping_cid})));
      return true;
    },
    strategyRemoteManagedOutputEvidenceKind: () => 'test-unused-kind',
    strategyPublicationContractJson: () => runDefinition.wire,
    clientRequestAuthorityScopeCid: () => cid('3'),
    clientRequestCallerId: () => 'request',
    clientProgramEffectAcquisitionCount: () => 0,
    clientProgramEffectInferOccurrence: () => undefined,
    clientProgramEffectTargetSelections(value) { return value === prepared ? selectionWire : undefined; },
    clientProgramEffectCompilationCompiledPlanWire(value) { assert.equal(value, compilation); return 'compiled'; },
    clientProgramIssueEffectPreparedOriginal(value) { assert.equal(value, compilation); return ok(preparedWire); },
    clientProgramAdmitEffectPreparedOriginal(wire, expected) {
      calls.push('restore-prepared');
      assert.equal(wire, preparedWire); assert.equal(expected, cid('1')); return ok({prepared, compilation});
    },
    clientProgramEffectPreparedOriginalPrepared: value => value.prepared,
    clientProgramEffectPreparedOriginalCompilation: value => value.compilation,
    clientProgramIssuePreparedEffectRunMaterials(a, d, identity) {
      assert.equal(a, allowed); assert.equal(d, definition); assert.equal(identity, 'request');
      return ok(materialsWire);
    },
    clientProgramAdmitEffectRunMaterials(wire, expected, ...features) {
      calls.push('bind-exact-run');
      assert.equal(wire, materialsWire); assert.equal(expected, cid('2'));
      assert.equal(features.at(-1), 'request'); return ok({prepared, compilation, allowed, definition});
    },
    clientProgramAdmitEffectRunMaterialsWithCompilation(wire, expected, originalCompilation, request) {
      calls.push('bind-exact-run');
      assert.equal(wire, materialsWire); assert.equal(expected, cid('2'));
      assert.strictEqual(originalCompilation, compilation); assert.equal(request, 'request');
      return ok({prepared, compilation, allowed, definition});
    },
    clientProgramEffectRunMaterialsPrepared: value => value.prepared,
    clientProgramEffectRunMaterialsCompilation: value => value.compilation,
    clientProgramEffectRunMaterialsAllowed: value => value.allowed,
    clientProgramEffectRunMaterialsDefinition: value => value.definition,
    clientProgramEffectRunMaterialsTargetSelections() {
      assert.equal(calls.at(-1), 'bind-exact-run'); calls.push('read-selections'); return ok(selectionWire);
    },
    clientProgramPrepareSourceComputationWithParameters() { assert.fail('Restart must never resolve aliases'); },
  };
  const unavailable = () => assert.fail('Original projection must not perform provider I/O');
  const installedEffect = await createInstalledRowEffect({moon, environmentWire: '{}',
    connectorId: 'crm', connectorRegistration: 'update_target_fixture',
    connectorRevision: 'update_target_fixture/0.1', connection: 'fixture',
    runtimeBundleCid: cid('d'), bindingCid: cid('c'), continuationBinding: cid('e'),
    ledgerRoot: root,
    mappings: [{resource: 'account', mappingRef: 'mapping:crm.account', mappingCid: cid('a'),
      body: JSON.stringify({mapping_contract_cid: cid('a'), target_ref: 'connector://crm/account',
        minimum_approval: 'required', permission_rules: [{effect_kind: 'update'}]})}],
    site: {issueReadGrant: unavailable, issueEffectGrant: unavailable, close() {}},
    authorization: {authorize: unavailable}, driver: {kinds: ['update'],
      prepareRequest: unavailable, requestFacts: unavailable, writeOperation: unavailable,
      send: unavailable, project: unavailable, footprint: unavailable,
      targetRead: {operation: 'read'}, observeTargets: unavailable,
      recoveryEntry: unavailable, recoverRequests: unavailable, requestCid: unavailable},
  });
  originalInstallation = installedRowEffectOwnerBinding(installedEffect);
  assert.equal(originalInstallation.cid, expectedOwnerCid);
  const control = {admit(kind, wire) {
    assert.equal(kind, 'compiled_plan'); assert.equal(wire, 'compiled'); return {identity: cid('1')};
  }};
  const originals = installUpdateTargetOriginals({moon, control, installedEffect, limits});
  return {prepared, compilation, allowed, definition, calls, originals, materialsWire,
    selectionWire, selections: originals.selectionsOf(prepared), installedEffect, moon, control, runDefinition};
}

test('prepared and Run original projections fund their actual material before DATA conversion', async t => {
  const f = await fixture(t), projected = [];
  const reserve = (prepared, material, installations) => {
    assert.strictEqual(prepared, f.prepared);
    assert.equal(installations.length, 1);
    assert.equal(installations[0].cid, expectedOwnerCid);
    projected.push(material);
  };
  const original = f.originals.capturePrepared(f.prepared, f.compilation, reserve);
  assert.deepEqual(projected, [original.preparedWire]);
  f.originals.captureRun({...f, identity: 'request'}, reserve);
  assert.deepEqual(projected, [original.preparedWire, f.materialsWire]);
  const refused = new Error('SameRequestCapacityRefused');
  assert.throws(() => f.originals.capturePrepared(f.prepared, f.compilation,
    () => {throw refused;}), error => error === refused);
  assert.throws(() => f.originals.captureRun({...f, identity: 'request'},
    () => {throw refused;}), error => error === refused);
  assert.equal(f.originals.restorePrepared(original).prepared, f.prepared);
});

test('held originals restore concrete selection without invoking a source resolver', async t => {
  const f = await fixture(t);
  const original = f.originals.capturePrepared(f.prepared, f.compilation);
  assert.equal(updateTargetPreparedOriginalShape(original), true);
  const restored = f.originals.restorePrepared(original);
  assert.equal(restored.prepared, f.prepared);
  assert.equal(f.originals.compilationFor(restored.prepared), f.compilation);
  restored.assertUpdateSelectionCurrent();
  assert.deepEqual(f.calls, ['restore-prepared']);
});

test('accepted original binds the independently selected Run before exposing selection', async t => {
  const f = await fixture(t);
  const original = f.originals.captureRun({...f, identity: 'request'});
  const evidence = {prepared: 'prepared invocation', authorization: 'authorization',
    updateTargetRunOriginal: original};
  assert.equal(updateTargetRunOriginalShape(original, evidence), true);
  const restored = f.originals.validateRun({...f, evidence,
    runDefinition: f.runDefinition, identity: 'request'});
  restored.assertUpdateSelectionCurrent();
  assert.deepEqual(f.calls, ['bind-exact-run', 'read-selections']);
  assert.throws(() => f.originals.restoreRun(original, {...f.runDefinition, identity: cid('3')}, 'request'));
});

test('stripped or substituted originals never downgrade a selected Run to legacy', async t => {
  const f = await fixture(t);
  const original = f.originals.captureRun({...f, identity: 'request'});
  const runDefinition = f.runDefinition;
  assert.throws(() => f.originals.validateRun({...f, evidence: {}, runDefinition, identity: 'request'}));
  const body = JSON.parse(original.materialsWire);
  delete body.effect_target_selections_json;
  assert.equal(updateTargetRunOriginalShape({...original, materialsWire: valueJson(body)}), false);
  assert.throws(() => f.originals.restoreRun({...original, installations: []}, runDefinition, 'request'));
  assert.throws(() => f.originals.restoreRun({...original, installations: [{...original.installations[0],
    cid: cid('f')}]}, runDefinition, 'request'));
  assert.throws(() => f.originals.validateRun({...f, prepared: {}, evidence: {
    updateTargetRunOriginal: original}, runDefinition, identity: 'request'}));
});

test('missing context preserves legacy omission without source or owner work', async t => {
  const f = await fixture(t);
  assert.equal(f.originals.capturePrepared({}, {}), undefined);
  assert.equal(f.originals.captureRun({prepared: {}}), undefined);
  assert.deepEqual(f.originals.validateRun({prepared: {}, evidence: {}, runDefinition: {wire: '{}'}}), {});
  assert.deepEqual(f.calls, []);
});

test('original aggregate wire bounds reject multiplication and escape expansion before serialization', async t => {
  const f = await fixture(t);
  const original = f.originals.captureRun({...f, identity: 'request'});
  assert.equal(updateTargetRunOriginalShape({...original,
    materialsWire: 'x'.repeat(65_536)}), false);
  assert.equal(updateTargetRunOriginalShape({...original,
    materialsWire: '\\'.repeat(40_000)}), false);
  assert.equal(updateTargetRunOriginalShape({...original,
    installations: Array(1024).fill(original.installations[0])}), false);
});

test('selected recovery refuses an omitted or asynchronous live fence before Ledger or provider work', async t => {
  const f = await fixture(t);
  const selection = f.selections[0];
  const installation = JSON.parse(installedRowEffectOwnerBinding(f.installedEffect).wire);
  const provider = {version: 'actql-installed-row-effect-continuation/0.1',
    binding_cid: cid('e'), program_id: 'program', stage_id: 'stage', stage_index: 0,
    members: [{effect_id: selection.effect_id, mapping_cid: selection.mapping_cid,
      installation}]};
  const body = {invocation_cid: cid('9'), effects: [{effect_id: selection.effect_id,
    effect_kind: 'update', target: selection.target_ref, mapping: selection.mapping_ref,
    resolved_mapping_contract_cid: selection.mapping_cid}]};
  const facts = {moon: f.moon, recovered: {computation: {preview: {}}},
    continuation: provider, updateTargetSelections: f.selections,
    control: {effectComputationPreviewWire: () => JSON.stringify(body)}};
  for (const assertion of [undefined, null, async () => {},
    () => Promise.reject(new Error('async fence is not authority'))]) {
    assert.throws(() => f.installedEffect.prepareRecovered({...facts,
      ...(assertion === undefined ? {} : {assertUpdateSelectionCurrent: assertion})}),
    {code: 'InstalledRowEffectInstallationChanged'});
  }
  assert.deepEqual(f.calls, []);
});

test('selected Source originals use existing custody without rejecting acquisition', async t => {
  const f = await fixture(t);
  f.moon.clientProgramEffectAcquisitionCount = () => {
    assert.fail('Original custody must not restrict independent Source acquisition');
  };
  const original = f.originals.capturePrepared(f.prepared, f.compilation);
  assert.equal(updateTargetPreparedOriginalShape(original), true);
  assert.equal(f.originals.restorePrepared(original).prepared, f.prepared);
  assert.deepEqual(f.calls, ['restore-prepared']);
});

test('selected Model custody projects the original compilation without selecting another profile', async t => {
  const f = await fixture(t);
  f.moon.clientProgramEffectInferOccurrence = () => {
    assert.fail('Original custody must not derive a replacement Model occurrence');
  };
  const original = f.originals.capturePrepared(f.prepared, f.compilation);
  const restored = f.originals.restorePrepared(original);
  assert.equal(restored.prepared, f.prepared);
  assert.equal(restored.compilation, f.compilation);
  assert.equal(f.originals.compilationFor(restored.prepared), f.compilation);
  assert.deepEqual(f.calls, ['restore-prepared']);
});


test('marked recovery requires synchronous original custody and exact selection before capture Store reads', async t => {
  const f = await fixture(t);
  let reads = 0;
  const options = {requests: {lookupOwnedDefinition: () => ({runDefinition: f.runDefinition,
    requestIdentity: 'request'})}, store: {storeAuthorityCid: cid('4'),
    inspectPhysicalHolding() { reads++; assert.fail('No capture read before original custody'); }},
  key: {namespaceId: 'local', authorityScopeCid: cid('3'), requestId: 'request',
    runDefinitionCid: cid('2')}, principalId: 'fixture', authorizeEvidenceRead: () => true,
  contractLimits: limits};
  for (const restoreOriginal of [undefined, async () => ({}), () => ({}),
    () => ({updateTargetSelections: f.selections}),
    () => ({updateTargetSelections: f.selections, assertUpdateSelectionCurrent: async () => {}}),
    () => ({updateTargetSelections: f.selections.map(value => ({...value, mapping_cid: cid('f')})),
      assertUpdateSelectionCurrent() {}})]) {
    await assert.rejects(recoverAdmittedEffectRun({...options,
      ...(restoreOriginal === undefined ? {} : {restoreOriginal})}, async () => f.moon),
    {code: 'EffectRecoveryOriginalSelectionUnavailable'});
  }
  assert.equal(reads, 0);
});
