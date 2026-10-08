// One exact producer and external installation for the focused O3 acceptance.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdir, readFile, writeFile} from 'node:fs/promises';
import {dirname, join} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {assertTestExecution, nodeTestArguments} from './test-execution.mjs';
import {withPackedQueryEvidence} from './packed-query-evidence.mjs';
import {CLIENT_PACKAGES, checkoutState, packClientPackages, packedClientPackage, packedNpmCache, pinnedDuckDBPackage} from './packed-client-packages.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
const before = checkoutState(repository);
assert.equal(before.clean, true, 'O3 packages must represent a clean fixed revision');
await withPackedQueryEvidence({scratch: join(repository, '..', '.codex-scratch'), revision: before.revision,
  githubOutput: process.env.GITHUB_OUTPUT, keepArtifacts: process.argv.includes('--keep-artifacts')},
async ({root, directory, run, recordTarball}) => {
  console.log(`Packed INFER evaluation evidence: ${directory}`);
  const env = {...process.env, npm_config_cache: packedNpmCache(root)};
  await packClientPackages({repository, destination: root, pack: async name => {
    await packedClientPackage({repository, name, destination: root,
      pack: () => run('npm', ['pack', '--pack-destination', root, '--json'],
        {cwd: join(repository, 'packages', name), env, timeout: 600000})});
    recordTarball(join(root, `actql-${name}-0.0.0-development.tgz`));
  }});
  // This optional package has no runtime prepack. The five actual runtime
  // packages above still use their normal producer and exact digest checks.
  run('npm', ['pack', '--pack-destination', root, '--json'], {cwd: join(repository, 'packages/otel-node'), env, timeout: 60000});
  const optional = join(root, 'actql-otel-node-0.0.0-development.tgz');
  recordTarball(optional);
  assert.deepEqual(checkoutState(repository), before);
  await writeFile(join(directory, 'optional-otel-package.json'), JSON.stringify({revision: before.revision,
    sha256: createHash('sha256').update(await readFile(optional)).digest('hex')}, null, 2) + '\n');
  await writeFile(join(root, 'package.json'), '{"private":true,"type":"module"}\n');
  run('npm', ['install', '--ignore-scripts', '--no-save', await pinnedDuckDBPackage(repository),
    ...[...CLIENT_PACKAGES, 'otel-node'].map(name => join(root, `actql-${name}-0.0.0-development.tgz`))],
  {cwd: root, env, timeout: 240000});
  await writeFile(join(root, 'infer-evidence.typecheck.mts'), await readFile(join(repository, 'packages/node/infer-evidence.typecheck.mts')));
  run(process.execPath, [join(repository, 'node_modules/typescript/bin/tsc'), '--noEmit', '--strict',
    '--module', 'NodeNext', '--moduleResolution', 'NodeNext', '--target', 'ES2022', 'infer-evidence.typecheck.mts'],
  {cwd: root, env, timeout: 60000});
  const files = [
    'adapters/host-node/infer-evaluation-public.test.mjs',
    'adapters/host-node/source-multi-infer-evidence-public.test.mjs',
    'adapters/host-node/source-multi-infer-evidence-worker.fixture.mjs',
    'scripts/fixtures/installed-infer-fixture.mjs',
    'scripts/fixtures/source-multi-infer-evidence.mjs',
    'scripts/fixtures/model-provider-binding-fixture.mjs',
    'scripts/test-execution-reporter.mjs',
    'examples/infer-evaluation/evaluate.mjs',
    'examples/infer-evaluation/compare-source-instructions.mjs',
    'examples/infer-evaluation/capture-sink.mjs',
    'examples/infer-evaluation/evidence-reference.mjs',
    'examples/infer-evaluation/evaluator-process.mjs',
    'examples/infer-evaluation/evaluator-worker.mjs',
  ];
  const copied = {};
  for (const name of files) {
    const source = await readFile(join(repository, name), 'utf8');
    // Import substitution only. Programs, expected values and checks are
    // byte-for-byte the same source acceptance; no lowered Program repair.
    const external = source.replaceAll("'../../packages/sdk/host-port.mjs'", "'@actql/sdk/host-port'");
    await mkdir(dirname(join(root, name)), {recursive: true});
    await writeFile(join(root, name), external);
    copied[name] = {sourceSha256: createHash('sha256').update(source).digest('hex'),
      externalSha256: createHash('sha256').update(external).digest('hex')};
  }
  await writeFile(join(directory, 'external-consumer-files.json'), JSON.stringify({revision: before.revision, copied}, null, 2) + '\n');
  const environment = join(root, 'base-environment.json');
  await writeFile(environment, await readFile(join(repository, 'spec/local-check-environment.json')));
  const sourceEnvironment = join(root, 'source-environment.json');
  await writeFile(sourceEnvironment, await readFile(join(repository, 'adapters/host-node/fixtures/query-amount-environment.json')));
  const inputs = join(root, 'evaluation-acceptance-inputs.json');
  await writeFile(inputs, JSON.stringify({revision: before.revision, preserveArtifacts: true, evidenceDirectory: directory,
    client: '@actql/node', httpHost: '@actql/local-node/http-host', observation: '@actql/otel-node',
    inferFixture: pathToFileURL(join(root, 'scripts/fixtures/installed-infer-fixture.mjs')).href,
    providerFixture: pathToFileURL(join(root, 'scripts/fixtures/model-provider-binding-fixture.mjs')).href,
    sourceInferFixture: pathToFileURL(join(root, 'scripts/fixtures/source-multi-infer-evidence.mjs')).href,
    duckdbRequire: pathToFileURL(join(root, 'package.json')).href,
    sourceEnvironment, environment}));
  const runtimeEnv = {...env, PATH: `${dirname(process.execPath)}:/usr/bin:/bin`, ACTQL_INFER_EVIDENCE_ACCEPTANCE_INPUTS: inputs};
  for (const name of ['NODE_PATH', 'NODE_OPTIONS', 'MOON_HOME', 'ACTQL_LOCAL_SOURCE_PROFILE', 'ACTQL_LOCAL_EFFECT_PROFILE', 'ACTQL_LOCAL_STATE_DIR']) delete runtimeEnv[name];
  const args = nodeTestArguments(['--test-concurrency=1', 'adapters/host-node/infer-evaluation-public.test.mjs',
    'adapters/host-node/source-multi-infer-evidence-public.test.mjs']);
  args[1] = '--test-reporter=' + pathToFileURL(join(root, 'scripts/test-execution-reporter.mjs')).href;
  const stdout = run(process.execPath, args, {cwd: root, env: runtimeEnv, timeout: 600000});
  const checked = assertTestExecution('node', process.execPath, args, {status: 0, stdout});
  assert.equal(checked.counts.passed, 8, 'Single and Source-backed multiple INFER must execute through both transports and actual observability modes');
  console.log(stdout.trimEnd());
  const receipts = [];
  for (const transport of ['local', 'https']) for (const mode of ['disabled', 'sampling-zero']) {
    const receipt = JSON.parse(await readFile(join(directory, `evaluation-${transport}-${mode}.json`), 'utf8'));
    assert.equal(receipt.revision, before.revision);
    assert.equal(receipt.result.status, 'scored');
    assert.deepEqual(receipt.result.records.map(record => record.score), [0, 1, 1]);
    assert.equal(receipt.physicalCalls, 4, 'Three fresh comparison calls plus one declared capture-limit counterexample');
    assert.equal(receipt.otlpRequests, 0);
    assert.equal(new Set(receipt.evaluatorProcessIds).size, 3);
    receipts.push(receipt);
  }
  const sourceReceipts = [];
  for (const transport of ['local', 'https']) {
    const restored = JSON.parse(await readFile(join(directory, `source-evidence-${transport}-disabled.json`), 'utf8'));
    assert.equal(restored.revision, before.revision); assert.equal(restored.complete, true);
    assert.equal(restored.sourceCalls, 1); assert.equal(restored.providerCalls, 4);
    assert.equal(restored.restoredItems.length, 4); assert.equal(restored.otlpRequests, 0);
    const comparison = JSON.parse(await readFile(join(directory, `source-comparison-${transport}-sampling-zero.json`), 'utf8'));
    assert.equal(comparison.revision, before.revision); assert.equal(comparison.complete, true);
    assert.equal(comparison.result.status, 'scored'); assert.equal(comparison.result.selectedCandidate, 'B');
    assert.equal(comparison.result.records.length, 12); assert.equal(comparison.result.used.providerCalls, 12);
    assert.equal(comparison.result.used.evaluatorCalls, 12);
    assert(comparison.runs.every(run => run.revision === before.revision && run.sourceCalls === 1 &&
      run.calls.length === 4 && run.otlpRequests === 0 && run.terminal.status === 'succeeded'));
    sourceReceipts.push({transport, restored, comparison});
  }
  assert.deepEqual(checkoutState(repository), before);
  await writeFile(join(directory, 'evaluation-summary.json'), JSON.stringify({revision: before.revision,
    complete: true, receipts: receipts.map(({transport, observationMode, physicalCalls, observationRecords}) =>
      ({transport, observationMode, physicalCalls, observationRecords})), sourceReceipts}, null, 2) + '\n');
});
