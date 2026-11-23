// Copied into a repository-external installation of only @actql/node.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createServer} from 'node:https';
import {readFile, writeFile} from 'node:fs/promises';
import {isAbsolute, join} from 'node:path';
import {userInfo} from 'node:os';
import {connect} from '@actql/node';
import {openInstalledRemoteHttpHost} from '@actql/local-node/http-host';

const executable = process.argv[2]; assert(executable);
const sharedClients = process.argv[3] === '--shared-clients';
const sharedSavedRestart = process.argv[3] === '--shared-saved-restart';
const sharedNames = process.argv[3] === '--shared-names';
const lostReplyOnly = sharedNames && process.argv[4] === '--lost-reply-only';
assert(process.argv.length === 3 || (process.argv.length === 4 && (sharedClients || sharedSavedRestart || sharedNames)) ||
  (process.argv.length === 5 && lostReplyOnly),
  'Unknown Remote Host fixture selection');
const root = process.cwd(), records = [];
// Only the standalone acceptance harness selects this environment. The Host
// driver is separate; its Native children have no Node/npm/tool search path.
const standaloneHome = process.env.ACTQL_TEST_NATIVE_STANDALONE_HOME;
const childEnvironment = standaloneHome === undefined ? undefined : {
  PATH: '', HOME: standaloneHome, TMPDIR: join(standaloneHome, 'tmp'), LANG: 'C',
};
// Authentication identifies the caller; the operator still supplies the exact
// Account permissions for the pure request and its two independent read scopes.
const authorization = {accountConfiguration: JSON.stringify({
  version: 'actql-execution-account-config/0.1', account_id: 'native-release-http',
  entries: [{entry_id: 'compute-write', outcome: 'allow',
    principal: {any_of: [userInfo().username]},
    connection: {any_of: ['actql-remote-host']},
    resource: {any_of: ['source-free-values']},
    operation: {any_of: ['write']}, exclusions: []},
  {entry_id: 'result-main-read', outcome: 'allow',
    principal: {any_of: [userInfo().username]},
    connection: {any_of: ['actql-remote-host']},
    resource: {any_of: ['result/main']},
    operation: {any_of: ['read']}, exclusions: []},
  {entry_id: 'run-read', outcome: 'allow',
    principal: {any_of: [userInfo().username]},
    connection: {any_of: ['actql-remote-host']},
    resource: {any_of: ['run']},
    operation: {any_of: ['read']}, exclusions: []}],
})};
let computes = 0;
const host = await openInstalledRemoteHttpHost({directory: join(root, sharedNames ? 'host-state-names' : 'host-state'), authorization,
  beforeDispatch: () => {computes++;}, authenticate: header => header === 'Bearer fixture-token' ? userInfo().username : undefined});
const certificate = await readFile('remote.crt');
const server = createServer({key: await readFile('remote.key'), cert: certificate,
  ca: certificate, requestCert: true, rejectUnauthorized: true}, host.handler);
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const endpoint = `https://127.0.0.1:${server.address().port}/`;
// The Native transport uses mTLS. The independent SDK schema check uses its
// standard server-authenticated HTTPS transport against the same Host owner.
let loseNamedReply = false, lostNamedReplies = 0, namedSubmissions = 0;
const schemaServer = createServer({key: await readFile('remote.key'), cert: certificate}, (request, response) => {
  if (sharedNames && request.url === '/actql/client/0.1/submit-named-intent') {
    namedSubmissions++;
    if (loseNamedReply) {
      loseNamedReply = false;
      // Drop only this actual Host reply, after its original operation reaches
      // response completion. There is no replacement reply or automatic resend.
      response.end = () => {lostNamedReplies++; response.destroy(); return response;};
    }
  }
  host.handler(request, response);
});
await new Promise(resolve => schemaServer.listen(0, '127.0.0.1', resolve));
await writeFile('connection.json', JSON.stringify({mode: 'remote', owner: 'remote', durability: 'durable', consentRefs: [], runners: []}));
await writeFile('token.txt', 'fixture-token\n', {mode: 0o600});
await writeFile('query.sql', 'SELECT 1 AS id UNION ALL SELECT 2 AS id ORDER BY id');
const selectedHttpLibrary = process.env.ACTQL_TEST_NATIVE_HTTP_LIBRARY;
if (selectedHttpLibrary !== undefined) assert(isAbsolute(selectedHttpLibrary), 'Use the admitted installed HTTP member');
const compatibilityHttpLibrary = process.platform === 'darwin' ? '/usr/lib/libcurl.4.dylib' : 'libcurl.so.4';
const common = ['--endpoint', endpoint, '--connection-root', root, '--connection-file', 'connection.json',
  '--token-root', root, '--token-file', 'token.txt', '--http-library', selectedHttpLibrary ?? compatibilityHttpLibrary,
  '--ca', join(root, 'remote.crt'), '--cert', join(root, 'remote.crt'), '--key', join(root, 'remote.key')];
let commandWrites = Promise.resolve();
async function runCaptured(command, argv, args = argv) {
  const startedAt = new Date().toISOString();
  const record = await new Promise((resolve, reject) => {
    const child = spawn(command, argv, {cwd: root, env: childEnvironment, stdio: ['ignore', 'pipe', 'pipe']});
    let stdout = '', stderr = '', bytes = 0, terminationReason = null;
    const timer = setTimeout(() => {terminationReason = 'original-child-timeout'; child.kill('SIGTERM');}, 30_000);
    const append = (chunk, error) => {
      bytes += chunk.length;
      if (bytes > 8 * 1024 * 1024) {terminationReason = 'output-limit'; child.kill('SIGTERM');}
      else if (error) stderr += chunk; else stdout += chunk;
    };
    child.stdout.on('data', chunk => append(chunk, false)); child.stderr.on('data', chunk => append(chunk, true));
    child.once('error', error => {clearTimeout(timer); reject(error);});
    child.once('close', (code, signal) => {clearTimeout(timer); resolve({args, pid: child.pid ?? null, startedAt, endedAt: new Date().toISOString(), code, signal, terminationReason, stdout, stderr});});
  });
  records.push(record);
  // Serialize only evidence-file replacement, never the actual Native calls.
  const complete = JSON.stringify(records, null, 2);
  commandWrites = commandWrites.then(() => writeFile(sharedNames ? 'named-client-commands.json' : sharedSavedRestart ? 'native-restart-commands.json' : 'native-commands.json', complete));
  await commandWrites;
  assert.equal(record.code, 0, `${args[0]}: ${record.stderr}`); assert.equal(record.signal, null);
  assert.equal(record.terminationReason, null); return record.stdout;
}
function run(...args) {return runCaptured(executable, [...common, ...args], args);}
// Concurrent actors finish under their original child bounds even when a peer
// fails. Preserve the first actual failure instead of closing their shared Host
// while another original command is still running.
async function parallel(commands) {
  let firstFailure;
  const results = await Promise.allSettled(commands.map(command => command().catch(error => {
    firstFailure ??= error; throw error;
  })));
  if (firstFailure !== undefined) throw firstFailure;
  return results.map(result => result.value);
}
async function sharedClientCase() {
  const actors = ['first', 'second'].map(name => ({name,
    requestId: `native-shared-${name}`, submissionFile: `submission-${name}.json`,
    refFile: `run-${name}.json`}));
  await parallel(actors.map(actor => async () => {
    actor.submission = JSON.parse(await run('new-submission', '--request-id', actor.requestId));
    await writeFile(actor.submissionFile, JSON.stringify(actor.submission), {mode: 0o600});
  }));
  await parallel(actors.map(actor => async () => {
    actor.admission = JSON.parse(await run('aql', '--program-file', 'query.sql', '--format', 'sql',
      '--submission-ref-file', actor.submissionFile, '--request-id', actor.requestId,
      '--operation-attempt-id', `native-shared-submit-${actor.name}`));
    assert(actor.admission.ref);
    // Preserve each actual original reference before its first wait.
    await writeFile(actor.refFile, JSON.stringify(actor.admission.ref), {mode: 0o600});
  }));
  assert.notDeepEqual(actors[0].admission.ref, actors[1].admission.ref);
  await parallel(actors.map(actor => async () => {
    assert.equal(JSON.parse(await run('wait', '--ref-file', actor.refFile)).status, 'succeeded');
    const rows = (await run('read', '--ref-file', actor.refFile, '--result-name', 'main',
      '--attempt-id', `native-shared-first-read-${actor.name}`)).trimEnd().split('\n').map(JSON.parse);
    assert.deepEqual(rows, [{id: 1}, {id: 2}]);
  }));
  const detached = await connect({mode: 'remote', endpoint: `https://127.0.0.1:${schemaServer.address().port}/`,
    token: 'fixture-token', durability: 'durable'});
  try {
    const attached = await detached.attach(actors[0].admission.ref);
    assert.deepEqual((await attached.result('main').describe()).columns,
      [{name: 'id', contract: {type: 'number', nullable: false}}]);
  } finally {await detached.close();}
  // A detached SDK client and exited Native commands do not close the Owner.
  // These are separate NEW Native processes reading SAME original references.
  await parallel(actors.map(actor => async () => {
    const attached = JSON.parse(await run('attach', '--ref-file', actor.refFile));
    assert.deepEqual(attached.ref, actor.admission.ref);
    const lookup = JSON.parse(await run('lookup-submission', '--submission-ref-file', actor.submissionFile));
    assert.equal(lookup.kind, 'ready'); assert.deepEqual(lookup.admission.ref, actor.admission.ref);
    const rows = (await run('read', '--ref-file', actor.refFile, '--result-name', 'main',
      '--attempt-id', `native-shared-saved-read-${actor.name}`)).trimEnd().split('\n').map(JSON.parse);
    assert.deepEqual(rows, [{id: 1}, {id: 2}]);
  }));
  assert.equal(computes, 2, 'Saved lookups and client detachment must not issue another Compute');
  await writeFile('native-shared-host-acceptance.json', JSON.stringify({
    version: 'actql-native-shared-host-acceptance/0.1',
    scope: 'parallel-new-and-saved-client-detach', actors, computes,
    sdkClientCloseReturned: true, ownerClose: 'not_yet_attempted', operations: records,
    unexecuted: ['active-cancel-isolation', 'named-conflict', 'client-crash', 'owner-crash-restart'],
  }, null, 2));
}
// A new explicit owner opens the original successful state only after the
// first owner has actually exited. No submission or execution is reconstructed.
async function sharedSavedRestartCase() {
  const original = JSON.parse(await readFile('native-shared-host-acceptance.json', 'utf8'));
  assert.equal(original.actors.length, 2);
  for (const actor of original.actors) {
    const ref = JSON.parse(await readFile(actor.refFile, 'utf8'));
    assert.deepEqual(ref, actor.admission.ref);
    const attached = JSON.parse(await run('attach', '--ref-file', actor.refFile));
    assert.deepEqual(attached.ref, ref);
    const lookup = JSON.parse(await run('lookup-submission', '--submission-ref-file', actor.submissionFile));
    assert.equal(lookup.kind, 'ready'); assert.deepEqual(lookup.admission.ref, ref);
    assert.equal(JSON.parse(await run('status', '--ref-file', actor.refFile)).status, 'succeeded');
    const rows = (await run('read', '--ref-file', actor.refFile, '--result-name', 'main',
      '--attempt-id', `native-shared-restarted-read-${actor.name}`)).trimEnd().split('\n').map(JSON.parse);
    assert.deepEqual(rows, [{id: 1}, {id: 2}]);
  }
  assert.equal(computes, 0, 'Owner restart and Saved reads must not dispatch another Compute');
  await writeFile('native-shared-host-restart-acceptance.json', JSON.stringify({
    version: 'actql-native-shared-host-restart-acceptance/0.1',
    scope: 'explicit-owner-restart-after-graceful-exit', originalActors: original.actors.map(actor => actor.name),
    computes, operations: records, ownerClose: 'not_yet_attempted',
    unexecuted: ['owner-crash-recovery', 'active-cancel-isolation', 'named-conflict', 'client-crash'],
  }, null, 2), {flag: 'wx'});
}
async function sharedNamesCase() {
  const endpoint = `https://127.0.0.1:${schemaServer.address().port}/`;
  const child = phase => runCaptured(process.execPath,
    [join(root, 'named-client.mjs'), phase, endpoint], ['named-client', phase]);
  if (!lostReplyOnly) {
    await child('first'); assert.equal(computes, 1);
    await child('duplicate'); assert.equal(computes, 1);
    await child('conflict'); assert.equal(computes, 1);
  }
  loseNamedReply = true;
  await child('lost'); assert.equal(lostNamedReplies, 1);
  await child('lookup'); assert.equal(computes, lostReplyOnly ? 1 : 2);
  assert.equal(namedSubmissions, lostReplyOnly ? 1 : 4, 'Lookup must not resend the uncertain submission');
  await writeFile('named-shared-host-acceptance.json', JSON.stringify({
    version: 'actql-named-shared-host-acceptance/0.1',
    scope: 'public SDK independent CLI named binding/conflict/lost-reply lookup',
    computes, namedSubmissions, lostNamedReplies, lostReplyOnly, operations: records,
    ownerClose: 'not_yet_attempted',
    unexecuted: ['active-cancel-isolation', 'client-crash', 'owner-crash-recovery'],
  }, null, 2), {flag: 'wx'});
}
let client;
async function singleClientCase() {
  assert.equal(JSON.parse(await run('connect')).mode, 'remote');
  const original = JSON.parse(await run('new-submission', '--request-id', 'native-release-query'));
  await writeFile('submission.json', JSON.stringify(original), {mode: 0o600});
  const accepted = JSON.parse(await run('aql', '--program-file', 'query.sql', '--format', 'sql',
    '--submission-ref-file', 'submission.json', '--request-id', 'native-release-query',
    '--operation-attempt-id', 'native-release-submit-invocation'));
  assert(accepted.ref);
  await writeFile('run.json', JSON.stringify(accepted.ref), {mode: 0o600});
  assert.equal(JSON.parse(await run('wait', '--ref-file', 'run.json')).status, 'succeeded');
  assert.equal(JSON.parse(await run('status', '--ref-file', 'run.json')).status, 'succeeded');
  const attached = JSON.parse(await run('attach', '--ref-file', 'run.json')); assert.deepEqual(attached.ref, accepted.ref);
  const lookup = JSON.parse(await run('lookup-submission', '--submission-ref-file', 'submission.json'));
  assert.equal(lookup.kind, 'ready'); assert.deepEqual(lookup.admission.ref, accepted.ref);
  const rows = (await run('read', '--ref-file', 'run.json', '--result-name', 'main', '--attempt-id', 'native-release-read'))
    .trimEnd().split('\n').map(JSON.parse);
  assert.deepEqual(rows, [{id: 1}, {id: 2}]);
  const delivery = JSON.parse(await run('delivery-attempt', '--ref-file', 'run.json',
    '--result-name', 'main', '--attempt-id', 'native-release-read'));
  assert.equal(delivery.kind, 'found');
  assert.equal(delivery.attempt.attempt_id, 'native-release-read');
  assert.equal(delivery.record.state, 'succeeded');
  assert(delivery.hostReleaseReceipt, 'The real Host must retain its Result release evidence');
  client = await connect({mode: 'remote', endpoint: `https://127.0.0.1:${schemaServer.address().port}/`,
    token: 'fixture-token', durability: 'durable'});
  const execution = await client.attach(accepted.ref);
  assert.deepEqual((await execution.result('main').describe()).columns,
    [{name: 'id', contract: {type: 'number', nullable: false}}]);
  const cancellation = JSON.parse(await run('cancel', '--ref-file', 'run.json', '--cancel-id', 'native-release-terminal-cancel',
    '--expected-revision', String(attached.revision),
    '--operation-attempt-id', 'native-release-terminal-invocation'));
  assert.equal(cancellation.kind, 'already_satisfied');
  assert.deepEqual(cancellation.attemptRef, {operation: 'cancel', attemptId: 'native-release-terminal-invocation'});
  assert.equal(cancellation.cancellation.kind, 'already_terminal');
  const cancelled = JSON.parse(await run('lookup-cancellation', '--ref-file', 'run.json', '--cancel-id', 'native-release-terminal-cancel',
    '--expected-revision', String(attached.revision)));
  assert.equal(cancelled.kind, 'found'); assert.deepEqual(cancelled.cancellation, cancellation.cancellation);
  assert.equal(computes, 1, 'Lookup, reads and terminal cancel must not start another Compute');
  await writeFile('native-host-acceptance.json', JSON.stringify({version: 'actql-native-release-host-acceptance/0.1',
    rows, computes, operations: records}, null, 2));
  console.log('Installed Native Remote CLI: real Host connect, submit, wait, lookup, Result/schema, terminal cancel and cleanup passed');
}
try {
  if (sharedNames) {
    await sharedNamesCase();
    console.log(lostReplyOnly
      ? 'Installed shared Host: lost-reply original recovery target lookup passed; duplicate/conflict not repeated'
      : 'Installed shared Host: named duplicate/conflict and lost-reply original lookup passed');
  } else if (sharedSavedRestart) {
    await sharedSavedRestartCase();
    console.log('Installed Native shared Host: explicit owner restart and SAME original Saved reads passed');
  } else if (sharedClients) {
    await sharedClientCase();
    console.log('Installed Native shared Host: parallel NEW, original Saved and detached-client independence passed');
  } else {
    await singleClientCase();
  }
} finally {
  await client?.close();
  await new Promise(resolve => schemaServer.close(resolve));
  await new Promise(resolve => server.close(resolve));
  await host.close();
}
if (standaloneHome !== undefined || sharedClients || sharedSavedRestart || sharedNames) {
  // All original explicit close calls above returned before this observation.
  // The parent observes this SAME still-live Host process, then acknowledges.
  console.log(JSON.stringify({stage: 'closed', pid: process.pid, clientCloseReturned: true, hostCloseReturned: true}));
  const acknowledgement = await new Promise(resolve => {
    let input = ''; process.stdin.setEncoding('utf8');
    process.stdin.on('data', chunk => {input += chunk; if (input.includes('\n')) resolve(input);});
    process.stdin.once('end', () => resolve(input));
  });
  assert.equal(acknowledgement, 'observed\n');
  console.log(JSON.stringify({stage: 'close-observation-ack', pid: process.pid}));
}
