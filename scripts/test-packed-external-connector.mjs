// A private build fixture: normal packages enter the build and the consumer.
// No registry resolution, runtime discovery or source-tree fallback is allowed.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {cp, mkdir, readFile, readdir, writeFile, symlink} from 'node:fs/promises';
import {existsSync, lstatSync, readFileSync, realpathSync} from 'node:fs';
import {isBuiltin} from 'node:module';
import {basename, dirname, isAbsolute, join, relative, resolve, sep} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {build, buildSync} from 'esbuild';
import {createOwnedScratch} from './owned-scratch.mjs';
import {packedNpmCache, normalNpmPackJsonArgs, parseNpmPackJson, normalPackSourceInputs, initializeNormalPackSourceIndex} from './packed-client-packages.mjs';
import {tokens} from './portable-core.mjs';
import {resolveConnectorBuildInputs} from './connector-build-inputs.mjs';
import {checkNodeAssembly} from './connector-node-bundles.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');
const quote = path => JSON.stringify(pathToFileURL(path).href);
const inside = (parent, path) => {
  const child = relative(parent, path);
  return child === '' || !isAbsolute(child) && child !== '..' && !child.startsWith('..' + sep);
};
function run(command, args, cwd, environment, timeout = 120000) {
  const result = spawnSync(command, args, {cwd, env: environment, encoding: 'utf8',
    timeout, maxBuffer: 32 * 1024 * 1024});
  if (result.error || result.status !== 0) throw new Error(
    `ExternalConnectorCommandFailed:${command}\n${result.stdout}\n${result.stderr}`,
    {cause: result.error});
  return result.stdout;
}

export function manifestImports(source) {
  const list = tokens(source), result = [];
  for (let index = 0; index < list.length; index++) {
    if (list[index].kind !== 'word' || list[index].value !== 'import') continue;
    assert.equal(list[++index].value, '{');
    while (list[++index].value !== '}') {
      assert.equal(list[index].kind, 'string');
      const path = list[index].value;
      let alias = path.split('/').at(-1);
      if (list[index + 1].value === '@') {
        index += 2;
        assert.equal(list[index].kind, 'word');
        alias = list[index].value;
      }
      result.push({path, alias});
      if (list[index + 1].value === ',') index++;
    }
  }
  return result;
}

async function filesBelow(root) {
  const result = [];
  const visit = async directory => {
    for (const entry of await readdir(directory, {withFileTypes: true})) {
      const path = join(directory, entry.name);
      if (entry.isDirectory()) await visit(path);
      else {
        assert.ok(entry.isFile(), `Nonregular fixture output: ${path}`);
        result.push(path);
      }
    }
  };
  await visit(root);
  return result.sort();
}

// Invoked by the Host fixture's normal npm prepack lifecycle.
export async function buildExternalComputeFixture({coreRoot, connectorRoot, hostRoot, outputRoot}) {
  assert.equal(existsSync(outputRoot), false, 'compiler output starts empty');
  const inputs = resolveConnectorBuildInputs({target: 'js',
    modules: [
      {namespace: 'actql/actql', version: '0.0.1', root: coreRoot},
      {namespace: 'fixture/external_numeric', version: '0.0.1', root: connectorRoot},
      {namespace: 'fixture/compute_host', version: '0.0.1', root: hostRoot},
    ], host: 'fixture/compute_host',
    connectors: [{name: 'external_numeric', module: 'fixture/external_numeric', directory: 'src'}]});
  checkNodeAssembly(hostRoot, true, {buildInputs: inputs,
    assembly: 'compute', bridge: 'runtime', adapter: 'installed'});
  const runtimeRoot = join(hostRoot, 'src/runtime');
  await cp(join(hostRoot, 'src/scenario/scenario.mbt'), join(runtimeRoot, 'scenario.mbt'));
  await cp(join(coreRoot, 'src/node_host_conformance/fixture.generated.mbt'),
    join(runtimeRoot, 'fixture.generated.mbt'));
  const runtimeManifest = join(runtimeRoot, 'moon.pkg');
  const aliases = new Map();
  for (const path of [runtimeManifest, join(hostRoot, 'src/scenario/moon.pkg')]) {
    for (const entry of manifestImports(await readFile(path, 'utf8'))) {
      assert.ok(!aliases.has(entry.alias) || aliases.get(entry.alias) === entry.path,
        `Conflicting fixture import alias: ${entry.alias}`);
      aliases.set(entry.alias, entry.path);
    }
  }
  await writeFile(runtimeManifest, 'supported_targets = "js"\n' +
    'pkgtype(kind: "foreign_library")\nimport {\n' +
    [...aliases].map(([alias, path]) => `  ${JSON.stringify(path)} @${alias},\n`).join('') + '}\n');
  run('moon', ['build', '--frozen', '--target', 'js', '--release', '--target-dir', outputRoot,
    'src/runtime'], hostRoot, process.env);
  // The owned output directory was empty and this command requested exactly
  // one foreign-library target. Never select an older repository executable.
  const runtimes = (await filesBelow(outputRoot)).filter(path => basename(path) === 'runtime.js');
  assert.equal(runtimes.length, 1, 'one newly built Host runtime');
  await mkdir(join(hostRoot, 'dist'));
  const entry = join(hostRoot, 'entry.mjs');
  const modulePath = path => JSON.stringify(relative(hostRoot, path).split(sep).join('/'));
  await writeFile(entry,
    `import * as moon from ${modulePath(runtimes[0])};\nexport {moon};\n` +
    `export {installStrategyContributions} from './adapters/installed/strategy.generated.mjs';\n` +
    `export {bindLocalJsHost} from ${modulePath(join(coreRoot, 'adapters/host-common/local-js-host.mjs'))};\n` +
    `export {withScopedStrategy} from ${modulePath(join(coreRoot, 'adapters/host-common/scoped-strategy.mjs'))};\n` +
    `export {runtimeCore} from ${modulePath(join(coreRoot, 'adapters/host-common/runtime-core.mjs'))};\n` +
    `export {checked} from ${modulePath(join(coreRoot, 'adapters/host-common/runtime-result.mjs'))};\n`);
  // Preserve Node's URL semantics for relative ESM specifiers, and keep the
  // bundler inside the explicit package roots before it reads imported bytes.
  const roots = [coreRoot, connectorRoot, hostRoot, outputRoot];
  const resolveOwned = path => {
    const owner = roots.find(root => inside(root, path));
    assert.ok(owner, `Escaped fixture build dependency: ${path}`);
    let current = owner;
    for (const part of relative(owner, path).split(sep)) {
      current = join(current, part);
      assert.equal(lstatSync(current).isSymbolicLink(), false, `Linked fixture input: ${current}`);
    }
    assert.ok(lstatSync(path).isFile(), `Nonregular fixture input: ${path}`);
    return path;
  };
  const bundled = await build({entryPoints: [entry], bundle: true, platform: 'node', format: 'esm',
    target: 'node22', minify: true, write: false, metafile: true,
    outfile: join(hostRoot, 'dist/index.mjs'), plugins: [{name: 'owned-fixture-inputs',
      setup(builder) {
        builder.onResolve({filter: /.*/}, args => {
          if (isBuiltin(args.path)) return {path: args.path, external: true};
          if (args.kind === 'entry-point') return {path: resolveOwned(resolve(args.path))};
          assert.ok(/^\.\.?\//u.test(args.path), `Unpinned fixture dependency: ${args.path}`);
          const url = new URL(args.path, pathToFileURL(args.importer));
          assert.equal(url.search + url.hash, '', 'Only a concrete module file is selected');
          return {path: resolveOwned(fileURLToPath(url))};
        });
      },
    }]});
  for (const path of Object.keys(bundled.metafile.inputs)) resolveOwned(resolve(path));
  assert.equal(bundled.outputFiles.length, 1);
  await writeFile(join(hostRoot, 'dist/index.mjs'), bundled.outputFiles[0].contents);
  await writeFile(join(hostRoot, 'build-receipt.json'), JSON.stringify({
    runtimePath: relative(outputRoot, runtimes[0]),
    runtimeSha256: sha256(await readFile(runtimes[0])),
    generatedComputeSha256: sha256(await readFile(join(hostRoot, 'src/compute/compute.generated.mbt'))),
    generatedBridgeSha256: sha256(await readFile(join(runtimeRoot, 'bridge.generated.mbt'))),
  }, null, 2) + '\n');
}

async function acceptance() {
  const scratch = await createOwnedScratch({parent: join(repository, '..', '.codex-scratch'),
    prefix: 'external-compute-pack-', label: 'packed external Compute fixture'});
  const coreRoot = join(scratch.path, 'core'), hostRoot = join(scratch.path, 'host');
  const sourceRoot = join(scratch.path, 'connector-source'), buildDeps = join(scratch.path, 'build-dependencies');
  const consumer = join(scratch.path, 'consumer'), artifacts = join(scratch.path, 'artifacts');
  for (const path of [coreRoot, buildDeps, consumer, artifacts]) await mkdir(path);
  const environment = Object.fromEntries(Object.entries(process.env)
    .filter(([key]) => !key.startsWith('ACTQL_') && key !== 'NODE_PATH'));
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
    await mkdir(dirname(target), {recursive: true});
    await writeFile(target, bytes);
    sourceHashes.push([path, sha256(bytes)]);
  }
  initializeNormalPackSourceIndex(coreRoot, sourceHashes.map(([path]) => path));
  await symlink(join(repository, 'node_modules'), join(coreRoot, 'node_modules'), 'dir');
  const fixture = join(coreRoot, 'scripts/fixtures/external-compute');
  await cp(join(fixture, 'external-numeric'), sourceRoot, {recursive: true});
  await cp(join(fixture, 'compute-host'), hostRoot, {recursive: true});
  const pack = async root => {
    const metadata = parseNpmPackJson(run('npm', normalNpmPackJsonArgs(['pack', '--offline', '--json', '--pack-destination', artifacts]),
      root, environment, 180000))[0];
    const path = join(artifacts, metadata.filename), bytes = await readFile(path);
    assert.equal(metadata.integrity, 'sha512-' + createHash('sha512').update(bytes).digest('base64'));
    return {path, name: metadata.name, sha256: sha256(bytes), integrity: metadata.integrity};
  };
  const connectorPack = await pack(sourceRoot);
  await writeFile(join(buildDeps, 'package.json'), '{"private":true,"type":"module"}\n');
  run('npm', ['install', '--ignore-scripts', '--offline', '--no-audit', '--no-fund', '--no-save',
    connectorPack.path], buildDeps, environment);
  const connectorRoot = realpathSync(join(buildDeps, 'node_modules/@fixture/external-numeric'));
  assert.ok(inside(buildDeps, connectorRoot));
  await writeFile(join(scratch.path, 'moon.work'), 'members = [\n' +
    [coreRoot, connectorRoot, hostRoot].map(path => `  ${JSON.stringify(relative(scratch.path, path))},\n`).join('') + ']\n');
  const options = {coreRoot, connectorRoot, hostRoot, outputRoot: join(scratch.path, 'compiled')};
  await writeFile(join(hostRoot, 'build.mjs'),
    `import {buildExternalComputeFixture} from ${quote(join(coreRoot, 'scripts/test-packed-external-connector.mjs'))};\n` +
    `await buildExternalComputeFixture(${JSON.stringify(options)});\n`);
  const hostPack = await pack(hostRoot);
  for (const [path, expected] of sourceHashes) {
    assert.equal(sha256(await readFile(join(coreRoot, path))), expected, `Changed Core build input: ${path}`);
  }
  assert.doesNotMatch(await readFile(join(coreRoot, 'moon.mod'), 'utf8'), /fixture\//);
  await writeFile(join(consumer, 'package.json'), '{"private":true,"type":"module"}\n');
  run('npm', ['install', '--ignore-scripts', '--offline', '--no-audit', '--no-fund', '--no-save',
    connectorPack.path, hostPack.path], consumer, environment);
  const hostEntry = join(consumer, 'node_modules/@fixture/compute-host/dist/index.mjs');
  const graph = buildSync({entryPoints: [hostEntry], bundle: true, platform: 'node',
    format: 'esm', packages: 'external', metafile: true, write: false});
  for (const [path, input] of Object.entries(graph.metafile.inputs)) {
    assert.ok(inside(consumer, realpathSync(resolve(path))), `Consumer source fallback: ${path}`);
    assert.ok(input.imports.filter(entry => entry.external).every(entry => isBuiltin(entry.path)),
      `Unbundled fixture dependency: ${path}`);
  }
  await cp(join(fixture, 'consumer.mjs'), join(consumer, 'verify.mjs'));
  await writeFile(join(consumer, 'acceptance.mjs'),
    'import {verifyExternalComputeFixture} from "./verify.mjs";\n' +
    'globalThis.fetch = () => { throw new Error("UnexpectedFixtureNetwork"); };\n' +
    'const packed = await import("@fixture/compute-host");\n' +
    'console.log("EXTERNAL_COMPUTE_ACCEPTANCE", JSON.stringify(await verifyExternalComputeFixture(packed)));\n');
  const output = run(process.execPath, ['acceptance.mjs'], consumer, environment, 30000);
  assert.match(output, /EXTERNAL_COMPUTE_ACCEPTANCE/);
  console.log(output.trim());
  console.log('EXTERNAL_COMPUTE_PACKS', JSON.stringify({
    sourceRevision: run('git', ['rev-parse', 'HEAD'], repository, environment).trim(),
    copiedSourceSha256: sha256(JSON.stringify(sourceHashes)),
    packages: [connectorPack, hostPack].map(({name, sha256, integrity}) => ({name, sha256, integrity})),
    build: JSON.parse(await readFile(join(hostRoot, 'build-receipt.json'), 'utf8')),
  }));
  scratch.passed();
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) await acceptance();
