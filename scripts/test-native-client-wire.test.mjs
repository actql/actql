import assert from 'node:assert/strict';
import {test} from 'node:test';
import {clientWireCorpus, connection, profile, ref}
  from './fixtures/client-wire-contract-corpus.mjs';
import {validClientProfile, validClientAdmission, validRunRef,
  validClientConnection, validHeldRequest, validRequestLookup, validSubmitReply}
  from '../packages/client-wire/index.mjs';
import {execFileSync, spawn} from 'node:child_process';
import {createServer} from 'node:https';
import {chmod, copyFile, mkdir, mkdtemp, readFile, writeFile}
  from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {isAbsolute, join} from 'node:path';

// An optional, independently authored JSON array can add authority-evolution
// probes without rewriting this harness or deriving expectations from a product.
// Select named probes with the ordinary --test-name-pattern and nonzero wrapper.
const corpus = [...clientWireCorpus];
const extraCorpusFile = process.env.ACTQL_TEST_CLIENT_WIRE_EXTRA_CORPUS;
if (extraCorpusFile) {
  assert.ok(isAbsolute(extraCorpusFile), 'extra corpus path must be absolute');
  const extra = JSON.parse(await readFile(extraCorpusFile, 'utf8'));
  assert.ok(Array.isArray(extra) && extra.length > 0,
    'extra corpus must be a nonempty JSON array');
  corpus.push(...extra);
}
assert.ok(corpus.length > 0, 'the contract corpus must not be empty');
assert.equal(new Set(corpus.map(entry => entry.name)).size, corpus.length,
  'contract case names must be unique');
for (const entry of corpus) {
  assert.equal(typeof entry.name, 'string');
  assert.equal(typeof entry.expected, 'boolean');
  assert.ok(['profile', 'admission', 'run_ref', 'connection', 'lookup', 'held']
    .includes(entry.kind), `unknown corpus kind: ${entry.kind}`);
  if (entry.kind === 'lookup' || entry.kind === 'held') {
    assert.equal(typeof entry.requestId, 'string');
    assert.ok(!entry.requestId.includes('\0'),
      'NUL belongs in response JSON, never a process argument');
    assert.ok(['lookup-request', 'start'].includes(entry.operation));
    assert.equal(entry.failureCode, entry.operation === 'start'
      ? 'SubmissionUnknown' : 'InvalidHostRequestLookup');
  }
}

const root = await mkdtemp(join(tmpdir(), 'actql-native-client-'));
const openssl = (...args) => execFileSync('openssl', args,
  {cwd: root, stdio: 'ignore'});
openssl('genrsa', '-out', 'ca.key', '2048');
openssl('req', '-x509', '-new', '-key', 'ca.key', '-out', 'ca.crt',
  '-subj', '/CN=ActQL Client Test CA', '-days', '1');
await writeFile(join(root, 'server.ext'),
  'subjectAltName=DNS:localhost,IP:127.0.0.1\nextendedKeyUsage=serverAuth\n');
await writeFile(join(root, 'client.ext'), 'extendedKeyUsage=clientAuth\n');
for (const [name, extension] of [['server', 'server.ext'],
  ['client', 'client.ext']]) {
  openssl('genrsa', '-out', `${name}.key`, '2048');
  openssl('req', '-new', '-key', `${name}.key`, '-out', `${name}.csr`,
    '-subj', `/CN=${name}`);
  openssl('x509', '-req', '-in', `${name}.csr`, '-CA', 'ca.crt',
    '-CAkey', 'ca.key', '-CAcreateserial', '-out', `${name}.crt`,
    '-days', '1', '-extfile', extension);
}

await writeFile(join(root, 'connection.json'), JSON.stringify(connection));
await writeFile(join(root, 'token.txt'), 'scoped-token');
let reply = profile;
let active;
const requests = [];
function responseValue(entry) {
  return entry.kind === 'run_ref'
    ? {kind: 'found', requestId: 'fixed-request', ref: entry.value,
      durability: 'durable', lookupExpiresAt: '2026-10-04T10:00:00Z'}
    : entry.value;
}
const server = createServer({
  key: await readFile(join(root, 'server.key')),
  cert: await readFile(join(root, 'server.crt')),
  ca: await readFile(join(root, 'ca.crt')),
  requestCert: true, rejectUnauthorized: true,
}, async (request, response) => {
  let raw = '';
  for await (const chunk of request) raw += chunk;
  requests.push({url: request.url, method: request.method,
    authorization: request.headers.authorization, body: JSON.parse(raw)});
  response.writeHead(200, {'content-type': 'application/json'});
  response.end(JSON.stringify(request.url.endsWith('/connect')
    ? reply : responseValue(active)));
});
const builtExecutable = new URL(
  '../_build/native/release/build/cmd/native_client/native_client.exe',
  import.meta.url).pathname;
const executable = join(root, 'actql-native-client');
await copyFile(builtExecutable, executable);
await chmod(executable, 0o755);
const emptyPath = join(root, 'empty-path');
await mkdir(emptyPath);
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const endpoint = `https://127.0.0.1:${server.address().port}/`;
const library = process.env.ACTQL_TEST_NATIVE_HTTP_LIBRARY ??
  (process.platform === 'darwin' ? '/usr/lib/libcurl.4.dylib' : 'libcurl.so.4');
const common = ['--endpoint', endpoint,
  '--connection-root', root, '--connection-file', 'connection.json',
  '--token-root', root, '--token-file', 'token.txt',
  '--http-library', library, '--ca', join(root, 'ca.crt'),
  '--cert', join(root, 'client.crt'), '--key', join(root, 'client.key')];

function runProcess(command, commandArgs) {
  return new Promise((resolve, reject) => {
    // The installed binary must not rely on a repository cwd or find Node,
    // MoonBit, curl's CLI, or another build tool through PATH.
    const child = spawn(command, commandArgs, {cwd: root,
      env: {...process.env, PATH: emptyPath}});
    let stdout = '', stderr = '';
    child.stdout.setEncoding('utf8').on('data', data => { stdout += data; });
    child.stderr.setEncoding('utf8').on('data', data => { stderr += data; });
    child.once('error', reject);
    child.once('close', (code, signal) => resolve({code, signal, stdout, stderr}));
  });
}
const run = (...args) => runProcess(executable, [...common, ...args]);

function jsOutcomes(entry, selected) {
  const {value, requestId} = entry;
  switch (entry.kind) {
    case 'profile': return [['validClientProfile',
      validClientProfile(value, selected)]];
    case 'admission': return [['validClientAdmission',
      validClientAdmission(value, selected)]];
    case 'run_ref': return [['validRunRef', validRunRef(value)]];
    case 'connection': return [['validClientConnection',
      validClientConnection(value)]];
    case 'lookup': return [['validRequestLookup',
      validRequestLookup(value, requestId)]];
    case 'held': return [
      ['validHeldRequest', validHeldRequest(value, requestId)],
      entry.operation === 'start'
        ? ['validSubmitReply', validSubmitReply(value, selected, requestId)]
        : ['validRequestLookup', validRequestLookup(value, requestId)],
    ];
    default: throw new Error(`unknown corpus kind: ${entry.kind}`);
  }
}
function commandArgs(entry) {
  const requestId = entry.requestId ?? 'fixed-request';
  if (entry.operation === 'attach') return ['attach', '--ref-file', 'ref.json'];
  if (entry.operation === 'start' || entry.kind === 'admission') {
    return ['start', '--program-file', 'program.json', '--request-id', requestId];
  }
  if (entry.operation === 'lookup-request' || entry.kind === 'run_ref') {
    return ['lookup-request', '--request-id', requestId];
  }
  return ['connect'];
}
function assertResponseBoundary(entry, selected, actual) {
  const route = entry.operation === 'start' ? 'submit' : 'lookup-request';
  assert.equal(actual.signal, null, 'Native must finish normally');
  assert.deepEqual(requests.map(request => request.url),
    ['/actql/client/0.1/connect', `/actql/client/0.1/${route}`],
    'the exact response endpoint must be reached after valid negotiation');
  for (const request of requests) {
    assert.equal(request.method, 'POST');
    assert.equal(request.authorization, 'Bearer scoped-token');
    assert.deepEqual(request.body.connection, selected);
  }
  assert.equal(requests[1].body.requestId, entry.requestId,
    'the requested identity must reach the response endpoint unchanged');
  if (route === 'submit') assert.equal(requests[1].body.kind, 'program');
  if (entry.expected) {
    assert.equal(actual.code, 0,
      `Native must accept the independent positive control: ${actual.stderr}`);
    assert.equal(actual.stderr, '');
    assert.deepEqual(JSON.parse(actual.stdout), entry.value,
      'Native must return the admitted response unchanged');
  } else {
    assert.equal(actual.code, 1,
      `Native must reject at response validation: ${actual.stderr}`);
    const diagnostic = entry.failureCode === 'SubmissionUnknown'
      ? `${entry.failureCode} request-id=${entry.requestId}` : entry.failureCode;
    assert.equal(actual.stderr, `actql-native-client: ${diagnostic}\n`,
      'argument, profile, transport, and spawn failures are not rejections');
    assert.equal(actual.stdout, '', 'a rejected response must not escape');
  }
}

try {
  await writeFile(join(root, 'program.json'), '{}');
  for (const entry of corpus) await test(entry.name, async () => {
    active = entry;
    requests.length = 0;
    const selected = entry.kind === 'connection'
      ? entry.value : entry.selected ?? connection;
    reply = entry.kind === 'profile' ? entry.value
      : {...profile, mode: selected?.mode, owner: selected?.owner};
    await writeFile(join(root, 'connection.json'), JSON.stringify(selected));
    await writeFile(join(root, 'ref.json'),
      JSON.stringify(entry.kind === 'run_ref' ? entry.value : ref));
    const outcomes = jsOutcomes(entry, selected);
    const actual = await run(...commandArgs(entry));
    for (const [validator, accepted] of outcomes) {
      assert.equal(accepted, entry.expected,
        `${validator} matches the independent expected outcome`);
    }
    if (entry.kind === 'lookup' || entry.kind === 'held') {
      assertResponseBoundary(entry, selected, actual);
    } else {
      assert.equal(actual.code === 0, entry.expected,
        `Native matches independent expected outcome: ${actual.stderr}`);
    }
    if (entry.kind === 'profile' && !entry.expected) {
      requests.length = 0;
      const subsequent = await run('start', '--program-file', 'program.json',
        '--request-id', 'blocked-request');
      assert.notEqual(subsequent.code, 0);
      assert.deepEqual(requests.map(request => request.url),
        ['/actql/client/0.1/connect'], 'malformed profile stops before submit');
    }
    if (entry.kind === 'connection' && !entry.expected) {
      assert.equal(requests.length, 0, 'invalid connection stops before network');
    }
  });
} finally {
  await new Promise(resolve => server.close(resolve));
}
