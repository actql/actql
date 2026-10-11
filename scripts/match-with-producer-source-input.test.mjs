import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {matchWithProducerSuccesses as successes, matchWithProducerRefusals as refusals}
  from './fixtures/match-with-producer-source-input.mjs';

test('MATCH WITH has ordinary independent controls with NULL and empty contracts', () => {
  assert.equal(successes.length, 10);
  const find = name => successes.find(item => item.name === 'match-data-' + name);
  for (const [source, control] of [['nodes-source', 'nodes-json'], ['empty-source', 'empty-json'],
    ['parallel-trail-source', 'parallel-trail-json'], ['acquired-reused-source', 'reused-json']]) {
    assert.deepEqual(find(source).results, find(control).results);
    assert.equal(find(control).format, 'json');
    assert.ok(JSON.parse(find(control).text).stages[0].steps.some(step => step.graph));
  }
  assert.deepEqual(find('nodes-source').results.matched, {
    rows: [{value: null, key: 1}, {value: 7, key: 2}], columns: [
      {name: 'value', contract: {type: 'number', nullable: true}},
      {name: 'key', contract: {type: 'number', nullable: false}},
    ],
  });
  assert.deepEqual(find('empty-source').results.matched.rows, []);
  assert.deepEqual(find('empty-source').results.matched.columns, find('nodes-source').results.matched.columns);
  assert.match(find('quoted-relation-star').text, /SELECT \*/);
});

test('MATCH WITH preserves keyed edge multiplicity and acquired producer reuse', () => {
  const trail = successes.find(item => item.name === 'match-data-parallel-trail-json');
  const control = JSON.parse(trail.text);
  assert.deepEqual(control.stages[0].steps[1].values.rows, [
    {edge_key: 11, src: 1, dst: 1}, {edge_key: 10, src: 1, dst: 1},
  ]);
  assert.equal(control.stages[0].steps[4].traverse.path_mode, 'trail');
  assert.deepEqual(trail.results.matched.rows, [{value: 2}, {value: 2}]);
  const reused = successes.find(item => item.name === 'match-data-acquired-reused-source');
  assert.equal(reused.sourceReadCount, 2);
  assert.equal(reused.sourceReadSessionCount, 1);
  assert.match(reused.text, /FROM records \|> WHERE id = 2/);
  assert.equal((reused.text.match(/FROM records/g) ?? []).length, 1);
  assert.deepEqual(reused.results.original, reused.results.matched);
  assert.deepEqual(reused.results.matched.rows, [{value: 20, key: 2}]);
  for (const item of successes) {
    for (const output of Object.values(item.results)) {
      assert.ok(output.columns.every(column => !column.name.startsWith('aql_')));
    }
  }
});

test('MATCH WITH refusals pin scope and supported-surface classifications', () => {
  assert.equal(refusals.length, 7);
  assert.deepEqual(refusals.map(item => item.expectedCode), [
    'ClientProgramInvalidInput', 'ClientProgramInvalidInput', 'ClientProgramInvalidInput',
    'ClientProgramImplementationLimit', 'ClientProgramImplementationLimit', 'ClientProgramInvalidInput',
    'ClientProgramInvalidInput',
  ]);
});

test('MATCH WITH is copied and registered in ordinary packed acceptance', async () => {
  const packed = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  assert.ok(packed.includes('scopeInputs.successes.push(...matchWithProducerSuccesses)'));
  assert.ok(packed.includes('scopeInputs.refusals.push(...matchWithProducerRefusals)'));
  assert.ok(driver.includes("['scripts/fixtures/match-with-producer-source-input.mjs', 'match-with-producer-source-input.mjs']"));
  assert.ok(driver.includes('--match-with-producer-only'));
  const narrowStart = driver.indexOf('const narrowPublicQuery =');
  const narrowEnd = driver.indexOf('async function retainTransportReports', narrowStart);
  assert.ok(narrowStart >= 0 && narrowEnd > narrowStart);
  assert.ok(driver.slice(narrowStart, narrowEnd).includes('--match-with-producer-only'),
    'the selected cohort must not trigger unrelated planner/two-source corpora');
});

// Fixed predecessor fixture bytes preserve the authored JSON and public values.
test('WITH caller retirement preserves every control, result and acquisition count', async () => {
  const retained = JSON.parse(await readFile(new URL('../reviews/2026-10-11-with-carrier-cutover/with-match-producer-original-callers.json', import.meta.url), 'utf8'));
  const oldSource = retained.files['scripts/fixtures/match-data-producer-source-input.mjs'].text;
  const old = await import('data:text/javascript;base64,' + Buffer.from(oldSource).toString('base64'));
  assert.deepEqual(successes.map(({text, ...item}) => item), old.matchDataProducerSuccesses.map(({text, ...item}) => item));
  for (let index = 0; index < successes.length; index++) {
    if (successes[index].format === 'json') assert.equal(successes[index].text, old.matchDataProducerSuccesses[index].text);
    else {
      assert.match(successes[index].text, /^WITH /);
      assert.doesNotMatch(successes[index].text, /\bDATA\b|PROPERTY GRAPH/);
    }
  }
  assert.deepEqual(refusals.map(({text, expectedCode, ...item}) => item), old.matchDataProducerRefusals.map(({text, expectedCode, ...item}) => item));
  assert.equal(refusals.find(item => item.name === 'match-data-invalid-nested-result').expectedCode, 'ClientProgramInvalidInput');
});
