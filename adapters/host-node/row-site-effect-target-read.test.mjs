// Actual credential grant/signature/SQLite Site with explicit Checkpoint ports.
// No account permission, Provider operation, public Effect or numerical funding
// is inferred from these nominal-lifetime and request-boundary controls.
import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import test from 'node:test';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {recordCheckpointApproval} from '../host-common/checkpoint-approval.mjs';
import {effectTargetReadContinuation} from './effect-target-read-continuation.mjs';
import {openSqliteCredentialJournal} from '../site-node/sqlite-credential-journal.mjs';
import {openRowSourceCredentialSite} from './installed-row-source.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const connection = 'gcs:project/bucket', resource = 'objects', operation = 'gcs:file:read';
const tuple = Object.freeze({connection, resource, operation: 'read'});
const physical = Object.freeze({version: 'fixture-original-effect-read/0.1',
  site_binding_cid: cid('1'), resource, command: 'command:storage.gcs.upload.v1',
  name: 'in/e\u0301%2F.csv'});
const failure = {code: 'RowSourceEffectTargetReadApprovalNotAdmitted'};

async function fixture(t, {hook, journalFailure = false, admitsSource = () => false} = {}) {
  const scratch = await createOwnedScratch({parent: new URL('../../_build/', import.meta.url).pathname,
    prefix: 'row-site-effect-read-', label: 'Row Site original Effect read control'});
  const keys = generateKeyPairSync('ed25519'), key = join(scratch.path, 'credential.key');
  await writeFile(key, keys.privateKey.export({type: 'pkcs8', format: 'pem'}), {mode: 0o600});
  const state = {grants: 0, secrets: 0, current: 0, enter: 0, live: true,
    bindingLive: true, journalFailure, closes: 0};
  const options = {profile: {credentialPrivateKeyPath: key, credentialAuthorityId: 'test-authority',
    credentialKeyId: 'test-key', journalRoot: join(scratch.path, 'journal'),
    resourceOrigin: 'https://storage.googleapis.com', namespaceId: 'namespace',
    environment: 'test', siteKey: 'site', siteGeneration: 1},
    principalId: 'principal', authorization: {issued: () => false,
      configurationCid: cid('a'), context: {contextCid: cid('b')}},
    connection, connectorRegistration: 'gcs', connectorRevision: 'gcs/0.1',
    runtimeBundleCid: cid('c'), commonMoon: moon,
    resolveSecret: async () => { state.secrets++; assert.fail('No credential material or HTTP'); },
    admitsApprovalTarget: admitsSource,
    admitsEffectTargetRead: hook ?? ((binding, selected, selectedOperation) =>
      state.bindingLive && selected === resource && selectedOperation === operation &&
      JSON.stringify(binding) === JSON.stringify(physical)),
    openCredentialJournal(root, config) {
      const journal = openSqliteCredentialJournal(root, config);
      return Object.freeze({...journal,
        acceptGrant(...args) { state.grants++; return journal.acceptGrant(...args); },
        close() {
          state.closes++;
          if (state.journalFailure) throw Object.assign(new Error('original journal close'), {code: 'TestJournalClose'});
          return journal.close();
        }});
    }};
  const site = await openRowSourceCredentialSite(options);
  let closed = false;
  const close = () => { if (!closed) { site.close(); closed = true; } };
  t.after(async () => {
    state.journalFailure = false;
    close();
    await scratch.cleanup();
  });
  const facts = {kind: 'effect_target', principalId: 'principal',
    configurationCid: cid('a'), contextCid: cid('b'), runDefinitionCid: cid('d'),
    readTuple: tuple, physicalBindings: [physical],
    assertCurrent() { state.current++; if (!state.live) throw Object.assign(new Error('original changed'), {code: 'OriginalChanged'}); },
    enter() { state.enter++; }};
  const issue = (changed = {}, decision = {}) => recordCheckpointApproval(Object.freeze({
    action: 'dispatch', basis: 'resumed_approval', boundary: 'acquisition', tuple,
    ...decision}), {...facts, ...changed});
  const grant = (decision, changed = {}) => site.issueReadGrant({operation, decision, resource,
    runInvocationCid: cid('e'), dispatchRequestCid: cid('f'), maxUses: 1, ...changed});
  return {site, state, options, issue, facts, grant, close};
}

test('same Site admits the original target decision and signs only its exact read operation', async t => {
  const f = await fixture(t), original = f.issue();
  assert.equal(f.site.admitCheckpointEffectTargetRead(original, physical, operation), original);
  assert.equal(f.state.grants, 0); assert.equal(f.state.enter, 0);
  const grant = f.grant(original);
  assert.equal(grant.scope.operation, operation);
  assert.equal(grant.scope.runInvocationCid, cid('e'));
  assert.equal(grant.scope.dispatchRequestCid, cid('f'));
  assert.equal(f.state.grants, 1); assert.equal(f.state.enter, 1);
  assert.equal(f.state.secrets, 0);
  assert.throws(() => f.grant(Object.freeze({...original})), {code: 'RowSourceGrantNotAuthorized'});
  assert.throws(() => f.grant(original, {operation: 'gcs:object:upload'}), {code: 'RowSourceGrantNotAuthorized'});
  assert.throws(() => f.grant(original, {resource: 'foreign'}), {code: 'RowSourceGrantNotAuthorized'});
  assert.throws(() => f.site.issueEffectGrant({operation: 'gcs:object:upload', decision: original,
    resource, runInvocationCid: cid('e'), dispatchRequestCid: cid('f'), subjectCid: cid('1')}),
  {code: 'RowSourceGrantNotAuthorized'});
  assert.equal(f.state.grants, 1);
});

test('missing target supplier refuses and malformed supplier fails before journal opening', async t => {
  const f = await fixture(t); f.close();
  let opens = 0;
  for (const supplied of [null, false, {}]) {
    await assert.rejects(openRowSourceCredentialSite({...f.options,
      admitsEffectTargetRead: supplied, openCredentialJournal() { opens++; assert.fail('No journal acquisition'); }}),
    {code: 'InvalidRowSourceCredentialSite'});
  }
  assert.equal(opens, 0);
  const site = await openRowSourceCredentialSite({...f.options, admitsEffectTargetRead: undefined});
  t.after(() => site.close());
  assert.throws(() => site.admitCheckpointEffectTargetRead(f.issue(), physical, operation), failure);
  assert.equal(f.state.grants, 0);
});

test('legacy Source approval remains separate from an Effect target approval', async t => {
  const f = await fixture(t, {admitsSource: (binding, selected) => binding === physical && selected === resource});
  const original = f.issue({kind: 'source', physicalBinding: physical});
  assert.equal(f.site.admitCheckpointReadApproval(original), original);
  f.grant(original);
  assert.equal(f.state.grants, 1); assert.equal(f.state.enter, 0);
  assert.throws(() => f.site.admitCheckpointEffectTargetRead(original, physical, operation), failure);
  assert.throws(() => f.site.admitCheckpointReadApproval(f.issue()), {code: 'RowSourceReadApprovalNotAdmitted'});
});

test('a target approval cannot be re-admitted through the Source port to lose its operation fence', async t => {
  const f = await fixture(t, {admitsSource: (binding, selected) => binding === physical && selected === resource});
  const original = f.issue({physicalBinding: physical});
  f.site.admitCheckpointEffectTargetRead(original, physical, operation);
  assert.throws(() => f.site.admitCheckpointReadApproval(original), {code: 'RowSourceReadApprovalNotAdmitted'});
  assert.throws(() => f.grant(original, {operation: 'gcs:object:upload'}), {code: 'RowSourceGrantNotAuthorized'});
  assert.equal(f.state.grants, 0);
});

test('an asynchronous binding predicate never authorizes a target read', async t => {
  const f = await fixture(t, {hook: () => Promise.resolve(true)});
  assert.throws(() => f.site.admitCheckpointEffectTargetRead(f.issue(), physical, operation), failure);
  assert.equal(f.state.grants, 0); assert.equal(f.state.enter, 0);
});

for (const [name, changed, decision] of [
  ['foreign principal', {principalId: 'other'}],
  ['foreign configuration', {configurationCid: cid('1')}],
  ['foreign context', {contextCid: cid('2')}],
  ['non-target facts', {kind: 'source'}],
  ['missing binding', {physicalBindings: []}],
  ['normalized path', {physicalBindings: [{...physical, name: 'in/é%2F.csv'}]}],
  ['foreign tuple', {readTuple: {...tuple, connection: 'other'}}],
  ['wrong decision operation', {}, {tuple: {...tuple, operation: 'effect'}}],
  ['held decision', {}, {action: 'hold'}],
  ['missing current', {assertCurrent: undefined}],
  ['missing entry', {enter: undefined}],
]) {
  test(`Site target read refuses ${name} before entry or grant`, async t => {
    const f = await fixture(t);
    assert.throws(() => f.site.admitCheckpointEffectTargetRead(f.issue(changed, decision), physical, operation), failure);
    assert.equal(f.state.enter, 0); assert.equal(f.state.grants, 0); assert.equal(f.state.secrets, 0);
  });
}

for (const [name, invalidate] of [
  ['original current', f => { f.state.live = false; }],
  ['installation binding', f => { f.state.bindingLive = false; }],
]) {
  test(`same nominal approval rechecks ${name} before entering or signing`, async t => {
    const f = await fixture(t), original = f.issue();
    f.site.admitCheckpointEffectTargetRead(original, physical, operation);
    invalidate(f);
    assert.throws(() => f.grant(original));
    assert.equal(f.state.enter, 0); assert.equal(f.state.grants, 0);
  });
}

test('mutable physical binding cannot retarget an already admitted decision', async t => {
  const f = await fixture(t), binding = {...physical};
  const original = f.issue({physicalBindings: [binding]});
  f.site.admitCheckpointEffectTargetRead(original, binding, operation);
  binding.name = 'in/other.csv';
  assert.throws(() => f.grant(original), failure);
  assert.equal(f.state.grants, 0); assert.equal(f.state.enter, 0);
});

test('malformed grant arguments do not consume the original entry', async t => {
  const f = await fixture(t), original = f.issue();
  f.site.admitCheckpointEffectTargetRead(original, physical, operation);
  for (const changed of [{runInvocationCid: 'bad'}, {dispatchRequestCid: 'bad'}, {maxUses: 0}]) {
    assert.throws(() => f.grant(original, changed), {code: 'InvalidRowSourceGrantRequest'});
  }
  assert.equal(f.state.enter, 0); assert.equal(f.state.grants, 0);
  f.grant(original);
  assert.equal(f.state.enter, 1); assert.equal(f.state.grants, 1);
});

for (const [name, result] of [['false', false], ['resolved', Promise.resolve()],
  ['rejected', Promise.reject(new Error('test async current'))]]) {
  // Observe a deliberately rejected test promise even before its case starts.
  if (typeof result?.then === 'function') void result.catch(() => {});
  test(`async or non-Unit target current refuses before credential issuance (${name})`, async t => {
    const f = await fixture(t);
    assert.throws(() => f.site.admitCheckpointEffectTargetRead(f.issue({assertCurrent: () => result}), physical, operation), failure);
    assert.equal(f.state.grants, 0); assert.equal(f.state.enter, 0);
  });
}

test('entry failure or lifecycle change keeps the original failure and issues no credential', async t => {
  const f = await fixture(t), primary = Object.freeze(new Error('original entry failure'));
  const original = f.issue({enter() { throw primary; }});
  f.site.admitCheckpointEffectTargetRead(original, physical, operation);
  assert.throws(() => f.grant(original), error => error === primary);
  assert.equal(f.state.grants, 0);
  const retired = f.issue({enter() { f.state.live = false; }});
  f.site.admitCheckpointEffectTargetRead(retired, physical, operation);
  assert.throws(() => f.grant(retired), {code: 'OriginalChanged'});
  assert.equal(f.state.grants, 0);
});

test('same Site closing with pending journal cleanup denies all new target reads', async t => {
  const f = await fixture(t), original = f.issue();
  f.site.admitCheckpointEffectTargetRead(original, physical, operation);
  f.state.journalFailure = true;
  assert.throws(f.close, {code: 'TestJournalClose'});
  assert.throws(() => f.grant(original), {code: 'RowSourceSiteClosed'});
  assert.throws(() => f.site.admitCheckpointEffectTargetRead(original, physical, operation), {code: 'RowSourceSiteClosed'});
  assert.equal(f.state.grants, 0);
  f.state.journalFailure = false; f.close();
  assert.equal(f.state.closes, 2);
});

test('actual target continuation decision survives Site admission and retains its original fence', async t => {
  const f = await fixture(t);
  const gate = {scopeCid: cid('1'), configurationCid: cid('a'), contextCid: cid('b'),
    assertCurrent: f.facts.assertCurrent,
    async authorize() { return {action: 'dispatch', basis: 'account_allow'}; },
    async current() { return {action: 'dispatch', basis: 'account_allow'}; }, close() {}};
  const continuation = await effectTargetReadContinuation({
    checkpoints: {journal: {committedApprovalAt() { assert.fail('No resolved Checkpoint'); }},
      async inspectEffectTargetApprovals() { return []; }, async effectTargetAuthorization() { return gate; }},
    runId: 'original-run', runDefinitionCid: cid('d'), unitId: 'unit', declaredResults: [],
    submission: {original: 'submission'}, principalId: 'principal',
    inventory: [{readTuple: tuple, physicalBinding: physical}], assertCurrent: f.facts.assertCurrent,
    assertOriginalCurrent: f.facts.assertCurrent});
  t.after(() => continuation.close());
  assert.deepEqual(await continuation.prepare(), {status: 'ready'});
  const original = await continuation.authorize(tuple);
  assert.equal(f.site.admitCheckpointEffectTargetRead(original, physical, operation), original);
  f.grant(original); assert.equal(f.state.grants, 1);
  continuation.close();
  assert.throws(() => f.grant(original));
  assert.equal(f.state.grants, 1);
});
