import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdtempSync, mkdirSync, readFileSync, readdirSync, rmSync, statSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {runInNewContext} from 'node:vm';
import test from 'node:test';
import {parse} from 'acorn';
import {nativeProjectConfigurationFixture, nativeProjectContentCaseFixture}
  from './native-project-configuration-fixture.mjs';
import {nativeClientFileResponseTestFile, nativeCoreScopedTestEnvironment}
  from './native-core-test-selection.mjs';

test('Native staged import quote belongs only to its exact scoped Request case', () => {
  const wrapper = readFileSync(new URL('./test-native-core.mjs', import.meta.url), 'utf8');
  const fixtureStart = wrapper.indexOf('const fixtureEnvironment = {');
  const fixtureEnd = wrapper.indexOf('\n};', fixtureStart);
  assert(fixtureStart >= 0 && fixtureEnd > fixtureStart);
  const fixtureBody = wrapper.slice(fixtureStart + 'const fixtureEnvironment = '.length, fixtureEnd + 2);
  const base = runInNewContext('(' + fixtureBody + ')', {
    process: {env: {ACTQL_TEST_NATIVE_IMPORT_QUOTE: 'ambient',
      ACTQL_TEST_NATIVE_FILE_RECEIPT_ROOT: '/ambient/file',
      ACTQL_TEST_CLIENT_FILE_RECEIPT_APPROVE_RESOLUTION_WIRE: 'ambient-file-receipt'}, platform: 'darwin', arch: 'arm64'},
    full: false, args: [], namespace: '/original', root: '/checkout', join,
    httpLifetime: {}, clientFiles: {}, bundle: {}, clientCheckpoint: {}, fileReceiptCheckpoint: {}, privateHost: {},
    originalSigning: {}, processRegion: {}, readerCustody: {}, projectConfiguration: {}, walFixture: undefined,
  });
  assert.equal(base.ACTQL_TEST_NATIVE_IMPORT_QUOTE, undefined, 'ordinary children must not inherit the marker');
  assert.equal(base.ACTQL_TEST_NATIVE_FILE_RECEIPT_ROOT, undefined);
  assert.equal(base.ACTQL_TEST_CLIENT_FILE_RECEIPT_APPROVE_RESOLUTION_WIRE, undefined);
  const environments = [];
  function visit(node) {
    if (node === null || typeof node !== 'object') return;
    if (node.type === 'CallExpression' && node.callee.name === 'spawn') {
      const env = node.arguments[2]?.properties?.find(value => value.key?.name === 'env')?.value;
      if (env?.properties?.some(value => value.type === 'SpreadElement' &&
        value.argument.type === 'MemberExpression' && value.argument.object.name === 'scoped' &&
        value.argument.property.name === 'environment')) environments.push(env);
    }
    for (const value of Object.values(node)) {
      if (Array.isArray(value)) value.forEach(visit);
      else if (value && typeof value === 'object') visit(value);
    }
  }
  visit(parse(wrapper, {ecmaVersion: 'latest', sourceType: 'module'}));
  assert.equal(environments.length, 1, 'One actual async scoped child environment required');
  const environment = wrapper.slice(environments[0].start, environments[0].end);
  const source = 'src/cmd/native_client/local_project_mock_request_physical_scoped_wbtest.mbt';
  const authored = readFileSync(new URL('../' + source, import.meta.url), 'utf8');
  const names = [...authored.matchAll(/^test "([^"]+)"/gmu)].map(match => match[1]);
  assert.equal(names[10], 'Native original two-row staged import construction fits its unchanged facility');
  for (const [selectedSource, index, expected] of [[source, 10, '1'], [source, 9], [source, 11],
    [source, '10'], ['src/foreign/local_project_mock_request_physical_scoped_wbtest.mbt', 10],
    ['src/cmd/native_client/local_project_mock_content_physical_scoped_wbtest.mbt', 10]]) {
    const selected = runInNewContext('(' + environment + ')', {
      fixtureEnvironment: {...base, ACTQL_TEST_NATIVE_IMPORT_QUOTE: 'ambient'},
      scoped: {environment: {ACTQL_TEST_NATIVE_IMPORT_QUOTE: 'profile-ambient'}},
      physical: {ACTQL_TEST_INSTALLED_PROCESS_ROOT: '/original/physical'},
      content: {ACTQL_TEST_NATIVE_CONTENT_LOOKUPS: '2', ACTQL_TEST_NATIVE_STORE_ROOT: '/original/content'},
      nativeClientFileResponseTestFile,
      nativeCoreScopedTestEnvironment,
      fileReceiptCheckpoint: {ACTQL_TEST_CLIENT_FILE_RECEIPT_APPROVE_RESOLUTION_WIRE: 'original-file-receipt'},
      test: {source: selectedSource, index},
    });
    assert.equal(selected.ACTQL_TEST_NATIVE_IMPORT_QUOTE, expected);
    assert.equal(selected.ACTQL_TEST_CLIENT_FILE_RECEIPT_APPROVE_RESOLUTION_WIRE, undefined);
    assert.equal(selected.ACTQL_TEST_INSTALLED_PROCESS_ROOT, '/original/physical');
    assert.equal(selected.ACTQL_TEST_NATIVE_CONTENT_LOOKUPS, '2');
    assert.equal(selected.ACTQL_TEST_NATIVE_STORE_ROOT, '/original/content');
  }
});

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
  const originalNames = [
    'Native README metadata returns completed codec workspace before both keyed captures',
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
  const names = [...originalNames.slice(0, 13),
    'Native README lookup receipt retains every original attempt and measured usage',
    'Native completed Lookup bodies enter strict Effect dependency admission',
    'Native original Lookup closes dependency graph over exact Carrier and Catalog bodies',
    ...originalNames.slice(13),
    'Native original whole Source Unit evidence preserves original captures and retired refusal'];
  const originalIndices = [...Array.from({length: 13}, (_, index) => index), 16, 17, 18];
  assert.deepEqual(originalIndices.map(index => names[index]), originalNames);
  const source = readFileSync(new URL('../src/cmd/native_client/local_project_mock_content_physical_scoped_wbtest.mbt', import.meta.url), 'utf8');
  assert.deepEqual([...source.matchAll(/^test "([^"]+)"/gmu)].map(match => match[1]), names,
    'Every compiler-owned Content case needs its reviewed per-case inputs');
  const namespaces = names.map((_, index) => {
    const path = join(root, String(index)); mkdirSync(path); return path;
  });
  const cases = namespaces.map((path, index) => nativeProjectContentCaseFixture(path, index, project));
  const originals = originalIndices.map(index => cases[index]);
  assert.deepEqual(originals.map(value => value.ACTQL_TEST_NATIVE_CONTENT_LOOKUPS), ['2', '1', ...Array(14).fill('2')]);
  assert.equal(new Set(cases.map(value => value.ACTQL_TEST_NATIVE_STORE_ROOT)).size, 20);
  for (const key of ['ACTQL_TEST_NATIVE_RAW_SNAPSHOT_CID', 'ACTQL_TEST_NATIVE_RAW_SNAPSHOT_BYTES'])
    assert.equal(cases[19][key], cases[9][key], 'whole Source Unit uses the same authored raw file: ' + key);
  const roles = {
    METADATA_REMAINDER: [0],
    RAW_SNAPSHOT: [0, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
    BATCH_PLAN: [0, 4, 5, 6, 7, 8, 9, 10, 11, 12],
    ACTIVATION: [0, 5, 6, 7, 8, 9, 10, 11, 12],
    RAW_STORE: [0, 6, 7, 8, 9, 10, 11, 12], RAW_STORE_REFUSAL: [7, 11],
    LEFT_IDENTITY: [0, 8, 9, 10, 11, 12], SOURCE_ARTIFACTS: [0, 9, 10, 11, 12],
    ATTEMPT_USAGE: [0, 10, 11, 12], CAPTURED_PAGE: [0, 12],
    MODEL_SOURCE_CLOSURE: [0, 9, 10, 11, 12, 14], EFFECT_PLAN_ONLY: [15],
  };
  for (const [role, selected] of Object.entries(roles)) {
    const key = 'ACTQL_TEST_NATIVE_' + role;
    assert.deepEqual(originals.map(value => value[key]), originalNames.map((_, index) => selected.includes(index) ? '1' : undefined), role);
    for (const index of [13, 14, 15]) assert.equal(cases[index][key], cases[12][key], role);
    assert.equal(cases[19][key], cases[9][key], 'whole Source Unit retains original Source-artifact role: ' + role);
    for (const value of cases) assert.equal(({[key]: 'ambient', ...value})[key], value[key]);
  }
  for (const [role, selected] of Object.entries({
    LOOKUP_COMPLETION: [13, 14, 15], LOOKUP_DEPENDENCIES: [14, 15], LOOKUP_CLOSURE: [15],
    SOURCE_UNIT_EVIDENCE: [19],
  })) {
    const key = 'ACTQL_TEST_NATIVE_' + role;
    assert.deepEqual(cases.map(value => value[key]), names.map((_, index) => selected.includes(index) ? '1' : undefined), role);
    for (const value of cases) assert.equal(({[key]: 'ambient', ...value})[key], value[key]);
  }
  for (const value of cases) {
    assert.equal(statSync(value.ACTQL_TEST_NATIVE_STORE_ROOT).mode & 0o777, 0o700);
    assert.deepEqual(readdirSync(value.ACTQL_TEST_NATIVE_STORE_ROOT), []);
  }
  assert.throws(() => nativeProjectContentCaseFixture(namespaces[0], 0, project), {code: 'EEXIST'});
  for (const index of [-1, 20, 0.5, '1', undefined]) {
    assert.throws(() => nativeProjectContentCaseFixture(root, index), /exact original/u);
  }
});

test('Native raw snapshot case binds its own authored file digest before selected execution', t => {
  const root = mkdtempSync(join(tmpdir(), 'native-raw-snapshot-case-'));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  const project = nativeProjectConfigurationFixture(root).ACTQL_TEST_NATIVE_PROJECT_CONFIGURATION_ROOT;
  const selected = join(root, 'selected'); mkdirSync(selected);
  const value = nativeProjectContentCaseFixture(selected, 3, project);
  assert.equal(value.ACTQL_TEST_NATIVE_RAW_SNAPSHOT, '1');
  const original = readFileSync(join(project, 'deal-review/mock/data.json'));
  assert.equal(value.ACTQL_TEST_NATIVE_RAW_SNAPSHOT_BYTES, String(original.length));
  assert.equal(value.ACTQL_TEST_NATIVE_RAW_SNAPSHOT_CID,
    'sha256:' + createHash('sha256').update(original).digest('hex'));
  assert.equal(value.ACTQL_TEST_NATIVE_MODEL_SOURCE_CLOSURE, undefined);
  assert.equal(value.ACTQL_TEST_NATIVE_EFFECT_PLAN_ONLY, undefined);
});
