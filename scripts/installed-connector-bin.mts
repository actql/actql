import assert from 'node:assert/strict';
import {constants} from 'node:fs';
import {access, lstat, readlink, readdir, realpath} from 'node:fs/promises';
import {join} from 'node:path';
import {authoringBinPath} from './connector-authoring-toolkit.mjs';

const name = 'actql-connector';
const owner = '@actql/local-node';

// Observe only the actual npm-created POSIX alias of the supported declaration.
// The surrounding consumer independently verifies the installed payload.
export async function inspectInstalledConnectorBins(modules: string,
  manifest: Readonly<{name?: unknown; bin?: unknown}> | null | undefined) {
  const directory = join(modules, '.bin');
  const stat = await lstat(directory).catch(error => {
    if ((error as NodeJS.ErrnoException).code !== 'ENOENT') throw error;
  });
  if (stat) assert(stat.isDirectory(), 'Installed .bin must be a real directory');
  const commands = stat ? await readdir(directory) : [];
  if (manifest?.bin === undefined) {
    assert.deepEqual(commands, [], 'Unexpected installed command link');
    return [];
  }
  assert.equal(manifest.name, owner, 'Installed command belongs to the verified Local Host');
  assert.deepEqual(manifest.bin, {[name]: authoringBinPath}, 'Unexpected Local Host bin declaration');
  assert.deepEqual(commands, [name], 'Unexpected or missing installed command link');
  const path = `.bin/${name}`;
  const alias = join(modules, path);
  assert((await lstat(alias)).isSymbolicLink(), 'Installed command must be an npm link');
  const target = await readlink(alias);
  assert.equal(target, `../${owner}/${authoringBinPath}`, 'Installed command points to the wrong target');
  const executable = join(await realpath(modules), owner, authoringBinPath);
  assert((await lstat(executable)).isFile(), 'Installed command target must be a regular file');
  assert.equal(await realpath(alias), executable, 'Installed command target escapes its package path');
  await access(alias, constants.X_OK);
  return [{path, target}];
}
