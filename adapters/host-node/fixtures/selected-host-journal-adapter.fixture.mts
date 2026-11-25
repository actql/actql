import {createRequire, Module} from 'node:module';

type Adapter = typeof import('../node-host-journal-installation.mjs');

// Load the real adapter. The fixture supplies only its selected startup
// table, captured before the temporary module cache and entry flags unwind.
let adapterLoads = 0;
export async function loadSelectedJournalAdapter(owner: object): Promise<Adapter> {
  const require = createRequire(import.meta.url);
  const path = require.resolve('../infer-trusted-node-preload.cjs');
  const previous = require.cache[path];
  const originalExecArgv = process.execArgv;
  const preload = new Module(path);
  preload.filename = path;
  preload.loaded = true;
  preload.exports = owner;
  const url = new URL('../node-host-journal-installation.mjs', import.meta.url);
  url.searchParams.set('selectedFixture', String(++adapterLoads));
  require.cache[path] = preload;
  process.execArgv = [...originalExecArgv, '@actql/node/selected-infer-startup'];
  try {
    return await import(url.href);
  } finally {
    process.execArgv = originalExecArgv;
    if (previous === undefined) delete require.cache[path];
    else require.cache[path] = previous;
  }
}
