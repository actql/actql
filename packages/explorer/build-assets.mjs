import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {lstat, readFile, readdir, writeFile} from 'node:fs/promises';
import {loadExplorerAssets} from './assets.mjs';
const root = new URL('./dist/', import.meta.url), assets = [];
async function visit(directory, prefix = '') {
  for (const name of (await readdir(directory)).sort()) {
    const path = new URL(name, directory), stat = await lstat(path);
    assert(!stat.isSymbolicLink(), 'Built assets cannot contain symlinks');
    if (stat.isDirectory()) await visit(new URL(`${name}/`, directory), `${prefix}${name}/`);
    else {
      assert(stat.isFile(), 'Built assets must be regular files');
      const bytes = await readFile(path);
      assets.push({path: `/${prefix}${name}`, bytes: bytes.length,
        sha256: createHash('sha256').update(bytes).digest('hex')});
    }
  }
}
await visit(root);
await writeFile(new URL('assets.json', root), `${JSON.stringify({
  version: 'actql-explorer-assets/0.1', assets}, null, 2)}\n`);
await loadExplorerAssets();
console.log(`Frozen Explorer assets: ${assets.length}, ${assets.reduce((n, a) => n + a.bytes, 0)} bytes`);
