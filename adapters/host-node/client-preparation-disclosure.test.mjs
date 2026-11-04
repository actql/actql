// Original Request refusal and audience projection are separate original
// observations. The execution installer never invokes an independent checker.
import assert from 'node:assert/strict';
import test from 'node:test';
import {readFile} from 'node:fs/promises';
import {parse} from 'acorn';
import {installNodeClientProgramPreparation, checkedRequestProgramPreparation} from './client-program-preparation.mjs';
import {installNodeClientCheck} from './client-check.mjs';
import {validCheckOutcome, isClientSubmitRejection} from '../../packages/client-wire/index.mjs';

const invalid = JSON.parse(await readFile(new URL('../../packages/client-wire/fixtures/check-default-type.invalid.json', import.meta.url), 'utf8'));
const verified = JSON.parse(await readFile(new URL('../../packages/client-wire/fixtures/check-outcome-pins.verified.json', import.meta.url), 'utf8'));
const failed = JSON.parse(await readFile(new URL('../../packages/client-wire/fixtures/check-reporting-failure.json', import.meta.url), 'utf8'));
const sourceRequest = {principalId: 'original-audience', connection: {}, kind: 'aql',
  input: {format: 'sql', text: 'SELECT 1 AS n', parameterDeclarations: {minimum: {type: 'number', default: 'bad'}}},
  parameters: {raw: 'e\u0301\r\n'}};

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


// Extract the actual closed refusal/disclosure functions. Explicit Journal and
// audience ports isolate call ordering; no SQLite/Core/Run or cleanup ACK is
// claimed. The generated bodies are neither copied implementations nor a
// second preparation path.
const submissionSource = await readFile(new URL('./client-submission.mjs', import.meta.url), 'utf8');
const submissionAst = parse(submissionSource, {ecmaVersion: 'latest', sourceType: 'module'});
function actualInitializer(name) {
  let found;
  const visit = node => {
    if (!node || typeof node !== 'object') return;
    if (node.type === 'VariableDeclarator' && node.id?.name === name) {
      assert.equal(found, undefined, `unique original ${name}`); found = node.init;
    }
    for (const value of Object.values(node)) {
      if (Array.isArray(value)) value.forEach(visit);
      else if (value && typeof value === 'object') visit(value);
    }
  };
  visit(submissionAst); assert.ok(found, name);
  return submissionSource.slice(found.start, found.end);
}
const actualRefusal = new Function('ports', `
  const {authorize, observeOriginalPreparationFailure, checkSubmissionInput,
    journal, value, input, moon, retained, attempt, restartFields, storedOutcome,
    validCheckOutcome, isClientSubmitRejection, fail} = ports;
  const classification = ${actualInitializer('classification')};
  const immutable = ${actualInitializer('immutable')};
  const supportsCheckObservation = ${actualInitializer('supportsCheckObservation')};
  const discloseOutcome = ${actualInitializer('discloseOutcome')};
  const retainPreparationRefusal = ${actualInitializer('retainPreparationRefusal')};
  return {discloseOutcome, retainPreparationRefusal};
`);
function refusalPorts(options = {}) {
  const {observationFailure, changedScope = false} = options;
  const report = Object.hasOwn(options, 'report') ? options.report : invalid;
  const events = [], scope = {authorityScopeCid: 'sha256:' + 'a'.repeat(64), namespaceId: 'unit'};
  const intentWire = JSON.stringify({kind: 'aql', input: sourceRequest.input, parameters: sourceRequest.parameters});
  const value = {...sourceRequest, submissionRef: {}, intentCid: 'fixture-intent'};
  let observations = 0, checks = 0, recorded = 0;
  const ports = {value, input: {}, validCheckOutcome, isClientSubmitRejection,
    fail(code) {throw Object.assign(new Error(code), {code});},
    async authorize() {
      events.push('current');
      return changedScope && observations > 0 ? {...scope, namespaceId: 'changed'} : scope;
    },
    async observeOriginalPreparationFailure(error, actual) {
      assert.strictEqual(actual, value); observations++; events.push('original');
      if (observationFailure) throw observationFailure;
      return report;
    },
    async checkSubmissionInput() {checks++; events.push('retained-check'); return report;},
    moon: {clientSubmittedIntentWire() {return intentWire;}},
    restartFields: current => current,
    storedOutcome: retained => retained.outcome,
    journal: {recordSubmittedIntent(ref, input, fields) {
      assert.strictEqual(ref, value.submissionRef); recorded++; events.push('record');
      return {intentWire, outcome: fields.outcome};
    }},
  };
  return {...actualRefusal(ports), ports, scope, events,
    counts: () => ({observations, checks, recorded})};
}

test('fresh original refusal projects the same checked result across the durable boundary without a semantic recheck', async () => {
  const report = structuredClone(invalid), f = refusalPorts({report});
  const error = Object.assign(new Error('original typed refusal'), {code: 'ClientProgramInvalidInput'});
  const result = await f.retainPreparationRefusal(error);
  assert.equal(result.kind, 'not_accepted'); assert.equal(result.problem.code, error.code);
  assert.strictEqual(result.checkObservation, report);
  assert.deepEqual(f.counts(), {observations: 2, checks: 0, recorded: 1});
  assert.ok(f.events.indexOf('original') < f.events.indexOf('record'));
  assert.ok(f.events.lastIndexOf('original') > f.events.indexOf('record'));
});

for (const missing of ['unavailable', 'throw']) {
  test(`fresh original ${missing} projection cannot select a public semantic recheck`, async () => {
    const f = refusalPorts({report: undefined, observationFailure: missing === 'throw' ? Error('reporting unavailable') : undefined});
    const actual = actualRefusal(f.ports);
    const error = Object.assign(new Error('same typed refusal'), {code: 'ClientProgramInvalidInput'});
    const result = await actual.retainPreparationRefusal(error);
    assert.equal(result.problem.code, 'ClientProgramRejected');
    assert.equal(Object.hasOwn(result, 'checkObservation'), false);
    assert.equal(f.counts().checks, 0); assert.equal(f.counts().recorded, 1);
  });
}

test('fresh original audience change refuses before recording and never rechecks the Program', async () => {
  const f = refusalPorts({changedScope: true});
  await assert.rejects(f.retainPreparationRefusal(Object.assign(Error('original'),
    {code: 'ClientProgramInvalidInput'})), {code: 'ClientRequestLookupDenied'});
  assert.deepEqual(f.counts(), {observations: 1, checks: 0, recorded: 0});
});

test('retained disclosure remains a separate current-audience check-only boundary without preparing a Run', async () => {
  const f = refusalPorts();
  const result = await f.discloseOutcome(f.ports.value,
    {kind: 'not_accepted', problem: {code: 'ClientProgramInvalidInput', classification: 'invalid_input'}},
    f.scope, {intentWire: f.ports.moon.clientSubmittedIntentWire()});
  assert.equal(result.problem.code, 'ClientProgramInvalidInput');
  assert.deepEqual(f.counts(), {observations: 0, checks: 1, recorded: 0});
});
