import assert from 'node:assert/strict';
import {execFileSync, spawn} from 'node:child_process';
import {createHash, generateKeyPairSync, X509Certificate} from 'node:crypto';
import {existsSync} from 'node:fs';
import {mkdir, mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {request as httpsRequest} from 'node:https';
import {isAbsolute, join} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {runtimeCore} from '../adapters/host-common/runtime-core.mjs';
import {signRemoteRuntimeBundle} from
  '../adapters/site-node/remote-bundle-signature.mjs';

const repositoryRoot = fileURLToPath(new URL('../', import.meta.url));
const scratchParent = process.env.ACTQL_TEST_SCRATCH_ROOT;
if (typeof scratchParent !== 'string' || scratchParent.length === 0) {
  throw new Error('ACTQL_TEST_SCRATCH_ROOT is required');
}
await mkdir(scratchParent, {recursive: true});
const root = await mkdtemp(join(scratchParent, 'native-remote-runtime-'));
const storeRoot = join(root, 'store');
const agentRoot = join(root, 'agent');
const standardRoot = join(root, 'standard');
const valuesRoot = join(root, 'values');
const valuesHttpsRoot = join(root, 'values-https');
await mkdir(storeRoot, {recursive: true});
await mkdir(agentRoot, {recursive: true});
await mkdir(standardRoot, {recursive: true});
await mkdir(valuesRoot, {recursive: true});
await mkdir(valuesHttpsRoot, {recursive: true});

const openssl = (...args) => execFileSync('openssl', args,
  {cwd: root, stdio: 'ignore'});

async function issueTestCertificates() {
  openssl('genrsa', '-out', 'ca.key', '2048');
  openssl('req', '-x509', '-new', '-key', 'ca.key', '-out',
    'ca.crt', '-subj', '/CN=ActQL Values Test CA', '-days', '1');
  await writeFile(join(root, 'server.ext'),
    'subjectAltName=DNS:localhost,IP:127.0.0.1\n' +
      'extendedKeyUsage=serverAuth\n');
  await writeFile(join(root, 'client.ext'),
    'extendedKeyUsage=clientAuth\n');
  for (const name of ['server', 'coordinator', 'other']) {
    openssl('genrsa', '-out', `${name}.key`, '2048');
    openssl('req', '-new', '-key', `${name}.key`, '-out',
      `${name}.csr`, '-subj', `/CN=${name}`);
    openssl('x509', '-req', '-in', `${name}.csr`, '-CA', 'ca.crt',
      '-CAkey', 'ca.key', '-CAcreateserial', '-out', `${name}.crt`,
      '-days', '1', '-extfile', name === 'server'
        ? 'server.ext' : 'client.ext');
  }
  const certificate = await readFile(join(root, 'coordinator.crt'));
  return {
    ca: await readFile(join(root, 'ca.crt')),
    cert: certificate,
    key: await readFile(join(root, 'coordinator.key')),
    otherCert: await readFile(join(root, 'other.crt')),
    otherKey: await readFile(join(root, 'other.key')),
    peer: new X509Certificate(certificate).fingerprint256,
  };
}

function sendValuesSiteRequest(tls, port, path, body, cid) {
  return new Promise((resolve, reject) => {
    const call = httpsRequest({
      hostname: 'localhost', port, path, method: 'POST',
      ca: tls.ca, cert: tls.cert, key: tls.key,
      headers: {
        'content-type': 'application/json',
        'content-length': Buffer.byteLength(body),
        'actql-dispatch-cid': cid,
      },
      signal: AbortSignal.timeout(10000),
    }, response => {
      let text = '';
      response.setEncoding('utf8');
      response.on('data', chunk => {
        text += chunk;
        if (text.length > 262144) call.destroy(
          new Error('Site response exceeded test bound'));
      });
      response.on('end', () => resolve({status: response.statusCode, body: text}));
      response.on('error', reject);
    });
    call.on('error', reject);
    call.end(body);
  });
}

async function testValuesHttps(tls, environment) {
  const child = spawn(moon, [
    'test', 'src/query_integration/client_source_free_root_wbtest.mbt',
    '--target', 'native',
  ], {cwd: repositoryRoot, env: environment, stdio: ['ignore', 'pipe', 'pipe']});
  let stdout = '';
  let stderr = '';
  child.stdout.setEncoding('utf8');
  child.stdout.on('data', chunk => { stdout += chunk; });
  child.stderr.setEncoding('utf8');
  child.stderr.on('data', chunk => { stderr += chunk; });
  const exited = new Promise((resolve, reject) => {
    child.on('error', reject);
    child.on('exit', (code, signal) => {
      if (code === 0) resolve();
      else reject(new Error(`native Values Site exited ${code ?? signal}: ${stdout}\n${stderr}`));
    });
  });
  void exited.catch(() => {});
  try {
    const readyPath = join(valuesHttpsRoot, 'https-ready');
    const deadline = Date.now() + 60000;
    while (!existsSync(readyPath)) {
      if (child.exitCode !== null || Date.now() >= deadline) {
        throw new Error('native Values Site did not become ready');
      }
      await new Promise(resolve => setTimeout(resolve, 25));
    }
    const [portText, cid, dispatch, query] =
      (await readFile(readyPath, 'utf8')).trimEnd().split('\n');
    if ([portText, cid, dispatch, query].some(value => !value)) {
      throw new Error('incomplete native Values Site route');
    }
    const port = Number(portText);
    if (!Number.isInteger(port) || port < 1 || port > 65535) {
      throw new Error('invalid native Values Site port');
    }
    const path = '/v1/sites/native-values-site/generations/1/dispatches';
    const externalDriver = process.env.ACTQL_TEST_NATIVE_VALUES_DRIVER;
    if (externalDriver !== undefined) {
      if (!isAbsolute(externalDriver)) {
        throw new Error('native Values driver path must be absolute');
      }
      execFileSync(process.execPath, ['--experimental-strip-types',
        externalDriver], {
        cwd: repositoryRoot,
        env: {
          ...process.env,
          ACTQL_TEST_NATIVE_VALUES_READY_PATH: readyPath,
          ACTQL_TEST_NATIVE_VALUES_TLS_CA: join(root, 'ca.crt'),
          ACTQL_TEST_NATIVE_VALUES_TLS_CERT: join(root, 'coordinator.crt'),
          ACTQL_TEST_NATIVE_VALUES_TLS_KEY: join(root, 'coordinator.key'),
          ACTQL_TEST_NATIVE_VALUES_TLS_OTHER_CERT: join(root, 'other.crt'),
          ACTQL_TEST_NATIVE_VALUES_TLS_OTHER_KEY: join(root, 'other.key'),
        },
        stdio: 'inherit',
      });
      await exited;
      process.stdout.write('Native Values external mTLS driver passed.\n');
      return;
    }
    const foreign = await sendValuesSiteRequest({
      ...tls, cert: tls.otherCert, key: tls.otherKey,
    }, port, path, dispatch, cid);
    assert.equal(foreign.status, 404);
    const missing = await sendValuesSiteRequest(tls, port,
      `${path}/query`, query, cid);
    if (missing.status !== 404) throw new Error('missing dispatch was not 404');
    const first = await sendValuesSiteRequest(tls, port,
      path, dispatch, cid);
    if (first.status !== 200) throw new Error(`dispatch failed: ${first.body}`);
    assert.equal(JSON.parse(first.body).dispatch_request_cid, cid);
    assert.equal(JSON.parse(first.body).version,
      'actql-remote-dispatch-response/0.1');
    const duplicate = await sendValuesSiteRequest(tls, port,
      path, dispatch, cid);
    if (duplicate.status !== 200 || duplicate.body !== first.body) {
      throw new Error('exact retransmission changed the Site reply');
    }
    const observed = await sendValuesSiteRequest(tls, port,
      `${path}/query`, query, cid);
    if (observed.status !== 200) throw new Error('Site evidence query failed');
    const status = JSON.parse(observed.body);
    assert.equal(status.dispatch_request_cid, cid);
    assert.equal(status.version, 'actql-remote-dispatch-status/0.1');
    assert.ok(status.evidence && status.subject && status.measurement);
    await exited;
    process.stdout.write('Native Values mTLS dispatch and query passed.\n');
  } catch (error) {
    throw new Error(`native Values HTTPS exchange failed: ${stdout}\n${stderr}`,
      {cause: error});
  } finally {
    if (child.exitCode === null) child.kill('SIGTERM');
  }
}

const moon = join(process.env.MOON_HOME ?? '', 'bin', 'moon');
const valuesHttpsOnly = process.argv.includes('--values-https-only');
const cryptoLibrary = process.env.ACTQL_TEST_NATIVE_CRYPTO_LIBRARY ??
  (process.platform === 'darwin'
    ? [
        '/opt/homebrew/opt/openssl@3/lib/libcrypto.3.dylib',
        '/usr/local/opt/openssl@3/lib/libcrypto.3.dylib',
      ].find(existsSync) ?? 'libcrypto.3.dylib'
    : 'libcrypto.so.3');
const sqliteLibrary = process.env.ACTQL_TEST_NATIVE_SQLITE_LIBRARY ??
  (process.platform === 'darwin'
    ? '/usr/lib/libsqlite3.dylib'
    : 'libsqlite3.so.0');
const duckdbLibraryName = process.platform === 'darwin'
  ? 'libduckdb.dylib'
  : 'libduckdb.so';
const duckdbLibrary = process.env.ACTQL_TEST_DUCKDB_LIBRARY ?? join(
  repositoryRoot,
  'adapters',
  'connectors',
  'duckdb',
  'node',
  'node_modules',
  '@duckdb',
  `node-bindings-${process.platform}-${process.arch}`,
  duckdbLibraryName,
);
if (!existsSync(duckdbLibrary)) {
  throw new Error(`native DuckDB library is required: ${duckdbLibrary}`);
}
const targetTriple = process.platform === 'darwin' && process.arch === 'arm64'
  ? 'aarch64-apple-darwin'
  : process.platform === 'linux' && process.arch === 'x64'
    ? 'x86_64-unknown-linux-gnu'
    : undefined;
if (targetTriple === undefined) {
  throw new Error(
    `unsupported native runtime test target ${process.platform}/${process.arch}`,
  );
}

try {
  execFileSync(moon, [
    'build', '--target', 'js', '--release', 'src/connectors_builtin_node',
  ], {cwd: repositoryRoot, stdio: 'inherit'});
  const moonModule = await import(pathToFileURL(join(
    repositoryRoot,
    '_build/js/release/build/connectors_builtin_node/' +
      'connectors_builtin_node.js',
  )).href);
  const control = runtimeCore(moonModule).remoteBundleControl;
  const keys = generateKeyPairSync('ed25519');
  const component = Buffer.from('native-runtime');
  const manifest = control.prepare({
    issuerAuthority: 'bundle-authority-a',
    bundleName: 'native-runtime',
    revision: 'native/1',
    targetTriple,
    componentCid: `sha256:${createHash('sha256')
      .update(component).digest('hex')}`,
    componentBytes: BigInt(component.byteLength),
    connectorRegistration: 'local',
    connectorRevision: 'local/1',
    strategyRevision: 'strategy/1',
  });
  const envelope = signRemoteRuntimeBundle(manifest, control, {
    keyId: 'key-a',
    privateKey: keys.privateKey,
  });
  if (!valuesHttpsOnly) execFileSync(moon, [
    'test', 'src/platform_native/remote_runtime/native_test',
    '--target', 'native',
  ], {
    cwd: repositoryRoot,
    env: {
      ...process.env,
      ACTQL_TEST_NATIVE_SQLITE_LIBRARY: sqliteLibrary,
      ACTQL_TEST_NATIVE_CRYPTO_LIBRARY: cryptoLibrary,
      ACTQL_TEST_NATIVE_REMOTE_RUNTIME_ROOT: storeRoot,
      ACTQL_TEST_NATIVE_REMOTE_RUNTIME_TARGET: targetTriple,
      ACTQL_TEST_NATIVE_REMOTE_RUNTIME_PUBLIC_KEY:
        keys.publicKey.export({type: 'spki', format: 'pem'}),
      ACTQL_TEST_NATIVE_REMOTE_RUNTIME_BUNDLE_BODY: envelope.body,
      ACTQL_TEST_NATIVE_REMOTE_RUNTIME_BUNDLE_CID: envelope.runtimeBundleCid,
      ACTQL_TEST_NATIVE_REMOTE_RUNTIME_SIGNATURE: envelope.signature,
    },
    stdio: 'inherit',
  });
  if (!valuesHttpsOnly) execFileSync(moon, [
    'test', 'src/query_integration', '--target', 'native',
  ], {
    cwd: repositoryRoot,
    env: {
      ...process.env,
      ACTQL_TEST_NATIVE_SQLITE_LIBRARY: sqliteLibrary,
      ACTQL_TEST_NATIVE_CRYPTO_LIBRARY: cryptoLibrary,
      ACTQL_TEST_DUCKDB_LIBRARY: duckdbLibrary,
      ACTQL_TEST_NATIVE_REMOTE_STANDARD_ROOT: standardRoot,
      ACTQL_TEST_NATIVE_REMOTE_VALUES_ROOT: valuesRoot,
      ACTQL_TEST_NATIVE_REMOTE_RUNTIME_TARGET: targetTriple,
      ACTQL_TEST_NATIVE_REMOTE_RUNTIME_PUBLIC_KEY:
        keys.publicKey.export({type: 'spki', format: 'pem'}),
      ACTQL_TEST_NATIVE_REMOTE_RUNTIME_BUNDLE_BODY: envelope.body,
      ACTQL_TEST_NATIVE_REMOTE_RUNTIME_BUNDLE_CID: envelope.runtimeBundleCid,
      ACTQL_TEST_NATIVE_REMOTE_RUNTIME_SIGNATURE: envelope.signature,
    },
    stdio: 'inherit',
  });
  const valuesTls = await issueTestCertificates();
  await testValuesHttps(valuesTls, {
    ...process.env,
    ACTQL_TEST_NATIVE_SQLITE_LIBRARY: sqliteLibrary,
    ACTQL_TEST_NATIVE_CRYPTO_LIBRARY: cryptoLibrary,
    ACTQL_TEST_DUCKDB_LIBRARY: duckdbLibrary,
    ACTQL_TEST_NATIVE_REMOTE_VALUES_ROOT: valuesHttpsRoot,
    ACTQL_TEST_NATIVE_REMOTE_RUNTIME_TARGET: targetTriple,
    ACTQL_TEST_NATIVE_REMOTE_RUNTIME_PUBLIC_KEY:
      keys.publicKey.export({type: 'spki', format: 'pem'}),
    ACTQL_TEST_NATIVE_REMOTE_RUNTIME_BUNDLE_BODY: envelope.body,
    ACTQL_TEST_NATIVE_REMOTE_RUNTIME_BUNDLE_CID: envelope.runtimeBundleCid,
    ACTQL_TEST_NATIVE_REMOTE_RUNTIME_SIGNATURE: envelope.signature,
    ACTQL_TEST_NATIVE_VALUES_HTTPS_CERT: join(root, 'server.crt'),
    ACTQL_TEST_NATIVE_VALUES_HTTPS_KEY: join(root, 'server.key'),
    ACTQL_TEST_NATIVE_VALUES_HTTPS_CA: join(root, 'ca.crt'),
    ACTQL_TEST_NATIVE_VALUES_HTTPS_PEER: valuesTls.peer,
  });
  if (!valuesHttpsOnly) execFileSync(moon, [
    'test', 'src/platform_native/remote_agent/native_test',
    '--target', 'native',
  ], {
    cwd: repositoryRoot,
    env: {
      ...process.env,
      ACTQL_TEST_NATIVE_SQLITE_LIBRARY: sqliteLibrary,
      ACTQL_TEST_NATIVE_CRYPTO_LIBRARY: cryptoLibrary,
      ACTQL_TEST_NATIVE_REMOTE_AGENT_ROOT: agentRoot,
      ACTQL_TEST_NATIVE_REMOTE_RUNTIME_TARGET: targetTriple,
      ACTQL_TEST_NATIVE_REMOTE_RUNTIME_PUBLIC_KEY:
        keys.publicKey.export({type: 'spki', format: 'pem'}),
      ACTQL_TEST_NATIVE_REMOTE_RUNTIME_BUNDLE_BODY: envelope.body,
      ACTQL_TEST_NATIVE_REMOTE_RUNTIME_BUNDLE_CID: envelope.runtimeBundleCid,
      ACTQL_TEST_NATIVE_REMOTE_RUNTIME_SIGNATURE: envelope.signature,
    },
    stdio: 'inherit',
  });
} finally {
  await rm(root, {recursive: true, force: true});
}
