import assert from 'node:assert/strict';
import {lstatSync, mkdtempSync, mkdirSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {nativeFilesystemTestRoot, nativePackageStoreRoot, nativePrivateHostFixture} from './native-private-host-fixture.mjs';

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
