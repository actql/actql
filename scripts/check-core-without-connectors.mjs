// Build the actual common dependency closure in an isolated source tree. No
// connector implementation, Node bridge or generated bundle is
// copied. This complements import/API gates; it is not a whole-repository test.
import {tmpdir} from 'node:os';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {copyProductionCore} from './portable-core.mjs';
import {createOwnedScratch} from './owned-scratch.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const scratch = await createOwnedScratch({parent: tmpdir(),
  prefix: 'actql-common-closure-', label: 'Common dependency isolation'});
const isolated = scratch.path;
const audit = copyProductionCore(root, isolated);
console.log(JSON.stringify({roots: audit.roots, packages: audit.packages.length, isolated}));
const result = spawnSync('moon', ['check', '--target', 'all', '--deny-warn'], {
  cwd: isolated, env: process.env, stdio: 'inherit',
});
if (result.error) throw result.error;
if (result.status !== 0) process.exit(result.status ?? 1);
console.log('Common closure checks without concrete connectors passed.');
scratch.passed();
