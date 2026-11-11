import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync, mkdirSync, writeFileSync, readFileSync, readdirSync, existsSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
import {inspectCore, packageImports, copyProductionCore} from './portable-core.mjs';

const manifest = 'supported_targets = "+js+wasm+native"\n';
function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'actql-portable-negative-'));
  writeFileSync(join(root,'moon.mod'),'name = "actql/actql"\nsource = "src"\n');
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

test('portable numeric primitive imports are reviewed only for their actual Owner', t => {
  const f = fixture(t);
  const paths = ['builtin', 'double', 'float', 'int'].map(name => `moonbitlang/core/${name}`);
  f.put('root', 'moon.pkg', manifest + 'import { "actql/actql/scalar_numeric_kernel" @math }');
  f.put('scalar_numeric_kernel', 'moon.pkg', manifest + `import { ${paths.map(path => JSON.stringify(path)).join(', ')} }`);
  f.put('scalar_numeric_kernel', 'main.mbt', 'pub fn identity(x : Double) -> Double { x }');
  assert.deepEqual(Object.keys(f.check().external).sort(), [...paths].sort());
  for (const path of paths) {
    // A reviewed dependency of the kernel cannot become another Owner's import
    // or public type merely because it appears in the same rooted closure.
    f.put('root', 'moon.pkg', manifest + `import { "${path}" @math }`);
    assert.throws(f.check, /UnreviewedExternal: root/);
    f.put('root', 'moon.pkg', manifest + 'import { "actql/actql/scalar_numeric_kernel" @math }');
    f.put('root', 'pkg.generated.mbti', `import { "${path}" @math }`);
    assert.throws(f.check, /UnreviewedPublicType: root/);
  }
});

test('numeric Owner review retains unreviewed math, I/O and source-code refusal', t => {
  const f = fixture(t);
  f.put('root', 'moon.pkg', manifest + 'import { "actql/actql/scalar_numeric_kernel" }');
  for (const path of ['moonbitlang/core/math', 'moonbitlang/core/env', 'vendor/neutral/numeric']) {
    f.put('scalar_numeric_kernel', 'moon.pkg', manifest + `import { "${path}" @math }`);
    assert.throws(f.check, /UnreviewedExternal: scalar_numeric_kernel/);
  }
  f.put('scalar_numeric_kernel', 'moon.pkg', manifest + 'import { "moonbitlang/core/builtin" }');
  for (const source of ['extern "js" fn host() -> Int = "Math.random"', 'fn host() { println("output") }']) {
    f.put('scalar_numeric_kernel', 'main.mbt', source);
    assert.throws(f.check, /CoreEnvironmentAccess/);
  }
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

test('module-level build hooks and alternative roots fail closed', t => {
  const f = fixture(t);
  writeFileSync(join(f.root,'moon.mod'),'name = "actql/actql"\noptions(pre_build: "node io.mjs")');
  assert.throws(f.check,/UnauditedCoreModuleDirective/);
  writeFileSync(join(f.root,'moon.mod'),'source = "foreign"');
  assert.throws(f.check,/UnsupportedCoreSourceRoot/);
});

test('reviewed ESM module literal preserves legacy metadata and isolated bytes', t => {
  const f = fixture(t);
  const legacy = 'name = "actql/actql"\nsource = "src"\n';
  const reviewed = 'options("link-flags": [ "-js-format", "esm" ])\n';
  assert.deepEqual(f.check().packages, ['root']);
  for (const source of [legacy + reviewed, reviewed + legacy]) {
    writeFileSync(join(f.root, 'moon.mod'), source);
    assert.deepEqual(f.check().packages, ['root']);
  }
  const source = legacy + '// Pinned format selection only.\n' + reviewed;
  writeFileSync(join(f.root, 'moon.mod'), source);
  const isolated = join(f.root, 'isolated');
  copyProductionCore(f.root, isolated, ['root']);
  assert.equal(readFileSync(join(isolated, 'moon.mod'), 'utf8'), source);
  assert.deepEqual(inspectCore(isolated, ['root']).packages, ['root']);
});

test('reviewed module option refuses unknown keys, hooks and surplus fields', t => {
  const f = fixture(t);
  for (const option of [
    'options("link-flags": ["-js-format", "esm",,],)',
    'options("link-flags": ["-js-format", "esm"],,)',
    'options("other": ["-js-format", "esm"])',
    'options("pre-build": ["-js-format", "esm"])',
    'options(link_flags: ["-js-format", "esm"])',
    'options("link-flags": ["-js-format", "esm"], "pre-build": "node io.mjs")',
    'options("link-flags": ["-js-format", "esm"], "link-flags": [])',
  ]) {
    writeFileSync(join(f.root, 'moon.mod'), 'source = "src"\n' + option);
    assert.throws(f.check, /UnauditedCoreModuleDirective/, option);
  }
});

test('reviewed module flags refuse modified values, extra flags and wrong types', t => {
  const f = fixture(t);
  for (const value of [
    '[]', '["-js-format"]', '["esm", "-js-format"]',
    '["-js-format", "cjs"]', '["-other", "esm"]',
    '["-js-format", "esm", "-another"]',
    '["-js-format", esm]', '["-js-format", 1]',
    '["-js-format", ["esm"]]', '"-js-format esm"',
    '{"format": "esm"}', '["-js-format", "esm",]',
  ]) {
    writeFileSync(join(f.root, 'moon.mod'), `source = "src"\noptions("link-flags": ${value})`);
    assert.throws(f.check, /UnauditedCoreModuleDirective/, value);
  }
});

test('reviewed module literal refuses duplicates, incomplete input and trailing directives', t => {
  const f = fixture(t);
  const reviewed = 'options("link-flags": ["-js-format", "esm"])';
  for (const source of [
    reviewed + '\n' + reviewed, reviewed + '\npre_build("node io.mjs")',
    reviewed + '\nunknown = "value"', reviewed.slice(0, -1),
    reviewed + ', external = "socket"',
  ]) {
    writeFileSync(join(f.root, 'moon.mod'), 'source = "src"\n' + source);
    assert.throws(f.check, /UnauditedCoreModuleDirective/, source);
  }
});

test('public concrete binding import is rejected; opaque abstract port is allowed', t => {
  const f = fixture(t);
  f.put('root', 'pkg.generated.mbti', 'import { "actql/actql/connectors/duckdb/adapter" @db }\npub fn leak() -> @db.Session');
  assert.throws(f.check, /ConcretePublicType/);
  for (const path of ['cloudflare:workers', 'node:fs', 'vendor/neutral/session']) {
    f.put('root', 'pkg.generated.mbti', `import { "${path}" @ordinary }\npub fn leak() -> @ordinary.Binding`);
    assert.throws(f.check, /UnreviewedPublicType/);
  }
  f.put('root', 'pkg.generated.mbti', 'type Port\npub fn request(Port) -> Unit');
  assert.deepEqual(f.check().packages, ['root']);
});

test('captured original input Ref is a reviewed public DATA type only for its existing Owner', t => {
  const f = fixture(t), owner = 'pipeline_check_context';
  f.put(owner, 'moon.pkg', manifest);
  f.put(owner, 'main.mbt', 'pub fn identity(value : Int) -> Int { value }');
  f.put(owner, 'pkg.generated.mbti', 'import { "moonbitlang/core/ref" @ref }\npub fn retain(@ref.Ref[Int]) -> Unit');
  assert.deepEqual(inspectCore(f.root, [owner]).packages, [owner]);
  f.put('root', 'pkg.generated.mbti', 'import { "moonbitlang/core/ref" @ref }');
  assert.throws(f.check, /UnreviewedPublicType: root/);
  f.put(owner, 'moon.pkg', manifest + 'import { "moonbitlang/core/ref" @ref }');
  assert.throws(() => inspectCore(f.root, [owner]), /UnreviewedExternal: pipeline_check_context/);
  f.put(owner, 'moon.pkg', manifest);
  f.put(owner, 'pkg.generated.mbti', 'import { "moonbitlang/core/env" @host }');
  assert.throws(() => inspectCore(f.root, [owner]), /UnreviewedPublicType: pipeline_check_context/);
});

test('Source native key extent Ref is reviewed DATA without permitting foreign Owners or Host imports', t => {
  const f = fixture(t), owner = 'source_value';
  f.put(owner, 'moon.pkg', manifest);
  f.put(owner, 'main.mbt', 'pub fn observe(out : Ref[Int]) -> Unit { out.val = 0 }');
  f.put(owner, 'pkg.generated.mbti', 'import { "moonbitlang/core/ref" @ref }\npub fn observe(@ref.Ref[Int]) -> Unit');
  assert.deepEqual(inspectCore(f.root, [owner]).packages, [owner]);
  f.put('root', 'pkg.generated.mbti', 'import { "moonbitlang/core/ref" @ref }\npub fn retain(@ref.Ref[Int]) -> Unit');
  assert.throws(f.check, /UnreviewedPublicType: root/);
  f.put(owner, 'pkg.generated.mbti', 'import { "moonbitlang/core/ref" @ref; "cloudflare:workers" @host }\npub fn leak(@ref.Ref[@host.Binding]) -> Unit');
  assert.throws(() => inspectCore(f.root, [owner]), /UnreviewedPublicType: source_value/);
  f.put(owner, 'pkg.generated.mbti', 'import { "moonbitlang/core/ref" @ref }\npub fn observe(@ref.Ref[Int]) -> Unit');
  f.put(owner, 'moon.pkg', manifest + 'import { "moonbitlang/core/ref" @ref }');
  assert.throws(() => inspectCore(f.root, [owner]), /UnreviewedExternal: source_value/);
});

test('actual explicitly rooted product closure passes', () => {
  const result = inspectCore(new URL('../', import.meta.url).pathname);
  assert.ok(result.roots.includes('program_check'));
  assert.ok(result.roots.includes('execution_relation'));
  assert.ok(result.packages.includes('lowering_relation'));
  assert.ok(Object.keys(result.external).every(key => !key.endsWith('/env')));
});

test('actual Text sizing target files survive the audited production copy', t => {
  const f = fixture(t), root = new URL('../', import.meta.url).pathname;
  const isolated = join(f.root, 'isolated-text-sizing');
  copyProductionCore(root, isolated, ['execution_relation']);
  const copied = readFileSync(join(isolated, 'src/execution_relation/moon.pkg'), 'utf8');
  assert.match(copied, /"text_workspace_growth_js\.mbt": \["js"\]/u);
  assert.match(copied, /"text_workspace_growth_nonjs\.mbt": \["not","js"\]/u);
  for (const file of ['text_workspace_growth.mbt', 'text_workspace_growth_js.mbt',
    'text_workspace_growth_nonjs.mbt']) {
    assert.equal(readFileSync(join(isolated, 'src/execution_relation', file), 'utf8'),
      readFileSync(join(root, 'src/execution_relation', file), 'utf8'));
  }
  assert.equal(existsSync(join(isolated, 'src/execution_relation/text_workspace_growth_wbtest.mbt')), false);
  assert.ok(inspectCore(isolated, ['execution_relation']).packages.includes('execution_relation'));
});


test('isolated build retains production aliases and excludes test-only packages and files', t => {
  const f = fixture(t);
  f.put('root', 'moon.pkg', manifest + `
    import { "actql/actql/helper" @production, }
    import { "actql/actql/internal_structural_fixture" @frontend, } for "test"
    import { "moonbitlang/core/env" @host, } for "wbtest"
    formatter(ignore: ["example_test.mbt"],)
  `);
  f.put('helper', 'moon.pkg', manifest);
  f.put('helper', 'helper.mbt', 'pub fn value() -> Int { 1 }');
  f.put('root', 'main.mbt', 'pub fn identity() -> Int { @production.value() }');
  f.put('root', 'example_test.mbt', 'test { @frontend.parse() }');
  f.put('root', 'example_wbtest.mbt', 'test { @host.now() }');
  const isolated = join(f.root, 'isolated');
  const audit = copyProductionCore(f.root, isolated, ['root']);
  assert.deepEqual(audit.packages, ['helper', 'root']);
  assert.deepEqual(readdirSync(join(isolated, 'src', 'root')).sort(),
    ['main.mbt', 'moon.pkg']);
  assert.deepEqual(packageImports(readFileSync(join(isolated, 'src', 'root', 'moon.pkg'), 'utf8')),
    [{path: 'actql/actql/helper', alias: 'production', scope: 'production'}]);
  assert.equal(readFileSync(join(isolated, 'src', 'root', 'main.mbt'), 'utf8'),
    readFileSync(join(f.root, 'src', 'root', 'main.mbt'), 'utf8'));
  assert.equal(existsSync(join(isolated, 'src', 'internal_structural_fixture')), false);
  assert.deepEqual(inspectCore(isolated, ['root']).packages, audit.packages);
});


test('raw multiline Moon data keeps environment names literal', t => {
  const f = fixture(t);
  f.put('root', 'main.mbt', String.raw`pub fn data() -> String {
    #|{"extern":"fetch", "Date.now":"process", "quoted":"\{eval()}", "hash":"#cfg"}
    #|// require crypto @"js" /* println */
  }
  `);
  assert.deepEqual(f.check().packages, ['root']);
});

test('raw multiline data cannot hide following code or foreign declarations', t => {
  const f = fixture(t);
  for (const source of [
    'extern "js" fn host() -> Int =\n  #|() => 1\n',
    'fn data() -> String {\n  #|safe data\n}\nfn io() { println("output") }',
    'fn data() -> String {\n  #|safe data\n}\nfn io() { Date.now() }',
  ]) {
    f.put('root', 'main.mbt', source);
    assert.throws(f.check, /CoreEnvironmentAccess/);
  }
  f.put('root', 'main.mbt', '@\n  #|() => 1\n');
  assert.throws(f.check, /CoreEmbeddedCode/);
});

test('raw multiline support keeps misplaced prefixes and unknown attributes closed', t => {
  const f = fixture(t);
  for (const source of [
    'fn data() -> String { #|not a leading raw line\n}',
    '#unknown\nfn data() -> String {\n  #|literal\n}',
    '#cfg(target="js")\nfn data() -> String {\n  #|literal\n}',
  ]) {
    f.put('root', 'main.mbt', source);
    assert.throws(f.check, /CoreForeignOrUnknownAttribute/);
  }
});

test('interpolated multiline source is never treated as opaque raw data', t => {
  const f = fixture(t);
  for (const source of [
    'fn data(x : Int) -> String {\n  $|value \\{x}\n}',
    'fn data(x : Int) -> String {\n  #|raw line\n  $|value \\{x}\n}',
  ]) {
    f.put('root', 'main.mbt', source);
    assert.throws(f.check, /UnsupportedInterpolatedMultilineString/);
  }
});

test('reviewed ESM module accepts the formatter optional argument comma', t => {
  const f = fixture(t);
  const source = 'name = "actql/actql"\nsource = "src"\n' +
    'options(\n  "link-flags": [ "-js-format", "esm" ],\n)\n';
  writeFileSync(join(f.root, 'moon.mod'), source);
  assert.deepEqual(f.check().packages, ['root']);
  const isolated = join(f.root, 'isolated-comma');
  copyProductionCore(f.root, isolated, ['root']);
  assert.equal(readFileSync(join(isolated, 'moon.mod'), 'utf8'), source);
  assert.deepEqual(inspectCore(isolated, ['root']).packages, ['root']);
});

test('formatted ESM argument comma preserves exact flag values and order', t => {
  const f = fixture(t);
  for (const flags of [
    '["-js-format", "cjs"]', '["esm", "-js-format"]',
    '["-js-format", "esm", "-unsafe"]', '["-js-format"]',
    '["-js-format", "esm",]', '["-js-format", esm]',
  ]) {
    writeFileSync(join(f.root, 'moon.mod'), `source = "src"\noptions("link-flags": ${flags},)\n`);
    assert.throws(f.check, /UnauditedCoreModuleDirective/, flags);
  }
});

test('formatted ESM argument comma refuses surplus options and duplicate declarations', t => {
  const f = fixture(t);
  const valid = 'options("link-flags": ["-js-format", "esm"],)';
  for (const option of [
    'options("link-flags": ["-js-format", "esm"],,)',
    'options("link-flags": ["-js-format", "esm"], "pre-build": "node host.mjs")',
    'options("link-flags": ["-js-format", "esm"], "link-flags": [])',
    'options("other": ["-js-format", "esm"],)',
    valid + '\n' + valid, valid + '\npre_build("node host.mjs")',
  ]) {
    writeFileSync(join(f.root, 'moon.mod'), `source = "src"\n${option}\n`);
    assert.throws(f.check, /UnauditedCoreModuleDirective/, option);
  }
});

test('formatted ESM module keeps foreign and unknown source declarations rejected', t => {
  const f = fixture(t);
  writeFileSync(join(f.root, 'moon.mod'),
    'source = "src"\noptions("link-flags": ["-js-format", "esm"],)\n');
  f.put('root', 'main.mbt', 'extern "js" fn host() -> Int =\n  #|() => process.pid\n');
  assert.throws(f.check, /CoreEnvironmentAccess: root\/main.mbt: extern/);
  f.put('root', 'main.mbt', '#cfg(target="js")\nfn id(x : Int) -> Int { x }');
  assert.throws(f.check, /CoreForeignOrUnknownAttribute/);
  f.put('root', 'main.mbt', '@\n  #|() => 1\n');
  assert.throws(f.check, /CoreEmbeddedCode/);
});

test('raw multiline data is not an attribute or executable host access', t => {
  const f = fixture(t);
  f.put('root', 'main.mbt', `pub fn data() -> String {
    #|{"text":"extern fetch Date.now #cfg require crypto"}
    #|unescaped "quotes" and /* literal comments */
  }`);
  assert.deepEqual(f.check().packages, ['root']);
  for (const suffix of ['fn host() { println("output") }',
    '#cfg(target="native")\nfn host() {}',
    'extern "js" fn host() -> Int = "Date.now"']) {
    f.put('root', 'main.mbt', `pub fn data() -> String {\n  #|safe literal\n}\n${suffix}`);
    assert.throws(f.check, /CoreEnvironmentAccess|CoreForeignOrUnknownAttribute/);
  }
  // An inline marker is not the reviewed line-literal syntax.
  f.put('root', 'main.mbt', 'fn host() { #| println("output") }');
  assert.throws(f.check, /CoreEnvironmentAccess|CoreForeignOrUnknownAttribute/);
});

test('live custody packages are refused directly and transitively even without FFI', t => {
  for (const name of ['physical_resources', 'physical_strategy_host', 'physical_host_dispatch']) {
    const f = fixture(t);
    f.put(name, 'moon.pkg', manifest);
    f.put(name, 'main.mbt', 'pub fn identity(x : Int) -> Int { x }');
    f.put('root', 'moon.pkg', manifest + `import { "actql/actql/${name}" @ordinary, }`);
    assert.throws(f.check, /HostCustodyCoreDependency/);
    f.put('root', 'moon.pkg', manifest + 'import { "actql/actql/helper" @ordinary, }');
    f.put('helper', 'moon.pkg', manifest + `import { "actql/actql/${name}" @ordinary, }`);
    assert.throws(f.check, /HostCustodyCoreDependency/);
  }
});

import './core-host-boundary.test.mjs';


test('isolated production copy keeps implicit builtin imports compiler-valid', t => {
  const f = fixture(t);
  f.put('root', 'moon.pkg', manifest + 'import { "actql/actql/scalar_numeric_kernel" }\n');
  f.put('root', 'main.mbt', 'pub fn identity() -> Int { @scalar_numeric_kernel.value() }');
  f.put('scalar_numeric_kernel', 'moon.pkg', manifest + 'import { "moonbitlang/core/builtin" }\n');
  f.put('scalar_numeric_kernel', 'main.mbt', 'pub fn value() -> Int { 7 }');
  const check = root => {
    const result = spawnSync(join(process.env.MOON_HOME, 'bin/moon'),
      ['check', '--target', 'js', '--deny-warn', '--jobs', '1', 'src/root'],
      {cwd: root, env: process.env, encoding: 'utf8', maxBuffer: 2 * 1024 * 1024});
    assert.equal(result.error, undefined);
    assert.equal(result.signal, null);
    assert.equal(result.status, 0, result.stdout + result.stderr);
  };
  check(f.root);
  const isolated = join(f.root, 'isolated');
  copyProductionCore(f.root, isolated, ['root']);
  check(isolated);
});


test('isolated production copy distinguishes explicit default aliases from implicit imports', t => {
  const f = fixture(t);
  const implicit = 'import { "actql/actql/helper" }\n';
  const explicit = 'import { "actql/actql/helper" @helper }\n';
  assert.deepEqual(packageImports(manifest + implicit), packageImports(manifest + explicit));
  f.put('helper', 'moon.pkg', manifest);
  f.put('helper', 'main.mbt', 'pub fn value() -> Int { 1 }');
  for (const [label, source] of [['implicit', implicit], ['explicit', explicit]]) {
    f.put('root', 'moon.pkg', manifest + source);
    f.put('root', 'main.mbt', 'pub fn identity() -> Int { @helper.value() }');
    const isolated = join(f.root, label);
    copyProductionCore(f.root, isolated, ['root']);
    const copied = readFileSync(join(isolated, 'src/root/moon.pkg'), 'utf8');
    assert.equal(copied.includes('@helper'), label === 'explicit');
    assert.deepEqual(packageImports(copied), [{path: 'actql/actql/helper', alias: 'helper', scope: 'production'}]);
  }
});

test('target metadata keeps the actual manifest production and test imports distinct', () => {
  const source = readFileSync(new URL('../src/physical_resources/moon.pkg', import.meta.url), 'utf8');
  assert.deepEqual(packageImports(source), [
    {path: 'actql/actql/capacity_arithmetic', alias: 'preparation_counts', scope: 'production'},
    {path: 'actql/actql/encode_core', alias: 'encode', scope: 'production'},
    {path: 'actql/actql/decode_core', alias: 'decode', scope: 'production'},
    {path: 'actql/actql/decode_shape', alias: 'shape', scope: 'production'},
    {path: 'actql/actql/source_value', alias: 'source', scope: 'wbtest'},
  ]);
});

test('target metadata remains compiler DATA in the isolated production copy', t => {
  const f = fixture(t);
  f.put('root', 'moon.pkg', manifest + `
    options(targets: {
      "main.mbt": ["not", "wasm"],
      "other.mbt": ["wasm"],
      "example_wbtest.mbt": ["not", "js"],
      "missing_wbtest.mbt": ["native"],
    },)
  `);
  f.put('root', 'other.mbt', 'pub fn value() -> Int { 2 }');
  f.put('root', 'example_wbtest.mbt', 'test { assert_eq(1, 1) }');
  const isolated = join(f.root, 'isolated-targets');
  copyProductionCore(f.root, isolated, ['root']);
  const copied = readFileSync(join(isolated, 'src/root/moon.pkg'), 'utf8');
  assert.equal(copied, manifest + '\noptions(targets: {\n' +
    '  "main.mbt": ["not","wasm"],\n' +
    '  "other.mbt": ["wasm"],\n' +
    '  "missing_wbtest.mbt": ["native"],\n})\n');
  assert.equal(existsSync(join(isolated, 'src/root/example_wbtest.mbt')), false);
  for (const file of ['main.mbt', 'other.mbt']) {
    assert.equal(readFileSync(join(isolated, 'src/root', file), 'utf8'),
      readFileSync(join(f.root, 'src/root', file), 'utf8'));
  }
  assert.deepEqual(inspectCore(isolated, ['root']).packages, ['root']);
});

test('target metadata refuses malformed, duplicate and unknown manifest options', () => {
  const valid = 'options(targets: {"main.mbt": ["js"]})';
  for (const source of [
    'options(link: ["socket"])',
    'options(targets: {"main.mbt": [js]})',
    'options(targets: {"main.mbt": "js"})',
    'options(targets: {"main.mbt": [["js"]]})',
    'options(targets: {"main.mbt": ["js"]}, link: ["socket"])',
    'options(targets: {"main.mbt": ["js"], "main.mbt": ["wasm"]})',
    valid + '\n' + valid,
    valid + '\nnative_link("socket")',
    valid + '\nsupported_targets = "native"',
    valid + '\nimport {"moonbitlang/core/env"} for "native"',
    valid + '\nunknown_build("node io.mjs")',
  ]) assert.throws(() => packageImports(source), /Unknown|Unsupported/, source);
});

test('target metadata cannot conceal dependencies, FFI or foreign files on any target', t => {
  const f = fixture(t);
  const options = 'options(targets: {"main.mbt": ["js"]})\n';
  f.put('root', 'moon.pkg', manifest + options + 'import {"moonbitlang/core/env" @pure}');
  assert.throws(f.check, /UnreviewedExternal: root/);
  f.put('root', 'moon.pkg', manifest + options + 'import {"actql/actql/helper"}');
  f.put('helper', 'moon.pkg', manifest + options + 'import {"actql/actql/connectors/duckdb/adapter"}');
  assert.throws(f.check, /ConcreteCoreDependency/);
  f.put('root', 'moon.pkg', manifest + options);
  for (const source of [
    '#external\ntype Host',
    'extern "js" fn host() -> Int = "Date.now"',
    'extern "C" fn host() -> Int = "host"',
    '#cfg(target="native")\nfn host() -> Unit {}',
    '@"host()"',
  ]) {
    f.put('root', 'main.mbt', source);
    assert.throws(f.check, /CoreEnvironmentAccess|CoreForeignOrUnknownAttribute|CoreEmbeddedCode/);
  }
  f.put('root', 'main.mbt', 'pub fn value() -> Int { 1 }');
  f.put('root', 'host.c', 'int host(void) { return 1; }');
  assert.throws(f.check, /CoreForeignFile/);
});
