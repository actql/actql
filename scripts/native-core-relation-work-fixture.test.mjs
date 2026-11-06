import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync,
  statSync, symlinkSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {nativeCoreScopedAllocationProfile, nativeRelationWorkTestFile, nativeScopedTestFiles}
  from './native-core-test-selection.mjs';
import {nativeRelationWorkBackingBytes, prepareNativeCoreRelationRuntime,
  provisionNativeRelationBacking, runNativeRelationInputEmitter, selectNativeRelationBundle,
  verifyNativeRelationProducerInputs}
  from './native-core-relation-work-fixture.mjs';

function namespace(t) {
  const path = mkdtempSync(join(tmpdir(), 'actql-core-relation-input-'));
  t.after(() => rmSync(path, {recursive: true, force: true}));
  return path;
}

// Metadata ports are not component bytes and cannot be admitted as a runtime.
function bundleMetadata(target) {
  const suffix = target === 'darwin-arm64' ? 'dylib' : 'so';
  const components = {sqliteLibrary: `/components/sqlite/libactql_sqlite_component.${suffix}`,
    cryptoLibrary: `/components/crypto/libactql_crypto_component.${suffix}`};
  const bundle = {source: 'a'.repeat(40), target, providers: 0, loaded: false, initialized: false,
    sqlite: {path: components.sqliteLibrary, bytes: 1, sha256: 'b'.repeat(64)},
    crypto: {path: components.cryptoLibrary, bytes: 1, sha256: 'c'.repeat(64)},
    producer_receipts: {sqlite: {path: '/components/sqlite/process-producer.json'},
      crypto: {path: '/components/crypto/producer.json'}}};
  return {components, bundle};
}

test('Native relation Work selects only its exact scoped file without moving Local allocation profiles', () => {
  assert(nativeScopedTestFiles.includes(nativeRelationWorkTestFile));
  assert.equal(nativeScopedTestFiles.filter(file => file === nativeRelationWorkTestFile).length, 1);
  assert.equal(nativeCoreScopedAllocationProfile(nativeRelationWorkTestFile), 'scoped-review-values');
  for (const file of ['src/platform_native/relation_file_work_tests/unrelated_test.mbt',
    'src/platform_native/client_host/local_store_execution_wbtest.mbt',
    'src/cmd/native_client/local_command_business_wbtest.mbt'])
    assert.equal(nativeCoreScopedAllocationProfile(file), 'runtime-values');
  for (const file of ['src/platform_native/installed_arena_control/original_read_consumer_scoped_wbtest.mbt',
    'src/platform_native/row_source/capture_physical_scoped_wbtest.mbt'])
    assert.equal(nativeCoreScopedAllocationProfile(file), 'scoped-review-values');
});

test('Native relation input metadata requires the current source and exact platform-owned component paths', () => {
  for (const target of ['darwin-arm64', 'linux-x64']) {
    const {bundle, components} = bundleMetadata(target);
    assert.deepEqual(selectNativeRelationBundle(bundle, components, bundle.source, target),
      {directory: '/components', platform: target === 'linux-x64' ? 'linux-x64-gnu' : target});
    for (const edit of [copy => {copy.source = 'd'.repeat(40);}, copy => {copy.target = 'other';},
      copy => {copy.providers = 1;}, copy => {copy.loaded = true;}, copy => {copy.initialized = true;},
      copy => {copy.sqlite.path = '/borrowed/sqlite.so';},
      copy => {copy.crypto.sha256 = 'unverified';}, copy => {copy.crypto.bytes = 0;},
      copy => {copy.sqlite.bytes = 64 * 1024 ** 2 + 1;},
      copy => {copy.producer_receipts.crypto.path = '/borrowed/producer.json';}]) {
      const changed = structuredClone(bundle); edit(changed);
      assert.throws(() => selectNativeRelationBundle(changed, components, bundle.source, target));
    }
    assert.throws(() => selectNativeRelationBundle(bundle, {...components, cryptoLibrary: '/foreign/crypto.dylib'}, bundle.source, target));
  }
});

test('Native relation input preparation refuses dirty or missing current provenance before Common emission', async t => {
  const root = namespace(t), components = {sqliteLibrary: join(root, 'sqlite/libactql_sqlite_component.so'),
    cryptoLibrary: join(root, 'crypto/libactql_crypto_component.so')};
  for (const dirty of [true, false]) {
    const calls = [], destination = join(root, dirty ? 'dirty' : 'missing');
    const execute = (command, args) => {
      calls.push([command, args]); assert.equal(command, 'git');
      return args[0] === 'rev-parse' ? 'a'.repeat(40) + '\n' : dirty ? ' M source.mbt\n' : '';
    };
    await assert.rejects(prepareNativeCoreRelationRuntime(root, destination, components,
      {execute, platform: 'linux', arch: 'x64'}));
    assert.equal(existsSync(destination), false);
    assert.equal(calls.length, 2);
  }
});

test('Native relation producer provenance retains nested compiled source inputs and refuses changed originals', t => {
  const path = join(namespace(t), 'original.c'), body = 'original compiled source';
  writeFileSync(path, body, {mode: 0o600});
  const inputs = {[path]: {bytes: Buffer.byteLength(body), sha256: createHash('sha256').update(body).digest('hex')}};
  const receipt = {source: 'a'.repeat(40), target: 'aarch64-apple-darwin', inputs,
    static_source: {source: 'a'.repeat(40), target: 'aarch64-apple-darwin', inputs, compiled_inputs: inputs}};
  verifyNativeRelationProducerInputs(receipt);
  const omitted = structuredClone(receipt); delete omitted.inputs[path];
  assert.throws(() => verifyNativeRelationProducerInputs(omitted));
  const foreign = structuredClone(receipt); foreign.static_source.source = 'b'.repeat(40);
  assert.throws(() => verifyNativeRelationProducerInputs(foreign));
  const incomplete = structuredClone(receipt); incomplete.static_source.compiled_inputs = undefined;
  assert.throws(() => verifyNativeRelationProducerInputs(incomplete));
  writeFileSync(path, 'changed source');
  assert.throws(() => verifyNativeRelationProducerInputs(receipt));
});

test('Native relation Common emitter is bounded, nonzero, JS-only setup with explicit private destinations', () => {
  const calls = [], execute = (...args) => calls.push(args);
  const outputs = {ACTQL_TEST_NATIVE_RELATION_ENVIRONMENT_OUTPUT: '/new/environment.json',
    ACTQL_TEST_NATIVE_RELATION_BASELINE_ASSETS_OUTPUT: '/new/assets.json'};
  runNativeRelationInputEmitter('/checkout', '/new/js-target', outputs, {
    ACTQL_TEST_NATIVE_RELATION_ENVIRONMENT_OUTPUT: '/stale/environment.json',
    ACTQL_TEST_NATIVE_RELATION_CONFIGURATION_INPUTS: '/stale/configuration.json',
    ACTQL_TEST_NATIVE_RELATION_AUDIT_ROOT: '/foreign/audit-inputs',
    PATH: '/pinned',
  }, execute, 300);
  assert.equal(calls.length, 1);
  const [command, args, options] = calls[0];
  assert.equal(command, process.execPath);
  assert.match(args[2], /runFocusedTests\('moon'/u);
  assert.match(args[2], /"--target","js"/u);
  assert.match(args[2], /"--target-dir","\/new\/js-target"/u);
  assert.match(args[2], /"src\/native_relation_fixture_inputs"/u);
  assert.match(args[2], /expectedTests: 3/u);
  assert.match(args[2], /timeout: 300000/u);
  assert.equal(options.timeout, 310000);
  assert.deepEqual(options.env, {...outputs, PATH: '/pinned'});
  for (const seconds of [0, Infinity, 901]) assert.throws(() =>
    runNativeRelationInputEmitter('/checkout', '/new/target', outputs, {}, execute, seconds));
  assert.throws(() => runNativeRelationInputEmitter('/checkout', '/new/target',
    {ACTQL_EXECUTE_QUERY: '/query'}, {}, execute, 300));
  assert.throws(() => runNativeRelationInputEmitter('/checkout', '/new/target',
    {ACTQL_TEST_NATIVE_RELATION_CONFIGURATION_INPUTS: 'relative'}, {}, execute, 300));
  assert.equal(calls.length, 1);
});

function configuration(root) {
  mkdirSync(root, {mode: 0o700});
  // File-preservation ports only. They are not runtime/configuration admission.
  for (const name of ['account', 'environment', 'records', 'row-declaration', 'run', 'runtime'])
    writeFileSync(join(root, name + '.json'), `original ${name}`, {flag: 'wx', mode: 0o600});
}

test('Native relation backing owns exactly 768 MiB without resetting initialized input or config bytes', t => {
  const root = join(namespace(t), 'input'); configuration(root);
  provisionNativeRelationBacking(root);
  const backing = statSync(join(root, 'backing'));
  assert.equal(backing.size, nativeRelationWorkBackingBytes);
  assert.equal(backing.size, 805306368);
  assert.equal(backing.mode & 0o777, 0o600);
  assert.equal(backing.nlink, 1);
  writeFileSync(join(root, 'backing'), 'initialized marker');
  assert.throws(() => provisionNativeRelationBacking(root));
  assert.equal(readFileSync(join(root, 'backing'), 'utf8'), 'initialized marker');
  assert.equal(readFileSync(join(root, 'records.json'), 'utf8'), 'original records');
});

test('Native relation backing refuses foreign aliases, broad roots, and partial inputs', t => {
  const base = namespace(t), root = join(base, 'input'); configuration(root);
  const alias = join(base, 'alias'); symlinkSync(root, alias);
  assert.throws(() => provisionNativeRelationBacking(alias));
  chmodSync(root, 0o750);
  assert.throws(() => provisionNativeRelationBacking(root));
  chmodSync(root, 0o700);
  rmSync(join(root, 'account.json'));
  assert.throws(() => provisionNativeRelationBacking(root));
  assert.equal(existsSync(join(root, 'backing')), false);
});
