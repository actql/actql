import {publicationOriginalFixture} from './fixtures/local-publication-original.mjs';
// Actual preparation, checked Run issuance and SQLite acceptance, without
// physical dispatch. Reply loss never supplies evidence of nonacceptance.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdir, mkdtemp, readFile, rm} from 'node:fs/promises';
import {createServer} from 'node:https';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import test, {after} from 'node:test';
import * as sdk from '../../packages/sdk/index.mjs';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {createClientHttpHandler} from './client-http.mjs';
import {installNodeClientCheck} from './client-check.mjs';
import {createNodeInProcessClientHost} from './in-process-client.mjs';
import {openClientRequestJournal} from './client-request-journal.mjs';
import {openFundedClientPreparation} from './funded-client-preparation.fixture.mjs';
import {installNodeClientRequestLookup} from './client-request-lookup.mjs';
import {installNodeClientSubmission} from './client-submission.mjs';
import {sourceFreeValuesPlan} from './local-values-plan.mjs';
import {createNodeAuthorizationGate} from './authorization.mjs';
import {canonicalText} from '../../scripts/check-canonical-json.mjs';
import {runtimeOptionalField, runtimeTag} from '../host-common/compiler-binding.generated.mjs';

const scratch = new URL('../../_build/client-submission-input-tests/', import.meta.url).pathname;
await mkdir(scratch, {recursive: true});
const tlsRoot = await mkdtemp(join(scratch, 'tls-'));
execFileSync('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048',
  '-keyout', 'remote.key', '-out', 'remote.crt', '-days', '1',
  '-subj', '/CN=localhost', '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'],
{cwd: tlsRoot, stdio: 'ignore'});
const tlsKey = await readFile(join(tlsRoot, 'remote.key'));
const tlsCertificate = await readFile(join(tlsRoot, 'remote.crt'));
setDefaultCACertificates([...getCACertificates('default'), tlsCertificate.toString('utf8')]);
after(() => rm(tlsRoot, {recursive: true, force: true}));
const document = await readFile(new URL('../../packages/sdk/fixtures/values.json', import.meta.url), 'utf8');
const environmentWire = await readFile(new URL('../../packages/sdk/fixtures/values.environment.json', import.meta.url), 'utf8');
const environment = moon.clientProgramCheckEnvironment(environmentWire.trimEnd(),
  'sha256:aa727ea3fb169143aa8b774d7ee16679166cdae133c990a128921eaad0c3d904',
  false, false, true, false, false, false, false);
assert.ok(environment);
const control = runtimeCore(moon).publicationControl;
const cid = digit => `sha256:${digit.repeat(64)}`;
const scope = {namespaceId: 'namespace-a', authorityScopeCid: cid('a')};
// Assemble the documented preimages independently of the product's identity
// helpers; the Host supplies the authenticated epoch fields, not this digest.
const submissionRequestId = ({epoch, nonce}) => {
  const digest = value => 'sha256:' + createHash('sha256').update(JSON.stringify(value)).digest('hex');
  const epochCid = digest({authority_scope_cid: epoch.authorityScopeCid,
    epoch_nonce: epoch.epochNonce, expires_at: epoch.expiresAt,
    not_before: epoch.notBefore, version: 'actql-submission-epoch/0.1'});
  return digest({caller_nonce: nonce, epoch_cid: epochCid,
    version: 'actql-submission-identity/0.1'});
};
const notAccepted = code => error => {
  assert.equal(error.code, 'SubmissionNotAccepted');
  const outcome = sdk.getSubmissionOutcome(error);
  assert.equal(outcome.kind, 'not_accepted');
  assert.equal(outcome.problem.code, code);
  assert.deepEqual(outcome.submissionRef, sdk.getSubmissionInput(error).submissionRef);
  return true;
};
// These actual Request failures precede an original semantic CheckOutcome.
// Preserve the SDK's owned input/phase without manufacturing a report or
// invoking a second checker to obtain a verdict, limits or text coordinates.
function assertOriginalPreparationRefusal(fixture, error, program) {
  assert.equal(error?.code, 'SubmissionNotAccepted');
  const outcome = sdk.getSubmissionOutcome(error), input = sdk.getSubmissionInput(error);
  assert.equal(outcome?.kind, 'not_accepted');
  assert.equal(input.kind, 'program');
  assert.deepEqual(input.input, program);
  assert.deepEqual(Object.keys(input.input), Object.keys(program));
  assert.notStrictEqual(input.input, program);
  assert.equal(Object.isFrozen(input), true); assert.equal(Object.isFrozen(input.input), true);
  assert.deepEqual(outcome.submissionRef, input.submissionRef);
  const before = [...fixture.operations];
  const checked = sdk.getSubmissionCheckObservation(error);
  assert.equal(checked, undefined, '[check-mutation:program-presemantic-observation]');
  assert.equal(sdk.getCheckInput(checked, 'program'), undefined);
  assert.equal(sdk.getCheckFixes(checked), undefined);
  assert.equal(sdk.getSubmissionCheckObservation(structuredClone(error)), undefined);
  assert.equal(sdk.getSubmissionInput({...error}), undefined);
  assert.equal(sdk.getSubmissionOutcome({...error}), undefined);
  assert.strictEqual(sdk.getSubmissionInput(error), input);
  assert.deepEqual(fixture.operations, before, '[check-mutation:program-presemantic-passive]');
  assert.deepEqual(fixture.stored(), []);
  assert.deepEqual(fixture.counts(), {submits:0, issues:0});
}
const profile = {version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
  durability: 'durable', scopeRef: 'principal-a', capabilities: ['aql-document'],
  limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024,
    maxRowRetainedValueBytes: 1024, maxRetainedValueBytes: 4096,
    maxRows: 10, maxBatchRows: 10, maxBatchRetainedValueBytes: 2048}};

async function fixture(t, entrance, loss, {checkingEnvironment = environment, publication, sourceAccesses = []} = {}) {
  const directory = await mkdtemp(join(scratch, 'request-'));
  const journal = openClientRequestJournal(directory);
  const submissionEpoch = journal.issueSubmissionEpoch({...scope, currentAuthorization: true}, moon);
  const observer = new DatabaseSync(join(directory, 'client-requests.sqlite3'), {readOnly: true});
  let client, server, funded, authorized = true, submits = 0, issues = 0;
  let endpoint = 'actql:embedded';
  const operations = [], received = [];
  let credentials = 0, authentications = 0, preparations = 0, pause;
  const beforeBoundary = async () => {
    const pending = pause; pause = undefined;
    if (pending) await pending;
  };
  // Register teardown before opening the actual Request preparation owner.
  t.after(async () => {
    await client?.close();
    if (server) {
      server.closeAllConnections();
      await new Promise(resolve => server.close(resolve));
    }
    // No ingress or original HTTP handler may outlive its Request parent.
    await funded?.close();
    observer.close();
    journal.close();
    await rm(directory, {recursive: true, force: true});
  });
  funded = await openFundedClientPreparation({moon, environment: checkingEnvironment,
    http: entrance === 'https'});
  const prepare = entrance === 'https' ? funded.prepareSubmit : funded.prepare;
  // This routes DATA to the existing owner, never certifies a failure/report.
  // The nested original SubmissionRef distinguishes concurrent calls even if
  // a caller throws the same Error object; the manager still checks identity.
  const failedRequests = new WeakMap();
  let diagnosticRecords = 0;
  const diagnose = detail => {
    if (process.env.ACTQL_TEST_PREPARATION_DIAGNOSTICS !== '1') return;
    if (diagnosticRecords >= 12) return;
    diagnosticRecords++;
    try {t.diagnostic(`ACTQL_PREPARATION_ORIGINAL ${JSON.stringify(detail)}`);}
    catch { /* Diagnostic delivery cannot replace the original operation. */ }
  };
  const prepareSubmit = Object.freeze(Object.assign(async request => {
    preparations++;
    received.push(structuredClone({input: request.input, parameters: request.parameters}));
    const originalRequest = entrance === 'https' ? funded.originalRequest(request) : request;
    try {return await prepare(request);}
    catch (failure) {
      // The existing adapter preserves the original Core terminal in cause.
      // Record only three compiler tags, never constructor payloads, inputs,
      // Error strings, opaque references or a reconstructed Result. These
      // diagnostics neither classify the public failure nor change its oracle.
      try {
        const terminal = Object.getOwnPropertyDescriptor(failure, 'cause')?.value;
        const detail = runtimeOptionalField(terminal, 0);
        const nested = runtimeOptionalField(detail, 0);
        diagnose({port: 'prepareSubmit.catch', tags: [terminal, detail, nested].map(value => {
          const tag = runtimeTag(value);
          return Number.isSafeInteger(tag) && tag >= 0 && tag <= 65535 ? tag : null;
        })});
      } catch {
        // Missing diagnostic shape cannot replace the same original failure.
      }
      if (failure !== null && (typeof failure === 'object' || typeof failure === 'function') &&
          request.submissionRef !== null && typeof request.submissionRef === 'object') {
        let requests = failedRequests.get(failure);
        if (requests === undefined) {requests = new WeakMap(); failedRequests.set(failure, requests);}
        requests.set(request.submissionRef, originalRequest);
      }
      throw failure;
    }
  }, {assertSubmittedIntent: prepare.assertSubmittedIntent}));
  const check = installNodeClientCheck({moon, environment: checkingEnvironment, publication, sourceAccesses});
  const configuration = {
    authenticate: async () => {
      authentications++;
      if (entrance === 'local') await beforeBoundary();
      return 'principal-a';
    },
    authorizeConnection: () => authorized,
    negotiate: () => ({...profile, submissionEpoch}),
    prepareSubmit,
    ...(entrance === 'https' ? {prepareRequest: funded.prepareRequest} : {}),
    check: Object.assign(request => {
      received.push(structuredClone({input: request.input, parameters: request.parameters}));
      return check(request);
    }, {unavailable: check.unavailable}),
    async submit({preparedProgram, requestId, submission}) {
      submits++;
      const identity = moon.clientProgramRequestIdentity(preparedProgram,
        scope.authorityScopeCid, requestId, cid('b'));
      assert.ok(identity);
      const accepted = await journal.admitOrLookupDefinition(identity, {
        namespaceId: scope.namespaceId, submission,
        lookupExpiresAt: '2099-01-01T00:00:00.000Z',
        issueDefinition: () => {
          issues++;
          return sourceFreeValuesPlan({moon, control, preparedProgram, publicationOriginal: publicationOriginalFixture(moon, preparedProgram),
            ...scope, storeAuthorityCid: cid('7'),
            now: () => '2026-10-04T00:00:00.000Z'}).runDefinition;
        },
      }, moon, control);
      return {ref: accepted.ref, durability: 'durable', revision: accepted.revision};
    },
    lookupRequest: installNodeClientRequestLookup({journal, control: moon,
      authorizedScope: () => authorized ? scope : undefined}),
    maxRowBytes: 1024,
  };
  const submission = installNodeClientSubmission({journal, moon,
    ...(entrance === 'https' ? funded.submission : {}),
    authorizedScope: () => authorized ? scope : undefined,
    prepareSubmit: configuration.prepareSubmit, submit: configuration.submit,
    lookupRequest: configuration.lookupRequest, checkSubmissionInput: check,
    async observeOriginalPreparationFailure(failure, value) {
      const request = failedRequests.get(failure)?.get(value.submissionRef);
      if (request === undefined) return undefined;
      const current = () => {
        if (!authorized) throw Object.assign(new Error('ClientConnectionDenied'), {code: 'ClientConnectionDenied'});
      };
      current();
      const outcome = await funded.manager.observeOriginalCheckOutcome(request, failure, project =>
        check.projectOriginal({principalId: value.principalId, connection: value.connection,
          kind: value.kind === 'program' ? 'program' : 'text', scope: 'bound_input',
          input: value.input, parameters: value.parameters, signal: value.signal}, project));
      current();
      diagnose({port: 'observeOriginalCheckOutcome.return', defined: outcome !== undefined});
      return outcome;
    }});
  Object.assign(configuration, {submitIntent: submission.submitAttempt,
    lookupSubmission: submission.lookupSubmission});
  let pendingLoss = loss;
  if (entrance === 'local') {
    const port = createNodeInProcessClientHost(configuration);
    client = await sdk.connectInProcess({mode: 'local', owner: 'local'}, {
      async perform(operation, body, signal) {
        operations.push(operation);
        const phase = operation === 'submit-intent' ? pendingLoss : undefined;
        if (phase) pendingLoss = undefined;
        if (phase === 'before-dispatch') throw new Error('private-submission-cause');
        const answer = await port.perform(operation, body, signal);
        if (phase === 'after-commit') throw new Error('private-submission-cause');
        return answer;
      },
    });
  } else {
    const handler = createClientHttpHandler(configuration);
    server = createServer({key: tlsKey, cert: tlsCertificate}, (request, response) => {
      const operation = request.url.split('/').at(-1);
      operations.push(operation);
      const phase = operation === 'submit-intent' ? pendingLoss : undefined;
      if (phase) pendingLoss = undefined;
      if (phase === 'before-dispatch') {
        request.resume(); response.destroy(); return;
      }
      if (phase === 'after-commit') {
        response.end = () => {
          assert.equal(response.statusCode, 200);
          response.destroy(); return response;
        };
      }
      void handler(request, response);
    });
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    endpoint = `https://127.0.0.1:${server.address().port}/`;
    client = await sdk.connect({mode: 'local', owner: 'local',
      endpoint, token: async () => {
        credentials++;
        await beforeBoundary();
        return 'private-token';
      }});
  }
  return {client, endpoint, operations, received,
    retainPreparingProgram(input, submissionRef) {
      const owned = moon.clientSubmittedIntent(JSON.stringify({kind: 'program', input, parameters: null}),
        1048576, 65536, 64);
      assert.ok(owned);
      return journal.recordSubmittedIntent(submissionRef, owned,
        {...scope, currentAuthorization: true, actorId: 'principal-a'}, moon);
    },
    activity: () => ({credentials, authentications, preparations}),
    pauseNext: () => {
      let release; pause = new Promise(resolve => { release = resolve; });
      return release;
    }, revoke: () => { authorized = false; },
    counts: () => ({submits, issues}),
    stored: () => observer.prepare(`SELECT caller_request_id, namespace_id,
      authority_scope_cid, program_definition_cid, run_definition_cid,
      dispatch_reserved, physical_start_reserved FROM client_requests`).all().map(row => ({...row}))};
}

for (const entrance of ['local', 'https']) {
  for (const kind of ['program', 'aql-json']) {
    for (const loss of ['before-dispatch', 'after-commit', undefined]) {
      test(`${entrance}: ${kind} submission inputs survive ${loss ?? 'acceptance'}`, async t => {
        const f = await fixture(t, entrance, loss);
        const program = JSON.parse(document), parameters = {};
        const options = {submissionRef: f.client.newSubmission({nonce: 'saved-request'}), parameters};
        const operation = kind === 'program' ? f.client.start(program, options)
          : f.client.startSource(document, {...options, format: 'json'});
        program.stages[0].steps[0].values.rows[0].id = 9999;
        parameters.changed = 'private-edit';
        let result;
        try { result = await operation; }
        catch (cause) {
          assert.equal(cause.code, 'SubmissionUnknown');
          assert.equal(cause.requestId, 'saved-request');
          result = cause;
        }
        assert.equal(result instanceof sdk.ClientError, loss !== undefined);
        assert.equal(result.code, loss ? 'SubmissionUnknown' : undefined);
        const committed = loss !== 'before-dispatch';
        const stored = f.stored();
        assert.equal(stored.length, committed ? 1 : 0);
        assert.deepEqual(f.counts(), {submits: committed ? 1 : 0, issues: committed ? 1 : 0});
        if (committed) {
          assert.equal(stored[0].caller_request_id, submissionRequestId(options.submissionRef));
          // Independently assembled current Values Program semantics and
          // Definition preimages include the current expression contract closure.
          assert.equal(stored[0].program_definition_cid,
            'sha256:0d76c0cc6c1a708e8083b08f1f21ff5b7629c5f0341b2ce0688b2f0079628436');
          assert.equal(stored[0].dispatch_reserved, 0);
          assert.equal(stored[0].physical_start_reserved, 0);
        }
        assert.deepEqual(f.operations, ['connect', 'submit-intent']);
        const snapshot = sdk.getSubmissionInput?.(result);
        assert.deepEqual(snapshot?.input, kind === 'program' ? JSON.parse(document)
          : {text: document, format: 'json'}, '[check-mutation:submission-input]');
        assert.deepEqual(snapshot.parameters, {}, '[check-mutation:submission-input]');
        assert.equal(snapshot.requestId, 'saved-request');
        assert.deepEqual(snapshot.submissionRef, options.submissionRef);
        assert.equal(snapshot.lookupContext.scopeRef, 'principal-a');
        assert.equal(snapshot.lookupContext.endpoint, f.endpoint);
        assert.equal(Object.isFrozen(snapshot), true);
        assert.equal(Object.isFrozen(snapshot.parameters), true);
        assert.ok(!JSON.stringify(snapshot).includes('private-token'));
        assert.ok(!JSON.stringify(result).includes('client-values'));
        assert.equal(sdk.getSubmissionInput({...result}), undefined);
        const explanation = sdk.explainSubmission?.(result);
        const expectedExplanation = loss ? {
          observation: 'acceptance_unknown',
          summary: 'Submission acceptance is unknown. Work may already have started.',
          next: {operation: 'lookupSubmission', submissionRef: options.submissionRef,
            lookupContext: {endpoint: f.endpoint, scopeRef: 'principal-a'}},
        } : {
          observation: 'run_reference_received',
          summary: 'The Host returned a validated Run reference. Check the current Run state for execution progress.',
          next: {operation: 'status', ref: {namespaceId: 'namespace-a',
            authorityScopeCid: cid('a'), runDefinitionCid: stored[0].run_definition_cid}},
        };
        assert.deepEqual(explanation, expectedExplanation,
          '[check-mutation:submission-explanation]');
        const callsBeforeLocale = [...f.operations];
        for (const format of ['text', 'html', 'json']) {
          const output = sdk.formatSubmission(result, {format});
          assert.ok(output);
          assert.doesNotMatch(output, /private-token|private-submission-cause|client-values/);
          if (format === 'json') assert.deepEqual(JSON.parse(output).explanation, expectedExplanation,
            '[check-mutation:operation-submit-public-format]');
        }
        const japanese = {...expectedExplanation, summary: loss
          ? '送信の受理を確認できません。処理は既に始まっている可能性があります。'
          : 'Hostは検証済みのRun参照を返しました。実行の進行はRunの現在状態で確認してください。'};
        assert.deepEqual(sdk.explainSubmission(result, {locale: 'ja-JP'}), japanese,
          '[check-mutation:operation-submit-public-locale]');
        assert.equal(sdk.explainSubmission(result, {get locale() {throw new Error('private-locale');}}), explanation);
        assert.equal(sdk.explainSubmission({...result}, {locale: 'ja'}), undefined);
        assert.deepEqual(f.operations, callsBeforeLocale, '[check-mutation:operation-submit-public-passive]');
        assert.equal(Object.isFrozen(explanation), true);
        assert.equal(Object.isFrozen(explanation.next), true);
        for (const privateText of ['private-token', 'private-submission-cause', 'client-values']) {
          assert.equal(JSON.stringify(explanation).includes(privateText), false);
        }
        assert.equal(sdk.explainSubmission({...result}), undefined);
        if (loss) {
          result.code = 'Accepted';
          result.message = 'Work completed successfully';
          result.requestId = 'edited-request';
          assert.deepEqual(sdk.explainSubmission(result), expectedExplanation);
        }
        const recovery = f.client.recoverRequest(result);
        assert.deepEqual(recovery.target.submissionRef, options.submissionRef);
        assert.deepEqual(f.operations, callsBeforeLocale);
        const found = await recovery.lookup();
        assert.equal(found.kind, committed ? 'ready' : 'unresolvable',
          '[check-mutation:request-public-observation]');
        assert.deepEqual(found.submissionRef, snapshot.submissionRef);
        if (committed) {
          assert.equal(found.admission.ref.runDefinitionCid, stored[0].run_definition_cid);
          if (loss === undefined) assert.deepEqual(found, sdk.getSubmissionOutcome(result));
          else assert.equal(sdk.getSubmissionOutcome(result), undefined);
        } else assert.deepEqual(found.problem, {code: 'submission_history_unresolvable'});
        if (!committed) {
          // The canonical Submission lookup above is not the separate existing
          // Request lookup. Exercise that original absence projection too;
          // neither read grants a Run reference or a permission to resubmit.
          const absent = await f.client.lookupRequest(submissionRequestId(snapshot.submissionRef));
          assert.deepEqual(absent, {kind: 'not_found'});
          assert.equal(sdk.explainRequestLookup(absent).observation, 'lookup_unresolved',
            '[check-mutation:request-public-observation]');
        }
        assert.equal(sdk.getSubmissionInput(found), undefined);
        assert.deepEqual(f.stored(), stored);
        f.revoke();
        await assert.rejects(f.client.lookupSubmission(snapshot.submissionRef), {code: 'ClientConnectionDenied'});
        assert.deepEqual(f.stored(), stored);
        assert.equal(f.operations.filter(value => value === 'submit-intent').length, 1);
        assert.equal(sdk.getSubmissionInput(result), snapshot);
        assert.deepEqual(sdk.explainSubmission(result), expectedExplanation);
      });
    }
  }
}

for (const entrance of ['local', 'https']) {
  test(`${entrance}: structured Program admission refusal retains input without a semantic observation`, async t => {
    const f = await fixture(t, entrance);
    const program = {version: 'actql/0.1', id: 'missing-stages'};
    let rejected;
    try {await f.client.start(program);}
    catch (error) {rejected = error;}
    assert.equal(rejected?.code, 'SubmissionNotAccepted');
    const outcome = sdk.getSubmissionOutcome(rejected);
    assert.equal(outcome?.kind, 'not_accepted', '[check-mutation:program-original-phase]');
    const input = sdk.getSubmissionInput(rejected);
    const before = [...f.operations];
    assert.equal(input.kind, 'program');
    assert.deepEqual(input.input, program);
    assert.notStrictEqual(input.input, program);
    assert.equal(Object.isFrozen(input), true);
    assert.equal(Object.isFrozen(input.input), true);
    assert.deepEqual(outcome.submissionRef, input.submissionRef);
    // Program JSON admission precedes the semantic CheckOutcome owner. An
    // absent observation cannot supply a diagnostic pointer or a second check.
    const checked = sdk.getSubmissionCheckObservation(rejected);
    assert.equal(checked, undefined, '[check-mutation:program-structural-observation]');
    assert.equal(sdk.getCheckInput(checked, 'program'), undefined);
    assert.equal(sdk.getCheckFixes(checked), undefined);
    assert.equal(sdk.getSubmissionCheckObservation(structuredClone(rejected)), undefined);
    assert.equal(sdk.getSubmissionInput({...rejected}), undefined);
    assert.equal(sdk.getSubmissionOutcome({...rejected}), undefined);
    assert.strictEqual(sdk.getSubmissionInput(rejected), input);
    assert.equal(sdk.explainSubmission(rejected).observation, 'not_accepted');
    assert.deepEqual(f.operations, before, '[check-mutation:program-passive]');
    assert.deepEqual(f.stored(), []);
    assert.deepEqual(f.counts(), {submits: 0, issues: 0});
  });

  test(`${entrance}: structured Program accepted preparation failure retains phase without a semantic observation`, async t => {
    const f = await fixture(t, entrance);
    const program = {version: 'actql/0.1', id: 'original'};
    const submissionRef = f.client.newSubmission({nonce: 'preparing-program'});
    // The existing journal Owner supplies a durable preparing intent, as after
    // restart before preflight. No response or execution outcome is fabricated.
    assert.equal(f.retainPreparingProgram(program, submissionRef).phase, 'preparing');
    let rejected;
    try {await f.client.start(program, {submissionRef});} catch (error) {rejected = error;}
    assert.equal(rejected?.code, 'SubmissionPreparationFailed');
    const outcome = sdk.getSubmissionOutcome(rejected);
    assert.equal(outcome?.kind, 'preparation_failed', '[check-mutation:program-original-phase]');
    const original = sdk.getSubmissionInput(rejected);
    assert.deepEqual(outcome.submissionRef, submissionRef);
    assert.deepEqual(original.submissionRef, submissionRef);
    assert.deepEqual(original.input, program);
    assert.equal(Object.isFrozen(original.input), true);
    const before = [...f.operations];
    const checked = sdk.getSubmissionCheckObservation(rejected);
    assert.equal(checked, undefined, '[check-mutation:program-structural-observation]');
    assert.equal(sdk.getCheckInput(checked, 'program'), undefined);
    assert.equal(sdk.getCheckFixes(checked), undefined);
    assert.equal(sdk.getSubmissionInput({...rejected}), undefined);
    assert.strictEqual(sdk.getSubmissionInput(rejected), original);
    assert.equal(sdk.explainSubmission(rejected).observation, 'preparation_failed');
    assert.deepEqual(f.operations, before, '[check-mutation:program-passive]');
    const retained = await f.client.lookupSubmission(submissionRef);
    assert.deepEqual(retained, outcome);
    assert.equal(Object.hasOwn(retained, 'checkObservation'), false);
    assert.equal(sdk.getSubmissionCheckObservation(retained), undefined);
    assert.deepEqual(f.stored(), []);
    assert.deepEqual(f.counts(), {submits: 0, issues: 0});
  });

  test(`${entrance}: structured Program refusals retain missing null and wrong-type inputs`, async t => {
    const f = await fixture(t, entrance);
    for (const value of [{version: 'actql/0.1', id: 'missing'},
      {version: 'actql/0.1', id: 'null', stages: null},
      {version: 'actql/0.1', id: 'wrong', stages: {}}]) {
      let rejected;
      try {await f.client.start(value);} catch (error) {rejected = error;}
      assert.equal(rejected?.code, 'SubmissionNotAccepted');
      const outcome = sdk.getSubmissionOutcome(rejected);
      assert.equal(outcome?.kind, 'not_accepted', '[check-mutation:program-original-phase]');
      const before = [...f.operations];
      const original = sdk.getSubmissionInput(rejected);
      assert.deepEqual(original.input, value, '[check-mutation:program-structural-input]');
      assert.notStrictEqual(original.input, value);
      assert.equal(Object.hasOwn(original.input, 'stages'), Object.hasOwn(value, 'stages'));
      assert.equal(Object.isFrozen(original.input), true);
      if (value.stages !== null && typeof value.stages === 'object') {
        assert.equal(Object.isFrozen(original.input.stages), true);
      }
      assert.deepEqual(outcome.submissionRef, original.submissionRef);
      const checked = sdk.getSubmissionCheckObservation(rejected);
      assert.equal(checked, undefined, '[check-mutation:program-structural-observation]');
      assert.equal(sdk.getCheckInput(checked, 'program'), undefined);
      assert.equal(sdk.getSubmissionInput({...rejected}), undefined);
      assert.strictEqual(sdk.getSubmissionInput(rejected), original);
      assert.equal(sdk.explainSubmission(rejected).observation, 'not_accepted');
      assert.deepEqual(f.operations, before, '[check-mutation:program-passive]');
      assert.deepEqual(f.stored(), []);
      assert.deepEqual(f.counts(), {submits: 0, issues: 0});
    }
  });

  test(`${entrance}: structured Program supplied violations coexist with missing declarations`, async t => {
    const f = await fixture(t, entrance);
    const program = JSON.parse(document);
    program.params = {missing: {type: 'number'}, wrong: {type: 'number'}};
    program.stages[0].steps.push({derive: {n: '$missing + $wrong'}});
    for (const wrong of ['private-value', null]) {
      let rejected;
      try {await f.client.start(program, {parameters: {wrong}});} catch (error) {rejected = error;}
      const checked = sdk.getSubmissionCheckObservation(rejected);
      assert.equal(checked?.report.verdict, 'invalid', '[check-mutation:program-mixed-verdict]');
      const programInput = sdk.getCheckInput(checked, 'program');
      const parametersInput = sdk.getCheckInput(checked, 'parameters');
      assert.deepEqual(checked.report.reasons.map(({location, ...reason}) => reason),
        [{code: 'supplied_value_type_mismatch', facts: {
          parameter: 'wrong', expected_type: 'number', actual_type: wrong === null ? 'null' : 'string'}}],
      '[check-mutation:program-mixed-facts]');
      // The retained native binder proves the type facts, but may not retain
      // authored Parameters coordinates. Any emitted location still owns them.
      const location = checked.report.reasons[0].location;
      if (location !== undefined) {
        assert.deepEqual(location, {kind: 'structured', document_id: 'parameters',
          revision: parametersInput.revision, pointer: '/wrong'});
        assert.equal(sdk.resolveCheckLocation(checked, location).input, parametersInput);
      }
      const requirement = checked.report.requirements[0];
      assert.equal(requirement.code, 'parameter_value_required');
      assert.equal(requirement.facts.parameter, 'missing');
      assert.deepEqual(requirement.location, {kind: 'structured', document_id: 'program',
        revision: programInput.revision, pointer: '/params/missing'});
      assert.equal(sdk.resolveCheckLocation(checked, requirement.location).input, programInput);
      assert.equal(JSON.stringify(checked).includes('private-value'), false);
      const before = [...f.operations];
      sdk.getCheckParameterAdmission(checked, 'missing');
      sdk.getCheckFixes(checked); sdk.explainCheckReason(requirement);
      assert.deepEqual(f.operations, before, '[check-mutation:program-passive]');
      assert.deepEqual(f.counts(), {submits: 0, issues: 0});
    }
  });

  test(`${entrance}: structured Program preparation limits retain input without a semantic observation`, async t => {
    const f = await fixture(t, entrance);
    const unsupported = JSON.parse(document);
    unsupported.bindings = {opaque: {type: 'string'}};
    const budget = JSON.parse(document);
    budget.stages = Array.from({length: 33}, (_, index) => ({...budget.stages[0], id: `stage-${index}`}));
    for (const program of [unsupported, budget]) {
      let rejected;
      try {await f.client.start(program);} catch (error) {rejected = error;}
      assertOriginalPreparationRefusal(f, rejected, program);
    }
  });

  test(`${entrance}: structured Program Unicode and declaration refusals retain exact preparation input`, async t => {
    const f = await fixture(t, entrance);
    const unicode = {...JSON.parse(document), 'e\u0301/😀~': null};
    const defaultType = {...JSON.parse(document), params: {n: {type: 'number', default: 'private-default'}}};
    for (const program of [unicode, defaultType]) {
      let rejected;
      try {await f.client.start(program);} catch (error) {rejected = error;}
      assertOriginalPreparationRefusal(f, rejected, program);
      assert.equal(JSON.stringify(sdk.getSubmissionOutcome(rejected)).includes('private-default'), false);
    }
  });

  test(`${entrance}: structured Program protected Sources retain only independent public obligations`, async t => {
    const wire = JSON.parse(await readFile(new URL('./fixtures/query-amount-environment.json', import.meta.url), 'utf8'));
    const checkingEnvironment = moon.clientProgramCheckEnvironment(canonicalText(wire), wire.evidence_bundle_cid,
      false, false, true, false, false, false, false);
    assert.ok(checkingEnvironment);
    const view = wire.source_views[0];
    const publication = {environmentCid: wire.evidence_bundle_cid, aliases: [{name: 'records',
      sourceRef: 'connector://crm/main/r#v', sourceViewContractCid: view.contract_cid,
      schemaContractCid: view.output.schema.cid}]};
    const denied = await createNodeAuthorizationGate({configuration: JSON.stringify({
      version: 'actql-execution-account-config/0.1', account_id: 'structured-test', entries: [{
        entry_id: 'read-denied', outcome: 'deny', principal: {all: true}, connection: {all: true},
        resource: {all: true}, operation: {any_of: ['read']}, exclusions: []}]}),
      context: {principal: 'principal-a', contextCid: cid('3')}});
    t.after(() => denied.close());
    const peers = [await fixture(t, entrance), await fixture(t, entrance, undefined, {checkingEnvironment}),
      await fixture(t, entrance, undefined, {checkingEnvironment, publication, sourceAccesses: [{
        authorization: denied, sourceRef: 'connector://crm/main/r#v', connection: 'source', resource: 'r'}]})];
    const program = {version: 'actql/0.1', id: 'protected',
      params: {missing: {type: 'number'}, wrong: {type: 'number'}},
      stages: [{id: 'main', inputs: {rows: {connector: 'crm/main', resource: 'r', view: 'v'}},
        steps: [{select: ['private_field'], as: 'selected'}],
        results: {out: {from: 'selected', fields: ['private_field']}}}],
      results: {out: {from: {stage: 'main', result: 'out'}}}};
    const observations = [];
    for (const f of peers) {
      let rejected;
      try {await f.client.start(program, {parameters: {wrong: 'private-supplied'}});} catch (error) {rejected = error;}
      const checked = sdk.getSubmissionCheckObservation(rejected);
      assert.ok(sdk.getSubmissionOutcome(rejected), `Expected a retained rejection, received ${rejected?.code}: ${rejected?.cause?.code ?? rejected?.cause?.message}`);
      assert.deepEqual(sdk.getSubmissionOutcome(rejected).problem, {code: 'ClientProgramRejected', classification: 'operation_failed'}, '[check-mutation:program-protected-problem]');
      assert.equal(checked?.report?.verdict, 'invalid', '[check-mutation:program-protected-verdict]');
      assert.deepEqual(checked.report.coverage.unresolved, [{boundary: 'source_resolution', reason: 'unresolved_protected'}],
        '[check-mutation:program-protected-coverage]');
      assert.equal(checked.report.reasons.length, 1);
      assert.equal(checked.report.reasons[0].code, 'supplied_value_type_mismatch');
      assert.equal(checked.report.reasons[0].location.pointer, '/wrong');
      assert.equal(checked.report.requirements[0].location.pointer, '/params/missing');
      assert.equal(JSON.stringify(checked).includes('private_field'), false, '[check-mutation:program-protected-disclosure]');
      assert.equal(JSON.stringify(checked).includes('private-supplied'), false);
      assert.deepEqual(f.counts(), {submits: 0, issues: 0});
      observations.push(checked);
    }
    // Host-keyed references differ between fixtures; disclosable facts do not.
    const facts = value => ({verdict: value.report.verdict, coverage: value.report.coverage,
      reasons: value.report.reasons.map(({location, ...reason}) => ({...reason, pointer: location.pointer})),
      requirements: value.report.requirements.map(({location, ...reason}) => ({...reason, pointer: location.pointer}))});
    for (const observation of observations.slice(1)) assert.deepEqual(facts(observations[0]), facts(observation), '[check-mutation:program-protected-equivalence]');
  });

  test(`${entrance}: bound count input refusal precedes Run acceptance`, async t => {
    const f = await fixture(t, entrance);
    const program = {version: 'actql/0.1', id: 'bound-count',
      params: {n: {type: 'number', nullable: true}}, stages: [{id: 'main', inputs: {},
        steps: [{values: {schema: {id: {type: 'number', nullable: false}}, rows: [{id: 1}]}, as: 'rows'},
          {take: {$param: 'n'}, as: 'selected'}],
        results: {out: {from: 'selected', fields: ['id']}}}],
      results: {out: {from: {stage: 'main', result: 'out'}}}};
    for (const [index, n] of [0, -1, 1.5, 9007199254740992, null].entries()) {
      for (const kind of ['program', 'aql-json']) {
        const options = {submissionRef: f.client.newSubmission({nonce: `${kind}-${index}`}), parameters: {n}};
        await assert.rejects(kind === 'program' ? f.client.start(program, options)
          : f.client.startSource(JSON.stringify(program), {...options, format: 'json'}),
        error => {
          assert.equal(error.code, 'SubmissionNotAccepted');
          assert.equal(sdk.getSubmissionOutcome(error).problem.code, 'ClientProgramInvalidInput',
            '[check-mutation:bound-count-category]');
          return true;
        });
        assert.deepEqual(f.counts(), {submits: 0, issues: 0});
        assert.deepEqual(f.stored(), []);
      }
    }
    const submissionRef = f.client.newSubmission({nonce: 'missing-count'});
    let rejected;
    await assert.rejects(f.client.start(program, {submissionRef}), error => {
      notAccepted('ClientProgramNeedsInputs')(error);
      rejected = sdk.getSubmissionOutcome(error);
      return true;
    });
    assert.deepEqual(await f.client.lookupSubmission(submissionRef), rejected);
    const beforeReplay = f.activity();
    await assert.rejects(f.client.start(program, {submissionRef}), error => {
      notAccepted('ClientProgramNeedsInputs')(error);
      assert.deepEqual(sdk.getSubmissionOutcome(error), rejected);
      return true;
    });
    assert.equal(f.activity().preparations, beforeReplay.preparations);
    await assert.rejects(f.client.start(program, {submissionRef, parameters: {n: 1}}),
      error => {
        assert.equal(error.code, 'SubmissionConflict');
        assert.equal(sdk.getSubmissionAttempt(error)?.reason, 'intent');
        assert.deepEqual(sdk.getSubmissionAttempt(error).submissionRef, submissionRef);
        assert.equal(sdk.getSubmissionOutcome(error), undefined);
        return true;
      });
    assert.deepEqual(await f.client.lookupSubmission(submissionRef), rejected);
    assert.deepEqual(f.counts(), {submits: 0, issues: 0});
    assert.deepEqual(f.stored(), []);
  });
}


for (const entrance of ['local', 'https']) {
  test(`${entrance}: temporal input refusal precedes Run acceptance`, async t => {
    const f = await fixture(t, entrance);
    for (const field of ['size', 'step', 'offset']) {
      const program = {version: 'actql/0.1', id: 'temporal-input',
        params: {n: {type: 'number'}}, stages: [{id: 'main', inputs: {},
          steps: [{values: {schema: {id: {type: 'number', nullable: false}},
            rows: [{id: 1}]}, as: 'rows'},
          {row_window: {time: 'id', kind: 'sliding', size: 1, step: 1,
            [field]: {$param: 'n'}}, as: 'selected'}],
          results: {out: {from: 'selected', fields: ['id']}}}],
        results: {out: {from: {stage: 'main', result: 'out'}}}};
      const invalid = field === 'offset' ? [1.5, 9007199254740992]
        : [0, -1, 1.5, 9007199254740992];
      for (const [index, n] of invalid.entries()) {
        for (const kind of ['program', 'aql-json']) {
          const options = {submissionRef: f.client.newSubmission({nonce: `${field}-${kind}-${index}`}), parameters: {n}};
          await assert.rejects(kind === 'program' ? f.client.start(program, options)
            : f.client.startSource(JSON.stringify(program), {...options, format: 'json'}),
          error => {
            assert.equal(error.code, 'SubmissionNotAccepted');
            assert.equal(sdk.getSubmissionOutcome(error).problem.code, 'ClientProgramInvalidInput',
              '[check-mutation:temporal-input-category]');
            return true;
          });
          assert.deepEqual(f.counts(), {submits: 0, issues: 0});
          assert.deepEqual(f.stored(), []);
        }
      }
      for (const kind of ['program', 'aql-json']) {
        const options = {submissionRef: f.client.newSubmission({nonce: `${field}-${kind}-missing`}), parameters: {}};
        await assert.rejects(kind === 'program' ? f.client.start(program, options)
          : f.client.startSource(JSON.stringify(program), {...options, format: 'json'}),
        notAccepted('ClientProgramNeedsInputs'));
        await assert.rejects(kind === 'program'
          ? f.client.start(program, {...options, submissionRef: f.client.newSubmission({nonce: `${field}-${kind}-null`}), parameters: {n: null}})
          : f.client.startSource(JSON.stringify(program), {...options, submissionRef: f.client.newSubmission({nonce: `${field}-${kind}-null`}), parameters: {n: null}, format: 'json'}),
        notAccepted('ClientProgramInvalidInput'));
      }
      assert.deepEqual(f.counts(), {submits: 0, issues: 0});
      assert.deepEqual(f.stored(), []);
    }
  });
}


for (const entrance of ['local', 'https']) {
  test(`${entrance}: valid signed temporal offsets preserve Run acceptance`, async t => {
    const f = await fixture(t, entrance);
    for (const [index, n] of [-1, 0, 1].entries()) {
      const program = {version: 'actql/0.1', id: 'signed-temporal-input',
        params: {n: {type: 'number'}}, stages: [{id: 'main', inputs: {},
          steps: [{values: {schema: {id: {type: 'number', nullable: false}},
            rows: [{id: 1}]}, as: 'rows'},
          {row_window: {time: 'id', kind: 'sliding', size: 1, step: 1,
            offset: {$param: 'n'}}, as: 'selected'}],
          results: {out: {from: 'selected', fields: ['id']}}}],
        results: {out: {from: {stage: 'main', result: 'out'}}}};
      for (const kind of ['program', 'aql-json']) {
        const options = {submissionRef: f.client.newSubmission({nonce: `signed-${kind}-${index}`}), parameters: {n}};
        const result = await (kind === 'program' ? f.client.start(program, options)
          : f.client.startSource(JSON.stringify(program), {...options, format: 'json'}));
        assert.equal(typeof result.ref.runDefinitionCid, 'string');
        assert.equal(sdk.explainSubmission(result).observation, 'run_reference_received');
      }
      assert.deepEqual(f.counts(), {submits: (index + 1) * 2, issues: (index + 1) * 2});
      assert.equal(f.stored().length, (index + 1) * 2);
    }
  });
}


// Independently authored public inputs. The real preparation, checker, Run
// issuer and SQLite journal above observe only the SDK's one detached request.
const nestedDeclaration = () => ({type: 'object', fields: {nested:
  {type: 'array', items: {type: 'number', nullable: true}}}});
const nestedParameterProgram = declaration => {
  const program = JSON.parse(document);
  program.params = {x: declaration};
  program.stages[0].steps.push({from: 'selected',
    derive: {value: {$param: 'x'}}, as: 'bound'});
  program.stages[0].results.rows = {from: 'bound', fields: ['value']};
  return program;
};
const scalarProgram = value => {
  const program = JSON.parse(document);
  program.stages[0].steps[0].values.schema.id.nullable = true;
  program.stages[0].steps[0].values.rows = [{id: value}];
  return program;
};
const numericInputCases = value => {
  const nested = {nested: [value]};
  const declaration = nestedDeclaration();
  const defaultDeclaration = {...nestedDeclaration(), default: nested};
  return [
    ['start parameters', 'submit-intent', client => client.start(nestedParameterProgram(declaration),
      {submissionRef: client.newSubmission({nonce: 'numeric-start-parameters'}), parameters: {x: nested}})],
    ['start Program values', 'submit-intent', client => client.start(scalarProgram(value),
      {submissionRef: client.newSubmission({nonce: 'numeric-start-values'})})],
    ['start default', 'submit-intent', client => client.start(nestedParameterProgram(defaultDeclaration),
      {submissionRef: client.newSubmission({nonce: 'numeric-start-default'}), parameters: {}})],
    ['aql parameters', 'submit-intent', client => client.startSource('SELECT @x AS n',
      {format: 'sql', submissionRef: client.newSubmission({nonce: 'numeric-aql-parameters'}),
        parameterDeclarations: {x: declaration}, parameters: {x: nested}})],
    ['aql default', 'submit-intent', client => client.startSource('SELECT @x AS n',
      {format: 'sql', submissionRef: client.newSubmission({nonce: 'numeric-aql-default'}),
        parameterDeclarations: {x: defaultDeclaration}, parameters: {}})],
    ['check parameters', 'check', client => client.check('SELECT @x AS n',
      {kind: 'text', scope: 'bound_input', format: 'sql', parameterDeclarations: {x: declaration}, parameters: {x: nested}})],
    ['check default', 'check', client => client.check('SELECT @x AS n',
      {kind: 'text', scope: 'bound_input', format: 'sql', parameterDeclarations: {x: defaultDeclaration}, parameters: {}})],
  ];
};

for (const entrance of ['local', 'https']) {
  test(`${entrance}: all SDK input paths refuse lossy numbers before credentials and Host admission`, async t => {
    const f = await fixture(t, entrance), before = f.activity();
    for (const value of [NaN, Infinity, -Infinity, -0,
      ...[NaN, Infinity, -Infinity, -0].map(value => new Number(value)),
      {toJSON: () => Infinity}, {toJSON: () => -0},
      Object.assign(new Number(1), {valueOf: () => NaN}),
      Object.assign(new Number(1), {[Symbol.toPrimitive]: () => -0})]) {
      for (const [name, operation, invoke] of numericInputCases(value)) {
        await assert.rejects(invoke(f.client), error => {
          assert.equal(error.code, operation === 'check' ? 'InvalidCheckRequest' : 'InvalidClientPayload',
            `[request-snapshot:local-refusal] ${name}`);
          assert.equal(sdk.getSubmissionInput(error), undefined);
          assert.equal(sdk.explainSubmission(error), undefined);
          return true;
        });
        assert.deepEqual(f.activity(), before, '[request-snapshot:before-credentials]');
        assert.deepEqual(f.operations, ['connect'], '[request-snapshot:zero-exchange]');
        assert.deepEqual(f.counts(), {submits: 0, issues: 0}, '[request-snapshot:zero-admission]');
        assert.deepEqual(f.stored(), []);
        assert.deepEqual(f.received, []);
      }
    }
  });

  test(`${entrance}: finite and null SDK inputs retain real check and Run acceptance`, async t => {
    // Each independently authored value gets a fresh request journal so the
    // fixed request IDs exercise input admission, not request-ID collisions.
    for (const value of [null, 0, 1.25, -2, Number.MAX_VALUE, Number.MIN_VALUE, new Number(3.5)]) {
      const f = await fixture(t, entrance);
      let submits = 0, checks = 0;
      for (const [name, operation, invoke] of numericInputCases(value)) {
        const result = await invoke(f.client);
        if (operation === 'check') {
          checks++;
          assert.equal(result.outcome, 'completed', name);
          assert.equal(result.report.verdict, 'verified', name);
        } else {
          submits++;
          assert.equal(sdk.explainSubmission(result).observation, 'run_reference_received', name);
          const snapshot = sdk.getSubmissionInput(result);
          assert.deepEqual(f.received.at(-1), {input: snapshot.input, parameters: snapshot.parameters},
            '[request-snapshot:received-value]');
          assert.ok(Object.isFrozen(snapshot.input));
          assert.ok(snapshot.parameters === null || Object.isFrozen(snapshot.parameters));
        }
      }
      assert.equal(checks, 2);
      assert.deepEqual(f.counts(), {submits: 5, issues: 5});
      assert.equal(f.stored().length, 5);
      assert.equal(f.operations.filter(operation => operation === 'submit-intent').length, submits);
    }
  });

  test(`${entrance}: SDK snapshots serialize caller values once before the first await`, async t => {
    for (const operation of ['start', 'startSource', 'check']) {
      const f = await fixture(t, entrance);
      let conversions = 0, serializations = 0;
      const boxed = Object.assign(new Number(1), {valueOf: () => { conversions++; return 3.5; }});
      const parameters = {x: {toJSON() { serializations++; return {nested: [boxed, null]}; }}};
      const declarations = {x: nestedDeclaration()};
      const program = nestedParameterProgram(declarations.x);
      const expectedInput = operation === 'start' ? structuredClone(program) :
        {text: 'SELECT @x AS n', format: 'sql', parameterDeclarations: structuredClone(declarations)};
      const release = f.pauseNext();
      const pending = operation === 'start'
        ? f.client.start(program, {submissionRef: f.client.newSubmission({nonce: 'one-snapshot'}), parameters})
        : f.client[operation]('SELECT @x AS n', {format: 'sql',
          ...(operation === 'check' ? {kind: 'text', scope: 'bound_input'} :
            {submissionRef: f.client.newSubmission({nonce: 'one-snapshot'})}),
          parameterDeclarations: declarations, parameters});
      assert.equal(conversions, 1);
      assert.equal(serializations, 1);
      // Mutation during the real Local authentication / HTTPS credential wait
      // cannot change the already-owned request or introduce a second snapshot.
      parameters.x = {nested: [Infinity]};
      declarations.x.type = 'number';
      program.stages[0].steps[0].values.rows[0].id = -0;
      release();
      const result = await pending;
      assert.equal(conversions, 1, '[request-snapshot:one-conversion]');
      assert.equal(serializations, 1, '[request-snapshot:one-serialization]');
      assert.deepEqual(f.received, [{input: expectedInput,
        parameters: {x: {nested: [3.5, null]}}}], '[request-snapshot:pre-await-custody]');
      if (operation === 'check') {
        assert.equal(result.report.verdict, 'verified');
        assert.deepEqual(sdk.getCheckInput(result, 'parameters').value, {x: {nested: [3.5, null]}});
        assert.deepEqual(f.counts(), {submits: 0, issues: 0});
      } else {
        const snapshot = sdk.getSubmissionInput(result);
        assert.deepEqual(snapshot.input, expectedInput);
        assert.deepEqual(snapshot.parameters, {x: {nested: [3.5, null]}});
        assert.ok(Object.isFrozen(snapshot.parameters.x.nested));
        assert.deepEqual(f.counts(), {submits: 1, issues: 1});
      }
    }
  });
}
