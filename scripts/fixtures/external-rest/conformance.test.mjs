import assert from 'node:assert/strict';
import childProcess from 'node:child_process';
import fs, {mkdtemp, mkdir, readFile, rm, writeFile} from 'node:fs/promises';
import {syncBuiltinESMExports} from 'node:module';
import {realpathSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {captureStandardRestRead, observeOwnScopedStateFds, scopedStateFdCommand} from './conformance.mjs';
import {cancelStandardRestAtPageBarrier} from './cancel-conformance.mjs';

test('scoped FD observations select the existing Linux and Darwin lsof locations', () => {
  assert.equal(scopedStateFdCommand('linux'), '/usr/bin/lsof');
  assert.equal(scopedStateFdCommand('darwin'), '/usr/sbin/lsof');
});

test('scoped FD command failure or nonempty output cannot become an empty observation', t => {
  // Explicit command results cover only this observer's refusal logic, not a
  // physical descriptor observation or product cleanup acknowledgement.
  let result;
  const calls = [];
  t.mock.method(childProcess, 'spawnSync', (command, args, options) => {
    calls.push({command, args, options}); return result;
  });
  syncBuiltinESMExports();
  try {
    for (const [value, empty] of [
      [{status: 1, stdout: '', stderr: ''}, true],
      [{status: null, stdout: '', stderr: '',
        error: Object.assign(new Error('authored unavailable command'), {code: 'ENOENT'})}, false],
      [{status: 2, stdout: '', stderr: 'authored failure'}, false],
      [{status: 0, stdout: 'p1\nf3\nn/authored-root/file\n', stderr: ''}, false],
      [{status: 1, stdout: '', stderr: 'authored warning'}, false],
    ]) {
      result = value;
      const observed = observeOwnScopedStateFds(['/authored-root']);
      assert.equal(observed.scopedStateFd0, empty);
      assert.equal(observed.observations[0].command, scopedStateFdCommand(process.platform));
    }
    assert.equal(calls.length, 5);
    for (const call of calls) {
      assert.equal(call.command, scopedStateFdCommand(process.platform));
      assert.deepEqual(call.args, ['-nP', '-a', '-p', String(process.pid), '+D', '/authored-root', '-F', 'pfn']);
    }
  } finally {
    t.mock.restoreAll(); syncBuiltinESMExports();
  }
});

async function fixture(t) {
  const root = await mkdtemp(join(realpathSync(tmpdir()), 'actql-rest-caller-mechanism-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const state = join(root, 'state'); await mkdir(state);
  const outputRoot = join(root, 'report');
  return {root, state, outputRoot, read: async name => JSON.parse(await readFile(join(outputRoot, name), 'utf8'))};
}

test('conformance caller captures the actual original pending projection before wait and closes once', async t => {
  const f = await fixture(t), events = [];
  const reference = {run: 'synthetic-mechanism-only'}, rows = [{id: 'authored'}];
  const execution = {ref: reference, wait: async () => {events.push('wait');return {status: 'succeeded'};},
    status: async () => ({status: 'succeeded'}), result: name => {
      assert.equal(name, 'rows'); return {all: async () => structuredClone(rows)};
    }};
  const pending = Promise.resolve(execution);
  const publicSdk = {getSubmissionInput(value) {assert.equal(value, pending);
    events.push('original-getter'); return {original: 'synthetic-input'};}};
  const client = {startSource() {events.push('start'); return pending;},
    close: async () => events.push('first-close')};
  const result = await captureStandardRestRead(client, {publicSdk, program: {version: 'synthetic'},
    assertRows: actual => assert.deepEqual(actual, rows), outputRoot: f.outputRoot, stateRoots: [f.state]});
  assert.deepEqual(events, ['start', 'original-getter', 'wait', 'first-close']);
  assert.deepEqual(result, {reference, rows});
  assert.deepEqual(await f.read('original-submission-input.json'),
    {available: true, input: {original: 'synthetic-input'}});
  assert.deepEqual(await f.read('original-wait.json'), {status: 'succeeded'});
  const close = await f.read('first-close.json');
  assert.equal(close.acknowledged, true); assert.equal(close.fd.scopedStateFd0, true);
  assert.equal(close.fd.aliveAfterClose, true);
});

test('a pre-ref public rejection keeps original input and failure without an invented refusal', async t => {
  const f = await fixture(t), primary = Object.assign(new Error('original synthetic unknown'), {code: 'SubmissionUnknown'});
  const pending = Promise.reject(primary); let starts = 0, closes = 0;
  const client = {startSource() {starts++; return pending;}, close: async () => {closes++;}};
  const publicSdk = {getSubmissionInput(value) {assert.equal(value, pending); return {original: 'before-ref'};}};
  await assert.rejects(captureStandardRestRead(client, {publicSdk, program: {},
    assertRows: () => assert.fail('No rows available'), outputRoot: f.outputRoot, stateRoots: [f.state]}),
  cause => cause === primary);
  assert.equal(starts, 1); assert.equal(closes, 1);
  assert.deepEqual(await f.read('original-submission-input.json'), {available: true, input: {original: 'before-ref'}});
  const report = await f.read('outcome.json');
  assert.equal(report.passed, false); assert.equal(report.primary.code, 'SubmissionUnknown');
  assert.equal(report.publicCloseAcknowledged, true);
  assert.equal(Object.hasOwn(report, 'knownNotAccepted'), false);
});

test('empty scoped descriptors never turn a failed first close into ACK or success', async t => {
  const f = await fixture(t), cleanup = Object.assign(new Error('synthetic cleanup pending'), {code: 'ClientCleanupPending'});
  const execution = {ref: {run: 'synthetic-close-only'}, wait: async () => ({status: 'succeeded'}),
    status: async () => ({status: 'succeeded'}), result: () => ({all: async () => []})};
  let closes = 0;
  const client = {startSource: () => Promise.resolve(execution),
    close: async () => {closes++; throw cleanup;}};
  await assert.rejects(captureStandardRestRead(client, {
    publicSdk: {getSubmissionInput: () => ({original: 'close-case'})}, program: {},
    assertRows: rows => assert.deepEqual(rows, []), outputRoot: f.outputRoot, stateRoots: [f.state]}),
  cause => cause === cleanup);
  assert.equal(closes, 1);
  const close = await f.read('first-close.json'), report = await f.read('outcome.json');
  assert.equal(close.fd.scopedStateFd0, true); assert.equal(close.acknowledged, false);
  assert.equal(report.passed, false); assert.equal(report.publicCloseAcknowledged, false);
});


test('a missing canonical SDK getter still closes the opened client without submitting', async t => {
  const f = await fixture(t); let starts = 0, closes = 0;
  const client = {startSource() {starts++; throw new Error('Must not submit');},
    close: async () => {closes++;}};
  await assert.rejects(captureStandardRestRead(client, {publicSdk: {}, program: {},
    assertRows() {}, outputRoot: f.outputRoot, stateRoots: [f.state]}), {code: 'ERR_ASSERTION'});
  assert.equal(starts, 0); assert.equal(closes, 1);
  const report = await f.read('outcome.json');
  assert.equal(report.passed, false); assert.equal(report.publicCloseAcknowledged, true);
});

test('a throwing canonical submission getter keeps the same pending rejection observed and closes once', async t => {
  const f = await fixture(t);
  const submissionFailure = Object.assign(new Error('synthetic original pending rejection'), {code: 'SubmissionUnknown'});
  const projectionFailure = new Error('synthetic original getter failure');
  let starts = 0, closes = 0;
  const pending = Promise.reject(submissionFailure);
  const client = {startSource() {starts++; return pending;}, close: async () => {closes++;}};
  const publicSdk = {getSubmissionInput(value) {assert.equal(value, pending);throw projectionFailure;}};
  await assert.rejects(captureStandardRestRead(client, {publicSdk, program: {},
    assertRows() {assert.fail('No rows are available');},
    outputRoot: f.outputRoot, stateRoots: [f.state]}), cause => cause === projectionFailure);
  assert.equal(starts, 1);assert.equal(closes, 1);
  const report = await f.read('outcome.json');
  assert.equal(report.passed, false);assert.equal(report.primary.message, projectionFailure.message);
  assert.equal(report.publicCloseAcknowledged, true);
  assert.equal(Object.hasOwn(report, 'knownNotAccepted'), false);
});

test('an original failed wait cannot be replaced by later successful status or rows', async t => {
  const f = await fixture(t), events = [];
  const reference = {run: 'synthetic-original-failed-wait'};
  const waited = {status: 'failed', result_available: false};
  const pending = Promise.resolve({ref: reference,
    wait: async () => {events.push('wait');return waited;},
    status: async () => {events.push('status');return {status: 'succeeded'};},
    result: () => ({all: async () => {events.push('rows');return [];}})});
  const client = {startSource: () => {events.push('start');return pending;},
    close: async () => {events.push('first-close');}};
  await assert.rejects(captureStandardRestRead(client, {
    publicSdk: {getSubmissionInput(value) {assert.equal(value, pending);return {original: 'failed-wait'};}},
    program: {}, assertRows: rows => assert.deepEqual(rows, []),
    outputRoot: f.outputRoot, stateRoots: [f.state]}), {code: 'ERR_ASSERTION'});
  assert.deepEqual(events, ['start', 'wait', 'first-close']);
  assert.deepEqual(await f.read('original-reference.json'), reference);
  assert.deepEqual(await f.read('original-wait.json'), waited);
  const outcome = await f.read('outcome.json');
  assert.equal(outcome.passed, false);assert.equal(outcome.publicCloseAcknowledged, true);
  assert.equal(outcome.scopedStateFd0, true);
});


// Explicit synthetic public ports exercise only the existing fixture caller.
// They supply no product Run, authority, provider or physical-stop evidence.
function cancellationPorts(events) {
  const reference = {run: 'synthetic-marker-only'};
  const execution = {ref: reference,
    status: async () => ({status: 'running', result_available: false,
      control: {physical_stop: 'unknown', revision: 2}}),
    cancel: async options => {
      events.push('cancel');
      return {kind: 'accepted', cancellation: {kind: 'accepted', ref: reference,
        cancelRef: {...reference, cancelId: options.cancelId, expectedRevision: options.expectedRevision}}};
    },
    wait: async () => {events.push('wait');return {status: 'cancelled', result_available: false,
      control: {cancellation_requested: true, physical_stop: 'confirmed'}};},
  };
  const pending = Promise.resolve(execution);
  return {client: {startSource() {events.push('start');return pending;},
    close: async () => {events.push('close');}},
  publicSdk: {getSubmissionInput(value) {assert.equal(value, pending);return {original: 'synthetic'};},
    explainCancellation: answer => ({kind: answer.kind})}};
}

test('REST cancel marker stays absent until the original write has complete bytes', async t => {
  const f = await fixture(t), events = [];
  await mkdir(f.outputRoot);
  const pageEnteredPath = join(f.root, 'page-entered.json');
  await writeFile(pageEnteredPath, JSON.stringify({page: 2, replyHeld: true}));
  const marker = join(f.root, 'cancel-returned.json'), partial = Promise.withResolvers();
  const release = Promise.withResolvers(), originalWrite = fs.writeFile, originalOpen = fs.open;
  t.mock.method(fs, 'writeFile', async (path, data, options) => {
    if (path !== marker && path !== marker + '.pending') return originalWrite(path, data, options);
    const handle = await originalOpen(path, options.flag, options.mode);
    try {
      const bytes = Buffer.from(data);
      await handle.writeFile(bytes.subarray(0, 1));
      partial.resolve();
      await release.promise;
      await handle.writeFile(bytes.subarray(1));
    } finally {await handle.close();}
  });
  syncBuiltinESMExports();
  const ports = cancellationPorts(events);
  const flight = cancelStandardRestAtPageBarrier(ports.client, {publicSdk: ports.publicSdk,
    program: {}, outputRoot: f.outputRoot, stateRoots: [f.state],
    pageEnteredPath, cancellationReturnedPath: marker});
  const observed = flight.then(value => ({value}), error => ({error}));
  try {
    const entered = await Promise.race([partial.promise.then(() => true), observed]);
    assert.equal(entered, true, 'Existing caller did not reach original marker write');
    await assert.rejects(readFile(marker, 'utf8'), {code: 'ENOENT'});
    release.resolve();
    const terminal = await observed;
    assert.equal(terminal.error, undefined);
    const value = JSON.parse(await readFile(marker, 'utf8'));
    assert.equal(value.returned, true);assert.equal(value.answer.kind, 'accepted');
    await assert.rejects(readFile(marker + '.pending'), {code: 'ENOENT'});
    assert.deepEqual(events, ['start', 'cancel', 'wait', 'close']);
  } finally {
    release.resolve();await observed;
    t.mock.restoreAll();syncBuiltinESMExports();
  }
});

test('REST cancel marker refuses replacement and keeps the original complete marker', async t => {
  const f = await fixture(t), marker = join(f.root, 'cancel-returned.json');
  const pageEnteredPath = join(f.root, 'page-entered.json');
  await writeFile(pageEnteredPath, JSON.stringify({page: 2, replyHeld: true}));
  for (const index of [0, 1]) {
    const events = [], ports = cancellationPorts(events), outputRoot = join(f.root, 'attempt-' + index);
    await mkdir(outputRoot);
    const flight = cancelStandardRestAtPageBarrier(ports.client, {publicSdk: ports.publicSdk,
      program: {}, outputRoot, stateRoots: [f.state], pageEnteredPath, cancellationReturnedPath: marker});
    if (index === 0) await flight;
    else await assert.rejects(flight, {code: 'EEXIST'});
    assert.equal(events.filter(value => value === 'cancel').length, 1);
    assert.equal(events.filter(value => value === 'close').length, 1);
    if (index === 0) f.originalMarker = await readFile(marker);
    else assert.deepEqual(await readFile(marker), f.originalMarker);
  }
});

test('REST cancel keeps malformed published page markers as failure without parsing retries', async t => {
  const f = await fixture(t), events = [], ports = cancellationPorts(events);
  await mkdir(f.outputRoot);
  const pageEnteredPath = join(f.root, 'page-entered.json');
  await writeFile(pageEnteredPath, '{');
  await assert.rejects(cancelStandardRestAtPageBarrier(ports.client, {publicSdk: ports.publicSdk,
    program: {}, outputRoot: f.outputRoot, stateRoots: [f.state], pageEnteredPath,
    cancellationReturnedPath: join(f.root, 'must-not-exist.json')}), SyntaxError);
  assert.deepEqual(events, ['start', 'close']);
  await assert.rejects(readFile(join(f.root, 'must-not-exist.json')), {code: 'ENOENT'});
});
