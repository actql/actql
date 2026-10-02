import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {readFile, stat, writeFile} from 'node:fs/promises';
import {dirname, join, resolve} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {parseArgs} from 'node:util';
import {withPackedQueryEvidence} from './packed-query-evidence.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));

export function inferPackedOptions(args) {
  const {values} = parseArgs({args, options: {
    'host-setup': {type: 'string'}, 'owner-sha': {type: 'string'},
    'keep-artifacts': {type: 'boolean', default: false},
    'first-row-only': {type: 'boolean', default: false},
    'checkpoint-only': {type: 'boolean', default: false},
  }, allowPositionals: false});
  if (!values['host-setup']) throw new Error('InferTestHostSetupRequired');
  if (!/^[a-f0-9]{40}$/u.test(values['owner-sha'] ?? '')) {
    throw new Error('InferCommonOwnerFullShaRequired');
  }
  return {setup: resolve(values['host-setup']),
    ownerSha: values['owner-sha'], keepArtifacts: values['keep-artifacts'],
    firstRowOnly: values['first-row-only'], checkpointOnly: values['checkpoint-only']};
}

// Select authored acceptance cases, never construct expected rows from runtime
// output. The initial path deliberately avoids KEEP's join and ordered output.
export function inferPackedFixture(fixture, firstRowOnly) {
  const selected = structuredClone(fixture);
  if (firstRowOnly) {
    if (selected.first_row_success === undefined) {
      throw new Error('InferFirstRowFixtureRequired');
    }
    selected.successes = [selected.first_row_success];
    selected.preparation_refusals = [];
    selected.preflight_failures = [];
  }
  return selected;
}

export async function runPackedInferInput(args) {
  // All prerequisite validation precedes package building and installation.
  const options = inferPackedOptions(args);
  if (!(await stat(options.setup)).isFile()) {
    throw new Error('InferTestHostSetupNotFile');
  }
  const setup = await readFile(options.setup);
  const git = command => spawnSync('git', command, {cwd: repository,
    encoding: 'utf8'});
  const revision = git(['rev-parse', 'HEAD']);
  if (revision.status !== 0) throw new Error('PackedInferRevisionUnavailable');
  if (git(['diff', '--quiet', 'HEAD']).status !== 0) {
    throw new Error('PackedInferCommittedSourceRequired');
  }
  if (git(['merge-base', '--is-ancestor', options.ownerSha, 'HEAD']).status !== 0) {
    throw new Error('InferCommonOwnerNotIntegrated');
  }
  return withPackedQueryEvidence({
    scratch: join(repository, '..', '.codex-scratch'),
    revision: revision.stdout.trim(), keepArtifacts: options.keepArtifacts,
    githubOutput: process.env.GITHUB_OUTPUT,
  }, async ({root, directory, run, recordTarball}) => {
    const provenance = {sourceSha: revision.stdout.trim(),
      commonOwnerSha: options.ownerSha,
      acceptanceProfile: options.checkpointOnly ? 'checkpoint' :
        options.firstRowOnly ? 'first-row' : 'keep-as',
      hostSetupSha256: createHash('sha256').update(setup).digest('hex')};
    await writeFile(join(directory, 'infer-provenance.json'),
      JSON.stringify(provenance, null, 2) + '\n');
    console.log(`Packed INFER evidence: ${directory}`);
    const env = {...process.env, npm_config_cache: join(root, 'npm-cache')};
    const packages = ['client-wire', 'sdk', 'run-host-core', 'local-node', 'node'];
    for (const name of packages) {
      run('npm', ['pack', '--pack-destination', root, '--json'], {
        cwd: join(repository, 'packages', name), env});
      recordTarball(join(root, `actql-${name}-0.0.0-development.tgz`));
    }
    await writeFile(join(root, 'package.json'),
      '{"private":true,"type":"module"}\n');
    run('npm', ['install', '--ignore-scripts', '--no-save',
      ...packages.map(name => join(root,
        `actql-${name}-0.0.0-development.tgz`))], {env});
    for (const [source, destination] of [
      [options.checkpointOnly ? 'scripts/fixtures/packed-infer-checkpoint.mjs' :
        'scripts/fixtures/packed-infer-client.mjs', 'packed-infer-client.mjs'],
      ['scripts/fixtures/public-infer-input.mjs', 'public-infer-input.mjs'],
    ]) {
      await writeFile(join(root, destination),
        await readFile(join(repository, source)));
    }
    const fixture = JSON.parse(await readFile(join(repository,
      options.checkpointOnly ? 'spec/frontend/fixtures/infer-keep/checkpoint-acceptance.json' :
        'spec/frontend/fixtures/infer-keep/packed-acceptance.json'), 'utf8'));
    await writeFile(join(root, 'infer-acceptance.json'), JSON.stringify(
      options.checkpointOnly ? fixture : inferPackedFixture(fixture, options.firstRowOnly), null, 2) + '\n');
    await writeFile(join(root, 'infer-host-setup.mjs'), setup);
    if (options.checkpointOnly) {
      await writeFile(join(root, 'base-environment.json'),
        await readFile(join(repository, 'spec/local-check-environment.json')));
    }
    run('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048',
      '-keyout', 'remote.key', '-out', 'remote.crt', '-days', '1',
      '-subj', '/CN=localhost',
      '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'], {env});
    const runtimeEnv = {...env, PATH: `${dirname(process.execPath)}:/usr/bin:/bin`,
      NODE_EXTRA_CA_CERTS: join(root, 'remote.crt')};
    for (const name of ['MOON_HOME', 'ACTQL_LOCAL_SOURCE_PROFILE',
      'ACTQL_LOCAL_EFFECT_PROFILE', 'ACTQL_LOCAL_STATE_DIR']) {
      delete runtimeEnv[name];
    }
    const output = run(process.execPath,
      ['packed-infer-client.mjs', './infer-host-setup.mjs'],
      {env: runtimeEnv, timeout: 900_000});
    console.log(output.trimEnd());
  });
}

if (process.argv[1] !== undefined &&
  pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
  await runPackedInferInput(process.argv.slice(2));
}
