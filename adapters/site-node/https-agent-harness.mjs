// Shared harness for tests against the real HTTPS mTLS Remote Site agent
// (`https-agent-fixture.mjs` in a child process): test certificates, the
// signed runtime bundle, Site configuration and dispatch requests.
import {execFileSync, fork} from 'node:child_process';
import {once} from 'node:events';
import {readFile, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {
  createHash,
  generateKeyPairSync,
  X509Certificate,
} from 'node:crypto';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {queryRemoteDispatch} from '../host-node/remote-site-client.mjs';
import {signRemoteRuntimeBundle} from './remote-bundle-signature.mjs';

const runtime = runtimeCore(moon);
const cid = digit => `sha256:${digit.repeat(64)}`;
const dispatchBudget = runtime.remoteSiteControl.prepareBudget({
  retainedBytes: 64n,
  executionBytes: 16n,
});
const dispatchBudgetCid = runtime.remoteSiteControl.budgetIdentity(
  dispatchBudget,
);

function openssl(root, ...arguments_) {
  execFileSync('openssl', arguments_, {cwd: root, stdio: 'ignore'});
}

function issueCertificate(root, name, subject, extensionFile) {
  openssl(root, 'genrsa', '-out', `${name}.key`, '2048');
  openssl(
    root,
    'req',
    '-new',
    '-key', `${name}.key`,
    '-out', `${name}.csr`,
    '-subj', subject,
  );
  openssl(
    root,
    'x509',
    '-req',
    '-in', `${name}.csr`,
    '-CA', 'ca.crt',
    '-CAkey', 'ca.key',
    '-CAcreateserial',
    '-out', `${name}.crt`,
    '-days', '1',
    ...(extensionFile === undefined ? [] : ['-extfile', extensionFile]),
  );
}

export async function certificates(root) {
  openssl(root, 'genrsa', '-out', 'ca.key', '2048');
  openssl(
    root,
    'req',
    '-x509',
    '-new',
    '-key', 'ca.key',
    '-out', 'ca.crt',
    '-subj', '/CN=ActQL Remote Test CA',
    '-days', '1',
  );
  await writeFile(
    join(root, 'site.ext'),
    'subjectAltName=DNS:localhost,IP:127.0.0.1\n',
  );
  issueCertificate(root, 'site', '/CN=localhost', 'site.ext');
  issueCertificate(root, 'coordinator', '/CN=coordinator-a');
  issueCertificate(root, 'foreign', '/CN=foreign-coordinator');
  const read = name => readFile(join(root, name));
  const coordinatorCertificate = await read('coordinator.crt');
  return Object.freeze({
    ca: await read('ca.crt'),
    siteKey: await read('site.key'),
    siteCertificate: await read('site.crt'),
    coordinatorKey: await read('coordinator.key'),
    coordinatorCertificate,
    coordinatorFingerprint: new X509Certificate(
      coordinatorCertificate,
    ).fingerprint256,
    foreignKey: await read('foreign.key'),
    foreignCertificate: await read('foreign.crt'),
  });
}

export const remoteDispatch = (
  dispatchId = 'dispatch-a',
  revision = 'local/1',
  overrides = {},
) =>
  runtime.remoteSiteControl.prepare(Object.freeze({
    coordinatorAuthority: 'coordinator-a',
    runDefinitionCid: cid('0'),
    taskKey: 'task-a',
    taskAttempt: 1,
    dispatchId,
    siteKey: 'site-a',
    siteGeneration: 1,
    runtimeBundleCid: cid('a'),
    connectorRegistration: 'local',
    connectorRevision: revision,
    strategyRevision: 'strategy/1',
    inputBindingCid:
      'sha256:44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a',
    obligationsCid: cid('2'),
    budgetCid: dispatchBudgetCid,
    evidenceIssuerCapabilityCid: cid('b'),
    grantCid: cid('4'),
    ...overrides,
  }));

// Start the real HTTPS mTLS Remote Site agent fixture in a child process.
// `siteKey` selects the Site; `stats()` reports what the Site process
// itself observed: HTTP requests reaching its server, per endpoint, and
// dispatch runtime starts.
export async function startFixture(
  root,
  material,
  {delayMs = 0, maxConcurrentOperations = 4, siteKey = 'site-a',
    preacceptDispatchId} = {},
) {
  const configurationPath = join(root, `agent-${siteKey}.json`);
  const targetTriple = 'test-native-target';
  const component = Buffer.from('remote-site-runtime-fixture', 'utf8');
  const componentPath = join(root, 'runtime-component');
  const bundlePublicKeyPath = join(root, 'bundle-authority.pem');
  const bundleKeys = generateKeyPairSync('ed25519');
  const bundleManifest = runtime.remoteBundleControl.prepare({
    issuerAuthority: 'bundle-authority-a',
    bundleName: 'remote-site-fixture',
    revision: '1',
    targetTriple,
    componentCid: `sha256:${createHash('sha256')
      .update(component).digest('hex')}`,
    componentBytes: BigInt(component.byteLength),
    connectorRegistration: 'local',
    connectorRevision: 'local/1',
    strategyRevision: 'strategy/1',
  });
  const runtimeBundleCid = runtime.remoteBundleControl.identity(
    bundleManifest,
  );
  const preaccepted = preacceptDispatchId === undefined ? undefined :
    remoteDispatch(preacceptDispatchId, 'local/1', {runtimeBundleCid,
      siteKey});
  const signedBundle = signRemoteRuntimeBundle(
    bundleManifest,
    runtime.remoteBundleControl,
    {keyId: 'key-a', privateKey: bundleKeys.privateKey},
  );
  await Promise.all([
    writeFile(componentPath, component, {mode: 0o600}),
    writeFile(
      bundlePublicKeyPath,
      bundleKeys.publicKey.export({type: 'spki', format: 'pem'}),
      {mode: 0o600},
    ),
  ]);
  await writeFile(configurationPath, JSON.stringify({
    keyPath: join(root, 'site.key'),
    certPath: join(root, 'site.crt'),
    caPath: join(root, 'ca.crt'),
    storeRoot: join(root, siteKey === 'site-a'
      ? 'site-store' : `site-store-${siteKey}`),
    bundle: {
      componentPath,
      expectedComponent: component.toString('utf8'),
      issuerAuthority: 'bundle-authority-a',
      keyId: 'key-a',
      publicKeyPath: bundlePublicKeyPath,
      signed: signedBundle,
      storeRoot: join(root, siteKey === 'site-a'
        ? 'bundle-store' : `bundle-store-${siteKey}`),
      targetTriple,
    },
    coordinatorAuthorities: [
      [material.coordinatorFingerprint, 'coordinator-a'],
    ],
    site: {
      key: siteKey,
      generation: 1,
      runtimeRevision: runtimeBundleCid,
      maxConcurrentOperations,
      maxConcurrentTransfers: 4,
      maxRetainedBytes: '1048576',
      maxExecutionBytes: '1048576',
    },
    runtime: {
      runtimeBundleCid,
      connectorRegistration: 'local',
      connectorRevision: 'local/1',
      strategyRevision: 'strategy/1',
      operationCapabilityCid: cid('4'),
      evidenceKind: runtime.remoteSiteControl.managedOutputEvidenceKind,
      issuerCapabilityCid: cid('b'),
      delayMs,
      output: {
        materialGeneration: 'material-generation-a',
        managedProfileCid: cid('3'),
        measurement: {
          rowCount: 2,
          admissionNodes: 0,
          admissionTextBytes: 0,
          admissionWork: 0,
          columnRows: [2],
          columnBytes: [2],
          columnNodes: [2],
          columnMaxValueBytes: [1],
          columnNullRows: [0],
          columnAdmittedDepths: [10],
        },
        resultSchemaCid: cid('5'),
        logicalViewCid: cid('6'),
        representationCodecCid: cid('7'),
        physicalManifestCid: cid('8'),
        rowCount: 2,
        retainedBytes: '8',
      },
    },
    budgets: [{retainedBytes: '64', executionBytes: '16'}],
    ...(preaccepted === undefined ? {} : {preaccepted: {
      wire: runtime.remoteSiteControl.requestJson(preaccepted),
      cid: runtime.remoteSiteControl.identity(preaccepted),
    }}),
  }), {mode: 0o600});
  const child = fork(
    new URL('./https-agent-fixture.mjs', import.meta.url),
    [configurationPath],
    {stdio: ['ignore', 'ignore', 'pipe', 'ipc']},
  );
  let errors = '';
  let executionStarts = 0;
  child.stderr.setEncoding('utf8');
  child.stderr.on('data', value => { errors += value; });
  const ready = await new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      reject(new Error(`Remote Site fixture timeout: ${errors}`));
    }, 10_000);
    child.once('error', error => {
      clearTimeout(timeout);
      reject(error);
    });
    child.on('message', message => {
      if (message?.type === 'execution-started') executionStarts++;
      if (message?.type === 'ready') {
        clearTimeout(timeout);
        resolve(message);
      }
    });
    child.once('exit', code => {
      clearTimeout(timeout);
      reject(new Error(`Remote Site fixture exited ${code}: ${errors}`));
    });
  });
  return Object.freeze({
    origin: `https://127.0.0.1:${ready.port}`,
    child,
    runtimeBundleCid,
    siteKey,
    storeRoot: join(root, siteKey === 'site-a'
      ? 'site-store' : `site-store-${siteKey}`),
    dispatch(dispatchId = 'dispatch-a', revision = 'local/1', overrides = {}) {
      return remoteDispatch(dispatchId, revision, {
        runtimeBundleCid,
        siteKey,
        ...overrides,
      });
    },
    stats() {
      return new Promise((resolve, reject) => {
        const onMessage = message => {
          if (message?.type !== 'site-stats') return;
          child.off('message', onMessage);
          resolve(message.stats);
        };
        child.on('message', onMessage);
        child.send({type: 'site-stats'}, error => {
          if (error === null || error === undefined) return;
          child.off('message', onMessage);
          reject(error);
        });
      });
    },
    executionStarts: () => executionStarts,
    stopAdmission() {
      return new Promise((resolve, reject) => {
        const onMessage = message => {
          if (message?.type !== 'admission-stopped') return;
          child.off('message', onMessage);
          resolve(message.changed);
        };
        child.on('message', onMessage);
        child.send({type: 'stop-admission'}, error => {
          if (error === null || error === undefined) return;
          child.off('message', onMessage);
          reject(error);
        });
      });
    },
    async close() {
      if (child.exitCode !== null) return;
      child.send({type: 'close'});
      await once(child, 'exit');
    },
  });
}

export async function terminalStatus(options, query = queryRemoteDispatch) {
  for (let attempt = 0; attempt < 100; attempt++) {
    const status = await query(options);
    // ExecutionUnknown is a reconciliation obligation, not a terminal fact.
    if (status.state[0] >= 3 && status.state[0] !== 6) return status;
    await new Promise(resolve => setTimeout(resolve, 5));
  }
  throw new Error('Remote dispatch did not reach terminal state');
}
