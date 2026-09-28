import {mkdirSync, readFileSync, readdirSync, writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {buildSync} from 'esbuild';

const root = fileURLToPath(new URL('../', import.meta.url));
const destination = join(root, 'packages/local-node');
const entries = [
  'adapters/host-node/entry.mjs',
  'adapters/host-node/embedded-local.mjs',
  'adapters/host-node/captured-duckdb-source.mjs',
  'adapters/host-node/installed-source.mjs',
  'adapters/connectors/salesforce/host/installed-salesforce-source.mjs',
  'adapters/host-node/local-account-config.mjs',
  'adapters/host-node/in-process-client.mjs',
  'adapters/host-node/client-request-journal.mjs',
  'adapters/host-node/client-request-lookup.mjs',
  'adapters/host-node/client-run-start.mjs',
  'adapters/host-node/client-effect-run.mjs',
  'adapters/host-node/installed-effect-site.mjs',
  'adapters/host-node/client-run-attach.mjs',
  'adapters/host-node/client-program-preparation.mjs',
  'adapters/host-node/result-access.mjs',
  'adapters/host-common/run-state-access.mjs',
  'adapters/store-local/publication-store.mjs',
];
const graph = buildSync({entryPoints: entries, bundle: true,
  packages: 'external', platform: 'node', format: 'esm', target: 'node22',
  metafile: true, write: false, absWorkingDir: root,
  outdir: join(root, '_build/local-node-adapter-graph')});
const sourcePaths = Object.keys(graph.metafile.inputs)
  .filter(path => path.startsWith('adapters/')).sort();
if (sourcePaths.length < entries.length ||
    entries.some(path => !sourcePaths.includes(path))) {
  throw new Error('IncompleteLocalNodeAdapterGraph');
}
const replacements = new Map([
  ["'../../packages/client-wire/index.mjs'", "'@actql/client-wire'"],
  ["'../../packages/sdk/index.mjs'", "'@actql/sdk'"],
  ["'../../packages/sdk/host-port.mjs'", "'@actql/sdk/host-port'"],
  ["'../../packages/run-host-core/index.mjs'", "'@actql/run-host-core'"],
]);
const expected = new Set();
for (const path of sourcePaths) {
  const output = join(destination, path);
  let bytes = readFileSync(join(root, path));
  if (path.endsWith('.mjs')) {
    let code = bytes.toString('utf8');
    for (const [source, target] of replacements) {
      code = code.replaceAll(source, target);
    }
    if (code.includes("'../../packages/")) {
      throw new Error(`UnpackagedLocalNodeImport:${path}`);
    }
    bytes = Buffer.from(code);
  }
  expected.add(path);
  if (process.argv.includes('--check')) {
    if (!readFileSync(output).equals(bytes)) {
      throw new Error(`StaleLocalNodeAdapter:${path}`);
    }
  } else {
    mkdirSync(join(output, '..'), {recursive: true});
    writeFileSync(output, bytes);
  }
}
const walk = (directory, prefix = '') => {
  for (const entry of readdirSync(directory, {withFileTypes: true})) {
    const path = prefix ? `${prefix}/${entry.name}` : entry.name;
    if (entry.isDirectory()) walk(join(directory, entry.name), path);
    else if (!expected.has(`adapters/${path}`)) {
      throw new Error(`StaleLocalNodeAdapter:${path}`);
    }
  }
};
walk(join(destination, 'adapters'));
for (const path of [
  'spec/dependencies/aoa-pipeline-registry.json',
  'spec/contracts/actql-aoa.json',
  'spec/local-check-environment.json',
  'spec/contracts/actql-query-acquisition.json',
  'spec/contracts/actql-query-process-evidence.json',
  'spec/contracts/actql-query-two-receipt.json',
]) {
  const bytes = readFileSync(join(root, path));
  const output = join(destination, path);
  if (process.argv.includes('--check')) {
    if (!readFileSync(output).equals(bytes)) {
      throw new Error(`StaleLocalNodeContract:${path}`);
    }
  } else {
    mkdirSync(join(output, '..'), {recursive: true});
    writeFileSync(output, bytes);
  }
}
