// Explicit build-time composition. Never resolve unused connector declarations
// or rely on tree shaking to remove their initialization and dependencies.
import {fileURLToPath} from 'node:url';
import {readFileSync, writeFileSync, existsSync} from 'node:fs';
import {checkNodeAssembly} from './connector-node-bundles.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
// One canonical authority bridge, linked with the checked Program and Host.
// This is a byte-identical source projection, never a Workers permission model.
const authorization = readFileSync(new URL('../src/connectors_builtin_node/authorization_bridge.mbt', import.meta.url), 'utf8');
const authorizationPath = new URL('../src/connectors_workers_bridge/authorization_bridge.mbt', import.meta.url);
if (process.argv.includes('--write')) writeFileSync(authorizationPath, authorization);
else if (!existsSync(authorizationPath) || readFileSync(authorizationPath, 'utf8') !== authorization) {
  throw new Error('Stale Workers authorization bridge');
}
checkNodeAssembly(root, process.argv.includes('--write'), {
  names:['local'], assembly:'connectors_workers', bridge:'connectors_workers_bridge',
  adapter:'connectors-workers', loading:'static', nativeRemoteStandard:false,
});
console.log('Local-only Workers Compute composition verified.');
checkNodeAssembly(root, process.argv.includes('--write'), {
  names:['reference_compute'], assembly:'connectors_workers_async',
  bridge:'connectors_workers_async_bridge', adapter:'connectors-workers-async',
  loading:'static', nativeRemoteStandard:false,
});
console.log('Independent numeric Workers test composition verified.');
