import {copyFileSync, mkdirSync, readFileSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const source = join(root, '_build/js/release/build/remote_transfer_abi',
  'remote_transfer_abi.js');
const destination = join(root, 'packages/transfer-core/dist',
  'remote_transfer_abi.js');
if (process.argv.includes('--check')) {
  if (!readFileSync(source).equals(readFileSync(destination))) {
    throw new Error('StaleRemoteTransferPackage');
  }
} else {
  mkdirSync(join(root, 'packages/transfer-core/dist'), {recursive: true});
  copyFileSync(source, destination);
}
