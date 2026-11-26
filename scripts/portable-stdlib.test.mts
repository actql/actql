import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync, mkdtempSync, mkdirSync, writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {auditedImports, inspectStdlib} from './portable-stdlib.mjs';

test('pinned runtime closure includes implicit dependencies and matches exact source inventory', () => {
  const root = new URL('../',import.meta.url).pathname;
  const recorded = JSON.parse(readFileSync(join(root,'scripts/fixtures/portable-stdlib.json'),'utf8'));
  assert.deepEqual(inspectStdlib(root,process.env.MOON_HOME,recorded),recorded);
  assert.ok(recorded.packages.prelude);
  assert.ok(recorded.packages.builtin);
  assert.ok(recorded.packages['internal/regex_engine/automata']);
  assert.throws(() => inspectStdlib(root,process.env.MOON_HOME,{...recorded,version:'different'}),
    /UnauditedStdlibVersion/);
  const changed = structuredClone(recorded);
  changed.packages.builtin.digest = 'unreviewed';
  assert.throws(() => inspectStdlib(root,process.env.MOON_HOME,changed),/UnauditedStdlibSource: builtin/);
});

test('review recording cannot turn an unknown transitive package into a namespace exemption', t => {
  const root = mkdtempSync(join(tmpdir(),'actql-stdlib-negative-'));
  t.diagnostic(`isolated fixture retained: ${root}`);
  mkdirSync(join(root,'src/root'),{recursive:true});
  writeFileSync(join(root,'moon.mod'),'name = "actql/actql"\nsource = "src"');
  // Explicit Core roots remain mandatory; reuse each as an empty neutral package.
  for (const name of ['program_check','lowering_relation','execution_relation','query_planning',
    'connector_sdk','physical_strategy','physical_host']) {
    mkdirSync(join(root,'src',name),{recursive:true});
    writeFileSync(join(root,'src',name,'moon.pkg'),'supported_targets = "+js+wasm+native"');
  }
  writeFileSync(join(root,'toolchain.json'),JSON.stringify({version:'test',core:{sha256:'test'}}));
  for (const name of ['prelude','builtin']) mkdirSync(join(root,'lib/core',name),{recursive:true});
  writeFileSync(join(root,'lib/core/prelude/moon.pkg'),'import { "moonbitlang/core/env" }');
  writeFileSync(join(root,'lib/core/builtin/moon.pkg'),'');
  assert.throws(() => inspectStdlib(root,root,undefined,true),/UnreviewedStdlibPackage: env/);
});

test('runtime import extraction distinguishes aliases test scopes and comments', () => {
  assert.deepEqual(auditedImports(`
    // import { "unreviewed" }
    import { "moonbitlang/core/builtin" @runtime, }
    import { "moonbitlang/core/test" } for "test"
    import { "moonbitlang/core/random" } for "wbtest"
  `),['moonbitlang/core/builtin']);
  assert.throws(() => auditedImports('import { "anything" } for "native"'),/UnauditedStdlibScope/);
});
