// Original Request refusal and audience projection are separate original
// observations. The execution installer never invokes an independent checker.
import assert from 'node:assert/strict';
import test from 'node:test';
import {parse} from 'acorn';
import {readFile} from 'node:fs/promises';
import {installNodeClientProgramPreparation, checkedRequestProgramPreparation,
  checkedRequestSnapshotPreparation, requestProgramCapacityRefusal, retainPreparedSubmissionFailure} from './client-program-preparation.mjs';
import {createDiagnosticObserver} from '../host-common/diagnostic-observer.mjs';
import {installNodeClientCheck} from './client-check.mjs';
import {installNodeClientSubmission} from './client-submission.mjs';
import {validCheckOutcome} from '../../packages/client-wire/index.mjs';

const invalid = JSON.parse(await readFile(new URL('../../packages/client-wire/fixtures/check-default-type.invalid.json', import.meta.url), 'utf8'));
const verified = JSON.parse(await readFile(new URL('../../packages/client-wire/fixtures/check-outcome-pins.verified.json', import.meta.url), 'utf8'));
const failed = JSON.parse(await readFile(new URL('../../packages/client-wire/fixtures/check-reporting-failure.json', import.meta.url), 'utf8'));
const sourceRequest = {principalId: 'original-audience', connection: {}, kind: 'aql',
  input: {format: 'sql', text: 'SELECT 1 AS n', parameterDeclarations: {minimum: {type: 'number', default: 'bad'}}},
  parameters: {raw: 'e\u0301\r\n'}};

test('prepared submission catch retains original first and observer throw cannot replace primary or touch cleanup', () => {
  const failures = new WeakMap(), requested = {}, sourceRefusal = {}, prepared = {};
  const submission = {preparedProgram: prepared};
  const primary = Object.assign(new Error('MoonBitHostFailure'), {code: 'MoonBitHostFailure'});
  let forbidden = 0, cleaned = 0, caught;
  const observed = [];
  for (const key of ['cause', 'cleanupHandle']) Object.defineProperty(primary, key, {
    get() {forbidden++;throw Error('Private failed-owner accessor');}});
  const observe = (event, detail) => {
    observed.push({event, detail, retained: failures.get(submission)});
    throw Error('Optional observer failed');
  };
  try {retainPreparedSubmissionFailure(failures, submission, primary, requested, sourceRefusal, observe);}
  catch (error) {caught = error;}
  finally {cleaned++;assert.strictEqual(failures.get(submission).error, primary);}
  assert.strictEqual(caught, primary); assert.equal(observed.length, 1); assert.equal(cleaned, 1); assert.equal(forbidden, 0);
  const {event, detail, retained} = observed[0];
  assert.equal(event, 'preparation_failed'); assert.strictEqual(retained.error, primary);
  assert.strictEqual(retained.prepared, prepared); assert.strictEqual(retained.requested, requested);
  assert.strictEqual(retained.sourceRefusal, sourceRefusal); assert(Object.isFrozen(retained));
  assert.equal(detail.boundary, 'request_admission'); assert.equal(detail.primaryDiagnostic.kind, 'code_site');
  assert.equal(detail.available, true); assert.equal(Object.hasOwn(detail, 'cause'), false);
  assert(detail.primaryDiagnostic.message.split('\n').every(site => /^(?:adapters|packages|_build)\//u.test(site)));
});

test('prepared submission catch keeps undefined and unavailable foreign errors without invoking accessors', () => {
  let touched = 0;
  const proxy = new Proxy({}, {get() {touched++;throw Error('Private get');},
    getOwnPropertyDescriptor() {touched++;throw Error('Private descriptor');}});
  for (const original of [undefined, new TypeError('Private arbitrary text'), proxy]) {
    const failures = new WeakMap(), submission = {preparedProgram: {}}, observed = [];
    let threw = false;
    try {retainPreparedSubmissionFailure(failures, submission, original, undefined, undefined,
      (event, detail) => observed.push({event, detail}));}
    catch (error) {threw = true;assert.strictEqual(error, original);}
    assert(threw); assert.strictEqual(failures.get(submission).error, original);
    assert.deepEqual(observed, [{event: 'preparation_failed', detail: {boundary: 'request_admission', available: false}}]);
  }
  assert.equal(touched, 0);
});

test('prepared submission catch forwards only existing original typed capacity projection', () => {
  // Explicit typed-result port isolates the catch transport, not actual Core
  // funding, normal failure cause or a real Request/Host admission.
  const issue = {}, result = {$tag: 0, _0: issue};
  const moon = {clientProgramRequestSnapshotCapacityRefusal(value) {
    assert.strictEqual(value, result); return {_0: 'request_snapshot', _1: 'retention',
      _2: 9n, _3: 11n, _4: 8n, _5: 12n};
  }};
  let primary;
  try {checkedRequestSnapshotPreparation(moon, result);} catch (error) {primary = error;}
  const original = requestProgramCapacityRefusal(primary), failures = new WeakMap(), submission = {preparedProgram: {}};
  assert(original); assert(Object.isFrozen(original));
  let observed;
  assert.throws(() => retainPreparedSubmissionFailure(failures, submission, primary, {}, undefined,
    (_event, detail) => {observed = detail;}), error => error === primary);
  assert.strictEqual(observed.capacity, original);
  const foreign = Object.assign(Error('Private copied capacity'), {capacity: {...original}});
  assert.equal(requestProgramCapacityRefusal(foreign), undefined);
});

test('prepared submission catch uses existing bounded observer without awaiting its failed callback', async () => {
  const failures = new WeakMap(), submission = {preparedProgram: {}}, primary = {};
  let entered, release, actual;
  const delivered = new Promise(resolve => {entered = resolve;});
  const held = new Promise(resolve => {release = resolve;});
  const observer = createDiagnosticObserver(async (event, detail) => {
    actual = {event, detail, retained: failures.get(submission)}; entered();
    await held;
    throw Error('Optional async delivery failed');
  });
  assert.throws(() => retainPreparedSubmissionFailure(failures, submission, primary, {}, undefined, observer),
    error => error === primary);
  await delivered;
  assert.strictEqual(failures.get(submission).error, primary);
  assert.equal(actual.event, 'preparation_failed'); assert.equal(actual.detail.available, false);
  assert.strictEqual(actual.retained.error, primary);
  assert.equal(observer.status().active, 1);
  release();
  // Observe the existing queue's rejection/finally settlement after this
  // turn, rather than assuming a number of Promise-assimilation microtasks.
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(observer.status().failures, 1);
  assert.equal(observer.status().active, 0); observer.close();
});

// Source forwarding contract only; runtime retention/failure behavior is
// established by the actual imported helper controls above.
test('prepared submission catch forwards its same original association to the imported helper', async () => {
  const source = await readFile(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
  const tree = parse(source, {ecmaVersion: 'latest', sourceType: 'module'}), calls = [];
  const visit = node => {
    if (node === null || typeof node !== 'object') return;
    if (node.type === 'CallExpression' && node.callee.type === 'Identifier' &&
        node.callee.name === 'retainPreparedSubmissionFailure') calls.push(node);
    for (const value of Object.values(node)) {
      if (Array.isArray(value)) value.forEach(visit); else if (value && typeof value === 'object') visit(value);
    }
  };
  visit(tree); assert.equal(calls.length, 1);
  assert.deepEqual(calls[0].arguments.map(value => value.type === 'Identifier' && value.name),
    ['admissionFailures', 'submission', 'error', 'requested', 'sourceRefusal', 'diagnostic']);
});

// Typed result ports isolate JS refusal transport. The actual audience-bound
// same-Request projection below is exercised separately, never fabricated by
// attaching one of these report fixtures to the error or repeating preparation.
function installation(category) {
  let checks = 0, preparations = 0;
  const issue = {private: 'original Request preparation issue'}, result = {$tag: 0, _0: issue};
  const owner = {}, moon = {clientProgramRequestPreparationIssueCode(actual) {
    assert.strictEqual(actual, result); return category;
  }};
  const options = {moon, environment: owner, getFundedPreparation(actual, environment) {
    assert.strictEqual(environment, owner); preparations++;
    return checkedRequestProgramPreparation(moon, result);
  }};
  Object.defineProperty(options, 'check', {get() {
    checks++; assert.fail('Execution must not acquire an independent diagnostic checker');
  }});
  const prepare = installNodeClientProgramPreparation(options);
  return {prepare, get checks() {return checks;}, get preparations() {return preparations;}, issue, moon, owner};
}

for (const [category, code] of [
  ['check_invalid_input', 'ClientProgramInvalidInput'],
  ['check_compile_limit', 'ClientProgramAnalysisLimit'],
  ['check_unsupported', 'ClientProgramImplementationLimit'],
  ['source_rejected', 'ClientProgramRejected'],
  ['source_limit', 'ClientProgramRejected'],
  ['source_unsupported', 'ClientProgramRejected'],
  ['effect_not_supported', 'ClientProgramUnsupported'],
]) test(`original Request ${category} retains its typed code without diagnostic rechecking`, async () => {
  const f = installation(category);
  await assert.rejects(f.prepare(sourceRequest), error => {
    assert.equal(error.code, code, '[request-source-category-private]'); assert.strictEqual(error.cause, f.issue); return true;
  });
  assert.equal(f.preparations, 1); assert.equal(f.checks, 0);
});

for (const [label, report] of [['invalid', invalid], ['partial', {...failed, partial_report: invalid.report}], ['verified', verified], ['failed', failed]]) {
  test(`an unrelated ${label} report cannot replace the original Request refusal`, async () => {
    assert.equal(validCheckOutcome(report), true);
    const f = installation('source_rejected');
    const request = {...sourceRequest, get diagnosticReport() {
      assert.fail('Only the original audience-bound projection may disclose a report');
    }};
    await assert.rejects(f.prepare(request), {code: 'ClientProgramRejected'});
    assert.equal(f.preparations, 1); assert.equal(f.checks, 0);
  });
}

test('successful original Request keeps its owner without serializing or consulting diagnostics', async () => {
  const owner = {}, prepared = {}, cursor = {};
  const prepare = installNodeClientProgramPreparation({moon: {}, environment: owner,
    getFundedPreparation(request, environment) {
      assert.strictEqual(environment, owner);
      return {kind: 'effect_free', prepared, originalInputs: {environment, parametersCursor: cursor}};
    }});
  const request = {...sourceRequest, input: {toJSON() {assert.fail('No second serializer');}}};
  assert.strictEqual(await prepare(request), prepared);
  prepare.assertOwned(prepared); assert.equal(prepare.kindOf(prepared), 'effect_free');
  assert.strictEqual(prepare.originalInputs(prepared).parametersCursor, cursor);
  assert.throws(() => prepare.assertOwned({}), /Foreign/);
});

// Only protocol metadata is echoed by these explicit report ports. They do
// not certify a semantic verdict, compiled Check child or normal Host funding.
function originalObservationChecker(authorize = () => ({action: 'dispatch'})) {
  const environment = {}, cid = 'sha256:' + 'a'.repeat(64), sourceRef = 'fixture:original';
  const moon = {
    clientProgramCheckProgram: () => assert.fail('Original projection must not recheck Program'),
    clientProgramCheckSource: () => assert.fail('Original projection must not recheck text'),
    clientProgramCheckUnavailable: () => JSON.stringify(failed),
    clientProgramCheckCompilerIdentity: () => '{}',
    clientProgramCheckContextIdentity: () => '{}',
    clientProgramCheckingEnvironmentCid: actual => {assert.strictEqual(actual, environment); return cid;},
    clientProgramCheckSourceNamespace: () => assert.fail('No namespace owner selected'),
    clientProgramCheckSourceSelectorNamespace: () => assert.fail('No namespace owner selected'),
  };
  return installNodeClientCheck({moon, environment, contextKey: Buffer.alloc(32, 7),
    publication: {environmentCid: cid, aliases: [{name: 'original', sourceRef}]},
    sourceAccesses: [{sourceRef, resource: 'records', connection: {}, authorization: {authorize}}]});
}
function boundOriginalReport(metadata) {
  const [, context, kind, revision, bytes, declarations, declarationBytes, parameters, parameterBytes] = metadata;
  const outcome = structuredClone(verified);
  outcome.report.context_ref = context; outcome.report.scope = {kind: 'bound_input'};
  outcome.report.inputs = [{document_id: kind === 'program' ? 'program' : 'source',
    kind: kind === 'program' ? 'structured' : 'text', revision, byte_length: bytes},
  ...(declarations === undefined ? [] : [{document_id: 'parameter_declarations', kind: 'structured',
    revision: declarations, byte_length: declarationBytes}]),
  ...(parameters === undefined ? [] : [{document_id: 'parameters', kind: 'structured',
    revision: parameters, byte_length: parameterBytes}])];
  assert.equal(validCheckOutcome(outcome), true); return outcome;
}

test('original Request observation awaits current audience and binds exact UTF8 inputs without rechecking', async () => {
  let enter, release, projected = 0;
  const entered = new Promise(resolve => {enter = resolve;});
  const held = new Promise(resolve => {release = resolve;});
  const checker = originalObservationChecker(async () => {enter(); await held; return {action: 'dispatch'};});
  for (const kind of ['text', 'program']) {
    const request = {principalId: 'original-audience', scope: 'bound_input', kind,
      input: kind === 'text' ? {format: 'sql', text: 'SELECT @name AS name\r\n',
        parameterDeclarations: {name: {type: 'string'}}} : {original: 'e\u0301\r\n日本語'},
      parameters: {name: 'e\u0301\r\n日本語'}};
    let metadata;
    const pending = checker.projectOriginal(request, actual => {
      projected++; metadata = actual; assert.ok(Object.isFrozen(actual));
      assert.equal(actual.length, 13); assert.equal(actual[2], kind);
      assert.equal(actual[4], Buffer.byteLength(kind === 'text' ? request.input.text : JSON.stringify(request.input)));
      assert.equal(actual[8], Buffer.byteLength(JSON.stringify(request.parameters)));
      assert.equal(actual[10], undefined, 'No query-alias to Source-selector cast');
      assert.equal(actual[11], undefined, 'No namespace owner selected');
      assert.equal(actual[12], JSON.stringify(request.parameters), 'Retain the same supplied parameter wire');
      assert.deepEqual(JSON.parse(actual[0]).aliases, [{name: 'original', sourceRef: 'fixture:original'}]);
      return JSON.stringify(boundOriginalReport(actual));
    });
    await entered; if (kind === 'text') {assert.equal(projected, 0); release();}
    const result = await pending;
    assert.equal(result.report.context_ref, metadata[1]);
    assert.match(metadata[1], /^ctx:[0-9a-f]{64}$/u);
    assert.match(metadata[3], /^rev:[0-9a-f]{64}$/u);
  }
  assert.equal(projected, 2);
});

test('original Request observation omits unavailable and refuses stale binding or nonstring without fallback', async () => {
  const checker = originalObservationChecker();
  const request = {principalId: 'original-audience', scope: 'bound_input', kind: 'text',
    input: {format: 'sql', text: 'SELECT 1'}, parameters: null};
  assert.equal(await checker.projectOriginal(request, () => undefined), undefined);
  await assert.rejects(checker.projectOriginal(request, metadata => {
    const outcome = boundOriginalReport(metadata); outcome.report.context_ref = 'ctx:stale';
    return JSON.stringify(outcome);
  }), /InvalidOriginalCheckObservation/u);
  await assert.rejects(checker.projectOriginal(request, () => ({toString() {assert.fail('Do not coerce a result');}})),
    /InvalidOriginalCheckObservation/u);
  assert.throws(() => checker.projectOriginal({...request, scope: 'template_only'}, () => undefined),
    /InvalidOriginalCheckObservation/u);
});


// Exercise the imported submission service with explicit Journal and audience
// ports. These fixtures establish refusal/disclosure call ordering, not actual
// SQLite/Core/Run admission or a physical cleanup acknowledgement.
function refusalPorts(options = {}) {
  const {observationFailure, changedScope = false} = options;
  const report = Object.hasOwn(options, 'report') ? options.report : invalid;
  const events = [], scope = {authorityScopeCid: 'sha256:' + 'a'.repeat(64), namespaceId: 'unit'};
  const submissionRef = {epoch: {version: 'actql-submission-epoch/0.1',
    authorityScopeCid: scope.authorityScopeCid, epochNonce: 'b'.repeat(64),
    notBefore: 1, expiresAt: 2, authenticator: 'c'.repeat(64)}, nonce: 'original'};
  const intentCid = 'sha256:' + 'd'.repeat(64);
  const intentWire = JSON.stringify({kind: 'aql', input: sourceRequest.input, parameters: sourceRequest.parameters});
  const value = {...sourceRequest, submissionRef, intentCid};
  const input = Object.freeze({original: 'fixture submitted intent'});
  let observations = 0, checks = 0, recorded = 0, originalRequest, refusal;
  let retained = options.retained ? {phase: 'not_accepted', intentWire, intentCid, submissionRef,
    outcome: {kind: 'not_accepted', submissionRef, intentCid,
      problem: {code: 'ClientProgramInvalidInput', classification: 'invalid_input'}}} : undefined;
  const sameRef = ref => assert.deepEqual(ref, submissionRef);
  const service = installNodeClientSubmission({
    async authorizedScope(actual) {
      originalRequest ??= actual;
      assert.strictEqual(actual, originalRequest);
      events.push('current');
      return changedScope && observations > 0 ? {...scope, namespaceId: 'changed'} : scope;
    },
    async observeOriginalPreparationFailure(error, actual) {
      assert.strictEqual(error, refusal); assert.strictEqual(actual, originalRequest);
      observations++; events.push('original');
      if (observationFailure) throw observationFailure;
      return report;
    },
    async checkSubmissionInput(actual) {
      assert.deepEqual(actual, {principalId: value.principalId, connection: value.connection,
        kind: 'text', scope: 'bound_input', input: value.input, parameters: value.parameters});
      checks++; events.push('retained-check'); return report;
    },
    async prepareSubmit(actual) {
      assert.equal(actual.requestId, 'original-request');
      assert.deepEqual(actual.input, value.input); sameRef(actual.submissionRef);
      throw refusal;
    },
    submit() {assert.fail('A preparation refusal must not submit a Run');},
    lookupRequest() {assert.fail('A retained refusal must not look up a Run');},
    moon: {
      clientSubmittedIntent(wire) {
        assert.deepEqual(JSON.parse(wire), JSON.parse(intentWire)); return input;
      },
      clientSubmittedIntentCid(actual) {assert.strictEqual(actual, input); return intentCid;},
      clientSubmittedIntentWire(actual) {assert.strictEqual(actual, input); return intentWire;},
    },
    journal: {
      checkSubmittedIntent(ref, actual) {sameRef(ref); assert.strictEqual(actual, input);},
      lookupSubmittedIntent(ref) {sameRef(ref); return retained;},
      verifySubmissionEpoch(epoch) {assert.deepEqual(epoch, submissionRef.epoch); return {validity: 'admissible'};},
      submissionIdentity(epoch, nonce) {
        assert.deepEqual(epoch, submissionRef.epoch); assert.equal(nonce, submissionRef.nonce);
        return {requestId: 'original-request'};
      },
      recordSubmittedIntent(ref, actual, fields) {
        sameRef(ref); assert.strictEqual(actual, input);
        assert.equal(Object.hasOwn(fields.outcome, 'checkObservation'), false);
        recorded++; events.push('record');
        retained = {intentWire, intentCid, submissionRef: ref, phase: fields.phase, outcome: fields.outcome};
        return retained;
      },
    },
  });
  return {events, counts: () => ({observations, checks, recorded}),
    refuse(error) {refusal = error; return service.submitIntent(value);},
    lookup() {return service.lookupSubmission({principalId: value.principalId,
      connection: value.connection, submissionRef});},
  };
}

test('fresh original refusal projects the same checked result across the durable boundary without a semantic recheck', async () => {
  const report = structuredClone(invalid), f = refusalPorts({report});
  const error = Object.assign(new Error('original typed refusal'), {code: 'ClientProgramInvalidInput'});
  const result = await f.refuse(error);
  assert.equal(result.kind, 'not_accepted'); assert.equal(result.problem.code, error.code);
  assert.strictEqual(result.checkObservation, report);
  assert.deepEqual(f.counts(), {observations: 2, checks: 0, recorded: 1});
  assert.ok(f.events.indexOf('original') < f.events.indexOf('record'));
  assert.ok(f.events.lastIndexOf('original') > f.events.indexOf('record'));
});

for (const missing of ['unavailable', 'throw']) {
  test(`fresh original ${missing} projection cannot select a public semantic recheck`, async () => {
    const f = refusalPorts({report: undefined, observationFailure: missing === 'throw' ? Error('reporting unavailable') : undefined});
    const error = Object.assign(new Error('same typed refusal'), {code: 'ClientProgramInvalidInput'});
    const result = await f.refuse(error);
    assert.equal(result.problem.code, 'ClientProgramRejected');
    assert.equal(Object.hasOwn(result, 'checkObservation'), false);
    assert.equal(f.counts().checks, 0); assert.equal(f.counts().recorded, 1);
  });
}

test('fresh original audience change refuses before recording and never rechecks the Program', async () => {
  const f = refusalPorts({changedScope: true});
  await assert.rejects(f.refuse(Object.assign(Error('original'),
    {code: 'ClientProgramInvalidInput'})), {code: 'ClientRequestLookupDenied'});
  assert.deepEqual(f.counts(), {observations: 1, checks: 0, recorded: 0});
});

test('retained disclosure remains a separate current-audience check-only boundary without preparing a Run', async () => {
  const f = refusalPorts({retained: true});
  const result = await f.lookup();
  assert.equal(result.problem.code, 'ClientProgramInvalidInput');
  assert.deepEqual(f.counts(), {observations: 0, checks: 1, recorded: 0});
});
