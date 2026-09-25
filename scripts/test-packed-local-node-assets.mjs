import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdir, mkdtemp, readFile, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';

const repository = fileURLToPath(new URL('../', import.meta.url));
const build = join(repository, '_build');
await mkdir(build, {recursive: true});
const root = await mkdtemp(join(build, 'packed-local-assets-'));
const environment = {...process.env,
  npm_config_cache: join(build, 'npm-cache')};

function run(command, args, cwd) {
  const result = spawnSync(command, args, {cwd, env: environment,
    encoding: 'utf8', timeout: 30000});
  if (result.error || result.status !== 0) {
    throw new Error(`${command} ${args.join(' ')} failed:\n` +
      `${result.stdout}\n${result.stderr}`, {cause: result.error});
  }
  return result.stdout;
}

const artifacts = [];
for (const name of ['client-wire', 'sdk', 'local-node']) {
  const packed = run('npm', ['pack', '--pack-destination', root, '--json'],
    join(repository, 'packages', name));
  const metadata = JSON.parse(packed);
  artifacts.push(join(root, metadata[0]?.filename ??
    metadata[`@actql/${name}`]?.filename));
}
await writeFile(join(root, 'package.json'),
  '{"private":true,"type":"module"}\n');
run('npm', ['install', '--ignore-scripts', '--no-save', ...artifacts], root);
const moduleRoot = join(root, 'node_modules/@actql/local-node');
for (const name of [
  'connectors_builtin_node/connectors_builtin_node.js',
  'connectors/duckdb/host_node/host_node.js',
  'retained_host_bridge/retained_host_bridge.js',
  'process_host_bridge/process_host_bridge.js',
]) {
  assert((await readFile(join(moduleRoot, '_build/js/release/build',
    name))).byteLength > 0);
}
await writeFile(join(root, 'smoke.mjs'), `
import assert from 'node:assert/strict';
const owner = await import('@actql/local-node/runtime');
assert.equal(typeof owner.clientProgramPrepareEffectFree, 'function');
assert.equal(typeof owner.clientProgramOpenSourceFreeLocalHost, 'function');
const host = await import('./node_modules/@actql/local-node/adapters/' +
  'host-node/entry.mjs');
assert.equal(typeof host.runPublishedCapturedStrategy, 'function');
const ingress = await import('./node_modules/@actql/local-node/adapters/' +
  'host-node/in-process-client.mjs');
assert.equal(typeof ingress.createNodeInProcessClientHost, 'function');
`);
run(process.execPath, ['smoke.mjs'], root);
console.log('packed Local runtime assets passed');
