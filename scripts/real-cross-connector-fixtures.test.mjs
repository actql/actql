import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
import {resolve, dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {realCrossConnectorFixturePaths, realCrossConnectorEnvironment} from './real-cross-connector-fixtures.mjs';
import {realCrossConnectorControl as control} from './fixtures/real-cross-connector-control.mjs';
import {checkRealRoutePreview} from './fixtures/real-cross-connector-preview.mjs';
const root = fileURLToPath(new URL('../', import.meta.url));
const entries = ['adapters/host-node/real-cross-connector-installed.test.mjs',
  'scripts/fixtures/real-cross-connector-restart.mjs'];
function missing(paths) {
  const delivered = new Set(paths.map(path => resolve(root, path)));
  const pending = entries.map(path => resolve(root, path)), visited = new Set(), absent = [];
  while (pending.length) {
    const file = pending.pop(); if (visited.has(file)) continue; visited.add(file);
    if (!delivered.has(file)) { absent.push(file); continue; }
    for (const match of readFileSync(file, 'utf8').matchAll(
      /(?:from\s*|import\s*\()(['"])(\.[^'"\n]+\.mjs)\1/gu)) pending.push(resolve(dirname(file), match[2]));
  }
  return absent;
}
test('real route delivers complete main and different-process import closures', () => {
  assert.deepEqual(missing(realCrossConnectorFixturePaths), []);
});
for (const path of ['scripts/gcs-files-content-credential.mjs',
  'scripts/fixtures/real-cross-connector-control.mjs',
  'scripts/fixtures/real-cross-connector-observation.mjs',
  'scripts/fixtures/real-cross-connector-preview.mjs']) {
  test(`real route detects missing ${path} before any live Source`, () => {
    assert(missing(realCrossConnectorFixturePaths.filter(item => item !== path)).includes(resolve(root, path)));
  });
}
test('independent real route fixes different read systems, original JOIN and one ordered Named Result', () => {
  assert.deepEqual(control.duckdbRows, [[1, 'actql-content-test/a.csv'], [2, 'not-selected.csv']]);
  assert.match(control.document, /r\.object_name = f\.name/u);
  assert.match(control.document, /LIST_FILES\(docs\.files/u);
  assert.deepEqual(control.expected, {name: 'joined', rows: [{id: 1, tag: 'actql-content-test/a.csv'}], columns: [
    {name: 'id', contract: {type: 'number', nullable: false}},
    {name: 'tag', contract: {type: 'string', nullable: false}},
  ]});
});

const cid = digit => `sha256:${digit.repeat(64)}`;
const previewExpected = {catalogCid: cid('1'), mappingCid: cid('2')};
function originalReview() {
  return {artifactCid: cid('3'), bytes: Buffer.from(JSON.stringify({version: 'actql-effect-preview/0.1',
    executed: false, effects: [{effect_kind: 'store', target: 'connector://table/catalog',
      mapping: 'mapping:table.catalog.v1', resolved_mapping_contract_cid: cid('2'),
      result_artifact_cid: cid('4'), source_binding_cid: cid('5'), effect_identity_cid: cid('6'),
      approval: 'required', executed: false, count: 1, max_items: 1,
      changes: [{target_guard: {state: 'not_applicable'}, before: {state: 'not_applicable'},
        after: {state: 'not_applicable'}, target_row_identity: cid('7'),
        intended_changes: {state: 'present', value: {version: 'actql-table-operation/0.1',
          action: 'create', catalog_identity_cid: cid('1'), namespace: ['test'], table_name: 'rows',
          expected_table: null, schema_cid: 'sha256:443804f9662e5e0591f71c5159ac6b60eb227fe8fbb6d992359dc34d823e92c9',
          input_artifact_cid: cid('4'), input_carrier: {kind: 'relation', cid: cid('8')},
          effect_identity_cid: cid('6'), storage_mapping_cid: cid('9'), request_cid: cid('7')}}}]}]}))};
}
test('sealed Table review checks independent target and schema while retaining unavailable row payload', () => {
  const review = originalReview(), checked = checkRealRoutePreview(review, previewExpected);
  assert.equal(checked.operation.action, 'create');
  assert.equal(checked.preApprovalPayload, 'unavailable_in_existing_review_projection');
  assert.deepEqual(checkRealRoutePreview(review, {...previewExpected, original: checked.identity}), checked);
  const changed = {artifactCid: review.artifactCid, bytes: Buffer.from(review.bytes.toString() + ' ')};
  assert.throws(() => checkRealRoutePreview(changed, {...previewExpected, original: checked.identity}));
});
for (const fault of ['target', 'mapping', 'catalog', 'action', 'schema', 'artifact']) {
  test(`sealed Table review refuses substituted ${fault} before approval`, () => {
    const review = originalReview(), body = JSON.parse(review.bytes), member = body.effects[0];
    const operation = member.changes[0].intended_changes.value;
    if (fault === 'target') member.target = 'connector://foreign/catalog';
    if (fault === 'mapping') member.resolved_mapping_contract_cid = cid('f');
    if (fault === 'catalog') operation.catalog_identity_cid = cid('f');
    if (fault === 'action') operation.action = 'replace';
    if (fault === 'schema') operation.schema_cid = cid('f');
    if (fault === 'artifact') operation.input_artifact_cid = cid('f');
    assert.throws(() => checkRealRoutePreview({...review, bytes: Buffer.from(JSON.stringify(body))}, previewExpected));
  });
}
test('normal route entry and both processes parse without executing products or credentials', () => {
  for (const path of ['scripts/test-real-cross-connector-release.mjs', ...entries]) {
    execFileSync(process.execPath, ['--check', resolve(root, path)], {timeout: 10000});
  }
});

test('real route isolates private npm configuration and checkout runtime variables without changing HOME', () => {
  const base = {HOME: '/original/home', NODE_PATH: '/checkout', NODE_OPTIONS: '--import=/overlay',
    ACTQL_LOCAL_SOURCE_PROFILE: '/old/source', MOON_HOME: '/compiler', npm_config_registry: 'https://foreign.invalid/',
    NPM_CONFIG_USERCONFIG: '/foreign/config'};
  const env = realCrossConnectorEnvironment(base, {root: '/private/tmp/new-app', node: '/pinned/node/bin/node'});
  assert.equal(env.HOME, base.HOME); assert.equal(env.npm_config_registry, 'https://registry.npmjs.org/');
  assert.equal(env.npm_config_userconfig, '/private/tmp/new-app/npmrc');
  assert.equal(env.npm_config_globalconfig, '/private/tmp/new-app/npmrc-global');
  for (const key of ['NODE_PATH','NODE_OPTIONS','ACTQL_LOCAL_SOURCE_PROFILE','MOON_HOME','NPM_CONFIG_USERCONFIG']) {
    assert.equal(Object.hasOwn(env, key), false);
  }
  assert.equal(base.NPM_CONFIG_USERCONFIG, '/foreign/config');
});
