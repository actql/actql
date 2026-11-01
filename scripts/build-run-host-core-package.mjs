import {mkdirSync, readFileSync, writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {deferredFunctionRuntime} from './deferred-function-runtime.mjs';
import {prepareProductionRuntimeModule} from '../adapters/workers/moon-runtime.mjs';
import {buildFiniteRuntime} from '../adapters/workers/build.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const source = join(root, '_build/js/release/build/client_values_host_abi',
  'client_values_host_abi.js');
const destination = join(root, 'packages/run-host-core/dist',
  'client_values_host_abi.js');
const bytes = deferredFunctionRuntime(source, {minify: true});
// Reuse the existing storage-free Checkpoint bridge. The package does not
// supply a clock, reviewer authority, persistence or another lifecycle Owner.
const checkpointDestination = join(root, 'packages/run-host-core/dist',
  'checkpoint_runtime_node.js');
const checkpointBytes = deferredFunctionRuntime(join(root,
  '_build/js/release/build/checkpoint_runtime_node/checkpoint_runtime_node.js'),
{minify: true});
prepareProductionRuntimeModule();
const finiteDestination = join(root, 'packages/run-host-core/dist',
  'workers_finite.js');
const finiteBytes = Buffer.from((await buildFiniteRuntime()).source);
const finitePayloadDestination = join(root, 'packages/run-host-core/dist',
  'workers_finite_payload.js');
// The existing runtime_executable component binds the exact audited payload.
// Keep the descriptor outside that payload so its digest is not circular.
const finiteMetadata = {componentCid: `sha256:${createHash('sha256')
  .update(finiteBytes).digest('hex')}`, componentBytes: finiteBytes.length};
const finiteEntryBytes = Buffer.from(
  "export {createWorkersFiniteRuntime} from './workers_finite_payload.js';\n" +
  `export const workersFiniteArtifact = Object.freeze(${JSON.stringify(finiteMetadata)});\n`);
const accessSource = readFileSync(join(root, 'adapters/host-common',
  'result-access.mjs'), 'utf8');
const access = accessSource.replace(
  "'../../packages/client-wire/index.mjs'", "'@actql/client-wire'");
if (access === accessSource) {
  throw new Error('RunHostResultAccessImportChanged');
}
const delivery = readFileSync(join(root, 'adapters/host-common',
  'result-delivery.mjs'));
const action = readFileSync(join(root, 'adapters/host-common',
  'publication-action.mjs'));
const failure = readFileSync(join(root, 'adapters/host-common',
  'managed-failure.mjs'));
const accessFile = join(root, 'packages/run-host-core',
  'result-access.mjs');
const deliveryFile = join(root, 'packages/run-host-core',
  'result-delivery.mjs');
const actionFile = join(root, 'packages/run-host-core',
  'publication-action.mjs');
const failureFile = join(root, 'packages/run-host-core',
  'managed-failure.mjs');
if (process.argv.includes('--check')) {
  if (!readFileSync(destination).equals(bytes)) {
    throw new Error('StaleRunHostCorePackage');
  }
  if (!readFileSync(checkpointDestination).equals(checkpointBytes)) {
    throw new Error('StaleRunHostCheckpointPackage');
  }
  if (!readFileSync(finiteDestination).equals(finiteEntryBytes) ||
      !readFileSync(finitePayloadDestination).equals(finiteBytes)) {
    throw new Error('StaleRunHostWorkersFinitePackage');
  }
  if (readFileSync(accessFile, 'utf8') !== access ||
      !readFileSync(deliveryFile).equals(delivery) ||
      !readFileSync(actionFile).equals(action) ||
      !readFileSync(failureFile).equals(failure)) {
    throw new Error('StaleRunHostResultAccessService');
  }
} else {
  mkdirSync(join(root, 'packages/run-host-core/dist'), {recursive: true});
  writeFileSync(destination, bytes);
  writeFileSync(checkpointDestination, checkpointBytes);
  writeFileSync(finiteDestination, finiteEntryBytes);
  writeFileSync(finitePayloadDestination, finiteBytes);
  if (!process.argv.includes('--runtime-only')) {
    writeFileSync(accessFile, access);
    writeFileSync(deliveryFile, delivery);
    writeFileSync(actionFile, action);
    writeFileSync(failureFile, failure);
  }
}
