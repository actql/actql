// Install outside the checkout, then run B's unchanged public acceptance
// against Embedded Local and HTTP without a MoonBit toolchain at runtime.
import {spawnSync} from 'node:child_process';
import {mkdir, readFile, writeFile} from 'node:fs/promises';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {withPackedQueryEvidence} from './packed-query-evidence.mjs';
import {packedClientPackage, packedNpmCache} from './packed-client-packages.mjs';

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
await writeFile(join(root, 'package.json'), '{"private":true,"type":"module"}\n');
run('npm', ['install', '--ignore-scripts', '--no-save', ...packages.map(name =>
  join(root, `actql-${name}-0.0.0-development.tgz`))]);
for (const [source, destination] of [
  ['scripts/fixtures/public-query-input.mjs', 'public-query-input.mjs'],
  ['scripts/fixtures/packed-public-query.mjs', 'acceptance.mjs'],
  ['adapters/host-node/fixtures/query-amount-environment.json', 'source-environment.json'],
  ['spec/local-check-environment.json', 'base-environment.json'],
  ['spec/frontend/fixtures/pipe-scope/cases.json', 'pipe-scope-cases.json'],
  ['spec/frontend/fixtures/join-order/cases.json', 'join-order-cases.json'],
  ['scripts/accept-sga-public-source.mjs', 'accept-sga-public-source.mjs'],
  ['scripts/reach-selector-capacity-fixture.mjs', 'reach-selector-capacity-fixture.mjs'],
  ['scripts/fixtures/packed-sga-cancellation.mjs', 'sga-cancellation.mjs'],
]) {
  await writeFile(join(root, destination), await readFile(join(repository, source)));
}
await mkdir(join(root, 'sga-source-fixtures'));
for (const name of ['normalize-rows', 'mean-graphs', 'traverse-paths',
  'shortest-path',
  'reach-selector', 'reach-selector-duplicates', 'reach-selector-empty',
  'reach-selector-nullable',
  'union-graphs', 'graft-graphs', 'subtract-graphs', 'degree-rows',
  'components', 'graph-bounds', 'match-projections', 'reach-subgraph',
  'graphs-equal', 'diff-apply']) {
  for (const suffix of ['named.aql', 'expected-program.json', 'expected-results.json']) {
    const file = `${name}.${suffix}`;
    await writeFile(join(root, 'sga-source-fixtures', file),
      await readFile(join(repository,
        'spec/frontend/fixtures/sga-surface', file)));
  }
}
run('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048',
  '-keyout', 'remote.key', '-out', 'remote.crt', '-days', '1',
  '-subj', '/CN=localhost',
  '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1']);
const runtimeEnvironment = {...environment,
  PATH: `${dirname(process.execPath)}:/usr/bin:/bin`,
  NODE_EXTRA_CA_CERTS: join(root, 'remote.crt')};
if (process.argv.includes('--join-order-only')) {
  runtimeEnvironment.ACTQL_TEST_JOIN_ORDER_ONLY = '1';
}
if (process.argv.includes('--alias-scope-only')) {
  runtimeEnvironment.ACTQL_TEST_PIPE_SCOPE_ONLY = '1';
}
if (process.argv.includes('--infer-refusal-only')) {
  runtimeEnvironment.ACTQL_TEST_INFER_REFUSAL_ONLY = '1';
}
for (const name of ['MOON_HOME', 'ACTQL_LOCAL_SOURCE_PROFILE',
  'ACTQL_LOCAL_EFFECT_PROFILE', 'ACTQL_LOCAL_STATE_DIR']) {
  delete runtimeEnvironment[name];
}
if (process.argv.includes('--cancellation-only')) {
  console.log(run(process.execPath, ['sga-cancellation.mjs'], root,
    runtimeEnvironment, 120000).trimEnd());
  return;
}
const output = run(process.execPath, ['acceptance.mjs'], root,
  runtimeEnvironment, 900_000);
console.log(output.trimEnd());
if (process.argv.includes('--alias-scope-only') ||
  process.argv.includes('--infer-refusal-only') ||
  process.argv.includes('--join-order-only')) return;
console.log(run(process.execPath, ['sga-cancellation.mjs'], root,
  runtimeEnvironment, 120000).trimEnd());
run('moon', ['build', '--target', 'native', '--release',
  'src/cmd/native_client'], repository, environment);
const nativeClient = join(repository, '_build/native/release/build/cmd',
  'native_client/native_client.exe');
const nativeOutput = run(process.execPath,
  [join(repository, 'scripts/test-native-sga-public-source.mjs'),
    root, nativeClient, directory], root, runtimeEnvironment);
console.log(nativeOutput.trimEnd());
});
