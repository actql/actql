// Fixture contract and TLS transport components only. Client doubles prove
// oracle/phase ordering; synthetic TLS requests prove the fixture socket point.
// Neither establishes actual Host authentication, Run/Unknown or ordinary acceptance.
import assert from 'node:assert/strict';
import test from 'node:test';
import {copyFile, mkdir, mkdtemp, open, readFile, realpath, rm, stat, writeFile, unlink} from 'node:fs/promises';
import {generateKeyPairSync, verify} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {request as requestHttps} from 'node:https';
import {openRecordApprovalExchange, installedRecordReplyLossExpectation,
  assertRecordApprovalTarget} from './fixtures/record-approval/installed.fixture.mjs';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {pathToFileURL} from 'node:url';
import {salesforceUpdateCase, hubspotUpdateCase, kintoneUpdateCase,
  sharedRecordUpdateSelections, recordUpdateFixtureState, recordUpdateReplyLossFaults} from './fixtures/record-approval/cases.mjs';
import {runRecordUpdateApprovalPhase, recordApprovalReplyLossExpectation} from './fixtures/record-approval/workflow.mjs';
import {runRecordApprovalCommand} from './fixtures/record-approval/command.mjs';
import {hubspotApprovalProvider} from './fixtures/hubspot-approval/provider.mjs';
import {kintoneApprovalProvider} from './fixtures/kintone-approval/provider.mjs';
import {recordApprovalHostAccountConfiguration} from './fixtures/record-approval/host-account.fixture.mjs';
import {observeRecordApprovalDescriptors, recordApprovalScopedPaths} from './fixtures/record-approval/scoped-fds.fixture.mjs';
import {mockProjectFiles as salesforceMock} from './fixtures/salesforce-approval/mock-project.mjs';
import {mockProjectFiles as hubspotMock} from './fixtures/hubspot-approval/mock-project.mjs';
import {runSalesforceApprovalPhase} from './fixtures/salesforce-approval/workflow.mjs';
import {runHubSpotApprovalPhase} from './fixtures/hubspot-approval/workflow.mjs';
import {mockProjectFiles as kintoneMock} from './fixtures/kintone-approval/mock-project.mjs';
import {runKintoneApprovalPhase} from './fixtures/kintone-approval/workflow.mjs';

const cid = mark => 'sha256:' + mark.repeat(64);
const selection = {recordId: 'record-1', previousName: 'before', nextName: 'after'};

test('record approval descriptor scope includes root, descendants and deleted originals, not siblings', () => {
  assert.deepEqual(recordApprovalScopedPaths(['/tmp/root', '/tmp/root/file', '/tmp/root (deleted)',
    '/tmp/root/file (deleted)', '/tmp/root-other/file', '/tmp/other'], ['/tmp/root']),
  ['/tmp/root', '/tmp/root/file', '/tmp/root (deleted)', '/tmp/root/file (deleted)']);
});

test('record approval descriptor observer sees actual open root and child then their close', async () => {
  const root = await mkdtemp(join(tmpdir(), 'actql-approval-descriptors-'));
  const file = join(root, 'child');
  let directory, child;
  try {
    await writeFile(file, 'synthetic');
    directory = await open(root, 'r'); child = await open(file, 'r');
    const before = await observeRecordApprovalDescriptors([root]);
    assert(before.openPaths.includes(await realpath(root)));
    assert(before.openPaths.includes(await realpath(file)));
    await directory.close(); directory = undefined;
    await child.close(); child = undefined;
    assert.deepEqual((await observeRecordApprovalDescriptors([root])).openPaths, []);
  } finally {
    await directory?.close(); await child?.close(); await rm(root, {recursive: true});
  }
});
async function definition(connector) {
  const files = await Promise.all(['update.aql', 'read.aql'].map(name =>
    readFile(new URL(`./fixtures/${connector}-approval/${name}`, import.meta.url), 'utf8')));
  return ({salesforce: salesforceUpdateCase, hubspot: hubspotUpdateCase, kintone: kintoneUpdateCase}[connector])(
    {update: files[0], read: files[1]}, selection);
}
function publicDouble(value) {
  const events = [], saved = new Map(), ref = {authorityScopeCid: cid('a'), original: 'effect'};
  const summary = {reviewProjectionCid: cid('b'), requiredArtifact: {cid: cid('c')},
    requirements: [{original: 'claim'}], checkpointCid: cid('d')};
  const checkpoint = {id: 'checkpoint', checkpoint_cid: cid('d')};
  const body = {version: 'actql-review-projection/0.1',
    review_projection_cid: cid('b'), effect_preview_cid: cid('c'), authority_scope_cid: cid('a'),
    approval_claims: [{original: 'claim'}], displayed_scope: {
      effects: [{kind: 'update', target: value.review.target, count: 1}]},
    displayed_rows: [{target_row_identity: value.review.identity, preview_strength: 'full_diff',
      row_preview_cid: cid('e'), target_guard: {state: 'version', version_cid: cid('f')},
      before: {state: 'present', value: {...value.review.before, independent_extra_field: 'retained'}},
      intended_changes: {state: 'present', value: {...value.review.changes}},
      after: {state: 'present', value: {...value.review.changes}}}]};
  let approved = false, number = 0;
  const effect = {ref, async wait() {
    events.push('effect:wait');return approved ? {status: 'succeeded', run_id: 'same-run'}
      : {status: 'waiting_checkpoint', run_id: 'same-run', checkpoint};
  }, async status() {
    events.push('effect:status');return approved ? {status: 'succeeded', run_id: 'same-run'}
      : {status: 'waiting_checkpoint', run_id: 'same-run', checkpoint};
  }, result(name) {
    if (name !== value.effect.resultName) {
      assert(Object.hasOwn(value.effect.additionalResults ?? {}, name));
      events.push('effect:result:' + name);
      return {async all() {events.push('effect:rows:' + name);return structuredClone(value.effect.additionalResults[name]);}};
    }
    events.push('effect:result');
    return {async all() {events.push('effect:rows');return structuredClone(value.effect.expectedRows);}};}};
  const client = {async startSource(document, options) {
    if (document === value.effect.document) {
      events.push('submit:effect');assert.equal(options.stopBefore, 'commit');
      assert.deepEqual(options.parameters, value.effect.parameters);return effect;
    }
    assert.equal(document, value.read.document);events.push('submit:read');number++;
    assert.deepEqual(options.parameters, value.read.parameters);
    return {ref: {original: 'read-' + number}, async wait() {events.push('read:wait');return {status: 'succeeded'};},
      result(name) {assert.equal(name, value.read.resultName);return {async all() {
        events.push('read:rows');return structuredClone(approved ? value.read.afterRows : value.read.beforeRows);
      }};}};
  }, async checkpoints(actual) {assert.deepEqual(actual, {checkpointId: 'checkpoint'});return {items: [summary]};},
  async reviewCheckpoint(actual) {assert.deepEqual(actual, summary);events.push('review');return {bytes: Buffer.from(JSON.stringify(body))};},
  async attach(actual) {assert.deepEqual(actual, ref);events.push('attach');return effect;},
  async close() {events.push('close');}};
  return {client, events, saved, body, effect,
    async load(name) {events.push('load:' + name);assert(saved.has(name));return structuredClone(saved.get(name));},
    async save(name, data) {events.push('save:' + name);assert(!saved.has(name));saved.set(name, structuredClone(data));},
    async approve(actual, captured) {assert.strictEqual(actual, client);assert.deepEqual(captured.ref, ref);
      events.push('approve');approved = true;return {results: [{status: 'committed'}]};}};
}
async function phase(which, value, f, changes = {}) {
  return runRecordUpdateApprovalPhase({phase: which, definition: value, ...f, ...changes});
}

test('record rejection resolves the same signed Checkpoint and cold lookup only reads cancelled state', async () => {
  const value = await definition('kintone'), f = publicDouble(value), decision = 'rejected';
  const resolved = {status: 'cancelled', run_id: 'same-run'};
  await phase('capture', value, f, {decision});
  const status = f.effect.status.bind(f.effect);
  f.effect.status = async () => {
    const original = await status();
    return {...original, checkpoint: {...original.checkpoint, checkpoint_cid: cid('7')}};
  };
  const noResolution = () => {throw new Error('An altered original checkpoint must refuse before signing');};
  await assert.rejects(phase('reject', value, f, {decision, reject: noResolution}), {code: 'ERR_ASSERTION'});
  assert.equal(f.events.at(-1), 'close');
  assert.equal(f.saved.has('rejected'), false);

  const original = publicDouble(value);
  original.effect.ref.runDefinitionCid = cid('6');
  let rejectionCalls = 0;
  await phase('capture', value, original, {decision});
  original.effect.wait = async () => {original.events.push('effect:wait');return resolved;};
  original.effect.result = () => assert.fail('A rejected update must not read a Result');
  let cursor = original.events.length;
  await phase('reject', value, original, {decision, async reject(client, captured) {
    rejectionCalls++;
    assert.equal(client, original.client);
    assert.equal(captured.checkpointId, 'checkpoint');
    assert.equal(captured.summary.checkpointCid, cid('d'));
    original.events.push('reject');
    return {results: [{status: 'committed'}], signed: [{resolutionWire: JSON.stringify({
      decision, checkpoint_id: 'checkpoint', checkpoint_cid: cid('d'), run_id: 'same-run',
      run_definition_cid: original.effect.ref.runDefinitionCid,
    })}]};
  }});
  assert.deepEqual(original.events.slice(cursor), ['load:captured', 'attach', 'effect:status',
    'save:reject-status', 'review', 'reject', 'effect:wait', 'save:reject-wait', 'save:rejected', 'close']);
  assert.equal(rejectionCalls, 1);
  assert.equal(original.saved.get('rejected').status, 'cancelled');
  original.effect.status = async () => {original.events.push('effect:status');return resolved;};
  cursor = original.events.length;
  await phase('recover', value, original, {decision, reject: () => assert.fail('Repeated rejection')});
  assert.deepEqual(original.events.slice(cursor), ['load:captured', 'attach', 'load:rejected',
    'effect:status', 'save:reject-lookup', 'close']);
  assert.equal(original.saved.get('reject-lookup').status, 'cancelled');
  assert(!original.saved.has('approved'));
});

test('record wrapper persists original primary before pending first close and never replaces it with diagnostic failure', async () => {
  for (const diagnosticFails of [false, true]) for (const closeFails of [false, true]) {
    const primary = Object.assign(new Error('OriginalCaseRefusal'), {code: 'OriginalCaseRefusal'});
    const cleanup = Object.assign(new Error('OriginalClosePending'), {code: 'ClientCleanupPending'});
    const observations = [];
    let release, entered, closes = 0;
    const waiting = new Promise(resolve => {release = resolve;});
    const started = new Promise(resolve => {entered = resolve;});
    const result = runRecordUpdateApprovalPhase({phase: 'capture', createDefinition() {throw primary;},
      client: {async close() {closes++;entered();await waiting;if (closeFails) throw cleanup;}},
      async observeClose(value) {
        observations.push(structuredClone(value));
        if (diagnosticFails) throw new Error('OriginalDiagnosticWriteFailed');
      }});
    const rejected = assert.rejects(result, error => {
      if (!closeFails) return error === primary;
      assert.strictEqual(error.cause, primary); assert.deepEqual(error.errors, [primary, cleanup]);return true;
    });
    await started;
    assert.equal(observations.length, 1); assert.equal(observations[0].stage, 'started');
    assert.equal(observations[0].primary.code, primary.code); assert.equal(observations[0].primaryPresent, true);
    assert.deepEqual(observations[0].firstClose, {attempted: true, returned: false, state: 'pending'});
    release(); await rejected;
    assert.equal(closes, 1); assert.equal(observations[1].stage, closeFails ? 'threw' : 'returned');
    assert.equal(observations[1].firstClose.returned, !closeFails);
  }
});

test('record wrapper cannot pass lost diagnostics after successful workflow and first close', async () => {
  const value = await definition('hubspot'), sdk = publicDouble(value), primary = new Error('OriginalDiagnosticWriteFailed');
  await assert.rejects(phase('capture', value, sdk, {observeClose() {throw primary;}}), error => {
    assert(error instanceof AggregateError); assert.deepEqual(error.errors, [primary, primary]);return true;
  });
  assert.equal(sdk.events.filter(value => value === 'close').length, 1);
});

test('shared command reopens the same externally authored Program, parameters and independent oracle', async t => {
  const value = await definition('kintone');
  value.name = 'alternate-original-case';
  value.effect.document += '\n-- Author update';
  value.read.document += '\n-- Author read';
  value.effect.parameters.next_name = 'Selected alternate value';
  value.effect.expectedRows[0].next_name = 'Selected alternate value';
  value.read.afterRows[0].Subject = 'Selected alternate value';
  value.review.changes.Subject = 'Selected alternate value';
  const f = await commandFixture(t, 'kintone', {casePath: 'case.json', connect: {mode: 'local'}});
  const path = join(f.root, 'case.json'), original = JSON.stringify(value);
  await writeFile(path, original);
  f.options.programDirectory = pathToFileURL(join(f.root, 'absent') + '/');
  f.options.createDefinition = () => assert.fail('Authored input must not construct a default case');
  await runRecordApprovalCommand(f.options);
  assert.deepEqual(f.log, [{phase: 'check', status: 'ready', connected: false}]);
  assert.deepEqual(f.events, []);

  const sdk = publicDouble(value);
  const start = sdk.client.startSource.bind(sdk.client);
  sdk.client.startSource = (document, options) => {
    const program = document === value.effect.document ? value.effect : value.read;
    assert.equal(options.format, program.format);
    assert.deepEqual(options.parameterDeclarations, program.parameterDeclarations);
    return start(document, options);
  };
  sdk.client.approve = checkpointId => {
    assert.equal(checkpointId, 'checkpoint');
    return sdk.approve(sdk.client, {ref: sdk.effect.ref});
  };
  f.options.connect = async () => sdk.client;
  f.options.runPhase = runKintoneApprovalPhase;
  f.options.argv[0] = 'capture';
  await runRecordApprovalCommand(f.options);
  assert.equal(JSON.parse(await readFile(f.options.argv[2] + '.captured.json', 'utf8')).binding.caseName, value.name);
  f.options.argv[0] = 'approve';
  const changed = structuredClone(value);
  changed.effect.expectedRows[0].next_name = 'Wrong independent oracle';
  await writeFile(path, JSON.stringify(changed));
  let cursor = sdk.events.length;
  await assert.rejects(runRecordApprovalCommand(f.options), /Reopen the same Program/u);
  assert.deepEqual(sdk.events.slice(cursor), ['close']);
  await writeFile(path, original);
  await runRecordApprovalCommand(f.options);
  cursor = sdk.events.length;
  f.options.argv[0] = 'recover';
  await runRecordApprovalCommand(f.options);
  const recovered = sdk.events.slice(cursor);
  assert.deepEqual(recovered, ['attach', 'effect:result', 'effect:rows', 'effect:status', 'close']);
  assert.equal(sdk.events.filter(event => event === 'approve').length, 1);
});

test('shared command refuses incompatible authored case inputs before connecting', async t => {
  const value = await definition('hubspot'), config = {casePath: 'case.json', connect: {mode: 'local'}};
  const f = await commandFixture(t, 'hubspot', config), path = join(f.root, 'case.json');
  for (const wire of [JSON.stringify({...value, connect: {mode: 'remote'}}),
    JSON.stringify({...value, effect: {...value.effect, parameters: []}}),
    JSON.stringify({...value, read: {...value.read, afterRows: ['Invalid row']}}), Buffer.from([0xc0, 0xaf])]) {
    await writeFile(path, wire);
    await assert.rejects(runRecordApprovalCommand(f.options), {message: 'InvalidRecordApprovalAuthoredCase'});
  }
  await writeFile(path, 'x'.repeat(1024 * 1024 + 1));
  await assert.rejects(runRecordApprovalCommand(f.options), {message: 'InvalidRecordApprovalCaseFile'});
  await writeFile(f.path, JSON.stringify({...config, selection}));
  await assert.rejects(runRecordApprovalCommand(f.options), {message: 'InvalidRecordApprovalCaseSelection'});
  assert.deepEqual(f.events, []);
  assert.deepEqual(f.log, []);
});

for (const connector of ['salesforce', 'hubspot', 'kintone']) {
  test(`shared ${connector} fixture preserves original reference, explicit approval and Saved-first order`, async () => {
    const value = await definition(connector), f = publicDouble(value);
    await phase('capture', value, f);
    assert(f.events.indexOf('save:submitted') < f.events.indexOf('effect:wait'));
    assert(!f.events.includes('approve'));
    await phase('approve', value, f);
    const split = f.events.length;await phase('recover', value, f);
    const recovered = f.events.slice(split);
    assert(recovered.indexOf('effect:rows') < recovered.indexOf('effect:status'));
    assert(!recovered.some(x => x.startsWith('submit:') || x === 'approve'));
    assert.deepEqual(f.saved.get('submitted').ref, f.saved.get('recovered').ref);
    assert.equal(f.events.filter(x => x === 'close').length, 3);
    assert.equal(f.events.filter(x => x === 'approve').length, 1);
  });
  test(`shared ${connector} fixture rejects a changed sealed Review before operator approval`, async () => {
    const value = await definition(connector), f = publicDouble(value);
    await phase('capture', value, f);
    f.body.displayed_rows[0].intended_changes.value = {changed: 'unapproved'};
    const split = f.events.length;
    await assert.rejects(phase('approve', value, f));
    assert(!f.events.slice(split).includes('approve'));
    assert.equal(f.events.at(-1), 'close');
  });
  test(`shared ${connector} fixture refuses an uncommitted approval before wait or Result`, async () => {
    const value = await definition(connector), f = publicDouble(value);
    await phase('capture', value, f);const split = f.events.length;
    await assert.rejects(phase('approve', value, f, {approve: async () => ({results: [{status: 'refused'}]})}));
    assert(!f.events.slice(split).some(x => ['effect:wait', 'effect:result', 'submit:read'].includes(x)));
    assert.equal(f.events.at(-1), 'close');
  });
  test(`shared ${connector} fixture cannot retarget a saved reference to another Program`, async () => {
    const value = await definition(connector), f = publicDouble(value);
    await phase('capture', value, f);await phase('approve', value, f);
    const changed = structuredClone(value);changed.effect.document += '\n-- changed';
    const split = f.events.length;await assert.rejects(phase('recover', changed, f));
    assert(!f.events.slice(split).includes('attach'));
    assert.equal(f.events.at(-1), 'close');
  });
}

test('shared capture retains the exact first returned failed observation before its assertion and close', async () => {
  const value = await definition('hubspot'), f = publicDouble(value);
  const state = {status: 'failed', run_id: 'same-run',
    terminal_error: {code: 'ACTQL_E_AUTHORED_PUBLIC_FIXTURE', message: 'Original public diagnostic'}};
  Object.defineProperty(state, 'unselectedInput', {enumerable: true,
    get() {assert.fail('Do not enumerate or retain unselected reply data');}});
  f.effect.wait = async () => {f.events.push('effect:wait'); return state;};
  await assert.rejects(phase('capture', value, f), {code: 'ERR_ASSERTION'});
  assert.deepEqual(f.saved.get('capture-wait'), {ref: f.effect.ref, status: 'failed',
    terminal_error: {code: 'ACTQL_E_AUTHORED_PUBLIC_FIXTURE', message: 'Original public diagnostic'}, terminal_error_truncated: false});
  assert(f.events.indexOf('save:submitted') < f.events.indexOf('effect:wait'));
  assert(f.events.indexOf('effect:wait') < f.events.indexOf('save:capture-wait'));
  assert.equal(f.events.at(-1), 'close');
  assert(!f.events.includes('effect:status')); assert(!f.events.includes('approve'));
  assert(!f.saved.has('captured'));
});

test('shared capture bounds only the retained public diagnostic without changing the first reply', async () => {
  const value = await definition('hubspot'), f = publicDouble(value);
  const state = {status: 'failed', terminal_error: {
    code: 'ACTQL_E_' + 'A'.repeat(1100), message: 'M'.repeat(1100)}};
  f.effect.wait = async () => state;
  await assert.rejects(phase('capture', value, f), {code: 'ERR_ASSERTION'});
  const retained = f.saved.get('capture-wait');
  assert.equal(retained.terminal_error.code.length, 1024);
  assert.equal(retained.terminal_error.message.length, 1024);
  assert.equal(retained.terminal_error_truncated, true);
  assert.equal(state.terminal_error.code.length, 1108);
  assert.equal(state.terminal_error.message.length, 1100);
  assert.equal(f.events.at(-1), 'close');
});

test('shared capture keeps a thrown first wait primary and never invents a returned observation', async () => {
  const value = await definition('hubspot'), f = publicDouble(value), primary = new Error('OriginalWaitFailure');
  f.effect.wait = async () => {f.events.push('effect:wait'); throw primary;};
  await assert.rejects(phase('capture', value, f), error => error === primary);
  assert(f.saved.has('submitted')); assert(!f.saved.has('capture-wait'));
  assert.equal(f.events.filter(event => event === 'effect:wait').length, 1);
  assert.equal(f.events.at(-1), 'close');
});

for (const connector of ['hubspot', 'kintone']) {
  test(`shared ${connector} existing Unknown status cannot approve or resend the original update`, async () => {
    const value = await definition(connector), f = publicDouble(value);
    await phase('capture', value, f);
    f.effect.status = async () => {f.events.push('effect:status');return {status: 'needs_reconciliation', run_id: 'same-run'};};
    const split = f.events.length;
    await assert.rejects(phase('approve', value, f), {code: 'ERR_ASSERTION'});
    assert.deepEqual(f.saved.get('approve-status'), {ref: f.effect.ref, status: 'needs_reconciliation'});
    const events = f.events.slice(split);
    assert(!events.some(value => value.startsWith('submit:') || ['approve', 'effect:wait', 'effect:result'].includes(value)));
    assert(!f.saved.has('approved'));assert(!f.saved.has('approve-wait'));
    assert.equal(events.filter(value => value === 'close').length, 1);
  });

  test(`shared ${connector} post-commit Unknown is retained before refusing Result without another send`, async () => {
    const value = await definition(connector), f = publicDouble(value);
    await phase('capture', value, f);
    const state = {status: 'needs_reconciliation', run_id: 'same-run'};
    Object.defineProperty(state, 'unselectedInput', {enumerable: true,
      get() {assert.fail('Do not read unselected returned DATA');}});
    f.effect.wait = async () => {f.events.push('effect:wait');return state;};
    const split = f.events.length;
    await assert.rejects(phase('approve', value, f), {code: 'ERR_ASSERTION'});
    assert.deepEqual(f.saved.get('approve-wait'), {ref: f.saved.get('captured').ref, status: 'needs_reconciliation'});
    assert(!f.saved.has('approved'));
    const events = f.events.slice(split);
    assert.equal(events.filter(value => value === 'approve').length, 1);
    assert.equal(events.filter(value => value === 'effect:wait').length, 1);
    assert(events.indexOf('effect:wait') < events.indexOf('save:approve-wait'));
    assert(events.indexOf('save:approve-wait') < events.indexOf('close'));
    assert(!events.some(value => value.startsWith('submit:') || value === 'effect:result'));
    assert.equal(events.filter(value => value === 'close').length, 1);
  });

  test(`shared ${connector} thrown post-commit wait preserves original failure without an invented observation`, async () => {
    const value = await definition(connector), f = publicDouble(value), primary = new Error('OriginalApprovalWaitLost');
    await phase('capture', value, f);
    f.effect.wait = async () => {f.events.push('effect:wait');throw primary;};
    const split = f.events.length;
    await assert.rejects(phase('approve', value, f), error => error === primary);
    assert(f.saved.has('approve-status'));assert(!f.saved.has('approve-wait'));assert(!f.saved.has('approved'));
    const events = f.events.slice(split);
    assert.equal(events.filter(value => value === 'approve').length, 1);
    assert.equal(events.filter(value => value === 'effect:wait').length, 1);
    assert(!events.some(value => value.startsWith('submit:') || value === 'effect:result'));
    assert.equal(events.filter(value => value === 'close').length, 1);
  });
}

for (const primary of [undefined, null, false, 0, '']) {
  test(`shared fixture preserves original falsy rejection ${String(primary)} through cleanup`, async () => {
    const value = await definition('salesforce');let closed = 0, rejected = false;
    try {await runRecordUpdateApprovalPhase({phase: 'capture', definition: value,
      client: {async startSource() {throw primary;}, async close() {closed++;}}});}
    catch (error) {rejected = true;assert.strictEqual(error, primary);}
    assert(rejected);assert.equal(closed, 1);
  });
}
test('shared fixture keeps original and cleanup failures separately even for undefined primary', async () => {
  const cleanup = new Error('original cleanup pending'), value = await definition('hubspot');
  await assert.rejects(runRecordUpdateApprovalPhase({phase: 'capture', definition: value,
    client: {async startSource() {throw undefined;}, async close() {throw cleanup;}}}), error => {
      assert(error instanceof AggregateError);assert.deepEqual(error.errors, [undefined, cleanup]);
      assert(Object.hasOwn(error, 'cause'));assert.equal(error.cause, undefined);return true;
    });
});

for (const [connector, builder, resource, idField, valueField] of [
  ['salesforce', salesforceMock, 'Account', 'Id', 'Name'],
  ['hubspot', hubspotMock, 'companies', 'id', 'name'],
  ['kintone', kintoneMock, 'inquiries', '$id', 'Subject'],
]) test(`shared ${connector} mock supplies explicit unchanged Program aliases and required approval`, () => {
  const files = builder(selection), catalog = JSON.parse(files['mock/catalog.json']).connections[connector];
  assert.equal(catalog.writes[0].approval, 'required');
  assert.deepEqual(catalog.writes[0].writable_fields, [valueField]);
  assert.equal(catalog.writes[0].primary_identity, idField);
  const rows = JSON.parse(files['mock/data.json'])[connector][resource].rows;
  assert.deepEqual(rows[0], {[idField]: selection.recordId, [valueField]: 'before'});
  assert.equal(rows.length, 2);assert.notEqual(rows[1][idField], selection.recordId);
});

for (const [connector, runPhase] of [
  ['salesforce', runSalesforceApprovalPhase], ['hubspot', runHubSpotApprovalPhase],
  ['kintone', runKintoneApprovalPhase],
]) {
  for (const [name, invalid] of [
    ['missing record', {...selection, recordId: undefined}],
    ['unchanged values', {...selection, nextName: selection.previousName}],
  ]) test(`shared ${connector} case ${name} closes its connected Client without submission`, async () => {
    const value = await definition(connector), f = publicDouble(value);
    await assert.rejects(runPhase({phase: 'capture', ...f, selection: invalid,
      programs: {update: value.effect.document, read: value.read.document}}), TypeError);
    assert.deepEqual(f.events, ['close']);
    assert.equal(f.saved.size, 0);
  });

  test(`shared ${connector} invalid case retains primary and cleanup failure separately`, async () => {
    const cleanup = new Error('Original close pending');
    let closes = 0;
    await assert.rejects(runPhase({phase: 'capture', selection: {}, programs: {},
      client: {async close() {closes++; throw cleanup;}}}), error => {
      assert(error instanceof AggregateError);
      assert(error.errors[0] instanceof TypeError);
      assert.strictEqual(error.cause, error.errors[0]);
      assert.strictEqual(error.errors[1], cleanup);
      return true;
    });
    assert.equal(closes, 1);
  });

  for (const phase of ['capture', 'recover']) {
    test(`shared ${connector} ${phase} entry does not load its configured absent approval key`, async t => {
      // Exercise the exact public-consumer entry in a fresh process. Only its
      // Client and phase implementation are explicit doubles: no Host, state,
      // provider, signature, approval or ordinary acceptance is claimed here.
      const root = await mkdtemp(join(tmpdir(), 'actql-approval-entry-'));
      t.after(() => rm(root, {recursive: true, force: true}));
      await writeFile(join(root, 'package.json'), '{"private":true,"type":"module"}\n');
      const dependency = join(root, 'node_modules/@actql/node');
      await mkdir(dependency, {recursive: true});
      await writeFile(join(dependency, 'package.json'),
        '{"name":"@actql/node","type":"module","exports":"./index.mjs"}\n');
      await writeFile(join(dependency, 'index.mjs'),
        "import {writeFile} from 'node:fs/promises';" +
        "export async function connect(){return {async close(){" +
        "await writeFile(process.env.ACTQL_FIXTURE_CLOSE_MARKER,'closed',{flag:'wx'});}};}\n");
      const folder = new URL(`./fixtures/${connector}-approval/`, import.meta.url);
      const entry = join(root, connector + '-approval');
      const shared = join(root, 'record-approval');
      await mkdir(entry);
      await mkdir(shared);
      for (const name of ['command.mjs', 'cases.mjs', 'workflow.mjs']) {
        await copyFile(new URL('./fixtures/record-approval/' + name, import.meta.url), join(shared, name));
      }
      for (const name of ['run.mjs', 'update.aql', 'read.aql']) {
        await copyFile(new URL(name, folder), join(entry, name));
      }
      const exportName = {salesforce: 'runSalesforceApprovalPhase', hubspot: 'runHubSpotApprovalPhase',
        kintone: 'runKintoneApprovalPhase'}[connector];
      await writeFile(join(entry, 'workflow.mjs'),
        "import assert from 'node:assert/strict';" +
        `export async function ${exportName}({phase,client,approve}){` +
        `assert.equal(phase,${JSON.stringify(phase)});assert.equal(typeof approve,'function');` +
        "await client.close();}\n");
      await writeFile(join(root, 'consumer.json'), JSON.stringify({selection,
        connect: {mode: 'local'}, signer: {keyId: 'operator', reviewerId: 'reviewer',
          privateKeyPath: join(root, 'absent-approval.key')}}));
      const marker = join(root, 'close-returned');
      const child = spawnSync(process.execPath, [join(entry, 'run.mjs'), phase,
        join(root, 'consumer.json'), join(root, 'receipt')], {cwd: root,
        env: {...process.env, NODE_OPTIONS: '', NODE_PATH: '', ACTQL_FIXTURE_CLOSE_MARKER: marker},
        encoding: 'utf8', timeout: 10000, maxBuffer: 64 * 1024});
      assert.equal(child.error, undefined);
      assert.equal(child.status, 0, child.stderr);
      assert.equal(child.signal, null);
      assert.equal(await readFile(marker, 'utf8'), 'closed');
      assert.deepEqual(JSON.parse(child.stdout), {phase, status: 'passed', publicClientClose: 'returned'});
    });
  }
}

test('shared case construction preserves an undefined primary through failing close', async () => {
  const cleanup = new Error('Original close still pending');
  await assert.rejects(runRecordUpdateApprovalPhase({phase: 'capture',
    createDefinition() {throw undefined;}, client: {async close() {throw cleanup;}}}), error => {
    assert(error instanceof AggregateError);
    assert.deepEqual(error.errors, [undefined, cleanup]);
    assert(Object.hasOwn(error, 'cause'));
    assert.equal(error.cause, undefined);
    return true;
  });
});

test('kintone fixture retains a system record id above the exact Number range', async () => {
  const selected = {...selection, recordId: '9007199254740993'};
  const programs = Object.fromEntries(await Promise.all(['update', 'read'].map(async name =>
    [name, await readFile(new URL(`./fixtures/kintone-approval/${name}.aql`, import.meta.url), 'utf8')])));
  const value = kintoneUpdateCase(programs, selected);
  assert.equal(value.effect.parameters.record_id, '9007199254740993');
  assert.equal(value.effect.expectedRows[0].id, '9007199254740993');
  assert.equal(value.review.identity, '9007199254740993');
  const files = kintoneMock(selected);
  assert.equal(JSON.parse(files['mock/data.json']).kintone.inquiries.rows[0].$id, '9007199254740993');
});

async function commandFixture(t, connector, configuration = {selection, connect: {mode: 'local'}}) {
  const root = await mkdtemp(join(tmpdir(), 'actql-approval-command-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const path = join(root, 'consumer.json');
  await writeFile(path, JSON.stringify(configuration), {mode: 0o600});
  const log = [], events = [];
  return {root, path, log, events,
    options: {argv: ['check', path, join(root, 'receipt')],
      programDirectory: new URL(`./fixtures/${connector}-approval/`, import.meta.url),
      createDefinition: {salesforce: salesforceUpdateCase, hubspot: hubspotUpdateCase,
        kintone: kintoneUpdateCase}[connector],
      connect: async () => {events.push('connect'); throw new Error('Unexpected connection');},
      runPhase: async () => {throw new Error('Unexpected workflow');}, log: value => log.push(value)}};
}

async function retainedCommandFixture(t) {
  const command = await commandFixture(t, 'hubspot'), value = await definition('hubspot');
  const sdk = publicDouble(value), directory = join(command.root, 'programs');
  await mkdir(directory);
  await writeFile(join(directory, 'update.aql'), value.effect.document);
  await writeFile(join(directory, 'read.aql'), value.read.document);
  command.options.programDirectory = pathToFileURL(directory + '/');
  command.options.retainProgramInputs = true;
  command.options.argv[0] = 'capture';
  command.options.connect = async () => {command.events.push('connect'); return sdk.client;};
  command.options.runPhase = ({programs, selection: selected, ...rest}) =>
    runRecordUpdateApprovalPhase({...rest, createDefinition: () => hubspotUpdateCase(programs, selected),
      approve: sdk.approve});
  return {command, sdk, directory};
}

test('retained fixture Programs allow approval and Saved first after original files are removed', async t => {
  // Actual fixture file IO and workflow, with the existing explicit public SDK
  // double. This does not qualify installed Source, approval or physical close.
  const {command: f, sdk, directory} = await retainedCommandFixture(t);
  await runRecordApprovalCommand(f.options);
  const path = f.options.argv[2] + '.programs.json';
  const original = await readFile(path, 'utf8'), before = await stat(path);
  assert.equal(before.mode & 0o777, 0o600);
  assert.equal(sdk.events.at(-1), 'close');
  await unlink(join(directory, 'update.aql')); await unlink(join(directory, 'read.aql'));
  f.options.argv[0] = 'approve'; await runRecordApprovalCommand(f.options);
  const split = sdk.events.length;
  f.options.argv[0] = 'recover'; await runRecordApprovalCommand(f.options);
  const recovered = sdk.events.slice(split);
  assert(recovered.indexOf('effect:rows') < recovered.indexOf('effect:status'));
  assert(!recovered.some(value => value.startsWith('submit:') || value === 'approve'));
  assert.equal(sdk.events.filter(value => value === 'approve').length, 1);
  assert.equal(sdk.events.filter(value => value === 'close').length, 3);
  assert.equal(await readFile(path, 'utf8'), original);
  const after = await stat(path); assert.equal(after.ino, before.ino); assert.equal(after.dev, before.dev);
  await assert.rejects(readFile(join(directory, 'update.aql')), {code: 'ENOENT'});
  await assert.rejects(readFile(join(directory, 'read.aql')), {code: 'ENOENT'});
});

test('retained fixture Programs keep original binding and reject changed inputs before attach or approval', async t => {
  for (const change of ['program', 'selection']) {
    const {command: f, sdk, directory} = await retainedCommandFixture(t);
    await runRecordApprovalCommand(f.options);
    await unlink(join(directory, 'update.aql')); await unlink(join(directory, 'read.aql'));
    if (change === 'program') {
      const path = f.options.argv[2] + '.programs.json', programs = JSON.parse(await readFile(path, 'utf8'));
      programs.update += '\n-- changed'; await writeFile(path, JSON.stringify(programs));
    } else await writeFile(f.path, JSON.stringify({selection: {...selection, nextName: 'foreign'}, connect: {mode: 'local'}}));
    const split = sdk.events.length; f.options.argv[0] = 'approve';
    await assert.rejects(runRecordApprovalCommand(f.options), {code: 'ERR_ASSERTION'});
    assert.deepEqual(sdk.events.slice(split), ['close']);
  }
});

test('retained fixture Programs refuse missing malformed or incompatible receipt before connection', async t => {
  for (const retained of [undefined, '{private malformed', JSON.stringify({update: {}, read: 'original'})]) {
    const {command: f} = await retainedCommandFixture(t);
    f.options.argv[0] = 'approve';
    if (retained !== undefined) await writeFile(f.options.argv[2] + '.programs.json', retained);
    await assert.rejects(runRecordApprovalCommand(f.options), retained === undefined
      ? {code: 'ENOENT'} : /InvalidRecordApprovalRetainedPrograms/u);
    assert.deepEqual(f.events, []); assert.deepEqual(f.log, []);
  }
});

for (const connector of ['salesforce', 'hubspot', 'kintone']) {
  test(`shared ${connector} check validates its original case without connection or key IO`, async t => {
    const f = await commandFixture(t, connector, {selection, connect: {mode: 'local'},
      signer: {keyId: 'operator', reviewerId: 'reviewer', privateKeyPath: 'absent.key'}});
    await runRecordApprovalCommand(f.options);
    assert.deepEqual(f.events, []);
    assert.deepEqual(f.log, [{phase: 'check', status: 'ready', connected: false}]);
    await assert.rejects(readFile(join(f.root, 'receipt.submitted.json')), {code: 'ENOENT'});
  });

  test(`shared ${connector} command rejects an invalid original selection before connecting`, async t => {
    const f = await commandFixture(t, connector, {selection: {...selection, recordId: undefined},
      connect: {mode: 'local'}});
    f.options.argv[0] = 'capture';
    await assert.rejects(runRecordApprovalCommand(f.options), /InvalidRecordApprovalSelection/u);
    assert.deepEqual(f.events, []);
    assert.deepEqual(f.log, []);
  });
}

test('shared command validates signer configuration without reading its key or connecting', async t => {
  const f = await commandFixture(t, 'kintone', {selection, connect: {mode: 'local'},
    signer: {keyId: 'operator', privateKeyPath: 'absent.key'}});
  await assert.rejects(runRecordApprovalCommand(f.options), /InvalidRecordApprovalSigner/u);
  assert.deepEqual(f.events, []);
  assert.deepEqual(f.log, []);
});

test('shared command malformed JSON error does not repeat configuration contents', async t => {
  const f = await commandFixture(t, 'kintone');
  const privateText = 'do-not-repeat-this-configuration-value';
  await writeFile(f.path, '{"private":"' + privateText + '",');
  await assert.rejects(runRecordApprovalCommand(f.options), error => {
    assert.equal(error.message, 'InvalidRecordApprovalConfiguration');
    assert.equal(String(error.stack).includes(privateText), false);
    assert.equal(error.cause, undefined);
    return true;
  });
  assert.deepEqual(f.events, []);
});

test('shared command signs only explicit approval with a configuration-relative operator key', async t => {
  const f = await commandFixture(t, 'kintone', {selection, connect: {mode: 'local'},
    signer: {keyId: 'operator', reviewerId: 'reviewer', privateKeyPath: 'keys/operator.pem'}});
  const {privateKey, publicKey} = generateKeyPairSync('ed25519');
  await mkdir(join(f.root, 'keys'));
  await writeFile(join(f.root, 'keys/operator.pem'),
    privateKey.export({format: 'pem', type: 'pkcs8'}), {mode: 0o600});
  const captured = {summary: {original: 'sealed-checkpoint'}, ref: {authorityScopeCid: cid('a')}};
  const bytes = Buffer.from('original-public-resolution-preimage');
  let called = false;
  const client = {resolveCheckpoints: async (decisions, {signer}) => {
    called = true;
    assert.deepEqual(decisions, [{checkpoint: captured.summary, decision: 'approved'}]);
    assert.equal(signer.keyId, 'operator');
    assert.equal(signer.reviewerId, 'reviewer');
    assert.equal(signer.authorityScopeCid, captured.ref.authorityScopeCid);
    assert(verify(null, bytes, publicKey, signer.sign(bytes)));
    return {results: [{status: 'committed'}]};
  }};
  f.options.argv[0] = 'approve';
  f.options.connect = async () => client;
  f.options.runPhase = async ({approve, client: selected, phase}) => {
    assert.equal(phase, 'approve');
    assert.strictEqual(selected, client);
    assert.equal(called, false);
    await approve(selected, captured);
  };
  await runRecordApprovalCommand(f.options);
  assert.equal(called, true);
  assert.deepEqual(f.log, [{phase: 'approve', status: 'passed', publicClientClose: 'returned'}]);
});

test('shared command requires explicit rejection and invokes only the matching public SDK method', async t => {
  const f = await commandFixture(t, 'kintone', {selection, decision: 'rejected', connect: {mode: 'local'}});
  f.options.argv[0] = 'approve';
  await assert.rejects(runRecordApprovalCommand(f.options), /InvalidRecordApprovalDecision/u);
  assert.deepEqual(f.events, []);
  const captured = {checkpointId: 'original-checkpoint'};
  const client = {async reject(checkpoint) {
    assert.equal(checkpoint, captured.checkpointId);
    f.events.push('reject');
  }};
  f.options.argv[0] = 'reject';
  f.options.connect = async () => client;
  f.options.runPhase = async ({reject, decision, client: active}) => {
    assert.equal(decision, 'rejected');
    assert.equal(active, client);
    await reject(active, captured);
  };
  await runRecordApprovalCommand(f.options);
  assert.deepEqual(f.events, ['reject']);
  assert.deepEqual(f.log, [{phase: 'reject', status: 'passed', publicClientClose: 'returned', decision: 'rejected'}]);
});

test('shared command keeps receipt creation exclusive and private with the original prefix', async t => {
  const f = await commandFixture(t, 'kintone');
  f.options.argv[0] = 'capture';
  f.options.connect = async () => ({});
  f.options.runPhase = async ({save, load}) => {
    const original = {ref: {original: 'first-run'}};
    await save('submitted', original);
    assert.deepEqual(await load('submitted'), original);
    await assert.rejects(save('submitted', {ref: {original: 'replacement'}}), {code: 'EEXIST'});
    assert.deepEqual(await load('submitted'), original);
  };
  await runRecordApprovalCommand(f.options);
  assert.equal((await stat(join(f.root, 'receipt.submitted.json'))).mode & 0o777, 0o600);
});

test('shared command never prints success when its original workflow fails', async t => {
  const f = await commandFixture(t, 'kintone');
  const primary = new Error('Original workflow failed');
  f.options.argv[0] = 'capture';
  f.options.connect = async () => ({});
  f.options.runPhase = async () => {throw primary;};
  await assert.rejects(runRecordApprovalCommand(f.options), error => error === primary);
  assert.deepEqual(f.log, []);
});

test('shared command check does not import a configured operator module', async t => {
  const f = await commandFixture(t, 'kintone', {selection, connect: {mode: 'local'},
    operatorModulePath: 'not-yet-configured-operator.mjs'});
  await runRecordApprovalCommand(f.options);
  assert.deepEqual(f.events, []);
  assert.deepEqual(f.log, [{phase: 'check', status: 'ready', connected: false}]);
});

test('shared command forwards an explicit operator callback through the existing connection entrance', async t => {
  const f = await commandFixture(t, 'kintone', {selection, connect: {mode: 'local',
    installation: {directory: '/original/project/.actql'}}, operatorModulePath: 'operator.mjs'});
  await writeFile(join(f.root, 'operator.mjs'),
    `export function configureConnection(options) {
      return {...options, installation: {...options.installation,
        authorization: {original: () => 'original-operator-port'}}};
    }\n`);
  f.options.argv[0] = 'capture';
  f.options.connect = async options => {
    assert.equal(options.mode, 'local');
    assert.equal(options.installation.directory, '/original/project/.actql');
    assert.equal(options.installation.authorization.original(), 'original-operator-port');
    f.events.push('connect');
    return {};
  };
  f.options.runPhase = async () => f.events.push('workflow');
  await runRecordApprovalCommand(f.options);
  assert.deepEqual(f.events, ['connect', 'workflow']);
});

test('shared command rejects an incompatible operator module before connection', async t => {
  const f = await commandFixture(t, 'kintone', {selection, connect: {mode: 'local'},
    operatorModulePath: 'operator.mjs'});
  await writeFile(join(f.root, 'operator.mjs'), 'export const authorization = {};\n');
  f.options.argv[0] = 'capture';
  await assert.rejects(runRecordApprovalCommand(f.options), /InvalidRecordApprovalOperatorModule/u);
  assert.deepEqual(f.events, []);
  assert.deepEqual(f.log, []);
});

function hubspotProviderFixture(alternate = {}) {
  const selected = {...selection, controlId: 'untouched-control', ...alternate};
  const value = hubspotApprovalProvider(selected);
  const exchange = (pathname, body, authorized = true) => ({method: 'POST', pathname,
    authorized, body: JSON.stringify(body)});
  const apply = body => value.routes.find(route => route.pathname.endsWith('/batch/update'))
    .handle(exchange('/crm/v3/objects/companies/batch/update', body));
  const body = {inputs: [{id: selected.recordId, objectWriteTraceId: cid('a'),
    properties: {name: selected.nextName, actql_request_id: cid('b')}}]};
  return {value, selected, exchange, apply, body};
}

test('HubSpot approval provider retains independent original records and accepts one exact marked update', () => {
  const f = hubspotProviderFixture(), before = f.value.snapshot();
  assert.equal(before.target.name, selection.previousName);
  assert.equal(before.writes, 0);
  const response = f.apply(f.body);
  assert.equal(response.body.status, 'COMPLETE');
  assert.equal(response.body.results[0].id, selection.recordId);
  const after = f.value.snapshot();
  assert.equal(after.writes, 1);
  assert.equal(after.target.name, selection.nextName);
  assert.equal(after.target.marker, cid('b'));
  assert.deepEqual(after.control, before.control);
  assert.throws(() => f.apply(f.body));
  assert.equal(f.value.snapshot().writes, 1);
});

test('HubSpot approval provider refuses wrong targets, malformed values and markers without writing', () => {
  for (const mutate of [body => {body.inputs[0].id = 'other';},
    body => {body.inputs[0].properties.name = null;},
    body => {delete body.inputs[0].properties.actql_request_id;},
    body => {body.inputs[0].properties.actql_request_id = 'not-a-cid';},
    body => {body.inputs[0].extra = 'unapproved';}]) {
    const f = hubspotProviderFixture();
    mutate(f.body);
    assert.throws(() => f.apply(f.body));
    assert.equal(f.value.snapshot().writes, 0);
    assert.equal(f.value.snapshot().target.name, selection.previousName);
    assert.equal(f.value.snapshot().failures.length, 1, 'The rejected route remains an independent fixture failure');
  }
});

test('HubSpot approval provider requires a credential-bearing request before target observation', () => {
  const f = hubspotProviderFixture();
  const path = '/crm/v3/objects/companies/batch/read';
  const read = f.value.routes.find(route => route.pathname === path);
  assert.throws(() => read.handle(f.exchange(path, {inputs: [{id: selection.recordId}], properties: ['name']}, false)));
  assert.equal(f.value.snapshot().writes, 0);
  assert.equal(f.value.snapshot().requests.length, 0);
  const response = read.handle(f.exchange(path, {inputs: [{id: selection.recordId}], properties: ['name']}));
  assert.equal(response.body.results[0].properties.name, selection.previousName);
});

test('shared record approval Account fixture preserves provider policy in one complete Host/Site wire', () => {
  const provider = {version: 'actql-execution-account-config/0.1', account_id: 'fixture',
    entries: [{entry_id: 'provider', outcome: 'delegate', principal: {all: true},
      connection: {any_of: ['hubspot:hubspot']}, resource: {any_of: ['companies']},
      operation: {any_of: ['effect']}, exclusions: []}]};
  const original = JSON.stringify(provider);
  const wire = recordApprovalHostAccountConfiguration(JSON.stringify, original,
    'original-principal', 'row-source-acquired');
  const actual = JSON.parse(wire);
  assert.equal(actual.version, provider.version);
  assert.equal(actual.account_id, provider.account_id);
  assert.deepEqual(actual.entries.map(entry => entry.entry_id), ['host-read', 'host-submit', 'provider']);
  assert.deepEqual(actual.entries[2], provider.entries[0]);
  assert.deepEqual(actual.entries[0], {entry_id: 'host-read', outcome: 'allow', exclusions: [],
    principal: {any_of: ['original-principal']}, connection: {any_of: ['actql-remote-host']},
    resource: {any_of: ['result/main', 'result/updates', 'run']}, operation: {any_of: ['read']}});
  assert.deepEqual(actual.entries[1].resource, {any_of: ['row-source-acquired']});
  assert.notEqual(wire, original, 'A provider-only subset is a different complete configuration');
  assert.equal(JSON.stringify(provider), original);
});

test('shared record approval Account fixture selects only explicitly allowed Result names', () => {
  const provider = JSON.stringify({entries: []});
  const wire = recordApprovalHostAccountConfiguration(JSON.stringify, provider, 'principal', 'row-source-acquired',
    ['main', 'authored_updates']);
  const entry = JSON.parse(wire).entries.find(entry => entry.entry_id === 'host-read');
  assert.deepEqual(entry.resource, {any_of: ['result/authored_updates', 'result/main', 'run']});
  for (const names of [[], ['main', 'main'], ['result/main'], ['*'], Array(1)]) {
    assert.throws(() => recordApprovalHostAccountConfiguration(JSON.stringify, provider, 'principal',
      'row-source-acquired', names), {message: 'InvalidRecordApprovalAccountFixture'});
  }
});

test('shared record approval Account fixture never overwrites an existing Host rule', () => {
  for (const entry_id of ['host-read', 'host-submit']) {
    assert.throws(() => recordApprovalHostAccountConfiguration(JSON.stringify,
      JSON.stringify({entries: [{entry_id, outcome: 'deny'}]}), 'principal', 'row-source-acquired'),
    /InvalidRecordApprovalAccountFixture/u);
  }
});

function kintoneProviderFixture(alternate = {}) {
  const selected = {...selection, recordId: '9007199254740993', controlId: '9007199254740994', ...alternate};
  const value = kintoneApprovalProvider(selected);
  const exchange = (method, pathname, body, headers = {}, authorized = true) =>
    ({method, pathname, headers, authorized, body: JSON.stringify(body)});
  const body = {app: '12', records: [{id: selected.recordId, revision: '9007199254740994',
    record: {Subject: {value: selected.nextName}}}], upsert: false};
  const update = value.routes.find(route => route.method === 'PUT');
  return {value, selected, body, exchange,
    apply: (body, authorized = true) => update.handle(exchange('PUT', update.pathname, body, {}, authorized))};
}

test('kintone approval provider keeps string identity and original revision for one UPDATE', () => {
  const f = kintoneProviderFixture(), before = f.value.snapshot();
  assert.deepEqual(f.apply(f.body).body.records,
    [{id: f.selected.recordId, revision: '9007199254740995'}]);
  const after = f.value.snapshot();
  assert.equal(after.target.name, selection.nextName);
  assert.equal(after.target.revision, '9007199254740995');
  assert.equal(after.writes, 1);
  assert.deepEqual(after.control, before.control);
  assert.throws(() => f.apply(f.body));
  assert.equal(f.value.snapshot().writes, 1);
});

test('record approval target oracle refuses protocol-valid writes with unexpected values', () => {
  const hubspot = hubspotProviderFixture(), kintone = kintoneProviderFixture();
  const wrongValue = 'Wrong but valid provider text';
  hubspot.body.inputs[0].properties.name = wrongValue;
  kintone.body.records[0].record.Subject.value = wrongValue;
  for (const fixture of [hubspot, kintone]) {
    const expected = recordUpdateFixtureState(fixture.selected);
    const before = fixture.value.snapshot();
    fixture.apply(fixture.body);
    const after = fixture.value.snapshot();
    assert.equal(after.writes, 1);
    assert.deepEqual(after.failures, []);
    assert.equal(after.target.name, wrongValue);
    assert.deepEqual(after.control, before.control);
    assert.throws(() => assertRecordApprovalTarget(after, expected.after), /Independent provider target state/u);
  }
});

for (const [connector, makeFixture, buildMock, resource, idField, nameField, alternate] of [
  ['hubspot', hubspotProviderFixture, hubspotMock, 'companies', 'id', 'name',
    {recordId: '77', controlId: '88', previousName: 'Bureau Est', nextName: 'Bureau Sud', controlName: 'Bureau Nord'}],
  ['kintone', kintoneProviderFixture, kintoneMock, 'inquiries', '$id', 'Subject',
    {recordId: '9007199254741991', controlId: '9007199254741998', previousName: '依頼前', nextName: '依頼済', controlName: '照合用'}],
]) test(`${connector} provider resets to the original alternate case with detached observations`, () => {
  const fixture = makeFixture(alternate), before = fixture.value.snapshot();
  const expected = {target: {id: alternate.recordId, name: alternate.previousName},
    control: {id: alternate.controlId, name: alternate.controlName}};
  const files = buildMock(fixture.selected);
  const rows = JSON.parse(files['mock/data.json'])[connector][resource].rows;
  assert.deepEqual(rows, [expected.target, expected.control].map(({id, name}) => ({[idField]: id, [nameField]: name})));
  assertRecordApprovalTarget(before, expected);
  assert.deepEqual({id: before.control.id, name: before.control.name}, expected.control);
  fixture.selected.previousName = 'Changed after opening the fixture';
  fixture.selected.controlName = 'Changed after opening the fixture';
  fixture.apply(fixture.body);
  const after = fixture.value.snapshot();
  assertRecordApprovalTarget(after, {target: {...expected.target, name: alternate.nextName}});
  assert.deepEqual(after.control, before.control);
  assert.equal(after.writes, 1);
  assert.deepEqual(after.requests, [fixture.value.writeRequest]);
  assert.throws(() => fixture.apply(fixture.body));
  assert.equal(fixture.value.snapshot().failures.length, 1);
  after.target.name = 'Changed snapshot';
  after.requests.length = 0;
  assert.equal(fixture.value.snapshot().target.name, alternate.nextName);
  assert.equal(fixture.value.snapshot().requests.length, 2);
  fixture.value.reset();
  assert.deepEqual(fixture.value.snapshot(), before);
  assert.equal(after.writes, 1);
});

test('record update provider bounds seed, write text and route observations before changing state', () => {
  const tooLong = 'x'.repeat(16_385);
  assert.throws(() => hubspotProviderFixture({controlName: tooLong}), /RecordApprovalFixtureSeedLimit/u);
  assert.throws(() => hubspotMock({...selection, controlName: tooLong}), /RecordApprovalFixtureSeedLimit/u);
  const write = hubspotProviderFixture();
  write.body.inputs[0].properties.name = tooLong;
  assert.throws(() => write.apply(write.body), /InvalidRecordApprovalFixtureValue/u);
  assert.equal(write.value.snapshot().writes, 0);

  const fixture = hubspotProviderFixture(), before = fixture.value.snapshot();
  const read = fixture.value.routes.find(route => route.method === 'GET');
  const exchange = {method: 'GET', pathname: read.pathname, authorized: true};
  for (let i = 0; i < 64; i++) read.handle(exchange);
  for (let i = 0; i < 2; i++) assert.throws(() => fixture.apply(fixture.body), /RecordApprovalFixtureRequestLimit/u);
  const exhausted = fixture.value.snapshot();
  assert.equal(exhausted.requests.length, 64);
  assert.equal(exhausted.failures.length, 1);
  assert.equal(exhausted.writes, 0);
  assert.deepEqual(exhausted.target, before.target);
  fixture.value.reset();
  assert.deepEqual(fixture.value.snapshot(), before);
});

for (const [connector, builder, resource, idField, valueField, makeProvider, makeCase, beforeName, afterName] of [
  ['hubspot', hubspotMock, 'companies', 'id', 'name', hubspotApprovalProvider, hubspotUpdateCase,
    'Before HubSpot approval', 'After HubSpot approval'],
  ['kintone', kintoneMock, 'inquiries', '$id', 'Subject', kintoneApprovalProvider, kintoneUpdateCase,
    'Before kintone approval', 'After kintone approval'],
]) test(`shared ${connector} record update fixture keeps identical seed and independent Mock HTTP DATA oracles`, async () => {
  const selected = sharedRecordUpdateSelections[connector];
  const expectedBefore = {target: {id: '9007199254740993', name: beforeName},
    control: {id: '9007199254740994', name: 'Untouched control'}};
  const expectedAfter = {target: {id: '9007199254740993', name: afterName}, control: expectedBefore.control};
  assert.deepEqual(recordUpdateFixtureState(selected), {before: expectedBefore, after: expectedAfter});
  assert(Object.isFrozen(selected));assert.throws(() => {selected.controlId = 'foreign';}, TypeError);
  const files = builder(selected), catalog = JSON.parse(files['mock/catalog.json']).connections[connector];
  const rows = JSON.parse(files['mock/data.json'])[connector][resource].rows;
  assert.deepEqual(rows, [expectedBefore.target, expectedBefore.control].map(value =>
    ({[idField]: value.id, [valueField]: value.name})));
  assert.deepEqual(catalog.views[0].schema, {[idField]: {type: 'string', nullable: false},
    [valueField]: {type: 'string', nullable: false}});
  const programs = Object.fromEntries(await Promise.all(['read', 'update'].map(async name =>
    [name, await readFile(new URL(`./fixtures/${connector}-approval/${name}.aql`, import.meta.url), 'utf8')])));
  const definition = makeCase(programs, selected);
  assert.equal(definition.effect.document, programs.update);assert.equal(definition.read.document, programs.read);
  assert.deepEqual(definition.effect.parameters, {record_id: '9007199254740993', next_name: afterName});
  assert.deepEqual(definition.effect.expectedRows, [{id: '9007199254740993', previous_name: beforeName, next_name: afterName}]);
  const provider = makeProvider(selected), before = provider.snapshot();
  assert.deepEqual({id: before.target.id, name: before.target.name}, expectedBefore.target);
  assert.deepEqual({id: before.control.id, name: before.control.name}, expectedBefore.control);
  assert.equal(before.writes, 0);
  if (connector === 'hubspot') {
    const update = provider.routes.find(route => route.pathname.endsWith('/batch/update'));
    const exchange = {method: 'POST', pathname: update.pathname, authorized: true, body: JSON.stringify({inputs: [{
      id: selected.recordId, objectWriteTraceId: cid('a'), properties: {name: selected.nextName, actql_request_id: cid('b')},
    }]})};
    update.handle(exchange);
    assert.equal(provider.snapshot().target.marker, cid('b'));
    assert.equal(Object.hasOwn(provider.snapshot().target, 'revision'), false, 'HubSpot does not gain atomic revision semantics');
    assert.throws(() => update.handle(exchange), 'A repeated fixture 200 must not prove another write');
  } else {
    const update = provider.routes.find(route => route.method === 'PUT');
    const exchange = {method: 'PUT', pathname: update.pathname, headers: {}, authorized: true,
      body: JSON.stringify({app: '12', records: [{id: selected.recordId, revision: '9007199254740994',
        record: {Subject: {value: selected.nextName}}}], upsert: false})};
    update.handle(exchange);
    assert.equal(provider.snapshot().target.revision, '9007199254740995');
    assert.equal(Object.hasOwn(provider.snapshot().target, 'marker'), false);
    assert.throws(() => update.handle(exchange), 'Original revision cannot authorize another write');
  }
  const after = provider.snapshot();
  assert.deepEqual({id: after.target.id, name: after.target.name}, expectedAfter.target);
  assert.deepEqual(after.control, before.control);assert.equal(after.writes, 1);
  assert.equal(after.failures.length, 1, 'The explicit repeated-write refusal remains a separate fixture failure');
});

test('shared record fixture rejects missing or aliased control identity without changing its original selection', () => {
  const selected = sharedRecordUpdateSelections.hubspot, before = structuredClone(selected);
  for (const controlId of [undefined, '', 9007199254740994, selected.recordId]) {
    assert.throws(() => recordUpdateFixtureState({...selected, controlId}), {message: 'InvalidRecordApprovalControl'});
  }
  const state = recordUpdateFixtureState(selected);
  assert.throws(() => {state.before.control.name = 'changed';}, TypeError);
  assert.deepEqual(selected, before);
});

test('kintone approval provider refuses changed identity, revision, fields and UPSERT before mutation', () => {
  for (const mutate of [body => {body.records[0].id = '123';},
    body => {body.records[0].revision = '7';}, body => {delete body.records[0].revision;},
    body => {body.records[0].record.Subject.value = 7;},
    body => {body.records[0].record.Computed = {value: 'unapproved'};},
    body => {body.upsert = true;}]) {
    const f = kintoneProviderFixture(), before = f.value.snapshot();
    mutate(f.body); assert.throws(() => f.apply(f.body));
    assert.equal(f.value.snapshot().writes, 0);
    assert.deepEqual(f.value.snapshot().target, before.target);
    assert.deepEqual(f.value.snapshot().control, before.control);
    assert.equal(f.value.snapshot().failures.length, 1, 'The rejected route remains an independent fixture failure');
  }
  const f = kintoneProviderFixture();
  assert.throws(() => f.apply(f.body, false));
  assert.equal(f.value.snapshot().writes, 0);
  assert.equal(f.value.snapshot().failures.length, 1);
});

test('kintone approval provider requires credential-bearing Form and exact selected-record reads', () => {
  const f = kintoneProviderFixture();
  const form = f.value.routes.find(route => route.pathname.endsWith('/app/form/fields.json'));
  const read = f.value.routes.find(route => route.pathname === '/k/v1/records.json' && route.method === 'POST');
  const headers = {'x-http-method-override': 'GET'};
  assert.throws(() => form.handle(f.exchange('POST', form.pathname, {app: '12'}, headers, false)));
  assert.equal(form.handle(f.exchange('POST', form.pathname, {app: '12'}, headers)).body.revision, '7');
  const body = {app: '12', fields: ['$id', '$revision', 'Computed', 'Subject', 'Tags'],
    query: `$id in (${f.selected.recordId}) order by $id asc limit 1`};
  const response = read.handle(f.exchange('POST', read.pathname, body, headers));
  assert.equal(response.body.records.length, 1);
  assert.equal(response.body.records[0].$id.value, f.selected.recordId);
  assert.equal(response.body.records[0].Subject.value, selection.previousName);
  assert.throws(() => read.handle(f.exchange('POST', read.pathname, {...body, query: 'all'}, headers)));
  assert.equal(f.value.snapshot().writes, 0);
});


test('binary Whole JOIN fixture reads full permitted answer rows and updates before cold same-Run status', async () => {
  const update = await readFile(new URL('./fixtures/hubspot-approval/binary-source-update.aql', import.meta.url), 'utf8');
  const read = await readFile(new URL('./fixtures/hubspot-approval/read.aql', import.meta.url), 'utf8');
  assert.equal(update.split('\nJOIN ').length - 1, 1, 'One existing binary JOIN, no N-ary extension');
  const {mockProjectFiles} = await import('./fixtures/hubspot-approval/binary-source-mock-project.mjs');
  const files = mockProjectFiles(selection), catalog = JSON.parse(files['mock/catalog.json']);
  assert.deepEqual(catalog.connections.hubspot.query_aliases, [
    {name: 'hubspot.companies', resource: 'companies'},
    {name: 'hubspot.companies_peer', resource: 'companies'},
  ]);
  assert(update.includes('|> RESULT answer\n'));
  assert(!update.includes('|> RESULT joined'));
  const value = hubspotUpdateCase({update, read}, {...selection, variant: 'binary-source'});
  assert.deepEqual(value.effect.additionalResults, {answer: [{id: 'record-1', left_name: 'before',
    right_id: 'record-1', right_name: 'before', next_name: 'after'}]});
  const f = publicDouble(value);
  await phase('capture', value, f); await phase('approve', value, f);
  const split = f.events.length;
  await phase('recover', value, f);
  const cold = f.events.slice(split);
  assert(cold.indexOf('effect:rows:answer') < cold.indexOf('effect:status'));
  assert(!cold.some(value => value.startsWith('submit:') || value === 'approve'));
  assert.deepEqual(f.saved.get('approved').additionalResults, value.effect.additionalResults);
  assert.deepEqual(f.saved.get('recovered').additionalResults, value.effect.additionalResults);
  assert.deepEqual(f.saved.get('submitted').ref, f.saved.get('recovered').ref);
  assert.equal(f.events.filter(value => value === 'effect:result:answer').length, 2);
  assert.equal(f.events.filter(value => value === 'close').length, 3);
});

test('binary Whole JOIN fixture refuses incomplete answer Result without losing first close', async () => {
  const value = hubspotUpdateCase({update: 'authored binary JOIN', read: 'authored source read'},
    {...selection, variant: 'binary-source'}), f = publicDouble(value);
  await phase('capture', value, f);
  const original = f.effect.result;
  f.effect.result = name => name === 'answer' ? {all: async () => []} : original.call(f.effect, name);
  await assert.rejects(phase('approve', value, f), {code: 'ERR_ASSERTION'});
  assert.equal(f.events.at(-1), 'close');
  assert.equal(f.saved.has('approved'), false);
});


for (const [connector, makeProvider, credentialHeader] of [
  ['hubspot', hubspotApprovalProvider, 'authorization'],
  ['kintone', kintoneApprovalProvider, 'x-cybozu-api-token'],
]) test(`shared ${connector} reply loss applies once over real TLS and retains independent control`,
  {timeout: 15000}, async t => {
  const selected = sharedRecordUpdateSelections[connector];
  const expected = recordUpdateFixtureState(selected), provider = makeProvider(selected);
  const before = provider.snapshot();
  assert.deepEqual({id: before.target.id, name: before.target.name}, expected.before.target);
  const faults = recordUpdateReplyLossFaults(provider);
  const tls = await openRecordApprovalExchange(t, {provider, faults});
  const body = connector === 'hubspot' ? {inputs: [{id: selected.recordId,
    objectWriteTraceId: cid('a'), properties: {name: selected.nextName, actql_request_id: cid('b')}}]}
    : {app: '12', records: [{id: selected.recordId, revision: '9007199254740994',
      record: {Subject: {value: selected.nextName}}}], upsert: false};
  let receivedResponse = false;
  // One test protocol request, not a Host claim/approval/credential grant.
  // The existing TLS fixture alone applies then destroys the original socket.
  await assert.rejects(new Promise((resolve, reject) => {
    const bytes = Buffer.from(JSON.stringify(body));
    const call = requestHttps(new URL(provider.writeRequest.pathname, tls.origin), {
      method: provider.writeRequest.method, ca: tls.ca, agent: false,
      headers: {[credentialHeader]: credentialHeader === 'authorization'
        ? 'Bearer loopback-loss-credential' : 'loopback-loss-credential', 'content-type': 'application/json',
        'content-length': bytes.length},
    }, response => {
      receivedResponse = true;response.resume();response.once('end', resolve);
      response.once('error', reject);
    });
    call.setTimeout(5000, () => call.destroy(Object.assign(new Error('FixtureRequestTimeout'),
      {code: 'FixtureRequestTimeout'})));
    call.once('error', reject);call.end(bytes);
  }), error => error.code === 'ECONNRESET');
  assert.equal(receivedResponse, false, 'No returned HTTP success/body was fabricated');
  assert.equal(tls.remainingFaults(), 0);
  assert.equal(tls.seen().length, 1, 'This component sends exactly one original request, with no retry');
  assert.equal(tls.seen()[0].method, provider.writeRequest.method);
  assert.equal(tls.seen()[0].pathname, provider.writeRequest.pathname);
  assert.equal(JSON.stringify(tls.seen()).includes('loopback-loss-credential'), false);
  const after = provider.snapshot();
  assert.equal(after.writes, 1);
  assert.deepEqual({id: after.target.id, name: after.target.name}, expected.after.target);
  assert.deepEqual(after.control, before.control);
  assert.equal(after.failures.length, 0, 'Socket failure followed a real successful provider apply');
  if (connector === 'hubspot') {
    assert.equal(after.target.marker, cid('b'));
    assert.equal(Object.hasOwn(after.target, 'revision'), false);
  } else {
    assert.equal(after.target.revision, '9007199254740995');
    assert.equal(Object.hasOwn(after.target, 'marker'), false);
  }
  provider.reset();
  assert.deepEqual(provider.snapshot(), before);
  assert.equal(tls.remainingFaults(), 0, 'Resetting fixture rows does not rearm transport faults');
  assert.equal(tls.seen().length, 1, 'The original transport observation remains');
  // These independent backend facts are NOT a public Run/Result/receipt or
  // product no-resend proof. Actual Unknown/recovery needs the original Host.
});

test('shared reply-loss selection snapshots only a finite provider-owned write route', () => {
  assert.deepEqual(recordUpdateReplyLossFaults({writeRequest: {method: 'PUT', pathname: '/v10/records'}}),
    [{kind: 'apply-then-lose-reply', method: 'PUT', pathname: '/v10/records', times: 1}]);
  const request = {method: 'PUT', pathname: '/original'};
  const faults = recordUpdateReplyLossFaults({writeRequest: request});
  request.pathname = '/changed';
  assert.deepEqual(faults, [{kind: 'apply-then-lose-reply', method: 'PUT', pathname: '/original', times: 1}]);
  assert(Object.isFrozen(faults) && Object.isFrozen(faults[0]));
  for (const writeRequest of [undefined, {}, {method: 'put', pathname: '/x'},
    {method: 'PUT', pathname: 'https://external.invalid/x'},
    {method: 'PUT', pathname: '//external.invalid/x'}, {method: 'PUT', pathname: '/x?secret=x'},
    {method: 'PUT', pathname: '/x\0'}, {method: 'PUT', pathname: '/x\\y'},
    {method: 'PUT', pathname: '/\ud800'}]) {
    assert.throws(() => recordUpdateReplyLossFaults({writeRequest}), {message: 'InvalidRecordApprovalWriteRoute'});
  }
});

// Client doubles qualify only the selected consumer/control flow. These
// hypothetical capability outcomes are not either provider's runtime evidence.
for (const connector of ['hubspot', 'kintone']) {
  test(`shared installed reply-loss ${connector} keeps Unknown and cold same-Run lookup without Result or another approval`, async () => {
    const value = await definition(connector), f = publicDouble(value);
    const replyLossExpectation = {approveStatus: 'needs_reconciliation', lookupStatus: 'needs_reconciliation'};
    await phase('capture', value, f, {replyLossExpectation});
    f.effect.wait = async () => {f.events.push('effect:wait');return {status: 'needs_reconciliation', run_id: 'same-run'};};
    const split = f.events.length;
    await phase('approve', value, f, {replyLossExpectation});
    assert.deepEqual(f.saved.get('approval-answer'), {ref: f.effect.ref, statuses: ['committed']});
    assert.equal(f.saved.get('reply-loss').status, 'needs_reconciliation');
    assert(!f.saved.has('approved'));
    f.effect.status = async () => {f.events.push('effect:status');return {status: 'needs_reconciliation', run_id: 'same-run'};};
    const cold = f.events.length;
    await phase('recover', value, f, {replyLossExpectation});
    assert.deepEqual(f.saved.get('reply-loss-lookup'), {ref: f.effect.ref, status: 'needs_reconciliation'});
    assert(!f.saved.has('recovered'));
    const after = f.events.slice(split), lookup = f.events.slice(cold);
    assert.equal(after.filter(event => event === 'approve').length, 1);
    assert.equal(after.filter(event => event === 'effect:wait').length, 1);
    assert(!after.some(event => event.startsWith('submit:') || event.startsWith('effect:result')));
    assert(!lookup.some(event => ['approve', 'effect:wait'].includes(event)));
    assert.equal(lookup.filter(event => event === 'effect:status').length, 1);
    assert.equal(after.filter(event => event === 'close').length, 2);
    assert(f.events.indexOf('save:approval-answer') < f.events.lastIndexOf('effect:wait'));
  });
}

test('shared installed reply-loss uses explicit distinct capability outcomes and reads Result only after actual success', async () => {
  for (const approveStatus of ['needs_reconciliation', 'succeeded']) {
    const value = await definition('hubspot'), f = publicDouble(value);
    const replyLossExpectation = {approveStatus, lookupStatus: 'succeeded'};
    await phase('capture', value, f, {replyLossExpectation});
    f.effect.wait = async () => {f.events.push('effect:wait');return {status: approveStatus, run_id: 'same-run'};};
    const approval = f.events.length;
    await phase('approve', value, f, {replyLossExpectation});
    assert.equal(f.saved.has('approved'), approveStatus === 'succeeded');
    assert(!f.events.slice(approval).some(event => event.startsWith('submit:')));
    const cold = f.events.length;
    await phase('recover', value, f, {replyLossExpectation});
    const events = f.events.slice(cold);
    assert(events.indexOf('effect:status') < events.indexOf('effect:result'));
    assert.deepEqual(f.saved.get('recovered').rows, value.effect.expectedRows);
    assert.deepEqual(f.saved.get('recovered').ref, f.saved.get('captured').ref);
    assert(!events.some(event => event.startsWith('submit:') || ['approve', 'effect:wait'].includes(event)));
  }
});

test('shared installed reply-loss refuses an unexpected outcome after saving the original returned reply', async () => {
  const value = await definition('kintone'), f = publicDouble(value);
  const replyLossExpectation = {approveStatus: 'succeeded', lookupStatus: 'succeeded'};
  await phase('capture', value, f, {replyLossExpectation});
  f.effect.wait = async () => {f.events.push('effect:wait');return {status: 'needs_reconciliation', run_id: 'same-run'};};
  const split = f.events.length;
  await assert.rejects(phase('approve', value, f, {replyLossExpectation}), {code: 'ERR_ASSERTION'});
  assert.equal(f.saved.get('approve-wait').status, 'needs_reconciliation');
  assert(!f.saved.has('reply-loss'));assert(!f.saved.has('approved'));
  assert(!f.events.slice(split).some(event => event.startsWith('effect:result') || event.startsWith('submit:')));
  assert.equal(f.events.at(-1), 'close');
});

test('shared installed reply-loss cannot change its original expectation or operation during cold lookup', async () => {
  const replyLossExpectation = {approveStatus: 'needs_reconciliation', lookupStatus: 'needs_reconciliation'};
  for (const change of ['expectation', 'ref', 'runId', 'status']) {
    const value = await definition('hubspot'), f = publicDouble(value);
    await phase('capture', value, f, {replyLossExpectation});
    f.effect.wait = async () => ({status: 'needs_reconciliation', run_id: 'same-run'});
    await phase('approve', value, f, {replyLossExpectation});
    if (change !== 'expectation') f.saved.get('reply-loss')[change] = change === 'ref' ? {other: 'operation'} : 'other';
    const split = f.events.length;
    await assert.rejects(phase('recover', value, f, {replyLossExpectation: change === 'expectation'
      ? {...replyLossExpectation, lookupStatus: 'succeeded'} : replyLossExpectation}), {code: 'ERR_ASSERTION'});
    const events = f.events.slice(split);
    assert(!events.some(event => event.startsWith('submit:') || ['approve', 'effect:wait', 'effect:status', 'effect:result'].includes(event)));
    assert.equal(events.at(-1), 'close');
  }
});

test('shared installed reply-loss preserves a thrown original wait and actual cleanup failure without retry', async () => {
  const value = await definition('hubspot'), f = publicDouble(value);
  const replyLossExpectation = {approveStatus: 'needs_reconciliation', lookupStatus: 'needs_reconciliation'};
  await phase('capture', value, f, {replyLossExpectation});
  const primary = new Error('OriginalPostApprovalWaitFailed'), cleanup = new Error('OriginalCleanupPending');
  f.effect.wait = async () => {f.events.push('effect:wait');throw primary;};
  f.client.close = async () => {f.events.push('close');throw cleanup;};
  const split = f.events.length;
  await assert.rejects(phase('approve', value, f, {replyLossExpectation}), error => {
    assert(error instanceof AggregateError);assert.deepEqual(error.errors, [primary, cleanup]);
    assert.strictEqual(error.cause, primary);return true;
  });
  assert(f.saved.has('approval-answer'));assert(!f.saved.has('approve-wait'));assert(!f.saved.has('reply-loss'));
  const events = f.events.slice(split);
  assert.equal(events.filter(event => event === 'effect:wait').length, 1);
  assert.equal(events.filter(event => event === 'close').length, 1);
  assert(!events.some(event => event.startsWith('submit:') || event === 'effect:result'));
});

test('shared installed reply-loss selection is finite opt-in DATA and snapshots independent outcomes', () => {
  assert.equal(recordApprovalReplyLossExpectation(undefined), undefined);
  assert.equal(installedRecordReplyLossExpectation({}), undefined);
  const original = {approveStatus: 'needs_reconciliation', lookupStatus: 'succeeded'};
  const selected = recordApprovalReplyLossExpectation(original);
  original.lookupStatus = 'cancelled';
  assert.deepEqual(selected, {approveStatus: 'needs_reconciliation', lookupStatus: 'succeeded'});
  assert(Object.isFrozen(selected));
  assert.deepEqual(installedRecordReplyLossExpectation({ACTQL_RECORD_APPROVAL_REPLY_LOSS_EXPECTATION: JSON.stringify(selected)}), selected);
  for (const value of [null, [], {}, {approveStatus: 'unknown', lookupStatus: 'succeeded'},
    {approveStatus: 'needs_reconciliation', lookupStatus: 'failed'}, {...selected, allow: true}]) {
    assert.throws(() => recordApprovalReplyLossExpectation(value));
  }
  for (const wire of ['', '{', ' '.repeat(257)]) {
    assert.throws(() => installedRecordReplyLossExpectation({ACTQL_RECORD_APPROVAL_REPLY_LOSS_EXPECTATION: wire}));
  }
});
