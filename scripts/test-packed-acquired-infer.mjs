// Verify acquired INFER through only installed public exports.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {readFile, writeFile} from 'node:fs/promises';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {withPackedQueryEvidence} from './packed-query-evidence.mjs';
import {packedClientPackage, packedNpmCache} from './packed-client-packages.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
const revision = spawnSync('git', ['rev-parse', 'HEAD'], {cwd: repository,
  encoding: 'utf8'});
if (revision.status !== 0) throw new Error('PackedAcquiredRevisionUnavailable');
await withPackedQueryEvidence({scratch: join(repository, '..', '.codex-scratch'),
  revision: revision.stdout.trim(), githubOutput: process.env.GITHUB_OUTPUT,
  keepArtifacts: process.argv.includes('--keep-artifacts')},
async ({root, directory, run, recordTarball}) => {
  console.log(`Packed acquired INFER evidence: ${directory}`);
  const env = {...process.env, npm_config_cache: packedNpmCache(root)};
  const names = ['client-wire', 'sdk', 'run-host-core', 'local-node', 'node'];
  for (const name of names) {
    await packedClientPackage({repository, name, destination: root,
      pack: () => run('npm', ['pack', '--pack-destination', root, '--json'],
        {cwd: join(repository, 'packages', name), env, timeout: 600000})});
    recordTarball(join(root, `actql-${name}-0.0.0-development.tgz`));
  }
  await writeFile(join(root, 'package.json'),
    '{"private":true,"type":"module"}\n');
  run('npm', ['install', '--ignore-scripts', '--no-save', ...names.map(name =>
    join(root, `actql-${name}-0.0.0-development.tgz`))],
  {cwd: root, env, timeout: 240000});
  for (const [source, name] of [
    ['scripts/fixtures/packed-acquired-infer.mjs', 'acceptance.mjs'],
    ['scripts/fixtures/model-custody-fixture.mjs', 'model-custody-fixture.mjs'],
    ['scripts/fixtures/model-provider-binding-fixture.mjs',
      'model-provider-binding-fixture.mjs'],
    ['scripts/fixtures/installed-infer-fixture.mjs', 'installed-infer-fixture.mjs'],
    ['scripts/fixtures/installed-acquired-infer-fixture.mjs',
      'installed-acquired-infer-fixture.mjs'],
    ['adapters/host-node/fixtures/query-amount-environment.json',
      'source-environment.json'],
    ['spec/local-check-environment.json', 'base-environment.json'],
  ]) await writeFile(join(root, name), await readFile(join(repository, source)));
  const runtimeEnv = {...env, PATH: `${dirname(process.execPath)}:/usr/bin:/bin`};
  for (const name of ['NODE_PATH', 'NODE_OPTIONS', 'MOON_HOME',
    'ACTQL_LOCAL_SOURCE_PROFILE', 'ACTQL_LOCAL_STATE_DIR']) delete runtimeEnv[name];
  for (const mode of ['success', 'cancel', 'capture', 'replay']) {
    console.log(run(process.execPath, ['acceptance.mjs', mode],
      {cwd: root, env: runtimeEnv, timeout: 120000}).trimEnd());
  }
  const calls = (await readFile(join(root, 'provider-calls.jsonl'), 'utf8'))
    .trim().split('\n').map(line => JSON.parse(line).mode);
  assert.deepEqual(calls, ['success', 'cancel', 'capture']);
  assert.deepEqual(JSON.parse(await readFile(join(root, 'capture-boundary.json'))),
    {calls: 1, name: 'infer_capture_committed'});
});
