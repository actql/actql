// A real clean-HEAD tarball consumer. Only authored tests/independent oracles
// are copied; Host, SDK, MoonBit and Python worker come from installed packages.
import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {copyFile, mkdir, readFile, writeFile} from 'node:fs/promises';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createOwnedScratch} from './owned-scratch.mjs';
import {CLIENT_PACKAGES, checkoutState, packClientPackages, packedClientPackage,
  packedNpmCache} from './packed-client-packages.mjs';
import {auditPackedPackages} from './packed-package-boundaries.mjs';
import {assertTestExecution, nodeTestArguments} from './test-execution.mjs';
import {admitCompositionRelease, compositionReleaseDirectory} from './composition-release-input.mjs';
import {tablePublicTestGroups, tablePublicFixturePaths} from './table-public-acceptance-cases.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
const fixtures = tablePublicFixturePaths;
const digest = bytes => createHash('sha256').update(bytes).digest('hex');

test('packed Table commits preserve original operations and sparse inputs through public clients', async () => {
  const state = checkoutState(repository);
  assert.equal(state.clean, true, 'Packed acceptance requires committed build inputs');
  const selection = tablePublicTestGroups(process.env.ACTQL_TABLE_CASE_GROUP ?? 'all');
  const releaseDirectory = process.env.ACTQL_TABLE_NORMAL_RELEASE === undefined ? undefined
    : compositionReleaseDirectory(['--release-dir', process.env.ACTQL_TABLE_NORMAL_RELEASE]);
  // Reuse the normal4 verifier, exact clean source, immutable manifest and
  // original/final archive checks already used by the composition consumer.
  const normalRelease = releaseDirectory === undefined ? undefined
    : await admitCompositionRelease({repository, directory: releaseDirectory});
  assert.ok(process.env.ACTQL_TABLE_PYTHON, 'Explicit optional Table Python installation required');
  const scratch = await createOwnedScratch({parent: join(repository, '..', '.codex-scratch'),
    prefix: 'packed-table-private-', label: 'packed private Table input',
    digests: () => CLIENT_PACKAGES.map(name => `actql-${name}-0.0.0-development.tgz`)});
  const application = join(scratch.path, 'application');
  await mkdir(application);
  const environment = {...process.env, npm_config_cache: packedNpmCache(scratch.path)};
  // This is a separate Node test process, not recursive discovery inside the
  // producer test worker. Keep its normal reporter/nonzero guard intact.
  delete environment.NODE_TEST_CONTEXT;
  delete environment.NODE_PATH;
  delete environment.ACTQL_LOCAL_SOURCE_PROFILE;
  delete environment.ACTQL_LOCAL_EFFECT_PROFILE;
  const run = (command, args, cwd, timeout = 120000) => {
    const result = spawnSync(command, args, {cwd, env: environment, encoding: 'utf8',
      timeout, maxBuffer: 64 * 1024 * 1024});
    assert.ifError(result.error);
    assert.equal(result.status, 0, `${command}:\n${result.stdout}\n${result.stderr}`);
    return result.stdout;
  };
  const python = JSON.parse(run(process.env.ACTQL_TABLE_PYTHON, ['-c',
    'import json,platform,pyarrow,pyiceberg; print(json.dumps({"python":platform.python_version(),"pyiceberg":pyiceberg.__version__,"pyarrow":pyarrow.__version__}))'], application));
  assert.equal(python.pyiceberg, '0.10.0');
  assert.equal(python.pyarrow, '21.0.0');
  const pack = name => run('npm', ['pack', '--json', '--pack-destination', scratch.path],
    join(repository, 'packages', name), 180000);
  // Normal mode never packs, rewrites metadata, or falls back to development.
  if (normalRelease === undefined) {
    if (process.env.ACTQL_PACKED_CLIENT_PACKAGES) {
      for (const name of CLIENT_PACKAGES) await packedClientPackage({repository, name,
        destination: scratch.path, pack});
    } else await packClientPackages({repository, destination: scratch.path, pack});
  }
  const packageNames = normalRelease?.manifest.cohort.packages ?? CLIENT_PACKAGES;
  const packages = normalRelease === undefined
    ? await Promise.all(CLIENT_PACKAGES.map(async name => {
      const path = join(scratch.path, `actql-${name}-0.0.0-development.tgz`);
      return {name, path, sha256: digest(await readFile(path))};
    }))
    : await Promise.all(normalRelease.archives.map(async (path, index) => ({
      name: packageNames[index], path, sha256: digest(await readFile(path))})));
  await writeFile(join(application, 'package.json'), '{"private":true,"type":"module"}\n');
  run('npm', ['install', '--offline', '--ignore-scripts', '--omit=optional',
    '--no-audit', '--no-fund', '--no-save', ...packages.map(value => value.path)], application);
  auditPackedPackages(application, packageNames);
  const copied = [];
  for (const path of fixtures) {
    const destination = join(application, path);
    await mkdir(dirname(destination), {recursive: true});
    await copyFile(join(repository, path), destination);
    copied.push({path, sha256: digest(await readFile(destination))});
  }
  environment.ACTQL_TEST_TABLE_PACKED_APPLICATION = application;
  // Reuse one exact package installation for disjoint case groups. Keep
  // the existing per-child budget/nonzero guard; do not omit slow recovery
  // cases or turn a timed-out partial run into acceptance.
  const groups = selection;
  const executed = [];
  for (const group of groups) {
    const args = nodeTestArguments(['--test-concurrency=1',
      '--test-name-pattern', group.pattern, 'adapters/host-node/table-public-commit.test.mjs']);
    const result = spawnSync(process.execPath, args, {cwd: application, env: environment,
      encoding: 'utf8', timeout: 360000, maxBuffer: 64 * 1024 * 1024});
    process.stdout.write(result.stdout ?? '');
    process.stderr.write(result.stderr ?? '');
    const checked = assertTestExecution('node', process.execPath, args, result);
    assert.equal(checked.counts.passed, group.expected, `${group.name}: all selected cases must execute`);
    executed.push({name: group.name, pattern: group.pattern, counts: checked.counts});
  }
  const counts = Object.fromEntries(Object.keys(executed[0].counts).map(field =>
    [field, executed.reduce((sum, group) => sum + group.counts[field], 0)]));
  assert.equal(counts.passed, groups.reduce((sum, group) => sum + group.expected, 0),
    'Every case in the closed physical selection must execute');
  assert.deepEqual(checkoutState(repository), state, 'Source changed during packed acceptance');
  const local = join(application, 'node_modules/@actql/local-node');
  const artifacts = await Promise.all([
    '_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js',
    'adapters/connectors/local/iceberg/process_worker.py', 'adapters/connectors/local/iceberg/catalog.py',
    'adapters/connectors/local/iceberg/physical.py', 'adapters/connectors/local/iceberg/requirements.lock',
  ].map(async path => ({path, sha256: digest(await readFile(join(local, path)))})));
  const provenance = {sourceRevision: state.revision, python,
    ...(normalRelease === undefined ? {} : {normalRelease: {directory: normalRelease.directory,
      sourceSha: normalRelease.manifest.sourceSha, manifestSha256: normalRelease.manifestSha256}}),
    packages: packages.map(({name, sha256}) => ({name, sha256})),
    installedArtifacts: artifacts, authoredFixtures: copied, counts, groups: executed};
  console.log('PACKED_TABLE_PRIVATE_INPUT', JSON.stringify(provenance));
  if (normalRelease !== undefined) await normalRelease.verifyUnchanged();
  // Child tests await the real Host's cleanup, and spawnSync has reaped every
  // command before this owner permits removal of its disposable installation.
  scratch.passed();
});
