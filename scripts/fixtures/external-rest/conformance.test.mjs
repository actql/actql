import assert from 'node:assert/strict';
import {mkdtemp, mkdir, readFile, rm} from 'node:fs/promises';
import {realpathSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {captureStandardRestRead} from './conformance.mjs';

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
  const execution = {ref: reference, wait: async () => events.push('wait'),
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
  const execution = {ref: {run: 'synthetic-close-only'}, wait: async () => {},
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
