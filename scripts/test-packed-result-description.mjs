import {spawnSync} from 'node:child_process';
import {readFile, writeFile} from 'node:fs/promises';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {withPackedQueryEvidence} from './packed-query-evidence.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
const revision = spawnSync('git', ['rev-parse', 'HEAD'], {
  cwd: repository, encoding: 'utf8'});
if (revision.status !== 0) throw new Error('PackedRevisionUnavailable');
await withPackedQueryEvidence({revision: revision.stdout.trim(),
  scratch: join(repository, '..', '.codex-scratch'),
  keepArtifacts: process.argv.includes('--keep-artifacts'),
  githubOutput: process.env.GITHUB_OUTPUT},
async ({root, directory, run, recordTarball}) => {
  console.log(`Result description evidence: ${directory}`);
  const env = {...process.env, npm_config_cache: join(root, 'npm-cache')};
  const packages = ['client-wire', 'sdk', 'run-host-core', 'local-node', 'node'];
  for (const name of packages) {
    run('npm', ['pack', '--pack-destination', root, '--json'], {
      cwd: join(repository, 'packages', name), env});
    recordTarball(join(root, `actql-${name}-0.0.0-development.tgz`));
  }
  await writeFile(join(root, 'package.json'), '{"private":true,"type":"module"}\n');
  run('npm', ['install', '--ignore-scripts', '--no-save', ...packages.map(name =>
    join(root, `actql-${name}-0.0.0-development.tgz`))], {env});
  await writeFile(join(root, 'acceptance.mjs'), await readFile(join(repository,
    'scripts/fixtures/packed-result-description.mjs')));
  run('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048',
    '-keyout', 'remote.key', '-out', 'remote.crt', '-days', '1',
    '-subj', '/CN=localhost',
    '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1']);
  const runtimeEnv = {...env, PATH: `${dirname(process.execPath)}:/usr/bin:/bin`,
    NODE_EXTRA_CA_CERTS: join(root, 'remote.crt')};
  for (const name of ['MOON_HOME', 'ACTQL_LOCAL_STATE_DIR',
    'ACTQL_LOCAL_SOURCE_PROFILE', 'ACTQL_LOCAL_EFFECT_PROFILE']) {
    delete runtimeEnv[name];
  }
  console.log(run(process.execPath, ['acceptance.mjs'], {
    env: runtimeEnv, timeout: 240000}));
});
