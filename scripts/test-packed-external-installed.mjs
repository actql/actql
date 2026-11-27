// An external consumer of a normally built, explicitly composed Node Host.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {existsSync, lstatSync, realpathSync} from 'node:fs';
import {cp, mkdir, readFile, writeFile} from 'node:fs/promises';
import {dirname, join, relative, resolve} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {createOwnedScratch} from './owned-scratch.mjs';
import {prepareCopiedTypeScript} from './copied-typescript-preparation.mjs';
import {checkoutState, packedNpmCache, normalNpmPackJsonArgs, parseNpmPackJson, normalPackSourceInputs, initializeNormalPackSourceIndex} from './packed-client-packages.mjs';
import {resolveConnectorBuildInputs} from './connector-build-inputs.mjs';
import {checkNodeAssembly} from './connector-node-bundles.mjs';
import {localNodePackageInputs} from './local-node-package-inputs.mjs';
import {buildExternalLocalNodeRuntime} from './build-runtime-packages.mjs';
import {buildLocalNodeAdapters} from './build-local-node-adapters.mjs';
import {buildConnectorAuthoring} from './build-connector-authoring.mjs';
import {authoringBinPath, authoringToolkitPath} from './connector-authoring-toolkit.mjs';
import {inventory, unpack} from './package-release.mjs';
import {preparePackedClientInstallCache} from './prepare-packed-client-install-cache.mjs';

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

export async function verifyExternalAuthoringPayload(packageRoot, expected) {
  const metadata = JSON.parse(await readFile(join(packageRoot, 'package.json'), 'utf8'));
  assert.equal(metadata.name, '@actql/local-node');
  assert.equal(metadata.bin?.['actql-connector'], authoringBinPath);
  const toolkit = join(packageRoot, authoringToolkitPath);
  assert(lstatSync(toolkit).isDirectory(), 'Selected external Host must contain the original authoring toolkit');
  const files = await inventory(toolkit);
  assert.deepEqual(files, expected, 'Changed external Host authoring toolkit');
  const launcher = files.find(file => file.path === 'scripts/connector.mjs');
  assert(launcher && (launcher.mode & 0o111) !== 0, 'Expected an executable authoring launcher');
  return join(packageRoot, authoringBinPath);
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
  const payload = localNodePackageInputs(hostRoot, {buildInputs: inputs});
  const destination = join(hostRoot, 'distribution');
  await buildExternalLocalNodeRuntime({inputs: payload, destination,
    compiledDirectory: join(hostRoot, '_build/external-compiled')});
  await buildLocalNodeAdapters({root: hostRoot, inputs: payload, destination});
  await buildLocalNodeAdapters({root: hostRoot, inputs: payload, destination, check: true});
  buildConnectorAuthoring(coreRoot, destination);
  const authoringToolkit = await inventory(join(destination, authoringToolkitPath));
  const runtimeDigests = [];
  for (const path of payload.runtimeFiles) {
    runtimeDigests.push({path, sha256: sha256(await readFile(join(destination, '_build/js/release/build', path)))});
  }
  await writeFile(join(hostRoot, 'build-receipt.json'), JSON.stringify({
    modules: inputs.modules.map(({namespace, version}) => ({namespace, version})),
    providers: payload.providerBundles, runtimeDigests, authoringToolkit,
    tableSha256: sha256(await readFile(join(destination, payload.installationTable.destination))),
    assets: payload.dataInputs.map(({destination}) => destination),
  }, null, 2) + '\n');
}

async function acceptance() {
  const source = checkoutState(repository);
  assert(source.clean, 'The composed external installer must use the original clean source');
  const scratch = await createOwnedScratch({parent: join(repository, '..', '.codex-scratch'),
    prefix: 'external-installed-pack-', label: 'packed external installed Connectors'});
  const coreRoot = join(scratch.path, 'core'), hostRoot = join(scratch.path, 'host');
  const buildDeps = join(scratch.path, 'build-dependencies'), consumer = join(scratch.path, 'consumer');
  const artifacts = join(scratch.path, 'artifacts');
  for (const path of [coreRoot, hostRoot, buildDeps, consumer, artifacts]) await mkdir(path);
  await mkdir(join(hostRoot, 'src'));
  const environment = Object.fromEntries(Object.entries(process.env)
    .filter(([key]) => !key.startsWith('ACTQL_') && key !== 'NODE_PATH' && key !== 'NODE_OPTIONS'));
  environment.npm_config_cache = packedNpmCache(scratch.path);
  const listed = [...new Set(run('git', ['ls-files', '-z', '--cached', '--others', '--exclude-standard'],
    repository, environment).split('\0').filter(Boolean))];
  const paths = await normalPackSourceInputs(repository, listed);
  const sourceHashes = [];
  for (const path of paths) {
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
  initializeNormalPackSourceIndex(coreRoot, sourceHashes.map(([path]) => path));
  await prepareCopiedTypeScript({source: repository, root: coreRoot, environment, run});
  const fixture = join(coreRoot, 'scripts/fixtures/external-installed');
  const packs = [];
  const pack = async root => {
    const metadata = parseNpmPackJson(run('npm', normalNpmPackJsonArgs(['pack', '--offline', '--json', '--pack-destination', artifacts]),
      root, environment, 180000))[0];
    const path = join(artifacts, metadata.filename), bytes = await readFile(path);
    assert.equal(metadata.integrity, 'sha512-' + createHash('sha512').update(bytes).digest('base64'));
    const result = {path, name: metadata.name, file: metadata.filename, bytes: bytes.length,
      sha256: sha256(bytes), integrity: metadata.integrity};
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
  const receipt = JSON.parse(await readFile(join(hostRoot, 'build-receipt.json'), 'utf8'));
  const packedHost = await unpack(hostPack.path, join(scratch.path, 'packed-host-authoring'));
  await verifyExternalAuthoringPayload(packedHost, receipt.authoringToolkit);
  for (const [path, expected] of sourceHashes) {
    assert.equal(sha256(await readFile(join(coreRoot, path))), expected, `Changed Core build input: ${path}`);
  }
  assert.doesNotMatch(await readFile(join(coreRoot, 'moon.mod'), 'utf8'), /fixture\//);
  const sdk = await pack(join(coreRoot, 'packages/sdk')), wire = await pack(join(coreRoot, 'packages/client-wire'));
  await writeFile(join(consumer, 'package.json'), '{"private":true,"type":"module"}\n');
  await preparePackedClientInstallCache(environment.npm_config_cache);
  run('npm', ['install', '--ignore-scripts', '--legacy-peer-deps', '--offline', '--no-audit', '--no-fund', '--no-save',
    hostPack.path, sdk.path, wire.path, ...providers.map(entry => entry.pack.path)], consumer, environment);
  const installedHost = join(consumer, 'node_modules/@actql/local-node');
  const installedLauncher = await verifyExternalAuthoringPayload(installedHost, receipt.authoringToolkit);
  const command = join(consumer, 'node_modules/.bin/actql-connector');
  assert.equal(realpathSync(command), realpathSync(installedLauncher));
  const authorDirectory = join(consumer, 'author-probe');
  const scaffold = JSON.parse(run(command, ['init', authorDirectory, 'independent_effect'], consumer, environment, 10000));
  assert.deepEqual(scaffold, {definition: join(authorDirectory, 'connector.json'), runtimeExecuted: false});
  assert.equal(JSON.parse(await readFile(scaffold.definition, 'utf8')).id, 'independent_effect');
  for (const {path, sha256: expected} of receipt.runtimeDigests) {
    assert.equal(sha256(await readFile(join(installedHost, '_build/js/release/build', path))), expected);
  }
  for (const path of receipt.assets) assert.ok(lstatSync(join(installedHost, path)).isFile());
  const table = await readFile(join(installedHost, 'adapters/connectors-builtin/installations.generated.mjs'), 'utf8');
  assert.equal(sha256(table), receipt.tableSha256);
  assert.ok(!table.includes(scratch.path), 'no producer path in packaged installation table');
  await cp(join(packageSource, 'connector-installation.typecheck.mts'), join(consumer, 'helpers.typecheck.mts'));
  run(process.execPath, [join(repository, 'node_modules/typescript/bin/tsc'), '--noEmit', '--strict',
    '--module', 'NodeNext', '--moduleResolution', 'NodeNext', '--target', 'ES2022', 'helpers.typecheck.mts'],
  consumer, environment, 30000);
  assert.deepEqual(checkoutState(repository), source);
  const sourceTree = run('git', ['rev-parse', `${source.revision}^{tree}`], repository, environment).trim();
  const manifestPath = join(artifacts, 'external-installer-cohort.json');
  const packages = packs.map(({name, file, bytes, sha256, integrity}) => ({name, file, bytes, sha256, integrity}));
  const manifestWire = JSON.stringify({kind: 'actql-external-installed-cohort/0.1', sourceSha: source.revision, sourceTree, packages});
  await writeFile(manifestPath, manifestWire, {flag: 'wx'});
  const descriptor = join(scratch.path, 'conformance.json'), outputRoot = join(scratch.path, 'author-conformance');
  const manifestSha256 = sha256(manifestWire);
  await writeFile(descriptor, JSON.stringify({kind: 'actql-external-installed-normal/0.1', mode: 'provider-bundle',
    sourceSha: source.revision, sourceTree, manifestPath, manifestSha256, outputRoot, consumerRoot: consumer}), {flag: 'wx'});
  run(command, ['conformance', descriptor, '--timeout-seconds', '120'], consumer, environment, 130000);
  const qualified = JSON.parse(await readFile(join(outputRoot, 'qualification.json'), 'utf8'));
  assert.equal(qualified.manifestSha256, manifestSha256);
  assert.equal(qualified.outcome.externalRead, true);
  assert.equal(qualified.outcome.externalEffect, true);
  await verifyExternalAuthoringPayload(installedHost, receipt.authoringToolkit);
  assert.equal(sha256(await readFile(hostPack.path)), hostPack.sha256);
  assert.deepEqual(checkoutState(repository), source);
  console.log('EXTERNAL_INSTALLED_ACCEPTANCE', JSON.stringify(qualified.outcome));
  console.log('EXTERNAL_INSTALLED_PACKS', JSON.stringify({
    sourceRevision: source.revision, sourceTree, copiedSourceSha256: sha256(JSON.stringify(sourceHashes)),
    manifestSha256, packages, build: receipt,
    authoring: {launcher: authoringBinPath, installedScaffold: true, files: receipt.authoringToolkit.length}}));
  scratch.passed();
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) await acceptance();
