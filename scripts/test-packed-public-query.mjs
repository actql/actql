// Install outside the checkout, then run B's unchanged public acceptance
// against Embedded Local and HTTP without a MoonBit toolchain at runtime.
import {spawnSync} from 'node:child_process';
import {readFile, writeFile} from 'node:fs/promises';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {withPackedQueryEvidence} from './packed-query-evidence.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
const scratch = join(repository, '..', '.codex-scratch');
const revision = spawnSync('git', ['rev-parse', 'HEAD'], {cwd: repository,
  encoding: 'utf8'});
if (revision.status !== 0) throw new Error('PackedQueryRevisionUnavailable');
await withPackedQueryEvidence({scratch, revision: revision.stdout.trim(),
  githubOutput: process.env.GITHUB_OUTPUT,
  keepArtifacts: process.argv.includes('--keep-artifacts')},
async ({root, directory, run: capture, recordTarball}) => {
const environment = {...process.env, npm_config_cache: join(root, 'npm-cache')};
function run(command, args, cwd = root, env = environment) {
  return capture(command, args, {cwd, env});
}
console.log(`Packed public-query evidence: ${directory}`);
const packages = ['client-wire', 'sdk', 'run-host-core', 'local-node', 'node'];
for (const name of packages) {
  run('npm', ['pack', '--pack-destination', root, '--json'],
    join(repository, 'packages', name));
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
]) {
  await writeFile(join(root, destination), await readFile(join(repository, source)));
}
run('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048',
  '-keyout', 'remote.key', '-out', 'remote.crt', '-days', '1',
  '-subj', '/CN=localhost',
  '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1']);
const runtimeEnvironment = {...environment,
  PATH: `${dirname(process.execPath)}:/usr/bin:/bin`,
  NODE_EXTRA_CA_CERTS: join(root, 'remote.crt')};
for (const name of ['MOON_HOME', 'ACTQL_LOCAL_SOURCE_PROFILE',
  'ACTQL_LOCAL_EFFECT_PROFILE', 'ACTQL_LOCAL_STATE_DIR']) {
  delete runtimeEnvironment[name];
}
const output = run(process.execPath, ['acceptance.mjs'], root, runtimeEnvironment);
console.log(output.trimEnd());
});
