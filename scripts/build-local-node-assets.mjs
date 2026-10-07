import {mkdirSync, readFileSync, writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {buildSync} from 'esbuild';
import {localNodePackageInputs} from './local-node-package-inputs.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const bundles = localNodePackageInputs(root).runtimeFiles;
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
