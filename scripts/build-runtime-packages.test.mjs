import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, symlinkSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {basename, dirname, join} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import test from 'node:test';
import {buildSync} from 'esbuild';
import {parse} from 'yaml';
import {readHostBundles, generateInstallations} from './connector-node-bundles.mjs';
import {localModuleGraphInputs} from './adapter-module-graph.mjs';
import {finiteRuntimeModules} from '../adapters/workers/artifact.mjs';
// Keep the deferred-initialization regressions in the ordinary cold-pack gate.
import './deferred-function-runtime.test.mjs';
import './runtime-package-pack-json.test.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));

test('holder terminal facade runs after the existing prepared Remote Site CI gate', () => {
  const workflow = parse(readFileSync(join(root, '.github/workflows/ci.yml'), 'utf8'));
  const steps = workflow.jobs.host.steps;
  const named = name => {
    const selected = steps.filter(step => step.name === name);
    assert.equal(selected.length, 1, name);
    return selected[0];
  };
  const prepared = steps.filter(step => step.id === 'remote-site-preparation');
  assert.equal(prepared.length, 1);
  const gate = JSON.parse(readFileSync(join(root, 'package.json'), 'utf8'))
    .scripts['check:remote-site-runtime'].split(' && ');
  assert.deepEqual(gate, ['npm run prepare:remote-site-runtime',
    'npm run test:remote-site-runtime', 'node scripts/test-packed-coordinator-core.mjs']);
  assert.equal(prepared[0].run, gate[0]);
  const consumers = [named('Test durable Remote Site dispatch admission'),
    named('Test packed Remote coordinator'), named('Test original holder terminal facade')];
  assert.deepEqual(consumers.map(step => step.run), [...gate.slice(1),
    'node --test packages/coordinator-core/holder-terminal.test.mjs']);
  for (const step of consumers) {
    assert(steps.indexOf(prepared[0]) < steps.indexOf(step));
    assert.equal(step.if, "${{ !cancelled() && steps.remote-site-preparation.outcome == 'success' }}");
    assert.equal(step['continue-on-error'], undefined);
  }
});

const packages = {
  'run-host-core': {builder: 'build-run-host-core-package', args: ['--runtime-only'],
    sources: ['client_values_host_abi', 'checkpoint_runtime_node',
      'connectors_workers_bridge'],
    destination: 'packages/run-host-core/dist/client_values_host_abi.js',
    stale: 'StaleRunHostCorePackage'},
  'coordinator-core': {builder: 'build-remote-coordinator-package', args: [],
    sources: ['remote_coordinator_abi'],
    destination: 'packages/coordinator-core/dist/remote_coordinator_abi.js',
    stale: 'StaleRemoteCoordinatorPackage'},
  'transfer-core': {builder: 'build-remote-transfer-package', args: [],
    sources: ['remote_transfer_abi'],
    destination: 'packages/transfer-core/dist/remote_transfer_abi.js',
    stale: 'StaleRemoteTransferPackage'},
  'local-node': {builder: 'build-local-node-assets', args: [],
    sources: ['connectors_builtin_node', 'connectors/duckdb/host_node',
      'retained_host_bridge', 'process_host_bridge', 'checkpoint_runtime_node',
      'connectors/calendar/host_node', 'connectors/gcs/host_node',
      'connectors/github/host_node', 'connectors/gmail/host_node',
      'connectors/hubspot/host_node', 'connectors/notion/host_node',
      'connectors/salesforce/host_node', 'connectors/sheets/host_node',
      'connectors/slack/host_node'],
    destination: 'packages/local-node/_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js',
    stale: 'StaleLocalNodeAsset'},
};

function put(directory, path, contents) {
  mkdirSync(dirname(join(directory, path)), {recursive: true});
  writeFileSync(join(directory, path), contents);
}

function run(t, requested, {fail, stalePayload, wrapper, version, additionalProvider = false,
  refuseInterfaces = false, normalCli = false, missingInterfaceOwner = false, jobs, commandEntry = false, temporaryParent = tmpdir()} = {}) {
  const directory = realpathSync(mkdtempSync(join(temporaryParent, 'runtime-build-check-')));
  t.after(() => rmSync(directory, {recursive: true, force: true}));
  mkdirSync(join(directory, 'scripts'));
  // Resolve actual transitive builder imports instead of maintaining a partial
  // helper list. The one deliberately omitted checker is replaced only by the
  // explicit scheduling port below; normal CLI selection must still refuse it.
  const builderModules = localModuleGraphInputs(root, ['scripts/build-runtime-packages.mjs',
    ...Object.values(packages).map(item => `scripts/${item.builder}.mjs`)]);
  assert(builderModules.includes('scripts/check-interface-owners.mjs'));
  for (const path of builderModules) {
    assert.ok(!path.startsWith('../') && !path.startsWith('/'));
    // The unowned fixture publishes plain JS only, with no generated compiler
    // bindings. It has no generator inputs or compiler-interface approvals.
    if (missingInterfaceOwner && path === 'scripts/generate-js-compiler-bindings.mjs') continue;
    if (path !== 'scripts/check-interface-owners.mjs') {
      put(directory, path, readFileSync(join(root, path)));
    }
  }
  // Only this distinct negative uses the original real checker; the ordinary
  // scheduling controls keep their explicit port and missing-checker oracle.
  if (missingInterfaceOwner) symlinkSync(join(root, 'scripts/check-interface-owners.mjs'),
    join(directory, 'scripts/check-interface-owners.mjs'));
  put(directory, 'adapters/host-common/installed-connector-declaration.mjs',
    readFileSync(join(root, 'adapters/host-common/installed-connector-declaration.mjs')));
  put(directory, 'adapters/host-common/http-exchange.mjs',
    readFileSync(join(root, 'adapters/host-common/http-exchange.mjs'), 'utf8'));
  // Copy the actual reviewed product JS closure. Only the compiler output
  // below is synthetic; the producer still audits and bundles real adapters.
  for (const path of [...finiteRuntimeModules.filter(path => !path.startsWith('_build/')),
    'adapters/workers/build.mjs', 'adapters/workers/artifact.mjs',
    'adapters/workers/moon-runtime.mjs']) {
    put(directory, path, readFileSync(join(root, path)));
  }
  for (const entry of readHostBundles(root)) {
    for (const path of [`src/connectors/${entry.name}/host-bundle.json`,
      ...(entry.providerBundle === undefined ? [] : [`src/${entry.providerBundle}/moon.pkg`]),
      ...[entry.source, entry.effect].filter(Boolean).map(role => role.module), ...entry.assets]) {
      put(directory, path, readFileSync(join(root, path)));
    }
  }
  // Implementation inventories now resolve real transitive imports. This
  // scheduling fixture needs their complete source inputs before generation,
  // not only the installation entry file. No provider code is executed here;
  // the independently authored compiled payloads below still test each builder.
  const fixtureGraph = buildSync({
    entryPoints: readHostBundles(root).flatMap(entry => [entry.source, entry.effect]
      .filter(Boolean).map(role => role.module)),
    bundle: true, packages: 'external', platform: 'node', format: 'esm',
    metafile: true, write: false, absWorkingDir: root,
    outdir: join(root, '_build/runtime-preparation-fixture-graph'),
  });
  for (const path of Object.keys(fixtureGraph.metafile.inputs)) {
    assert.ok(!path.startsWith('../') && !path.startsWith('/'));
    put(directory, path, readFileSync(join(root, path)));
  }
  // Package import maps are part of the actual adapter source closure.
  put(directory, 'packages/sdk/package.json',
    readFileSync(join(root, 'packages/sdk/package.json')));
  if (additionalProvider) {
    put(directory, 'src/connectors/third/host-bundle.json', JSON.stringify({installation: {
      registration: 'third', revision: 'third/0.1', responseHeaders: [],
      providerBundle: 'connectors/third/host_node',
      source: {profileVersion: 'actql-installed-third-source/0.1',
        module: 'adapters/connectors/third/host/source.mjs',
        exports: {check: 'check', identityParts: 'identity', load: 'load'}}}}));
    put(directory, 'src/connectors/third/host_node/moon.pkg',
      'supported_targets = "js"\npkgtype(kind: "foreign_library")\n');
    put(directory, 'adapters/connectors/third/host/source.mjs',
      'export function check() {}\nexport function identity() {}\nexport function load() {}\n');
    put(directory, '_build/js/release/build/connectors/third/host_node/host_node.js',
      'export const third = "independent-provider-fixture";\n');
  }
  put(directory, 'adapters/connectors-builtin/installations.generated.mjs',
    generateInstallations(readHostBundles(directory),
      join(directory, 'adapters/connectors-builtin/installations.generated.mjs'), directory));
  put(directory, 'scripts/owned-contract-version-legacy.json',
    readFileSync(join(root, 'scripts/owned-contract-version-legacy.json')));
  put(directory, '.gitignore', '_build/\npackages/*/dist/\nnode_modules/\n');
  const initialized = spawnSync('git', ['init', '--quiet'], {cwd: directory});
  assert.equal(initialized.status, 0);
  // Use the real package builders and installed esbuild; only the MoonBit
  // compiler is replaced with independent tiny compiled-source fixtures.
  symlinkSync(join(root, 'node_modules'), join(directory, 'node_modules'), 'dir');
  if (missingInterfaceOwner) {
    // Independent, valid JS entrances deliberately have no Owner sidecar.
    // The normal checker must refuse them before any compiler or builder.
    for (const name of Object.keys(packages)) {
      put(directory, `packages/${name}/package.json`, JSON.stringify({
        name: `@fixture/${name}`, type: 'module', exports: './fixture-interface.mjs',
      }));
      put(directory, `packages/${name}/fixture-interface.mjs`,
        'export function runtimePreparationInput(value) { return value; }\n');
    }
  }
  for (const [name, item] of Object.entries(packages)) {
    for (const source of item.sources) {
      if (source === 'connectors_workers_bridge') continue;
      put(directory, `_build/js/release/build/${source}/${source.split('/').at(-1)}.js`,
        `export function payload() { return ${JSON.stringify(version === name
          ? 'actql-fixture/' + ['0', '2'].join('.') : `fixture-${source}`)}; }\n`);
    }
  }
  // Exact audited pinned builtin spelling, with an independent tiny ABI.
  // This fixture tests producer scheduling, not execution conformance.
  put(directory, '_build/js/release/build/connectors_workers_bridge/connectors_workers_bridge.js',
    `const _M0FPB12random__seed = () => {
  if (globalThis.crypto?.getRandomValues) {
    const array = new Uint32Array(1);
    globalThis.crypto.getRandomValues(array);
    return array[0] | 0; // Convert to signed 32
  } else {
    return Math.floor(Math.random() * 0x100000000) | 0; // Fallback to Math.random
  }
};
function payload() { return 'fixture-connectors-workers-bridge'; }
export {payload};\n`);
  const wrappers = {
    'result-access.mjs': ["export {value} from '../../packages/client-wire/index.mjs';\n",
      "export {value} from '@actql/client-wire';\n"],
    'result-delivery.mjs': ['export const delivery = 1;\n', 'export const delivery = 1;\n'],
    'managed-failure.mjs': [readFileSync(join(root, 'adapters/host-common/managed-failure.mjs'), 'utf8'),
      readFileSync(join(root, 'adapters/host-common/managed-failure.mjs'), 'utf8')],
    'publication-action.mjs': [
      'export const action = 1;\nexport const publicationAction = () => action;\n',
      'export const action = 1;\nexport const publicationAction = () => action;\n'],
  };
  for (const [path, [source, tracked]] of Object.entries(wrappers)) {
    put(directory, `adapters/host-common/${path}`, source);
    put(directory, `packages/run-host-core/${path}`, wrapper === path ? 'stale wrapper\n' : tracked);
  }
  put(directory, 'driver.mjs', `
import childProcess from 'node:child_process';
import {appendFileSync, writeFileSync} from 'node:fs';
import {syncBuiltinESMExports} from 'node:module';
const original = childProcess.execFileSync;
const record = value => appendFileSync('calls.jsonl', JSON.stringify(value) + '\\n');
childProcess.execFileSync = (command, args, options) => {
  if (command === 'git') return original(command, args, options);
  record({command: command === process.execPath ? 'node' : command, args,
    cwd: options.cwd, stdio: options.stdio});
  if (command === 'moon') return Buffer.alloc(0);
  if (command === 'python3' && ${JSON.stringify(missingInterfaceOwner)}) return original(command, args, options);
  if (command !== process.execPath) throw new Error('Unexpected subprocess');
  if (args[0] === ${JSON.stringify(fail ? `scripts/${packages[fail].builder}.mjs` : null)} &&
      args.includes('--check')) {
    writeFileSync(${JSON.stringify(fail ? stalePayload ?? packages[fail].destination : '')}, 'stale runtime\\n');
  }
  return original(command, args, options);
};
syncBuiltinESMExports();
const refusal = new Error('Original fixture interface admission refused');
try {
  if (${JSON.stringify(normalCli || missingInterfaceOwner)}) {
    record({normalCli: true});
    process.argv = [process.execPath, 'scripts/build-runtime-packages.mjs',
      ...${JSON.stringify(jobs === undefined ? [] : ['--moon-jobs', String(jobs)])}, ...${JSON.stringify(requested)}];
    await import('./scripts/build-runtime-packages.mjs');
  } else {
    const {prepareRuntimePackages,runRuntimePackageCommand} = await import('./scripts/build-runtime-packages.mjs');
    const prepare = ${JSON.stringify(commandEntry)} ? runRuntimePackageCommand : prepareRuntimePackages;
    await prepare(${JSON.stringify(commandEntry ? [...(jobs === undefined ? [] : ['--moon-jobs', String(jobs)]), ...requested] : requested)}, {
      jobs: ${JSON.stringify(jobs)},
      checkInterfaces: async (root, {manifests}) => {
        record({command: 'fixture-interface-admission', root, manifests});
        await Promise.resolve();
        if (${JSON.stringify(refuseInterfaces)}) throw refusal;
        record({fixtureInterfacesAdmitted: true});
      },
    });
  }
} catch (error) {
  if (${JSON.stringify(refuseInterfaces)}) record({originalInterfaceRefusal: error === refusal});
  throw error;
}
record({done: true});
`);
  const result = spawnSync(process.execPath, ['driver.mjs'], {
    cwd: directory, encoding: 'utf8', timeout: 30000,
  });
  assert.ok(existsSync(join(directory, 'calls.jsonl')),
    result.error?.message ?? result.stderr);
  const calls = readFileSync(join(directory, 'calls.jsonl'), 'utf8').trim().split('\n').map(JSON.parse);
  return {result, calls, directory};
}

function expectedCalls(names, directory) {
  return [{command: 'fixture-interface-admission', root: directory + '/',
    manifests: names.map(name => `packages/${name}/package.json`)},
  {fixtureInterfacesAdmitted: true},
  {command: 'moon', args: ['build', '--target', 'js', '--release',
    ...new Set(names.flatMap(name => packages[name].sources.map(source => `src/${source}`)))],
  cwd: directory + '/', stdio: 'inherit'}, ...names.flatMap(name => {
    const item = packages[name];
    return [item.args, ['--check']].map(args => ({command: 'node',
      args: [`scripts/${item.builder}.mjs`, ...args], cwd: directory + '/', stdio: 'inherit'}));
  }), {done: true}];
}



test('explicit fixture interface admission is awaited for the physical root and selected manifests', t => {
  const {result, calls, directory} = run(t, ['coordinator-core', 'transfer-core', 'coordinator-core']);
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(calls, expectedCalls(['coordinator-core', 'transfer-core'], directory));
  assert.equal(realpathSync(calls[0].root), directory);
  const bounded=run(t,['coordinator-core','transfer-core'],{jobs:1,commandEntry:true});
  assert.equal(bounded.result.status,0,bounded.result.stderr);
  const compiler=bounded.calls.find(call=>call.command==='moon');
  assert.equal(compiler.args[compiler.args.indexOf('-j')+1],'1');
  assert(compiler.args.includes('src/remote_coordinator_abi'));
  assert(compiler.args.includes('src/remote_transfer_abi'));
  assert.equal(bounded.calls[0].command,'fixture-interface-admission');
  assert.equal(bounded.calls[1].fixtureInterfacesAdmitted,true);
  assert.equal(bounded.calls.at(-1).done,true);
});

test('original interface refusal prevents every compiler and builder call', t => {
  const {result, calls, directory} = run(t, ['local-node', 'run-host-core'], {refuseInterfaces: true,jobs:1,commandEntry:true});
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /Original fixture interface admission refused/u);
  assert.deepEqual(calls, [expectedCalls(['local-node', 'run-host-core'], directory)[0],
    {originalInterfaceRefusal: true}]);
});

test('normal runtime CLI selects its real interface checker instead of fixture admission', t => {
  for(const jobs of [undefined,1]) {
  const {result, calls} = run(t, ['transfer-core'], {normalCli: true,jobs});
  assert.notEqual(result.status, 0);
  // The isolated scheduling fixture deliberately has no real Owner checker
  // or approvals. Normal CLI selection must load that missing dependency.
  assert.match(result.stderr, /ERR_MODULE_NOT_FOUND/u);
  assert.match(result.stderr, /scripts\/check-interface-owners\.mjs/u);
  assert.deepEqual(calls, [{normalCli: true}]);
  }
  const invalid=run(t,['transfer-core'],{normalCli:true,jobs:2});
  assert.notEqual(invalid.result.status,0);
  assert.match(invalid.result.stderr,/requires one selected build slot/u);
  assert.deepEqual(invalid.calls,[{normalCli:true}]);
  for(const requested of [['--moon-jobs'],['--moon-jobs','1','--moon-jobs','1','transfer-core']]) {
    const refused=run(t,requested,{normalCli:true});
    assert.notEqual(refused.result.status,0);
    assert.deepEqual(refused.calls,[{normalCli:true}]);
  }
});

test('runtime preparation preserves physical cwd and output through a symlinked temporary parent', t => {
  const scratch = realpathSync(mkdtempSync(join(tmpdir(), 'runtime-build-alias-')));
  // Both the link and its target belong to this test. Recursive removal of
  // scratch unlinks directory symlinks rather than following their targets.
  t.after(() => rmSync(scratch, {recursive: true, force: true}));
  const physicalParent = join(scratch, 'physical'), logicalParent = join(scratch, 'logical');
  mkdirSync(physicalParent);
  symlinkSync(physicalParent, logicalParent, 'dir');
  assert.notEqual(logicalParent, realpathSync(logicalParent));
  const {result, calls, directory} = run(t, ['transfer-core'], {temporaryParent: logicalParent});
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(calls, expectedCalls(['transfer-core'], directory));
  assert.equal(dirname(directory), physicalParent);
  const output = packages['transfer-core'].destination;
  const physicalOutput = join(physicalParent, basename(directory), output);
  const logicalOutput = join(logicalParent, basename(directory), output);
  assert.equal(realpathSync(logicalOutput), physicalOutput);
  assert.deepEqual(readFileSync(physicalOutput), readFileSync(logicalOutput));
  const consumer = spawnSync(process.execPath, ['--input-type=module', '-e',
    `import {payload} from ${JSON.stringify(pathToFileURL(physicalOutput).href)};
     if (payload() !== 'fixture-remote_transfer_abi') throw new Error('Wrong original payload');`],
  {encoding: 'utf8', timeout: 30000});
  assert.equal(consumer.status, 0, consumer.stderr);
});

test('runtime preparation refuses missing fixture ownership before compiling', t => {
  const {result, calls} = run(t, ['transfer-core'], {missingInterfaceOwner: true});
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /Unregistered distributed interfaces/);
  assert.equal(calls.some(value => value.command === 'moon'), false);
  assert.equal(calls.some(value => value.done), false);
});


for (const names of [[], ...Object.keys(packages).map(name => [name]),
  ['local-node', 'run-host-core'], ['run-host-core', 'coordinator-core'],
  ['local-node', 'local-node']]) {
  test(`runtime preparation generates and checks each selected builder exactly once: ${names.join(',') || 'all'}`, t => {
    const {result, calls, directory} = run(t, names);
    assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(calls, expectedCalls([...new Set(names.length ? names : Object.keys(packages))], directory));
  });
}

for (const name of Object.keys(packages)) {
  test(`${name} internal check rejects stale output and stops subsequent work`, t => {
    const {result, calls, directory} = run(t, [], {fail: name});
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, new RegExp(packages[name].stale));
    const expected = expectedCalls(Object.keys(packages), directory);
    const stop = expected.findIndex(call => call.args?.[0] === `scripts/${packages[name].builder}.mjs` &&
      call.args.includes('--check'));
    assert.deepEqual(calls, expected.slice(0, stop + 1));
  });
}

for (const wrapper of ['result-access.mjs', 'result-delivery.mjs', 'publication-action.mjs', 'managed-failure.mjs']) {
  test(`runtime-only build refuses the old tracked ${wrapper} without repairing it`, t => {
    const {result, calls, directory} = run(t, [], {wrapper});
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /StaleRunHostResultAccessService/);
    assert.deepEqual(calls, expectedCalls(Object.keys(packages), directory).slice(0, 5));
    assert.equal(readFileSync(join(directory, `packages/run-host-core/${wrapper}`), 'utf8'), 'stale wrapper\n');
  });
}

test('run-host-core includes the unchanged canonical cleanup dependency as a private package member', () => {
  const manifest = JSON.parse(readFileSync(join(root, 'packages/run-host-core/package.json')));
  assert(manifest.files.includes('managed-failure.mjs'));
  assert(!Object.hasOwn(manifest.exports, './managed-failure'));
  assert.deepEqual(readFileSync(join(root, 'packages/run-host-core/managed-failure.mjs')),
    readFileSync(join(root, 'adapters/host-common/managed-failure.mjs')));
  assert.deepEqual(readFileSync(join(root, 'packages/run-host-core/result-delivery.mjs')),
    readFileSync(join(root, 'adapters/host-common/result-delivery.mjs')));
});

test('run-host-core refuses a stale Checkpoint payload before subsequent work', t => {
  const {result, calls, directory} = run(t, ['run-host-core', 'coordinator-core'], {
    fail: 'run-host-core',
    stalePayload: 'packages/run-host-core/dist/checkpoint_runtime_node.js',
  });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /StaleRunHostCheckpointPackage/);
  assert.deepEqual(calls, expectedCalls(['run-host-core', 'coordinator-core'], directory).slice(0, 5));
});

for (const file of ['workers_finite.js', 'workers_finite_payload.js']) {
  test(`run-host-core refuses stale finite Worker ${file} before subsequent work`, t => {
    const {result, calls, directory} = run(t, ['run-host-core', 'coordinator-core'], {
      fail: 'run-host-core', stalePayload: `packages/run-host-core/dist/${file}`,
    });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /StaleRunHostWorkersFinitePackage/);
    assert.deepEqual(calls, expectedCalls(['run-host-core', 'coordinator-core'], directory).slice(0, 5));
  });
}

for (const name of Object.keys(packages)) {
  test(`${name} still rejects a generated nonbaseline contract version`, t => {
    const {result, calls} = run(t, [name], {version: name});
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /Generated owned contracts require admitted production source/);
    assert.equal(calls.some(call => call.done), false);
  });
}

for (const name of Object.keys(packages)) {
  test(`${name} retains its real prepack runtime preparation`, () => {
    const manifest = JSON.parse(readFileSync(join(root, 'packages', name, 'package.json'), 'utf8'));
    assert.equal(manifest.scripts.prepack, (name === 'local-node' ? 'node ../../scripts/generate-credential-scope-binding.mjs --check && ' : '') +
      `node ../../scripts/build-runtime-packages.mjs ${name}` +
      (name === 'local-node' ? ' && node ../../scripts/build-local-node-adapters.mjs' : ''));
  });
}

test('a new Host manifest drives both the actual build command and copied runtime', t => {
  const {result, calls, directory} = run(t, ['local-node'], {additionalProvider: true});
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(calls[2].args, ['build', '--target', 'js', '--release',
    ...packages['local-node'].sources.map(source => `src/${source}`),
    'src/connectors/third/host_node']);
  assert.match(readFileSync(join(directory,
    'packages/local-node/_build/js/release/build/connectors/third/host_node/host_node.js'),
  'utf8'), /independent-provider-fixture/);
});

test('the existing cold pack runner executes this regression and still packs all four packages', () => {
  const source = readFileSync(join(root, 'scripts/test-runtime-package-build.mjs'), 'utf8');
  assert.match(source, /'dist\/workers_finite\.js'/);
  assert.match(source, /'dist\/workers_finite_payload\.js'/);
  assert.match(source, /execFileSync\(process\.execPath, \['--test', 'scripts\/build-runtime-packages\.test\.mjs'\]/);
  assert.match(source, /for \(const \[name, paths\] of Object\.entries\(expected\)\)/);
  assert.match(source, /execFileSync\('npm', normalNpmPackJsonArgs\(\['pack', '--json', '--pack-destination', destination\]\)/);
  assert.match(source, /const metadata = parseNpmPackJson\(output\)/);
  assert.doesNotMatch(source, /--ignore-scripts/);
});
