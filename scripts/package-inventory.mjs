// Read exact package-owned files for staging and ordinary consumers.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {lstat, readFile, readdir} from 'node:fs/promises';
import {join} from 'node:path';

export async function inventory(directory, prefix = '', {ignoreInstalledDependencies = false} = {}) {
  assert.equal(typeof ignoreInstalledDependencies, 'boolean');
  const files = [];
  for (const name of (await readdir(directory)).sort()) {
    // Only the public consumer asks to separate npm's installed dependency
    // subtree from this package's own frozen payload. Archive checks never do.
    if (ignoreInstalledDependencies && prefix === '' && name === 'node_modules') continue;
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
