import assert from 'node:assert/strict';
import {execFileSync, spawn} from 'node:child_process';
import {createServer} from 'node:https';
import {mkdtemp, readFile, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';

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

const connection = {mode: 'remote', owner: 'remote',
  consentRefs: [], runners: []};
const ref = {tenantId: 'tenant-a',
  authorityScopeCid: `sha256:${'a'.repeat(64)}`,
  runDefinitionCid: `sha256:${'b'.repeat(64)}`};
const profile = {version: 'actql-client-host/0.1',
  mode: 'remote', owner: 'remote', durability: 'durable',
  scopeRef: 'principal-a', capabilities: ['aql-document', 'result-jsonl'],
  limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024,
    maxRowRetainedValueBytes: 1024, maxRetainedValueBytes: 4096,
    maxRows: 10, maxBatchRows: 3, maxBatchRetainedValueBytes: 1024}};
await writeFile(join(root, 'connection.json'), JSON.stringify(connection));
await writeFile(join(root, 'connection-durable.json'),
  JSON.stringify({...connection, durability: 'durable'}));
await writeFile(join(root, 'ref.json'), JSON.stringify(ref));
await writeFile(join(root, 'token.txt'), 'scoped-token\n');
await writeFile(join(root, 'parameters.json'), '{"minimum":1}');
await writeFile(join(root, 'program.json'), await readFile(new URL(
  '../packages/sdk/fixtures/values.json', import.meta.url)));

const requests = [];
const server = createServer({key: await readFile(join(root, 'server.key')),
  cert: await readFile(join(root, 'server.crt')),
  ca: await readFile(join(root, 'ca.crt')),
  requestCert: true, rejectUnauthorized: true}, async (request, response) => {
  const operation = request.url?.split('/').at(-1);
  let raw = '';
  for await (const chunk of request) raw += chunk;
  const body = JSON.parse(raw);
  requests.push({operation, body, authorization: request.headers.authorization});
  assert.equal(request.headers.authorization, 'Bearer scoped-token');
  assert.equal(request.method, 'POST');
  assert.deepEqual(body.connection, body.connection.durability === 'durable'
    ? {...connection, durability: 'durable'} : connection);
  if (operation === 'submit' && body.requestId === 'lost-ack') {
    response.destroy();
    return;
  }
  if (operation === 'submit' && body.requestId === 'malformed-ack') {
    response.writeHead(200, {'content-type': 'application/json'});
    response.end('{"bad":true}');
    return;
  }
  response.writeHead(200, {'content-type': operation === 'read'
    ? 'application/x-ndjson' : 'application/json'});
  if (operation === 'connect') response.end(JSON.stringify(
    body.connection.durability === 'durable'
      ? {...profile, durability: 'volatile'} : profile));
  else if (operation === 'submit' || operation === 'attach') {
    response.end(JSON.stringify({ref, durability: 'durable', revision: 1}));
  } else if (operation === 'lookup-request') {
    response.end(JSON.stringify({kind: 'unknown', reason: 'query_failed'}));
  } else if (operation === 'status') {
    response.end(JSON.stringify({status: 'succeeded'}));
  } else if (operation === 'delivery-attempt') {
    response.end(JSON.stringify({kind: 'not_found'}));
  } else if (operation === 'read') {
    response.end(body.attemptId === 'prefix' ? '{"value":7}\n'
      : '{"value":7}\n\x1e');
  } else {
    response.end('{}');
  }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const endpoint = `https://127.0.0.1:${server.address().port}/`;
const executable = new URL('../_build/native/release/build/cmd/native_client/' +
  'native_client.exe', import.meta.url).pathname;
const library = process.env.ACTQL_TEST_NATIVE_HTTP_LIBRARY ??
  (process.platform === 'darwin' ? '/usr/lib/libcurl.4.dylib' : 'libcurl.so.4');
const common = ['--endpoint', endpoint,
  '--connection-root', root, '--connection-file', 'connection.json',
  '--token-root', root, '--token-file', 'token.txt',
  '--http-library', library, '--ca', join(root, 'ca.crt'),
  '--cert', join(root, 'client.crt'), '--key', join(root, 'client.key')];

function runProcess(command, commandArgs) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, commandArgs);
    let stdout = '', stderr = '';
    child.stdout.setEncoding('utf8').on('data', data => { stdout += data; });
    child.stderr.setEncoding('utf8').on('data', data => { stderr += data; });
    child.once('error', reject);
    child.once('close', code => resolve({code, stdout, stderr}));
  });
}
const runWith = (commonArgs, ...args) =>
  runProcess(executable, [...commonArgs, ...args]);
const run = (...args) => runWith(common, ...args);

try {
  const connected = await run('connect');
  assert.equal(connected.code, 0, connected.stderr);
  assert.deepEqual(JSON.parse(connected.stdout), profile);
  if (process.platform === 'darwin' &&
      process.env.ACTQL_MEASURE_NATIVE_CLIENT === '1') {
    const timed = await runProcess('/usr/bin/time',
      ['-l', executable, ...common, 'connect']);
    assert.equal(timed.code, 0, timed.stderr);
    assert.deepEqual(JSON.parse(timed.stdout), profile);
    assert.match(timed.stderr, /maximum resident set size/);
    console.log(timed.stderr.trim());
  }
  const durableArgs = [...common];
  durableArgs[durableArgs.indexOf('--connection-file') + 1] =
    'connection-durable.json';
  const downgraded = await runWith(durableArgs, 'connect');
  assert.notEqual(downgraded.code, 0);
  assert.match(downgraded.stderr, /requested durable profile is unavailable/);
  const submitted = await run('aql', '--program-file', 'program.json',
    '--parameters-file', 'parameters.json', '--format', 'json',
    '--request-id', 'saved-id');
  assert.equal(submitted.code, 0, submitted.stderr);
  assert.deepEqual(JSON.parse(submitted.stdout),
    {ref, durability: 'durable', revision: 1});
  const sent = requests.find(item => item.operation === 'submit');
  assert.equal(sent.body.requestId, 'saved-id');
  assert.equal(sent.body.kind, 'aql');
  assert.equal(sent.body.input.format, 'json');
  assert.deepEqual(sent.body.parameters, {minimum: 1});
  assert.deepEqual(JSON.parse(sent.body.input.text),
    JSON.parse(await readFile(join(root, 'program.json'), 'utf8')));
  const status = await run('status', '--ref-file', 'ref.json');
  assert.equal(status.code, 0, status.stderr);
  assert.deepEqual(JSON.parse(status.stdout), {status: 'succeeded'});
  const attached = await run('attach', '--ref-file', 'ref.json');
  assert.equal(attached.code, 0, attached.stderr);
  assert.deepEqual(JSON.parse(attached.stdout),
    {ref, durability: 'durable', revision: 1});
  const read = await run('read', '--ref-file', 'ref.json',
    '--result-name', 'answer', '--attempt-id', 'attempt-a');
  assert.equal(read.code, 0, read.stderr);
  assert.equal(read.stdout, '{"value":7}\n');
  const attempt = await run('delivery-attempt', '--ref-file', 'ref.json',
    '--result-name', 'answer', '--attempt-id', 'attempt-a');
  assert.equal(attempt.code, 0, attempt.stderr);
  assert.deepEqual(JSON.parse(attempt.stdout), {kind: 'not_found'});
  const prefix = await run('read', '--ref-file', 'ref.json',
    '--result-name', 'answer', '--attempt-id', 'prefix');
  assert.notEqual(prefix.code, 0);
  assert.match(prefix.stderr, /IncompleteResultStream attempt-id=prefix/);
  assert.doesNotMatch(prefix.stdout, /"value"/);
  const started = await run('start', '--program-file', 'program.json',
    '--request-id', 'program-id');
  assert.equal(started.code, 0, started.stderr);
  assert.deepEqual(JSON.parse(started.stdout),
    {ref, durability: 'durable', revision: 1});
  assert.equal(requests.find(item => item.operation === 'submit' &&
    item.body.requestId === 'program-id').body.kind, 'program');
  const malformed = await run('aql', '--program-file', 'program.json',
    '--format', 'json', '--request-id', 'malformed-ack');
  assert.notEqual(malformed.code, 0);
  assert.match(malformed.stderr,
    /SubmissionUnknown request-id=malformed-ack/);
  const uncertain = await run('aql', '--program-file', 'program.json',
    '--format', 'json', '--request-id', 'lost-ack');
  assert.notEqual(uncertain.code, 0);
  assert.match(uncertain.stderr, /SubmissionUnknown request-id=lost-ack/);
  const lookedUp = await run('lookup-request', '--request-id', 'lost-ack');
  assert.equal(lookedUp.code, 0, lookedUp.stderr);
  assert.deepEqual(JSON.parse(lookedUp.stdout),
    {kind: 'unknown', reason: 'query_failed'});
  assert.equal(requests.filter(item => item.operation === 'submit' &&
    item.body.requestId === 'lost-ack').length, 1);
  for (const [index, item] of requests.entries()) {
    if (item.operation !== 'connect') {
      assert.equal(requests[index - 1]?.operation, 'connect');
    }
  }
  console.log('native Client mTLS tests passed');
} finally {
  await new Promise(resolve => server.close(resolve));
}
