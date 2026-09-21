import {readFile, writeFile} from 'node:fs/promises';
import {X509Certificate} from 'node:crypto';
import * as moon from
  '../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../adapters/host-common/runtime-core.mjs';
import {createLocalRetainedStore} from
  '../adapters/store-local/files.mjs';
import {openLocalPublicationStore} from
  '../adapters/store-local/publication-store.mjs';
import {startHttpsDirectTransferReceiver} from
  '../adapters/site-node/https-direct-transfer.mjs';
import {startHttpsTransferObjectStore} from
  '../adapters/site-node/https-transfer-store.mjs';
import {openSqliteTransferJournal} from
  '../adapters/site-node/sqlite-transfer-journal.mjs';
import {openSqliteTransferStoreJournal} from
  '../adapters/site-node/sqlite-transfer-store-journal.mjs';

const configurationPath = process.argv[2];
if (typeof configurationPath !== 'string') {
  throw new Error('transfer service configuration is required');
}
const configuration = JSON.parse(await readFile(configurationPath, 'utf8'));
const control = runtimeCore(moon).remoteTransferControl;
const publicationControl = runtimeCore(moon).publicationControl;
const certificate = path => readFile(path);
const fingerprint = async path =>
  new X509Certificate(await certificate(path)).fingerprint256;
const peer = async ({certificatePath, siteKey, siteGeneration}) => [
  await fingerprint(certificatePath),
  Object.freeze({siteKey, siteGeneration}),
];
const maximumBytes = BigInt(configuration.maxBytes);
const common = {
  host: configuration.host,
  port: configuration.port,
  key: await certificate(configuration.keyPath),
  cert: await certificate(configuration.certificatePath),
  ca: await certificate(configuration.caPath),
  maxManifestBytes: configuration.maxManifestBytes,
  maxChunks: configuration.maxChunks,
  maxReferencedBytes: maximumBytes,
  maxFrameBytes: configuration.maxFrameBytes,
};
let service;
let closeResources;
if (configuration.mode === 'direct') {
  const requests = new Set();
  const store = await createLocalRetainedStore({
    parentDirectory: configuration.root,
    capacityBytes: configuration.maxBytes,
    maxFrameBytes: configuration.maxFrameBytes,
    maxEntries: configuration.maxObjects,
    maxReadersPerBody: 2,
  });
  const journal = openSqliteTransferJournal(configuration.journalPath, {
    destinationSiteKey: configuration.destinationSiteKey,
    destinationSiteGeneration: configuration.destinationSiteGeneration,
    maxChunks: configuration.maxChunks,
    maxManifestBytes: configuration.maxManifestBytes,
    maxReferencedBytes: maximumBytes,
  });
  service = await startHttpsDirectTransferReceiver({
    ...common,
    sourceAuthorities: new Map([
      await peer(configuration.sourceAuthority),
    ]),
    destinationSiteKey: configuration.destinationSiteKey,
    destinationSiteGeneration: configuration.destinationSiteGeneration,
    control,
    journal,
    store,
    authorize: ({request, peer: authority}) => {
      const projection = control.requestProjection(request);
      const accepted = authority.sourceSite === projection[2] &&
        authority.sourceSiteGeneration === Number(projection[3]) &&
        projection[4] === configuration.destinationSiteKey &&
        Number(projection[5]) === configuration.destinationSiteGeneration;
      if (accepted) requests.add(control.identity(request));
      return accepted;
    },
    maxControlBytes: configuration.maxControlBytes,
  });
  closeResources = async () => {
    for (const requestCid of requests) {
      try { await service.release(requestCid); }
      catch {}
    }
    await service.close();
    journal.close();
    store.close();
    await store.cleanup();
  };
} else if (configuration.mode === 'store') {
  const store = await openLocalPublicationStore({
    directory: configuration.root,
    storeAuthorityCid: configuration.storeAuthorityCid,
    capacityBytes: configuration.maxBytes,
    maxObjectBytes: configuration.maxBytes,
    maxObjects: configuration.maxObjects,
    maxContractNodes: 4096,
    maxContractDepth: 64,
  }, publicationControl);
  const useJournal = openSqliteTransferStoreJournal(
    configuration.journalPath,
    {
      maxChunks: configuration.maxChunks,
      maxManifestBytes: configuration.maxManifestBytes,
      maxReferencedBytes: maximumBytes,
    },
  );
  const authorities = await Promise.all([
    peer(configuration.sourceAuthority),
    peer(configuration.destinationAuthority),
  ]);
  service = await startHttpsTransferObjectStore({
    ...common,
    peerAuthorities: new Map(authorities),
    control,
    store,
    useJournal,
    authorize: ({request, peer: authority, phase}) => {
      const projection = control.requestProjection(request);
      if (phase.startsWith('upload:')) {
        return authority.siteKey === projection[2] &&
          authority.siteGeneration === Number(projection[3]);
      }
      return authority.siteKey === projection[4] &&
        authority.siteGeneration === Number(projection[5]);
    },
    observe: event => {
      if (event.kind !== 'upload-commit-replied' ||
          configuration.uploadRepliedPath === undefined) return;
      return writeFile(
        configuration.uploadRepliedPath,
        JSON.stringify({uploadReplied: true}),
        {flag: 'w'},
      );
    },
  });
  closeResources = async () => {
    await service.close();
    useJournal.close();
    await store.close();
  };
} else {
  throw new Error('unsupported transfer service mode');
}

await writeFile(configuration.readyPath, JSON.stringify({
  origin: service.origin,
  mode: configuration.mode,
}), {flag: 'wx'});

let closing = false;
const close = async signal => {
  if (closing) return;
  closing = true;
  try {
    await closeResources();
    process.exitCode = 0;
  } catch (error) {
    console.error(error);
    process.exitCode = 1;
  } finally {
    if (signal !== undefined) process.exit();
  }
};
process.once('SIGINT', () => { void close('SIGINT'); });
process.once('SIGTERM', () => { void close('SIGTERM'); });
await new Promise(() => {});
