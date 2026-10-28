// A new producer starts without any compiled runtime or package output.
// Only source inputs are copied; consumers install real tarballs outside it.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {copyFile, mkdir, readFile, writeFile} from 'node:fs/promises';
import {existsSync} from 'node:fs';
import {join, dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createOwnedScratch} from './owned-scratch.mjs';
import {auditPackedPackages} from './packed-package-boundaries.mjs';
import {BUILD_INPUTS, packedNpmCache, normalNpmPackJsonArgs, parseNpmPackJson} from './packed-client-packages.mjs';
import {localNodePackageInputs} from './local-node-package-inputs.mjs';
import {symlink} from 'node:fs/promises';

const repository = fileURLToPath(new URL('../', import.meta.url));
const names = ['client-wire', 'sdk', 'run-host-core', 'local-node', 'node'];
const scratch = await createOwnedScratch({parent: join(repository, '..', '.codex-scratch'),
  prefix: 'packed-installed-connectors-', label: 'fresh packed installed Connectors'});
const producer = join(scratch.path, 'producer'), application = join(scratch.path, 'application');
const artifacts = join(scratch.path, 'artifacts');
for (const path of [producer, application, artifacts]) await mkdir(path);
const environment = {...process.env, npm_config_cache: packedNpmCache(scratch.path)};
delete environment.NODE_PATH;
delete environment.ACTQL_PACKED_CLIENT_PACKAGES;
delete environment.ACTQL_LOCAL_SOURCE_PROFILE;
delete environment.ACTQL_LOCAL_EFFECT_PROFILE;
function run(command, args, cwd, timeout = 120000) {
  const result = spawnSync(command, args, {cwd, env: environment, encoding: 'utf8',
    timeout, maxBuffer: 32 * 1024 * 1024});
  if (result.error || result.status !== 0) throw new Error(
    `PackedConnectorCommandFailed:${command}\n${result.stdout}\n${result.stderr}`,
    {cause: result.error});
  return result.stdout;
}
const listed = run('git', ['ls-files', '-z', '--cached', '--others', '--exclude-standard'],
  repository).split('\0').filter(Boolean);
const paths = [...new Set(listed)].filter(path => !path.includes('/') ||
  BUILD_INPUTS.some(prefix => path.startsWith(prefix + '/')));
const sourceDigests = [];
for (const path of paths) {
  // Sparse checkouts may omit unrelated tests/docs. Every byte actually used
  // by normal prepack must still exist and succeeds through that real build.
  if (!existsSync(join(repository, path))) continue;
  const bytes = await readFile(join(repository, path));
  const output = join(producer, path);
  await mkdir(dirname(output), {recursive: true});
  await writeFile(output, bytes);
  sourceDigests.push([path, createHash('sha256').update(bytes).digest('hex')]);
}
assert.equal(existsSync(join(producer, '_build')), false);
for (const name of names) {
  assert.equal(existsSync(join(producer, 'packages', name, '_build')), false);
  assert.equal(existsSync(join(producer, 'packages', name, 'dist')), false);
}
await symlink(join(repository, 'node_modules'), join(producer, 'node_modules'), 'dir');
const inputs = localNodePackageInputs(producer);
const packs = [];
for (const name of names) {
  const output = parseNpmPackJson(run('npm', normalNpmPackJsonArgs(['pack', '--json', '--pack-destination', artifacts]),
    join(producer, 'packages', name), 180000));
  const pack = output[0] ?? output[`@actql/${name}`];
  const path = join(artifacts, pack.filename);
  packs.push({name, path, sha256: createHash('sha256').update(await readFile(path)).digest('hex')});
  if (name === 'local-node') {
    for (const file of [...inputs.runtimeFiles.map(path => '_build/js/release/build/' + path),
      ...inputs.dataFiles]) {
      assert.ok(pack.files.some(entry => entry.path === file && entry.size > 0),
        `Missing declared package payload: ${file}`);
    }
  }
}
for (const [path, digest] of sourceDigests) {
  assert.equal(createHash('sha256').update(await readFile(join(producer, path))).digest('hex'),
    digest, `Prepack changed copied source: ${path}`);
}
await writeFile(join(application, 'package.json'), '{"private":true,"type":"module"}\n');
run('npm', ['install', '--ignore-scripts', '--offline', '--no-audit', '--no-fund',
  '--no-save', ...packs.map(pack => pack.path)], application);
auditPackedPackages(application, names);
for (const name of ['source-inventory.typecheck.mts', 'effect-inventory.typecheck.mts',
  'connector-table.typecheck.mts']) {
  await copyFile(join(repository, 'packages/local-node', name), join(application, name));
}
run(process.execPath, [join(repository, 'node_modules/typescript/bin/tsc'),
  '--strict', '--target', 'ES2022', '--module', 'NodeNext',
  '--moduleResolution', 'NodeNext', '--noEmit',
  'source-inventory.typecheck.mts', 'effect-inventory.typecheck.mts',
  'connector-table.typecheck.mts'], application);
await copyFile(join(repository, 'scripts/fixtures/packed-installed-connectors.mjs'),
  join(application, 'acceptance.mjs'));
const output = run(process.execPath, ['acceptance.mjs'], application, 30000);
assert.match(output, /PACKED_INSTALLED_CONNECTORS/);
console.log(output.trim());
// Keep the source and packed campaigns on the exact same authored fixture.
// Only independent HTTPS responders are copied beside the public consumer.
for (const path of [
  'scripts/fixtures/installed-effect-inventory-acceptance.mjs',
  'adapters/site-node/https-exchange-fixture.mjs',
  'adapters/connectors/github/test/github-graphql.fixture.mjs',
]) {
  const target = join(application, path);
  await mkdir(dirname(target), {recursive: true});
  await copyFile(join(repository, path), target);
  assert.deepEqual(await readFile(target), await readFile(join(repository, path)));
}
await copyFile(join(repository, 'scripts/fixtures/packed-effect-inventory.mjs'),
  join(application, 'effect-inventory.mjs'));
const effectOutput = run(process.execPath, ['effect-inventory.mjs'], application, 120000);
assert.match(effectOutput, /PACKED_EFFECT_INVENTORY/);
console.log(effectOutput.trim());
for (const [source, target] of [
  ['scripts/fixtures/installed-connector-table-acceptance.mjs', 'connector-table-acceptance.mjs'],
  ['scripts/fixtures/packed-connector-table.mjs', 'connector-table.mjs'],
  ['packages/sdk/fixtures/values.json', 'table-values.json'],
]) await copyFile(join(repository, source), join(application, target));
const tableOutput = run(process.execPath, ['connector-table.mjs'], application, 30000);
assert.match(tableOutput, /PACKED_CONNECTOR_TABLE/);
console.log(tableOutput.trim());
console.log('FRESH_CONNECTOR_PACKS', JSON.stringify({
  sourceRevision: run('git', ['rev-parse', 'HEAD'], repository).trim(),
  copiedSourceFiles: sourceDigests.length, initiallyEmptyBuild: true,
  sourceInputSha256: createHash('sha256').update(JSON.stringify(sourceDigests)).digest('hex'),
  runtimes: await Promise.all(inputs.runtimeFiles.map(async path => ({path,
    sha256: createHash('sha256').update(await readFile(join(producer,
      'packages/local-node/_build/js/release/build', path))).digest('hex')}))),
  packages: packs.map(({name, sha256}) => ({name, sha256})),
}));
scratch.passed();
