// Verification-only preparation for the ordinary Node/Local package exports.
// Keep links private to each source package: never mutate borrowed root deps.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {lstat, mkdir, readFile, readlink, realpath, symlink} from 'node:fs/promises';
import {dirname, join, relative, resolve} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';

const root = fileURLToPath(new URL('../../../', import.meta.url));
async function directory(path) {
  let stat;
  try { stat = await lstat(path); }
  catch (error) {
    if (error.code !== 'ENOENT') throw error;
    await mkdir(path);
    stat = await lstat(path);
  }
  assert(stat.isDirectory() && !stat.isSymbolicLink(), `Non-private source dependency directory: ${path}`);
}

async function sourceLink(link, target) {
  let stat;
  try { stat = await lstat(link); }
  catch (error) {
    if (error.code !== 'ENOENT') throw error;
    await symlink(relative(dirname(link), target), link, 'dir');
    stat = await lstat(link);
  }
  assert(stat.isSymbolicLink() && resolve(dirname(link), await readlink(link)) === target,
    `Existing source dependency conflict: ${link}`);
}

export async function prepareSourceNodeClient({assemble = false} = {}) {
  const dependencies = {
    node: ['sdk', 'local-node'], sdk: ['client-wire'],
    'local-node': ['sdk', 'client-wire', 'run-host-core'],
    'run-host-core': ['client-wire'],
  };
  for (const [name, children] of Object.entries(dependencies)) {
    const modules = join(root, 'packages', name, 'node_modules');
    await directory(modules);
    const scope = join(modules, '@actql');
    await directory(scope);
    for (const child of children) {
      const link = join(scope, child), target = join(root, 'packages', child);
      await sourceLink(link, target);
    }
  }
  // Reuse the already-installed, pinned adapter dependency without changing
  // its borrowed directory or installing another native dependency copy.
  const adapter = join(root, 'adapters/connectors/duckdb/node');
  const required = JSON.parse(await readFile(join(adapter, 'package.json'), 'utf8'))
    .dependencies['@duckdb/node-api'];
  const api = await realpath(join(adapter, 'node_modules/@duckdb/node-api'));
  assert.equal(JSON.parse(await readFile(join(api, 'package.json'), 'utf8')).version, required);
  const scope = join(root, 'packages/local-node/node_modules/@duckdb');
  await directory(scope);
  await sourceLink(join(scope, 'node-api'), api);
  if (assemble) {
    for (const args of [[], ['--check']]) {
      execFileSync(process.execPath, ['scripts/build-local-node-adapters.mjs', ...args],
        {cwd: root, stdio: 'inherit'});
    }
  }
  return import(pathToFileURL(join(root, 'packages/node/index.mjs')));
}
