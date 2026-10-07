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

const repository = fileURLToPath(new URL('../', import.meta.url));
const fixtures = [
  'adapters/host-node/table-public-commit.test.mjs',
  'adapters/host-node/fixtures/table-physical-fixture.mjs',
  'adapters/host-node/fixtures/table-test-modules.mjs',
  'adapters/host-common/connector-manifest.fixture.mjs',
  'adapters/host-common/publication-contract-control.fixture.mjs',
  'adapters/table-iceberg/fixtures/presence-mapping.json',
  'adapters/table-iceberg/fixtures/presence-schema.json',
  'scripts/check-canonical-json.mjs', 'scripts/actql-spec-family.mjs',
  'scripts/actql-requirement-extraction.mjs',
  'scripts/fixtures/graph-presence.program.json',
  'spec/local-check-environment.json',
  'spec/contracts/actql-table-effect.json',
  'spec/contracts/actql-run-publication.json',
  'spec/contracts/actql-numeric-reduction.json',
  'spec/dependencies/actql-graph-laws.json',
];
const digest = bytes => createHash('sha256').update(bytes).digest('hex');

test('packed Table commits preserve original operations and sparse inputs through public clients', async () => {
  const state = checkoutState(repository);
  assert.equal(state.clean, true, 'Packed acceptance requires committed build inputs');
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
  if (process.env.ACTQL_PACKED_CLIENT_PACKAGES) {
    for (const name of CLIENT_PACKAGES) await packedClientPackage({repository, name,
      destination: scratch.path, pack});
  } else await packClientPackages({repository, destination: scratch.path, pack});
  const packages = await Promise.all(CLIENT_PACKAGES.map(async name => {
    const path = join(scratch.path, `actql-${name}-0.0.0-development.tgz`);
    return {name, path, sha256: digest(await readFile(path))};
  }));
  await writeFile(join(application, 'package.json'), '{"private":true,"type":"module"}\n');
  run('npm', ['install', '--offline', '--ignore-scripts', '--omit=optional',
    '--no-audit', '--no-fund', '--no-save', ...packages.map(value => value.path)], application);
  auditPackedPackages(application, CLIENT_PACKAGES);
  const copied = [];
  for (const path of fixtures) {
    const destination = join(application, path);
    await mkdir(dirname(destination), {recursive: true});
    await copyFile(join(repository, path), destination);
    copied.push({path, sha256: digest(await readFile(destination))});
  }
  environment.ACTQL_TEST_TABLE_PACKED_APPLICATION = application;
  const args = nodeTestArguments(['--test-concurrency=1',
    'adapters/host-node/table-public-commit.test.mjs']);
  const result = spawnSync(process.execPath, args, {cwd: application, env: environment,
    encoding: 'utf8', timeout: 360000, maxBuffer: 64 * 1024 * 1024});
  process.stdout.write(result.stdout ?? '');
  process.stderr.write(result.stderr ?? '');
  const checked = assertTestExecution('node', process.execPath, args, result);
  assert.equal(checked.counts.passed, 9,
    'All real create/replace, reply-loss, concurrent replace, and sparse Local/HTTPS cases must execute');
  assert.deepEqual(checkoutState(repository), state, 'Source changed during packed acceptance');
  const local = join(application, 'node_modules/@actql/local-node');
  const artifacts = await Promise.all([
    '_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js',
    'adapters/table-iceberg/process_worker.py', 'adapters/table-iceberg/catalog.py',
    'adapters/table-iceberg/physical.py', 'adapters/table-iceberg/requirements.lock',
  ].map(async path => ({path, sha256: digest(await readFile(join(local, path)))})));
  const provenance = {sourceRevision: state.revision, python,
    packages: packages.map(({name, sha256}) => ({name, sha256})),
    installedArtifacts: artifacts, authoredFixtures: copied, counts: checked.counts};
  console.log('PACKED_TABLE_PRIVATE_INPUT', JSON.stringify(provenance));
  // Child tests await the real Host's cleanup, and spawnSync has reaped every
  // command before this owner permits removal of its disposable installation.
  scratch.passed();
});
