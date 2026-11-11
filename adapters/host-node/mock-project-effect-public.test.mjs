import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {parse} from 'acorn';
import {createHostObservationConnection, installHostObservation} from '../host-common/observation.mjs';

// Execute the fixture's actual capture branch with explicit SDK/filesystem
// ports. This is no installed SDK, Model, business Run or close acceptance.
const text = readFileSync(new URL('./fixtures/mock-project-effect-public.mjs', import.meta.url), 'utf8');
const ast = parse(text, {ecmaVersion: 'latest', sourceType: 'module'});
const workText = readFileSync(new URL('./fixtures/work-observation.fixture.mjs', import.meta.url), 'utf8');
const workAst = parse(workText, {ecmaVersion: 'latest', sourceType: 'module'});
const declaration = name => {
  const source = name === 'workflowWorkObservation' ? workText : text;
  const body = name === 'workflowWorkObservation' ? workAst.body : ast.body;
  const node = body.map(node => node.type === 'ExportNamedDeclaration' ? node.declaration : node)
    .find(node => node?.type === 'FunctionDeclaration' && node.id.name === name);
  assert.ok(node);return source.slice(node.start, node.end);
};
const observe = new Function(`${declaration('publicRunObservation')};return publicRunObservation;`)();
const main = ast.body.find(node => node.type === 'TryStatement');
const branch = main.block.body.find(node => node.type === 'IfStatement');
const captureBody = text.slice(branch.consequent.start, branch.consequent.end);

test('authored README Source and Model call bounds reject duplicated and missing starts', () => {
  const check = new Function('assert', `${declaration('checkWorkflowWork')};return checkWorkflowWork;`)(assert);
  for (const models of [1, 2]) {
    const work = {complete: true, sourceAcquisitionStarts: 2, modelCallStarts: 2 * models,
      effectReplacementReturns: 0};
    check(work, 'capture', 2, models);
    for (const sourceAcquisitionStarts of [1, 3]) {
      assert.throws(() => check({...work, sourceAcquisitionStarts}, 'capture', 2, models));
    }
    for (const modelCallStarts of [2 * models - 1, 2 * models + 1]) {
      assert.throws(() => check({...work, modelCallStarts}, 'capture', 2, models));
    }
    assert.throws(() => check({...work, effectReplacementReturns: 1}, 'capture', 2, models));
  }
});

test('workflow primary failure stays with its actual original Run instead of another verification Run', async () => {
  const make = new Function('createHostObservationConnection',
    `${declaration('workflowWorkObservation')};return workflowWorkObservation;`)(createHostObservationConnection);
  const ref = value => ({namespaceId: 'fixture', authorityScopeCid: `sha256:${'a'.repeat(64)}`,
    runDefinitionCid: `sha256:${value.repeat(64)}`});
  const original = ref('1'), verification = ref('2'), work = make({trackOriginal: true});
  const observer = installHostObservation(work.connection, {runId: () => 'same-host-fixture',
    journal: {observationStorage: () => ({consume: () => ({accepted: true})})}});
  const failure = {code: 'MoonBitHostFailure', phase: 'original_model_acquired_effect_evidence',
    kind: 'invocation.foreign_captured_input', task: 4, unit: 2, step: 5};
  observer.diagnostic('dispatch_failed', {ref: verification, primaryDiagnostic: {...failure, kind: 'dependency'}});
  observer.diagnostic('dispatch_failed', {ref: original, primaryDiagnostic: failure});
  observer.diagnostic('dispatch_failed', {ref: original, primaryDiagnostic: {...failure, kind: 'relation'}});
  await observer.close();
  assert.deepEqual(work.forOriginal(original).primaryFailure, {available: true,
    code: failure.code, phase: failure.phase, kind: failure.kind, occurrence: {task: 4, unit: 2, step: 5}});
  assert.equal(work.forOriginal(verification).primaryFailure.kind, 'dependency');
  assert.deepEqual(work.forOriginal(ref('3')).primaryFailure, {available: false});
  assert.deepEqual(work.forOriginal(undefined).primaryFailure, {available: false});
  assert.equal(work.forOriginal(original).complete, true);
  assert.equal(JSON.stringify(work.forOriginal(original)).includes('sha256:'), false);
});

test('workflow missing or lost primary delivery remains unavailable instead of becoming a fabricated cause', async () => {
  const make = new Function('createHostObservationConnection',
    `${declaration('workflowWorkObservation')};return workflowWorkObservation;`);
  for (const lose of [false, true]) {
    const work = make(options => createHostObservationConnection({...options,
      ...(lose ? {limits: {queueRecords: 1}} : {})}))();
    const observer = installHostObservation(work.connection);
    if (lose) observer.diagnostic('model_call_entered', {});
    observer.diagnostic('dispatch_failed', lose ? {primaryDiagnostic: {
      code: 'MoonBitHostFailure', phase: 'original_model_acquired_effect_evidence',
      kind: 'relation', task: 4, unit: 2, step: 5}} : {});
    await observer.close();
    assert.deepEqual(work.snapshot().primaryFailure, {available: false});
    if (lose) {assert.equal(work.snapshot().complete, false); assert(work.snapshot().status.dropped > 0);}
  }
});

test('workflow operation timers keep actual intervals and original failures even when logging fails', async () => {
  const make = new Function('ports', `
    const {console,process}=ports,phase='capture',stepDiagnosticFailures=ports.failures;
    let activeStep,firstFailedStep;
    ${declaration('step')}
    return step;
  `);
  for (const fails of [false, true]) for (const logFails of [false, true]) {
    const failures = [], rows = [], primary = new Error('OriginalOperationRefusal');
    const step = make({process, failures, console: {log(line) {
      rows.push(JSON.parse(line)); if (logFails) throw new Error('OriginalDiagnosticFailure');
    }}});
    let release, called = 0;
    const waiting = new Promise(resolve => {release = resolve;});
    const result = step('original public wait', async () => {called++; await waiting;
      if (fails) throw primary;return 'original';});
    const observed = fails ? assert.rejects(result, error => error === primary) : result;
    assert.equal(rows.length, 0, 'A pending operation must not acquire a completed timer');
    release(); await observed;
    assert.equal(called, 1); assert.equal(rows.length, 1);
    assert.equal(rows[0].status, fails ? 'failed' : 'passed');
    assert.equal(rows[0].step, 'original public wait');
    assert(rows[0].timing.wallNs > 0 && Number.isSafeInteger(rows[0].timing.wallNs));
    for (const name of ['cpuUserUs', 'cpuSystemUs']) assert(Number.isSafeInteger(rows[0].timing[name]) && rows[0].timing[name] >= 0);
    assert.equal(failures.length, logFails ? 1 : 0);
  }
});

test('workflow actual observation counts Source Model and physical writes with loss-aware phase controls', async () => {
  const make = new Function('createHostObservationConnection',
    `${declaration('workflowWorkObservation')};return workflowWorkObservation;`)(createHostObservationConnection);
  const check = new Function('assert', `${declaration('checkWorkflowWork')};return checkWorkflowWork;`)(assert);
  for (const phase of ['capture', 'approve', 'recover']) for (const models of [1, 2]) {
    const work = make(), observer = installHostObservation(work.connection, {});
    assert.equal(work.snapshot().complete, false, 'Pending delivery is not zero work');
    if (phase === 'capture') {
      observer.diagnostic('acquisition_started', {}); observer.diagnostic('acquisition_started', {});
      for (let i = 0; i < 2 * models; i++) observer.diagnostic('model_call_entered', {});
    } else if (phase === 'approve') {
      observer.diagnostic('effect_write_observed', {}); observer.diagnostic('effect_write_observed', {});
    }
    observer.diagnostic('effect_application_observed', {outcome: 'succeeded'});
    await observer.close();
    const actual = work.snapshot(); check(actual, phase, 2, models);
    assert.equal(actual.sourceAcquisitionStarts, phase === 'capture' ? 2 : 0);
    assert.equal(actual.modelCallStarts, phase === 'capture' ? 2 * models : 0);
    assert.equal(actual.effectReplacementReturns, phase === 'approve' ? 2 : 0);
    assert.throws(() => check({...actual, complete: false}, phase, 2, models));
    assert.throws(() => check({...actual, effectReplacementReturns: 3}, phase, 2, models));
    if (phase !== 'capture') {
      assert.throws(() => check({...actual, sourceAcquisitionStarts: 1}, phase, 2, models));
      assert.throws(() => check({...actual, modelCallStarts: 1}, phase, 2, models));
    }
  }
  const limited = new Function('createHostObservationConnection',
    `${declaration('workflowWorkObservation')};return workflowWorkObservation;`)(
    options => createHostObservationConnection({...options, limits: {queueRecords: 1}}))();
  const observer = installHostObservation(limited.connection, {});
  for (let n = 0; n < 10; n++) observer.diagnostic('model_call_entered', {});
  await observer.close();
  assert.equal(limited.snapshot().complete, false);
  assert(limited.snapshot().status.dropped > 0);
});

test('original Run work separates fresh verification reads and refuses unbound or over-limit scope', async () => {
  const make = new Function('createHostObservationConnection',
    `${declaration('workflowWorkObservation')};return workflowWorkObservation;`)(createHostObservationConnection);
  const ref = value => ({namespaceId: 'fixture', authorityScopeCid: `sha256:${'a'.repeat(64)}`,
    runDefinitionCid: `sha256:${value.repeat(64)}`});
  const original = ref('1'), verification = ref('2');
  const install = work => installHostObservation(work.connection, {runId: () => 'same-host-fixture',
    journal: {observationStorage: () => ({consume: () => ({accepted: true})})}});
  for (const phase of ['approve', 'saved']) {
    const work = make({trackOriginal: true}), observer = install(work);
    if (phase === 'approve') {
      observer.diagnostic('effect_write_observed', {ref: original});
      observer.diagnostic('acquisition_started', {ref: verification});
    }
    await observer.close();
    const actual = work.forOriginal(original);
    assert.equal(actual.complete, true); assert.equal(actual.sourceAcquisitionStarts, 0);
    assert.equal(actual.modelCallStarts, 0);
    assert.equal(actual.effectReplacementReturns, phase === 'approve' ? 1 : 0);
    assert.equal(actual.totals.sourceAcquisitionStarts, phase === 'approve' ? 1 : 0);
    assert.equal(JSON.stringify(actual).includes('sha256:'), false);
    assert.equal(work.forOriginal(undefined).complete, false);
  }
  for (const event of ['acquisition_started', 'model_call_entered', 'effect_write_observed']) {
    const work = make({trackOriginal: true}), observer = install(work);
    observer.diagnostic(event, {}); await observer.close();
    assert.equal(work.forOriginal(original).complete, false, 'Unbound work cannot become original zero');
  }
  const ambient = make({trackOriginal: true}), selected = install(ambient);
  await selected.run('resolve', undefined, () => {
    selected.accepted({ref: original, inserted: false}, 'fixture-request');
    selected.diagnostic('effect_write_observed', {ref: {}});
  });
  await selected.close();
  assert.equal(ambient.forOriginal(original).complete, false, 'Unknown physical original cannot borrow caller correlation');
  assert.equal(ambient.forOriginal(original).totals.effectReplacementReturns, 1);
  const work = make({trackOriginal: true}), observer = install(work);
  for (let n = 1; n <= 9; n++) observer.diagnostic('acquisition_started', {ref: ref(String(n))});
  await observer.close(); assert.equal(work.forOriginal(original).complete, false);
});

test('write attribution borrows the existing exact Mock original and keeps unreadable identity unbound', () => {
  const source = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
  const ast = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
  let callback;
  const declarations = new Map();
  function visit(node) {
    if (!node || typeof node !== 'object') return;
    if (node.type === 'VariableDeclarator' && node.id.type === 'Identifier') {
      assert(!declarations.has(node.id.name) || node.id.name !== 'observeMockEffectWrite');
      declarations.set(node.id.name, node.init);
    }
    if (node.type === 'CallExpression' && node.callee.type === 'MemberExpression' &&
        node.callee.object.name === 'preparation' && node.callee.property.name === 'installMockEffects') {
      assert.equal(callback, undefined); callback = node.arguments.at(-1);
    }
    for (const child of Object.values(node)) {
      if (Array.isArray(child)) child.forEach(visit);
      else if (child && typeof child === 'object') visit(child);
    }
  }
  visit(ast);
  if (callback?.type === 'Identifier') {
    assert.equal(callback.name, 'observeMockEffectWrite');
    callback = declarations.get(callback.name);
  }
  assert.equal(callback?.type, 'ArrowFunctionExpression');
  const original = Object.freeze({}), definition = Object.freeze({}), entries = new WeakMap();
  entries.set(original, {original, definition});
  const events = []; let calls = 0, unreadable = false;
  const observe = Function('mockEffectOriginals', 'diagnostic', 'namespaceId', 'authorityScopeCid', 'moon',
    `return (${source.slice(callback.start, callback.end)});`)(entries,
    (event, detail) => events.push({event, ...detail}), 'same-host', `sha256:${'a'.repeat(64)}`,
    {strategyPublicationContractIdentity(value) {
      assert.strictEqual(value, definition);calls++;
      if (unreadable) throw new Error('OriginalIdentityUnavailable');
      return `sha256:${'b'.repeat(64)}`;
    }});
  observe(original); observe(Object.freeze({})); unreadable = true; observe(original);
  assert.equal(calls, 2); assert.equal(events.length, 3);
  assert.deepEqual(events[0], {event: 'effect_write_observed', ref: {namespaceId: 'same-host',
    authorityScopeCid: `sha256:${'a'.repeat(64)}`, runDefinitionCid: `sha256:${'b'.repeat(64)}`}});
  assert.deepEqual(events[1].ref, {}); assert.deepEqual(events[2].ref, {});
});

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
    let activeStep,firstFailedStep,runObservation;const stepDiagnosticFailures=[];
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
    const workObservation={snapshot:()=>({complete:false})};const stepDiagnosticFailures=[];
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
    const workObservation={snapshot:()=>({complete:false})};const stepDiagnosticFailures=[];
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
    const phase='recover',template='churn-risk-mock',variant='readme',wholeProducer=false,handoffPath='fixture-handoff';
    let activeStep,firstFailedStep;const stepDiagnosticFailures=[];
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
