// Copied into a repository-external installation of only @actql/node.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createServer} from 'node:https';
import {readFile, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {userInfo} from 'node:os';
import {connect} from '@actql/node';
import {openInstalledRemoteHttpHost} from '@actql/local-node/http-host';

const executable = process.argv[2]; assert(executable);
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
const host = await openInstalledRemoteHttpHost({directory: join(root, 'host-state'), authorization,
  beforeDispatch: () => {computes++;}, authenticate: header => header === 'Bearer fixture-token' ? userInfo().username : undefined});
const certificate = await readFile('remote.crt');
const server = createServer({key: await readFile('remote.key'), cert: certificate,
  ca: certificate, requestCert: true, rejectUnauthorized: true}, host.handler);
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const endpoint = `https://127.0.0.1:${server.address().port}/`;
// The Native transport uses mTLS. The independent SDK schema check uses its
// standard server-authenticated HTTPS transport against the same Host owner.
const schemaServer = createServer({key: await readFile('remote.key'), cert: certificate}, host.handler);
await new Promise(resolve => schemaServer.listen(0, '127.0.0.1', resolve));
await writeFile('connection.json', JSON.stringify({mode: 'remote', owner: 'remote', durability: 'durable', consentRefs: [], runners: []}));
await writeFile('token.txt', 'fixture-token\n', {mode: 0o600});
await writeFile('query.sql', 'SELECT 1 AS id UNION ALL SELECT 2 AS id ORDER BY id');
const common = ['--endpoint', endpoint, '--connection-root', root, '--connection-file', 'connection.json',
  '--token-root', root, '--token-file', 'token.txt', '--http-library', process.platform === 'darwin' ? '/usr/lib/libcurl.4.dylib' : 'libcurl.so.4',
  '--ca', join(root, 'remote.crt'), '--cert', join(root, 'remote.crt'), '--key', join(root, 'remote.key')];
async function run(...args) {
  const record = await new Promise((resolve, reject) => {
    const child = spawn(executable, [...common, ...args], {cwd: root, env: childEnvironment, stdio: ['ignore', 'pipe', 'pipe']});
    let stdout = '', stderr = '', bytes = 0, terminationReason = null;
    const timer = setTimeout(() => {terminationReason = 'original-child-timeout'; child.kill('SIGTERM');}, 30_000);
    const append = (chunk, error) => {
      bytes += chunk.length;
      if (bytes > 8 * 1024 * 1024) {terminationReason = 'output-limit'; child.kill('SIGTERM');}
      else if (error) stderr += chunk; else stdout += chunk;
    };
    child.stdout.on('data', chunk => append(chunk, false)); child.stderr.on('data', chunk => append(chunk, true));
    child.once('error', error => {clearTimeout(timer); reject(error);});
    child.once('close', (code, signal) => {clearTimeout(timer); resolve({args, code, signal, terminationReason, stdout, stderr});});
  });
  records.push(record);
  await writeFile('native-commands.json', JSON.stringify(records, null, 2));
  assert.equal(record.code, 0, `${args[0]}: ${record.stderr}`); assert.equal(record.signal, null);
  assert.equal(record.terminationReason, null); return record.stdout;
}
let client;
try {
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
} finally {
  await client?.close();
  await new Promise(resolve => schemaServer.close(resolve));
  await new Promise(resolve => server.close(resolve));
  await host.close();
}
if (standaloneHome !== undefined) {
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
