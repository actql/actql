import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdtempSync, mkdirSync, readFileSync, readdirSync, rmSync, statSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {nativeProjectConfigurationFixture, nativeProjectContentCaseFixture}
  from './native-project-configuration-fixture.mjs';

test('Native project Content ports retain original contracts and independent authored byte digests', t => {
  const root = mkdtempSync(join(tmpdir(), 'native-project-content-'));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  const fixture = nativeProjectConfigurationFixture(root);
  for (const [key, name] of [['QUERY_CONTRACT', 'actql-query-acquisition.json'],
    ['EVIDENCE_CONTRACT', 'actql-query-process-evidence.json']]) {
    assert.equal(fixture['ACTQL_TEST_NATIVE_' + key],
      readFileSync(new URL('../spec/contracts/' + name, import.meta.url), 'utf8'));
  }
  const authored = JSON.parse(readFileSync(join(fixture.ACTQL_TEST_NATIVE_PROJECT_CONFIGURATION_ROOT,
    'deal-review/mock/data.json'), 'utf8'));
  const digests = JSON.parse(fixture.ACTQL_TEST_NATIVE_CONTENT_DIGESTS);
  assert.deepEqual(Object.keys(digests).sort(), ['file-acme-notes', 'file-globex-notes']);
  for (const row of authored.drive.files.rows) {
    assert.equal(digests[row.id], 'sha256:' + createHash('sha256')
      .update(Buffer.from(row.content_utf8, 'utf8')).digest('hex'));
  }
});

test('Native Content case indices retain one and two lookups in distinct fresh Stores', t => {
  const root = mkdtempSync(join(tmpdir(), 'native-content-cases-'));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  const namespaces = [0, 1].map(index => {
    const path = join(root, String(index)); mkdirSync(path); return path;
  });
  const cases = namespaces.map((path, index) => nativeProjectContentCaseFixture(path, index));
  assert.deepEqual(cases.map(value => value.ACTQL_TEST_NATIVE_CONTENT_LOOKUPS), ['1', '2']);
  assert.notEqual(cases[0].ACTQL_TEST_NATIVE_STORE_ROOT, cases[1].ACTQL_TEST_NATIVE_STORE_ROOT);
  for (const value of cases) {
    assert.equal(statSync(value.ACTQL_TEST_NATIVE_STORE_ROOT).mode & 0o777, 0o700);
    assert.deepEqual(readdirSync(value.ACTQL_TEST_NATIVE_STORE_ROOT), []);
  }
  assert.throws(() => nativeProjectContentCaseFixture(namespaces[0], 0), {code: 'EEXIST'});
  for (const index of [-1, 2, 0.5, '1', undefined]) {
    assert.throws(() => nativeProjectContentCaseFixture(root, index), /exact original/u);
  }
});
