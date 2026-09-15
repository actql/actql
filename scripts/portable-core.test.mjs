import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync, mkdirSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {inspectCore, packageImports} from './portable-core.mjs';

const manifest = 'supported_targets = "+js+wasm+native"\n';
function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'actql-portable-negative-'));
  t.diagnostic(`isolated fixture retained: ${root}`);
  const put = (name, file, text) => {
    const path = join(root, 'src', name);
    mkdirSync(path, {recursive:true}); writeFileSync(join(path, file), text);
  };
  put('root', 'moon.pkg', manifest);
  put('root', 'main.mbt', 'pub fn identity(x : Int) -> Int { x }');
  return {root, put, check:() => inspectCore(root, ['root'])};
}

test('production dependencies distinguish test scopes, aliases and comments', t => {
  const f = fixture(t);
  f.put('root', 'moon.pkg', manifest + `
    // Node I/O is allowed in tests, not a production import.
    import { "moonbitlang/core/env" @innocent, } for "wbtest"
    import { "actql/actql/connectors/duckdb/adapter", } for "test"
    import { "moonbitlang/core/encoding/utf8" @text, }
  `);
  f.put('root', 'main.mbt', `// filesystem fetch extern
    pub fn text() -> String { "# extern fetch filesystem" }
    pub fn quote() -> Char { '"' }
  `);
  f.put('root', 'unsafe_wbtest.mbt', 'extern "js" fn fetch() -> Unit = "..."');
  f.put('node_adapter', 'moon.pkg', 'native_link("socket")');
  assert.equal(f.check().external['moonbitlang/core/encoding/utf8'].startsWith('Pinned'), true);
});

test('direct and transitive external I/O are rejected despite aliases', t => {
  const f = fixture(t);
  f.put('root', 'moon.pkg', manifest + 'import { "moonbitlang/core/env" @pure, }');
  assert.throws(f.check, /UnreviewedExternal: root/);
  f.put('root', 'moon.pkg', manifest + 'import { "actql/actql/helper" @pure, }');
  f.put('helper', 'moon.pkg', manifest + 'import { "moonbitlang/core/env" @value, }');
  assert.throws(f.check, /UnreviewedExternal: helper/);
});

test('unknown target, build and conditional import syntax fail closed', () => {
  for (const source of [
    'native_link("socket")', 'options(link: ["socket"])',
    'pre_build("node generate.mjs")', 'import { "moonbitlang/core/env" } for "native"',
    'supported_targets = "native"', 'import { "safe", condition: "js" }',
  ]) assert.throws(() => packageImports(source), /Unknown|Unsupported/);
});

test('concrete transitive dependency cannot hide behind a neutral package', t => {
  const f = fixture(t);
  f.put('root', 'moon.pkg', manifest + 'import { "actql/actql/helper" }');
  f.put('helper', 'moon.pkg', manifest + 'import { "actql/actql/connectors/duckdb/adapter" }');
  assert.throws(f.check, /ConcreteCoreDependency/);
});

test('source FFI, embedded JS and native files are rejected', t => {
  const f = fixture(t);
  for (const source of [
    'extern "js" fn now() -> Int = "Date.now"',
    'extern "C" fn read() -> Int = "read"',
    '#cfg(target="native")\nfn io() -> Unit {}',
    '#import("fs")', 'fn now() { Date.now() }',
    'fn diagnostic() { println("unrequested output") }',
  ]) {
    f.put('root', 'main.mbt', source);
    assert.throws(f.check, /CoreEnvironmentAccess|CoreForeignOrUnknownAttribute/);
  }
  f.put('root', 'main.mbt', 'pub fn id(x : Int) -> Int { x }');
  f.put('root', 'native.c', 'int io() { return 1; }');
  assert.throws(f.check, /CoreForeignFile/);
});

test('alternative package metadata cannot be ignored in the audited closure', t => {
  const f = fixture(t);
  f.put('root', 'moon.pkg.json', '{"link":{"native":{"cc-link-flags":"-lsocket"}}}');
  assert.throws(f.check,/AmbiguousCoreManifest/);
});

test('public concrete binding import is rejected; opaque abstract port is allowed', t => {
  const f = fixture(t);
  f.put('root', 'pkg.generated.mbti', 'import { "actql/actql/connectors/duckdb/adapter" @db }\npub fn leak() -> @db.Session');
  assert.throws(f.check, /ConcretePublicType/);
  f.put('root', 'pkg.generated.mbti', 'type Port\npub fn request(Port) -> Unit');
  assert.deepEqual(f.check().packages, ['root']);
});

test('actual explicitly rooted product closure passes', () => {
  const result = inspectCore(new URL('../', import.meta.url).pathname);
  assert.ok(result.roots.includes('program_check'));
  assert.ok(result.roots.includes('execution_relation'));
  assert.ok(result.packages.includes('lowering_relation'));
  assert.ok(Object.keys(result.external).every(key => !key.endsWith('/env')));
});
