import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {copyFile, readFile, readdir, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createOwnedScratch} from './owned-scratch.mjs';
import {packedClientPackage, packedNpmCache} from './packed-client-packages.mjs';
import {auditPackedPackages} from './packed-package-boundaries.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
const names = ['client-wire', 'sdk', 'local-node', 'node'];
const scratch = await createOwnedScratch({parent: tmpdir(),
  prefix: 'actql-packed-no-duckdb-', label: 'packed dependency-free Local',
  digests: () => names.map(name => `actql-${name}-0.0.0-development.tgz`)});
const root = scratch.path;
const environment = {...process.env, npm_config_cache: packedNpmCache(root)};
delete environment.NODE_PATH;
delete environment.ACTQL_LOCAL_SOURCE_PROFILE;
delete environment.ACTQL_LOCAL_EFFECT_PROFILE;
function run(command, args, cwd = root) {
  const result = spawnSync(command, args, {cwd, env: environment,
    encoding: 'utf8', timeout: command === 'npm' ? 180_000 : 60_000});
  assert.equal(result.status, 0, `${command} ${args.join(' ')}\n${result.stdout}\n${result.stderr}`);
  return result.stdout;
}
for (const name of names) {
  await packedClientPackage({repository, name, destination: root,
    pack: () => run('npm', ['pack', '--pack-destination', root, '--json'],
      join(repository, 'packages', name))});
}
await writeFile(join(root, 'package.json'), '{"private":true,"type":"module"}\n');
// Ordinary npm installation: optional peers must not be downloaded implicitly.
console.log(run('npm', ['install', '--ignore-scripts', '--no-save', '--no-audit',
  '--no-fund', ...names.map(name => join(root, `actql-${name}-0.0.0-development.tgz`))]));
assert.deepEqual((await readdir(join(root, 'node_modules'))).filter(name =>
  name !== '.package-lock.json').sort(), ['@actql']);
const manifest = JSON.parse(await readFile(join(root,
  'node_modules/@actql/local-node/package.json'), 'utf8'));
assert.equal(manifest.dependencies['@duckdb/node-api'], undefined);
assert.equal(manifest.peerDependencies['@duckdb/node-api'], '1.5.5-r.4');
assert.equal(manifest.peerDependenciesMeta['@duckdb/node-api'].optional, true);
auditPackedPackages(root, names);
await copyFile(join(repository, 'packages/sdk/fixtures/values.json'), join(root, 'values.json'));
await copyFile(join(repository, 'adapters/host-node/fixtures/query-amount-environment.json'),
  join(root, 'source-environment.json'));
await copyFile(join(repository, 'spec/local-check-environment.json'), join(root, 'base-environment.json'));
await copyFile(join(repository, 'scripts/fixtures/packed-local-without-duckdb.mjs'),
  join(root, 'acceptance.mjs'));
console.log(run(process.execPath, ['acceptance.mjs', 'initial']).trimEnd());
console.log(run(process.execPath, ['acceptance.mjs', 'restart']).trimEnd());
await copyFile(join(repository, 'scripts/fixtures/packed-short-queries.mjs'),
  join(root, 'short-queries.mjs'));
await copyFile(join(repository, 'scripts/fixtures/run-revision-assertions.mjs'),
  join(root, 'run-revision-assertions.mjs'));
await copyFile(join(repository, 'scripts/fixtures/client-cleanup.mjs'),
  join(root, 'client-cleanup.mjs'));
await copyFile(join(repository, 'scripts/fixtures/packed-short-queries.typecheck.mts'),
  join(root, 'short-queries.typecheck.mts'));
await copyFile(join(repository, 'packages/local-node/source-inventory.typecheck.mts'),
  join(root, 'source-inventory.typecheck.mts'));
await copyFile(join(repository, 'packages/local-node/effect-inventory.typecheck.mts'),
  join(root, 'effect-inventory.typecheck.mts'));
// Reuse the pinned compiler, but resolve public imports from the isolated
// consumer. No schema dependency is installed just to make declarations work.
console.log(run(process.execPath, [join(repository, 'node_modules/typescript/bin/tsc'),
  '--strict', '--target', 'ES2022', '--module', 'NodeNext',
  '--moduleResolution', 'NodeNext', '--noEmit', 'short-queries.typecheck.mts',
  'source-inventory.typecheck.mts', 'effect-inventory.typecheck.mts']).trimEnd());
run('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048',
  '-keyout', 'remote.key', '-out', 'remote.crt', '-days', '1',
  '-subj', '/CN=localhost', '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1']);
environment.NODE_EXTRA_CA_CERTS = join(root, 'remote.crt');
console.log(run(process.execPath, ['short-queries.mjs']).trimEnd());
scratch.passed();
