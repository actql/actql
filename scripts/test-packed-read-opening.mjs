// Reuse the exact Client packages and the same authored opening-loss and receipt fixture.
// Only test inputs/support are copied; every product import uses the installation.
import {spawnSync} from 'node:child_process';
import assert from 'node:assert/strict';
import {copyFile, mkdir, readFile, writeFile} from 'node:fs/promises';
import {join, relative, resolve} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {createOwnedScratch} from './owned-scratch.mjs';
import {checkoutState, packClientPackages, packedClientPackage, packedNpmCache} from './packed-client-packages.mjs';
import {nodeTestArguments, assertTestExecution} from './test-execution.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
const state = checkoutState(repository);
if (!state.clean) throw new Error('Build inputs differ from HEAD');
const names = ['client-wire', 'sdk', 'run-host-core', 'local-node'];
const tarball = name => `actql-${name}-0.0.0-development.tgz`;
const scratch = await createOwnedScratch({parent: join(repository, '..', '.codex-scratch'),
  prefix: 'packed-read-opening-', label: 'packed original Delivery lookup',
  digests: () => [...names.map(tarball), 'packed-client-packages.json']});
const root = scratch.path;
const environment = {...process.env, npm_config_cache: packedNpmCache(root)};
function run(command, args, cwd, timeout = 120000) {
  const result = spawnSync(command, args, {cwd, env: environment, encoding: 'utf8', timeout});
  if (result.error || result.status !== 0) {
    throw new Error(`${command} failed (${result.status}):\n${result.stdout}\n${result.stderr}`, {cause: result.error});
  }
  return result.stdout;
}
if (!process.env.ACTQL_PACKED_CLIENT_PACKAGES) {
  const producer = join(root, 'producer');
  await packClientPackages({repository, destination: producer, names,
    pack: name => run('npm', ['pack', '--pack-destination', producer, '--json'],
      join(repository, 'packages', name), 180000)});
  process.env.ACTQL_PACKED_CLIENT_PACKAGES = producer;
}
for (const name of names) {
  await packedClientPackage({repository, name, destination: root,
    pack: () => {throw new Error('Missing exact package manifest');}});
}
await copyFile(join(process.env.ACTQL_PACKED_CLIENT_PACKAGES, 'packed-client-packages.json'),
  join(root, 'packed-client-packages.json'));
await writeFile(join(root, 'package.json'), '{"private":true,"type":"module"}\n');
run('npm', ['install', '--ignore-scripts', '--no-save', '--no-audit', '--no-fund',
  ...names.map(name => join(root, tarball(name)))], root);

const installedHost = join(root, 'node_modules/@actql/local-node');
const fixtureDirectory = join(root, 'adapters/host-node');
await mkdir(fixtureDirectory, {recursive: true});
const support = [
  'adapters/host-node/client-read-opening.test.mjs',
  'adapters/host-node/client-read-opening.fixture.mjs',
  'adapters/host-node/client-read-opening-restart.fixture.mjs',
  'scripts/owned-scratch.mjs',
  'packages/sdk/fixtures/values.json',
  'packages/sdk/fixtures/values.environment.json',
];
for (const path of support) {
  const output = join(root, path);
  await mkdir(join(output, '..'), {recursive: true});
  let text = await readFile(join(repository, path), 'utf8');
  if (path.includes('client-read-opening')) {
    text = text.replace(/from (['"])([^'"]+)\1/gu, (original, quote, specifier) => {
      if (specifier.startsWith('node:')) return original;
      const target = relative(repository, resolve(repository, path, '..', specifier));
      if (support.includes(target)) return original;
      if (target === 'packages/sdk/index.mjs') return `from ${quote}@actql/sdk${quote}`;
      if (target === 'packages/sdk/host-port.mjs') return `from ${quote}@actql/sdk/host-port${quote}`;
      if (target === '_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js') {
        return `from ${quote}@actql/local-node/runtime${quote}`;
      }
      if (!target.startsWith('adapters/')) throw new Error(`Unpackaged fixture import: ${target}`);
      return `from ${quote}${pathToFileURL(join(installedHost, target)).href}${quote}`;
    }).replace(/new URL\('((?:\.\.\/)+spec\/[^']+)', import.meta.url\)/gu,
      (_original, specifier) => `new URL(${JSON.stringify(pathToFileURL(join(installedHost,
        relative(repository, resolve(repository, path, '..', specifier)))).href)})`);
  }
  await writeFile(output, text);
}
const args = nodeTestArguments(['adapters/host-node/client-read-opening.test.mjs']);
const result = spawnSync(process.execPath, args, {cwd: root, env: environment, encoding: 'utf8', timeout: 120000});
const output = `${result.stdout ?? ''}\n${result.stderr ?? ''}`;
await writeFile(join(root, 'acceptance.log'), output);
console.log(output);
const checked = assertTestExecution('node', process.execPath, args, result);
assert.equal(checked.counts.tests, 8);
assert.equal(checked.counts.passed, 8);
const after = checkoutState(repository);
if (!after.clean || after.revision !== state.revision) throw new Error('Checkout changed during acceptance');
await writeFile(join(root, 'acceptance.json'), `${JSON.stringify({sourceHead: state.revision,
  packageNames: names, productOverlay: false, expectedRows: [{id: 1}, {id: 2}],
  cases: {openingLoss: 4, receiptDurability: 4}, passed: true}, null, 2)}\n`);
console.log(`Packed original Delivery lookup passed for ${state.revision}: ${root}`);
scratch.passed();
