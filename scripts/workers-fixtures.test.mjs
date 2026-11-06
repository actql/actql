import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdtempSync, mkdirSync, readFileSync, symlinkSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';

const repository = fileURLToPath(new URL('../', import.meta.url));
const generator = readFileSync(new URL('./workers-fixtures.mjs', import.meta.url), 'utf8');
const queryManifest = readFileSync(new URL('../src/query_integration/moon.pkg', import.meta.url), 'utf8');

test('actual query test targets preserve the checked Workers fixture source and imports', () => {
  const files = ['fixture.generated.mbt', 'moon.pkg', 'host.generated.mbt']
    .map(name => join(repository, 'src/workers_conformance', name));
  const before = files.map(path => readFileSync(path));
  const result = spawnSync(process.execPath, ['scripts/workers-fixtures.mjs', '--check'], {
    cwd: repository, env: process.env, encoding: 'utf8', timeout: 10_000,
  });
  assert.equal(result.error, undefined);
  assert.equal(result.signal, null);
  assert.equal(result.status, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /existing fixture helpers projected without concrete Node dependencies/u);
  assert.deepEqual(files.map(path => readFileSync(path)), before);
});

function refused(t, manifest, body = '') {
  const root = mkdtempSync(join(tmpdir(), 'actql-workers-manifest-'));
  t.diagnostic(`isolated manifest fixture retained: ${root}`);
  mkdirSync(join(root, 'scripts'));
  mkdirSync(join(root, 'src/query_integration'), {recursive: true});
  writeFileSync(join(root, 'package.json'), '{"type":"module"}\n');
  writeFileSync(join(root, 'scripts/workers-fixtures.mjs'), generator);
  symlinkSync(fileURLToPath(new URL('./portable-core.mjs', import.meta.url)),
    join(root, 'scripts/portable-core.mjs'));
  writeFileSync(join(root, 'src/query_integration/moon.pkg'), manifest);
  // Explicit preparation doubles reach only the metadata/dependency refusal.
  // A formatter or generated-output fallback must never rescue these inputs.
  writeFileSync(join(root, 'src/query_integration/fixture_wbtest.mbt'),
    `///|\nfn captured_graph_fixture() -> Unit { ${body} }\n` +
    '///|\nfn dispatch_test_generated() -> Unit { }\n');
  const result = spawnSync(process.execPath, [join(root, 'scripts/workers-fixtures.mjs'), '--check'], {
    env: {...process.env, MOON_HOME: join(root, 'formatter-must-not-run')},
    encoding: 'utf8', timeout: 10_000,
  });
  assert.equal(result.error, undefined);
  assert.equal(result.signal, null);
  assert.notEqual(result.status, 0);
  return result.stderr;
}

for (const [name, mutate, issue] of [
  ['changed native link flags', text => text.replace('"-lssl -lcrypto"', '"-lssl -lcrypto -lsocket"'), /UnexpectedQueryIntegrationOptions/u],
  ['production-file target metadata', text => text.replace('row_stream_current_js_wbtest.mbt', 'row_stream_current.mbt'), /UnexpectedQueryIntegrationOptions/u],
  ['another target for the reviewed test', text => text.replace('"row_stream_current_js_wbtest.mbt": [ "js" ]', '"row_stream_current_js_wbtest.mbt": [ "native" ]'), /UnexpectedQueryIntegrationOptions/u],
  ['unreviewed test target metadata', text => text.replace('  link: {', '  targets: { "other_wbtest.mbt": [ "js" ] },\n  link: {'), /UnexpectedQueryIntegrationOptions/u],
  ['unknown production directive before the reviewed options', text => 'native_link("socket")\n' + text, /UnknownManifestDirective/u],
  ['unknown production options before the reviewed block', text => 'options(warnings: "-all")\n' + text, /UnknownManifestSyntax/u],
]) test(`Workers fixture metadata refuses ${name}`, t => {
  const altered = mutate(queryManifest);
  assert.notEqual(altered, queryManifest);
  assert.match(refused(t, altered), issue);
});

test('reviewed test target metadata cannot hide a selected nonportable dependency', t => {
  const manifest = 'import { "actql/actql/connectors/duckdb/adapter" @blocked, }\n' + queryManifest;
  assert.match(refused(t, manifest, '@blocked.read()'), /Nonportable fixture dependency/u);
});

test('reviewed test target metadata cannot hide an unresolved fixture dependency', t => {
  assert.match(refused(t, queryManifest, '@missing.read()'), /Unresolved fixture import/u);
});
