import {execFileSync} from 'node:child_process';
import {cpSync, mkdtempSync, mkdirSync} from 'node:fs';
import {join, basename} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';

const root = fileURLToPath(new URL('../',import.meta.url));
execFileSync(process.execPath,['scripts/node-host-fixtures.mjs'],{cwd:root,stdio:'inherit'});
for (const pkg of ['node_host_conformance','connectors_builtin_node']) {
  execFileSync('moon',['build','--target','js','--release',`src/${pkg}`],{cwd:root,stdio:'inherit'});
}
const isolated = mkdtempSync(join(tmpdir(),'actql-node-no-duckdb-'));
for (const path of ['adapters','scripts','package.json']) {
  cpSync(join(root,path),join(isolated,path),{recursive:true,
    filter: path => basename(path) !== 'node_modules'});
}
// Copy the actual compiled product bridge and fixture, not a stub core.
for (const pkg of ['node_host_conformance','connectors_builtin_node']) {
  const directory = `_build/js/release/build/${pkg}`;
  mkdirSync(join(isolated,directory),{recursive:true});
  cpSync(join(root,directory,`${pkg}.js`),join(isolated,directory,`${pkg}.js`));
}
execFileSync(process.execPath,['--input-type=module','-e',`
  import {createRequire} from 'node:module';
  import assert from 'node:assert/strict';
  const require = createRequire(new URL('./adapters/duckdb-node/session.mjs',import.meta.url));
  assert.throws(() => require.resolve('@duckdb/node-api'),{code:'MODULE_NOT_FOUND'});
  await import('./scripts/node-host-subset-fixture.mjs');
`],{cwd:isolated,stdio:'inherit'});
execFileSync(process.execPath,[
  '--test',
  'scripts/connector-node-bundles.test.mjs',
  'adapters/host-node/strategy.test.mjs',
  'adapters/host-common/managed-failure.test.mjs',
],
  {cwd:isolated,stdio:'inherit'});
console.log(`Dependency-free standard-entry evidence retained: ${isolated}`);
