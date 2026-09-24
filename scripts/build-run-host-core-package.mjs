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
if (process.argv.includes('--check')) {
  if (!readFileSync(destination).equals(bytes)) {
    throw new Error('StaleRunHostCorePackage');
  }
} else {
  mkdirSync(join(root, 'packages/run-host-core/dist'), {recursive: true});
  writeFileSync(destination, bytes);
}
