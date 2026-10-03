// Exercise only installed public exports in a directory outside the checkout.
import {spawnSync} from 'node:child_process';
import {readFile, writeFile} from 'node:fs/promises';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {withPackedQueryEvidence} from './packed-query-evidence.mjs';
import {packedClientPackage, packedNpmCache} from './packed-client-packages.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
const revision = spawnSync('git', ['rev-parse', 'HEAD'], {cwd: repository,
  encoding: 'utf8'});
if (revision.status !== 0) throw new Error('PackedInferRevisionUnavailable');
await withPackedQueryEvidence({scratch: join(repository, '..', '.codex-scratch'),
  revision: revision.stdout.trim(),
  githubOutput: process.env.GITHUB_OUTPUT,
  keepArtifacts: process.argv.includes('--keep-artifacts')},
async ({root, directory, run, recordTarball}) => {
  console.log(`Packed single INFER evidence: ${directory}`);
  const env = {...process.env, npm_config_cache: packedNpmCache(root)};
  const packages = ['client-wire', 'sdk', 'run-host-core', 'local-node', 'node'];
  for (const name of packages) {
    await packedClientPackage({repository, name, destination: root,
      pack: () => run('npm', ['pack', '--pack-destination', root, '--json'],
        {cwd: join(repository, 'packages', name), env, timeout: 600000})});
    recordTarball(join(root, `actql-${name}-0.0.0-development.tgz`));
  }
  await writeFile(join(root, 'package.json'), '{"private":true,"type":"module"}\n');
  run('npm', ['install', '--ignore-scripts', '--no-save', ...packages.map(name =>
    join(root, `actql-${name}-0.0.0-development.tgz`))],
  {cwd: root, env, timeout: 240000});
  for (const name of ['installed-infer-fixture.mjs', 'packed-single-infer.mjs']) {
    await writeFile(join(root, name),
      await readFile(join(repository, 'scripts', 'fixtures', name)));
  }
  await writeFile(join(root, 'base-environment.json'),
    await readFile(join(repository, 'spec/local-check-environment.json')));
  const runtimeEnv = {...env, PATH: `${dirname(process.execPath)}:/usr/bin:/bin`};
  for (const name of ['MOON_HOME', 'ACTQL_LOCAL_SOURCE_PROFILE',
    'ACTQL_LOCAL_EFFECT_PROFILE', 'ACTQL_LOCAL_STATE_DIR']) delete runtimeEnv[name];
  for (const transport of ['local', 'http']) {
    for (const mode of ['success', 'cancel', 'failure', 'capture', 'replay']) {
      console.log(run(process.execPath, ['packed-single-infer.mjs', mode,
        transport], {cwd: root, env: runtimeEnv, timeout: 120000}).trimEnd());
    }
  }
  const calls = (await readFile(join(root, 'provider-calls.jsonl'), 'utf8'))
    .trim().split('\n').map(line => JSON.parse(line));
  const expectedCalls = ['local', 'http'].flatMap(transport =>
    ['success', 'cancel', 'failure', 'capture'].map(mode =>
      ({mode, transport})));
  if (JSON.stringify(calls.map(({mode, transport}) => ({mode, transport}))) !==
      JSON.stringify(expectedCalls)) {
    throw new Error(`Unexpected provider dispatches: ${JSON.stringify(calls)}`);
  }
  for (const transport of ['local', 'http']) {
    const boundary = JSON.parse(await readFile(join(root,
      `capture-boundary-${transport}.json`)));
    if (boundary.calls !== 1 || boundary.boundary !== 'infer_capture_committed') {
      throw new Error(`${transport}: capture process did not stop at its accepted boundary`);
    }
  }
});
