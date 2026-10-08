import {mkdirSync, readFileSync, writeFileSync} from 'node:fs';
import {join, relative, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {buildSync} from 'esbuild';
import {localNodePackageInputs} from './local-node-package-inputs.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));

export function buildLocalNodeAssets({root = repository, inputs = localNodePackageInputs(root),
  destination = join(root, 'packages/local-node'), compiledDirectory, check = false} = {}) {
  const external = inputs.buildInputs;
  const files = external === undefined ? inputs.runtimeFiles.map(name => ({name,
    source: join(root, '_build/js/release/build', name)})) : inputs.runtimeInputs.map(entry => ({
    name: entry.file, source: join(compiledDirectory, 'js/release/build', entry.compiledFile)}));
  const packageRoot = join(destination, '_build/js/release/build');
  if (external !== undefined) {
    for (const {name, source} of files) {
      external.outputPath(relative(external.host.root, source));
      external.outputPath(relative(external.host.root, join(packageRoot, name)));
    }
  }
  for (const {name, source} of files) {
  const built = buildSync({entryPoints: [source],
    bundle: true, minify: true, write: false, format: 'esm',
    platform: 'node', target: 'node22'}).outputFiles[0].contents;
  const destination = join(packageRoot, name);
  if (check) {
    if (!readFileSync(destination).equals(built)) {
      throw new Error(`StaleLocalNodeAsset:${name}`);
    }
  } else {
    mkdirSync(join(destination, '..'), {recursive: true});
    writeFileSync(destination, built);
  }
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  buildLocalNodeAssets({check: process.argv.includes('--check')});
}
