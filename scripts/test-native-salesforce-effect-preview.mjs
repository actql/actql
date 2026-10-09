import assert from 'node:assert/strict';
import {spawn, execFileSync} from 'node:child_process';
import {createHash, generateKeyPairSync, sign} from 'node:crypto';
import {once} from 'node:events';
import {mkdir, mkdtemp, readFile, writeFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {join} from 'node:path';

const scratch = process.env.ACTQL_TEST_SCRATCH_ROOT;
assert(typeof scratch === 'string' && scratch.length > 0,
  'ACTQL_TEST_SCRATCH_ROOT is required');
await mkdir(scratch, {recursive: true});
const root = await mkdtemp(join(scratch, 'native-salesforce-target-'));
const openssl = (...args) => execFileSync('openssl', args,
  {cwd: root, stdio: 'ignore', timeout: 10_000});
openssl('req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-keyout',
  'ca.key', '-out', 'ca.crt', '-days', '1', '-subj', '/CN=ActQL Target Test CA');
openssl('req', '-newkey', 'rsa:2048', '-nodes', '-keyout', 'server.key',
  '-out', 'server.csr', '-subj', '/CN=localhost');
await writeFile(join(root, 'server.ext'),
  'subjectAltName=DNS:localhost,IP:127.0.0.1\nextendedKeyUsage=serverAuth\n');
openssl('x509', '-req', '-in', 'server.csr', '-CA', 'ca.crt', '-CAkey',
  'ca.key', '-CAcreateserial', '-out', 'server.crt', '-days', '1',
  '-extfile', 'server.ext');
await writeFile(join(root, 'credential.secret'), 'native-target-test\n',
  {mode: 0o600});
const paths = [];
let writes = 0;
const expected = '/services/data/v66.0/sobjects/ActQL_Test_Record__c/';
const server = createServer({key: await readFile(join(root, 'server.key')),
  cert: await readFile(join(root, 'server.crt'))}, (request, response) => {
  if (request.method !== 'GET') writes++;
  paths.push({method: request.method, path: request.url});
  if (request.headers.authorization !== 'Bearer native-target-test' ||
      request.method !== 'GET' ||
      ![expected + '001000000000001', expected + '001000000000002']
        .includes(request.url)) {
    response.writeHead(403); response.end(); return;
  }
  // An actual physical fixture record, independent of the proposed update.
  // The second path deliberately returns a foreign record for the refusal case.
  response.writeHead(200, {'content-type': 'application/json'});
  response.end(JSON.stringify({Id: '001000000000001AAA',
    Optional_Value__c: 'e\u0301\r\n'}));
});
let child;
try {
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const origin = `https://127.0.0.1:${server.address().port}`;
  const hash = bytes => 'sha256:' + createHash('sha256').update(bytes).digest('hex');
  // Independent wire fixture, admitted and signature-checked by the real
  // credential Owner. No Cloud materials or Preview success are synthesized.
  const body = JSON.stringify({connector_registration: 'salesforce',
    connector_revision: 'salesforce/0.1',
    dispatch_request_cid: 'sha256:' + 'c'.repeat(64), environment: 'test',
    expires_unix_ms: '2000000000000', issuer_authority: 'credential-authority-a',
    max_uses: 1, namespace_id: 'namespace-a', operation: 'salesforce:record:observe',
    principal: 'principal-a', resource_origin: origin,
    run_invocation_cid: 'sha256:' + 'b'.repeat(64),
    runtime_bundle_cid: 'sha256:' + 'a'.repeat(64), site_generation: 4,
    site_key: 'site-a', task_attempt: 3, version: 'actql-remote-credential-grant/0.1'});
  const cid = hash(body);
  const keys = generateKeyPairSync('ed25519');
  const signature = sign(null,
    Buffer.from('actql-remote-credential-grant-signature/0.1\0' + cid + '\0' + body),
    keys.privateKey).toString('base64url');
  const testEnv = {...process.env,
    ACTQL_TEST_NATIVE_HTTP_URL: origin,
    ACTQL_TEST_NATIVE_HTTP_CA: join(root, 'ca.crt'),
    ACTQL_TEST_NATIVE_HTTP_SECRET: join(root, 'credential.secret'),
    ACTQL_TEST_NATIVE_HTTP_LIBRARY: process.env.ACTQL_TEST_NATIVE_HTTP_LIBRARY ??
      (process.platform === 'darwin' ? '/usr/lib/libcurl.4.dylib' : 'libcurl.so.4'),
    ACTQL_TEST_NATIVE_SQLITE_LIBRARY: process.env.ACTQL_TEST_NATIVE_SQLITE_LIBRARY ??
      (process.platform === 'darwin' ? '/usr/lib/libsqlite3.dylib' : 'libsqlite3.so.0'),
    ACTQL_TEST_NATIVE_CRYPTO_LIBRARY: process.env.ACTQL_TEST_NATIVE_CRYPTO_LIBRARY ??
      (process.platform === 'darwin' ? '/opt/homebrew/opt/openssl@3/lib/libcrypto.3.dylib' : 'libcrypto.so.3'),
    ACTQL_TEST_NATIVE_TARGET_ROOT: root,
    ACTQL_TEST_NATIVE_CREDENTIAL_GRANT_BODY: body,
    ACTQL_TEST_NATIVE_CREDENTIAL_GRANT_CID: cid,
    ACTQL_TEST_NATIVE_CREDENTIAL_SIGNATURE: signature,
    ACTQL_TEST_NATIVE_CREDENTIAL_PUBLIC_KEY:
      keys.publicKey.export({type: 'spki', format: 'pem'}),
  };
  child = spawn(process.execPath, ['--input-type=module', '-e',
    "import {runFocusedTests} from './scripts/test-execution.mjs'; " +
    "process.exitCode = runFocusedTests('moon', ['--target', 'native', '--strip', " +
    "'src/platform_native/salesforce_effect_preview/target_native_wbtest.mbt'], " +
    "{timeout: 180000, evidenceScratch: " + JSON.stringify(root) + "});"],
  {env: testEnv, stdio: 'inherit'});
  const [code, signal] = await once(child, 'close');
  child = undefined;
  await writeFile(join(root, 'physical-receipt.json'), JSON.stringify({
    code, signal, requests: paths, writes,
    scope: 'Native HTTPS target observation and durable scoped credential use; no Source capture, whole Preview, approval or apply'}, null, 2) + '\n');
  assert.equal(code, 0, `Native target observation failed: ${signal ?? code}`);
  assert.equal(writes, 0);
  assert.deepEqual(paths, [
    {method: 'GET', path: expected + '001000000000001'},
    {method: 'GET', path: expected + '001000000000001'},
    {method: 'GET', path: expected + '001000000000002'},
  ]);
  console.log(`Native Salesforce target observation receipt: ${join(root, 'physical-receipt.json')}`);
} finally {
  if (child !== undefined) {
    const closing = once(child, 'close');
    child.kill('SIGKILL');
    await closing;
  }
  server.closeAllConnections();
  await new Promise((resolve, reject) => server.close(error =>
    error ? reject(error) : resolve()));
}
