import {mkdirSync, readFileSync, writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';

import {deferredFunctionRuntime} from './deferred-function-runtime.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const source = join(root, '_build/js/release/build/remote_transfer_abi',
  'remote_transfer_abi.js');
const destination = join(root, 'packages/transfer-core/dist',
  'remote_transfer_abi.js');
const bytes = deferredFunctionRuntime(source);
if (process.argv.includes('--check')) {
  if (!bytes.equals(readFileSync(destination))) {
    throw new Error('StaleRemoteTransferPackage');
  }
} else {
  mkdirSync(join(root, 'packages/transfer-core/dist'), {recursive: true});
  writeFileSync(destination, bytes);
}
