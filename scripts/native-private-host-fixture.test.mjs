import assert from 'node:assert/strict';
import {createPrivateKey, createPublicKey} from 'node:crypto';
import {lstatSync, mkdtempSync, mkdirSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {createServer} from 'node:http';
import {once} from 'node:events';
import {nativeFilesystemTestRoot, nativePackageStoreRoot, nativePrivateHostFixture, nativeOriginalSigningFixture} from './native-private-host-fixture.mjs';
import {nativeEffectReviewFixture} from './fixtures/native-effect-review-fixture.mjs';

for (const path of ['/fixture/effect-review-report', '/fixture/effect-review', '/fixture/effect-resolution']) {
  test(`Native review fixture rejects foreign credentials without a fallback response: ${path}`, async t => {
    const fixture = nativeEffectReviewFixture('Bearer original-secret');
    let fallbacks = 0;
    const server = createServer((request, response) => {
      if (!fixture.handle(request, response)) {
        fallbacks++;
        response.writeHead(404).end();
      }
    });
    t.after(async () => {
      server.closeAllConnections();
      await new Promise(resolve => server.close(resolve));
    });
    server.listen(0, '127.0.0.1');
    await once(server, 'listening');
    const response = await fetch(`http://127.0.0.1:${server.address().port}${path}`, {
      method: 'POST', headers: {authorization: 'Bearer foreign-secret', 'content-type': 'application/json'},
      body: '{}',
    });
    assert.equal(response.status, 403);
    assert.equal(await response.text(), '');
    assert.equal(fallbacks, 0);
    assert.deepEqual(fixture.facts(), {resolutionRequests: 0, reviewUploads: 0,
      checkpointReportRequests: 0, checkpointReportWire: undefined, reviewUploadBodies: []});
  });
}

test('filesystem fixture is private even under the ordinary permissive umask', () => {
  const parent = mkdtempSync(join(tmpdir(), 'actql-private-fixture-'));
  const previous = process.umask(0o022);
  try {
    const root = nativeFilesystemTestRoot(parent);
    assert.equal(statSync(root).mode & 0o777, 0o700);
    assert.equal(root, join(parent, 'filesystem-test'));
  } finally {
    process.umask(previous);
    rmSync(parent, {recursive: true, force: true});
  }
});

test('filesystem fixture refuses existing directories without changing their mode', () => {
  const parent = mkdtempSync(join(tmpdir(), 'actql-private-fixture-'));
  const root = join(parent, 'filesystem-test');
  try {
    mkdirSync(root, {mode: 0o755});
    const original = statSync(root).mode;
    assert.throws(() => nativeFilesystemTestRoot(parent), {code: 'EEXIST'});
    assert.equal(statSync(root).mode, original);
  } finally {
    rmSync(parent, {recursive: true, force: true});
  }
});

test('Native filesystem fixtures retain independent real-file and alias counterexamples', () => {
  const parent = mkdtempSync(join(tmpdir(), 'actql-private-fixture-'));
  try {
    const env = nativePrivateHostFixture(parent);
    const files = env.ACTQL_TEST_NATIVE_FILE_OBSERVATION_ROOT;
    assert.equal(readFileSync(join(files, 'exact/file'), 'utf8'), 'abc');
    assert.equal(statSync(join(files, 'exact/file')).mode & 0o777, 0o644);
    assert(lstatSync(join(files, 'symlink/file')).isSymbolicLink());
    assert(statSync(join(files, 'directory/file')).isDirectory());
    assert.deepEqual(readdirSync(join(files, 'missing')), []);
    const census = env.ACTQL_TEST_NATIVE_CENSUS_ROOT;
    assert.deepEqual(readdirSync(join(census, 'exact')).sort(), ['LICENSE', 'bin']);
    assert(statSync(join(census, 'exact/bin')).isDirectory());
    assert(statSync(join(census, 'wrong-kind/bin')).isFile());
    assert(lstatSync(join(census, 'scoped-symlink/@actql')).isSymbolicLink());
    const namespace = env.ACTQL_TEST_NATIVE_DIRECTORY_OBSERVATION_ROOT;
    assert(lstatSync(join(namespace, 'alias')).isSymbolicLink());
    assert(lstatSync(join(namespace, 'scope-alias/node_modules/@actql')).isSymbolicLink());
    const ordinary = env.ACTQL_TEST_NATIVE_ORDINARY_FILE_ROOT;
    assert(lstatSync(join(ordinary, 'foreign link.json')).isSymbolicLink());
    assert.equal(readFileSync(join(ordinary, 'foreign link.json'), 'utf8'), 'unchanged');
  } finally {
    rmSync(parent, {recursive: true, force: true});
  }
});


test('independent package Store roots do not inherit retained state', () => {
  const parent = mkdtempSync(join(tmpdir(), 'actql-package-fixture-'));
  try {
    const first = nativePackageStoreRoot(parent);
    writeFileSync(join(first, 'retained'), 'original');
    const second = nativePackageStoreRoot(parent);
    assert.notEqual(first, second);
    assert.equal(statSync(first).mode & 0o777, 0o700);
    assert.equal(statSync(second).mode & 0o777, 0o700);
    assert.deepEqual(readdirSync(second), []);
    assert.equal(readFileSync(join(first, 'retained'), 'utf8'), 'original');
  } finally {
    rmSync(parent, {recursive: true, force: true});
  }
});

test('original signing fixture reuses public RFC bytes inside its private invocation', () => {
  const parent = mkdtempSync(join(tmpdir(), 'actql-original-signing-fixture-'));
  const previous = process.umask(0o022);
  const originalEnvironment = process.env.ACTQL_TEST_ORIGINAL_SIGNING_ROOT;
  try {
    const environment = nativeOriginalSigningFixture(parent);
    assert.deepEqual(Object.keys(environment), ['ACTQL_TEST_ORIGINAL_SIGNING_ROOT']);
    const root = environment.ACTQL_TEST_ORIGINAL_SIGNING_ROOT;
    assert.equal(root, join(parent, 'original-signing'));
    assert.equal(statSync(root).mode & 0o777, 0o700);
    const keyPath = join(root, 'key.pem');
    assert.equal(statSync(keyPath).mode & 0o777, 0o600);
    const existing = readFileSync(new URL('fixtures/native-original-key-signing.c', import.meta.url), 'utf8');
    const literal = existing.match(/static const char \*private_key = ("[^\n]+?");/u);
    assert(literal, 'Existing public RFC fixture literal is required');
    const key = readFileSync(keyPath, 'utf8');
    assert.equal(key, JSON.parse(literal[1]));
    const publicKey = createPublicKey(createPrivateKey(key)).export({type: 'spki', format: 'der'});
    assert.equal(publicKey.subarray(-32).toString('base64'),
      '11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo=');
    assert.equal(process.env.ACTQL_TEST_ORIGINAL_SIGNING_ROOT, originalEnvironment,
      'Fixture return values must not mutate the global environment');
    // Original test consumers retain the same file; setup is not a new key or
    // a replacement of a still-owned original after the first test closes.
    assert.throws(() => nativeOriginalSigningFixture(parent), {code: 'EEXIST'});
    assert.equal(readFileSync(keyPath, 'utf8'), key);
  } finally {
    process.umask(previous);
    rmSync(parent, {recursive: true, force: true});
  }
});

test('original signing fixture refuses a foreign child without adopting or chmodding it', () => {
  const parent = mkdtempSync(join(tmpdir(), 'actql-foreign-signing-fixture-'));
  const root = join(parent, 'original-signing');
  try {
    mkdirSync(root, {mode: 0o750});
    writeFileSync(join(root, 'marker'), 'foreign invocation');
    const before = statSync(root);
    assert.throws(() => nativeOriginalSigningFixture(parent), {code: 'EEXIST'});
    assert.equal(statSync(root).ino, before.ino);
    assert.equal(statSync(root).mode, before.mode);
    assert.deepEqual(readdirSync(root), ['marker']);
    assert.equal(readFileSync(join(root, 'marker'), 'utf8'), 'foreign invocation');
  } finally {
    rmSync(parent, {recursive: true, force: true});
  }
});
