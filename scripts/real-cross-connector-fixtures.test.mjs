import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
import {resolve, dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {realCrossConnectorFixturePaths} from './real-cross-connector-fixtures.mjs';
import {realCrossConnectorControl as control} from './fixtures/real-cross-connector-control.mjs';
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
  'scripts/fixtures/real-cross-connector-observation.mjs']) {
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
test('normal route entry and both processes parse without executing products or credentials', () => {
  for (const path of ['scripts/test-real-cross-connector-release.mjs', ...entries]) {
    execFileSync(process.execPath, ['--check', resolve(root, path)], {timeout: 10000});
  }
});
