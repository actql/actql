import {execFileSync, spawn} from 'node:child_process';
import {createHash} from 'node:crypto';
import {once} from 'node:events';
import {existsSync} from 'node:fs';
import {createServer} from 'node:https';
import {mkdtemp, mkdir, readFile, rm, writeFile} from 'node:fs/promises';
import {join} from 'node:path';

const scratchRoot = process.env.ACTQL_TEST_SCRATCH_ROOT;
if (typeof scratchRoot !== 'string' || scratchRoot.length === 0) {
  throw new Error('ACTQL_TEST_SCRATCH_ROOT is required');
}
await mkdir(scratchRoot, {recursive: true});
const root = await mkdtemp(join(scratchRoot, 'native-http-'));
const storeRoot = join(root, 'store');
const sqliteRoot = join(root, 'sqlite');
await mkdir(storeRoot, {recursive: true});
await mkdir(sqliteRoot, {recursive: true});

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
    '-days', '1', ...(extension === undefined ? [] : ['-extfile', extension]),
  );
};

const remoteRequestBody = JSON.stringify({
  budget_cid: `sha256:${'3'.repeat(64)}`,
  connector_registration: 'local',
  connector_revision: 'local/1',
  coordinator_authority: 'native-coordinator',
  dispatch_id: 'dispatch-native-remote',
  evidence_issuer_capability_cid: `sha256:${'b'.repeat(64)}`,
  grant_cid: `sha256:${'4'.repeat(64)}`,
  input_binding_cid: `sha256:${'1'.repeat(64)}`,
  obligations_cid: `sha256:${'2'.repeat(64)}`,
  run_definition_cid: `sha256:${'0'.repeat(64)}`,
  runtime_bundle_cid: `sha256:${'a'.repeat(64)}`,
  site_generation: 1,
  site_key: 'native-site',
  strategy_revision: 'strategy/1',
  task_attempt: 1,
  task_key: 'task-native-remote',
  version: 'actql-remote-dispatch-request/0.2',
});
const remoteRequestCid = `sha256:${createHash('sha256')
  .update(remoteRequestBody).digest('hex')}`;

let server;
try {
  openssl('genrsa', '-out', 'ca.key', '2048');
  openssl(
    'req', '-x509', '-new', '-key', 'ca.key', '-out', 'ca.crt',
    '-subj', '/CN=ActQL Native HTTP Test CA', '-days', '1',
  );
  openssl('genrsa', '-out', 'foreign-ca.key', '2048');
  openssl(
    'req', '-x509', '-new', '-key', 'foreign-ca.key',
    '-out', 'foreign-ca.crt', '-subj', '/CN=Foreign Test CA', '-days', '1',
  );
  await writeFile(
    join(root, 'server.ext'),
    'subjectAltName=DNS:localhost,IP:127.0.0.1\n' +
      'extendedKeyUsage=serverAuth\n',
  );
  await writeFile(
    join(root, 'client.ext'),
    'extendedKeyUsage=clientAuth\n',
  );
  issue('ca', 'server', 'server.ext');
  issue('ca', 'client', 'client.ext');
  issue('foreign-ca', 'foreign-client', 'client.ext');
  server = createServer({
    key: await readFile(join(root, 'server.key')),
    cert: await readFile(join(root, 'server.crt')),
    ca: await readFile(join(root, 'ca.crt')),
    requestCert: true,
    rejectUnauthorized: true,
  }, async (request, response) => {
    if (request.url === '/disconnect') {
      request.socket.destroy();
      return;
    }
    if (request.url === '/credential') {
      if (request.method !== 'GET' ||
          request.headers.authorization !== 'Bearer native-secret') {
        response.writeHead(403).end();
        return;
      }
      response.writeHead(200, {'content-type': 'application/json'});
      response.end('{"authorized":true}');
      return;
    }
    if (request.method !== 'POST' ||
        ![
          '/probe',
          '/remote/dispatch',
          '/remote/query',
          '/remote/foreign',
          '/outbound/poll',
          '/outbound/observation',
        ]
          .includes(request.url)) {
      response.writeHead(404).end();
      return;
    }
    const chunks = [];
    let length = 0;
    for await (const chunk of request) {
      length += chunk.length;
      if (length > 65_536) {
        request.destroy();
        return;
      }
      chunks.push(chunk);
    }
    const body = Buffer.concat(chunks).toString('utf8');
    if (request.url === '/probe' &&
        body !== '{"probe":true}' && body !== '{}') {
      response.writeHead(400).end();
      return;
    }
    if (request.url === '/probe') {
      response.writeHead(200, {'content-type': 'application/json'});
      response.end('{"accepted":true}');
      return;
    }
    if (request.url === '/outbound/poll') {
      if (body !== '{}') {
        response.writeHead(400).end();
        return;
      }
      response.writeHead(200, {'content-type': 'application/json'});
      response.end(JSON.stringify({
        dispatch_request_cid: remoteRequestCid,
        request_json: remoteRequestBody,
        version: 'actql-remote-poll-dispatch/0.1',
      }));
      return;
    }
    if (request.url === '/outbound/observation') {
      let observation;
      try { observation = JSON.parse(body); }
      catch {
        response.writeHead(400).end();
        return;
      }
      if (observation.version !== 'actql-remote-dispatch-response/0.1' ||
          observation.dispatch_request_cid !== remoteRequestCid ||
          observation.revision !== 0 ||
          JSON.stringify(observation.state) !== '[0,0,0,0,0]') {
        response.writeHead(400).end();
        return;
      }
      response.writeHead(200, {'content-type': 'application/json'});
      response.end('{"accepted":true}');
      return;
    }
    let dispatchCid;
    try {
      JSON.parse(body);
      dispatchCid = `sha256:${createHash('sha256').update(body).digest('hex')}`;
    } catch {
      response.writeHead(400).end();
      return;
    }
    if (request.url === '/remote/foreign') {
      dispatchCid = `sha256:${'f'.repeat(64)}`;
    }
    response.writeHead(200, {'content-type': 'application/json'});
    response.end(JSON.stringify({
      version: request.url === '/remote/query' ||
          request.url === '/remote/foreign'
        ? 'actql-remote-dispatch-status/0.1'
        : 'actql-remote-dispatch-response/0.1',
      dispatch_request_cid: dispatchCid,
      revision: 0,
      state: [0, 0, 0, 0, 0],
      ...(request.url === '/remote/query' ||
          request.url === '/remote/foreign'
        ? {evidence: null, subject: null, measurement: null}
        : {}),
    }));
  });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const address = server.address();
  if (address === null || typeof address === 'string') {
    throw new Error('native HTTP test listener has no TCP address');
  }
  const moon = join(
    process.env.MOON_HOME ?? '',
    'bin',
    'moon',
  );
  const library = process.env.ACTQL_TEST_NATIVE_HTTP_LIBRARY ??
    (process.platform === 'darwin'
      ? '/usr/lib/libcurl.4.dylib'
      : 'libcurl.so.4');
  const cryptoLibrary = process.env.ACTQL_TEST_NATIVE_CRYPTO_LIBRARY ??
    (process.platform === 'darwin'
      ? [
          '/opt/homebrew/opt/openssl@3/lib/libcrypto.3.dylib',
          '/usr/local/opt/openssl@3/lib/libcrypto.3.dylib',
        ].find(existsSync) ?? 'libcrypto.3.dylib'
      : 'libcrypto.so.3');
  const testEnvironment = {
    ...process.env,
    ACTQL_TEST_NATIVE_HTTP_LIBRARY: library,
    ACTQL_TEST_NATIVE_CRYPTO_LIBRARY: cryptoLibrary,
    ACTQL_TEST_NATIVE_HTTP_URL: `https://127.0.0.1:${address.port}`,
    ACTQL_TEST_NATIVE_HTTP_CA: join(root, 'ca.crt'),
    ACTQL_TEST_NATIVE_HTTP_CERT: join(root, 'client.crt'),
    ACTQL_TEST_NATIVE_HTTP_KEY: join(root, 'client.key'),
    ACTQL_TEST_NATIVE_HTTP_SECRET: join(root, 'credential.secret'),
    ACTQL_TEST_NATIVE_HTTP_BAD_CERT: join(root, 'foreign-client.crt'),
    ACTQL_TEST_NATIVE_HTTP_BAD_KEY: join(root, 'foreign-client.key'),
    ACTQL_TEST_NATIVE_SQLITE_LIBRARY:
      process.env.ACTQL_TEST_NATIVE_SQLITE_LIBRARY ??
      (process.platform === 'darwin'
        ? '/usr/lib/libsqlite3.dylib'
        : 'libsqlite3.so.0'),
    ACTQL_TEST_NATIVE_REMOTE_JOURNAL: join(root, 'coordinator.sqlite'),
    ACTQL_TEST_NATIVE_CREDENTIAL_JOURNAL: join(root, 'credential.sqlite'),
    ACTQL_TEST_NATIVE_SQLITE_ROOT: sqliteRoot,
    ACTQL_TEST_NATIVE_STORE_ROOT: storeRoot,
  };
  await writeFile(
    testEnvironment.ACTQL_TEST_NATIVE_HTTP_SECRET,
    'native-secret\n',
    {mode: 0o600},
  );
  for (const packagePath of [
    'src/platform_native/filesystem',
    'src/platform_native/sqlite',
    'src/platform_native/publication_store',
    'src/platform_native/run_publication',
    'src/platform_native/result_access',
    'src/platform_native/signature',
    'src/platform_native/http_client',
    'src/platform_native/remote_journal',
    'src/platform_native/remote_client',
    'src/platform_native/credential_resource',
  ]) {
    const child = spawn(moon, ['test', packagePath, '--target', 'native'], {
      cwd: new URL('../', import.meta.url),
      env: testEnvironment,
      stdio: 'inherit',
    });
    const [code, signal] = await once(child, 'exit');
    if (code !== 0) {
      throw new Error(`native HTTP test failed: ${code ?? signal}`);
    }
  }
} finally {
  if (server !== undefined) {
    server.close();
    await once(server, 'close');
  }
  await rm(root, {recursive: true, force: true});
}
