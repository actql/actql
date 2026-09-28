import {mkdirSync, readFileSync, writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {buildSync} from 'esbuild';

const root = fileURLToPath(new URL('../', import.meta.url));
const bundles = [
  'connectors_builtin_node/connectors_builtin_node.js',
  'connectors/duckdb/host_node/host_node.js',
  // The Salesforce Site's provider runtime, loaded only for an installed
  // Salesforce source.
  'connectors/salesforce/host_node/host_node.js',
  'retained_host_bridge/retained_host_bridge.js',
  'process_host_bridge/process_host_bridge.js',
  // The Checkpoint journal runtime of the Remote Host's Run-acceptance
  // protection (not part of the light @actql/sdk).
  'checkpoint_runtime_node/checkpoint_runtime_node.js',
];
const buildRoot = join(root, '_build/js/release/build');
const packageRoot = join(root, 'packages/local-node/_build/js/release/build');
for (const name of bundles) {
  const built = buildSync({entryPoints: [join(buildRoot, name)],
    bundle: true, minify: true, write: false, format: 'esm',
    platform: 'node', target: 'node22'}).outputFiles[0].contents;
  const destination = join(packageRoot, name);
  if (process.argv.includes('--check')) {
    if (!readFileSync(destination).equals(built)) {
      throw new Error(`StaleLocalNodeAsset:${name}`);
    }
  } else {
    mkdirSync(join(destination, '..'), {recursive: true});
    writeFileSync(destination, built);
  }
}
