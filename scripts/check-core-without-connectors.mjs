// Build the actual common dependency closure in an isolated source tree. No
// connector implementation, query_planning, Node bridge or generated bundle is
// copied. This complements import/API gates; it is not a whole-repository test.
import {cpSync, mkdtempSync, mkdirSync, readFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join, resolve} from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const roots = ['connector_sdk', 'physical_host', 'physical_strategy'];
const packages = new Set();
const pending = [...roots];
while (pending.length) {
  const name = pending.pop();
  if (packages.has(name)) continue;
  if (!/^[a-z0-9_]+(?:\/[a-z0-9_]+)*$/.test(name) ||
      /^(?:connectors\/|duckdb_|query_planning$)/.test(name)) {
    throw new Error(`Concrete or invalid common dependency: ${name}`);
  }
  packages.add(name);
  const manifest = readFileSync(join(root, 'src', name, 'moon.pkg'), 'utf8');
  for (const match of manifest.matchAll(/"actql\/actql\/([^"]+)"/g)) {
    pending.push(match[1]);
  }
}
const isolated = mkdtempSync(join(tmpdir(), 'actql-common-closure-'));
cpSync(join(root, 'moon.mod'), join(isolated, 'moon.mod'));
for (const name of [...packages].sort()) {
  const destination = join(isolated, 'src', name);
  mkdirSync(resolve(destination, '..'), {recursive: true});
  cpSync(join(root, 'src', name), destination, {recursive: true});
}
console.log(JSON.stringify({roots, packages: packages.size, isolated}));
const result = spawnSync('moon', ['check', '--target', 'all', '--deny-warn'], {
  cwd: isolated, env: process.env, stdio: 'inherit',
});
if (result.error) throw result.error;
if (result.status !== 0) process.exit(result.status ?? 1);
console.log('Common closure checks without concrete connectors; isolated tree retained.');
