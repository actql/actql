// Install outside the checkout, then run B's unchanged public acceptance
// against Embedded Local and HTTP without a MoonBit toolchain at runtime.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdir, readFile, rename, writeFile} from 'node:fs/promises';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {readmeQuickstart} from './readme-quickstart.mjs';
import {auditPackedPackages} from './packed-package-boundaries.mjs';
import {withPackedQueryEvidence} from './packed-query-evidence.mjs';
import {packedClientPackage, packedNpmCache} from './packed-client-packages.mjs';
import {exercisePackedInferSource} from './packed-infer-source-acceptance.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
const scratch = join(repository, '..', '.codex-scratch');
const revision = spawnSync('git', ['rev-parse', 'HEAD'], {cwd: repository,
  encoding: 'utf8'});
if (revision.status !== 0) throw new Error('PackedQueryRevisionUnavailable');
await withPackedQueryEvidence({scratch, revision: revision.stdout.trim(),
  githubOutput: process.env.GITHUB_OUTPUT,
  keepArtifacts: process.argv.includes('--keep-artifacts')},
async ({root, directory, run: capture, recordTarball}) => {
const environment = {...process.env, npm_config_cache: packedNpmCache(root)};
function run(command, args, cwd = root, env = environment,
  timeout = 240_000) {
  return capture(command, args, {cwd, env, timeout});
}
console.log(`Packed public-query evidence: ${directory}`);
const packages = ['client-wire', 'sdk', 'run-host-core', 'local-node', 'node'];
for (const name of packages) {
  await packedClientPackage({repository, name, destination: root,
    pack: () => run('npm', ['pack', '--pack-destination', root, '--json'],
      join(repository, 'packages', name))});
  recordTarball(join(root, `actql-${name}-0.0.0-development.tgz`));
}
const quickstart = readmeQuickstart(await readFile(join(repository, 'README.md'), 'utf8'));
run('bash', ['-eu', '-c', quickstart.install], root,
  {...environment, ACTQL_PACKED_CLIENT_PACKAGES: root});
for (const [source, destination] of [
  ['scripts/fixtures/packed-readme-quickstart.mjs', 'readme-acceptance.mjs'],
  ['scripts/fixtures/public-query-input.mjs', 'public-query-input.mjs'],
  ['scripts/fixtures/public-query-cases.mjs', 'public-query-cases.mjs'],
  ['scripts/fixtures/group-star-source-input.mjs', 'group-star-source-input.mjs'],
  ['scripts/fixtures/group-ordinal-source-input.mjs', 'group-ordinal-source-input.mjs'],
  ['scripts/fixtures/order-ordinal-source-input.mjs', 'order-ordinal-source-input.mjs'],
  ['scripts/fixtures/distinct-order-source-input.mjs', 'distinct-order-source-input.mjs'],
  ['scripts/fixtures/group-select-scope-source-input.mjs', 'group-select-scope-source-input.mjs'],
  ['scripts/fixtures/having-projection-source-input.mjs', 'having-projection-source-input.mjs'],
  ['scripts/fixtures/implicit-property-source-input.mjs', 'implicit-property-source-input.mjs'],
  ['scripts/fixtures/group-property-source-input.mjs', 'group-property-source-input.mjs'],
  ['scripts/fixtures/acquired-data-source-input.mjs', 'acquired-data-source-input.mjs'],
  ['scripts/fixtures/property-graph-source-input.mjs', 'property-graph-source-input.mjs'],
  ['scripts/fixtures/property-graph-row-source-input.mjs', 'property-graph-row-source-input.mjs'],
  ['scripts/fixtures/graph-match-source-input.mjs', 'graph-match-source-input.mjs'],
  ['scripts/fixtures/graph-property-predicate-source-input.mjs', 'graph-property-predicate-source-input.mjs'],
  ['scripts/fixtures/property-graph-traverse-source-input.mjs', 'property-graph-traverse-source-input.mjs'],
  ['scripts/fixtures/graph-projection-property-source-input.mjs', 'graph-projection-property-source-input.mjs'],
  ['scripts/fixtures/string-values-restart.mjs', 'string-values-restart.mjs'],
  ['scripts/fixtures/installed-infer-fixture.mjs', 'installed-infer-fixture.mjs'],
  ['scripts/fixtures/infer-source-expectation.mjs', 'infer-source-expectation.mjs'],
  ['scripts/fixtures/packed-infer-source.mjs', 'packed-infer-source.mjs'],
  ['scripts/fixtures/packed-public-query.mjs', 'acceptance.mjs'],
  ['scripts/fixtures/packed-two-source-public-query.mjs', 'packed-two-source-public-query.mjs'],
  ['scripts/fixtures/packed-two-source-example.mjs', 'packed-two-source-example.mjs'],
  ['scripts/fixtures/planner-selection-public-query.mjs', 'planner-selection-public-query.mjs'],
  ['scripts/fixtures/packed-planner-selection.mjs', 'packed-planner-selection.mjs'],
  ['scripts/fixtures/two-source-public-query.mjs', 'two-source-public-query.mjs'],
  ['scripts/fixtures/two-source-restart.mjs', 'two-source-restart.mjs'],
  ['adapters/host-node/fixtures/query-amount-environment.json', 'source-environment.json'],
  ['spec/local-check-environment.json', 'base-environment.json'],
  ['spec/frontend/fixtures/pipe-scope/cases.json', 'pipe-scope-cases.json'],
  ['spec/frontend/fixtures/join-order/cases.json', 'join-order-cases.json'],
  ['spec/frontend/fixtures/join-chain/cases.json', 'join-chain-cases.json'],
  ['spec/frontend/fixtures/group-scope/cases.json', 'group-scope-cases.json'],
  ['spec/frontend/fixtures/data-set-strategy/repro-program.json', 'data-set-strategy-program.json'],
  ['scripts/fixtures/packed-sga-cancellation.mjs', 'sga-cancellation.mjs'],
  ['scripts/property-graph-public-host.test.mjs', 'property-graph-public-host.test.mjs'],
  ['scripts/property-graph-source-snapshot.test.mjs', 'property-graph-source-snapshot.test.mjs'],
  ['scripts/check-canonical-json.mjs', 'check-canonical-json.mjs'],
  ['docs/reviews/2026-09-19-sga-veca-tea-local-coverage.json', 'local-family-coverage.json'],
]) {
  await writeFile(join(root, destination), await readFile(join(repository, source)));
}
await mkdir(join(root, 'two-source-fixtures'));
for (const name of ['database-rows.json', 'two-source-join.program.json', 'two-source-join.aql',
  'two-source-join.expected.json', 'equal-content-join.expected.json',
  'left-only.program.json', 'left.environment.json', 'right.environment.json']) {
  await writeFile(join(root, 'two-source-fixtures', name), await readFile(join(repository,
    'adapters/host-node/fixtures/two-source', name)));
}
// Copy the exact documented example and its shared JSON fixtures.
const exampleReadme = await readFile(join(repository,
  'examples/two-source-join/README.md'), 'utf8');
const exampleCommands = [...exampleReadme.matchAll(/```bash\n([\s\S]*?)\n```/gu)];
assert.equal(exampleCommands.length, 2);
run('bash', ['-eu', '-c', exampleCommands[0][1]], root,
  {...environment, ACTQL_CHECKOUT: repository});
await mkdir(join(root, 'fixtures'));
await writeFile(join(root, 'fixtures/property-graph-parallel.program.json'),
  await readFile(join(repository, 'scripts/fixtures/property-graph-parallel.program.json')));
await writeFile(join(root, 'fixtures/property-graph-presence.program.json'),
  await readFile(join(repository, 'scripts/fixtures/property-graph-presence.program.json')));
await writeFile(join(root, 'fixtures/property-graph-definition-rows.program.json'),
  await readFile(join(repository, 'scripts/fixtures/property-graph-definition-rows.program.json')));
await writeFile(join(root, 'fixtures/property-graph-label-rows.program.json'),
  await readFile(join(repository, 'scripts/fixtures/property-graph-label-rows.program.json')));
await writeFile(join(root, 'fixtures/property-graph-selector-derive.program.json'),
  await readFile(join(repository, 'scripts/fixtures/property-graph-selector-derive.program.json')));
await writeFile(join(root, 'fixtures/property-graph-traverse-nodes.expected.json'),
  await readFile(join(repository, 'scripts/fixtures/property-graph-traverse-nodes.expected.json')));
run('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048',
  '-keyout', 'remote.key', '-out', 'remote.crt', '-days', '1',
  '-subj', '/CN=localhost',
  '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1']);
auditPackedPackages(root, packages);
run('npm', ['ls', '--omit=dev', '--all']);
await writeFile(join(root, 'query.aql'), quickstart.program);
await writeFile(join(root, 'quickstart.mjs'), quickstart.client);
const runtimeEnvironment = {...environment,
  PATH: `${dirname(process.execPath)}:/usr/bin:/bin`,
  NODE_EXTRA_CA_CERTS: join(root, 'remote.crt')};
if (process.argv.includes('--property-graph-source-only')) {
  runtimeEnvironment.ACTQL_TEST_PROPERTY_GRAPH_SOURCE_ONLY = '1';
}
if (process.argv.includes('--graph-property-predicate-only')) {
  runtimeEnvironment.ACTQL_TEST_GRAPH_PROPERTY_PREDICATE_ONLY = '1';
}
if (process.argv.includes('--distinct-order-only')) {
  runtimeEnvironment.ACTQL_TEST_DISTINCT_ORDER_ONLY = '1';
}
if (process.argv.includes('--graph-projection-property-only')) {
  runtimeEnvironment.ACTQL_TEST_GRAPH_PROJECTION_PROPERTY_ONLY = '1';
}
if (process.argv.includes('--graph-match-only')) {
  runtimeEnvironment.ACTQL_TEST_GRAPH_MATCH_ONLY = '1';
}
if (process.argv.includes('--graph-rows-only')) {
  runtimeEnvironment.ACTQL_TEST_GRAPH_ROWS_ONLY = '1';
}
if (process.argv.includes('--order-ordinal-only')) {
  runtimeEnvironment.ACTQL_TEST_ORDER_ORDINAL_ONLY = '1';
}
if (process.argv.includes('--source-free-only')) {
  runtimeEnvironment.ACTQL_TEST_SOURCE_FREE_ONLY = '1';
}
if (process.argv.includes('--data-set-strategy-only')) {
  runtimeEnvironment.ACTQL_TEST_DATA_SET_STRATEGY_ONLY = '1';
}
if (process.argv.includes('--query-composition-only')) {
  runtimeEnvironment.ACTQL_TEST_QUERY_COMPOSITION_ONLY = '1';
}
if (process.argv.includes('--pipe-result-only')) {
  runtimeEnvironment.ACTQL_TEST_PIPE_RESULT_ONLY = '1';
}
if (process.argv.includes('--relation-data-only')) {
  runtimeEnvironment.ACTQL_TEST_RELATION_DATA_ONLY = '1';
}
if (process.argv.includes('--acquired-data-only')) {
  runtimeEnvironment.ACTQL_TEST_ACQUIRED_DATA_ONLY = '1';
}
if (process.argv.includes('--join-order-only')) {
  runtimeEnvironment.ACTQL_TEST_JOIN_ORDER_ONLY = '1';
}
if (process.argv.includes('--group-ordinal-only')) {
  runtimeEnvironment.ACTQL_TEST_GROUP_ORDINAL_ONLY = '1';
}
if (process.argv.includes('--group-property-only')) {
  runtimeEnvironment.ACTQL_TEST_GROUP_PROPERTY_ONLY = '1';
}
if (process.argv.includes('--group-star-only')) {
  runtimeEnvironment.ACTQL_TEST_GROUP_STAR_ONLY = '1';
}
if (process.argv.includes('--group-scope-only')) {
  runtimeEnvironment.ACTQL_TEST_GROUP_SCOPE_ONLY = '1';
}
if (process.argv.includes('--group-select-scope-only')) {
  runtimeEnvironment.ACTQL_TEST_GROUP_SELECT_SCOPE_ONLY = '1';
}
if (process.argv.includes('--implicit-property-only')) {
  runtimeEnvironment.ACTQL_TEST_IMPLICIT_PROPERTY_ONLY = '1';
}
if (process.argv.includes('--having-projection-only')) {
  runtimeEnvironment.ACTQL_TEST_HAVING_PROJECTION_ONLY = '1';
}
if (process.argv.includes('--alias-scope-only')) {
  runtimeEnvironment.ACTQL_TEST_PIPE_SCOPE_ONLY = '1';
}
if (process.argv.includes('--scoped-order-only')) {
  runtimeEnvironment.ACTQL_TEST_SCOPED_ORDER_ONLY = '1';
}
if (process.argv.includes('--infer-refusal-only')) {
  runtimeEnvironment.ACTQL_TEST_INFER_REFUSAL_ONLY = '1';
}
if (process.argv.includes('--two-source-only')) {
  runtimeEnvironment.ACTQL_TEST_TWO_SOURCE_ONLY = '1';
}
for (const name of ['NODE_PATH', 'NODE_OPTIONS', 'MOON_HOME', 'ACTQL_LOCAL_SOURCE_PROFILE',
  'ACTQL_LOCAL_EFFECT_PROFILE', 'ACTQL_LOCAL_STATE_DIR']) {
  delete runtimeEnvironment[name];
}
const exerciseInferSource = () => exercisePackedInferSource({root, directory,
  run, environment: runtimeEnvironment, sourceSha: revision.stdout.trim()});
if (process.argv.includes('--infer-source-only')) {
  await exerciseInferSource();
  return;
}
// Execute the README's literal runtime commands, then the same Program through
// the existing public Client acceptance helper on HTTPS. No second pack/build.
console.log(run('bash', ['-eu', '-c', quickstart.run], root, runtimeEnvironment).trimEnd());
assert.equal(await readFile(join(root, 'answer.jsonl'), 'utf8'), quickstart.expected);
console.log(run(process.execPath, ['readme-acceptance.mjs'], root,
  runtimeEnvironment).trimEnd());
// A fresh process must fail for a real missing generated wire asset; module
// caches and the checkout's dependency graph must not rescue this install.
const asset = join(root, 'node_modules/@actql/client-wire/publication.generated.js');
await rename(asset, asset + '.omitted');
try {
  const negative = spawnSync(process.execPath, ['--input-type=module', '-e',
    "await import('@actql/node')"], {cwd: root, env: runtimeEnvironment,
    encoding: 'utf8', timeout: 30_000});
  await writeFile(join(directory, 'missing-generated-asset.json'), JSON.stringify({
    status: negative.status, signal: negative.signal, stderr: negative.stderr,
    error: negative.error?.code ?? null}, null, 2) + '\n');
  assert.equal(negative.error, undefined);
  assert.notEqual(negative.status, 0, 'Missing packaged asset must fail at runtime');
  assert.match(negative.stderr, /ERR_MODULE_NOT_FOUND/u);
assert.match(negative.stderr, /publication\.generated\.js/u);
  console.log('Packed missing generated asset: child failed as expected');
} finally { await rename(asset + '.omitted', asset); }
async function exerciseNativeGraphSource(sourceOnly = false) {
  run('moon', ['build', '--target', 'native', '--release',
    'src/cmd/native_client'], repository, environment);
  const nativeClient = join(repository, '_build/native/release/build/cmd',
    'native_client/native_client.exe');
  console.log(run(process.execPath,
    [join(repository, 'scripts/test-native-sga-public-source.mjs'),
      root, nativeClient, directory, ...(sourceOnly ? ['--authored-source-only'] : [])],
    root, runtimeEnvironment).trimEnd());
}
if (process.argv.includes('--property-graph-native-only')) {
  await exerciseNativeGraphSource(true);
  return;
}
if (process.argv.includes('--quickstart-only')) return;
if (process.argv.includes('--cancellation-only')) {
  console.log(run(process.execPath, ['sga-cancellation.mjs'], root,
    runtimeEnvironment, 120000).trimEnd());
  return;
}
const twoSourceExampleOnly = process.argv.includes('--two-source-example-only');
const plannerSelectionOnly = process.argv.includes('--planner-selection-only');
const narrowPublicQuery = process.argv.some(flag => ['--source-free-only',
  '--graph-projection-property-only',
  '--graph-property-predicate-only',
  '--group-property-only',
  '--order-ordinal-only', '--distinct-order-only', '--query-composition-only', '--pipe-result-only', '--join-order-only', '--group-scope-only', '--group-select-scope-only', '--having-projection-only', '--implicit-property-only', '--group-star-only', '--group-ordinal-only',
  '--alias-scope-only', '--scoped-order-only', '--infer-refusal-only', '--two-source-only',
  '--relation-data-only', '--acquired-data-only',
  '--data-set-strategy-only', '--property-graph-source-only', '--graph-rows-only'].includes(flag));
try {
  if (!plannerSelectionOnly && !twoSourceExampleOnly) {
    const output = run(process.execPath, ['acceptance.mjs'], root,
      runtimeEnvironment, 900_000);
    console.log(output.trimEnd());
    // Reuse this exact installation and its producer artifact. Source INFER
    // is a separate authored corpus; narrow non-INFER selections stay narrow.
    if (!process.argv.some(flag => flag.endsWith('-only'))) await exerciseInferSource();
  }
  // The same packed installation executes this bounded candidate corpus once.
  // Cost inputs go to the Host profile; the public Program never chooses a route.
  if (plannerSelectionOnly || !narrowPublicQuery && !twoSourceExampleOnly) {
    console.log(run(process.execPath, ['packed-planner-selection.mjs'], root,
      runtimeEnvironment, 180_000).trimEnd());
  }
  if (twoSourceExampleOnly || !plannerSelectionOnly && !narrowPublicQuery) {
    console.log(run(process.execPath, ['packed-two-source-example.mjs'], root,
      runtimeEnvironment, 180_000).trimEnd());
  }
} finally {
  try {
    await writeFile(join(directory, 'two-source-example.json'),
      await readFile(join(root, 'two-source-example-report.json')));
  } catch (error) { if (error.code !== 'ENOENT') throw error; }
  // Preserve two-source observations beside existing command/tarball evidence
  // before the harness removes its installed consumer, including on failure.
  try {
    await writeFile(join(directory, 'two-source-acceptance.json'),
      await readFile(join(root, 'two-source-packed-report.json')));
  } catch (error) { if (error.code !== 'ENOENT') throw error; }
  try {
    await writeFile(join(directory, 'planner-selection-acceptance.json'),
      await readFile(join(root, 'planner-selection-packed-report.json')));
  } catch (error) { if (error.code !== 'ENOENT') throw error; }
}
if (plannerSelectionOnly || twoSourceExampleOnly) return;
// The first Host process has exited: no live Local installation still owns
// its Store. Restore retained Results in a new process without resubmission.
// Narrow selections without the String fixture have no retained String Run.
// Keep restart acceptance for full/source-free selections that create it.
if (!process.argv.some(flag => ['--alias-scope-only', '--scoped-order-only', '--infer-refusal-only',
  '--graph-projection-property-only',
  '--graph-property-predicate-only',
  '--group-property-only',
  '--order-ordinal-only', '--join-order-only', '--group-scope-only', '--group-select-scope-only', '--having-projection-only', '--implicit-property-only', '--group-star-only', '--group-ordinal-only', '--distinct-order-only', '--query-composition-only', '--pipe-result-only',
  '--relation-data-only', '--acquired-data-only', '--data-set-strategy-only', '--two-source-only',
  '--property-graph-source-only', '--graph-rows-only'].includes(flag))) {
  console.log(run(process.execPath, ['string-values-restart.mjs'], root,
    runtimeEnvironment, 120000).trimEnd());
}
if (process.argv.includes('--order-ordinal-only') ||
    process.argv.includes('--graph-projection-property-only') ||
    process.argv.includes('--graph-property-predicate-only') ||
    process.argv.includes('--group-property-only') ||
    process.argv.includes('--distinct-order-only') ||
    process.argv.includes('--implicit-property-only') ||
  process.argv.includes('--source-free-only') ||
  process.argv.includes('--data-set-strategy-only') ||
  process.argv.includes('--query-composition-only') ||
  process.argv.includes('--pipe-result-only') ||
  process.argv.includes('--relation-data-only') ||
  process.argv.includes('--acquired-data-only') ||
  process.argv.includes('--alias-scope-only') ||
  process.argv.includes('--scoped-order-only') ||
  process.argv.includes('--infer-refusal-only') ||
  process.argv.includes('--two-source-only') ||
  process.argv.includes('--join-order-only') ||
  process.argv.includes('--group-scope-only') ||
  process.argv.includes('--group-select-scope-only') ||
  process.argv.includes('--having-projection-only') ||
  process.argv.includes('--group-star-only') ||
  process.argv.includes('--group-ordinal-only') ||
  process.argv.includes('--graph-rows-only')) return;
if (!process.argv.includes('--property-graph-source-only')) {
  console.log(run(process.execPath, ['sga-cancellation.mjs'], root,
    runtimeEnvironment, 120000).trimEnd());
}
await mkdir(join(root, 'tls'));
await writeFile(join(root, 'tls/site.key'), await readFile(join(root, 'remote.key')));
await writeFile(join(root, 'tls/site.crt'), await readFile(join(root, 'remote.crt')));
await writeFile(join(root, 'tls/ca.crt'), await readFile(join(root, 'remote.crt')));
console.log(run(process.execPath, ['--test', 'property-graph-public-host.test.mjs',
  'property-graph-source-snapshot.test.mjs'], root,
  {...runtimeEnvironment, ACTQL_PROPERTY_GRAPH_PACKED: '1'}, 180000).trimEnd());
if (process.argv.includes('--property-graph-source-only')) return;
await exerciseNativeGraphSource();
});
