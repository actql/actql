import {readFile} from 'node:fs/promises';
import https from 'node:https';
import process from 'node:process';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {admitRemoteDispatchJson} from
  '../host-common/remote-dispatch-wire.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {startHttpsRemoteSiteAgent} from './https-agent.mjs';
import {
  createRemoteDispatchRuntime,
  prepareInstalledRemoteRuntimeRegistration,
} from
  './remote-dispatch-runtime.mjs';
import {openSqliteDispatchJournal} from './sqlite-dispatch-journal.mjs';
import {openRuntimeBundleStore} from './runtime-bundle-store.mjs';

const configurationPath = process.argv[2];
if (typeof configurationPath !== 'string') {
  throw new Error('Missing Remote Site fixture configuration');
}
const configuration = JSON.parse(await readFile(configurationPath, 'utf8'));

// Site-side observation for tests: every HTTP request that reaches this
// process's HTTPS server (after the TLS handshake, before any routing or
// admission), keyed by path suffix, and every dispatch runtime start.
const stats = {requests: {}, runtimeStarts: 0};
const emit = https.Server.prototype.emit;
https.Server.prototype.emit = function countRequest(event, request, ...rest) {
  if (event === 'request') {
    const operation = /\/dispatches(?:\/([a-z]+))?$/.exec(request.url ?? '')
      ?.[1] ?? (request.url?.endsWith('/dispatches') ? 'dispatch' : 'other');
    stats.requests[operation] = (stats.requests[operation] ?? 0) + 1;
  }
  return emit.call(this, event, request, ...rest);
};
const [key, cert, ca] = await Promise.all([
  readFile(configuration.keyPath),
  readFile(configuration.certPath),
  readFile(configuration.caPath),
]);
const runtime = runtimeCore(moon);
const bundlePublicKey = await readFile(configuration.bundle.publicKeyPath);
const bundleStore = await openRuntimeBundleStore(
  configuration.bundle.storeRoot,
  {
    bundleAuthorities: new Map([[
      configuration.bundle.issuerAuthority,
      new Map([[configuration.bundle.keyId, bundlePublicKey]]),
    ]]),
    targetTriple: configuration.bundle.targetTriple,
  },
);
await bundleStore.install(
  configuration.bundle.componentPath,
  configuration.bundle.signed,
  runtime.remoteBundleControl,
);
bundleStore.activate(
  configuration.runtime.runtimeBundleCid,
  runtime.remoteBundleControl,
);
const siteConfiguration = Object.freeze({
  ...configuration.site,
  maxRetainedBytes: BigInt(configuration.site.maxRetainedBytes),
  maxExecutionBytes: BigInt(configuration.site.maxExecutionBytes),
});
const site = runtime.siteControl.create(siteConfiguration);
const journal = runtime.remoteSiteControl.createJournal(site);
const store = openSqliteDispatchJournal(configuration.storeRoot, {
  siteKey: configuration.site.key,
  siteGeneration: configuration.site.generation,
  runtimeRevision: configuration.site.runtimeRevision,
});
const registration = await prepareInstalledRemoteRuntimeRegistration({
  control: runtime.remoteSiteControl,
  site,
  bundleStore,
  bundleControl: runtime.remoteBundleControl,
  ...configuration.runtime,
  async load(bundle) {
    const component = await readFile(bundle.artifactPath, 'utf8');
    if (component !== configuration.bundle.expectedComponent) {
      throw new Error('Remote fixture loaded an unexpected bundle');
    }
    return async ({signal}) => {
      process.send?.({type: 'execution-started'});
      if (configuration.runtime.delayMs > 0) {
        await new Promise((resolve, reject) => {
          const abort = () => {
            clearTimeout(timer);
            // Clearing this timer ends the fixture's only physical work.
            // A rejected Promise alone does not certify native stop.
            reject(Object.assign(new Error('Fixture execution stopped'), {
              cleanupHandle: {
                status: () => ({pending: false, errors: []}),
              },
            }));
          };
          const timer = setTimeout(() => {
            signal.removeEventListener('abort', abort);
            resolve();
          }, configuration.runtime.delayMs);
          signal.addEventListener('abort', abort, {once: true});
        });
      }
      return Object.freeze({
        ...configuration.runtime.output,
        retainedBytes: BigInt(configuration.runtime.output.retainedBytes),
        async close() {},
      });
    };
  },
});
const budgets = configuration.budgets.map(budget =>
  runtime.remoteSiteControl.prepareBudget({
    retainedBytes: BigInt(budget.retainedBytes),
    executionBytes: BigInt(budget.executionBytes),
  }));
const createdRuntime = createRemoteDispatchRuntime({
  control: runtime.remoteSiteControl,
  siteControl: runtime.siteControl,
  store,
  bundleStore,
  bundleControl: runtime.remoteBundleControl,
  registrations: [registration],
  budgets,
});
const dispatchRuntime = Object.freeze({
  ...createdRuntime,
  start(...arguments_) {
    stats.runtimeStarts++;
    return createdRuntime.start(...arguments_);
  },
});
const agent = await startHttpsRemoteSiteAgent({
  key,
  cert,
  ca,
  coordinatorAuthorities: new Map(configuration.coordinatorAuthorities),
  siteKey: configuration.site.key,
  siteGeneration: configuration.site.generation,
  journal,
  store,
  control: runtime.remoteSiteControl,
  admitDispatchJson: admitRemoteDispatchJson,
  dispatchRuntime,
});

process.send?.({type: 'ready', port: agent.port});

let closing = false;
async function close() {
  if (closing) return;
  closing = true;
  try {
    await agent.close();
    bundleStore.close();
    store.close();
    process.send?.({type: 'closed'});
    process.exitCode = 0;
    process.disconnect?.();
  } catch (error) {
    process.send?.({type: 'failed', error: error?.code ?? error?.message});
    process.exitCode = 1;
    process.disconnect?.();
  }
}

process.on('message', message => {
  if (message?.type === 'site-stats') {
    process.send?.({type: 'site-stats', stats: structuredClone(stats)});
    return;
  }
  if (message?.type === 'stop-admission') {
    process.send?.({
      type: 'admission-stopped',
      changed: agent.stopAdmission(),
    });
    return;
  }
  if (message?.type === 'close') void close();
});
process.on('SIGTERM', () => void close());
