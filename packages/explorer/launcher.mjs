import {startExplorerGateway} from './gateway.mjs';
import {loadExplorerAssets} from './assets.mjs';

// The embedding application keeps ownership of this existing SDK Client.
export async function startExplorer({client, ...options}) {
  return startExplorerGateway({...options, client, assets: await loadExplorerAssets()});
}

// Local is explicit: the existing Node entry owns one Host in this process.
// Store locks and recovery remain with that entry; never fall back on refusal.
export async function openLocalExplorer({local = {}, ...options} = {}) {
  const assets = await loadExplorerAssets();
  const {open} = await import('@actql/node');
  const client = await open(local);
  let gateway;
  try {gateway = await startExplorerGateway({...options, client, assets});}
  catch (error) {
    try {await client.close();}
    catch (cleanupError) {throw new AggregateError([error, cleanupError], 'ExplorerLocalCleanupPending');}
    throw error;
  }
  let closing;
  return Object.freeze({...gateway, local: client.info,
    close() {
      // Retry a failed original close, without opening another Host or Run.
      if (!closing) closing = (async () => {await gateway.close(); await client.close();})()
        .finally(() => {closing = undefined;});
      return closing;
    },
  });
}
