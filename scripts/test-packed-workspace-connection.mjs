import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {copyFile, mkdir, readFile, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createOwnedScratch} from './owned-scratch.mjs';
import {packedClientPackage} from './packed-client-packages.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
const loopbackHttp = process.argv.includes('--loopback-http');
const scratch = await createOwnedScratch({parent: join(repository, '..', '.codex-scratch'),
  prefix: 'packed-workspace-dsn-', label: 'packed Workspace DSN',
  digests: () => ['client-wire', 'sdk', 'local-node', 'node'].map(
    name => `actql-${name}-0.0.0-development.tgz`)});
const root = scratch.path;
const run = (command, args, cwd, timeout = 120000) => {
  const result = spawnSync(command, args, {cwd, encoding: 'utf8', timeout,
    env: {...process.env, npm_config_cache: join(repository, '_build/npm-cache')}});
  if (result.error || result.status !== 0) {
    throw new Error(`PackedWorkspaceCommandFailed:${command}\n${result.stdout}\n${result.stderr}`);
  }
  return result.stdout;
};
await mkdir(join(root, 'application'));
const tarballs = [];
for (const name of ['client-wire', 'sdk', 'local-node', 'node']) {
  await packedClientPackage({repository, name, destination: root,
    pack: () => run('npm', ['pack', '--json', '--pack-destination', root],
      join(repository, 'packages', name), 180000)});
  tarballs.push(join(root, `actql-${name}-0.0.0-development.tgz`));
}
const application = join(root, 'application');
await writeFile(join(application, 'package.json'), JSON.stringify({private: true, type: 'module'}));
run('npm', ['install', '--ignore-scripts', '--offline', '--no-audit', '--no-fund',
  '--omit=optional', ...tarballs], application);
await copyFile(join(repository, 'scripts/fixtures/workspace-dsn-acceptance.mjs'),
  join(application, 'fixture.mjs'));
await writeFile(join(application, 'acceptance.mjs'), `
import * as sdk from '@actql/sdk';
import * as node from '@actql/node';
import {openInstalledRemoteHttpHost} from '@actql/local-node/http-host';
import {exerciseWorkspaceConnection} from './fixture.mjs';
const evidence = await exerciseWorkspaceConnection({directory: process.cwd(), sdk, node,
  openHost: openInstalledRemoteHttpHost, loopbackHttp: ${loopbackHttp}});
console.log('PACKED_WORKSPACE_DSN', JSON.stringify(evidence));
`);
const result = run(process.execPath, ['acceptance.mjs'], application, 30000);
assert.match(result, /PACKED_WORKSPACE_DSN/);
const line = result.split('\n').find(value => value.startsWith('PACKED_WORKSPACE_DSN '));
const evidence = JSON.parse(line.slice('PACKED_WORKSPACE_DSN '.length));
assert.deepEqual(evidence.counts, {A: 1, B: 1});
assert.equal(evidence.unexpectedDispatches, 0);
await writeFile(join(application, 'usage.mts'), `
import {connect, type Client} from '@actql/sdk';
import {connect as connectNode} from '@actql/node';
import {openInstalledRemoteHttpHost} from '@actql/local-node/http-host';
const hostOptions: Parameters<typeof openInstalledRemoteHttpHost>[0] = {
  directory: '/fixture', workspaceId: 'workspace', loopbackHttp: true,
  authenticate: async () => 'fixture',
};
void hostOptions;
const dsn = 'actql://example.test/workspace';
const a: Promise<Client> = connect(dsn, {token: 'fixture'});
const b: Promise<Client> = connectNode(dsn, {token: async () => 'fixture'});
const c: Promise<Client> = connect({mode: 'remote', endpoint: 'https://example.test',
  token: 'fixture', workspaceId: 'workspace'});
const local: Promise<Client> = connectNode('actql://localhost:8080/workspace?transport=http',
  {token: 'fixture'});
// @ts-expect-error DSN transport has no arbitrary endpoint override.
connect(dsn, {endpoint: 'https://other.test', token: 'fixture'});
// @ts-expect-error Embedded Local has no remote credential.
connectNode({mode: 'local', owner: 'local', token: 'fixture'});
void [a, b, c, local];
`);
run(process.execPath, [join(repository, 'node_modules/typescript/bin/tsc'),
  '--noEmit', '--strict', '--module', 'NodeNext', '--moduleResolution', 'NodeNext',
  '--target', 'ES2022', 'usage.mts'], application);
// The production consumer is installed, not linked to source or a workspace.
const manifest = JSON.parse(await readFile(join(application, 'node_modules/@actql/sdk/package.json'), 'utf8'));
assert.deepEqual(manifest.dependencies, {'@actql/client-wire': '0.0.0-development'});
assert.deepEqual(manifest.imports['#loopback-http'], {
  node: './loopback-http.mjs', default: './loopback-http-unavailable.mjs'});
console.log('PACKED_WORKSPACE_DSN', JSON.stringify({...evidence, publicTypes: true}));
scratch.passed();
