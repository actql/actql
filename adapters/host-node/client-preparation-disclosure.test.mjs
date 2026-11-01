// Exercise the preparation/diagnostic connection without provider execution.
import assert from 'node:assert/strict';
import test from 'node:test';
import {readFile} from 'node:fs/promises';
import {installNodeClientProgramPreparation} from './client-program-preparation.mjs';
import {installNodeClientCheck} from './client-check.mjs';
import {validCheckOutcome} from '../../packages/client-wire/index.mjs';

const invalid = JSON.parse(await readFile(new URL('../../packages/client-wire/fixtures/check-default-type.invalid.json', import.meta.url), 'utf8'));
const verified = JSON.parse(await readFile(new URL('../../packages/client-wire/fixtures/check-outcome-pins.verified.json', import.meta.url), 'utf8'));
const failed = JSON.parse(await readFile(new URL('../../packages/client-wire/fixtures/check-reporting-failure.json', import.meta.url), 'utf8'));
const sourceRequest = {principalId: 'original-audience', connection: {}, kind: 'aql',
  input: {format: 'sql', text: 'SELECT 1 AS n', parameterDeclarations: {minimum: {type: 'number', default: 'bad'}}},
  parameters: {raw: 'e\u0301\r\n'}};
function installation(category, outcome) {
  let checks = 0, preparations = 0;
  const issue = {private: 'original preparation issue'};
  const owner = {};
  const moon = {
    clientProgramCheckingEnvironmentCid: () => `sha256:${'a'.repeat(64)}`,
    clientProgramPreparePublicSourceEnvironment: environment => Object.freeze({environment}),
    clientProgramPublicSourceEnvironmentMatches: (original, environment) => original.environment === environment,
    clientProgramPrepareEffectFreeWithParameters: () => {preparations++; return {issue, category};},
    clientProgramPreparationReady: value => value.prepared,
    clientProgramPreparationIssue: value => value.issue,
    clientProgramPreparationIssueCode: value => value.category,
    clientProgramPrepareSourceComputationInPublicEnvironment: () => {preparations++; return {pure: {issue, category}};},
    clientProgramSourceComputationPure: value => value.pure,
    clientProgramSourceComputationEffect: value => value.effect,
  };
  const prepare = installNodeClientProgramPreparation({moon, environment: owner,
    check: async request => {
      checks++;
      assert.equal(request.principalId, sourceRequest.principalId);
      assert.deepEqual(request.input, sourceRequest.input);
      assert.deepEqual(request.parameters, sourceRequest.parameters);
      if (outcome instanceof Error) throw outcome;
      return outcome;
    }});
  return {prepare, get checks() {return checks;}, get preparations() {return preparations;}, issue, moon};
}

test('typed common-checker invalid input retains the public input category', async () => {
  const f = installation('check_invalid_input', invalid);
  await assert.rejects(async () => f.prepare({kind: 'program', input: {}, parameters: null}),
    {code: 'ClientProgramInvalidInput'});
  assert.equal(f.checks, 0);
  assert.equal(f.preparations, 1);
});

for (const partial of [false, true]) {
  test(`rejected text exposes only an admitted independent violation (${partial ? 'partial' : 'completed'} report)`, async () => {
    const outcome = partial ? {...failed, partial_report: invalid.report} : invalid;
    assert.equal(validCheckOutcome(outcome), true);
    const f = installation('source_rejected', outcome);
    await assert.rejects(async () => f.prepare(sourceRequest), error => {
      assert.equal(error.code, 'ClientProgramInvalidInput');
      assert.equal(error.message, 'ClientProgramInvalidInput');
      return true;
    });
    assert.equal(f.checks, 1);
    assert.equal(f.preparations, 1);
  });
}

for (const cause of ['absent Source', 'denied Source', 'unavailable', 'report failure', 'malformed report', 'checker exception', 'verified report']) {
  test(`preparation refusal does not invent an input violation from ${cause}`, async () => {
    let outcome = structuredClone(verified);
    if (cause.includes('Source')) {
      outcome.report.verdict = 'undetermined';
      outcome.report.runnable = {verdict: 'no', reasons: [{code: 'unresolved_protected'}]};
      outcome.report.coverage.unresolved = [{boundary: 'source_resolution', reason: 'unresolved_protected'}];
    } else if (cause === 'analysis budget') {
      outcome.report.verdict = 'undetermined';
      outcome.report.coverage.limits = [{code: 'analysis_budget_exhausted'}];
    } else if (cause === 'unavailable') {
      outcome = {...failed, outcome: 'unavailable', problem: {code: 'check_unavailable'}};
    } else if (cause === 'report failure') outcome = failed;
    else if (cause === 'malformed report') {outcome = structuredClone(invalid); delete outcome.report.inputs;}
    else if (cause === 'checker exception') outcome = new Error('private provider detail');
    if (!['malformed report', 'checker exception'].includes(cause)) {
      assert.equal(validCheckOutcome(outcome), true, cause);
    }
    const f = installation('source_rejected', outcome);
    await assert.rejects(async () => f.prepare(sourceRequest), {code: 'ClientProgramRejected'});
    assert.equal(f.preparations, 1);
  });
}

test('successful preparation keeps its owner and never consults explanatory diagnostics', async () => {
  const f = installation('source_rejected', invalid);
  const prepared = {};
  f.moon.clientProgramPrepareSourceComputationInPublicEnvironment = () => ({pure: {prepared}});
  assert.equal(await f.prepare(sourceRequest), prepared);
  f.prepare.assertOwned(prepared);
  assert.equal(f.prepare.kindOf(prepared), 'effect_free');
  assert.throws(() => f.prepare.assertOwned({}), /Foreign/);
  assert.equal(f.checks, 0);
});

test('a protected obligation and a budget do not hide an independent disclosed violation', async () => {
  const outcome = structuredClone(invalid);
  outcome.report.coverage.unresolved = [{boundary: 'source_resolution', reason: 'unresolved_protected'}];
  outcome.report.coverage.limits = [{code: 'analysis_budget_exhausted'}];
  assert.equal(validCheckOutcome(outcome), true);
  const f = installation('source_rejected', outcome);
  await assert.rejects(async () => f.prepare(sourceRequest), {code: 'ClientProgramInvalidInput'});
});

test('an unknown diagnostic reason code does not erase the Owner input verdict', async () => {
  const outcome = structuredClone(invalid);
  outcome.report.reasons = [{code: 'future_input_violation'}];
  assert.equal(validCheckOutcome(outcome), true);
  const f = installation('source_rejected', outcome);
  await assert.rejects(async () => f.prepare(sourceRequest), {code: 'ClientProgramInvalidInput'});
});


test('typed common-checker analysis budget is retained without an input verdict', async () => {
  const f = installation('check_compile_limit', verified);
  await assert.rejects(async () => f.prepare({kind: 'program', input: {}, parameters: null}),
    {code: 'ClientProgramAnalysisLimit'});
  assert.equal(f.checks, 0);
  assert.equal(f.preparations, 1);
});

for (const partial of [false, true]) {
  test(`Source budget disclosure uses an admitted ${partial ? 'partial' : 'completed'} public fact`, async () => {
    const report = structuredClone(verified.report);
    report.verdict = 'undetermined';
    report.runnable = {verdict: 'no', reasons: [{code: 'analysis_budget_exhausted'},
      {code: 'unresolved_protected'}]};
    report.coverage.limits = [{code: 'analysis_budget_exhausted'}];
    report.coverage.unresolved = [{boundary: 'source_resolution', reason: 'unresolved_protected'}];
    const outcome = partial ? {...failed, partial_report: report} : {...verified, report};
    assert.equal(validCheckOutcome(outcome), true);
    for (const category of ['source_limit', 'check_compile_limit', 'source_rejected']) {
      const f = installation(category, outcome);
      await assert.rejects(async () => f.prepare(sourceRequest),
        {code: 'ClientProgramAnalysisLimit'}, '[check-mutation:preparation-budget]');
      assert.equal(f.checks, 1);
      assert.equal(f.preparations, 1);
    }
  });
}

test('raw Source budget remains private without an admitted public budget fact', async () => {
  for (const category of ['source_limit', 'check_compile_limit']) {
    const f = installation(category, verified);
    await assert.rejects(async () => f.prepare(sourceRequest), {code: 'ClientProgramRejected'});
    assert.equal(f.checks, 1);
  }
});


test('typed common-checker implementation limit is distinct from Host feature refusal', async () => {
  const f = installation('check_unsupported', verified);
  await assert.rejects(async () => f.prepare({kind: 'program', input: {}, parameters: null}),
    {code: 'ClientProgramImplementationLimit'});
  assert.equal(f.checks, 0);
});

for (const partial of [false, true]) {
  test(`Source implementation disclosure uses an admitted ${partial ? 'partial' : 'completed'} public fact`, async () => {
    const report = structuredClone(verified.report);
    report.verdict = 'undetermined';
    report.runnable = {verdict: 'no', reasons: [{code: 'implementation_limit'}]};
    report.coverage.limits = [{code: 'implementation_limit'}];
    const outcome = partial ? {...failed, partial_report: report} : {...verified, report};
    assert.equal(validCheckOutcome(outcome), true);
    for (const category of ['source_unsupported', 'source_rejected', 'source_invalid_input', 'check_unsupported']) {
      const f = installation(category, outcome);
      let error;
      try { await f.prepare(sourceRequest); } catch (cause) {error = cause;}
      assert.equal(error?.code, 'ClientProgramImplementationLimit', '[check-mutation:preparation-implementation]');
      assert.equal(f.checks, 1);
    }
  });
}

for (const category of ['source_unsupported', 'source_invalid_input', 'check_unsupported', 'check_invalid_input']) {
  test(`Source ${category} has no public fact without admitted checking evidence`, async () => {
    for (const input of [verified, failed, new Error('private checker failure')]) {
      const f = installation(category, input);
      await assert.rejects(async () => f.prepare(sourceRequest), {code: 'ClientProgramRejected'});
      assert.equal(f.checks, 1);
    }
  });
}

test('independent Host Effect feature refusal is not inferred from checking support', async () => {
  const f = installation('effect_not_supported', verified);
  await assert.rejects(async () => f.prepare(sourceRequest), {code: 'ClientProgramUnsupported'});
  assert.equal(f.checks, 0);
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
      assert.equal(actual.length, 11); assert.equal(actual[2], kind);
      assert.equal(actual[4], Buffer.byteLength(kind === 'text' ? request.input.text : JSON.stringify(request.input)));
      assert.equal(actual[8], Buffer.byteLength(JSON.stringify(request.parameters)));
      assert.equal(actual[10], undefined, 'No query-alias to Source-selector cast');
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
