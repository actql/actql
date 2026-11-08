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

test('Native Content case indices retain every original role in distinct fresh Stores', t => {
  const root = mkdtempSync(join(tmpdir(), 'native-content-cases-'));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  const project = nativeProjectConfigurationFixture(root).ACTQL_TEST_NATIVE_PROJECT_CONFIGURATION_ROOT;
  const names = [
    'Native original README joins its two physical Sources and original keyed Content Store',
    'Native original README retains both keyed Content originals for its Model input',
    'Native README keyed capture preserves original raw snapshot after ContentRef projection',
    'Native README dispatches original keyed requests in canonical batch order',
    'Native README prepares one first activation for each original canonical key',
    'Native README retains original raw Store custody before keyed Content page admission',
    'Native raw Store refusal prevents a keyed page and keeps its original cleanup child',
    'Native original left Relation identity retains its actual completed prefix before dispatch',
    'Native README reuses original Source evidence in its left Relation and Model input',
    'Native README records actual per attempt bytes and finality without refund on retirement',
    'Native raw Store refusal retains actual per attempt usage and unresolved finality',
    'Native README binds each actual captured page to its original activation before adoption',
    'Native lookup raw Store preserves exact bytes and original purpose through reopen',
    'Native README Source originals retain the keyed Model closure',
    'Native README original file Effect Plan admits actual operations before children',
  ];
  const source = readFileSync(new URL('../src/cmd/native_client/local_project_mock_content_physical_scoped_wbtest.mbt', import.meta.url), 'utf8');
  assert.deepEqual([...source.matchAll(/^test "([^"]+)"/gmu)].map(match => match[1]), names,
    'Every compiler-owned Content case needs its reviewed per-case inputs');
  const namespaces = names.map((_, index) => {
    const path = join(root, String(index)); mkdirSync(path); return path;
  });
  const cases = namespaces.map((path, index) => nativeProjectContentCaseFixture(path, index, project));
  assert.deepEqual(cases.map(value => value.ACTQL_TEST_NATIVE_CONTENT_LOOKUPS), ['1', ...Array(14).fill('2')]);
  assert.equal(new Set(cases.map(value => value.ACTQL_TEST_NATIVE_STORE_ROOT)).size, 15);
  const roles = {
    RAW_SNAPSHOT: [2, 3, 4, 5, 6, 7, 8, 9, 10, 11],
    BATCH_PLAN: [3, 4, 5, 6, 7, 8, 9, 10, 11],
    ACTIVATION: [4, 5, 6, 7, 8, 9, 10, 11],
    RAW_STORE: [5, 6, 7, 8, 9, 10, 11], RAW_STORE_REFUSAL: [6, 10],
    LEFT_IDENTITY: [7, 8, 9, 10, 11], SOURCE_ARTIFACTS: [8, 9, 10, 11],
    ATTEMPT_USAGE: [9, 10, 11], CAPTURED_PAGE: [11], MODEL_SOURCE_CLOSURE: [8, 9, 10, 11, 13], EFFECT_PLAN_ONLY: [14],
  };
  for (const [role, selected] of Object.entries(roles)) {
    const key = 'ACTQL_TEST_NATIVE_' + role;
    assert.deepEqual(cases.map(value => value[key]), names.map((_, index) => selected.includes(index) ? '1' : undefined), role);
    for (const value of cases) assert.equal(({[key]: 'ambient', ...value})[key], value[key]);
  }
  for (const value of cases) {
    assert.equal(statSync(value.ACTQL_TEST_NATIVE_STORE_ROOT).mode & 0o777, 0o700);
    assert.deepEqual(readdirSync(value.ACTQL_TEST_NATIVE_STORE_ROOT), []);
  }
  assert.throws(() => nativeProjectContentCaseFixture(namespaces[0], 0), {code: 'EEXIST'});
  for (const index of [-1, 15, 0.5, '1', undefined]) {
    assert.throws(() => nativeProjectContentCaseFixture(root, index), /exact original/u);
  }
});

test('Native raw snapshot case binds its own authored file digest before selected execution', t => {
  const root = mkdtempSync(join(tmpdir(), 'native-raw-snapshot-case-'));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  const project = nativeProjectConfigurationFixture(root).ACTQL_TEST_NATIVE_PROJECT_CONFIGURATION_ROOT;
  const selected = join(root, 'selected'); mkdirSync(selected);
  const value = nativeProjectContentCaseFixture(selected, 2, project);
  assert.equal(value.ACTQL_TEST_NATIVE_RAW_SNAPSHOT, '1');
  const original = readFileSync(join(project, 'deal-review/mock/data.json'));
  assert.equal(value.ACTQL_TEST_NATIVE_RAW_SNAPSHOT_BYTES, String(original.length));
  assert.equal(value.ACTQL_TEST_NATIVE_RAW_SNAPSHOT_CID,
    'sha256:' + createHash('sha256').update(original).digest('hex'));
  assert.equal(value.ACTQL_TEST_NATIVE_MODEL_SOURCE_CLOSURE, undefined);
  assert.equal(value.ACTQL_TEST_NATIVE_EFFECT_PLAN_ONLY, undefined);
});
