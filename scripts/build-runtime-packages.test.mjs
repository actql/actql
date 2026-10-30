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
  const steps = Object.values(workflow.jobs).flatMap(job => job.steps ?? []);
  const selected = steps.filter(step => step.name === 'Test durable Remote Site dispatch admission');
  assert.equal(selected.length, 1);
  assert.deepEqual(selected[0].run.split(' && '), ['npm run check:remote-site-runtime',
    'node --test packages/coordinator-core/holder-terminal.test.mjs']);
  const gate = JSON.parse(readFileSync(join(root, 'package.json'), 'utf8')).scripts['check:remote-site-runtime'];
  assert(gate.includes('node scripts/build-runtime-packages.mjs coordinator-core'));
});

// Independent command inventory: runtime preparation keeps its build, type,
// unit and asset checks. Moving packed acceptance to another CI job also
// requires the fixed scheduling assertions in client-ci.test.mjs.
const expectedGates = {
  "check:remote-site-runtime": [
    "moon build --target js --release src/connectors_builtin_node src/connectors/github/host_node src/connectors/notion/host_node src/connectors/slack/host_node",
    "node scripts/build-runtime-packages.mjs coordinator-core",
    "node --test packages/coordinator-core/payload.test.mjs packages/coordinator-core/cancellation.test.mjs packages/coordinator-core/bundle-retention.test.mjs adapters/host-common/remote-bundle-control.test.mjs adapters/host-common/remote-coordinator-abi.test.mjs adapters/host-common/remote-credential-control.test.mjs adapters/host-common/remote-dispatch-wire.test.mjs adapters/host-common/remote-transfer-control.test.mjs adapters/host-node/sqlite-coordinator-journal.test.mjs adapters/host-node/remote-site-coordinator.test.mjs adapters/host-node/outbound-site-gateway.test.mjs adapters/site-node/runtime-bundle-operations.test.mjs adapters/site-node/runtime-bundle-store.test.mjs adapters/site-node/sqlite-credential-journal.test.mjs adapters/site-node/sqlite-dispatch-journal.test.mjs adapters/site-node/sqlite-transfer-journal.test.mjs adapters/site-node/sqlite-transfer-store-journal.test.mjs adapters/site-node/https-credential-resource.test.mjs adapters/connectors/github/test/github-issue-read.test.mjs adapters/site-node/https-direct-transfer.test.mjs adapters/site-node/https-transfer-store.test.mjs adapters/site-node/remote-dispatch-runtime.test.mjs adapters/site-node/remote-standard-direct-execution.test.mjs adapters/site-node/https-agent.test.mjs adapters/site-node/https-agent-authorization.test.mjs",
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
    "node --test scripts/owned-scratch.test.mjs scripts/packed-client-packages.test.mjs scripts/dbt-compat-judge.test.mjs scripts/sga-surface-checker.test.mjs scripts/infer-owner-checker.test.mjs scripts/generate-client-publication-wire.test.mjs scripts/generate-client-host-wire.test.mjs packages/client-wire/index.test.mjs packages/sdk/index.test.mjs packages/sdk/host-port.test.mjs packages/sdk/result-description.test.mjs packages/sdk/http-redirect.test.mjs packages/sdk/checkpoints.test.mjs adapters/host-node/remote-checkpoint-host.test.mjs adapters/host-node/client-effect-checkpoints.test.mjs adapters/host-node/installed-effect-site.test.mjs adapters/host-node/acquired-effect-computation.test.mjs adapters/host-node/remote-acquisition-checkpoint.test.mjs adapters/host-node/embedded-installation.test.mjs adapters/host-node/installed-infer.test.mjs adapters/host-node/installed-infer-capture.test.mjs adapters/host-common/result-access-snapshot.test.mjs adapters/host-common/result-description.test.mjs adapters/host-node/client-check.test.mjs adapters/host-node/source-selector-check.test.mjs adapters/host-node/client-http.test.mjs adapters/host-node/in-process-client.test.mjs adapters/host-node/client-cancel-response-loss.test.mjs adapters/host-node/client-dispatch-owner.test.mjs adapters/host-node/installed-host-cleanup.test.mjs adapters/host-node/client-request-journal.test.mjs adapters/host-node/client-request-lookup.test.mjs adapters/host-node/client-run-attach.test.mjs adapters/host-node/client-program-bridge.test.mjs adapters/host-node/local-values-plan.test.mjs",
    "node scripts/test-node-client-package.mjs",
    "node scripts/test-packed-client-checkpoint.mjs",
    "moon build --target native --release src/cmd/native_client",
    "node scripts/test-native-client.mjs"
  ],
  "check:run-host-core": [
    "node scripts/build-runtime-packages.mjs run-host-core coordinator-core",
    "npm run check:run-host-types",
    "node --test packages/run-host-core/index.test.mjs packages/run-host-core/schema-field-order.test.mjs packages/run-host-core/checkpoints.test.mjs adapters/host-common/publication-action.test.mjs adapters/host-common/result-access-clock.test.mjs adapters/host-common/result-delivery.test.mjs",
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
  refuseInterfaces = false, normalCli = false, temporaryParent = tmpdir()} = {}) {
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
    if (path !== 'scripts/check-interface-owners.mjs') {
      put(directory, path, readFileSync(join(root, path)));
    }
  }
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
  if (${JSON.stringify(normalCli)}) {
    record({normalCli: true});
    process.argv = [process.execPath, 'scripts/build-runtime-packages.mjs', ...${JSON.stringify(requested)}];
    await import('./scripts/build-runtime-packages.mjs');
  } else {
    const {prepareRuntimePackages} = await import('./scripts/build-runtime-packages.mjs');
    await prepareRuntimePackages(${JSON.stringify(requested)}, {
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

// The current Graph registration adds these three acceptance checks. Keep the
// predecessor command inventory independent, and require the exact additions
// at their registered positions rather than ignoring arbitrary extra checks.
const distribution = expectedGates['check:distribution-client'];
// Preserve main's typed-JSON input regressions in the registered command.
distribution[3] = distribution[3].replace(
  'node --test scripts/owned-scratch.test.mjs ',
  'node --test scripts/typed-json-literal-preparation.test.mjs scripts/typed-json-literal-public.test.mjs scripts/owned-scratch.test.mjs ',
).replace(
  'adapters/host-node/remote-acquisition-checkpoint.test.mjs ',
  'adapters/host-node/remote-acquisition-checkpoint.test.mjs adapters/host-node/acquired-chain-capacity.test.mjs ',
);
distribution[3] = distribution[3].replace(
  'scripts/packed-client-packages.test.mjs ',
  'scripts/packed-client-packages.test.mjs scripts/graph-composition-fixture.test.mjs ',
);
distribution[3] = distribution[3].replace(
  'scripts/infer-owner-checker.test.mjs ',
  'scripts/infer-owner-checker.test.mjs scripts/graph-surface-checker.test.mjs scripts/graph-public-host.test.mjs ',
);
distribution.splice(5, 0, 'node scripts/test-packed-graph.mjs');

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

// Workspace assertion checks remain in main's existing distribution gate.
distribution[3] = distribution[3].replace(
  'adapters/host-node/in-process-client.test.mjs ',
  'adapters/host-node/in-process-client.test.mjs adapters/host-node/client-workspace-binding.test.mjs adapters/host-node/client-workspace-installed.test.mjs ',
);

// Original-attempt recovery shares that runtime and distribution job.
distribution[3] = distribution[3].replace(
  'adapters/host-node/client-read-progress.test.mjs ',
  'adapters/host-node/client-read-progress.test.mjs adapters/host-node/client-read-opening.test.mjs adapters/host-node/client-read-run-capacity.test.mjs adapters/host-node/client-values-row-limit.test.mjs adapters/host-node/client-values-capacity-custody.test.mjs ',
);

// Model Checkpoint signing reuses the prepared SDK/Host distribution gate.
// Preserve the independently fixed command inventory and every existing test.
distribution[3] = distribution[3].replace(
  'packages/sdk/checkpoints.test.mjs ',
  'packages/sdk/checkpoints.test.mjs packages/sdk/model-checkpoints.test.mjs ',
);

// Installed Model restore reuses the existing build and distribution gate.
distribution[3] = distribution[3].replace(
  'adapters/host-node/installed-infer-capture.test.mjs ',
  'adapters/host-node/installed-infer-capture.test.mjs adapters/host-node/model-resume-public.test.mjs adapters/host-node/model-resume-effect-public.test.mjs adapters/local-node/model-pause.test.mjs ',
);

// Model approval sequencing uses the same runtime build and distribution job.
// Keep these adapter regressions separate from public packed acceptance.
distribution[3] = distribution[3].replace(
  'adapters/host-node/client-dispatch-owner.test.mjs ',
  'adapters/host-node/client-dispatch-owner.test.mjs adapters/host-node/infer-operation-approval.test.mjs adapters/host-node/client-confirmed-cancellation.test.mjs adapters/host-node/infer-dispatch-waiting.test.mjs ',
);

// Main's Effect outcome explanation retains its existing mutation gate.
distribution[3] = distribution[3].replace(
  'adapters/host-node/client-cancel-response-loss.test.mjs ',
  'adapters/host-node/client-cancel-response-loss.test.mjs adapters/host-node/client-effect-uncertainty.test.mjs ',
);

// Scoped Owner observations reuse the existing distribution gate. Keep its
// independently authored command inventory and avoid a second packed producer.
distribution[3] = distribution[3].replace(
  'adapters/host-node/client-effect-uncertainty.test.mjs ',
  'adapters/host-node/client-effect-uncertainty.test.mjs adapters/host-node/client-owner-cursor.test.mjs adapters/host-node/client-owner-observations.test.mjs adapters/host-node/client-owner-observations-public.test.mjs adapters/host-node/sqlite-effect-history-page.test.mjs packages/client-wire/owner-observations.test.mjs packages/sdk/owner-observations.test.mjs ',
);

// The issued-retention original regression is part of the existing prepared
// distribution gate. Pin its one intended addition independently of the
// package command, retaining the exact inventory and duplicate rejection.
distribution[3] += ' adapters/host-node/local-values-plan-policy.test.mjs';

// Main's submission custody and mutation registrations remain mandatory.
// Keep their exact independent inventory when integrating Model approval.
distribution[3] = distribution[3].replace(
  'adapters/host-node/client-cancel-response-loss.test.mjs ',
  'adapters/host-node/client-submission-input.test.mjs adapters/host-node/client-cancel-response-loss.test.mjs ',
);
distribution.splice(4, 0, 'node scripts/test-packed-read-opening.mjs',
  'node scripts/check-read-row-mutations.mjs',
  'node scripts/check-submission-input-mutations.mjs',
  'node scripts/check-effect-uncertainty-mutations.mjs');

// Retain main's reviewed registration order, including refusal settlement,
// alongside the independent actual 121-row read regressions.
distribution[3] = distribution[3].replace(
  'adapters/host-node/remote-checkpoint-host.test.mjs ',
  'adapters/host-node/installed-check-environment.test.mjs adapters/host-node/installed-host-policy.test.mjs adapters/host-node/remote-checkpoint-host.test.mjs ',
);
distribution[3] += ' packages/sdk/delivery-observation.test.mjs adapters/host-node/client-delivery-observation.test.mjs adapters/host-node/effect-partial-refusal.test.mjs packages/sdk/request-observation.test.mjs';

// Preserve main's response-capture regression and add the optional-dependency
// boundaries to the existing prepared distribution gate, without another job.
distribution[3] += ' packages/sdk/response-capture.test.mjs';
distribution[3] = distribution[3].replace(
  'scripts/packed-client-packages.test.mjs ',
  'scripts/packed-client-packages.test.mjs scripts/packed-package-boundaries.test.mjs ',
).replace(
  'adapters/host-node/embedded-installation.test.mjs ',
  'adapters/host-node/duckdb-import-boundary.test.mjs adapters/host-node/embedded-installation.test.mjs ',
);
distribution.splice(distribution.indexOf('node scripts/test-node-client-package.mjs'),
  0, 'node scripts/test-packed-local-without-duckdb.mjs');

// Preserve already-adopted Graph and cancellation registrations. The old
// inventory was independently reproduced as stale on the unchanged base.
distribution[3] = distribution[3].replace(
  'scripts/packed-client-packages.test.mjs ',
  'scripts/packed-client-packages.test.mjs scripts/packed-graph-host-dependencies.test.mjs ',
).replace('packages/client-wire/index.test.mjs ',
  'packages/client-wire/index.test.mjs packages/client-wire/cancel-identity.test.mjs '
).replace('packages/sdk/index.test.mjs ',
  'packages/sdk/index.test.mjs packages/sdk/cancel-identity.test.mjs '
).replace('adapters/host-node/client-cancel-response-loss.test.mjs ',
  'adapters/host-node/client-cancel-response-loss.test.mjs adapters/host-node/client-cancellation-attempt-public.test.mjs adapters/host-node/client-cancellation-operation.test.mjs adapters/host-node/client-cancellation-public.test.mjs adapters/host-node/client-cancellation-attempt-installed.test.mjs adapters/host-node/client-effect-cancellation-public.test.mjs ');
// Workspace packed acceptance follows the original Node package boundary.
distribution.splice(distribution.indexOf('node scripts/test-node-client-package.mjs') + 1,
  0, 'node scripts/test-packed-workspace-connection.mjs');
expectedGates['check:local-node-assets'].splice(3, 0,
  'node --test scripts/local-node-package-inputs.test.mjs scripts/local-node-external-package-inputs.test.mjs scripts/local-node-table-assets.test.mjs',
  'tsc --noEmit --strict --module NodeNext --moduleResolution NodeNext --target ES2022 packages/local-node/connector-installation.typecheck.mts');
expectedGates['check:local-node-assets'].push('node scripts/test-packed-installed-connectors.mjs',
  'node scripts/test-packed-external-connector.mjs', 'node scripts/test-packed-external-installed.mjs');

// The epoch-bound submission chain uses the same prepared distribution gate.
distribution[3] += ' adapters/host-node/client-submission-epoch.test.mjs adapters/host-node/client-submitted-intent.test.mjs adapters/host-node/client-submission.test.mjs adapters/host-node/submission-epoch-public.test.mjs adapters/host-node/synthetic-held-values-public.test.mjs packages/sdk/submission-identity.test.mjs';
// Invocation-bound Submit cases adopted with #1106 remain registered too.
distribution[3]=distribution[3].replace('adapters/host-node/client-submission.test.mjs ',
  'adapters/host-node/client-submission.test.mjs adapters/host-node/client-submission-attempt.test.mjs ');
distribution[3]+=' packages/sdk/submission-attempt.test.mjs';


// Retain adopted composed-INFER, evaluation and submission-check coverage at
// its exact registered positions, alongside every predecessor command.
distribution[3] = distribution[3].replace(
  'node --test ',
  'node --test adapters/host-node/installed-composed-infer-run.test.mjs adapters/host-node/composed-infer-provider.test.mjs adapters/host-node/infer-evaluation-evidence.test.mjs examples/infer-evaluation/evaluate.test.mjs examples/infer-evaluation/compare-source-instructions.test.mjs examples/infer-evaluation/capture-sink.test.mjs ',
).replace(
  'packages/client-wire/index.test.mjs ',
  'packages/client-wire/index.test.mjs packages/client-wire/submission-check-semantics.test.mjs packages/client-wire/submission-check-observations.test.mjs packages/sdk/structured-program-check-observations.test.mjs packages/sdk/scoped-authoring-check.test.mjs ',
);
distribution.splice(distribution.indexOf('node scripts/check-submission-input-mutations.mjs') + 1,
  0, 'node scripts/check-submission-check-observation-mutations.mjs');

// Preserve the additional public registrations at their adopted positions.
// These are fixed independent expectations, not a projection of package.json.
expectedGates['check:remote-site-runtime'][2] = expectedGates['check:remote-site-runtime'][2]
  .replace('adapters/connectors/github/test/github-issue-read.test.mjs ',
    'adapters/connectors/slack/test/remaining-row-requests.test.mjs adapters/connectors/notion/test/remaining-row-requests.test.mjs adapters/connectors/calendar/test/calendar-events-pages.test.mjs adapters/connectors/github/test/github-issue-read.test.mjs adapters/connectors/github/test/github-comment-read.test.mjs adapters/connectors/github/test/github-installed-comment-source.test.mjs adapters/connectors/github/test/github-installed-comment-outcome.test.mjs adapters/connectors/github/test/github-comment-marker.test.mjs ');
expectedGates['check:run-host-core'][2] +=
  ' packages/run-host-core/effect-checkpoint-retention.test.mjs packages/run-host-core/effect-checkpoint-binding.test.mjs packages/run-host-core/effect-publication.test.mjs packages/run-host-core/effect-publication.runtime.test.mjs';
expectedGates['check:run-host-core'][2] +=
  ' packages/run-host-core/review-binding-facts.test.mjs';
expectedGates['check:run-host-core'][2] +=
  ' packages/run-host-core/source-preparation.test.mjs';
distribution[3] = distribution[3]
  .replace('node --test ',
    'node --test adapters/host-common/file-media-type-consumers.test.mjs adapters/host-common/source-response-custody.test.mjs adapters/host-node/installed-family-content.test.mjs scripts/packed-public-query-profile.test.mjs adapters/host-node/client-full-join-refusal.test.mjs ')
  .replace('adapters/host-node/installed-composed-infer-run.test.mjs ',
    'adapters/host-node/installed-composed-infer-run.test.mjs adapters/host-common/strategy-usage.test.mjs adapters/host-node/ledger-usage-consumers.test.mjs ')
  .replace('adapters/host-node/installed-effect-site.test.mjs ',
    'adapters/host-node/installed-effect-site.test.mjs adapters/connectors/notion/test/source-configuration-reader.test.mjs adapters/host-node/installed-update-targets.test.mjs adapters/host-node/recovered-command-content.test.mjs adapters/connectors/local/host/local-file-store-declaration.actual.test.mjs adapters/connectors/local/host/local-file-store-driver.test.mjs adapters/connectors/local/host/local-file-store-target.test.mjs ')
  .replace('adapters/host-node/acquired-effect-computation.test.mjs ',
    'adapters/host-node/acquired-effect-computation.test.mjs adapters/host-node/acquired-effect-installed-capacity.test.mjs adapters/host-node/acquired-effect-source-binding.test.mjs ')
  .replace('adapters/host-node/client-check.test.mjs ',
    'adapters/host-node/client-check.test.mjs adapters/host-node/client-publication-limit-projection.test.mjs adapters/local-node/managed-failure-public.test.mjs adapters/host-node/client-result-alias-routing.test.mjs adapters/host-node/client-result-publication-envelope.test.mjs ')
  .replace('adapters/host-node/client-values-row-limit.test.mjs ',
    'adapters/host-node/client-values-row-limit.test.mjs adapters/host-node/client-values-join-profile.test.mjs adapters/host-node/client-sql-array-struct.test.mjs adapters/host-node/client-values-fragment-capacity.test.mjs ')
  .replace('adapters/host-node/client-request-journal.test.mjs ',
    'adapters/host-node/client-request-journal.test.mjs adapters/host-node/ordinary-source-binding.test.mjs adapters/host-node/client-mock-source-occurrences.test.mjs adapters/host-node/embedded-values-cleanup.test.mjs adapters/local-node/managed-output-custody.test.mjs ')
  .replace('adapters/host-node/public-source-preparation.test.mjs ',
    'adapters/host-node/public-source-preparation.test.mjs adapters/host-node/public-store-source-preparation.test.mjs ')
  .replace('adapters/host-node/client-submission.test.mjs ',
    'adapters/host-node/client-submission.test.mjs adapters/host-node/source-request-lineage.test.mjs adapters/host-node/journal-lifecycle-limits.test.mjs adapters/host-node/client-pre-admission-refusal.test.mjs ')
  .replace('adapters/host-node/client-submission-attempt.test.mjs ',
    'adapters/host-node/client-submission-attempt.test.mjs adapters/host-node/client-submission-operation.test.mjs ');
distribution[3] += ' scripts/connector-authoring.cli.test.mjs';
distribution[3] += ' scripts/fixtures/external-rest/preparation.test.mjs';

for (const files of [
  ['adapters/host-node/client-null-context.test.mjs'],
  ['adapters/host-node/public-text-time.test.mjs'],
  ['adapters/host-node/client-relational-composition.test.mjs'],
  ['adapters/host-node/client-right-join.test.mjs'],
  ['adapters/host-node/client-audited-capabilities.test.mjs'],
  ['adapters/host-node/client-publication-capacity.test.mjs'],
  ['adapters/host-node/local-preparation-custody.test.mjs'],
  ['adapters/host-node/client-preparation-custody-public.test.mjs'],
  ['adapters/host-node/client-result-schema-budget.test.mjs'],
  ['adapters/host-node/client-publication-plan-original.test.mjs'],
  ['adapters/host-node/ordinary-source-producer-lifetime.test.mjs'],
  ['scripts/verify-local-source-runtime.test.mjs'],
  ['scripts/preparation-context-carrier-layout.test.mjs'],
  ['adapters/host-node/preparation-root-bridge.test.mjs'],
  ['adapters/host-node/submission-snapshot-publication.test.mjs'],
  ['adapters/host-node/closed-values-own-data-scan.test.mjs'],
  ['adapters/host-node/local-preparation-registry.test.mjs'],
  ['adapters/host-node/preparation-host-custody.test.mjs'],
  ['adapters/host-node/client-large-input-public.test.mjs', 'adapters/host-node/local-values-policy-original.test.mjs',
    'adapters/host-node/host-result-extent.test.mjs', 'adapters/host-node/client-join-scale-public.test.mjs'],
  ['adapters/host-node/preparation-journal-failure-public.test.mjs', 'adapters/host-node/preparation-initial-failure-public.test.mjs'],
  ['adapters/host-node/ordinary-preparation-cut-retry.test.mjs'],
  ['scripts/preparation-closed-values-plan-controls.test.mjs'],
  ['adapters/store-local/publication-contract-node-bound.test.mjs'],
  ['scripts/preparation-closed-values-layout.test.mjs'],
  ['scripts/preparation-closed-values-graph-layout.test.mjs'],
  ['scripts/preparation-closed-values-contract-layout.test.mjs'],
  ['adapters/host-node/client-numeric-scale-public.test.mjs'],
  ['adapters/host-node/preparation-capacity-refusal.test.mjs'],
  ['scripts/preparation-intent-lifetime.test.mjs'],
  ['adapters/host-node/installed-sequence-infer-subset.test.mjs', 'adapters/host-node/client-compilation-original.test.mjs',
    'adapters/host-node/preparation-compilation-cold-open-public.test.mjs', 'scripts/preparation-compilation-call-controls.test.mjs',
    'scripts/preparation-compilation-projector-controls.test.mjs', 'adapters/host-node/client-snapshot-output-envelope.test.mjs',
    'adapters/host-node/client-captured-context-original.test.mjs'],
  ['scripts/scalar-snapshot-projector-layout.test.mjs', 'scripts/capture-projector-layout.test.mjs',
    'adapters/host-node/publication-currentness-boundary.test.mjs', 'adapters/host-node/client-publication-preparation-phase.test.mjs',
    'adapters/host-node/publication-validation-close-public.test.mjs'],
  ['adapters/host-node/publication-snapshot-original-public.test.mjs'],
  ['adapters/host-node/finalization-scratch-cut-public.test.mjs', 'adapters/connectors/calendar/test/installed-calendar-source.test.mjs'],
  ['adapters/host-node/installed-content-family-custody.test.mjs'],
]) distribution.push(`node scripts/local-checks.mjs test node -- ${files.join(' ')}`);

test('explicit fixture interface admission is awaited for the physical root and selected manifests', t => {
  const {result, calls, directory} = run(t, ['coordinator-core', 'transfer-core', 'coordinator-core']);
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(calls, expectedCalls(['coordinator-core', 'transfer-core'], directory));
  assert.equal(realpathSync(calls[0].root), directory);
});

test('original interface refusal prevents every compiler and builder call', t => {
  const {result, calls, directory} = run(t, ['local-node', 'run-host-core'], {refuseInterfaces: true});
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /Original fixture interface admission refused/u);
  assert.deepEqual(calls, [expectedCalls(['local-node', 'run-host-core'], directory)[0],
    {originalInterfaceRefusal: true}]);
});

test('normal runtime CLI selects its real interface checker instead of fixture admission', t => {
  const {result, calls} = run(t, ['transfer-core'], {normalCli: true});
  assert.notEqual(result.status, 0);
  // The isolated scheduling fixture deliberately has no real Owner checker
  // or approvals. Normal CLI selection must load that missing dependency.
  assert.match(result.stderr, /ERR_MODULE_NOT_FOUND/u);
  assert.match(result.stderr, /scripts\/check-interface-owners\.mjs/u);
  assert.deepEqual(calls, [{normalCli: true}]);
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
    assert.deepEqual(calls, expectedCalls(Object.keys(packages), directory).slice(0, 5));
    assert.equal(readFileSync(join(directory, `packages/run-host-core/${wrapper}`), 'utf8'), 'stale wrapper\n');
  });
}

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
