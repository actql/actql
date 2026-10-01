// Client package tarballs packed once per checkout state and reused by the
// packed acceptance scripts of one CI job. Packing runs each package's
// prepack build, so packing the same packages again in every script repeats
// that build. A script that finds no shared directory packs as before.
//
// `node scripts/packed-client-packages.mjs <directory>` packs the packages
// into <directory> and writes a manifest of the revision and each tarball's
// digest. A script then calls `packedClientPackage(...)`, which copies a
// tarball from the directory named by ACTQL_PACKED_CLIENT_PACKAGES only when
// it was packed from this revision, the packages are unchanged since, and
// its bytes still match the manifest.
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {copyFile, mkdir, readFile, writeFile} from 'node:fs/promises';
import {join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

export const CLIENT_PACKAGES = Object.freeze(['client-wire', 'sdk',
  'run-host-core', 'local-node', 'node']);
const MANIFEST = 'packed-client-packages.json';
const tarball = name => `actql-${name}-0.0.0-development.tgz`;

function git(repository, args) {
  const result = spawnSync('git', args, {cwd: repository, encoding: 'utf8'});
  if (result.status !== 0) {
    throw new Error(`git ${args.join(' ')} failed: ${result.stderr}`);
  }
  return result.stdout.trim();
}

// The checkout state the tarballs stand for: the revision and whether the
// package sources differ from it.
function checkoutState(repository) {
  return {revision: git(repository, ['rev-parse', 'HEAD']),
    clean: git(repository, ['status', '--porcelain', '--', 'packages']) === ''};
}

async function digest(path) {
  return createHash('sha256').update(await readFile(path)).digest('hex');
}

// Put the named package's tarball into `destination`: a verified copy of
// the shared one when available, otherwise `pack(name)`, which must pack it
// into `destination` itself.
export async function packedClientPackage({repository, name, destination,
  pack}) {
  const shared = process.env.ACTQL_PACKED_CLIENT_PACKAGES;
  if (shared === undefined || shared === '') return pack(name);
  const manifest = JSON.parse(await readFile(join(shared, MANIFEST), 'utf8'));
  const state = checkoutState(repository);
  if (manifest.revision !== state.revision || !state.clean) {
    throw new Error(`Shared Client packages were packed from ${
      manifest.revision}, not this checkout (${state.revision}${
      state.clean ? '' : ', packages changed'})`);
  }
  const expected = manifest.tarballs?.[name];
  if (typeof expected !== 'string') {
    throw new Error(`Shared Client packages have no ${name}`);
  }
  const source = join(shared, tarball(name));
  if (await digest(source) !== expected) {
    throw new Error(`Shared ${tarball(name)} changed after packing`);
  }
  await copyFile(source, join(destination, tarball(name)));
  return undefined;
}

// The npm cache a packed acceptance installation uses: shared within one CI
// job when ACTQL_TEST_NPM_CACHE is set, otherwise private to the root.
export function packedNpmCache(root) {
  const shared = process.env.ACTQL_TEST_NPM_CACHE;
  return shared === undefined || shared === '' ? join(root, 'npm-cache')
    : resolve(shared);
}

if (process.argv[1] && resolve(process.argv[1]) ===
    fileURLToPath(import.meta.url)) {
  const destination = process.argv[2];
  if (destination === undefined) {
    throw new Error('usage: packed-client-packages.mjs <directory>');
  }
  const repository = fileURLToPath(new URL('../', import.meta.url));
  const state = checkoutState(repository);
  if (!state.clean) throw new Error('Package sources differ from HEAD');
  await mkdir(destination, {recursive: true});
  const tarballs = {};
  for (const name of CLIENT_PACKAGES) {
    const result = spawnSync('npm', ['pack', '--pack-destination',
      resolve(destination), '--json'], {cwd: join(repository, 'packages',
      name), encoding: 'utf8', timeout: 600_000,
    env: {...process.env, npm_config_cache: packedNpmCache(destination)}});
    if (result.error || result.status !== 0) {
      throw new Error(`npm pack ${name} failed:\n${result.stdout}\n${
        result.stderr}`, {cause: result.error});
    }
    tarballs[name] = await digest(join(destination, tarball(name)));
  }
  await writeFile(join(destination, MANIFEST), `${JSON.stringify({
    revision: state.revision, tarballs}, null, 2)}\n`);
  console.log(`Packed Client packages for ${state.revision}: ${destination}`);
}
