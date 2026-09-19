import {readFile} from 'node:fs/promises';
import process from 'node:process';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {admitRemoteDispatchJson} from
  '../host-common/remote-dispatch-wire.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {startHttpsRemoteSiteAgent} from './https-agent.mjs';
import {createRemoteDispatchRuntime, prepareRemoteRuntimeRegistration} from
  './remote-dispatch-runtime.mjs';
import {openSqliteDispatchJournal} from './sqlite-dispatch-journal.mjs';

const configurationPath = process.argv[2];
if (typeof configurationPath !== 'string') {
  throw new Error('Missing Remote Site fixture configuration');
}
const configuration = JSON.parse(await readFile(configurationPath, 'utf8'));
const [key, cert, ca] = await Promise.all([
  readFile(configuration.keyPath),
  readFile(configuration.certPath),
  readFile(configuration.caPath),
]);
const runtime = runtimeCore(moon);
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
const registration = prepareRemoteRuntimeRegistration({
  control: runtime.remoteSiteControl,
  site,
  ...configuration.runtime,
  execute: async () => Object.freeze({
    ...configuration.runtime.output,
    retainedBytes: BigInt(configuration.runtime.output.retainedBytes),
    async close() {},
  }),
});
const budgets = configuration.budgets.map(budget =>
  runtime.remoteSiteControl.prepareBudget({
    retainedBytes: BigInt(budget.retainedBytes),
    executionBytes: BigInt(budget.executionBytes),
  }));
const dispatchRuntime = createRemoteDispatchRuntime({
  control: runtime.remoteSiteControl,
  siteControl: runtime.siteControl,
  store,
  registrations: [registration],
  budgets,
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
  if (message?.type === 'close') void close();
});
process.on('SIGTERM', () => void close());
