import {mkdirSync, readFileSync, writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {buildSync} from 'esbuild';

const root = fileURLToPath(new URL('../', import.meta.url));
const source = join(root, '_build/js/release/build/client_values_host_abi',
  'client_values_host_abi.js');
const destination = join(root, 'packages/run-host-core/dist',
  'client_values_host_abi.js');
const result = buildSync({entryPoints: [source], bundle: true, minify: true,
  write: false, format: 'esm', platform: 'neutral', target: 'es2022'});
const bytes = result.outputFiles[0].contents;
const accessSource = readFileSync(join(root, 'adapters/host-common',
  'result-access.mjs'), 'utf8');
const access = accessSource.replace(
  "'../../packages/client-wire/index.mjs'", "'@actql/client-wire'");
if (access === accessSource) {
  throw new Error('RunHostResultAccessImportChanged');
}
const delivery = readFileSync(join(root, 'adapters/host-common',
  'result-delivery.mjs'));
const accessFile = join(root, 'packages/run-host-core',
  'result-access.mjs');
const deliveryFile = join(root, 'packages/run-host-core',
  'result-delivery.mjs');
if (process.argv.includes('--check')) {
  if (!readFileSync(destination).equals(bytes)) {
    throw new Error('StaleRunHostCorePackage');
  }
  if (readFileSync(accessFile, 'utf8') !== access ||
      !readFileSync(deliveryFile).equals(delivery)) {
    throw new Error('StaleRunHostResultAccessService');
  }
} else {
  mkdirSync(join(root, 'packages/run-host-core/dist'), {recursive: true});
  writeFileSync(destination, bytes);
  if (!process.argv.includes('--runtime-only')) {
    writeFileSync(accessFile, access);
    writeFileSync(deliveryFile, delivery);
  }
}
