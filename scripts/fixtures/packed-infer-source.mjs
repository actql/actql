import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {appendFileSync, readFileSync, writeFileSync} from 'node:fs';
import {createServer} from 'node:https';
import {userInfo} from 'node:os';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {inspect} from 'node:util';
import {connect} from '@actql/node';
import {openInstalledRemoteHttpHost} from '@actql/local-node/http-host';
import {canonical, configuration} from './installed-infer-fixture.mjs';
import {providerBindingOriginals} from './model-provider-binding-fixture.mjs';
import {sourceCases, sourceRefusals, sourceRuntimeRefusals}
  from './infer-source-expectation.mjs';

const [transport, phase, caseName = 'minimal'] = process.argv.slice(2);
assert.ok(['local', 'remote'].includes(transport));
assert.ok(['success', 'capture', 'replay', 'refusal', 'runtime-refusal'].includes(phase));
const fixture = sourceCases[caseName];
const source = phase === 'refusal' ? sourceRefusals[caseName] :
  phase === 'runtime-refusal' ? sourceRuntimeRefusals[caseName] : fixture?.source;
assert.equal(typeof source, 'string', 'select one explicitly authored input');
const root = join(process.cwd(), `${transport}-${caseName}-${phase === 'replay' ? 'capture' : phase}`);
const requestId = `packed-infer-source-${transport}-${caseName}-${phase === 'replay' ? 'capture' : phase}`;
const baseEnvironment = JSON.parse(readFileSync('base-environment.json', 'utf8'));
const {installation, taskCid} = configuration(baseEnvironment);
const keys = generateKeyPairSync('ed25519');
let calls = 0;
const authorization = {
  observe(name, detail) {
    if (name === 'infer_preparation_rejected') {
      // Keep the existing Host's first typed boundary in command stderr.
      // This deterministic fixture contains no external Model input or secrets.
      console.error(name, inspect(detail, {depth: 4, maxArrayLength: 12,
        maxStringLength: 256}));
    }
  },
  hostKey: {keyId: 'packed-host', privateKey: keys.privateKey.export({
    type: 'pkcs8', format: 'pem'})},
  reviewers: [{keyId: 'packed-reviewer', reviewerId: 'packed-reviewer',
    principalId: userInfo().username,
    publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
  accountConfiguration: canonical({
    version: 'actql-execution-account-config/0.1', account_id: 'packed-owner',
    entries: [{entry_id: 'allow', outcome: 'allow', principal: {all: true},
      connection: {all: true}, resource: {all: true}, operation: {all: true},
      exclusions: []}],
  }),
  faultInjection(name) {
    if (phase === 'capture' && name === 'infer_capture_committed') {
      assert.equal(calls, 1);
      // This is the existing owner's committed-capture boundary. Exit before
      // publication so a new process must consume that exact retained capture.
      process.stdout.write(JSON.stringify({transport, phase, calls, boundary: name}) +
        '\n', () => process.exit(0));
      return new Promise(() => {});
    }
  },
};
const checked = result => {
  assert.equal(result.$tag, 1, 'physical request must pass common admission');
  return result._0;
};
const registerModelProviders = moon => [{providerId: 'models/packed',
  bindingOriginals: providerBindingOriginals('models/packed',
    {selector: 'packed-risk-model'}),
  invoke() { throw new Error('UnpreparedModelCall'); },
  validatePrompt(actual, selector, wire) {
    return actual === taskCid && selector === 'packed-risk-model' &&
      JSON.parse(wire).format === 'packed-risk/0.1';
  },
  quantityCapacity: {
    limits: {tokens: 33n, costUnits: 0n, durationMs: 500n},
    perAttempt: {tokens: 33n, costUnits: 0n, durationMs: 500n}},
  observeEgress: () => ({_0: 'public', _1: 'fixture-region', _2: false, _3: false}),
  physicalPreflight: request => moon.clientProgramModelRequestPreflight(
    () => ({_0: true, _1: checked(moon.clientProgramModelPhysicalRequestPlan(
      request, 1000n, 33n, 0n, 500n, () => {
        calls++;
        appendFileSync('source-provider-calls.jsonl',
          JSON.stringify({transport, phase, caseName, taskCid}) + '\n');
        assert.notEqual(phase, 'replay', 'retained capture must not redispatch');
        assert.notEqual(phase, 'runtime-refusal', 'ASSERT UNIQUE must precede Model dispatch');
        assert.equal(moon.clientProgramModelRequestInput(request, 'text'), fixture.inputWire);
        // The registered provider's optional response contract reports an
        // absent response as provider_error; do not fabricate a typed response
        // containing an invalid object or an authored capture/outcome.
        if (fixture.noResponse) return undefined;
        return moon.clientProgramModelResponse(request,
          '{"reason":null,"risk":"high"}', 'packed-risk-model',
          'packed-source-request', 1n, 2n, new Date().toISOString());
      }))}), () => true),
}];
let host;
let server;
let client;
try {
  if (transport === 'remote') {
    host = await openInstalledRemoteHttpHost({directory: root,
      hostCapacityPolicy: baseEnvironment.host_policy_profile.capacity,
      authenticate: () => userInfo().username, authorization,
      modelInstallation: installation, registerModelProviders});
    server = createServer({cert: readFileSync('remote.crt'),
      key: readFileSync('remote.key')}, host.handler);
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    client = await connect({mode: 'remote', durability: 'durable',
      endpoint: `https://127.0.0.1:${server.address().port}/`, token: 'fixture-owner'});
  } else {
    client = await connect({mode: 'local', owner: 'local', durability: 'durable',
      installation: {directory: root, authorization,
        hostCapacityPolicy: baseEnvironment.host_policy_profile.capacity,
        modelInstallation: installation, registerModelProviders}});
  }
  // Persist the original epoch-bound identity before submit/capture. Replay
  // must use this reference, never create new work under a reconnect's epoch.
  const referenceFile = join(root, 'submission-ref.json');
  const submissionRef = phase === 'replay'
    ? JSON.parse(readFileSync(referenceFile, 'utf8'))
    : client.newSubmission({nonce: requestId});
  if (phase !== 'replay') {
    writeFileSync(referenceFile, JSON.stringify(submissionRef) + '\n',
      {mode: 0o600, flag: 'wx'});
  }
  const journalCount = () => {
    const journal = new DatabaseSync(join(root, 'requests', 'client-requests.sqlite3'),
      {readOnly: true});
    try { return journal.prepare('SELECT COUNT(*) AS count FROM client_requests').get().count; }
    finally { journal.close(); }
  };
  if (phase === 'refusal') {
    const before = journalCount();
    let outcome;
    await assert.rejects(client.startSource(source, {format: 'aql-text', submissionRef}), error => {
      assert.equal(error.code, 'SubmissionNotAccepted');
      outcome = error.outcome;
      assert.equal(outcome.kind, 'not_accepted');
      assert.deepEqual(outcome.submissionRef, submissionRef);
      assert.ok(['ClientProgramInvalidInput', 'ClientProgramRejected',
        'ClientProgramUnsupported'].includes(outcome.problem.code), outcome.problem.code);
      return true;
    });
    assert.equal(calls, 0);
    assert.equal(journalCount(), before, 'refusal must not accept a Run');
    assert.deepEqual(await client.lookupSubmission(submissionRef), outcome);
    console.log(JSON.stringify({transport, phase, caseName, calls, admittedRuns: 0}));
  } else if (phase === 'runtime-refusal') {
    const assertFailedRun = state => {
      assert.equal(state.status, 'failed', 'ordinary row assertion must fail the admitted Run');
      // This is the existing public unpublished-Run code, not an invented
      // projection of the private AssertionDuplicate/AssertionNullKey causes.
      assert.equal(state.terminal_error.code, 'ACTQL_E_UNPUBLISHED_RUN');
      assert.equal(state.result_available, false);
      assert.equal(state.result_availability.answer.state, 'unavailable');
      assert.equal(state.result_availability.answer.reason, 'not_published');
      assert.deepEqual(state.next_action, {kind: 'none'});
    };
    const before = journalCount();
    const run = await client.startSource(source, {format: 'aql-text', submissionRef});
    const signal = AbortSignal.timeout(60_000);
    const terminal = await run.wait({signal});
    assertFailedRun(terminal);
    assert.equal(calls, 0, 'failed assertions must not dispatch a Model');
    assert.equal(journalCount(), before + 1, 'runtime refusal must retain one accepted Run');
    assert.deepEqual((await client.checkpoints()).items, []);
    await assert.rejects(run.result('answer').all({signal}), {code: 'ResultAccessDenied'});
    await assert.rejects(run.result('answer').describe({signal}), {code: 'ResultAccessDenied'});
    const lookup = await client.lookupSubmission(submissionRef);
    assert.equal(lookup.kind, 'ready');
    assert.deepEqual(lookup.submissionRef, submissionRef);
    assert.deepEqual(lookup.admission.ref, run.ref);
    const attached = await client.attach(run.ref);
    assertFailedRun(await attached.wait({signal}));
    await assert.rejects(attached.result('answer').all({signal}), {code: 'ResultAccessDenied'});
    await assert.rejects(attached.result('answer').describe({signal}), {code: 'ResultAccessDenied'});
    const resent = await client.startSource(source, {format: 'aql-text', submissionRef});
    assert.deepEqual(resent.ref, run.ref);
    assertFailedRun(await resent.wait({signal}));
    assert.equal(journalCount(), before + 1, 'reread, attach and resend must not create another Run');
    assert.equal(calls, 0);
    assert.deepEqual((await client.checkpoints()).items, []);
    console.log(JSON.stringify({transport, phase, caseName, status: terminal.status,
      terminalError: terminal.terminal_error, calls, admittedRuns: 1, ref: run.ref,
      checkpoints: 0}));
  } else {
    const run = await client.startSource(source, {format: 'aql-text', submissionRef});
    const signal = AbortSignal.timeout(60_000);
    const terminal = await run.wait({signal});
    console.log(JSON.stringify({transport, phase, caseName, observation: 'first-wait',
      state: terminal, calls}));
    assert.equal(terminal.status, 'succeeded');
    assert.notEqual(phase, 'capture', 'capture exit boundary was not reached');
    const result = run.result('answer');
    const description = await result.describe({signal});
    assert.deepEqual(description.ref, run.ref);
    assert.equal(description.resultName, 'answer');
    assert.equal(description.serialization.version, 'actql-jsonl/0.1');
    assert.equal(description.serialization.format, 'jsonl');
    assert.deepEqual(description.columns, fixture.columns);
    assert.deepEqual(await result.all({signal}), fixture.rows);
    const reader = result.rows({signal});
    const streamed = [];
    for await (const row of reader) streamed.push(row);
    assert.deepEqual(streamed, fixture.rows);
    assert.equal(reader.state(), 'complete', 'empty and nonempty streams must terminate');
    const attached = await client.attach(run.ref);
    assert.deepEqual(await attached.result('answer').describe({signal}), description);
    assert.deepEqual(await attached.result('answer').all({signal}), fixture.rows);
    const resent = await client.startSource(source, {format: 'aql-text', submissionRef});
    assert.deepEqual(resent.ref, run.ref);
    const lookup = await client.lookupSubmission(submissionRef);
    assert.equal(lookup.kind, 'ready');
    assert.deepEqual(lookup.submissionRef, submissionRef);
    assert.deepEqual(lookup.admission.ref, run.ref);
    assert.deepEqual(await resent.result('answer').all({signal}), fixture.rows);
    assert.equal(calls, phase === 'replay' ? 0 : fixture.calls);
    const journal = new DatabaseSync(join(root, 'requests', 'client-requests.sqlite3'),
      {readOnly: true});
    try {
      assert.equal(journal.prepare('SELECT COUNT(*) AS count FROM client_requests')
        .get().count, 1, 'reread, attach and resend must not create another Run');
    } finally { journal.close(); }
    console.log(JSON.stringify({transport, phase, caseName, status: terminal.status,
      calls, ref: run.ref, columns: description.columns, rows: fixture.rows}));
  }
} finally {
  await client?.close();
  if (server) {
    server.closeAllConnections();
    await new Promise(resolve => server.close(resolve));
  }
  await host?.close();
}
