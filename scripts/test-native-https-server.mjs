import assert from 'node:assert/strict';
import {execFileSync, spawn} from 'node:child_process';
import {X509Certificate} from 'node:crypto';
import {once} from 'node:events';
import {request} from 'node:https';
import {createServer} from 'node:net';
import {mkdir, mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {join} from 'node:path';

const scratchRoot = process.env.ACTQL_TEST_SCRATCH_ROOT;
if (typeof scratchRoot !== 'string' || scratchRoot.length === 0) {
  throw new Error('ACTQL_TEST_SCRATCH_ROOT is required');
}
await mkdir(scratchRoot, {recursive: true});
const root = await mkdtemp(join(scratchRoot, 'native-https-server-'));
const executable = process.env.ACTQL_NATIVE_HTTPS_SERVER_EXECUTABLE ??
  join(
    process.cwd(),
    '_build/native/release/build/cmd/native_https_echo/' +
      'native_https_echo.exe',
  );

const openssl = (...arguments_) => execFileSync(
  'openssl',
  arguments_,
  {cwd: root, stdio: 'ignore'},
);
const issue = (authority, name, extension) => {
  openssl('genrsa', '-out', `${name}.key`, '2048');
  openssl(
    'req', '-new', '-key', `${name}.key`, '-out', `${name}.csr`,
    '-subj', `/CN=${name}`,
  );
  openssl(
    'x509', '-req', '-in', `${name}.csr`, '-CA', `${authority}.crt`,
    '-CAkey', `${authority}.key`, '-CAcreateserial', '-out', `${name}.crt`,
    '-days', '1', '-extfile', extension,
  );
};

const unusedPort = async () => {
  const listener = createServer();
  listener.listen(0, '127.0.0.1');
  await once(listener, 'listening');
  const address = listener.address();
  assert.notEqual(address, null);
  assert.equal(typeof address, 'object');
  const port = address.port;
  listener.close();
  await once(listener, 'close');
  return port;
};

const call = async ({port, certificate, key, path, body}) => {
  const [ca, cert, privateKey] = await Promise.all([
    readFile(join(root, 'ca.crt')),
    readFile(join(root, certificate)),
    readFile(join(root, key)),
  ]);
  return new Promise((resolve, reject) => {
    const operation = request({
      hostname: 'localhost',
      port,
      path,
      method: 'POST',
      ca,
      cert,
      key: privateKey,
      headers: {'content-length': Buffer.byteLength(body)},
    }, response => {
      const chunks = [];
      response.on('data', chunk => chunks.push(chunk));
      response.once('end', () => resolve({
        status: response.statusCode,
        body: Buffer.concat(chunks).toString('utf8'),
      }));
    });
    operation.once('error', reject);
    operation.setTimeout(3_000, () => {
      operation.destroy(new Error('native HTTPS request timed out'));
    });
    operation.end(body);
  });
};

let child;
try {
  openssl('genrsa', '-out', 'ca.key', '2048');
  openssl(
    'req', '-x509', '-new', '-key', 'ca.key', '-out', 'ca.crt',
    '-subj', '/CN=ActQL Native HTTPS Test CA', '-days', '1',
  );
  openssl('genrsa', '-out', 'foreign-ca.key', '2048');
  openssl(
    'req', '-x509', '-new', '-key', 'foreign-ca.key',
    '-out', 'foreign-ca.crt', '-subj', '/CN=Foreign Test CA',
    '-days', '1',
  );
  await writeFile(
    join(root, 'server.ext'),
    'subjectAltName=DNS:localhost,IP:127.0.0.1\n' +
      'extendedKeyUsage=serverAuth\n',
  );
  await writeFile(join(root, 'client.ext'), 'extendedKeyUsage=clientAuth\n');
  issue('ca', 'server', 'server.ext');
  issue('ca', 'client', 'client.ext');
  issue('foreign-ca', 'foreign-client', 'client.ext');
  const port = await unusedPort();
  child = spawn(executable, [
    '--port', String(port),
    '--cert', join(root, 'server.crt'),
    '--key', join(root, 'server.key'),
    '--ca', join(root, 'ca.crt'),
    '--max-request-bytes', '64',
  ], {stdio: ['ignore', 'pipe', 'pipe']});
  const errorChunks = [];
  child.stderr.on('data', chunk => errorChunks.push(chunk));
  assert.ok(Number.isInteger(port) && port > 0);
  const expectedFingerprint = new X509Certificate(
    await readFile(join(root, 'client.crt')),
  ).fingerprint256;
  let success;
  for (let attempt = 0; attempt < 30; attempt += 1) {
    try {
      success = await call({
        port,
        certificate: 'client.crt',
        key: 'client.key',
        path: '/echo',
        body: 'native-body',
      });
      break;
    } catch (error) {
      if (child.exitCode !== null || attempt === 29) {
        throw new Error(
          `${error.message}: ` + Buffer.concat(errorChunks).toString('utf8'),
        );
      }
      await new Promise(resolve => setTimeout(resolve, 50));
    }
  }
  assert.equal(success.status, 200);
  assert.deepEqual(JSON.parse(success.body), {
    method: 'POST',
    path: '/echo',
    body_bytes: 11,
    peer: expectedFingerprint,
  });
  await assert.rejects(call({
    port,
    certificate: 'foreign-client.crt',
    key: 'foreign-client.key',
    path: '/echo',
    body: 'untrusted',
  }));
  const tooLarge = await call({
    port,
    certificate: 'client.crt',
    key: 'client.key',
    path: '/echo',
    body: 'x'.repeat(65),
  });
  assert.equal(tooLarge.status, 413);
  const shutdown = await call({
    port,
    certificate: 'client.crt',
    key: 'client.key',
    path: '/shutdown',
    body: '',
  });
  assert.equal(shutdown.status, 200);
  const [exitCode] = await once(child, 'exit');
  assert.equal(exitCode, 0);
  child = undefined;
  console.log('native HTTPS server tests passed');
} finally {
  if (child !== undefined) child.kill('SIGKILL');
  await rm(root, {recursive: true, force: true});
}
