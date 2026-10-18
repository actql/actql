import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {createInstalledRowEffect, composeInstalledRowEffectOwners,
  retainInstalledRowEffectAdapter} from './installed-row-effect.mjs';
import {installedEffectFor} from './installed-effect-inventory.mjs';

// Admission/provenance tests only. Core issuance and physical dispatch are not
// replaced with successful doubles; accepted recovery stops before the Ledger.
const cid = digit => `sha256:${digit.repeat(64)}`;
const profile = Object.freeze({
  continuation: 'actql-installed-row-effect-continuation/0.1',
  continuationBinding: 'binding_cid',
  dispatch: 'actql-installed-row-effect-dispatch/0.1',
  recovery: 'actql-installed-row-effect-recovery/0.1',
  source: 'actql-installed-row-effect-source/0.1',
  targetCheck: 'actql-installed-row-effect-check/0.1',
  unit: 'actql-installed-row-effect-unit/0.1',
});
const program = {stages: [{inputs: {}, steps: [{values: {}, as: 'rows'}]}]};
async function fixture(t, variants = [{}, {}]) {
  const root = await mkdtemp(join(tmpdir(), 'actql-row-routing-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const calls = [];
  const unused = action => () => { calls.push(action); assert.fail(action); };
  const moon = {strategyRemoteManagedOutputEvidenceKind: () => 'test-unused-kind',
    clientProgramEffectCompilationPlanWire: compilation =>
    JSON.stringify({execution_material: {program: compilation}})};
  const effects = [], descriptors = [], installations = [];
  for (const [index, variant] of variants.entries()) {
    const name = `owner-${index}`;
    const identity = cid(String(index + 1));
    const mappingRef = `mapping:${name}/create.v1`;
    const target = `connector://${name}/records`;
    const descriptor = {effectId: `effect-${index}`, kind: 'create', target,
      mappingRef, mappingCid: identity};
    const options = {moon, mappings: [{resource: 'records', mappingRef,
      mappingCid: identity, body: JSON.stringify({mapping_contract_cid: identity,
        target_ref: target, minimum_approval: 'required', permission_rules: [
          {effect_kind: 'create', permissions: ['write']}], primary_identity: ['id']})}],
    environmentWire: '{}', connectorId: name, connectorRegistration: name,
    connectorRevision: `${name}/0.1`, connection: name,
    site: {issueEffectGrant: unused('grant'), issueReadGrant: unused('read grant'),
      close() { calls.push(`close:${name}`); }},
    authorization: {authorize: unused('authorize')}, runtimeBundleCid: cid('a'),
    bindingCid: identity, ledgerRoot: root,
    driver: {kinds: ['create'], prepareRequest: unused('request'),
      requestFacts: unused('facts'), writeOperation: unused('operation'),
      send: unused('send'), project: unused('project'), footprint: unused('footprint'),
      ...variant.driverExtra},
    ...variant};
    effects.push(await createInstalledRowEffect(options));
    descriptors.push(descriptor);
    installations.push({connector_registration: options.connectorRegistration,
      connector_revision: options.connectorRevision, runtime_bundle_cid: options.runtimeBundleCid,
      binding_cid: options.bindingCid, connection: options.connection,
      profile, continuation_binding: options.bindingCid});
  }
  return {moon, effects, descriptors, installations, calls, root};
}

test('composed route retains real owner ports without acquiring a provider', async t => {
  const f = await fixture(t);
  const routed = composeInstalledRowEffectOwners(f.effects, f.descriptors, '{}');
  const inventory = {effects: f.effects, environmentWire: '{}'};
  installedEffectFor(inventory, f.descriptors).assertPrepared({moon: f.moon, compilation: program});
  for (const fault of [{mappingCid: cid('f')}, {target: 'foreign'},
    {capabilityCid: cid('f')}, {kind: 'update'}]) {
    assert.throws(() => installedEffectFor(inventory,
      [f.descriptors[0], {...f.descriptors[1], ...fault}]),
    {code: 'InstalledEffectProgramMismatch'});
  }
  assert.throws(() => installedEffectFor({effects: [...f.effects, f.effects[0]]}, f.descriptors),
    {code: 'InstalledEffectProgramMismatch'});
  assert.ok(Object.isFrozen(routed));
  assert.equal(routed.close, undefined, 'installation cleanup stays with original inventory');
  routed.assertPrepared({moon: f.moon, compilation: program});
  assert.deepEqual(f.calls, []);
  await f.effects[0].close();
  assert.deepEqual(f.calls, ['close:owner-0']);
  await f.effects[1].close();
  assert.deepEqual(f.calls, ['close:owner-0', 'close:owner-1']);
});

test('copied adapters cannot supply a routing port; exact loader projection retains it', async t => {
  const f = await fixture(t);
  const copy = Object.freeze({...f.effects[0]});
  assert.throws(() => composeInstalledRowEffectOwners([copy, f.effects[1]], f.descriptors, '{}'),
    {code: 'InstalledEffectSetOwnerMismatch'});
  assert.throws(() => retainInstalledRowEffectAdapter(f.effects[0],
    {...copy, prepareRecovered() {}}), {code: 'ForeignInstalledEffectOccurrence'});
  assert.equal(retainInstalledRowEffectAdapter(f.effects[0], copy), copy);
  composeInstalledRowEffectOwners([copy, f.effects[1]], f.descriptors, '{}')
    .assertPrepared({moon: f.moon, compilation: program});
  assert.deepEqual(f.calls, []);
});

test('unsupported mixed kinds and foreign ports refuse before provider work', async t => {
  const f = await fixture(t);
  for (const kind of ['store', 'update', 'upsert', 'command']) {
    assert.throws(() => composeInstalledRowEffectOwners(f.effects,
      [{...f.descriptors[0], kind}, f.descriptors[1]], '{}'),
    {code: 'InstalledEffectSetOwnerMismatch'});
  }
  assert.throws(() => composeInstalledRowEffectOwners([{}, f.effects[1]], f.descriptors, '{}'),
    {code: 'InstalledEffectSetOwnerMismatch'});
  assert.deepEqual(f.calls, []);
});

test('composed profile refuses imported, multi-stage and non-VALUES computation before dispatch', async t => {
  const f = await fixture(t);
  const routed = composeInstalledRowEffectOwners(f.effects, f.descriptors, '{}');
  for (const compilation of [undefined, {stages: []}, {stages: [program.stages[0], program.stages[0]]},
    {stages: [{inputs: {source: {}}, steps: program.stages[0].steps}]},
    {stages: [{inputs: {}, steps: [{infer: {}}]}]},
    {stages: [{inputs: {}, steps: [{filter: {}}]}]}]) {
    assert.throws(() => routed.assertPrepared({moon: f.moon, compilation}),
      {code: 'InstalledEffectSetOwnerMismatch'});
  }
  assert.throws(() => routed.assertPrepared({moon: {}, compilation: program}),
    {code: 'InstalledEffectSetOwnerMismatch'});
  assert.deepEqual(f.calls, []);
});

test('composed stage refuses unequal original runtime, Ledger location and limits', async t => {
  for (const variant of [{moon: {strategyRemoteManagedOutputEvidenceKind: () => 'test-unused-kind'}},
    {ledgerRoot: join(tmpdir(), 'foreign-ledger')},
    {limits: {maxRows: 201}}]) {
    const f = await fixture(t, [{}, variant]);
    assert.throws(() => composeInstalledRowEffectOwners(f.effects, f.descriptors, '{}'),
      {code: 'InstalledEffectSetOwnerMismatch'});
    assert.deepEqual(f.calls, []);
  }
});

test('recovery validates each original occurrence and installation before opening the Ledger', async t => {
  const limits = {key: {maxBytes: 4096, maxNodes: 64, maxDepth: 8}};
  const f = await fixture(t, [{limits}, {limits}]);
  const routed = composeInstalledRowEffectOwners(f.effects, f.descriptors, '{}');
  limits.key.maxBytes = 1;
  const invocation = cid('c');
  const body = {invocation_cid: invocation, effects: f.descriptors.map(d => ({
    effect_id: d.effectId, effect_kind: d.kind, target: d.target,
    mapping: d.mappingRef, resolved_mapping_contract_cid: d.mappingCid}))};
  const provider = {version: 'actql-installed-row-effect-routing/0.1',
    program_id: 'program', stage_id: 'stage', members: f.descriptors.map((d, i) => ({
      effect_id: d.effectId, mapping_cid: d.mappingCid,
      dispatch_request_cid: `sha256:${createHash('sha256').update(JSON.stringify({
        effect_id: d.effectId, run_invocation_cid: invocation,
        version: 'actql-installed-row-effect-dispatch/0.1'})).digest('hex')}`,
      installation: f.installations[i]}))};
  const stopped = new Error('StopBeforeLedger');
  const keyCalls = [];
  f.moon.strategyEffectRecoveredPreviewKeys = (...args) => { keyCalls.push(args); throw stopped; };
  const facts = {moon: f.moon, recovered: {computation: {preview: {}}},
    continuation: provider, control: {effectComputationPreviewWire: () => JSON.stringify(body),
      effectComputationPreviewLedgerIdentity: () => ({})}};
  assert.throws(() => routed.prepareRecovered(facts), error => error === stopped);
  assert.equal(keyCalls[0][5], 4096, 'original composed limits cannot change with bootstrap objects');
  for (const field of ['connector_registration', 'connector_revision', 'runtime_bundle_cid',
    'binding_cid', 'connection', 'continuation_binding']) {
    const changed = structuredClone(provider);
    changed.members[1].installation[field] = 'foreign';
    assert.throws(() => routed.prepareRecovered({...facts, continuation: changed}),
      {code: 'InstalledRowEffectInstallationChanged'});
  }
  const swapped = structuredClone(provider);
  swapped.members.reverse();
  assert.throws(() => routed.prepareRecovered({...facts, continuation: swapped}),
    {code: 'InstalledRowEffectInstallationChanged'});
  const changedTarget = structuredClone(body);
  changedTarget.effects[1].target = body.effects[0].target;
  assert.throws(() => routed.prepareRecovered({...facts, control: {
    ...facts.control, effectComputationPreviewWire: () => JSON.stringify(changedTarget)}}),
  {code: 'InstalledEffectProgramMismatch'});
  assert.deepEqual(f.calls, []);
});


test('retained-request composition requires an explicit member-scoped recovery port', async t => {
  const retained = {recoverRequests() { assert.fail('recovery before admission'); },
    recoveryEntry() { assert.fail('capture before admission'); },
    requestCid() { assert.fail('request before admission'); }};
  const unsupported = await fixture(t, [{driverExtra: retained}, {}]);
  assert.throws(() => composeInstalledRowEffectOwners(unsupported.effects,
    unsupported.descriptors, '{}'), {code: 'InstalledEffectSetOwnerMismatch'});
  assert.deepEqual(unsupported.calls, []);
  const scoped = await fixture(t, [{driverExtra: {...retained,
    recoverMemberRequests() { assert.fail('recovery before capture'); }}}, {}]);
  const stage = composeInstalledRowEffectOwners(scoped.effects, scoped.descriptors, '{}');
  stage.assertPrepared({moon: scoped.moon, compilation: program});
  assert.deepEqual(scoped.calls, []);
});

test('member-scoped recovery cannot be installed without the existing retained recovery protocol', async t => {
  await assert.rejects(fixture(t, [{driverExtra: {
    recoverMemberRequests() { assert.fail('uninstalled recovery'); }}}, {}]),
  {code: 'InvalidInstalledRowEffectDriver'});
});
