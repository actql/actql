// Exercise only installed public exports in a directory outside the checkout.
import {spawnSync} from 'node:child_process';
import assert from 'node:assert/strict';
import {mkdir, readFile, writeFile} from 'node:fs/promises';
import {dirname, join} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {assertTestExecution, nodeTestArguments} from './test-execution.mjs';
import {withPackedQueryEvidence} from './packed-query-evidence.mjs';
import {packedClientPackage, packedNpmCache} from './packed-client-packages.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
const approvalOnly = process.argv.includes('--approval-only');
const recoveryOnly = process.argv.includes('--recovery-only');
assert.ok(!(approvalOnly && recoveryOnly), 'Select one packed INFER filter');
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
  for (const name of ['installed-infer-fixture.mjs', 'model-provider-binding-fixture.mjs',
    'model-custody-fixture.mjs',
    'packed-single-infer.mjs']) {
    await writeFile(join(root, name),
      await readFile(join(repository, 'scripts', 'fixtures', name)));
  }
  await writeFile(join(root, 'base-environment.json'),
    await readFile(join(repository, 'spec/local-check-environment.json')));
  const runtimeEnv = {...env, PATH: `${dirname(process.execPath)}:/usr/bin:/bin`};
  for (const name of ['MOON_HOME', 'ACTQL_LOCAL_SOURCE_PROFILE',
    'ACTQL_LOCAL_EFFECT_PROFILE', 'ACTQL_LOCAL_STATE_DIR']) delete runtimeEnv[name];
  for (const transport of ['local', 'http']) {
    const modes = recoveryOnly ? [] : approvalOnly
      ? ['approval-wait', 'approval-approve', 'approval-replay']
      : ['success', 'cancel', 'failure', 'capture', 'replay',
        'approval-wait', 'approval-approve', 'approval-replay'];
    for (const mode of modes) {
      console.log(run(process.execPath, ['packed-single-infer.mjs', mode,
        transport], {cwd: root, env: runtimeEnv, timeout: 120000}).trimEnd());
    }
  }
  if (!recoveryOnly) {
    const calls = (await readFile(join(root, 'provider-calls.jsonl'), 'utf8'))
      .trim().split('\n').map(line => JSON.parse(line));
    const expectedCalls = ['local', 'http'].flatMap(transport =>
      (approvalOnly ? ['approval-approve'] :
        ['success', 'cancel', 'failure', 'capture', 'approval-approve']).map(mode =>
        ({mode, transport})));
    if (JSON.stringify(calls.map(({mode, transport}) => ({mode, transport}))) !==
        JSON.stringify(expectedCalls)) {
      throw new Error(`Unexpected provider dispatches: ${JSON.stringify(calls)}`);
    }
    for (const transport of ['local', 'http']) {
      if (approvalOnly) continue;
      const boundary = JSON.parse(await readFile(join(root,
        `capture-boundary-${transport}.json`)));
      if (boundary.calls !== 1 || boundary.boundary !== 'infer_capture_committed') {
        throw new Error(`${transport}: capture process did not stop at its accepted boundary`);
      }
    }
  }
  if (!approvalOnly) {
    // Reuse the source recovery harness unchanged. Every child imports only
    // this fresh installation's public exports; no checkout runtime can help.
    const files = [
      'adapters/host-node/model-resume-public.test.mjs',
      'adapters/host-node/fixtures/model-resume-public-process.mjs',
      'scripts/fixtures/model-custody-fixture.mjs',
      'scripts/fixtures/installed-infer-fixture.mjs',
      'scripts/test-execution-reporter.mjs',
    ];
    for (const name of files) {
      await mkdir(dirname(join(root, name)), {recursive: true});
      await writeFile(join(root, name), await readFile(join(repository, name)));
    }
    const inputs = join(root, 'packed-model-recovery-inputs.json');
    await writeFile(inputs, JSON.stringify({scratch: root, preserveArtifacts: true,
      runtime: {client: '@actql/node', httpHost: '@actql/local-node/http-host',
        inferFixture: pathToFileURL(join(root, 'installed-infer-fixture.mjs')).href,
        providerFixture: pathToFileURL(join(root, 'model-provider-binding-fixture.mjs')).href,
        environment: join(root, 'base-environment.json')}}));
    const args = nodeTestArguments(['--test-name-pattern',
      '^public Model(?: (?:local|https))?:',
      'adapters/host-node/model-resume-public.test.mjs']);
    // The external consumer owns its own copied reporter, not a source link.
    args[1] = '--test-reporter=' + pathToFileURL(join(root,
      'scripts/test-execution-reporter.mjs')).href;
    const stdout = run(process.execPath, args, {cwd: root,
      env: {...runtimeEnv, ACTQL_MODEL_ACCEPTANCE_INPUTS: inputs}, timeout: 360000});
    const checked = assertTestExecution('node', process.execPath, args,
      {status: 0, stdout});
    assert.equal(checked.counts.passed, 32,
      'The existing Source-free Model recovery boundary matrix must execute');
    console.log(stdout.trimEnd());
  }
});
