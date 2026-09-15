// Build the actual common dependency closure in an isolated source tree. No
// connector implementation, Node bridge or generated bundle is
// copied. This complements import/API gates; it is not a whole-repository test.
import {cpSync, mkdtempSync, mkdirSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join, resolve} from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {inspectCore} from './portable-core.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const audit = inspectCore(root);
const {roots} = audit;
const packages = new Set(audit.packages);
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
