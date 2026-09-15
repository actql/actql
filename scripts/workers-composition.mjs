// Explicit build-time composition. Never resolve unused connector declarations
// or rely on tree shaking to remove their initialization and dependencies.
import {fileURLToPath} from 'node:url';
import {checkComputeAssembly} from './connector-compute-bundles.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
checkComputeAssembly(root, process.argv.includes('--write'), {
  names:['local'], directory:'connectors_workers',
});
console.log('Local-only Workers Compute composition verified.');
