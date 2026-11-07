// One consumer of the current run's immutable normal tarballs. No pack/build
// callback, checkout import, runtime overlay or optional Native dependency.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {copyFile, mkdir, realpath, writeFile} from 'node:fs/promises';
import {join, relative, isAbsolute} from 'node:path';
import {fileURLToPath} from 'node:url';
import {CLIENT_PACKAGES, checkoutState, packedClientPackage} from './packed-client-packages.mjs';
import {inventory, unpack} from './package-release.mjs';
import {createOwnedScratch} from './owned-scratch.mjs';

export const supportedNodeCases = Object.freeze([
  {profile: 'sdk', version: '22.0.0'}, {profile: 'sdk', version: '26.13.0'},
  {profile: 'local', version: '22.16.0'}, {profile: 'local', version: '26.13.0'},
]);
const repository = fileURLToPath(new URL('../', import.meta.url));
export async function acceptSupportedNode({profile, version, parent}) {
  assert(supportedNodeCases.some(entry => entry.profile === profile && entry.version === version), 'Unselected supported-version case');
  assert.equal(process.versions.node, version, 'Consumer interpreter differs from the selected version');
  assert(process.env.ACTQL_PACKED_CLIENT_PACKAGES, 'Matching same-run normal tarballs are required');
  parent = await realpath(parent);
  const child = relative(await realpath(repository), parent);
  assert(child === '..' || child.startsWith('../') || isAbsolute(child), 'Fresh consumer must be outside checkout');
  const source = checkoutState(repository); assert(source.clean);
  const scratch = await createOwnedScratch({parent, prefix: `supported-${profile}-${version}-`, label: 'Supported Node version'});
  const consumer = join(scratch.path, 'consumer'); await mkdir(consumer);
  await writeFile(join(consumer, 'package.json'), '{"private":true,"type":"module"}\n');
  const names = profile === 'sdk' ? ['client-wire', 'sdk'] : CLIENT_PACKAGES;
  const originals = [];
  for (const name of names) {
    await packedClientPackage({repository, name, destination: scratch.path,
      pack() { throw new Error('Supported-version acceptance cannot build packages'); }});
    const tar = join(scratch.path, `actql-${name}-0.0.0-development.tgz`);
    const directory = await unpack(tar, join(scratch.path, 'original-' + name));
    originals.push({name, tar, files: await inventory(directory)});
  }
  const env = {...process.env}; delete env.NODE_PATH; delete env.NODE_OPTIONS;
  delete env.ACTQL_LOCAL_SOURCE_PROFILE; delete env.ACTQL_LOCAL_EFFECT_PROFILE;
  const run = (command, args, timeout) => {
    const result = spawnSync(command, args, {cwd: consumer, env, encoding: 'utf8', timeout, maxBuffer: 4 * 1024 * 1024});
    assert.ifError(result.error); assert.equal(result.signal, null, result.stderr);
    assert.equal(result.status, 0, result.stdout + result.stderr); return result.stdout;
  };
  run('npm', ['install', '--engine-strict', '--offline', '--ignore-scripts', '--no-audit', '--no-fund', '--no-save', '--omit=optional',
    ...originals.map(entry => entry.tar)], 120000);
  const audit = async () => {
    for (const entry of originals) assert.deepEqual(await inventory(join(consumer, 'node_modules/@actql', entry.name)), entry.files);
  };
  await audit();
  await copyFile(join(repository, 'scripts/fixtures/ci-supported-node.mjs'), join(consumer, 'acceptance.mjs'));
  console.log(run(process.execPath, ['acceptance.mjs', profile, version], 120000).trimEnd());
  await audit(); assert.deepEqual(checkoutState(repository), source);
  scratch.passed();
}
if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const [profile, version, parent] = process.argv.slice(2);
  await acceptSupportedNode({profile, version, parent});
}
