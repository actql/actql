import assert from 'node:assert/strict';
import {execFileSync, spawn} from 'node:child_process';
import {
  createHash,
  generateKeyPairSync,
  X509Certificate,
} from 'node:crypto';
import {once} from 'node:events';
import {existsSync} from 'node:fs';
import {createServer} from 'node:https';
import {mkdtemp, mkdir, readFile, rm, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {runtimeCore} from '../adapters/host-common/runtime-core.mjs';
import {startHttpsOutboundSiteGateway} from
  '../adapters/host-node/outbound-site-gateway.mjs';
import {signRemoteRuntimeBundle} from
  '../adapters/site-node/remote-bundle-signature.mjs';

const scratchRoot = process.env.ACTQL_TEST_SCRATCH_ROOT;
if (typeof scratchRoot !== 'string' || scratchRoot.length === 0) {
  throw new Error('ACTQL_TEST_SCRATCH_ROOT is required');
}
await mkdir(scratchRoot, {recursive: true});
const root = await mkdtemp(join(scratchRoot, 'native-http-'));
const storeRoot = join(root, 'store');
const sqliteRoot = join(root, 'sqlite');
const standardRoot = join(root, 'standard');
const transferStandardRoot = join(root, 'transfer-standard');
await mkdir(storeRoot, {recursive: true});
await mkdir(sqliteRoot, {recursive: true});
await mkdir(standardRoot, {recursive: true});
await mkdir(transferStandardRoot, {recursive: true});

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
  input_binding_cid:
    'sha256:44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a',
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
const notSeenRequestBody = JSON.stringify({
  ...JSON.parse(remoteRequestBody),
  dispatch_id: 'dispatch-not-seen',
  input_binding_cid: `sha256:${'1'.repeat(64)}`,
  task_key: 'task-native-remote-dispatch-not-seen',
});
const notSeenRequestCid = `sha256:${createHash('sha256')
  .update(notSeenRequestBody).digest('hex')}`;
const staleRemoteRequestBody = JSON.stringify({
  ...JSON.parse(remoteRequestBody),
  dispatch_id: 'dispatch-stale-process',
  task_attempt: 2,
});
const staleRemoteRequestCid = `sha256:${createHash('sha256')
  .update(staleRemoteRequestBody).digest('hex')}`;
const remoteInputBindingBody = '{}';
const remoteInputBindingCid = `sha256:${createHash('sha256')
  .update(remoteInputBindingBody).digest('hex')}`;

let server;
let standardGateway;
let remoteSiteControl;
let outboundPolls = 0;
let nativeTransferCid;
let nativeTransferChunks = 0;
let nativeTransferManifest = [];
let nativeTransferCommitted = false;
let nativeTransferCommitReplyLost = false;
let nativeStoreTransferCid;
let nativeStoreTransferChunks = 0;
let nativeStoreTransferSealed = false;
let nativeStoreTransferManifest = [];
const nativeStoreTransferBodies = [];
const nativeStoreUses = new Map();
const nativeStandardTransferCompletions = [];
let observeStalePoll;
const stalePollObserved = new Promise(resolve => {
  observeStalePoll = resolve;
});
let releaseStalePoll;
const stalePollReleased = new Promise(resolve => {
  releaseStalePoll = resolve;
});
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
    const nativeTransferBase =
      '/v1/sites/native-destination/generations/3/transfers';
    const nativeTransferRequest = request.url === nativeTransferBase ||
      request.url?.startsWith(`${nativeTransferBase}/`);
    const nativeStoreTransferBase = '/v1/transfer-store/uploads';
    const nativeStoreTransferRequest =
      request.url?.startsWith('/v1/transfer-store/');
    if (request.url === '/disconnect') {
      request.socket.destroy();
      return;
    }
    if (request.url === '/generic-get') {
      if (request.method !== 'GET' ||
          request.headers.accept !== 'application/octet-stream') {
        response.writeHead(400).end();
        return;
      }
      response.writeHead(200, {'content-type': 'application/octet-stream'});
      response.end('chunk-b');
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
    const genericPut = request.method === 'PUT' &&
      request.url === '/generic-put';
    if (!nativeTransferRequest && !nativeStoreTransferRequest && !genericPut &&
        (request.method !== 'POST' ||
        ![
          '/probe',
          '/generic-post-empty',
          '/remote/dispatch',
          '/remote/query',
          '/remote/foreign',
          '/outbound/poll',
          '/outbound/stale-poll',
          '/outbound/observation',
          '/outbound/status-observation',
          '/outbound/stale-observation',
          '/standard-transfer/queue',
        ]
          .includes(request.url))) {
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
    const bodyBytes = Buffer.concat(chunks);
    const body = bodyBytes.toString('utf8');
    if (request.url === '/standard-transfer/queue') {
      if (standardGateway === undefined || remoteSiteControl === undefined) {
        response.writeHead(503).end();
        return;
      }
      let envelope;
      try { envelope = JSON.parse(body); }
      catch {
        response.writeHead(400).end();
        return;
      }
      try {
        let completion;
        if (envelope.version === 'actql-remote-poll-dispatch/0.2') {
          const operation = remoteSiteControl.admitPollDispatch(body);
          const dispatch = remoteSiteControl.pollDispatchRequest(operation);
          completion = standardGateway.dispatch({
            dispatch,
            inputBindingBody:
              remoteSiteControl.pollDispatchBindingBody(operation),
          });
        } else if (envelope.version === 'actql-remote-poll-release/0.1') {
          const dispatch = remoteSiteControl.admitJson(
            envelope.request_json,
            envelope.dispatch_request_cid,
          );
          completion = standardGateway.release({dispatch});
        } else {
          response.writeHead(400).end();
          return;
        }
        nativeStandardTransferCompletions.push(completion);
        void completion.catch(() => {});
        response.writeHead(201).end();
      } catch {
        response.writeHead(400).end();
      }
      return;
    }
    if (request.url === nativeStoreTransferBase && request.method === 'POST') {
      let envelope;
      try { envelope = JSON.parse(body); }
      catch {
        response.writeHead(400).end();
        return;
      }
      if (typeof envelope?.manifest !== 'string' ||
          typeof envelope?.request !== 'string' ||
          typeof request.headers['actql-transfer-cid'] !== 'string' ||
          typeof request.headers['actql-manifest-cid'] !== 'string') {
        response.writeHead(400).end();
        return;
      }
      let manifest;
      try { manifest = JSON.parse(envelope.manifest); }
      catch {
        response.writeHead(400).end();
        return;
      }
      if (!Array.isArray(manifest?.chunks) ||
          manifest.chunks.some(chunk =>
            typeof chunk?.cid !== 'string' ||
            !Number.isSafeInteger(chunk?.byte_length))) {
        response.writeHead(400).end();
        return;
      }
      const requestCid = request.headers['actql-transfer-cid'];
      if (nativeStoreTransferCid !== undefined &&
          nativeStoreTransferCid !== requestCid) {
        response.writeHead(409).end();
        return;
      }
      nativeStoreTransferCid = requestCid;
      nativeStoreTransferManifest = manifest.chunks;
      response.writeHead(nativeStoreTransferSealed ? 200 : 201, {
        'content-type': 'application/json',
      });
      response.end(nativeStoreTransferSealed
        ? JSON.stringify({requestCid, sealed: true})
        : JSON.stringify({
            requestCid,
            sealed: false,
            nextChunk: nativeStoreTransferChunks,
          }));
      return;
    }
    if (request.url?.startsWith(`${nativeStoreTransferBase}/`)) {
      const suffix = request.url.slice(nativeStoreTransferBase.length + 1);
      const parts = suffix.split('/');
      if (decodeURIComponent(parts[0] ?? '') !== nativeStoreTransferCid) {
        response.writeHead(404).end();
        return;
      }
      if (request.method === 'PUT' && parts[1] === 'chunks') {
        const index = Number(parts[2]);
        const expected = nativeStoreTransferManifest[index];
        const digest = `sha256:${createHash('sha256')
          .update(bodyBytes).digest('hex')}`;
        if (nativeStoreTransferSealed || expected === undefined ||
            index !== nativeStoreTransferChunks ||
            bodyBytes.byteLength !== expected.byte_length ||
            digest !== expected.cid ||
            request.headers['content-type'] !==
            'application/octet-stream') {
          response.writeHead(400).end();
          return;
        }
        nativeStoreTransferBodies[index] = bodyBytes;
        nativeStoreTransferChunks += 1;
        response.writeHead(200, {'content-type': 'application/json'});
        response.end(JSON.stringify({
          requestCid: nativeStoreTransferCid,
          nextChunk: nativeStoreTransferChunks,
        }));
        return;
      }
      if (request.method === 'POST' && parts[1] === 'commit' &&
          nativeStoreTransferChunks === nativeStoreTransferManifest.length &&
          body === '') {
        nativeStoreTransferSealed = true;
        response.writeHead(200, {'content-type': 'application/json'});
        response.end(JSON.stringify({
          requestCid: nativeStoreTransferCid,
          sealed: true,
        }));
        return;
      }
      response.writeHead(409).end();
      return;
    }
    if (request.url === '/v1/transfer-store/downloads' &&
        request.method === 'POST') {
      const useId = request.headers['actql-transfer-use-id'];
      if (!nativeStoreTransferSealed || typeof useId !== 'string' ||
          typeof request.headers['actql-transfer-cid'] !== 'string' ||
          request.headers['actql-transfer-cid'] !== nativeStoreTransferCid) {
        response.writeHead(404).end();
        return;
      }
      if (!nativeStoreUses.has(useId)) nativeStoreUses.set(useId, false);
      response.writeHead(200, {'content-type': 'application/json'});
      response.end(JSON.stringify({
        requestCid: nativeStoreTransferCid,
        useId,
        complete: nativeStoreUses.get(useId),
      }));
      return;
    }
    if (request.url?.startsWith('/v1/transfer-store/downloads/')) {
      const parts = request.url.split('/').filter(Boolean);
      const requestCid = decodeURIComponent(parts[3] ?? '');
      const useId = decodeURIComponent(parts[4] ?? '');
      if (requestCid !== nativeStoreTransferCid ||
          !nativeStoreUses.has(useId)) {
        response.writeHead(404).end();
        return;
      }
      if (request.method === 'GET' && parts[5] === 'chunks') {
        const chunk = nativeStoreTransferBodies[Number(parts[6])];
        if (!Buffer.isBuffer(chunk) || nativeStoreUses.get(useId)) {
          response.writeHead(409).end();
          return;
        }
        response.writeHead(200, {
          'content-type': 'application/octet-stream',
          'content-length': String(chunk.byteLength),
        });
        response.end(useId === 'native-store-cancel'
          ? Buffer.from(`altered-${Number(parts[6])}`)
          : chunk);
        return;
      }
      if (request.method === 'POST' && parts[5] === 'complete' &&
          typeof request.headers['actql-destination-receipt-cid'] ===
            'string') {
        let receipt;
        try { receipt = JSON.parse(body); }
        catch {
          response.writeHead(400).end();
          return;
        }
        if (receipt.request_cid !== nativeStoreTransferCid) {
          response.writeHead(400).end();
          return;
        }
        nativeStoreUses.set(useId, true);
        response.writeHead(200, {'content-type': 'application/json'});
        response.end(JSON.stringify({
          requestCid: nativeStoreTransferCid,
          useId,
          complete: true,
        }));
        return;
      }
      if (request.method === 'POST' && parts[5] === 'cancel' && body === '') {
        response.writeHead(200, {'content-type': 'application/json'});
        response.end(JSON.stringify({
          requestCid: nativeStoreTransferCid,
          useId,
          cancelled: true,
        }));
        return;
      }
      response.writeHead(409).end();
      return;
    }
    if (request.url === nativeTransferBase && request.method === 'POST') {
      let envelope;
      try { envelope = JSON.parse(body); }
      catch {
        response.writeHead(400).end();
        return;
      }
      if (typeof envelope?.manifest !== 'string' ||
          typeof envelope?.request !== 'string' ||
          typeof request.headers['actql-transfer-cid'] !== 'string' ||
          typeof request.headers['actql-manifest-cid'] !== 'string') {
        response.writeHead(400).end();
        return;
      }
      let manifest;
      try { manifest = JSON.parse(envelope.manifest); }
      catch {
        response.writeHead(400).end();
        return;
      }
      const claimedCid = request.headers['actql-transfer-cid'];
      if (nativeTransferCid !== claimedCid) {
        nativeTransferCid = claimedCid;
        nativeTransferChunks = 0;
        nativeTransferManifest = manifest.chunks ?? [];
        nativeTransferCommitted = false;
        nativeTransferCommitReplyLost = false;
      }
      response.writeHead(201, {'content-type': 'application/json'});
      response.end(JSON.stringify({
        requestCid: nativeTransferCid,
        state: nativeTransferCommitted
          ? [3, 2, 0, 1, 0, 1, 1, 1, 1]
          : [0, 0, 0, 0, 0, 0, 0, 1, 0],
      }));
      return;
    }
    if (nativeTransferRequest && request.url !== nativeTransferBase) {
      const suffix = request.url.slice(nativeTransferBase.length + 1);
      const parts = suffix.split('/');
      if (decodeURIComponent(parts[0] ?? '') !== nativeTransferCid) {
        response.writeHead(404).end();
        return;
      }
      if (request.method === 'PUT' && parts[1] === 'chunks') {
        const index = Number(parts[2]);
        const expected = nativeTransferManifest[index];
        const digest = `sha256:${createHash('sha256')
          .update(bodyBytes).digest('hex')}`;
        if (body === 'cancel-source' || expected === undefined ||
            index !== nativeTransferChunks ||
            BigInt(bodyBytes.byteLength) !== BigInt(expected.byte_length) ||
            digest !== expected.cid || request.headers['content-type'] !==
              'application/octet-stream') {
          response.writeHead(400).end();
          return;
        }
        nativeTransferChunks += 1;
        response.writeHead(200, {'content-type': 'application/json'});
        response.end(JSON.stringify({
          requestCid: nativeTransferCid,
          state: [0, 0, 0, 0, 0, 0, 0, 1, 0],
        }));
        return;
      }
      if (request.method === 'POST' && parts[1] === 'commit' &&
          nativeTransferChunks === nativeTransferManifest.length &&
          body === '') {
        nativeTransferCommitted = true;
        if (nativeTransferManifest.length === 1 &&
            nativeTransferChunks === 1 && !nativeTransferCommitReplyLost) {
          nativeTransferCommitReplyLost = true;
          request.socket.destroy();
          return;
        }
        response.writeHead(200, {'content-type': 'application/json'});
        response.end(JSON.stringify({
          requestCid: nativeTransferCid,
          state: [3, 2, 0, 1, 0, 1, 1, 1, 1],
        }));
        return;
      }
      if (request.method === 'POST' && parts[1] === 'cancel' && body === '') {
        response.writeHead(200, {'content-type': 'application/json'});
        response.end(JSON.stringify({
          requestCid: nativeTransferCid,
          state: [2, 4, 0, 0, 1, 1, 1, 1, 0],
        }));
        return;
      }
      response.writeHead(409).end();
      return;
    }
    if (request.url === '/generic-put') {
      if (request.method !== 'PUT' || body !== 'chunk-a' ||
          request.headers['content-type'] !== 'application/octet-stream' ||
          request.headers['x-actql-test'] !== 'bounded-chunk') {
        response.writeHead(400).end();
        return;
      }
      response.writeHead(200, {'content-type': 'application/json'});
      response.end('{"stored":7}');
      return;
    }
    if (request.url === '/generic-post-empty') {
      if (request.method !== 'POST' || body !== '' ||
          request.headers['content-type'] !== 'application/json') {
        response.writeHead(400).end();
        return;
      }
      response.writeHead(200, {'content-type': 'application/json'});
      response.end('{"empty":true}');
      return;
    }
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
      outboundPolls += 1;
      response.writeHead(200, {'content-type': 'application/json'});
      response.end(JSON.stringify(outboundPolls <= 2 ? {
        dispatch_request_cid: remoteRequestCid,
        input_binding_cid: remoteInputBindingCid,
        input_binding_json: remoteInputBindingBody,
        request_json: remoteRequestBody,
        version: 'actql-remote-poll-dispatch/0.2',
      } : {
        dispatch_request_cid: remoteRequestCid,
        request_json: remoteRequestBody,
        version: 'actql-remote-poll-query/0.1',
      }));
      return;
    }
    if (request.url === '/outbound/stale-poll') {
      if (body !== '{}') {
        response.writeHead(400).end();
        return;
      }
      observeStalePoll();
      await stalePollReleased;
      response.writeHead(200, {'content-type': 'application/json'});
      response.end(JSON.stringify({
        dispatch_request_cid: staleRemoteRequestCid,
        input_binding_cid: remoteInputBindingCid,
        input_binding_json: remoteInputBindingBody,
        request_json: staleRemoteRequestBody,
        version: 'actql-remote-poll-dispatch/0.2',
      }));
      return;
    }
    if (request.url === '/outbound/stale-observation') {
      let observation;
      try { observation = JSON.parse(body); }
      catch {
        response.writeHead(400).end();
        return;
      }
      if (observation.version !== 'actql-remote-dispatch-response/0.1' ||
          observation.dispatch_request_cid !== staleRemoteRequestCid ||
          observation.revision !== 0) {
        response.writeHead(400).end();
        return;
      }
      response.writeHead(200, {'content-type': 'application/json'});
      response.end('{"accepted":true}');
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
    if (request.url === '/outbound/status-observation') {
      let observation;
      try { observation = JSON.parse(body); }
      catch {
        response.writeHead(400).end();
        return;
      }
      const status = observation.version ===
        'actql-remote-dispatch-status/0.1' &&
        observation.dispatch_request_cid === remoteRequestCid &&
        observation.revision === 0 &&
        JSON.stringify(observation.state) === '[0,0,0,0,0]' &&
        observation.evidence === null &&
        observation.subject === null &&
        observation.measurement === null;
      const notSeen = observation.version ===
        'actql-remote-dispatch-not-seen/0.1' &&
        (observation.dispatch_request_cid === remoteRequestCid ||
          observation.dispatch_request_cid === notSeenRequestCid);
      if (!status && !notSeen) {
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
  const targetTriple = process.platform === 'darwin' && process.arch === 'arm64'
    ? 'aarch64-apple-darwin'
    : process.platform === 'linux' && process.arch === 'x64'
      ? 'x86_64-unknown-linux-gnu'
      : undefined;
  if (targetTriple === undefined) {
    throw new Error(
      `unsupported native HTTP test target ${process.platform}/${process.arch}`,
    );
  }
  execFileSync(moon, [
    'build', '--target', 'js', '--release', 'src/connectors_builtin_node',
  ], {cwd: new URL('../', import.meta.url), stdio: 'inherit'});
  const moonModule = await import(pathToFileURL(join(
    new URL('../', import.meta.url).pathname,
    '_build/js/release/build/connectors_builtin_node/' +
      'connectors_builtin_node.js',
  )).href);
  const portableRuntime = runtimeCore(moonModule);
  const runtimeControl = portableRuntime.remoteBundleControl;
  remoteSiteControl = portableRuntime.remoteSiteControl;
  const runtimeKeys = generateKeyPairSync('ed25519');
  const runtimeComponent = Buffer.from('native-runtime');
  const runtimeManifest = runtimeControl.prepare({
    issuerAuthority: 'bundle-authority-a',
    bundleName: 'native-runtime',
    revision: 'native/1',
    targetTriple,
    componentCid: `sha256:${createHash('sha256')
      .update(runtimeComponent).digest('hex')}`,
    componentBytes: BigInt(runtimeComponent.byteLength),
    connectorRegistration: 'local',
    connectorRevision: 'local/1',
    strategyRevision: 'strategy/1',
  });
  const runtimeEnvelope = signRemoteRuntimeBundle(
    runtimeManifest,
    runtimeControl,
    {keyId: 'key-a', privateKey: runtimeKeys.privateKey},
  );
  const siteCertificate = await readFile(join(root, 'client.crt'));
  standardGateway = await startHttpsOutboundSiteGateway({
    key: await readFile(join(root, 'server.key')),
    cert: await readFile(join(root, 'server.crt')),
    ca: await readFile(join(root, 'ca.crt')),
    siteAuthorities: new Map([[
      new X509Certificate(siteCertificate).fingerprint256,
      {siteKey: 'native-standard-transfer-site', siteGeneration: 1},
    ]]),
    control: remoteSiteControl,
  });
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
    ACTQL_TEST_NATIVE_REMOTE_STANDARD_ROOT: standardRoot,
    ACTQL_TEST_NATIVE_REMOTE_TRANSFER_STANDARD_ROOT: transferStandardRoot,
    ACTQL_TEST_NATIVE_REMOTE_GATEWAY_ORIGIN: standardGateway.origin,
    ACTQL_TEST_NATIVE_REMOTE_RUNTIME_TARGET: targetTriple,
    ACTQL_TEST_NATIVE_REMOTE_RUNTIME_PUBLIC_KEY:
      runtimeKeys.publicKey.export({type: 'spki', format: 'pem'}),
    ACTQL_TEST_NATIVE_REMOTE_RUNTIME_BUNDLE_BODY: runtimeEnvelope.body,
    ACTQL_TEST_NATIVE_REMOTE_RUNTIME_BUNDLE_CID:
      runtimeEnvelope.runtimeBundleCid,
    ACTQL_TEST_NATIVE_REMOTE_RUNTIME_SIGNATURE: runtimeEnvelope.signature,
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
    'src/platform_native/runtime_bundle',
    'src/platform_native/http_client',
    'src/platform_native/remote_journal',
    'src/platform_native/remote_transfer_journal',
    'src/platform_native/remote_transfer_client',
    'src/platform_native/remote_client',
    'src/platform_native/credential_resource',
    'src/query_integration',
  ]) {
    if (packagePath === 'src/query_integration') {
      nativeStoreTransferCid = undefined;
      nativeStoreTransferChunks = 0;
      nativeStoreTransferSealed = false;
      nativeStoreTransferManifest = [];
      nativeStoreTransferBodies.length = 0;
      nativeStoreUses.clear();
      nativeStandardTransferCompletions.length = 0;
    }
    const child = spawn(moon, ['test', packagePath, '--target', 'native'], {
      cwd: new URL('../', import.meta.url),
      env: testEnvironment,
      stdio: 'inherit',
    });
    const [code, signal] = await once(child, 'exit');
    if (code !== 0) {
      throw new Error(`native HTTP test failed: ${code ?? signal}`);
    }
    if (packagePath === 'src/query_integration') {
      await Promise.all(nativeStandardTransferCompletions);
      assert.equal(standardGateway.pending(), 0);
    }
  }
  execFileSync(moon, [
    'build', '--target', 'native', 'src/cmd/native_remote_site',
  ], {cwd: new URL('../', import.meta.url), stdio: 'inherit'});
  const executable = join(
    new URL('../', import.meta.url).pathname,
    '_build/native/debug/build/cmd/native_remote_site/' +
      'native_remote_site.exe',
  );
  const journalPath = join(root, 'native-site-agent.sqlite3');
  const revisionA = `sha256:${'a'.repeat(64)}`;
  const revisionB = `sha256:${'b'.repeat(64)}`;
  const common = [
    '--sqlite-library', testEnvironment.ACTQL_TEST_NATIVE_SQLITE_LIBRARY,
    '--journal-path', journalPath,
    '--site-key', 'native-site',
    '--site-generation', '1',
    '--runtime-revision', revisionA,
  ];
  const startAgent = arguments_ => {
    const child = spawn(executable, [...common, ...arguments_], {
      cwd: new URL('../', import.meta.url),
      env: {PATH: '/usr/bin:/bin', LANG: 'C'},
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    const stdout = [];
    const stderr = [];
    child.stdout.on('data', chunk => stdout.push(chunk));
    child.stderr.on('data', chunk => stderr.push(chunk));
    return (async () => {
      const [code, signal] = await once(child, 'exit');
      return Object.freeze({
        code,
        signal,
        stdout: Buffer.concat(stdout).toString('utf8'),
        stderr: Buffer.concat(stderr).toString('utf8'),
      });
    })();
  };
  const runAgent = arguments_ => startAgent(arguments_);
  const rejectedDispatch = await runAgent([
    '--http-library', library,
    '--ca', join(root, 'ca.crt'),
    '--cert', join(root, 'client.crt'),
    '--key', join(root, 'client.key'),
    '--poll-url', `https://127.0.0.1:${address.port}/outbound/poll`,
    '--observation-url',
    `https://127.0.0.1:${address.port}/outbound/observation`,
    'poll-once',
  ]);
  assert.notEqual(rejectedDispatch.code, 0);
  assert.equal(
    rejectedDispatch.stdout,
    'actql-native-remote-site: dispatch requires a runtime-linked ' +
      'Site component\n',
  );
  const queried = await runAgent([
    '--http-library', library,
    '--ca', join(root, 'ca.crt'),
    '--cert', join(root, 'client.crt'),
    '--key', join(root, 'client.key'),
    '--poll-url', `https://127.0.0.1:${address.port}/outbound/poll`,
    '--observation-url',
    `https://127.0.0.1:${address.port}/outbound/status-observation`,
    'poll-once',
  ]);
  assert.equal(queried.code, 0, queried.stderr);
  assert.deepEqual(JSON.parse(queried.stdout), {
    kind: 'not-seen',
    request_cid: remoteRequestCid,
    revision: 0,
  });
  const staleProcess = startAgent([
    '--http-library', library,
    '--ca', join(root, 'ca.crt'),
    '--cert', join(root, 'client.crt'),
    '--key', join(root, 'client.key'),
    '--poll-url', `https://127.0.0.1:${address.port}/outbound/stale-poll`,
    '--observation-url',
    `https://127.0.0.1:${address.port}/outbound/stale-observation`,
    'poll-once',
  ]);
  await stalePollObserved;
  const restarted = await runAgent([
    'restart',
    '--next-generation', '2',
    '--next-runtime-revision', revisionB,
  ]);
  assert.equal(restarted.code, 0, restarted.stderr);
  assert.deepEqual(JSON.parse(restarted.stdout), {reconciled_records: 0});
  releaseStalePoll();
  const fenced = await staleProcess;
  assert.notEqual(fenced.code, 0);
  const stale = await runAgent(['restart',
    '--next-generation', '2',
    '--next-runtime-revision', revisionB,
  ]);
  assert.notEqual(stale.code, 0);
} finally {
  releaseStalePoll?.();
  if (standardGateway !== undefined) {
    await standardGateway.close();
  }
  if (server !== undefined) {
    server.close();
    await once(server, 'close');
  }
  await rm(root, {recursive: true, force: true});
}
