import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {copyFileSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, symlinkSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {basename, dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';

const root = fileURLToPath(new URL('../', import.meta.url));
// Independent command inventory: runtime preparation keeps its build, type,
// unit and asset checks. Moving packed acceptance to another CI job also
// requires the fixed scheduling assertions in client-ci.test.mjs.
const expectedGates = {
  "check:remote-site-runtime": [
    "moon build --target js --release src/connectors_builtin_node src/connectors/github/host_node",
    "node scripts/build-runtime-packages.mjs coordinator-core",
    "node --test packages/coordinator-core/payload.test.mjs packages/coordinator-core/cancellation.test.mjs adapters/host-common/remote-bundle-control.test.mjs adapters/host-common/remote-coordinator-abi.test.mjs adapters/host-common/remote-credential-control.test.mjs adapters/host-common/remote-dispatch-wire.test.mjs adapters/host-common/remote-transfer-control.test.mjs adapters/host-node/sqlite-coordinator-journal.test.mjs adapters/host-node/remote-site-coordinator.test.mjs adapters/host-node/outbound-site-gateway.test.mjs adapters/site-node/runtime-bundle-operations.test.mjs adapters/site-node/runtime-bundle-store.test.mjs adapters/site-node/sqlite-credential-journal.test.mjs adapters/site-node/sqlite-dispatch-journal.test.mjs adapters/site-node/sqlite-transfer-journal.test.mjs adapters/site-node/sqlite-transfer-store-journal.test.mjs adapters/site-node/https-credential-resource.test.mjs adapters/connectors/github/test/github-issue-read.test.mjs adapters/site-node/https-direct-transfer.test.mjs adapters/site-node/https-transfer-store.test.mjs adapters/site-node/remote-dispatch-runtime.test.mjs adapters/site-node/remote-standard-direct-execution.test.mjs adapters/site-node/https-agent.test.mjs adapters/site-node/https-agent-authorization.test.mjs",
    "node scripts/test-packed-coordinator-core.mjs"
  ],
  "check:transfer-core": [
    "moon build --target js --release src/connectors_builtin_node",
    "node scripts/build-runtime-packages.mjs transfer-core",
    "node --test packages/transfer-core/index.test.mjs"
  ],
  "check:distribution-client": [
    "node scripts/build-runtime-packages.mjs local-node run-host-core",
    "node scripts/generate-client-publication-wire.mjs",
    "node scripts/generate-client-host-wire.mjs",
    "node --test scripts/owned-scratch.test.mjs scripts/packed-client-packages.test.mjs scripts/dbt-compat-judge.test.mjs scripts/sga-surface-checker.test.mjs scripts/infer-owner-checker.test.mjs scripts/generate-client-publication-wire.test.mjs scripts/generate-client-host-wire.test.mjs packages/client-wire/index.test.mjs packages/sdk/index.test.mjs packages/sdk/host-port.test.mjs packages/sdk/result-description.test.mjs packages/sdk/http-redirect.test.mjs packages/sdk/checkpoints.test.mjs adapters/host-node/remote-checkpoint-host.test.mjs adapters/host-node/client-effect-checkpoints.test.mjs adapters/host-node/installed-effect-site.test.mjs adapters/host-node/acquired-effect-computation.test.mjs adapters/host-node/remote-acquisition-checkpoint.test.mjs adapters/host-node/embedded-installation.test.mjs adapters/host-node/installed-infer.test.mjs adapters/host-node/installed-infer-capture.test.mjs adapters/host-common/result-access-snapshot.test.mjs adapters/host-common/result-description.test.mjs adapters/host-node/client-check.test.mjs adapters/host-node/client-http.test.mjs adapters/host-node/in-process-client.test.mjs adapters/host-node/client-cancel-response-loss.test.mjs adapters/host-node/client-dispatch-owner.test.mjs adapters/host-node/installed-host-cleanup.test.mjs adapters/host-node/client-request-journal.test.mjs adapters/host-node/client-request-lookup.test.mjs adapters/host-node/client-run-attach.test.mjs adapters/host-node/client-program-bridge.test.mjs adapters/host-node/local-values-plan.test.mjs",
    "node scripts/test-node-client-package.mjs",
    "node scripts/test-packed-client-checkpoint.mjs",
    "moon build --target native --release src/cmd/native_client",
    "node scripts/test-native-client.mjs"
  ],
  "check:run-host-core": [
    "node scripts/build-runtime-packages.mjs run-host-core coordinator-core",
    "npm run check:run-host-types",
    "node --test packages/run-host-core/index.test.mjs adapters/host-common/publication-action.test.mjs adapters/host-common/result-access-clock.test.mjs adapters/host-common/result-delivery.test.mjs",
    "node scripts/test-packed-run-host-core.mjs"
  ],
  "check:local-node-assets": [
    "node scripts/build-runtime-packages.mjs local-node",
    "node scripts/build-local-node-adapters.mjs",
    "node scripts/build-local-node-adapters.mjs --check",
    "node scripts/test-packed-local-node-assets.mjs"
  ]
};
const packages = {
  'run-host-core': {builder: 'build-run-host-core-package', args: ['--runtime-only'],
    sources: ['client_values_host_abi'],
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
      'connectors/salesforce/host_node', 'retained_host_bridge',
      'process_host_bridge', 'checkpoint_runtime_node'],
    destination: 'packages/local-node/_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js',
    stale: 'StaleLocalNodeAsset'},
};

function put(directory, path, contents) {
  mkdirSync(dirname(join(directory, path)), {recursive: true});
  writeFileSync(join(directory, path), contents);
}

function run(t, requested, {fail, wrapper, version, temporaryParent = tmpdir()} = {}) {
  const directory = realpathSync(mkdtempSync(join(temporaryParent, 'runtime-build-check-')));
  t.after(() => rmSync(directory, {recursive: true, force: true}));
  mkdirSync(join(directory, 'scripts'));
  for (const name of ['build-runtime-packages', 'check-owned-contract-versions',
    ...Object.values(packages).map(item => item.builder)]) {
    copyFileSync(join(root, `scripts/${name}.mjs`), join(directory, `scripts/${name}.mjs`));
  }
  put(directory, 'scripts/owned-contract-version-legacy.json',
    JSON.stringify({version: 1, baseline: '0.1', entries: []}));
  // Use the real package builders and installed esbuild; only the MoonBit
  // compiler is replaced with independent tiny compiled-source fixtures.
  symlinkSync(join(root, 'node_modules'), join(directory, 'node_modules'), 'dir');
  for (const [name, item] of Object.entries(packages)) {
    for (const source of item.sources) {
      put(directory, `_build/js/release/build/${source}/${source.split('/').at(-1)}.js`,
        `export const payload = ${JSON.stringify(version === name
          ? 'actql-fixture/' + ['0', '2'].join('.') : `fixture-${source}`)};\n`);
    }
  }
  const wrappers = {
    'result-access.mjs': ["export {value} from '../../packages/client-wire/index.mjs';\n",
      "export {value} from '@actql/client-wire';\n"],
    'result-delivery.mjs': ['export const delivery = 1;\n', 'export const delivery = 1;\n'],
    'publication-action.mjs': ['export const action = 1;\n', 'export const action = 1;\n'],
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
  record({command: command === process.execPath ? 'node' : command, args,
    cwd: options.cwd, stdio: options.stdio});
  if (command === 'moon') return Buffer.alloc(0);
  if (command !== process.execPath) throw new Error('Unexpected subprocess');
  if (args[0] === ${JSON.stringify(fail ? `scripts/${packages[fail].builder}.mjs` : null)} &&
      args.includes('--check')) {
    writeFileSync(${JSON.stringify(fail ? packages[fail].destination : '')}, 'stale runtime\\n');
  }
  return original(command, args, options);
};
syncBuiltinESMExports();
process.argv = [process.execPath, 'scripts/build-runtime-packages.mjs', ...${JSON.stringify(requested)}];
await import('./scripts/build-runtime-packages.mjs');
record({done: true});
`);
  const result = spawnSync(process.execPath, ['driver.mjs'], {
    cwd: directory, encoding: 'utf8', timeout: 30000,
  });
  const calls = readFileSync(join(directory, 'calls.jsonl'), 'utf8').trim().split('\n').map(JSON.parse);
  return {result, calls, directory};
}

function expectedCalls(names, directory) {
  return [{command: 'moon', args: ['build', '--target', 'js', '--release',
    ...names.flatMap(name => packages[name].sources.map(source => `src/${source}`))],
  cwd: directory + '/', stdio: 'inherit'}, ...names.flatMap(name => {
    const item = packages[name];
    return [item.args, ['--check']].map(args => ({command: 'node',
      args: [`scripts/${item.builder}.mjs`, ...args], cwd: directory + '/', stdio: 'inherit'}));
  }), {done: true}];
}

// The current Graph registration adds these three acceptance checks. Keep the
// predecessor command inventory independent, and require the exact additions
// at their registered positions rather than ignoring arbitrary extra checks.
const distribution = expectedGates['check:distribution-client'];
distribution[3] = distribution[3].replace(
  'scripts/packed-client-packages.test.mjs ',
  'scripts/packed-client-packages.test.mjs scripts/graph-composition-fixture.test.mjs ',
);
distribution[3] = distribution[3].replace(
  'scripts/infer-owner-checker.test.mjs ',
  'scripts/infer-owner-checker.test.mjs scripts/property-graph-surface-checker.test.mjs scripts/property-graph-public-host.test.mjs ',
);
distribution.splice(5, 0, 'node scripts/test-packed-property-graph.mjs');

// Source computation handoff regression uses the same already-prepared
// runtime and existing distribution job; it adds no package build or job.
distribution[3] = distribution[3].replace(
  'adapters/host-node/client-program-bridge.test.mjs ',
  'adapters/host-node/client-program-bridge.test.mjs adapters/host-node/public-source-preparation.test.mjs ',
);

// Public read progress uses the existing prepared SDK/Host distribution gate.
// Keep the intended file additions fixed independently of package.json.
distribution[3] = distribution[3].replace(
  'packages/sdk/index.test.mjs ',
  'packages/sdk/index.test.mjs packages/sdk/read-progress.test.mjs ',
).replace(
  'adapters/host-node/in-process-client.test.mjs ',
  'adapters/host-node/in-process-client.test.mjs adapters/host-node/client-read-progress.test.mjs ',
);

// The issued-retention original regression is part of the existing prepared
// distribution gate. Pin its one intended addition independently of the
// package command, retaining the exact inventory and duplicate rejection.
distribution[3] += ' adapters/host-node/local-values-plan-policy.test.mjs';

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
  const expected = Buffer.from('export const payload = "fixture-remote_transfer_abi";\n');
  assert.deepEqual(readFileSync(physicalOutput), expected);
  assert.deepEqual(readFileSync(logicalOutput), expected);
});

for (const [gate, commands] of Object.entries(expectedGates)) {
  test(`${gate} retains its exact registered commands without duplicate checks`, () => {
    const actual = JSON.parse(readFileSync(join(root, 'package.json'), 'utf8')).scripts[gate];
    assert.deepEqual(actual.split(' && '), commands);
  });
}

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

for (const wrapper of ['result-access.mjs', 'result-delivery.mjs', 'publication-action.mjs']) {
  test(`runtime-only build refuses the old tracked ${wrapper} without repairing it`, t => {
    const {result, calls, directory} = run(t, [], {wrapper});
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /StaleRunHostResultAccessService/);
    assert.deepEqual(calls, expectedCalls(Object.keys(packages), directory).slice(0, 3));
    assert.equal(readFileSync(join(directory, `packages/run-host-core/${wrapper}`), 'utf8'), 'stale wrapper\n');
  });
}

for (const name of Object.keys(packages)) {
  test(`${name} still rejects a generated nonbaseline contract version`, t => {
    const {result, calls} = run(t, [name], {version: name});
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /Generated runtime contract versions must remain at 0\.1/);
    assert.equal(calls.some(call => call.done), false);
  });
}

for (const name of Object.keys(packages)) {
  test(`${name} retains its real prepack runtime preparation`, () => {
    const manifest = JSON.parse(readFileSync(join(root, 'packages', name, 'package.json'), 'utf8'));
    assert.equal(manifest.scripts.prepack, `node ../../scripts/build-runtime-packages.mjs ${name}` +
      (name === 'local-node' ? ' && node ../../scripts/build-local-node-adapters.mjs' : ''));
  });
}

test('the existing cold pack runner executes this regression and still packs all four packages', () => {
  const source = readFileSync(join(root, 'scripts/test-runtime-package-build.mjs'), 'utf8');
  assert.match(source, /execFileSync\(process\.execPath, \['--test', 'scripts\/build-runtime-packages\.test\.mjs'\]/);
  assert.match(source, /for \(const \[name, paths\] of Object\.entries\(expected\)\)/);
  assert.match(source, /execFileSync\('npm', \['pack', '--json', '--pack-destination', destination\]/);
  assert.doesNotMatch(source, /--ignore-scripts/);
});
