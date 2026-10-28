// An external consumer of a normally built, explicitly composed Node Host.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {existsSync, lstatSync, realpathSync} from 'node:fs';
import {cp, mkdir, readFile, symlink, writeFile} from 'node:fs/promises';
import {dirname, join, relative, resolve} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {createOwnedScratch} from './owned-scratch.mjs';
import {packedNpmCache, normalNpmPackJsonArgs, parseNpmPackJson} from './packed-client-packages.mjs';
import {resolveConnectorBuildInputs} from './connector-build-inputs.mjs';
import {checkNodeAssembly} from './connector-node-bundles.mjs';
import {localNodePackageInputs} from './local-node-package-inputs.mjs';
import {buildExternalLocalNodeRuntime} from './build-runtime-packages.mjs';
import {buildLocalNodeAdapters} from './build-local-node-adapters.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');
function run(command, args, cwd, env, timeout = 120000) {
  const result = spawnSync(command, args, {cwd, env, encoding: 'utf8', timeout,
    maxBuffer: 32 * 1024 * 1024});
  if (result.error || result.status !== 0) throw new Error(
    `ExternalInstalledCommandFailed:${command}\n${result.stdout}\n${result.stderr}`,
    {cause: result.error});
  return result.stdout;
}

// Called by the composed Host package's ordinary npm prepack lifecycle.
export async function buildExternalInstalledFixture({coreRoot, hostRoot, providers}) {
  const inputs = resolveConnectorBuildInputs({target: 'js',
    modules: [{namespace: 'actql/actql', version: '0.0.1', root: coreRoot},
      {namespace: 'fixture/installed_host', version: '0.0.1', root: hostRoot},
      ...providers.map(({name, root}) => ({namespace: `fixture/${name}`, version: '0.0.1', root}))],
    host: 'fixture/installed_host',
    connectors: providers.map(({name}) => ({name, module: `fixture/${name}`,
      directory: `src/connectors/${name}`}))});
  checkNodeAssembly(hostRoot, true, {buildInputs: inputs, installations: true,
    assembly: 'compute', bridge: 'runtime'});
  const inventory = localNodePackageInputs(hostRoot, {buildInputs: inputs});
  const destination = join(hostRoot, 'distribution');
  await buildExternalLocalNodeRuntime({inputs: inventory, destination,
    compiledDirectory: join(hostRoot, '_build/external-compiled')});
  await buildLocalNodeAdapters({root: hostRoot, inputs: inventory, destination});
  await buildLocalNodeAdapters({root: hostRoot, inputs: inventory, destination, check: true});
  const runtimeDigests = [];
  for (const path of inventory.runtimeFiles) {
    runtimeDigests.push({path, sha256: sha256(await readFile(join(destination, '_build/js/release/build', path)))});
  }
  await writeFile(join(hostRoot, 'build-receipt.json'), JSON.stringify({
    modules: inputs.modules.map(({namespace, version}) => ({namespace, version})),
    providers: inventory.providerBundles, runtimeDigests,
    tableSha256: sha256(await readFile(join(destination, inventory.installationTable.destination))),
    assets: inventory.dataInputs.map(({destination}) => destination),
  }, null, 2) + '\n');
}

async function acceptance() {
  const scratch = await createOwnedScratch({parent: join(repository, '..', '.codex-scratch'),
    prefix: 'external-installed-pack-', label: 'packed external installed Connectors'});
  const coreRoot = join(scratch.path, 'core'), hostRoot = join(scratch.path, 'host');
  const buildDeps = join(scratch.path, 'build-dependencies'), consumer = join(scratch.path, 'consumer');
  const artifacts = join(scratch.path, 'artifacts');
  for (const path of [coreRoot, hostRoot, buildDeps, consumer, artifacts]) await mkdir(path);
  await mkdir(join(hostRoot, 'src'));
  const environment = Object.fromEntries(Object.entries(process.env)
    .filter(([key]) => !key.startsWith('ACTQL_') && key !== 'NODE_PATH'));
  environment.npm_config_cache = packedNpmCache(scratch.path);
  const paths = [...new Set(run('git', ['ls-files', '-z', '--cached', '--others', '--exclude-standard'],
    repository, environment).split('\0').filter(Boolean))];
  const sourceHashes = [];
  for (const path of paths) {
    if (!['src/', 'adapters/', 'scripts/', 'packages/', 'spec/'].some(prefix => path.startsWith(prefix)) &&
        !['moon.mod', 'package.json', 'package-lock.json'].includes(path)) continue;
    const source = join(repository, path);
    if (!existsSync(source)) {
      assert.ok(!path.startsWith('src/') ||
        !path.endsWith('moon.pkg') && (!path.endsWith('.mbt') || /_(?:wb)?test\.mbt$/.test(path)),
      `Missing production source in sparse checkout: ${path}`);
      continue;
    }
    assert.ok(lstatSync(source).isFile(), `Nonregular producer input: ${path}`);
    const bytes = await readFile(source), target = join(coreRoot, path);
    await mkdir(dirname(target), {recursive: true}); await writeFile(target, bytes);
    sourceHashes.push([path, sha256(bytes)]);
  }
  await symlink(join(repository, 'node_modules'), join(coreRoot, 'node_modules'), 'dir');
  const fixture = join(coreRoot, 'scripts/fixtures/external-installed');
  const packs = [];
  const pack = async root => {
    const metadata = parseNpmPackJson(run('npm', normalNpmPackJsonArgs(['pack', '--offline', '--json', '--pack-destination', artifacts]),
      root, environment, 180000))[0];
    const path = join(artifacts, metadata.filename), bytes = await readFile(path);
    assert.equal(metadata.integrity, 'sha512-' + createHash('sha512').update(bytes).digest('base64'));
    const result = {path, name: metadata.name, sha256: sha256(bytes), integrity: metadata.integrity};
    packs.push(result); return result;
  };
  const providers = [];
  for (const role of ['read', 'effect']) {
    const source = join(scratch.path, `external-${role}`);
    await cp(join(fixture, `external-${role}`), source, {recursive: true});
    providers.push({name: `external_${role}`, npm: `@fixture/external-${role}`, pack: await pack(source)});
  }
  await writeFile(join(buildDeps, 'package.json'), '{"private":true,"type":"module"}\n');
  run('npm', ['install', '--ignore-scripts', '--legacy-peer-deps', '--offline', '--no-audit', '--no-fund',
    '--no-save', ...providers.map(entry => entry.pack.path)], buildDeps, environment);
  for (const entry of providers) entry.root = realpathSync(join(buildDeps, 'node_modules', entry.npm));
  await writeFile(join(hostRoot, 'moon.mod'),
    'name = "fixture/installed_host"\nversion = "0.0.1"\nsource = "src"\nsupported_targets = "js"\n' +
    'import {\n  "actql/actql@0.0.1",\n' + providers.map(entry => `  "fixture/${entry.name}@0.0.1",\n`).join('') + '}\n');
  await writeFile(join(scratch.path, 'moon.work'), 'members = [\n' +
    [coreRoot, hostRoot, ...providers.map(entry => entry.root)]
      .map(path => `  ${JSON.stringify(relative(scratch.path, path))},\n`).join('') + ']\n');
  const destination = join(hostRoot, 'distribution'); await mkdir(destination);
  const packageSource = join(coreRoot, 'packages/local-node');
  const manifest = JSON.parse(await readFile(join(packageSource, 'package.json'), 'utf8'));
  for (const path of manifest.files) {
    const source = join(packageSource, path);
    if (existsSync(source) && lstatSync(source).isFile()) await cp(source, join(destination, path));
  }
  manifest.scripts = {prepack: 'node build.mjs'};
  await writeFile(join(destination, 'package.json'), JSON.stringify(manifest, null, 2) + '\n');
  const options = {coreRoot, hostRoot, providers: providers.map(({name, root}) => ({name, root}))};
  await writeFile(join(destination, 'build.mjs'),
    `import {buildExternalInstalledFixture} from ${JSON.stringify(pathToFileURL(join(coreRoot, 'scripts/test-packed-external-installed.mjs')).href)};\n` +
    `await buildExternalInstalledFixture(${JSON.stringify(options)});\n`);
  const hostPack = await pack(destination);
  for (const [path, expected] of sourceHashes) {
    assert.equal(sha256(await readFile(join(coreRoot, path))), expected, `Changed Core build input: ${path}`);
  }
  assert.doesNotMatch(await readFile(join(coreRoot, 'moon.mod'), 'utf8'), /fixture\//);
  const sdk = await pack(join(coreRoot, 'packages/sdk')), wire = await pack(join(coreRoot, 'packages/client-wire'));
  await writeFile(join(consumer, 'package.json'), '{"private":true,"type":"module"}\n');
  run('npm', ['install', '--ignore-scripts', '--legacy-peer-deps', '--offline', '--no-audit', '--no-fund', '--no-save',
    hostPack.path, sdk.path, wire.path, ...providers.map(entry => entry.pack.path)], consumer, environment);
  const installedHost = join(consumer, 'node_modules/@actql/local-node');
  const receipt = JSON.parse(await readFile(join(hostRoot, 'build-receipt.json'), 'utf8'));
  for (const {path, sha256: expected} of receipt.runtimeDigests) {
    assert.equal(sha256(await readFile(join(installedHost, '_build/js/release/build', path))), expected);
  }
  for (const path of receipt.assets) assert.ok(lstatSync(join(installedHost, path)).isFile());
  const table = await readFile(join(installedHost, 'adapters/connectors-builtin/installations.generated.mjs'), 'utf8');
  assert.equal(sha256(table), receipt.tableSha256);
  assert.ok(!table.includes(scratch.path), 'no producer path in packaged installation table');
  await cp(join(fixture, 'consumer.mjs'), join(consumer, 'verify.mjs'));
  await cp(join(packageSource, 'connector-installation.typecheck.mts'), join(consumer, 'helpers.typecheck.mts'));
  run(process.execPath, [join(repository, 'node_modules/typescript/bin/tsc'), '--noEmit', '--strict',
    '--module', 'NodeNext', '--moduleResolution', 'NodeNext', '--target', 'ES2022', 'helpers.typecheck.mts'],
  consumer, environment, 30000);
  await writeFile(join(consumer, 'acceptance.mjs'),
    'import {verifyExternalInstalledFixture} from "./verify.mjs";\n' +
    'import {installedConnectors} from "./node_modules/@actql/local-node/adapters/connectors-builtin/installations.generated.mjs";\n' +
    'import {providerBundleUrl} from "./node_modules/@actql/local-node/adapters/host-node/installed-connectors.mjs";\n' +
    `console.log("EXTERNAL_INSTALLED_ACCEPTANCE",JSON.stringify(await verifyExternalInstalledFixture({directory:${JSON.stringify(join(consumer, 'state'))},installedConnectors,providerBundleUrl})));\n`);
  const output = run(process.execPath, ['acceptance.mjs'], consumer, environment, 60000);
  assert.match(output, /EXTERNAL_INSTALLED_ACCEPTANCE/); console.log(output.trim());
  console.log('EXTERNAL_INSTALLED_PACKS', JSON.stringify({
    sourceRevision: run('git', ['rev-parse', 'HEAD'], repository, environment).trim(),
    copiedSourceSha256: sha256(JSON.stringify(sourceHashes)),
    packages: packs.map(({name, sha256, integrity}) => ({name, sha256, integrity})), build: receipt}));
  scratch.passed();
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) await acceptance();
