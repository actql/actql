// Explicit build-time composition. Never resolve unused connector declarations
// or rely on tree shaking to remove their initialization and dependencies.
import {fileURLToPath} from 'node:url';
import {checkNodeAssembly} from './connector-node-bundles.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
checkNodeAssembly(root, process.argv.includes('--write'), {
  names:['local'], assembly:'connectors_workers', bridge:'connectors_workers_bridge',
  adapter:'connectors-workers',
});
console.log('Local-only Workers Compute composition verified.');
