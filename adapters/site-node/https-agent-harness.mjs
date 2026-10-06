// Shared harness for tests against the real HTTPS mTLS Remote Site agent
// (`https-agent-fixture.mjs` in a child process): test certificates, the
// signed runtime bundle, Site configuration and dispatch requests.
import {fork} from 'node:child_process';
import {once} from 'node:events';
import {writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {
  createHash,
  generateKeyPairSync,
} from 'node:crypto';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {queryRemoteDispatch} from '../host-node/remote-site-client.mjs';
import {signRemoteRuntimeBundle} from './remote-bundle-signature.mjs';
export {certificates} from './https-test-certificates.mjs';

const runtime = runtimeCore(moon);
const cid = digit => `sha256:${digit.repeat(64)}`;
const dispatchBudget = runtime.remoteSiteControl.prepareBudget({
  retainedBytes: 64n,
  executionBytes: 16n,
});
const dispatchBudgetCid = runtime.remoteSiteControl.budgetIdentity(
  dispatchBudget,
);

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
    preacceptDispatchId, holdCancellationExit = false} = {},
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
      holdCancellationExit,
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
  let executionStopsPending = 0;
  child.stderr.setEncoding('utf8');
  child.stderr.on('data', value => { errors += value; });
  const waitForObservation = (count, expected, label) => {
    if (count() >= expected) return Promise.resolve();
    if (child.exitCode !== null) {
      return Promise.reject(new Error(
        `Remote Site fixture exited before ${label}: ${errors}`,
      ));
    }
    return new Promise((resolve, reject) => {
      let settled = false;
      const finish = error => {
        if (settled) return;
        settled = true;
        clearTimeout(timeout);
        child.off('message', onMessage);
        child.off('exit', onExit);
        if (error === undefined) resolve();
        else reject(error);
      };
      const onMessage = () => {
        if (count() >= expected) finish();
      };
      const onExit = code => finish(
        new Error(`Remote Site fixture exited ${code} before ${label}: ${errors}`),
      );
      const timeout = setTimeout(() => finish(
        new Error(`Remote Site fixture did not report ${label}: ${errors}`),
      ), 10_000);
      child.on('message', onMessage);
      child.once('exit', onExit);
    });
  };
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
      if (message?.type === 'execution-stop-pending') executionStopsPending++;
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
    waitForExecutionStarts: (expected = 1) => waitForObservation(
      () => executionStarts, expected, 'execution start',
    ),
    waitForExecutionStopPending: (expected = 1) => waitForObservation(
      () => executionStopsPending, expected, 'pending physical stop',
    ),
    releaseExecutionStop() {
      if (child.exitCode !== null) return Promise.resolve(false);
      return new Promise((resolve, reject) => {
        let settled = false;
        const finish = (error, released) => {
          if (settled) return;
          settled = true;
          clearTimeout(timeout);
          child.off('message', onMessage);
          child.off('exit', onExit);
          if (error === undefined) resolve(released);
          else reject(error);
        };
        const onMessage = message => {
          if (message?.type !== 'execution-stop-released') return;
          finish(undefined, message.released);
        };
        const onExit = code => finish(new Error(
          `Remote Site fixture exited ${code} before stop release: ${errors}`,
        ));
        const timeout = setTimeout(() => finish(new Error(
          `Remote Site fixture did not release physical stop: ${errors}`,
        )), 10_000);
        child.on('message', onMessage);
        child.once('exit', onExit);
        child.send({type: 'release-execution-stop'}, error => {
          if (error === null || error === undefined) return;
          finish(error);
        });
      });
    },
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
