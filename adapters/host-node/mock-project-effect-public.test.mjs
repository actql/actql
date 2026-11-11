import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {parse} from 'acorn';

// Execute the fixture's actual capture branch with explicit SDK/filesystem
// ports. This is no installed SDK, Model, business Run or close acceptance.
const text = readFileSync(new URL('./fixtures/mock-project-effect-public.mjs', import.meta.url), 'utf8');
const ast = parse(text, {ecmaVersion: 'latest', sourceType: 'module'});
const declaration = name => {
  const node = ast.body.find(node => node.type === 'FunctionDeclaration' && node.id.name === name);
  assert.ok(node);return text.slice(node.start, node.end);
};
const observe = new Function(`${declaration('publicRunObservation')};return publicRunObservation;`)();
const main = ast.body.find(node => node.type === 'TryStatement');
const branch = main.block.body.find(node => node.type === 'IfStatement');
const captureBody = text.slice(branch.consequent.start, branch.consequent.end);

function capture({saveFailure, state = {status: 'failed', terminal_error: {code: 'OriginalSourceFailure'}}} = {}) {
  const events = [], originalRef = Object.freeze({run: 'fixture-private-original'});
  let saved;
  const ports = {
    console: {log() {}},
    client: {async startSource() {
      events.push('submit');return {ref: originalRef, async wait() {
        events.push('wait');assert.strictEqual(saved.ref, originalRef);return state;
      }};
    }},
    targetState: async () => ({bytes: '{}'}), readFile: async () => 'original Source',
    save: async (path, value) => {
      events.push('save-reference');assert.equal(path, 'fixture-handoff.started');
      if (saveFailure !== undefined) throw saveFailure;
      saved = value;
    },
  };
  const make = new Function('ports', 'assert', `
    const {client,targetState,readFile,save,console}=ports;
    const phase='capture',twoModels=false,dealReview=false,handoffPath='fixture-handoff';
    const template='churn-risk-mock',variant='readme';
    let activeStep,firstFailedStep,runObservation;
    ${declaration('step')}
    ${declaration('publicRunObservation')}
    return async()=>{try ${captureBody} catch(cause) {
      return {cause,firstFailedStep,runObservation};
    }};
  `);
  return {invoke: make(ports, assert), events, saved: () => saved, originalRef};
}

test('actual capture retains the original accepted reference before its first failed wait', async () => {
  const f = capture(), result = await f.invoke();
  assert.deepEqual(f.events, ['submit', 'save-reference', 'wait']);
  assert.strictEqual(f.saved().ref, f.originalRef);
  assert.equal(result.firstFailedStep, 'wait for original Checkpoint');
  assert.equal(result.cause.code, 'ERR_ASSERTION', 'keep the fixture oracle failure distinct');
  assert.deepEqual(result.runObservation, {available: true, status: 'failed', terminalCode: 'OriginalSourceFailure'});
});

test('reference persistence failure retains its exact cause and does not enter wait or resubmit', async () => {
  const failure = new Error('OriginalReferenceWriteRefused'), f = capture({saveFailure: failure});
  const result = await f.invoke();
  assert.strictEqual(result.cause, failure);
  assert.equal(result.firstFailedStep, 'retain original accepted reference before wait');
  assert.deepEqual(f.events, ['submit', 'save-reference']);
  assert.equal(result.runObservation, undefined);
});

test('public wait observation separates terminal DATA from uncertain stop and excludes private material', () => {
  const value = observe({status: 'needs_reconciliation', run_id: 'private-run',
    terminal_error: {code: 'OriginalSourceFailure', message: 'private rows and Source material'},
    next_action: {kind: 'reconcile_run', reason: 'execution_unknown'},
    control: {physical_stop: 'unknown', cancellation_requested: true, revision: 23}});
  assert.deepEqual(value, {available: true, status: 'needs_reconciliation',
    terminalCode: 'OriginalSourceFailure', nextAction: 'reconcile_run',
    physicalStop: 'unknown', cancellationRequested: true});
  assert.equal(JSON.stringify(value).includes('private'), false);
  assert.deepEqual(observe({status: 'failed', terminal_error: {code: 'x'.repeat(129)}}),
    {available: true, status: 'failed'});
  assert.deepEqual(observe({status: 'failed', get terminal_error() {throw new Error('unavailable');}}),
    {available: false});
});

test('actual first close reports its return separately and never replaces the original primary', async () => {
  const start = text.indexOf('let closeFailure, closeFailed');
  const end = text.indexOf('if (failed) throw primary;', start);
  assert.ok(start > 0 && end > start);
  const make = new Function('ports', `
    let {client,primary}=ports;const phase='capture',failed=true;
    const process={pid:123},writeFile=async()=>{};
    let firstFailedStep='wait for original Checkpoint',checkDiagnostic,runObservation;
    const console={log:line=>ports.summary(JSON.parse(line))};
    return async()=>{${text.slice(start,end)}};
  `);
  for (const cleanupFails of [false, true]) {
    const primary = Object.assign(new Error('original oracle'), {code: 'ERR_ASSERTION'});
    const cleanup = Object.assign(new Error('actual original cleanup'), {code: 'ClientCleanupPending'});
    let closes = 0, result;
    await make({primary, client: {async close() {closes++;if (cleanupFails) throw cleanup;}},
      summary(value) {result = value;}})();
    assert.equal(closes, 1);
    assert.equal(result.status, 'failed');assert.equal(result.code, primary.code);
    assert.equal(result.firstFailedStep, 'wait for original Checkpoint');
    assert.deepEqual(result.firstClose, {attempted: true, returned: !cleanupFails});
    assert.equal(result.cleanupCode, cleanupFails ? cleanup.code : undefined);
    assert.equal(result.physicalStop, undefined, 'a close return does not invent whole-Run stop');
  }
});

test('workflow persists the original primary before pending close even when diagnostic writes fail', async () => {
  const start = text.indexOf('let closeFailure, closeFailed');
  const make = new Function('ports', `
    const {client,primary,writeFile,process,console}=ports;const phase='capture',failed=true;
    let firstFailedStep='wait for original Checkpoint',checkDiagnostic,runObservation;
    return async()=>{${text.slice(start)}};
  `);
  for (const writeFails of [false, true]) {
    const primary = Object.assign(new Error('OriginalWaitRefusal'), {code: 'OriginalWaitRefusal'});
    const events = [], observations = [];
    let release, entered, summary;
    const closing = new Promise(resolve => {release = resolve;});
    const started = new Promise(resolve => {entered = resolve;});
    const result = make({primary, process: {pid: 123}, console: {log(value) {summary = JSON.parse(value);}},
      client: {async close() {events.push('close'); entered(); await closing;}},
      async writeFile(path, value) {
        events.push('save'); observations.push({path, value: JSON.parse(value)});
        if (writeFails) throw Object.assign(new Error('DiagnosticWriteRefused'), {code: 'EACCES'});
      }})();
    const rejected = assert.rejects(result, error => error === primary);
    await started;
    assert.deepEqual(events, ['save', 'close']);
    assert.equal(observations[0].path, 'capture.pending.json');
    assert.equal(observations[0].value.code, primary.code);
    assert.equal(observations[0].value.firstFailedStep, 'wait for original Checkpoint');
    assert.deepEqual(observations[0].value.firstClose, {attempted: true, returned: false, state: 'pending'});
    release(); await rejected;
    assert.deepEqual(observations[1].value.firstClose, {attempted: true, returned: true, state: 'returned'});
    assert.equal(summary.status, 'failed'); assert.equal(summary.code, primary.code);
    assert.equal(summary.diagnosticFailures?.length ?? 0, writeFails ? 2 : 0);
  }
});

test('actual cold recovery consumes the same Saved Result before status and preserves its first refusal', async () => {
  const approve = branch.alternate.body.find(node => node.type === 'IfStatement');
  assert.equal(approve.test.left.name, 'phase');assert.equal(approve.test.right.value, 'approve');
  const recoverBody = text.slice(approve.alternate.start, approve.alternate.end);
  const make = new Function('ports', 'assert', `
    const {execution,readFile,targetState,checkRows,console}=ports;
    const phase='recover',template='churn-risk-mock',variant='readme',handoffPath='fixture-handoff';
    let activeStep,firstFailedStep;
    ${declaration('step')}
    return async()=>${recoverBody};
  `);
  for (const fails of [false, true]) {
    const events = [], rows = [['original-result']], ref = {run: 'fixture-original'};
    const failure = new Error('OriginalSavedResultRefused');
    const approved = {ref, runId: 'same-original-run', rows, after: {bytes: 'original-target'}};
    const invoke = make({console: {log() {}},
      readFile: async () => JSON.stringify(approved), checkRows: actual => assert.deepEqual(actual, rows),
      targetState: async () => {events.push('target');return approved.after;},
      execution: {ref, result(name) {
        assert.equal(name, 'updates');return {async all() {
          events.push('saved');if (fails) throw failure;return rows;
        }};
      }, async status() {
        assert.deepEqual(events, ['saved'], 'status cannot precede the Saved read');
        events.push('status');return {status: 'succeeded', run_id: approved.runId};
      }},
    }, assert);
    if (fails) {
      await assert.rejects(invoke, error => error === failure);
      assert.deepEqual(events, ['saved']);
    } else {
      await invoke();assert.deepEqual(events, ['saved', 'status', 'target']);
    }
  }
});
