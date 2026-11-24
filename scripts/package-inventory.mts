// Read exact package-owned files for staging and ordinary consumers.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {lstat, readFile, readdir} from 'node:fs/promises';
import {join} from 'node:path';

type PackageFile = Readonly<{path: string; bytes: number; mode: number; sha256: string}>;

export async function inventory(directory: string, prefix = '', {ignoreInstalledDependencies = false} = {}): Promise<PackageFile[]> {
  assert.equal(typeof ignoreInstalledDependencies, 'boolean');
  const names = (await readdir(directory)).sort();
  // Only the public consumer separates the installed dependency subtree from
  // this package's own frozen payload. Archive checks never do.
  return inventoryEntries(directory, prefix, ignoreInstalledDependencies && prefix === ''
    ? names.filter(name => name !== 'node_modules') : names);
}

// Health checks the npm-created root .bin separately. Nested .bin directories
// and all package and archive files still go through the strict walk.
export async function installedModulesPayloadInventory(directory: string) {
  assert((await lstat(directory)).isDirectory(), 'Installed node_modules must be a real directory');
  const names = (await readdir(directory)).sort().filter(name => name !== '.bin');
  return inventoryEntries(directory, '', names);
}

async function inventoryEntries(directory: string, prefix: string, names: readonly string[]): Promise<PackageFile[]> {
  const files: PackageFile[] = [];
  for (const name of names) {
    const path = join(directory, name), relative = prefix + name;
    const stat = await lstat(path);
    assert(!stat.isSymbolicLink(), `Release payload symlink: ${relative}`);
    if (stat.isDirectory()) files.push(...await inventory(path, `${relative}/`));
    else {
      assert(stat.isFile(), `Non-file payload: ${relative}`);
      files.push({path: relative, bytes: stat.size, mode: stat.mode & 0o777,
        sha256: createHash('sha256').update(await readFile(path)).digest('hex')});
    }
  }
  return files;
}
