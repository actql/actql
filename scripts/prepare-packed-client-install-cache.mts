import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdtemp, readFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {isAbsolute, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const registry = 'https://registry.npmjs.org/';
const repository = fileURLToPath(new URL('../', import.meta.url));

export function lockedClientTransport(manifest: {
  dependencies?: {undici?: unknown};
}, lock: {
  packages?: {'node_modules/undici'?: {version?: unknown; resolved?: unknown; integrity?: unknown}};
}) {
  const version = manifest.dependencies?.undici;
  const selected = lock.packages?.['node_modules/undici'];
  assert(typeof version === 'string' && /^\d+\.\d+\.\d+$/u.test(version) &&
    selected?.version === version, 'Expected the exact Local transport version in the root npm lock');
  const file = `undici-${version}.tgz`;
  assert.equal(selected.resolved, new URL(`undici/-/${file}`, registry).href,
    'Expected the canonical locked Undici tar URL');
  assert(typeof selected.integrity === 'string' && /^sha512-[A-Za-z0-9+/]{86}==$/u.test(selected.integrity),
    'Expected SHA-512 integrity for the locked Local transport');
  return {specifier: `undici@${version}`, file, integrity: selected.integrity};
}

export async function preparePackedClientInstallCache(cache: string) {
  assert(isAbsolute(cache), 'Expected an absolute runner-private npm cache directory');
  const [manifest, lock] = await Promise.all([
    readFile(join(repository, 'packages/local-node/package.json'), 'utf8'),
    readFile(join(repository, 'package-lock.json'), 'utf8'),
  ]);
  const transport = lockedClientTransport(JSON.parse(manifest), JSON.parse(lock));
  const verification = await mkdtemp(join(tmpdir(), 'actql-client-transport-'));
  try {
    const npm = (args: string[]) => execFileSync('npm', [...args, '--cache', cache,
      '--registry', registry, '--ignore-scripts', '--no-audit', '--no-fund', '--loglevel=error'], {
      cwd: verification, timeout: 60_000, stdio: ['ignore', 'ignore', 'inherit'],
    });
    // A file-based install needs the registry package metadata as well as the tar bytes.
    npm(['cache', 'add', transport.specifier, '--prefer-online', '--fetch-retries=1']);
    npm(['pack', transport.specifier, '--offline', '--pack-destination', verification]);
    const bytes = await readFile(join(verification, transport.file));
    assert.equal('sha512-' + createHash('sha512').update(bytes).digest('base64'), transport.integrity,
      'Cached Undici does not match the root npm lock');
  } finally {
    await rm(verification, {recursive: true, force: true});
  }
}

if (process.argv[1] !== undefined && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const cache = process.argv[2];
  assert(process.argv.length === 3 && cache !== undefined,
    'usage: prepare-packed-client-install-cache.mjs ABSOLUTE_NPM_CACHE');
  await preparePackedClientInstallCache(cache);
}
