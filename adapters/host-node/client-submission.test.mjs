import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdtemp, readFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {openClientRequestJournal} from './client-request-journal.mjs';
import {installNodeClientSubmission} from './client-submission.mjs';
import {createNodeInProcessClientHost} from './in-process-client.mjs';
import {validSubmissionLookup, validCheckOutcome} from '../../packages/client-wire/index.mjs';
import {installNodeClientCheck} from './client-check.mjs';
import {installNodeClientProgramPreparation} from './client-program-preparation.mjs';
import {canonicalText} from '../../scripts/check-canonical-json.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';

const valuesWire = JSON.parse(await readFile(new URL(
  '../../packages/sdk/fixtures/values.environment.json', import.meta.url), 'utf8'));
const valuesEnvironment = moon.clientProgramCheckEnvironment(canonicalText(valuesWire),
  valuesWire.evidence_bundle_cid, false, false, true, false, false, false, false);
assert.ok(valuesEnvironment);
const checkValues = installNodeClientCheck({moon, environment: valuesEnvironment});

const authorityScopeCid = `sha256:${'a'.repeat(64)}`;
const connection = {mode: 'local', owner: 'local', durability: 'durable', consentRefs: [], runners: []};
const principalId = 'submission-principal';
const fields = {authorityScopeCid, namespaceId: 'submission-test', currentAuthorization: true};
async function fixture(t, callbacks = {}) {
  const root = await mkdtemp(join(tmpdir(), 'actql-d-submission-connection-'));
  let journal = openClientRequestJournal(root);
  t.after(async () => {journal.close(); await rm(root, {recursive: true, force: true});});
  let authorized = true;
  let prepareCount = 0, submitCount = 0;
  let service;
  const install = () => service = installNodeClientSubmission({journal, moon,
    authorizedScope: () => authorized ? fields : undefined,
    prepareSubmit: async value => {prepareCount++; return callbacks.prepare?.(value) ?? {};},
    submit: async value => {submitCount++; return await callbacks.submit(value);},
    lookupRequest: async value => callbacks.lookup?.(value) ?? {kind: 'not_found'},
    checkSubmissionInput: callbacks.check ?? checkValues,
  });
  install();
  const ref = {epoch: await service.issueEpoch({principalId, connection}), nonce: 'original-nonce'};
  const body = (text = 'SELECT 1 AS value') => {
    const source = {kind: 'aql', input: {format: 'aql-text', text}, parameters: null};
    const intent = moon.clientSubmittedIntent(JSON.stringify(source), 1048576, 65536, 64);
    return {principalId, connection, submissionRef: ref, intentCid: moon.clientSubmittedIntentCid(intent), ...source};
  };
  const port = () => createNodeInProcessClientHost({authenticate: () => principalId,
    authorizeConnection: () => authorized, negotiate: () => undefined,
    submitIntent: service.submitIntent, lookupSubmission: service.lookupSubmission, maxRowBytes: 65536});
  return {root, ref, body, port, get journal() {return journal;}, get service() {return service;},
    get counts() {return {prepare: prepareCount, submit: submitCount};},
    authorize: value => {authorized = value;}, restart() {journal.close(); journal = openClientRequestJournal(root); install();}};
}

function admitOriginal(f, value) {
  const cid = value => 'sha256:' + createHash('sha256').update(canonicalText(value)).digest('hex');
  const fixed = digit => 'sha256:' + digit.repeat(64);
  const program = fixed('1'), parameters = fixed('2'), input = fixed('3');
  const identity = moon.clientRequestAdmitRecord(authorityScopeCid, value.requestId,
    program, parameters, input,
    cid({version: 'actql-logical-request/0.1', authority_scope_cid: authorityScopeCid,
      caller_request_id: value.requestId}),
    cid({version: 'actql-logical-request-intent/0.1', program_definition_cid: program,
      parameter_values_cid: parameters, caller_input_intent_cid: input}));
  assert.ok(identity);
  const control = runtimeCore(moon).publicationControl;
  const definition = control.seal('run_definition', JSON.stringify({
    version: 'actql-run-definition/0.1', scope_id: 'submission-test-scope', run_id: 'original-run',
    compiled_plan_cid: fixed('4'), invocation_template_cid: fixed('5'),
    authorization_context_cid: fixed('6'), input_artifact_set_cid: fixed('7'),
    created_at: '2026-10-07T00:00:00.000Z', valid_until: '2098-01-01T00:00:00.000Z',
  }), {maxWireBytes: 65536, maxNodes: 4096, maxDepth: 64});
  const accepted = f.journal.acceptDefinition(identity, {namespaceId: fields.namespaceId,
    runDefinition: definition, lookupExpiresAt: '2099-01-01T00:00:00.000Z',
    submission: value.submission}, moon, control);
  return {ref: accepted.ref, durability: accepted.durability, revision: accepted.revision};
}

test('ready lookup stays read-only while explicit replay re-enters the original Run owner after restart', async t => {
  let f;
  f = await fixture(t, {submit: value => admitOriginal(f, value), lookup(value) {
    const admitted = f.journal.lookup({...fields, requestId: value.requestId}, moon);
    return admitted === undefined ? {kind: 'not_found'} : {kind: 'found', ref: admitted.ref};
  }});
  const original = await f.service.submitIntent(f.body());
  assert.equal(original.kind, 'ready');
  f.restart();
  assert.deepEqual(await f.service.lookupSubmission({principalId, connection, submissionRef: f.ref}), original);
  assert.deepEqual(f.counts, {prepare: 1, submit: 1}, 'lookup does not resume physical work');
  assert.deepEqual(await f.service.submitIntent(f.body()), original);
  assert.deepEqual(f.counts, {prepare: 2, submit: 2}, 'explicit replay reaches the existing Run owner');
  await assert.rejects(f.service.submitIntent(f.body('SELECT 2 AS value')), {code: 'ClientSubmittedIntentConflict'});
  assert.deepEqual(f.counts, {prepare: 2, submit: 2}, 'changed intent never enters the Run owner');
});

test('ready replay rechecks current authority after awaited preparation and retains its original receipt', async t => {
  let f, preparations = 0;
  f = await fixture(t, {async prepare() {
    preparations++;
    if (preparations === 2) {await Promise.resolve(); f.authorize(false);}
    return {};
  }, submit: value => admitOriginal(f, value), lookup(value) {
    const admitted = f.journal.lookup({...fields, requestId: value.requestId}, moon);
    return admitted === undefined ? {kind: 'not_found'} : {kind: 'found', ref: admitted.ref};
  }});
  const original = await f.service.submitIntent(f.body());
  await assert.rejects(f.service.submitIntent(f.body()), {code: 'ClientRequestLookupDenied'});
  assert.deepEqual(f.counts, {prepare: 2, submit: 1});
  f.authorize(true);
  f.restart();
  assert.deepEqual(await f.service.lookupSubmission({principalId, connection, submissionRef: f.ref}), original);
});

test('public Local submission lookup returns a durable pre-admission refusal after restart', async t => {
  const f = await fixture(t, {prepare() {throw Object.assign(new Error('invalid fixture'), {code: 'ClientProgramInvalidInput'});}});
  const body = f.body('SELECT (');
  const {principalId: ignored, ...wireBody} = body;
  const reply = await f.port().perform('submit-intent', wireBody);
  assert.equal(reply.kind, 'not_accepted');
  assert.equal(reply.problem.classification, 'invalid_input');
  assert.deepEqual(f.counts, {prepare: 1, submit: 0});
  f.restart();
  const restored = await f.port().perform('lookup-submission', {connection, submissionRef: f.ref});
  assert.deepEqual(restored, reply);
  assert.equal(validSubmissionLookup(restored, connection, f.ref), true);
  assert.deepEqual(await f.port().perform('submit-intent', wireBody), reply);
  assert.deepEqual(f.counts, {prepare: 1, submit: 0});
  await assert.rejects(f.service.submitIntent(f.body('SELECT 1 AS value')), {code: 'ClientSubmittedIntentConflict'});
});

test('retained Source input problems recheck original intent and current disclosure without preparation', async t => {
  const wire = JSON.parse(await readFile(new URL(
    './fixtures/query-amount-environment.json', import.meta.url), 'utf8'));
  const environment = moon.clientProgramCheckEnvironment(canonicalText(wire),
    wire.evidence_bundle_cid, false, false, true, true, false, false, false);
  assert.ok(environment);
  const view = wire.source_views[0];
  const sourceRef = 'connector://crm/main/r#v';
  const publication = {environmentCid: moon.clientProgramCheckingEnvironmentCid(environment),
    aliases: [{name: 'records', sourceRef, sourceViewContractCid: view.contract_cid,
      schemaContractCid: view.output.schema.cid}]};
  let visible = true, checks = 0;
  const checker = installNodeClientCheck({moon, environment, publication,
    sourceAccesses: [{sourceRef, resource: 'records', connection: {}, authorization: {
      authorize() {return {action: visible ? 'dispatch' : 'deny'};},
    }}]});
  const prepare = installNodeClientProgramPreparation({moon, environment, sourcePublication: publication});
  const f = await fixture(t, {prepare, check(value) {
    checks++;
    assert.deepEqual(value.input, {format: 'aql-text', text: 'SELECT missing AS n FROM records'});
    assert.equal(value.parameters, null);
    return checker(value);
  }});
  const expected = {code: 'ClientProgramInvalidInput', classification: 'invalid_input'};
  const first = await f.service.submitIntent(f.body('SELECT missing AS n FROM records'));
  assert.deepEqual(first.problem, expected, '[check-mutation:submission-disclosure]');
  f.restart();
  visible = false;
  const hidden = await f.service.lookupSubmission({principalId, connection, submissionRef: f.ref});
  assert.deepEqual(hidden.problem, {code: 'ClientProgramRejected', classification: 'operation_failed'},
    '[check-mutation:submission-disclosure]');
  assert.equal(hidden.kind, 'not_accepted');
  assert.deepEqual(hidden.submissionRef, first.submissionRef);
  assert.deepEqual(await f.service.submitIntent(f.body('SELECT missing AS n FROM records')), hidden);
  visible = true;
  const restored = await f.service.lookupSubmission({principalId, connection, submissionRef: f.ref});
  assert.deepEqual(restored, first, '[check-mutation:submission-disclosure]');
  assert.deepEqual(f.counts, {prepare: 1, submit: 0});
  assert.ok(checks >= 4);
});

test('submission disclosure retains an admitted partial invalid report across original lookup', async t => {
  const failed = JSON.parse(await readFile(new URL(
    '../../packages/client-wire/fixtures/check-reporting-failure.json', import.meta.url), 'utf8'));
  const f = await fixture(t, {prepare() {
    throw Object.assign(new Error('typed input fixture'), {code: 'ClientProgramInvalidInput'});
  }, async check(value) {
    const completed = await checkValues(value);
    const partial = {...failed, partial_report: completed.report};
    assert.equal(validCheckOutcome(partial), true);
    return partial;
  }});
  const first = await f.service.submitIntent(f.body('SELECT missing AS n'));
  assert.deepEqual(first.problem, {code: 'ClientProgramInvalidInput', classification: 'invalid_input'});
  f.restart();
  assert.deepEqual(await f.service.lookupSubmission({principalId, connection, submissionRef: f.ref}), first);
  assert.deepEqual(f.counts, {prepare: 1, submit: 0});
});

test('submission disclosure refuses authorization lost during its awaited check', async t => {
  let entered, resume;
  const checking = new Promise(resolve => {entered = resolve;});
  const paused = new Promise(resolve => {resume = resolve;});
  let calls = 0;
  const f = await fixture(t, {prepare() {
    throw Object.assign(new Error('typed input fixture'), {code: 'ClientProgramInvalidInput'});
  }, async check(value) {
    if (++calls === 1) {entered(); await paused;}
    return checkValues(value);
  }});
  const pending = f.service.submitIntent(f.body('SELECT missing AS n'));
  await checking;
  f.authorize(false); resume();
  await assert.rejects(pending, {code: 'ClientRequestLookupDenied'});
  assert.deepEqual(f.counts, {prepare: 1, submit: 0});
  f.authorize(true);
  const original = await f.service.lookupSubmission({principalId, connection, submissionRef: f.ref});
  assert.equal(original.kind, 'unresolvable');
});

for (const mode of ['undetermined', 'failed', 'unavailable', 'malformed', 'exception', 'missing']) {
  test(`submission disclosure does not derive invalid input from ${mode} reporting`, async t => {
    const f = await fixture(t, {prepare() {
      throw Object.assign(new Error('typed input fixture'), {code: 'ClientProgramInvalidInput'});
    }, async check(value) {
      if (mode === 'missing') return undefined;
      if (mode === 'exception') throw new Error('private-reporting-failure');
      if (mode === 'unavailable') return checkValues.unavailable();
      const report = await checkValues(value);
      if (mode === 'malformed') return {...report, outcome: 'malformed'};
      if (mode === 'failed') return {...report, outcome: 'failed'};
      return checkValues({...value, input: {format: 'sql', text: 'SELECT id FROM absent'}});
    }});
    const result = await f.service.submitIntent(f.body('SELECT missing AS n'));
    assert.equal(result.kind, 'not_accepted');
    assert.deepEqual(result.problem, {code: 'ClientProgramRejected', classification: 'operation_failed'},
      '[check-mutation:submission-reporting]');
    f.restart();
    assert.deepEqual(await f.service.lookupSubmission({principalId, connection, submissionRef: f.ref}), result);
    assert.deepEqual(f.counts, {prepare: 1, submit: 0});
  });
}

test('accepted preparation failure remains accepted with no invented Run identity', async t => {
  const f = await fixture(t, {submit() {throw Object.assign(new Error('missing fixture input'), {code: 'ClientProgramNeedsInputs'});}});
  const reply = await f.service.submitIntent(f.body());
  assert.equal(reply.kind, 'preparation_failed');
  assert.equal(reply.problem.classification, 'requirements');
  assert.equal('ref' in reply, false);
  f.restart();
  assert.deepEqual(await f.service.lookupSubmission({principalId, connection, submissionRef: f.ref}), reply);
  assert.deepEqual(await f.service.submitIntent(f.body()), reply);
  assert.deepEqual(f.counts, {prepare: 1, submit: 1});
});

test('unclassified interruption leaves Preparing and lookup never dispatches work', async t => {
  const f = await fixture(t, {submit() {throw new Error('fixture lost transport');}});
  await assert.rejects(f.service.submitIntent(f.body()), /fixture lost transport/);
  f.restart();
  const restored = await f.service.lookupSubmission({principalId, connection, submissionRef: f.ref});
  assert.equal(restored.kind, 'preparing');
  assert.deepEqual(restored.submissionRef, f.ref);
  assert.equal('ref' in restored, false);
  assert.deepEqual(f.counts, {prepare: 1, submit: 1});
});

test('unknown original identity is unresolvable rather than evidence of nonexecution', async t => {
  const f = await fixture(t);
  const found = await f.service.lookupSubmission({principalId, connection, submissionRef: f.ref});
  assert.equal(found.kind, 'unresolvable');
  assert.deepEqual(f.counts, {prepare: 0, submit: 0});
});

test('intent digest mismatch is refused before preparation or admission', async t => {
  const f = await fixture(t);
  await assert.rejects(f.service.submitIntent({...f.body(), intentCid: `sha256:${'0'.repeat(64)}`}),
    {code: 'InvalidClientSubmittedIntent'});
  assert.deepEqual(f.counts, {prepare: 0, submit: 0});
  assert.equal(f.journal.lookupSubmittedIntent(f.ref, fields, moon), undefined);
});

test('Local ingress owns nested submission values before authentication awaits', async t => {
  const f = await fixture(t, {prepare(value) {
    assert.equal(value.input.text, 'SELECT 1 AS value');
    throw Object.assign(new Error('fixture preflight'), {code: 'ClientProgramUnsupported'});
  }});
  let release;
  const authentication = new Promise(resolve => {release = resolve;});
  const port = createNodeInProcessClientHost({authenticate: () => authentication,
    authorizeConnection: () => true, negotiate: () => undefined, submitIntent: f.service.submitIntent,
    lookupSubmission: f.service.lookupSubmission, maxRowBytes: 65536});
  const {principalId: ignored, ...body} = f.body();
  const pending = port.perform('submit-intent', body);
  body.input.text = 'SELECT changed AS value';
  body.submissionRef.nonce = 'changed-nonce';
  release(principalId);
  const result = await pending;
  assert.equal(result.kind, 'not_accepted');
  assert.equal(result.submissionRef.nonce, 'original-nonce');
  assert.deepEqual(f.counts, {prepare: 1, submit: 0});
});

test('current authorization is checked again after awaited preparation', async t => {
  let f;
  f = await fixture(t, {prepare: async () => {await Promise.resolve(); f.authorize(false); return {};}});
  await assert.rejects(f.service.submitIntent(f.body()), {code: 'ClientRequestLookupDenied'});
  assert.deepEqual(f.counts, {prepare: 1, submit: 0});
  f.authorize(true);
  assert.equal(f.journal.lookupSubmittedIntent(f.ref, fields, moon), undefined);
});
