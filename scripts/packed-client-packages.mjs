// Client package tarballs packed once per checkout state and reused by the
// packed acceptance scripts of one CI job. Packing runs each package's
// prepack build, so packing the same packages again in every script repeats
// that build. A script that finds no shared directory packs as before.
//
// `node scripts/packed-client-packages.mjs <directory>` packs the packages
// into <directory> and writes a manifest of the revision and each tarball's
// digest. A script then calls `packedClientPackage(...)`, which copies a
// tarball from the directory named by ACTQL_PACKED_CLIENT_PACKAGES only when
// it was packed from this revision with no change to any build input, and
// its bytes still match the manifest.
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {copyFile, mkdir, readFile, writeFile} from 'node:fs/promises';
import {existsSync, readFileSync, realpathSync} from 'node:fs';
import {isAbsolute, join, relative, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

export const CLIENT_PACKAGES = Object.freeze(['client-wire', 'sdk',
  'run-host-core', 'local-node', 'node']);
const MANIFEST = 'packed-client-packages.json';
const tarball = name => `actql-${name}-0.0.0-development.tgz`;

// Normal lifecycle-enabled readers need one uncontaminated npm JSON value.
// Other npm options remain the caller's DATA; npm owns their interpretation.
export function normalNpmPackJsonArgs(args) {
  if (!Array.isArray(args) || args.some(value => typeof value !== 'string') ||
      args[0] !== 'pack' || args.filter(value => /^--json(?:=|$)/u.test(value)).length !== 1 ||
      !args.includes('--json') ||
      args.some(value => /^--(?:ignore-scripts|foreground-scripts)(?:=|$)/u.test(value))) {
    throw new TypeError('Normal npm pack JSON arguments required');
  }
  return [...args, '--foreground-scripts=false'];
}

// Never recover a JSON suffix from lifecycle diagnostics. The normal pack
// argument policy isolates those diagnostics; malformed output still refuses.
export function parseNpmPackJson(output) {
  return JSON.parse(output);
}

function git(repository, args) {
  const result = spawnSync('git', args, {cwd: repository, encoding: 'utf8'});
  if (result.status !== 0) {
    throw new Error(`git ${args.join(' ')} failed: ${result.stderr}`);
  }
  return result.stdout.trim();
}

// Directories a pack reads: the packages themselves, and the MoonBit
// sources, Host adapters, bundled contracts and generators their prepack
// builds use. Normative generation reads also include the portability corpus
// and specification text. Generated output and scratch are git-ignored.
export const BUILD_INPUTS = Object.freeze(['packages', 'src', 'adapters',
  'spec', 'scripts', 'release', 'portability', 'docs/spec']);

// Fresh CI producers retain the same source-input policy plus the exact
// references read by the required, original interface validator. This is
// acquisition DATA, not another interface classifier or admission result.
export async function normalPackSourceInputs(repository, listed) {
  const root = realpathSync(repository), available = new Set(listed);
  const selected = new Set(listed.filter(path => !path.includes('/') ||
    BUILD_INPUTS.some(prefix => path.startsWith(prefix + '/'))));
  const {interfaceOwnerDeclarations} = await import('./interface-owner-discovery.mjs');
  const {assertInterfaceCoverage} = await import('./interface-inventory.mjs');
  const readReference = path => {
    if (!available.has(path)) throw new Error(`UnlistedNormalPackSourceReference:${path}`);
    const actual = realpathSync(resolve(root, path)), child = relative(root, actual);
    if (isAbsolute(child) || child === '..' || child.startsWith('../')) {
      throw new Error(`EscapedNormalPackSourceReference:${path}`);
    }
    selected.add(path);
    return readFileSync(actual, 'utf8');
  };
  const checked = new Set();
  for (;;) {
    const owners = interfaceOwnerDeclarations(root, [...selected]).filter(owner => !checked.has(owner.id));
    if (!owners.length) break;
    for (const owner of owners) {
      // Use the same attribute/reference checks as normal prepack. The real
      // module/primary/generation check still runs in that original entrance.
      assertInterfaceCoverage({root, modules: [], declarations: owner.declarations, readReference});
      checked.add(owner.id);
    }
  }
  return [...selected];
}

// A private Git index describes only the files actually copied to this fresh
// fixture. It has no commit/revision claim and borrows no source Git history.
export function initializeNormalPackSourceIndex(directory, paths) {
  if (existsSync(join(directory, '.git'))) throw new Error('Normal pack source index already exists');
  const environment = Object.fromEntries(Object.entries(process.env)
    .filter(([key]) => !key.startsWith('GIT_')));
  for (const path of paths) {
    if (typeof path !== 'string' || !path || isAbsolute(path) ||
        path.split('/').some(part => !part || ['.', '..', '.git'].includes(part)) || path.includes('\0')) {
      throw new TypeError('Concrete normal pack source path required');
    }
  }
  if (new Set(paths).size !== paths.length) throw new TypeError('Duplicate normal pack source path');
  const run = (args, input) => {
    const result = spawnSync('git', args, {cwd: directory, env: environment,
      encoding: 'utf8', input, maxBuffer: 16 * 1024 * 1024});
    if (result.error || result.status !== 0) throw new Error(
      `NormalPackSourceIndexFailed:${result.stderr}`, {cause: result.error});
  };
  run(['init', '--quiet']);
  run(['--literal-pathspecs', 'add', '--force', '--pathspec-from-file=-', '--pathspec-file-nul'],
    paths.map(path => path + '\0').join(''));
}

// The checkout state the tarballs stand for: the revision, and whether
// anything a pack reads differs from it. Any tracked change in the
// repository counts, as does any untracked, non-ignored file in a build
// input directory.
export function checkoutState(repository) {
  const tracked = git(repository, ['status', '--porcelain',
    '--untracked-files=no']);
  const untracked = git(repository, ['status', '--porcelain',
    '--untracked-files=all', '--', ...BUILD_INPUTS]);
  return {revision: git(repository, ['rev-parse', 'HEAD']),
    clean: tracked === '' && untracked === ''};
}

function sameState(before, after) {
  return before.clean && after.clean && before.revision === after.revision;
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
      state.clean ? '' : ', build inputs changed'})`);
  }
  const expected = manifest.tarballs?.[name];
  if (typeof expected !== 'string') {
    throw new Error(`Shared Client packages have no ${name}`);
  }
  const source = join(shared, tarball(name));
  if (await digest(source) !== expected) {
    throw new Error(`Shared ${tarball(name)} changed after packing`);
  }
  const target = join(destination, tarball(name));
  await copyFile(source, target);
  if (await digest(target) !== expected) {
    throw new Error(`Shared ${tarball(name)} changed while copying`);
  }
  return undefined;
}

// Acquired-source consumers opt into the same exact native transport pin as
// the source adapter. Source-free package consumers leave this peer absent.
export async function pinnedDuckDBPackage(repository) {
  const manifest = JSON.parse(await readFile(join(repository,
    'adapters/connectors/duckdb/node/package.json'), 'utf8'));
  const version = manifest.dependencies?.['@duckdb/node-api'];
  if (typeof version !== 'string' || version === '') {
    throw new Error('MissingPinnedDuckDBDependency');
  }
  return `@duckdb/node-api@${version}`;
}

// The npm cache a packed acceptance installation uses: shared within one CI
// job when ACTQL_TEST_NPM_CACHE is set, otherwise private to the root.
export function packedNpmCache(root) {
  const shared = process.env.ACTQL_TEST_NPM_CACHE;
  return shared === undefined || shared === '' ? join(root, 'npm-cache')
    : resolve(shared);
}

// Pack `names` from `repository` into `destination` and record the manifest.
// `pack(name)` must write that package's tarball into `destination`. The
// manifest is written only when the build inputs are unchanged from the
// revision before the first pack and after the last.
export async function packClientPackages({repository, destination,
  names = CLIENT_PACKAGES, pack}) {
  const state = checkoutState(repository);
  if (!state.clean) throw new Error('Build inputs differ from HEAD');
  await mkdir(destination, {recursive: true});
  const tarballs = {};
  for (const name of names) {
    await pack(name);
    tarballs[name] = await digest(join(destination, tarball(name)));
  }
  // The manifest stands for this revision only if nothing changed while the
  // packages were packed.
  if (!sameState(state, checkoutState(repository))) {
    throw new Error('Build inputs changed while packing');
  }
  await writeFile(join(destination, MANIFEST), `${JSON.stringify({
    revision: state.revision, tarballs}, null, 2)}\n`);
  return state.revision;
}

if (process.argv[1] && resolve(process.argv[1]) ===
    fileURLToPath(import.meta.url)) {
  const destination = process.argv[2];
  if (destination === undefined) {
    throw new Error('usage: packed-client-packages.mjs <directory>');
  }
  const repository = fileURLToPath(new URL('../', import.meta.url));
  const revision = await packClientPackages({repository, destination,
    pack: name => {
      const result = spawnSync('npm', ['pack', '--pack-destination',
        resolve(destination), '--json'], {cwd: join(repository, 'packages',
        name), encoding: 'utf8', timeout: 600_000,
      env: {...process.env, npm_config_cache: packedNpmCache(destination)}});
      if (result.error || result.status !== 0) {
        throw new Error(`npm pack ${name} failed:\n${result.stdout}\n${
          result.stderr}`, {cause: result.error});
      }
    }});
  console.log(`Packed Client packages for ${revision}: ${destination}`);
}
