import {mkdirSync, readFileSync, writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';

import {deferredFunctionRuntime} from './deferred-function-runtime.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const source = join(root, '_build/js/release/build/remote_coordinator_abi',
  'remote_coordinator_abi.js');
const destination = join(root, 'packages/coordinator-core/dist',
  'remote_coordinator_abi.js');
const bytes = deferredFunctionRuntime(source);
if (process.argv.includes('--check')) {
  if (!bytes.equals(readFileSync(destination))) {
    throw new Error('StaleRemoteCoordinatorPackage');
  }
} else {
  mkdirSync(join(root, 'packages/coordinator-core/dist'), {recursive: true});
  writeFileSync(destination, bytes);
}
