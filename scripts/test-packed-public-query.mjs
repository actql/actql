// Install outside the checkout, then run B's unchanged public acceptance
// against Embedded Local and HTTP without a MoonBit toolchain at runtime.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdir, mkdtemp, readFile, writeFile} from 'node:fs/promises';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';

const repository = fileURLToPath(new URL('../', import.meta.url));
const scratch = join(repository, '..', '.codex-scratch');
await mkdir(scratch, {recursive: true});
const root = await mkdtemp(join(scratch, 'public-query-package-'));
const environment = {...process.env, npm_config_cache: join(root, 'npm-cache')};
function run(command, args, cwd = root, env = environment) {
  const result = spawnSync(command, args, {cwd, env, encoding: 'utf8',
    timeout: 240_000, maxBuffer: 8 * 1024 * 1024});
  assert.equal(result.status, 0,
    `${command}: ${result.error ?? ''}\n${result.stdout}\n${result.stderr}`);
  return result.stdout;
}
console.log(`Packed public-query evidence: ${root}`);
const packages = ['client-wire', 'sdk', 'run-host-core', 'local-node', 'node'];
for (const name of packages) {
  run('npm', ['pack', '--pack-destination', root, '--json'],
    join(repository, 'packages', name));
}
await writeFile(join(root, 'package.json'), '{"private":true,"type":"module"}\n');
run('npm', ['install', '--ignore-scripts', '--no-save', ...packages.map(name =>
  join(root, `actql-${name}-0.0.0-development.tgz`))]);
for (const [source, destination] of [
  ['scripts/fixtures/public-query-input.mjs', 'public-query-input.mjs'],
  ['scripts/fixtures/packed-public-query.mjs', 'acceptance.mjs'],
  ['adapters/host-node/fixtures/query-amount-environment.json', 'source-environment.json'],
  ['spec/local-check-environment.json', 'base-environment.json'],
  ['scripts/accept-sga-public-source.mjs', 'accept-sga-public-source.mjs'],
]) {
  await writeFile(join(root, destination), await readFile(join(repository, source)));
}
await mkdir(join(root, 'sga-source-fixtures'));
for (const name of ['normalize-rows']) {
  for (const suffix of ['named.aql', 'expected-results.json']) {
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
for (const name of ['MOON_HOME', 'ACTQL_LOCAL_SOURCE_PROFILE',
  'ACTQL_LOCAL_EFFECT_PROFILE', 'ACTQL_LOCAL_STATE_DIR']) {
  delete runtimeEnvironment[name];
}
const output = run(process.execPath, ['acceptance.mjs'], root, runtimeEnvironment);
await writeFile(join(root, 'acceptance.log'), output);
console.log(output.trimEnd());
