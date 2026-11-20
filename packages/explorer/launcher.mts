import type * as Public from './launcher.js';
import {startExplorerGateway} from './gateway.mjs';
import {loadExplorerAssets} from './assets.mjs';
import {copyExplorerLaunchInput} from './launch-input.mjs';

// The embedding application keeps ownership of this existing SDK Client.
export async function startExplorer({client, ...options}:Parameters<typeof Public.startExplorer>[0]):ReturnType<typeof Public.startExplorer> {
  options = {...options, launchInput: copyExplorerLaunchInput(options.launchInput)};
  return startExplorerGateway({...options, client, assets: await loadExplorerAssets()});
}

// Local is explicit: the existing Node entry owns one Host in this process.
// Store locks and recovery remain with that entry; never fall back on refusal.
export async function openLocalExplorer({local = {}, ...options}:NonNullable<Parameters<typeof Public.openLocalExplorer>[0]> = {}):ReturnType<typeof Public.openLocalExplorer> {
  // Copy/refuse caller presentation input before the first await or Host open.
  options = {...options, launchInput: copyExplorerLaunchInput(options.launchInput)};
  const assets = await loadExplorerAssets();
  const {open} = await import('@actql/node');
  const client = await open(local);
  let gateway:Awaited<ReturnType<typeof startExplorerGateway>>;
  try {gateway = await startExplorerGateway({...options, client, assets});}
  catch (error) {
    try {await client.close();}
    catch (cleanupError) {throw new AggregateError([error, cleanupError], 'ExplorerLocalCleanupPending');}
    throw error;
  }
  let closing:Promise<void>|undefined;
  return Object.freeze({...gateway, local: client.info,
    close() {
      // Retry a failed original close, without opening another Host or Run.
      if (!closing) closing = (async () => {await gateway.close(); await client.close();})()
        .finally(() => {closing = undefined;});
      return closing;
    },
  });
}
