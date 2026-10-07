// Source-execution acceptance. Fresh-packed identity is established separately
// by the existing packed consumer; these tests do not claim package evidence.
import assert from 'node:assert/strict';
import test from 'node:test';
import {generateKeyPairSync} from 'node:crypto';
import {mkdtemp, rm, writeFile} from 'node:fs/promises';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {createServer} from 'node:https';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import {tmpdir, userInfo} from 'node:os';
import {join} from 'node:path';
import {connect as connectRemote, getSubmissionInput, getSubmissionOutcome} from '../../packages/sdk/index.mjs';
import {connectEmbeddedLocal, openInstalledRemoteHttpHost} from './embedded-local.mjs';
import {fixtureCertificates} from '../site-node/https-exchange-fixture.mjs';

async function installedFixture(t, entrance, {loseSubmissionReply = false, outcome = 'allow', epochClock} = {}) {
  const root = await mkdtemp(join(tmpdir(), 'actql-d-submission-public-'));
  const directory = join(root, 'host');
  const principalId = userInfo().username;
  const keys = generateKeyPairSync('ed25519');
  let computes = 0, client, host, server, loseReply = loseSubmissionReply;
  const authorization = {
    accountConfiguration: JSON.stringify({version: 'actql-execution-account-config/0.1',
      account_id: 'submission-public', entries: [{entry_id: 'acceptance', outcome,
        principal: {all: true}, connection: {all: true}, resource: {all: true},
        operation: {any_of: ['write']}, exclusions: []}]}),
    reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId,
      publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
    reviewReaders: [principalId], hostKey: {keyId: 'host',
      privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})},
    observe(name) {if (name === 'computed') computes++;},
    ...(epochClock === undefined ? {} : {faultInjection: Object.assign(async () => {}, {
      submissionEpochTtlMs: 1000, submissionEpochNow: epochClock,
    })}),
  };
  const certificates = entrance === 'https' ? await fixtureCertificates(root) : undefined;
  const originalTrust = getCACertificates('default');
  if (certificates) setDefaultCACertificates([...originalTrust, certificates.ca.toString('utf8')]);
  const close = async () => {
    await client?.close(); client = undefined;
    if (server) {server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); server = undefined;}
    await host?.close(); host = undefined;
  };
  t.after(async () => {
    await close();
    if (certificates) setDefaultCACertificates(originalTrust);
    if (process.env.ACTQL_TEST_PRESERVE_SCRATCH === '1') {
      console.error(`Submission acceptance fixture retained: ${root}`);
    } else {
      await rm(root, {recursive: true, force: true});
    }
  });
  const open = async () => {
    if (entrance === 'local') client = await connectEmbeddedLocal({mode: 'local', owner: 'local',
      durability: 'durable', installation: {directory, authorization}});
    else {
      host = await openInstalledRemoteHttpHost({directory, authorization, authenticate: () => principalId});
      server = createServer({key: certificates.key, cert: certificates.cert}, (request, response) => {
        if (loseReply && request.url.endsWith('/submit-intent')) {
          loseReply = false;
          // The installed handler commits its answer before calling end.
          // Drop only that response, without retrying the submission.
          response.end = () => {response.destroy(); return response;};
        }
        return host.handler(request, response);
      });
      await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
      client = await connectRemote({mode: 'remote', token: 'fixture-principal', durability: 'durable',
        endpoint: `https://127.0.0.1:${server.address().port}/`});
    }
  };
  await open();
  return {get client() {return client;}, get computes() {return computes;},
    get root() {return root;}, get certificates() {return certificates;},
    get endpoint() {return server && `https://127.0.0.1:${server.address().port}/`;}, close, open};
}

for (const [entrance, loseSubmissionReply, defaultSubmission] of [
  ['local', false, false], ['https', false, false], ['https', true, false],
  ['local', false, true], ['https', false, true],
]) {
  test(`${entrance}${loseSubmissionReply ? ' lost reply' : ''}${defaultSubmission ? ' default submission' : ''}: ordinary installed Program retains its submission identity and Run after Host restart`, async t => {
    const f = await installedFixture(t, entrance, {loseSubmissionReply});
    let client = f.client;
    let submissionRef = defaultSubmission ? undefined : client.newSubmission({nonce: 'ordinary-original'});
    let run;
    if (loseSubmissionReply) {
      await assert.rejects(client.startSource('SELECT 1 AS n', {format: 'sql', submissionRef}), error => {
        assert.deepEqual(getSubmissionInput(error).submissionRef, submissionRef);
        return error.code === 'SubmissionUnknown';
      });
      const original = await client.lookupSubmission(submissionRef);
      assert.equal(original.kind, 'ready');
      run = await client.attach(original.admission.ref);
    } else {
      const pending = client.startSource('SELECT 1 AS n', {format: 'sql',
        ...(submissionRef === undefined ? {} : {submissionRef})});
      if (defaultSubmission) {
        submissionRef = getSubmissionInput(pending).submissionRef;
        assert.deepEqual(submissionRef.epoch, client.profile.submissionEpoch);
      }
      run = await pending;
    }
    assert.equal((await run.wait({signal: AbortSignal.timeout(15000)})).status, 'succeeded');
    assert.deepEqual(await run.result('answer').all(), [{n: 1}]);
    const first = await client.lookupSubmission(submissionRef);
    assert.equal(first.kind, 'ready');
    assert.deepEqual(first.admission.ref, run.ref);
    assert.equal(f.computes, 1);
    await f.close(); await f.open(); client = f.client;
    assert.notDeepEqual(client.newSubmission({nonce: submissionRef.nonce}), submissionRef);
    const found = await client.lookupSubmission(submissionRef);
    assert.equal(found.kind, 'ready');
    assert.deepEqual(found.submissionRef, submissionRef);
    assert.deepEqual(found.admission.ref, run.ref);
    const repeated = await client.startSource('SELECT 1 AS n', {format: 'sql', submissionRef});
    assert.deepEqual(repeated.ref, run.ref);
    assert.deepEqual(await repeated.result('answer').all(), [{n: 1}]);
    assert.equal(f.computes, 1);
  });
}

for (const entrance of ['local', 'https']) {
  test(`${entrance}: an accepted unsupported pre-Run wait remains a preparation failure after reconnect`, async t => {
    const f = await installedFixture(t, entrance, {outcome: 'delegate'});
    const pending = f.client.startSource('SELECT 1 AS n', {format: 'sql'});
    const original = getSubmissionInput(pending);
    let outcome;
    await assert.rejects(pending, error => {
      assert.equal(error.code, 'SubmissionPreparationFailed');
      assert.deepEqual(getSubmissionInput(error), original);
      outcome = getSubmissionOutcome(error);
      assert.equal(outcome.kind, 'preparation_failed');
      assert.deepEqual(outcome.submissionRef, original.submissionRef);
      assert.equal(outcome.problem.code, 'ACTQL_E_DELEGATION_UNAVAILABLE');
      assert.equal(Object.hasOwn(outcome, 'admission'), false);
      return true;
    });
    assert.equal(f.computes, 0);
    assert.deepEqual((await f.client.checkpoints()).items, []);
    assert.deepEqual(await f.client.lookupSubmission(original.submissionRef), outcome);
    await f.close(); await f.open();
    assert.deepEqual(await f.client.lookupSubmission(original.submissionRef), outcome);
    assert.deepEqual((await f.client.checkpoints()).items, []);
    await assert.rejects(f.client.startSource('SELECT 1 AS n', {format: 'sql',
      submissionRef: original.submissionRef}), error => {
      assert.deepEqual(getSubmissionOutcome(error), outcome);
      return error.code === 'SubmissionPreparationFailed';
    });
    assert.equal(f.computes, 0);
  });
}

test('installed HTTPS Host refuses epoch-less legacy execution without a Run', async t => {
  const f = await installedFixture(t, 'https');
  const response = await fetch(new URL('actql/client/0.1/submit', f.endpoint), {
    method: 'POST', headers: {'content-type': 'application/json',
      authorization: 'Bearer fixture-principal'},
    body: JSON.stringify({connection: {mode: 'remote', owner: 'remote',
      consentRefs: [], runners: [], durability: 'durable'},
    requestId: 'legacy-unbound', kind: 'aql', input: {text: 'SELECT 1 AS n', format: 'sql'},
    parameters: null}),
  });
  assert.equal(response.status, 400);
  assert.deepEqual(await response.json(), {code: 'ClientSubmissionReferenceRequired'});
  assert.deepEqual(await f.client.lookupRequest('legacy-unbound'), {kind: 'not_found'});
  assert.equal(f.computes, 0);
});

for (const entrance of ['local', 'https']) {
  test(`${entrance}: exact epoch expiry and restart fence new work while retaining original acceptance`, async t => {
    let clock = Date.now();
    const f = await installedFixture(t, entrance, {epochClock: () => clock});
    const saved = f.client.newSubmission({nonce: 'accepted-before-expiry'});
    const unaccepted = f.client.newSubmission({nonce: 'never-accepted'});
    clock = saved.epoch.expiresAt - 1;
    const pending = f.client.sql('SELECT 1 AS n', undefined, {submissionRef: saved});
    assert.deepEqual(getSubmissionInput(pending).submissionRef, saved);
    const result = await pending;
    assert.deepEqual(await result.all(), [{n: 1}]);
    const original = await f.client.lookupSubmission(saved);
    assert.equal(original.kind, 'ready');
    assert.equal(f.computes, 1);
    clock = saved.epoch.expiresAt;
    await assert.rejects(f.client.startSource('SELECT 1 AS n', {format: 'sql', submissionRef: unaccepted}));
    assert.equal((await f.client.lookupSubmission(unaccepted)).kind, 'unresolvable');
    assert.deepEqual(await f.client.lookupSubmission(saved), original);
    assert.equal(f.computes, 1);
    await f.close();
    clock = saved.epoch.notBefore; // The persisted high-water clock cannot go backwards.
    await f.open();
    await assert.rejects(f.client.startSource('SELECT 1 AS n', {format: 'sql', submissionRef: unaccepted}));
    assert.equal((await f.client.lookupSubmission(unaccepted)).kind, 'unresolvable');
    assert.deepEqual(await f.client.lookupSubmission(saved), original);
    const replay = await f.client.sql('SELECT 1 AS n', undefined, {submissionRef: saved});
    assert.deepEqual(replay.execution.ref, original.admission.ref);
    assert.deepEqual(await replay.all(), [{n: 1}]);
    assert.equal(f.computes, 1, 'expiry/restart observation and replay never create a second Compute');
  });
}

// Execute only when the matching-target native gate supplies its real binary.
// A refusal's phase and public input category survive the original lookup.
// This test uses the installed preparation/check/journal owners, with no Run.
for (const entrance of ['local', 'https']) {
  test(`${entrance}: durable known-input category survives original submission lookup after Host restart`, async t => {
    const f = await installedFixture(t, entrance);
    const submissionRef = f.client.newSubmission({nonce: 'known-input-original'});
    const pending = f.client.startSource('SELECT missing AS n', {format: 'sql', submissionRef});
    const original = getSubmissionInput(pending);
    let outcome;
    await assert.rejects(pending, error => {
      outcome = getSubmissionOutcome(error);
      assert.equal(outcome.kind, 'not_accepted');
      assert.deepEqual(outcome.submissionRef, submissionRef);
      assert.deepEqual(outcome.problem, {code: 'ClientProgramInvalidInput', classification: 'invalid_input'});
      assert.equal('admission' in outcome, false);
      return true;
    });
    assert.deepEqual(await f.client.lookupSubmission(submissionRef), outcome);
    assert.equal(f.computes, 0);
    await f.close(); await f.open();
    assert.deepEqual(await f.client.lookupSubmission(submissionRef), outcome);
    await assert.rejects(f.client.startSource(original.input.text,
      {format: original.input.format, submissionRef}), error => {
      assert.deepEqual(getSubmissionOutcome(error), outcome);
      return true;
    });
    // An exchange exception carries no validated admission outcome. Keep the
    // SDK's uncertainty rule and look up the immutable original fact instead.
    await assert.rejects(f.client.startSource('SELECT 1 AS n', {format: 'sql', submissionRef}), error => {
      assert.equal(error.code, 'SubmissionUnknown');
      assert.deepEqual(getSubmissionInput(error).submissionRef, submissionRef);
      return true;
    });
    assert.deepEqual(await f.client.lookupSubmission(submissionRef), outcome);
    assert.equal(f.computes, 0, 'lookup/replay never prepares a new Run or performs Model/Effect work');
  });
}

// Ordinary Node gates still exercise both public SDK entrances above.
if (process.env.ACTQL_NATIVE_SUBMISSION_CLIENT) {
  test('Native HTTPS: original submission survives a lost reply and Host restart', async t => {
    const f = await installedFixture(t, 'https', {loseSubmissionReply: true});
    const original = f.client.newSubmission({nonce: 'native-original'});
    await writeFile(join(f.root, 'connection.json'), JSON.stringify({mode: 'remote', owner: 'remote',
      consentRefs: [], runners: [], durability: 'durable'}));
    await writeFile(join(f.root, 'token.txt'), 'fixture-principal', {mode: 0o600});
    await writeFile(join(f.root, 'original.json'), JSON.stringify(original));
    await writeFile(join(f.root, 'query.sql'), 'SELECT 1 AS n');
    for (const [name, bytes] of [['ca.pem', f.certificates.ca], ['cert.pem', f.certificates.cert], ['key.pem', f.certificates.key]]) {
      await writeFile(join(f.root, name), bytes, {mode: 0o600});
    }
    const run = (...args) => promisify(execFile)(process.env.ACTQL_NATIVE_SUBMISSION_CLIENT,
      ['--endpoint', f.endpoint, '--connection-root', f.root, '--connection-file', 'connection.json',
        '--token-root', f.root, '--token-file', 'token.txt', '--http-library',
        process.platform === 'darwin' ? '/usr/lib/libcurl.4.dylib' : 'libcurl.so.4',
        '--ca', join(f.root, 'ca.pem'), '--cert', join(f.root, 'cert.pem'), '--key', join(f.root, 'key.pem'), ...args],
      {cwd: f.root, env: {...process.env, PATH: ''}, timeout: 20000});
    await assert.rejects(run('aql', '--program-file', 'query.sql', '--format', 'sql',
      '--submission-ref-file', 'original.json'), error => /SubmissionUnknown submission-ref-file=original.json/u.test(error.stderr));
    const lookedUp = JSON.parse((await run('lookup-submission', '--submission-ref-file', 'original.json')).stdout);
    assert.equal(lookedUp.kind, 'ready');
    assert.deepEqual(lookedUp.submissionRef, original);
    const execution = await f.client.attach(lookedUp.admission.ref);
    assert.equal((await execution.wait({until: 'terminal'})).status, 'succeeded');
    assert.deepEqual(await execution.result('answer').all(), [{n: 1}]);
    await f.close(); await f.open();
    const restored = JSON.parse((await run('lookup-submission', '--submission-ref-file', 'original.json')).stdout);
    assert.deepEqual(restored, lookedUp);
    const replay = JSON.parse((await run('aql', '--program-file', 'query.sql', '--format', 'sql',
      '--submission-ref-file', 'original.json')).stdout);
    assert.deepEqual(replay.ref, lookedUp.admission.ref);
    assert.equal(f.computes, 1, 'Native lookup/replay never allocates another Run or Compute');
  });
}
