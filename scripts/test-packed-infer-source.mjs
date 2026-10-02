// A's common owner is a fixed dependency; no Frontend-only inference runtime.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {readFile, writeFile} from 'node:fs/promises';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {parseArgs} from 'node:util';
import {withPackedQueryEvidence} from './packed-query-evidence.mjs';
import {packedClientPackage, packedNpmCache} from './packed-client-packages.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
const {values} = parseArgs({options: {
  'owner-sha': {type: 'string'},
  'keep-artifacts': {type: 'boolean', default: false},
}});
assert.match(values['owner-sha'] ?? '', /^[a-f0-9]{40}$/u);
const git = args => spawnSync('git', args, {cwd: repository, encoding: 'utf8'});
const revision = git(['rev-parse', 'HEAD']);
assert.equal(revision.status, 0);
assert.equal(git(['status', '--porcelain']).stdout, '', 'fixed clean source required');
assert.equal(git(['merge-base', '--is-ancestor', values['owner-sha'], 'HEAD']).status, 0);
await withPackedQueryEvidence({scratch: join(repository, '..', '.codex-scratch'),
  revision: revision.stdout.trim(), keepArtifacts: values['keep-artifacts'],
  githubOutput: process.env.GITHUB_OUTPUT},
async ({root, directory, run, recordTarball}) => {
  console.log(`Packed source INFER evidence: ${directory}`);
  await writeFile(join(directory, 'infer-source-provenance.json'), JSON.stringify({
    sourceSha: revision.stdout.trim(), commonOwnerSha: values['owner-sha'],
    profile: 'single-key-source-object-and-fresh-process-capture-replay',
  }, null, 2) + '\n');
  const env = {...process.env, npm_config_cache: packedNpmCache(root)};
  const packages = ['client-wire', 'sdk', 'run-host-core', 'local-node', 'node'];
  for (const name of packages) {
    await packedClientPackage({repository, name, destination: root,
      pack: () => run('npm', ['pack', '--pack-destination', root, '--json'],
        {cwd: join(repository, 'packages', name), env, timeout: 600_000})});
    recordTarball(join(root, `actql-${name}-0.0.0-development.tgz`));
  }
  await writeFile(join(root, 'package.json'), '{"private":true,"type":"module"}\n');
  run('npm', ['install', '--ignore-scripts', '--no-save', ...packages.map(name =>
    join(root, `actql-${name}-0.0.0-development.tgz`))], {env});
  for (const name of ['installed-infer-fixture.mjs', 'infer-source-expectation.mjs',
    'packed-infer-source.mjs']) {
    await writeFile(join(root, name),
      await readFile(join(repository, 'scripts', 'fixtures', name)));
  }
  await writeFile(join(root, 'base-environment.json'),
    await readFile(join(repository, 'spec/local-check-environment.json')));
  run('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048',
    '-keyout', 'remote.key', '-out', 'remote.crt', '-days', '1',
    '-subj', '/CN=localhost',
    '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1']);
  const runtimeEnv = {...env, PATH: `${dirname(process.execPath)}:/usr/bin:/bin`,
    NODE_EXTRA_CA_CERTS: join(root, 'remote.crt')};
  for (const name of ['MOON_HOME', 'ACTQL_LOCAL_SOURCE_PROFILE',
    'ACTQL_LOCAL_EFFECT_PROFILE', 'ACTQL_LOCAL_STATE_DIR']) delete runtimeEnv[name];
  for (const transport of ['local', 'remote']) {
    for (const phase of ['success', 'capture', 'replay']) {
      console.log(run(process.execPath, ['packed-infer-source.mjs', transport, phase],
        {env: runtimeEnv, timeout: 120_000}).trimEnd());
    }
  }
  const calls = (await readFile(join(root, 'source-provider-calls.jsonl'), 'utf8'))
    .trim().split('\n').map(line => {
      const {transport, phase} = JSON.parse(line);
      return `${transport}:${phase}`;
    });
  assert.deepEqual(calls, ['local:success', 'local:capture',
    'remote:success', 'remote:capture'], 'no replay provider call in either transport');
});
