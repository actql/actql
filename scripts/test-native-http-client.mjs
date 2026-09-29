import assert from 'node:assert/strict';
import {execFileSync, spawn} from 'node:child_process';
import {
  createHash,
  generateKeyPairSync,
  X509Certificate,
} from 'node:crypto';
import {once} from 'node:events';
import {existsSync} from 'node:fs';
import {createServer, request as httpsRequest} from 'node:https';
import {createServer as createNetServer, isIP} from 'node:net';
import {
  mkdtemp,
  mkdir,
  readFile,
  readdir,
  rename,
  rm,
  writeFile,
} from 'node:fs/promises';
import {join} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {runtimeCore} from '../adapters/host-common/runtime-core.mjs';
import {startNativeBearerServers} from './fixtures/native-bearer-servers.mjs';
import {startHttpsOutboundSiteGateway} from
  '../adapters/host-node/outbound-site-gateway.mjs';
import {signRemoteRuntimeBundle} from
  '../adapters/site-node/remote-bundle-signature.mjs';
import {signRemoteCredentialGrant} from
  '../adapters/site-node/remote-credential-signature.mjs';
import {uploadHttpsTransferObject} from
  '../adapters/site-node/https-transfer-store.mjs';
import {canonical, hash as canonicalHash} from
  '../adapters/connectors/duckdb/node/test/typed-catalog.mjs';
import {pinnedEngineContracts} from
  '../adapters/connectors/duckdb/node/test/pinned-engine-contracts.mjs';

const scratchRoot = process.env.ACTQL_TEST_SCRATCH_ROOT;
if (typeof scratchRoot !== 'string' || scratchRoot.length === 0) {
  throw new Error('ACTQL_TEST_SCRATCH_ROOT is required');
}
const nativeHttpHost = process.env.ACTQL_TEST_NATIVE_HTTP_HOST ?? '127.0.0.1';
if (isIP(nativeHttpHost) === 0) {
  throw new Error('ACTQL_TEST_NATIVE_HTTP_HOST must be an IP address');
}
const nativeSiteNamespace = process.env.ACTQL_TEST_NATIVE_SITE_NETNS;
const nativeSiteUser = process.env.ACTQL_TEST_NATIVE_SITE_USER;
if ((nativeSiteNamespace === undefined) !== (nativeSiteUser === undefined) ||
    nativeSiteNamespace === '' || nativeSiteUser === '') {
  throw new Error('native Site namespace and user must be configured together');
}
const nativeDestinationNamespace =
  process.env.ACTQL_TEST_NATIVE_DESTINATION_NETNS;
const nativeDestinationUser =
  process.env.ACTQL_TEST_NATIVE_DESTINATION_USER;
const nativeDestinationHost =
  process.env.ACTQL_TEST_NATIVE_DESTINATION_HOST ?? '127.0.0.1';
const configuredNativeTransferPort = Number.parseInt(
  process.env.ACTQL_TEST_NATIVE_TRANSFER_PORT ?? '0',
  10,
);
if ((nativeDestinationNamespace === undefined) !==
      (nativeDestinationUser === undefined) ||
    nativeDestinationNamespace === '' || nativeDestinationUser === '') {
  throw new Error(
    'native destination namespace and user must be configured together',
  );
}
if (nativeDestinationNamespace !== undefined &&
    nativeSiteNamespace === undefined) {
  throw new Error('destination namespace requires a source Site namespace');
}
if (isIP(nativeDestinationHost) === 0 ||
    !Number.isInteger(configuredNativeTransferPort) ||
    configuredNativeTransferPort < 0 || configuredNativeTransferPort > 65_535) {
  throw new Error('invalid native destination Transfer endpoint');
}
const allocatePort = async host => {
  const probe = createNetServer();
  probe.listen(0, host);
  await once(probe, 'listening');
  const address = probe.address();
  if (address === null || typeof address === 'string') {
    probe.close();
    throw new Error('native Transfer port probe has no TCP address');
  }
  const port = address.port;
  probe.close();
  await once(probe, 'close');
  return port;
};
const allocateNativeTransferPort = () => allocatePort(nativeDestinationHost);
const nativeTransferPort = configuredNativeTransferPort === 0
  ? await allocateNativeTransferPort()
  : configuredNativeTransferPort;
const applicationOutputRoute =
  process.env.ACTQL_TEST_NATIVE_APPLICATION_OUTPUT_ROUTE ?? 'direct';
if (!['direct', 'store'].includes(applicationOutputRoute)) {
  throw new Error('invalid native application output route');
}
await mkdir(scratchRoot, {recursive: true});
const root = await mkdtemp(join(scratchRoot, 'native-http-'));
const storeRoot = join(root, 'store');
const filesystemTestRoot = join(root, 'filesystem-test');
const retainedTaskRoot = join(root, 'retained-task');
const nativeTestDuckDBLibrary = process.env.ACTQL_TEST_DUCKDB_LIBRARY ?? join(
  fileURLToPath(new URL('../', import.meta.url)),
  'adapters',
  'connectors',
  'duckdb',
  'node',
  'node_modules',
  '@duckdb',
  `node-bindings-${process.platform}-${process.arch}`,
  process.platform === 'darwin' ? 'libduckdb.dylib' : 'libduckdb.so',
);
// This dedicated runner owns the native DuckDB prerequisites: a missing
// library is a failure here, not a silently skipped native test.
assert(existsSync(nativeTestDuckDBLibrary),
  `native DuckDB test library unavailable: ${nativeTestDuckDBLibrary}`);
const multiBundleStoreRoot = join(root, 'multi-bundle-store');
const sqliteRoot = join(root, 'sqlite');
const standardRoot = join(root, 'standard');
const transferStandardRoot = join(root, 'transfer-standard');
const remotePublicationRoot = join(root, 'remote-publication');
await mkdir(storeRoot, {recursive: true});
await mkdir(filesystemTestRoot, {recursive: true});
await mkdir(retainedTaskRoot, {recursive: true});
await mkdir(multiBundleStoreRoot, {recursive: true});
await mkdir(sqliteRoot, {recursive: true});
await mkdir(standardRoot, {recursive: true});
await mkdir(transferStandardRoot, {recursive: true});
await mkdir(remotePublicationRoot, {recursive: true});

const physicalCid = value => `sha256:${createHash('sha256')
  .update(value).digest('hex')}`;

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
  version: 'actql-remote-dispatch-request/0.1',
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
let bearerServers;
let applicationControlProxy;
let standardGateway;
let remoteSiteControl;
let outboundPolls = 0;
let placementPolicyAttempts = 0;
// Push dispatches this server received, as observed by the server (read by
// the native run-owner authorization test through /remote/received).
let remoteDispatchesReceived = 0;
let nativeTransferCid;
let nativeTransferChunks = 0;
let nativeTransferManifest = [];
let nativeTransferCommitted = false;
let nativeTransferCommitReplyLost = false;
let nativeTransferInjectLostReply = true;
let nativeStoreTransferCid;
let nativeStoreTransferChunks = 0;
let nativeStoreTransferSealed = false;
let nativeStoreTransferManifest = [];
let nativeStoreTransferRequest;
let nativeStoreCommittedRecord;
let nativeStoreAutoCommit = true;
const nativeStoreTransferBodies = [];
const nativeStoreUses = new Map();
const nativeStoreSealedWaiters = new Set();
const nativeStoreCommitWaiters = new Set();
const commitNativeStoreDestination = control => {
  let committed = control.open(nativeStoreTransferRequest);
  committed = control.commitTransition(
    control.prepareStart(committed),
    true,
  );
  committed = control.commitTransition(
    control.prepareSourceSettled(committed, true, true),
    true,
  );
  nativeStoreCommittedRecord = control.commitTransition(
    control.prepareDestinationCommit(committed),
    true,
  );
  for (const waiter of nativeStoreCommitWaiters) waiter();
  nativeStoreCommitWaiters.clear();
};
const nativeStandardTransferCompletions = [];
const resetNativeStoreTransfer = () => {
  nativeStoreTransferCid = undefined;
  nativeStoreTransferChunks = 0;
  nativeStoreTransferSealed = false;
  nativeStoreTransferManifest = [];
  nativeStoreTransferRequest = undefined;
  nativeStoreCommittedRecord = undefined;
  nativeStoreTransferBodies.length = 0;
  nativeStoreUses.clear();
  nativeStoreSealedWaiters.clear();
  nativeStoreCommitWaiters.clear();
};
let nativeApplicationInputRequestBody;
let nativeApplicationInputManifestBody;
let nativeApplicationOutputRequestBody;
let nativeApplicationOutputManifestBody;
let productTransferService;
let stopProductTransferService;
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
    `subjectAltName=DNS:localhost,IP:127.0.0.1,IP:${nativeHttpHost}\n` +
      'extendedKeyUsage=serverAuth\n',
  );
  await writeFile(
    join(root, 'client.ext'),
    'extendedKeyUsage=clientAuth\n',
  );
  await writeFile(
    join(root, 'destination-server.ext'),
    `subjectAltName=DNS:localhost,IP:127.0.0.1,` +
      `IP:${nativeDestinationHost}\n` +
      'extendedKeyUsage=serverAuth\n',
  );
  issue('ca', 'server', 'server.ext');
  issue('ca', 'client', 'client.ext');
  issue('ca', 'destination-client', 'client.ext');
  issue('ca', 'destination-server', 'destination-server.ext');
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
    const isNativeStoreTransferRequest =
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
    if (request.url === '/both') {
      // Mutual TLS was already required by this server; the bearer
      // credential is checked in addition.
      request.resume();
      const authorized = request.method === 'POST' &&
        request.headers.authorization === bearerServers?.controlAuthorization;
      response.writeHead(authorized ? 200 : 401,
        {'content-type': 'application/json'});
      response.end(JSON.stringify({both: authorized}));
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
    const applicationInputContract = new Map([
      [
        '/v1/native-application/input/request',
        nativeApplicationInputRequestBody,
      ],
      [
        '/v1/native-application/input/manifest',
        nativeApplicationInputManifestBody,
      ],
      [
        '/v1/native-application/output/request',
        nativeApplicationOutputRequestBody,
      ],
      [
        '/v1/native-application/output/manifest',
        nativeApplicationOutputManifestBody,
      ],
    ]).get(request.url);
    if (applicationInputContract !== undefined) {
      if (request.method !== 'GET') {
        response.writeHead(405).end();
        return;
      }
      response.writeHead(200, {
        'content-length': Buffer.byteLength(applicationInputContract),
        'content-type': 'application/json',
      });
      response.end(applicationInputContract);
      return;
    }
    const genericPut = request.method === 'PUT' &&
      request.url === '/generic-put';
    if (!nativeTransferRequest && !isNativeStoreTransferRequest &&
        !genericPut &&
        (request.method !== 'POST' ||
        ![
          '/probe',
          '/generic-post-empty',
          '/remote/dispatch',
          '/remote/received',
          '/remote/query',
          '/remote/foreign',
          '/outbound/poll',
          '/outbound/stale-poll',
          '/outbound/observation',
          '/outbound/status-observation',
          '/outbound/stale-observation',
          '/standard-transfer/queue',
          '/placement-policy/choose',
          '/placement-policy/foreign',
          '/placement-policy/late',
          '/placement-policy/flaky',
        ]
          .includes(request.url))) {
      response.writeHead(404).end();
      return;
    }
    if (request.url === '/remote/dispatch') remoteDispatchesReceived++;
    if (request.url === '/remote/received') {
      request.resume();
      response.writeHead(200, {'content-type': 'application/json'});
      response.end(JSON.stringify({dispatch: remoteDispatchesReceived}));
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
    if (request.url?.startsWith('/placement-policy/')) {
      let envelope;
      try { envelope = JSON.parse(body); }
      catch {
        response.writeHead(400).end();
        return;
      }
      if (request.headers['content-type'] !== 'application/json' ||
          envelope?.request?.version !== 'actql-placement-policy/0.1' ||
          typeof envelope?.candidates !== 'object' ||
          envelope.request.candidate_set_cid === undefined) {
        response.writeHead(400).end();
        return;
      }
      if (request.url === '/placement-policy/flaky' &&
          ++placementPolicyAttempts === 1) {
        request.socket.destroy();
        return;
      }
      if (request.url === '/placement-policy/late') {
        await new Promise(resolve => setTimeout(resolve, 2250));
      }
      response.writeHead(200, {'content-type': 'application/json'});
      response.end(JSON.stringify({
        ...envelope.request,
        explanation: 'mTLS policy fixture',
        policy_id: request.url === '/placement-policy/foreign'
          ? 'foreign-policy' : 'configured-policy',
        policy_revision: 'fixture-1',
        position: 0,
      }));
      return;
    }
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
        if (envelope.version === 'actql-remote-poll-dispatch/0.1') {
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
      let admittedRequest;
      try {
        admittedRequest = transferControl.admitAdmissionEnvelopeJson(
          body,
          requestCid,
          request.headers['actql-manifest-cid'],
          {
            maxChunks: 8,
            maxManifestBytes: 4096,
            maxReferencedBytes: 1048576n,
          },
        );
      } catch {
        response.writeHead(400).end();
        return;
      }
      if (nativeStoreTransferCid !== undefined &&
          nativeStoreTransferCid !== requestCid) {
        response.writeHead(409).end();
        return;
      }
      nativeStoreTransferCid = requestCid;
      nativeStoreTransferRequest = admittedRequest;
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
      if (request.method === 'POST' && parts[1] === 'completion') {
        try {
          transferControl.admitAdmissionEnvelopeJson(
            body,
            request.headers['actql-transfer-cid'],
            request.headers['actql-manifest-cid'],
            {
              maxChunks: 8,
              maxManifestBytes: 4096,
              maxReferencedBytes: 1048576n,
            },
          );
        } catch {
          response.writeHead(400).end();
          return;
        }
        if (nativeStoreCommittedRecord === undefined) {
          await new Promise((resolve, reject) => {
            const completed = () => {
              request.off('aborted', aborted);
              resolve();
            };
            const aborted = () => {
              nativeStoreCommitWaiters.delete(completed);
              reject(new Error('Store completion request aborted'));
            };
            nativeStoreCommitWaiters.add(completed);
            request.once('aborted', aborted);
          });
        }
        response.writeHead(200, {'content-type': 'application/json'});
        response.end(transferControl.replyJson(nativeStoreCommittedRecord));
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
        for (const waiter of nativeStoreSealedWaiters) waiter();
        nativeStoreSealedWaiters.clear();
        if (nativeStoreAutoCommit) {
          commitNativeStoreDestination(transferControl);
        }
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
      if (typeof useId !== 'string' ||
          typeof request.headers['actql-transfer-cid'] !== 'string' ||
          request.headers['actql-transfer-cid'] !== nativeStoreTransferCid) {
        response.writeHead(404).end();
        return;
      }
      if (!nativeStoreTransferSealed) {
        await new Promise((resolve, reject) => {
          const sealed = () => {
            request.off('aborted', aborted);
            resolve();
          };
          const aborted = () => {
            nativeStoreSealedWaiters.delete(sealed);
            reject(new Error('Store use request aborted'));
          };
          nativeStoreSealedWaiters.add(sealed);
          request.once('aborted', aborted);
        });
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
        commitNativeStoreDestination(transferControl);
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
        if (nativeTransferInjectLostReply &&
            nativeTransferManifest.length === 1 &&
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
        version: 'actql-remote-poll-dispatch/0.1',
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
        version: 'actql-remote-poll-dispatch/0.1',
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
  server.listen(0, nativeHttpHost);
  await once(server, 'listening');
  const address = server.address();
  if (address === null || typeof address === 'string') {
    throw new Error('native HTTP test listener has no TCP address');
  }
  const nativeHttpOrigin = `https://${nativeHttpHost}:${address.port}`;
  bearerServers = await startNativeBearerServers({
    host: nativeHttpHost,
    key: await readFile(join(root, 'server.key')),
    cert: await readFile(join(root, 'server.crt')),
    root,
  });
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
  const credentialControl = portableRuntime.remoteCredentialControl;
  remoteSiteControl = portableRuntime.remoteSiteControl;
  const transferControl = portableRuntime.remoteTransferControl;
  const runtimeKeys = generateKeyPairSync('ed25519');
  const credentialKeys = generateKeyPairSync('ed25519');
  const credentialGrant = credentialControl.prepare({
    issuerAuthority: 'credential-authority-a',
    principal: 'principal-a',
    namespaceId: 'namespace-a',
    environment: 'test',
    siteKey: 'site-a',
    siteGeneration: 2,
    runtimeBundleCid: `sha256:${'a'.repeat(64)}`,
    connectorRegistration: 'http-source',
    connectorRevision: 'http-source/1',
    resourceOrigin: nativeHttpOrigin,
    operation: 'records:read',
    runInvocationCid: `sha256:${'b'.repeat(64)}`,
    taskAttempt: 3,
    dispatchRequestCid: `sha256:${'c'.repeat(64)}`,
    expiresUnixMilliseconds: 2000000000000n,
    maxUses: 1,
  });
  const credentialEnvelope = signRemoteCredentialGrant(
    credentialGrant,
    credentialControl,
    {keyId: 'credential-key-a', privateKey: credentialKeys.privateKey},
  );
  const credentialPublicKey = credentialKeys.publicKey.export({
    type: 'spki',
    format: 'pem',
  });
  const productCredentialGrant = credentialControl.prepare({
    issuerAuthority: 'credential-authority-a',
    principal: 'principal-a',
    namespaceId: 'namespace-a',
    environment: 'test',
    siteKey: 'site-a',
    siteGeneration: 2,
    runtimeBundleCid: `sha256:${'a'.repeat(64)}`,
    connectorRegistration: 'http-source',
    connectorRevision: 'http-source/1',
    resourceOrigin: nativeHttpOrigin,
    operation: 'records:read',
    runInvocationCid: `sha256:${'b'.repeat(64)}`,
    taskAttempt: 3,
    dispatchRequestCid: `sha256:${'c'.repeat(64)}`,
    expiresUnixMilliseconds: 2000000000000n,
    maxUses: 2,
  });
  const productCredentialEnvelope = signRemoteCredentialGrant(
    productCredentialGrant,
    credentialControl,
    {keyId: 'credential-key-a', privateKey: credentialKeys.privateKey},
  );
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
    host: nativeHttpHost,
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
    ACTQL_TEST_NATIVE_HTTP_URL: nativeHttpOrigin,
    ACTQL_TEST_NATIVE_HTTP_CA: join(root, 'ca.crt'),
    ACTQL_TEST_NATIVE_HTTP_CERT: join(root, 'client.crt'),
    ACTQL_TEST_NATIVE_HTTP_KEY: join(root, 'client.key'),
    ACTQL_TEST_NATIVE_POLICY_CLOCK: join(root, 'placement-policy-clock.sqlite'),
    ACTQL_TEST_NATIVE_HTTP_SECRET: join(root, 'credential.secret'),
    ACTQL_TEST_NATIVE_HTTP_BEARER_URL: bearerServers.origin,
    ACTQL_TEST_NATIVE_HTTP_BEARER_FOREIGN_URL: bearerServers.foreignOrigin,
    ACTQL_TEST_NATIVE_HTTP_BEARER_ROOT: bearerServers.directory,
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
    ACTQL_TEST_NATIVE_RETAINED_TASK_ROOT: retainedTaskRoot,
    ACTQL_TEST_DUCKDB_LIBRARY: nativeTestDuckDBLibrary,
    // Native DuckDB tests fail instead of skipping when a variable is missing.
    ACTQL_REQUIRE_NATIVE_DUCKDB_TESTS: '1',
    ACTQL_TEST_NATIVE_MULTI_STORE_ROOT: multiBundleStoreRoot,
    ACTQL_TEST_NATIVE_REMOTE_STANDARD_ROOT: standardRoot,
    ACTQL_TEST_NATIVE_REMOTE_TRANSFER_STANDARD_ROOT: transferStandardRoot,
    ACTQL_TEST_NATIVE_REMOTE_PUBLICATION_ROOT: remotePublicationRoot,
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
  await writeFile(
    join(root, 'credential-grant.json'),
    productCredentialEnvelope.body,
  );
  await writeFile(
    join(root, 'credential-grant.signature'),
    productCredentialEnvelope.signature,
  );
  await writeFile(join(root, 'credential-authority.pem'), credentialPublicKey);
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
      resetNativeStoreTransfer();
      nativeStandardTransferCompletions.length = 0;
    }
    const child = spawn(moon, ['test', packagePath, '--target', 'native'], {
      cwd: new URL('../', import.meta.url),
      env: packagePath === 'src/platform_native/filesystem'
        ? {...testEnvironment, ACTQL_TEST_NATIVE_STORE_ROOT: filesystemTestRoot}
        : testEnvironment,
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
    'build', '--target', 'native', 'src/cmd/native_remote_credential',
  ], {cwd: new URL('../', import.meta.url), stdio: 'inherit'});
  const credentialExecutable = join(
    new URL('../', import.meta.url).pathname,
    '_build/native/debug/build/cmd/native_remote_credential/' +
      'native_remote_credential.exe',
  );
  const credentialHelp = execFileSync(
    credentialExecutable,
    ['--help'],
    {encoding: 'utf8'},
  );
  assert.doesNotMatch(credentialHelp, /trusted-now/u);
  if (nativeSiteNamespace !== undefined) {
    const credentialArguments = [
      '--sqlite-library', testEnvironment.ACTQL_TEST_NATIVE_SQLITE_LIBRARY,
      '--crypto-library', cryptoLibrary,
      '--http-library', testEnvironment.ACTQL_TEST_NATIVE_HTTP_LIBRARY,
      '--journal', join(root, 'credential-site.sqlite'),
      '--input-root', root,
      '--grant-body-file', 'credential-grant.json',
      '--signature-file', 'credential-grant.signature',
      '--public-key-file', 'credential-authority.pem',
      '--grant-cid', productCredentialEnvelope.grantCid,
      '--key-id', productCredentialEnvelope.keyId,
      '--issuer-authority', 'credential-authority-a',
      '--ca', testEnvironment.ACTQL_TEST_NATIVE_HTTP_CA,
      '--cert', testEnvironment.ACTQL_TEST_NATIVE_HTTP_CERT,
      '--key', testEnvironment.ACTQL_TEST_NATIVE_HTTP_KEY,
      '--secret-file', testEnvironment.ACTQL_TEST_NATIVE_HTTP_SECRET,
      '--resource-origin', testEnvironment.ACTQL_TEST_NATIVE_HTTP_URL,
      '--resource-path', '/credential',
      '--operation', 'records:read',
      '--principal', 'principal-a',
      '--namespace', 'namespace-a',
      '--environment', 'test',
      '--site-key', 'site-a',
      '--site-generation', '2',
      '--runtime-bundle-cid', `sha256:${'a'.repeat(64)}`,
      '--connector-registration', 'http-source',
      '--connector-revision', 'http-source/1',
      '--run-invocation-cid', `sha256:${'b'.repeat(64)}`,
      '--task-attempt', '3',
      '--dispatch-request-cid', `sha256:${'c'.repeat(64)}`,
    ];
    const runCredential = (operationArguments, useId = 'use-a') => spawn('sudo', [
      'ip', 'netns', 'exec', nativeSiteNamespace,
      'sudo', `--user=${nativeSiteUser}`,
      credentialExecutable,
      ...credentialArguments,
      '--use-id', useId,
      ...operationArguments,
    ], {
      cwd: new URL('../', import.meta.url),
      env: process.env,
      stdio: 'inherit',
    });
    const credential = runCredential([
      'call',
    ]);
    const [code, signal] = await once(credential, 'exit');
    if (code !== 0) {
      throw new Error(
        `namespaced native credential call failed: ${code ?? signal}`,
      );
    }
    const query = runCredential(['query']);
    const [queryCode, querySignal] = await once(query, 'exit');
    if (queryCode !== 0) {
      throw new Error(
        `namespaced native credential query failed: ${
          queryCode ?? querySignal
        }`,
      );
    }
    const duplicate = runCredential([
      'call',
    ]);
    const [duplicateCode] = await once(duplicate, 'exit');
    if (duplicateCode === 0) {
      throw new Error('native credential retry repeated external I/O');
    }
    const revoke = runCredential([
      'revoke', '--confirmation', 'revoke-signed-grant',
    ]);
    const [revokeCode, revokeSignal] = await once(revoke, 'exit');
    if (revokeCode !== 0) {
      throw new Error(
        `namespaced native credential revocation failed: ${
          revokeCode ?? revokeSignal
        }`,
      );
    }
    const revoked = runCredential([
      'call',
    ], 'use-b');
    const [revokedCode] = await once(revoked, 'exit');
    if (revokedCode === 0) {
      throw new Error('revoked native credential started external I/O');
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
    '--poll-url', `${nativeHttpOrigin}/outbound/poll`,
    '--observation-url',
    `${nativeHttpOrigin}/outbound/observation`,
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
    '--poll-url', `${nativeHttpOrigin}/outbound/poll`,
    '--observation-url',
    `${nativeHttpOrigin}/outbound/status-observation`,
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
    '--poll-url', `${nativeHttpOrigin}/outbound/stale-poll`,
    '--observation-url',
    `${nativeHttpOrigin}/outbound/stale-observation`,
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
  execFileSync(moon, [
    'build', '--target', 'native',
    'src/cmd/native_remote_application_site',
  ], {cwd: new URL('../', import.meta.url), stdio: 'inherit'});
  const applicationExecutable = join(
    new URL('../', import.meta.url).pathname,
    '_build/native/debug/build/cmd/native_remote_application_site/' +
      'native_remote_application_site.exe',
  );
  const applicationVersion = await new Promise(resolve => {
    const child = spawn(applicationExecutable, ['--version'], {
      cwd: new URL('../', import.meta.url),
      env: {PATH: '/usr/bin:/bin', LANG: 'C'},
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    const stdout = [];
    const stderr = [];
    child.stdout.on('data', chunk => stdout.push(chunk));
    child.stderr.on('data', chunk => stderr.push(chunk));
    child.on('exit', (code, signal) => resolve({
      code,
      signal,
      stdout: Buffer.concat(stdout).toString('utf8'),
      stderr: Buffer.concat(stderr).toString('utf8'),
    }));
  });
  assert.equal(applicationVersion.code, 0, applicationVersion.stderr);
  assert.match(applicationVersion.stdout, /0\.1/);

  const repositoryRoot = new URL('../', import.meta.url).pathname;
  const runCapturedIn = (
    executable_,
    arguments_,
    environment,
    namespace,
    user,
  ) => {
    const siteEnvironment = {PATH: '/usr/bin:/bin', LANG: 'C', ...environment};
    const namespaced = namespace !== undefined;
    const command = namespaced ? 'sudo' : executable_;
    const commandArguments = namespaced
      ? [
          'ip', 'netns', 'exec', namespace,
          'sudo', `--user=${user}`, 'env',
          ...Object.entries(siteEnvironment)
            .map(([name, value]) => `${name}=${value}`),
          executable_, ...arguments_,
        ]
      : arguments_;
    const child = spawn(command, commandArguments, {
      cwd: repositoryRoot,
      env: namespaced ? process.env : siteEnvironment,
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    const stdout = [];
    const stderr = [];
    child.stdout.on('data', chunk => stdout.push(chunk));
    child.stderr.on('data', chunk => stderr.push(chunk));
    return Object.freeze({
      child,
      stdoutSnapshot: () => Buffer.concat(stdout).toString('utf8'),
      stderrSnapshot: () => Buffer.concat(stderr).toString('utf8'),
      completed: (async () => {
        const [code, signal] = await once(child, 'exit');
        return Object.freeze({
          code,
          signal,
          stdout: Buffer.concat(stdout).toString('utf8'),
          stderr: Buffer.concat(stderr).toString('utf8'),
        });
      })(),
    });
  };
  const runCaptured = (executable_, arguments_, environment = {}) =>
    runCapturedIn(
      executable_,
      arguments_,
      environment,
      nativeSiteNamespace,
      nativeSiteUser,
    );
  const runCapturedAtDestination = (
    executable_,
    arguments_,
    environment = {},
  ) => runCapturedIn(
    executable_,
    arguments_,
    environment,
    nativeDestinationNamespace ?? nativeSiteNamespace,
    nativeDestinationUser ?? nativeSiteUser,
  );
  const waitForServiceFile = async (path, operation) => {
    const deadline = Date.now() + 10_000;
    while (Date.now() < deadline) {
      if (existsSync(path)) return JSON.parse(await readFile(path, 'utf8'));
      if (operation.child.exitCode !== null) {
        const outcome = await operation.completed;
        throw new Error(
          `product Transfer service exited: ${JSON.stringify(outcome)}`,
        );
      }
      await new Promise(resolve => setTimeout(resolve, 20));
    }
    throw new Error(`product Transfer service did not create ${path}`);
  };
  const startProductTransferService = async (
    configuration,
    {destination = false} = {},
  ) => {
    if (configuration.mode === 'direct') {
      assert.equal(destination, true);
      const sourceFingerprint = new X509Certificate(
        await readFile(configuration.sourceAuthority.certificatePath),
      ).fingerprint256;
      const adminFingerprint = new X509Certificate(
        await readFile(join(root, 'destination-client.crt')),
      ).fingerprint256;
      const operation = runCapturedAtDestination(
        nativeDirectTransferSite,
        [
          '--host', configuration.host,
          '--port', configuration.port.toString(),
          '--cert', configuration.certificatePath,
          '--key', configuration.keyPath,
          '--ca', configuration.caPath,
          '--sqlite-library', testEnvironment.ACTQL_TEST_NATIVE_SQLITE_LIBRARY,
          '--journal', `${configuration.journalPath}.sqlite3`,
          '--clock-journal', `${configuration.journalPath}-clock.sqlite3`,
          '--root', configuration.root,
          '--source-site', configuration.sourceAuthority.siteKey,
          '--source-generation',
          configuration.sourceAuthority.siteGeneration.toString(),
          '--source-fingerprint', sourceFingerprint,
          '--destination-site', configuration.destinationSiteKey,
          '--destination-generation',
          configuration.destinationSiteGeneration.toString(),
          '--source-grant-cid', configuration.sourceGrantCid,
          '--destination-grant-cid', configuration.destinationGrantCid,
          '--route-capability-cid', configuration.routeCapabilityCid,
          '--admin-fingerprint', adminFingerprint,
          '--max-request-bytes', configuration.maxControlBytes.toString(),
          '--max-response-bytes', configuration.maxControlBytes.toString(),
          '--max-pending', '32',
          '--max-entries', configuration.maxObjects.toString(),
          '--max-chunks', configuration.maxChunks.toString(),
          '--max-manifest-bytes', configuration.maxManifestBytes.toString(),
          '--max-bytes', configuration.maxBytes.toString(),
          '--max-objects', configuration.maxObjects.toString(),
        ],
      );
      const origin = `https://${configuration.host}:${configuration.port}`;
      const probeArguments = [
        '--silent', '--show-error', '--max-time', '1',
        '--cert', join(root, 'client.crt'),
        '--key', join(root, 'client.key'),
        '--cacert', join(root, 'ca.crt'),
        `${origin}/v1/ready`,
      ];
      const deadline = Date.now() + 10_000;
      let lastProbeError = '';
      while (Date.now() < deadline) {
        if (operation.child.exitCode !== null) {
          const outcome = await operation.completed;
          throw new Error(
            `native Direct Site exited: ${JSON.stringify(outcome)}`,
          );
        }
        const probe = await runCaptured('curl', probeArguments).completed;
        if (probe.code === 0) {
          return {
            operation,
            origin,
            stopping: undefined,
            shutdown: async () => {
              const stopped = await runCaptured('curl', [
                '--silent', '--show-error', '--fail', '--max-time', '5',
                '--request', 'POST',
                '--cert', join(root, 'destination-client.crt'),
                '--key', join(root, 'destination-client.key'),
                '--cacert', join(root, 'ca.crt'),
                `${origin}/v1/admin/shutdown`,
              ]).completed;
              assert.equal(stopped.code, 0, stopped.stderr);
            },
          };
        }
        lastProbeError = probe.stderr;
        await new Promise(resolve => setTimeout(resolve, 20));
      }
      throw new Error(
        'native Direct Site did not accept mTLS traffic: ' +
          operation.stderrSnapshot() + lastProbeError,
      );
    }
    if (configuration.mode === 'store') {
      assert.equal(destination, false);
      const sourceFingerprint = new X509Certificate(
        await readFile(configuration.sourceAuthority.certificatePath),
      ).fingerprint256;
      const destinationFingerprint = new X509Certificate(
        await readFile(configuration.destinationAuthority.certificatePath),
      ).fingerprint256;
      const operation = runCapturedIn(
        nativeTransferStoreSite,
        [
          '--host', configuration.host,
          '--port', configuration.port.toString(),
          '--cert', configuration.certificatePath,
          '--key', configuration.keyPath,
          '--ca', configuration.caPath,
          '--sqlite-library', testEnvironment.ACTQL_TEST_NATIVE_SQLITE_LIBRARY,
          '--journal', `${configuration.journalPath}.sqlite3`,
          '--clock-journal', `${configuration.journalPath}-clock.sqlite3`,
          '--root', configuration.root,
          '--source-site', configuration.sourceAuthority.siteKey,
          '--source-generation',
          configuration.sourceAuthority.siteGeneration.toString(),
          '--source-fingerprint', sourceFingerprint,
          '--destination-site', configuration.destinationAuthority.siteKey,
          '--destination-generation',
          configuration.destinationAuthority.siteGeneration.toString(),
          '--destination-fingerprint', destinationFingerprint,
          '--source-grant-cid', configuration.sourceGrantCid,
          '--destination-grant-cid', configuration.destinationGrantCid,
          '--route-capability-cid', configuration.routeCapabilityCid,
          '--admin-fingerprint', sourceFingerprint,
          '--max-request-bytes', configuration.maxControlBytes.toString(),
          '--max-response-bytes', configuration.maxFrameBytes.toString(),
          '--max-pending', '32',
          '--max-entries', configuration.maxObjects.toString(),
          '--max-chunks', configuration.maxChunks.toString(),
          '--max-manifest-bytes', configuration.maxManifestBytes.toString(),
          '--max-frame-bytes', configuration.maxFrameBytes.toString(),
          '--max-bytes', configuration.maxBytes.toString(),
          '--max-objects', configuration.maxObjects.toString(),
        ],
        {},
      );
      const origin = `https://${configuration.host}:${configuration.port}`;
      const probeArguments = [
        '--silent', '--show-error', '--max-time', '1',
        '--cert', join(root, 'client.crt'),
        '--key', join(root, 'client.key'),
        '--cacert', join(root, 'ca.crt'),
        `${origin}/v1/ready`,
      ];
      const deadline = Date.now() + 10_000;
      while (Date.now() < deadline) {
        if (operation.child.exitCode !== null) {
          const outcome = await operation.completed;
          throw new Error(
            `native Transfer Store exited: ${JSON.stringify(outcome)}`,
          );
        }
        const probe = await runCaptured('curl', probeArguments).completed;
        if (probe.code === 0) {
          return {
            operation,
            origin,
            stopping: undefined,
            shutdown: async () => {
              const stopped = await runCaptured('curl', [
                '--silent', '--show-error', '--fail', '--max-time', '5',
                '--request', 'POST',
                '--cert', join(root, 'client.crt'),
                '--key', join(root, 'client.key'),
                '--cacert', join(root, 'ca.crt'),
                `${origin}/v1/admin/shutdown`,
              ]).completed;
              assert.equal(stopped.code, 0, stopped.stderr);
            },
          };
        }
        await new Promise(resolve => setTimeout(resolve, 20));
      }
      throw new Error('native Transfer Store did not accept mTLS traffic');
    }
    const configurationPath = join(
      root,
      `transfer-service-${configuration.mode}-${configuration.instance}.json`,
    );
    await writeFile(configurationPath, JSON.stringify(configuration), {
      mode: 0o600,
    });
    const script = join(repositoryRoot, 'scripts/run-product-transfer-service.mjs');
    const operation = destination
      ? runCapturedAtDestination(process.execPath, [script, configurationPath])
      : runCapturedIn(process.execPath, [script, configurationPath], {});
    const ready = await waitForServiceFile(configuration.readyPath, operation);
    return {operation, origin: ready.origin, stopping: undefined};
  };
  stopProductTransferService = async (running, signal = 'SIGTERM') => {
    if (running === undefined) return;
    if (running.stopping === undefined) {
      running.stopping = (async () => {
        if (running.shutdown !== undefined && signal !== 'SIGKILL') {
          await running.shutdown();
        } else {
          running.operation.child.kill(signal);
        }
        const outcome = await running.operation.completed;
        if (signal !== 'SIGKILL' && outcome.code !== 0) {
          throw new Error(
            `product Transfer service cleanup failed: ${JSON.stringify(outcome)}`,
          );
        }
      })();
    }
    await running.stopping;
  };

  const applicationRoot = join(root, 'remote-application');
  const applicationTransferRoot = join(root, 'remote-application-transfer');
  const applicationPublicationRoot =
    join(root, 'remote-application-publication');
  const applicationRuntimeRoot =
    join(root, 'remote-application-runtime');
  const applicationBundleInputRoot =
    join(root, 'remote-application-bundle-input');
  const applicationCoordinatorRoot =
    join(root, 'remote-application-coordinator');
  const applicationOutputTransferRoot =
    join(root, 'remote-application-output-transfer');
  const applicationOutputTransferJournal =
    join(root, 'remote-application-output-transfer.sqlite3');
  const productTransferRoot = join(root, 'product-transfer-service');
  await Promise.all([
    mkdir(applicationRoot),
    mkdir(applicationTransferRoot),
    mkdir(applicationPublicationRoot),
    mkdir(applicationRuntimeRoot),
    mkdir(applicationBundleInputRoot),
    mkdir(applicationCoordinatorRoot),
    mkdir(applicationOutputTransferRoot),
    mkdir(productTransferRoot),
  ]);

  execFileSync(moon, [
    'build', '--target', 'native', 'src/cmd/native_runtime_bundle',
  ], {cwd: repositoryRoot, stdio: 'inherit'});
  const runtimeBundleExecutable = join(
    repositoryRoot,
    '_build/native/debug/build/cmd/native_runtime_bundle/' +
      'native_runtime_bundle.exe',
  );
  const applicationComponent = await readFile(applicationExecutable);
  const applicationComponentCid = physicalCid(applicationComponent);
  const duckdbLibrary = join(
    repositoryRoot,
    `adapters/connectors/duckdb/node/node_modules/@duckdb/` +
      `node-bindings-${process.platform}-${process.arch}/` +
      (process.platform === 'darwin' ? 'libduckdb.dylib' : 'libduckdb.so'),
  );
  assert.equal(existsSync(duckdbLibrary), true, duckdbLibrary);
  const duckdbComponent = await readFile(duckdbLibrary);
  const applicationRuntimeManifest = runtimeControl.prepare({
    issuerAuthority: 'bundle-authority-a',
    bundleName: 'native-application-site',
    revision: 'native-application/1',
    targetTriple,
    components: [
      {
        role: 'duckdb_library',
        cid: physicalCid(duckdbComponent),
        bytes: BigInt(duckdbComponent.byteLength),
      },
      {
        role: 'runtime_executable',
        cid: applicationComponentCid,
        bytes: BigInt(applicationComponent.byteLength),
      },
    ],
    connectorRegistration: 'local',
    connectorRevision: 'local/1',
    strategyRevision: 'strategy/1',
  });
  const applicationRuntimeEnvelope = signRemoteRuntimeBundle(
    applicationRuntimeManifest,
    runtimeControl,
    {keyId: 'key-a', privateKey: runtimeKeys.privateKey},
  );
  await Promise.all([
    writeFile(
      join(applicationBundleInputRoot, 'runtime-public.pem'),
      testEnvironment.ACTQL_TEST_NATIVE_REMOTE_RUNTIME_PUBLIC_KEY,
      {mode: 0o600},
    ),
    writeFile(
      join(applicationBundleInputRoot, 'trust.json'),
      JSON.stringify({
        authorities: [{
          admit_new_bundles: true,
          issuer_authority: 'bundle-authority-a',
          key_id: 'key-a',
          public_key_name: 'runtime-public.pem',
        }],
        version: 'actql-native-runtime-bundle-trust/0.1',
      }),
      {mode: 0o600},
    ),
    writeFile(
      join(applicationBundleInputRoot, 'manifest.json'),
      applicationRuntimeEnvelope.body,
      {mode: 0o600},
    ),
    writeFile(
      join(applicationBundleInputRoot, 'signature.txt'),
      applicationRuntimeEnvelope.signature,
      {mode: 0o600},
    ),
    writeFile(
      join(applicationBundleInputRoot, 'component.bin'),
      applicationComponent,
      {mode: 0o700},
    ),
    writeFile(
      join(applicationBundleInputRoot, 'duckdb.bin'),
      duckdbComponent,
      {mode: 0o600},
    ),
  ]);
  const applicationBundleCommon = [
    '--store-root', applicationRuntimeRoot,
    '--sqlite-library', testEnvironment.ACTQL_TEST_NATIVE_SQLITE_LIBRARY,
    '--crypto-library', cryptoLibrary,
    '--target-triple', targetTriple,
    '--authority-root', applicationBundleInputRoot,
    '--trust-config-name', 'trust.json',
    '--capacity-bytes', '268435456',
    '--max-bundles', '4',
    '--max-owners', '8',
    '--max-record-bytes', '1048576',
  ];
  const installedApplicationBundle = await runCaptured(
    runtimeBundleExecutable,
    [
      ...applicationBundleCommon,
      'install',
      '--install-id', 'native-application-install',
      '--signature-key-id', 'key-a',
      '--bundle-cid', applicationRuntimeEnvelope.runtimeBundleCid,
      '--input-root', applicationBundleInputRoot,
      '--manifest-name', 'manifest.json',
      '--signature-name', 'signature.txt',
      '--component-file', 'duckdb_library=duckdb.bin',
      '--component-file', 'runtime_executable=component.bin',
    ],
  ).completed;
  assert.equal(
    installedApplicationBundle.code,
    0,
    installedApplicationBundle.stderr,
  );
  const activatedApplicationBundle = await runCaptured(
    runtimeBundleExecutable,
    [
      ...applicationBundleCommon,
      'activate',
      '--bundle-cid', applicationRuntimeEnvelope.runtimeBundleCid,
    ],
  ).completed;
  assert.equal(
    activatedApplicationBundle.code,
    0,
    activatedApplicationBundle.stderr,
  );

  execFileSync(moon, [
    'build', '--target', 'native',
    'src/cmd/native_remote_transfer_receive',
  ], {cwd: repositoryRoot, stdio: 'inherit'});
  execFileSync(moon, [
    'build', '--target', 'native',
    'src/cmd/native_remote_application_inspect',
  ], {cwd: repositoryRoot, stdio: 'inherit'});
  execFileSync(moon, [
    'build', '--target', 'native',
    'src/cmd/native_direct_transfer_site',
  ], {cwd: repositoryRoot, stdio: 'inherit'});
  execFileSync(moon, [
    'build', '--target', 'native',
    'src/cmd/native_transfer_store_site',
  ], {cwd: repositoryRoot, stdio: 'inherit'});
  execFileSync(moon, [
    'build', '--target', 'native',
    'src/cmd/native_remote_coordinator',
  ], {cwd: repositoryRoot, stdio: 'inherit'});
  const transferReceiver = join(
    repositoryRoot,
    '_build/native/debug/build/cmd/native_remote_transfer_receive/' +
      'native_remote_transfer_receive.exe',
  );
  const applicationInspector = join(
    repositoryRoot,
    '_build/native/debug/build/cmd/native_remote_application_inspect/' +
      'native_remote_application_inspect.exe',
  );
  const nativeDirectTransferSite = join(
    repositoryRoot,
    '_build/native/debug/build/cmd/native_direct_transfer_site/' +
      'native_direct_transfer_site.exe',
  );
  const nativeTransferStoreSite = join(
    repositoryRoot,
    '_build/native/debug/build/cmd/native_transfer_store_site/' +
      'native_transfer_store_site.exe',
  );
  const nativeRemoteCoordinator = join(
    repositoryRoot,
    '_build/native/debug/build/cmd/native_remote_coordinator/' +
      'native_remote_coordinator.exe',
  );

  const catalogs = await readFile(join(
    repositoryRoot,
    'src/query_integration/query_amount_catalog_wbtest.mbt',
  ), 'utf8');
  const catalog = catalogs
    .slice(catalogs.indexOf('fn query_amount_nullable_catalog'))
    .match(
      /query_catalog_from_wire\(\s*("(?:[^"\\]|\\.)*")\s*,\s*expected="([^"]+)"/,
    );
  assert(catalog);
  const environment = JSON.parse(JSON.parse(catalog[1]));
  Object.assign(environment.host_policy_profile.capacity, {
    max_analytic_frame_memberships: 10000,
    max_analytic_input_wire_bytes: 10000,
    max_analytic_output_wire_bytes: 10000,
    max_analytic_partition_wire_bytes: 10000,
  });
  const {
    evidence_bundle_cid: ignoredEnvironmentCid,
    ...environmentBody
  } = environment;
  void ignoredEnvironmentCid;
  environment.evidence_bundle_cid = canonicalHash(environmentBody);
  const [registry, values, fragment] = await pinnedEngineContracts(
    repositoryRoot,
  );
  const applicationFiles = new Map([
    ['program.json', await readFile(join(
      repositoryRoot,
      'adapters/connectors/duckdb/node/examples/program.json',
    ), 'utf8')],
    ['environment.json', canonical(environment)],
    ['environment.cid', environment.evidence_bundle_cid],
    ['parameters.json', '{"minimum":1}'],
    ['registry.json', registry],
    ['values.json', values],
    ['fragment.json', fragment],
    ['query.json', await readFile(join(
      repositoryRoot,
      'spec/contracts/actql-query-acquisition.json',
    ), 'utf8')],
    ['evidence.json', await readFile(join(
      repositoryRoot,
      'spec/contracts/actql-query-process-evidence.json',
    ), 'utf8')],
    ['two-receipt.json', await readFile(join(
      repositoryRoot,
      'spec/contracts/actql-query-two-receipt.json',
    ), 'utf8')],
    ['runtime-public.pem',
      testEnvironment.ACTQL_TEST_NATIVE_REMOTE_RUNTIME_PUBLIC_KEY],
  ]);
  await Promise.all([...applicationFiles].map(([name, body_]) =>
    writeFile(join(applicationRoot, name), body_)));

  const inspectedRun = runCaptured(applicationInspector, [
    '--application-root', applicationRoot,
  ]);
  const inspected = await inspectedRun.completed;
  assert.equal(inspected.code, 0, inspected.stderr);
  const applicationContract = JSON.parse(inspected.stdout);
  assert.equal(applicationContract.task_count, 4);

  nativeStoreTransferCid = undefined;
  nativeStoreTransferChunks = 0;
  nativeStoreTransferSealed = false;
  nativeStoreTransferManifest = [];
  nativeStoreTransferBodies.length = 0;
  nativeStoreUses.clear();
  const inputChunks = [Buffer.from('{"id":3}'), Buffer.from('{"id":2}')];
  const inputSchemaCid = `sha256:${'1'.repeat(64)}`;
  const inputViewCid = `sha256:${'2'.repeat(64)}`;
  const inputCodecCid = `sha256:${'3'.repeat(64)}`;
  const inputTransfer = transferControl.prepare({
    coordinatorAuthority: 'native-application-coordinator',
    transferAttemptId: 'native-application-input-transfer',
    route: 'store',
    sourceSite: 'native-application-source',
    sourceSiteGeneration: 1,
    destinationSite: 'native-standard-transfer-site',
    destinationSiteGeneration: 1,
    sourceMaterialGeneration: 'native-application-input-material',
    physicalManifest: {
      version: 'actql-managed-physical-manifest/0.1',
      schemaContractCid: inputSchemaCid,
      viewContractCid: inputViewCid,
      codecContractCid: inputCodecCid,
      rowCount: 2,
      chunks: inputChunks.map(bytes => ({
        cid: physicalCid(bytes),
        byteLength: BigInt(bytes.byteLength),
        rowCount: 1,
      })),
    },
    limits: {
      maxChunks: 8,
      maxManifestBytes: 4096,
      maxReferencedBytes: 1048576n,
    },
    capacityBytes: 1048576n,
    expiresAtMilliseconds: 4102444800000n,
    sourceGrantCid: physicalCid('native-application-input-source-grant'),
    destinationGrantCid:
      physicalCid('native-application-input-destination-grant'),
    routeCapabilityCid:
      physicalCid('native-application-input-store-route'),
  });
  const inputSources = inputChunks.map(bytes => Object.freeze({
    cid: physicalCid(bytes),
    bytes: bytes.byteLength,
    async consume(emit) { await emit(bytes); },
  }));
  await uploadHttpsTransferObject({
    origin: nativeHttpOrigin,
    ca: await readFile(join(root, 'ca.crt')),
    cert: await readFile(join(root, 'client.crt')),
    key: await readFile(join(root, 'client.key')),
    control: transferControl,
    request: inputTransfer,
    sourceBodies: inputSources,
  });
  nativeApplicationInputRequestBody =
    transferControl.requestJson(inputTransfer);
  nativeApplicationInputManifestBody =
    transferControl.manifestJson(inputTransfer);
  const applicationTransferJournal =
    join(root, 'remote-application-transfer.sqlite3');
  const inputUseId = 'native-application-input-use';
  const receiveArguments = [
    '--sqlite-library', testEnvironment.ACTQL_TEST_NATIVE_SQLITE_LIBRARY,
    '--http-library', library,
    '--journal', applicationTransferJournal,
    '--root', applicationTransferRoot,
    '--origin', nativeHttpOrigin,
    '--ca', join(root, 'ca.crt'),
    '--cert', join(root, 'client.crt'),
    '--key', join(root, 'client.key'),
    '--request-url',
    `${nativeHttpOrigin}/v1/native-application/input/request`,
    '--manifest-url',
    `${nativeHttpOrigin}/v1/native-application/input/manifest`,
    '--request-cid', transferControl.identity(inputTransfer),
    '--manifest-cid', transferControl.requestProjection(inputTransfer)[7],
    '--use-id', inputUseId,
    '--max-chunks', '8',
    '--max-manifest-bytes', '4096',
    '--max-bytes', '1048576',
  ];
  const receivedRun = runCaptured(transferReceiver, receiveArguments);
  const received = await receivedRun.completed;
  assert.equal(received.code, 0, received.stderr);
  const inputBindingBody = received.stdout.trim();
  const inputBinding = remoteSiteControl.prepareInputBinding(inputBindingBody);

  const operationCapabilityCid =
    physicalCid('native-application-operation-capability');
  const issuerCapabilityCid =
    physicalCid('native-application-issuer-capability');
  const applicationMaxBytes = 268435456n;
  const budget = remoteSiteControl.prepareBudget({
    retainedBytes: applicationMaxBytes,
    executionBytes: applicationMaxBytes,
  });
  const dispatch = remoteSiteControl.prepare({
    coordinatorAuthority: 'native-application-coordinator',
    runDefinitionCid: applicationContract.program_definition_cid,
    taskKey: 'application-task',
    taskAttempt: 1,
    dispatchId: 'native-application-dispatch',
    siteKey: 'native-standard-transfer-site',
    siteGeneration: 1,
    runtimeBundleCid: applicationRuntimeEnvelope.runtimeBundleCid,
    connectorRegistration: 'local',
    connectorRevision: 'local/1',
    strategyRevision: 'strategy/1',
    inputBindingCid: remoteSiteControl.inputBindingIdentity(inputBinding),
    obligationsCid: physicalCid('native-application-obligations'),
    budgetCid: remoteSiteControl.budgetIdentity(budget),
    evidenceIssuerCapabilityCid: issuerCapabilityCid,
    grantCid: operationCapabilityCid,
  });
  let applicationOutputReceiveArguments;
  nativeTransferInjectLostReply = false;
  const publicationAuthorityCid =
    physicalCid('native-application-publication-store');
  const resultDefinitionCid =
    physicalCid('native-application-result-definition');
  const orderingEvidenceCid =
    physicalCid('native-application-ordering-evidence');
  if (applicationOutputRoute === 'store') {
    nativeStoreAutoCommit = false;
    resetNativeStoreTransfer();
  }
  const transferServiceRoot = join(
    productTransferRoot,
    applicationOutputRoute,
  );
  await mkdir(transferServiceRoot, {recursive: true});
  const transferServiceReady = join(
    productTransferRoot,
    `${applicationOutputRoute}-ready-1.json`,
  );
  const transferServiceUploadReplied = join(
    productTransferRoot,
    `${applicationOutputRoute}-upload-replied.json`,
  );
  const transferServiceConfiguration = {
    mode: applicationOutputRoute,
    instance: 1,
    host: applicationOutputRoute === 'direct'
      ? nativeDestinationHost
      : nativeHttpHost,
    port: nativeTransferPort,
    keyPath: join(
      root,
      applicationOutputRoute === 'direct'
        ? 'destination-server.key'
        : 'server.key',
    ),
    certificatePath: join(
      root,
      applicationOutputRoute === 'direct'
        ? 'destination-server.crt'
        : 'server.crt',
    ),
    caPath: join(root, 'ca.crt'),
    root: transferServiceRoot,
    journalPath: join(productTransferRoot, `${applicationOutputRoute}-journal`),
    readyPath: transferServiceReady,
    uploadRepliedPath: applicationOutputRoute === 'store'
      ? transferServiceUploadReplied
      : undefined,
    storeAuthorityCid: physicalCid('native-output-transfer-store'),
    sourceAuthority: {
      certificatePath: join(root, 'client.crt'),
      siteKey: 'native-standard-transfer-site',
      siteGeneration: 1,
    },
    destinationAuthority: {
      certificatePath: join(root, 'destination-client.crt'),
      siteKey: 'native-destination',
      siteGeneration: 3,
    },
    destinationSiteKey: 'native-destination',
    destinationSiteGeneration: 3,
    sourceGrantCid: physicalCid('native-application-output-source-grant'),
    destinationGrantCid:
      physicalCid('native-application-output-destination-grant'),
    routeCapabilityCid:
      physicalCid('native-application-output-direct-route'),
    maxControlBytes: 131072,
    maxManifestBytes: 4096,
    maxChunks: 8,
    maxBytes: 1048576,
    maxFrameBytes: 4096,
    maxObjects: 32,
  };
  productTransferService = await startProductTransferService(
    transferServiceConfiguration,
    {destination: applicationOutputRoute === 'direct'},
  );
  let transferServiceOrigin = productTransferService.origin;
  const outputIntent = remoteSiteControl.prepareOutputIntent(dispatch, {
    storeAuthorityCid: publicationAuthorityCid,
    publicationAttemptCid:
      physicalCid('native-application-publication-attempt'),
    resultDefinitionCid,
    orderingEvidenceCid,
    coordinatorAuthority: 'native-application-coordinator',
    transferAttemptId: 'native-application-output-transfer',
    transferRoute: applicationOutputRoute,
    destinationSite: 'native-destination',
    destinationSiteGeneration: 3,
    transferMaxBytes: 1048576n,
    transferExpiresAtMilliseconds: 4102444800000n,
    sourceGrantCid: physicalCid('native-application-output-source-grant'),
    destinationGrantCid:
      physicalCid('native-application-output-destination-grant'),
    routeCapabilityCid:
      physicalCid('native-application-output-direct-route'),
    transferOrigin: transferServiceOrigin,
  });
  const coordinatorPort = await allocatePort(nativeHttpHost);
  const coordinatorOrigin = `https://${nativeHttpHost}:${coordinatorPort}`;
  const dispatchFile = 'dispatch.json';
  const inputBindingFile = 'input-binding.json';
  const outputEnvelopeFile = 'output-envelope.json';
  await Promise.all([
    writeFile(
      join(applicationCoordinatorRoot, dispatchFile),
      remoteSiteControl.requestJson(dispatch),
      {mode: 0o600},
    ),
    writeFile(
      join(applicationCoordinatorRoot, inputBindingFile),
      inputBindingBody,
      {mode: 0o600},
    ),
    writeFile(
      join(applicationCoordinatorRoot, outputEnvelopeFile),
      remoteSiteControl.pollOutputJson(dispatch, outputIntent),
      {mode: 0o600},
    ),
  ]);
  const siteFingerprint = new X509Certificate(
    await readFile(join(root, 'client.crt')),
  ).fingerprint256;
  const coordinatorAdminFingerprint = new X509Certificate(
    await readFile(join(root, 'destination-client.crt')),
  ).fingerprint256;
  const coordinatorArguments = [
      '--sqlite-library', testEnvironment.ACTQL_TEST_NATIVE_SQLITE_LIBRARY,
      '--journal', join(applicationCoordinatorRoot, 'dispatch.sqlite3'),
      '--output-journal', join(applicationCoordinatorRoot, 'output.sqlite3'),
      '--contract-root', applicationCoordinatorRoot,
      '--dispatch-file', dispatchFile,
      '--dispatch-cid', remoteSiteControl.identity(dispatch),
      '--input-binding-file', inputBindingFile,
      '--output-envelope-file', outputEnvelopeFile,
      '--authority', 'native-application-coordinator',
      '--site-fingerprint', siteFingerprint,
      '--admin-fingerprint', coordinatorAdminFingerprint,
      '--host', nativeHttpHost,
      '--port', coordinatorPort.toString(),
      '--cert', join(root, 'server.crt'),
      '--key', join(root, 'server.key'),
      '--ca', join(root, 'ca.crt'),
      '--max-chunks', '8',
      '--max-manifest-bytes', '4096',
      '--max-referenced-bytes', '1048576',
  ];
  let coordinatorRun = runCapturedIn(
    nativeRemoteCoordinator,
    coordinatorArguments,
    {},
    undefined,
    undefined,
  );
  const coordinatorDeadline = Date.now() + 10_000;
  while (Date.now() < coordinatorDeadline) {
    if (coordinatorRun.child.exitCode !== null) {
      assert.fail(JSON.stringify(await coordinatorRun.completed));
    }
    const ready = await runCapturedIn('curl', [
      '--silent', '--show-error', '--max-time', '1',
      '--request', 'POST',
      '--cert', join(root, 'destination-client.crt'),
      '--key', join(root, 'destination-client.key'),
      '--cacert', join(root, 'ca.crt'),
      '--header', 'content-type: application/json',
      '--data', '{}',
      `${coordinatorOrigin}/v1/coordinator/output-plan`,
    ], {}, undefined, undefined).completed;
    if (ready.code === 0) break;
    await new Promise(resolve => setTimeout(resolve, 20));
  }
  let terminalStatusDropped = false;
  let interruptedCoordinatorExit;
  const applicationProxyFailures = [];
  const applicationProxyEvents = [];
  let applicationControlRequests = 0;
  applicationControlProxy = createServer({
    key: await readFile(join(root, 'server.key')),
    cert: await readFile(join(root, 'server.crt')),
    ca: await readFile(join(root, 'ca.crt')),
    requestCert: true,
    rejectUnauthorized: true,
  }, async (incoming, outgoing) => {
    applicationControlRequests += 1;
    const chunks = [];
    for await (const chunk of incoming) chunks.push(chunk);
    const body = Buffer.concat(chunks);
    const proxyEvent = {
      path: incoming.url,
      bodyBytes: body.length,
      terminalStatus: body.includes('"evidence":{'),
    };
    applicationProxyEvents.push(proxyEvent);
    if (applicationProxyEvents.length > 32) applicationProxyEvents.shift();
    if (!terminalStatusDropped &&
        incoming.url.endsWith('/outbound/observations') &&
        body.includes('actql-remote-dispatch-status/0.1') &&
        body.includes('"evidence":{')) {
      terminalStatusDropped = true;
      proxyEvent.dropped = true;
      incoming.socket.destroy();
      const interrupted = coordinatorRun;
      interrupted.child.kill('SIGKILL');
      interruptedCoordinatorExit = await interrupted.completed;
      coordinatorRun = runCapturedIn(
        nativeRemoteCoordinator,
        coordinatorArguments,
        {},
        undefined,
        undefined,
      );
      return;
    }
    const upstream = httpsRequest(`${coordinatorOrigin}${incoming.url}`, {
      method: incoming.method,
      agent: false,
      cert: await readFile(join(root, 'client.crt')),
      key: await readFile(join(root, 'client.key')),
      ca: await readFile(join(root, 'ca.crt')),
      headers: {'content-type': 'application/json'},
    }, response => {
      proxyEvent.status = response.statusCode;
      outgoing.writeHead(response.statusCode, {
        'content-type': response.headers['content-type'] ??
          'application/json',
      });
      response.pipe(outgoing);
    });
    upstream.on('error', error => {
      applicationProxyFailures.push({
        path: incoming.url,
        bodyBytes: body.length,
        code: error.code,
        message: error.message,
      });
      outgoing.destroy(error);
    });
    upstream.end(body);
  });
  applicationControlProxy.listen(0, nativeHttpHost);
  await once(applicationControlProxy, 'listening');
  const proxyPort = applicationControlProxy.address().port;
  const applicationControlOrigin =
    `https://${nativeHttpHost}:${proxyPort}`;
  const applicationArguments = [
    '--sqlite-library', testEnvironment.ACTQL_TEST_NATIVE_SQLITE_LIBRARY,
    '--crypto-library', cryptoLibrary,
    '--http-library', library,
    '--application-root', applicationRoot,
    '--transfer-root', applicationTransferRoot,
    '--publication-root', applicationPublicationRoot,
    '--publication-authority-cid', publicationAuthorityCid,
    '--runtime-root', applicationRuntimeRoot,
    '--transfer-journal', applicationTransferJournal,
    '--dispatch-journal', join(root, 'remote-application-dispatch.sqlite3'),
    '--database-path', join(root, 'remote-application.duckdb'),
    '--site-key', 'native-standard-transfer-site',
    '--site-generation', '1',
    '--target-triple', targetTriple,
    '--component-cid', applicationComponentCid,
    '--process-hold-id', 'runtime-process:native-application',
    '--bundle-issuer', 'bundle-authority-a',
    '--bundle-key-id', 'key-a',
    '--bundle-public-key-root', applicationRoot,
    '--bundle-public-key-file', 'runtime-public.pem',
    '--ca', join(root, 'ca.crt'),
    '--cert', join(root, 'client.crt'),
    '--key', join(root, 'client.key'),
    '--poll-url', applicationControlOrigin +
      '/v1/sites/native-standard-transfer-site/generations/1/outbound/poll',
    '--observation-url', applicationControlOrigin +
      '/v1/sites/native-standard-transfer-site/generations/1/' +
      'outbound/observations',
    '--operation-capability-cid', operationCapabilityCid,
    '--issuer-capability-cid', issuerCapabilityCid,
    '--input-schema-cid', inputSchemaCid,
    '--input-view-cid', inputViewCid,
    '--input-codec-cid', inputCodecCid,
    '--task-key', 'application-task',
    '--expected-task', '1',
    '--max-polls', '32',
    '--max-rows', '100',
    '--max-bytes', String(applicationMaxBytes),
    '--output-chunk-bytes', '4096',
  ];
  const componentCidIndex = applicationArguments.indexOf('--component-cid');
  assert.notEqual(componentCidIndex, -1);
  const mismatchedApplicationArguments = [...applicationArguments];
  mismatchedApplicationArguments[componentCidIndex + 1] =
    `sha256:${'0'.repeat(64)}`;
  const mismatchedApplication = await runCaptured(
    applicationExecutable,
    mismatchedApplicationArguments,
  ).completed;
  assert.notEqual(mismatchedApplication.code, 0);
  const applicationBundleName = `runtime-bundle-${createHash('sha256')
    .update(applicationRuntimeEnvelope.runtimeBundleCid).digest('hex')}`;
  const installedBundlePath = join(applicationRuntimeRoot,
    applicationBundleName);
  const preservedBundlePath = join(applicationRuntimeRoot,
    `${applicationBundleName}.preserved`);
  const requestsBeforeSubstitution = applicationControlRequests;
  await rename(installedBundlePath, preservedBundlePath);
  try {
    const missingComponent = await runCaptured(
      applicationExecutable, applicationArguments,
    ).completed;
    assert.notEqual(missingComponent.code, 0);
    await writeFile(installedBundlePath, 'substituted bundle');
    const substitutedComponent = await runCaptured(
      applicationExecutable, applicationArguments,
    ).completed;
    assert.notEqual(substitutedComponent.code, 0);
    assert.equal(applicationControlRequests, requestsBeforeSubstitution);
  } finally {
    await rm(installedBundlePath, {force: true});
    await rename(preservedBundlePath, installedBundlePath);
  }
  const applicationStartedAt = Date.now();
  const applicationRun = runCaptured(
    applicationExecutable,
    applicationArguments,
  );
  const destinationCompletion = applicationOutputRoute === 'store'
    ? (async () => {
        const planDeadline = Date.now() + 60_000;
        let planBody;
        let lastPlanObservation;
        while (Date.now() < planDeadline) {
          const result = await runCapturedIn('curl', [
            '--silent', '--show-error', '--fail', '--max-time', '2',
            '--request', 'POST',
            '--cert', join(root, 'destination-client.crt'),
            '--key', join(root, 'destination-client.key'),
            '--cacert', join(root, 'ca.crt'),
            '--header', 'content-type: application/json',
            '--data', '{}',
            `${coordinatorOrigin}/v1/coordinator/output-plan`,
          ], {}, undefined, undefined).completed;
          lastPlanObservation = result;
          if (result.code === 0) {
            planBody = result.stdout;
            console.log(JSON.stringify({
              kind: 'native-output-plan-ready',
              elapsedMilliseconds: Date.now() - applicationStartedAt,
            }));
            break;
          }
          if (applicationRun.child.exitCode !== null) {
            assert.fail(JSON.stringify({
              applicationExit: await applicationRun.completed,
              lastPlanObservation,
            }));
          }
          if (coordinatorRun.child.exitCode !== null) {
            assert.fail(JSON.stringify({
              coordinatorExit: await coordinatorRun.completed,
              lastPlanObservation,
            }));
          }
          await new Promise(resolve => setTimeout(resolve, 100));
        }
        assert.notEqual(
          planBody,
          undefined,
          `native output plan unavailable: ${JSON.stringify(
            {
              lastPlanObservation,
              applicationProcess: process.platform === 'linux'
                ? await runCapturedIn('ps', [
                    '-p', String(applicationRun.child.pid),
                    '-o', 'pid,stat,etime,time,comm',
                  ], {}, undefined, undefined).completed
                : undefined,
              applicationStdout: applicationRun.stdoutSnapshot(),
              applicationStderr: applicationRun.stderrSnapshot(),
              coordinatorStdout: coordinatorRun.stdoutSnapshot(),
              coordinatorStderr: coordinatorRun.stderrSnapshot(),
              terminalStatusDropped,
              applicationControlRequests,
              applicationProxyEvents,
              applicationProxyFailures,
            },
          )}`,
        );
        const plan = JSON.parse(planBody);
        const transferRequest = transferControl.admitJson(
          plan.transfer_request_json,
          plan.physical_manifest_json,
          plan.transfer_request_cid,
          plan.physical_manifest_cid,
          {
            maxChunks: 8,
            maxManifestBytes: 4096,
            maxReferencedBytes: 1048576n,
          },
        );
        nativeApplicationOutputRequestBody =
          transferControl.requestJson(transferRequest);
        nativeApplicationOutputManifestBody =
          transferControl.manifestJson(transferRequest);
        const envelopePath = join(
          productTransferRoot,
          'store-restart-admission.json',
        );
        await writeFile(
          envelopePath,
          transferControl.admissionEnvelopeJson(transferRequest),
          {mode: 0o600},
        );
        const projection = transferControl.requestProjection(transferRequest);
        let sealed = false;
        let lastStoreObservation;
        const sealDeadline = Date.now() + 60_000;
        while (Date.now() < sealDeadline && !sealed) {
          const observed = await runCapturedIn('curl', [
            '--silent', '--show-error', '--max-time', '2',
            '--request', 'POST',
            '--cert', join(root, 'client.crt'),
            '--key', join(root, 'client.key'),
            '--cacert', join(root, 'ca.crt'),
            '--header', 'content-type: application/json',
            '--header',
            `actql-transfer-cid: ${transferControl.identity(transferRequest)}`,
            '--header', `actql-manifest-cid: ${projection[7]}`,
            '--data-binary', `@${envelopePath}`,
            `${transferServiceOrigin}/v1/transfer-store/uploads`,
          ], {}, undefined, undefined).completed;
          lastStoreObservation = observed;
          if (observed.code === 0) {
            sealed = JSON.parse(observed.stdout).sealed === true;
          }
          if (!sealed) await new Promise(resolve => setTimeout(resolve, 20));
        }
        assert.equal(
          sealed,
          true,
          `native Store upload did not seal: ${JSON.stringify(
            lastStoreObservation,
          )}`,
        );
        await stopProductTransferService(productTransferService, 'SIGKILL');
        const restartedConfiguration = {
          ...transferServiceConfiguration,
          instance: 2,
          port: Number(new URL(transferServiceOrigin).port),
          readyPath: join(
            productTransferRoot,
            `${applicationOutputRoute}-ready-2.json`,
          ),
        };
        productTransferService = await startProductTransferService(
          restartedConfiguration,
        );
        transferServiceOrigin = productTransferService.origin;
        applicationOutputReceiveArguments = [
          '--sqlite-library', testEnvironment.ACTQL_TEST_NATIVE_SQLITE_LIBRARY,
          '--http-library', library,
          '--journal', applicationOutputTransferJournal,
          '--root', applicationOutputTransferRoot,
          '--origin', transferServiceOrigin,
          '--ca', join(root, 'ca.crt'),
          '--cert', join(root, 'destination-client.crt'),
          '--key', join(root, 'destination-client.key'),
          '--request-url',
          `${nativeHttpOrigin}/v1/native-application/output/request`,
          '--manifest-url',
          `${nativeHttpOrigin}/v1/native-application/output/manifest`,
          '--request-cid', transferControl.identity(transferRequest),
          '--manifest-cid', projection[7],
          '--use-id', 'native-application-output-use',
          '--max-chunks', '8',
          '--max-manifest-bytes', '4096',
          '--max-bytes', '1048576',
        ];
        const receivedOutput = runCapturedAtDestination(transferReceiver, [
          ...applicationOutputReceiveArguments,
          '--mode', 'receive-output',
        ]);
        const outcome = await receivedOutput.completed;
        assert.equal(outcome.code, 0, outcome.stderr);
        const record = transferControl.admitReplyJson(
          outcome.stdout.trim(),
          transferRequest,
        );
        assert.equal(
          transferControl.recordIsDestinationCommitted(record),
          true,
        );
      })()
    : Promise.resolve();
  const applicationExit = await applicationRun.completed;
  if (applicationExit.code !== 0) {
    if (coordinatorRun.child.exitCode === null &&
        coordinatorRun.child.signalCode === null) {
      coordinatorRun.child.kill('SIGTERM');
    }
    const coordinatorFailure = await coordinatorRun.completed;
    assert.fail(JSON.stringify({
      applicationExit, coordinatorFailure, terminalStatusDropped,
      applicationProxyFailures,
      interruptedCoordinatorExit,
    }));
  }
  await destinationCompletion;
  const coordinatorExit = await coordinatorRun.completed;
  assert.equal(interruptedCoordinatorExit?.signal, 'SIGKILL');
  assert.equal(
    applicationExit.code,
    0,
    JSON.stringify({applicationExit, coordinatorExit}),
  );
  assert.equal(
    coordinatorExit.code,
    0,
    JSON.stringify({applicationExit, coordinatorExit}),
  );
  assert.equal(terminalStatusDropped, true);
  const applicationEvents = applicationExit.stdout.trim().split('\n')
    .filter(Boolean).map(line => JSON.parse(line));
  assert.deepEqual(
    applicationEvents.map(event => event.kind),
    ['query', 'output-plan', 'output', 'released', 'idle'],
  );
  const coordinatorEvents = coordinatorExit.stdout.trim().split('\n')
    .filter(Boolean).map(line => JSON.parse(line));
  assert.equal(coordinatorEvents.at(-1).kind, 'complete');
  assert.equal(
    coordinatorEvents.at(-1).dispatch_request_cid,
    remoteSiteControl.identity(dispatch),
  );
  assert.ok(coordinatorEvents.at(-1).control_bytes < 3_145_728);
  const reconciled = await runCapturedIn(
    nativeRemoteCoordinator,
    [...coordinatorArguments, '--mode', 'reconcile'],
    {},
    undefined,
    undefined,
  ).completed;
  assert.equal(reconciled.code, 0, reconciled.stderr);
  assert.deepEqual(JSON.parse(reconciled.stdout), {
    kind: 'reconciled',
    dispatch_request_cid: remoteSiteControl.identity(dispatch),
  });

  const reclaimedRun = runCaptured(transferReceiver, [
    ...receiveArguments,
    '--mode', 'reclaim',
  ]);
  const reclaimed = await reclaimedRun.completed;
  assert.equal(reclaimed.code, 0, reclaimed.stderr);
  assert.deepEqual(JSON.parse(reclaimed.stdout), {reclaimed: true});
  assert.deepEqual(await readdir(applicationTransferRoot), []);
  if (applicationOutputRoute === 'store') {
    assert.notEqual(applicationOutputReceiveArguments, undefined);
    const reclaimedOutputRun = runCapturedAtDestination(transferReceiver, [
      ...applicationOutputReceiveArguments,
      '--mode', 'reclaim',
    ]);
    const reclaimedOutput = await reclaimedOutputRun.completed;
    assert.equal(reclaimedOutput.code, 0, reclaimedOutput.stderr);
    assert.deepEqual(JSON.parse(reclaimedOutput.stdout), {reclaimed: true});
    assert.deepEqual(await readdir(applicationOutputTransferRoot), []);
  }
  await stopProductTransferService(productTransferService);
  productTransferService = undefined;
} finally {
  releaseStalePoll?.();
  if (applicationControlProxy !== undefined) {
    applicationControlProxy.close();
    await once(applicationControlProxy, 'close');
  }
  if (productTransferService !== undefined &&
      stopProductTransferService !== undefined) {
    try { await stopProductTransferService(productTransferService); }
    catch (error) { console.error(error); }
  }
  if (standardGateway !== undefined) {
    await standardGateway.close();
  }
  if (bearerServers !== undefined) {
    await bearerServers.close();
  }
  if (server !== undefined) {
    server.close();
    await once(server, 'close');
  }
  if (process.env.ACTQL_TEST_PRESERVE_SCRATCH !== '1') {
    await rm(root, {recursive: true, force: true});
  }
}
