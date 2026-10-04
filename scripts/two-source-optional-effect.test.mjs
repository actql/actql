import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {optionalEffectSubmission, optionalEffectExpectations, optionalEffectFixtureFiles,
  optionalEffectCases} from './fixtures/two-source-optional-effect.mjs';

test('ordinary packed acceptance includes both optional Effect pairs', () => {
  assert.deepEqual(optionalEffectCases([]), ['native-json', 'broad-text']);
  assert.deepEqual(optionalEffectCases(['--optional-effect-only']), ['native-json', 'broad-text']);
  for (const flag of ['--composed-text', '--composed-infer', '--two-source-effect']) {
    assert.deepEqual(optionalEffectCases([flag]), []);
  }
  const script = readFileSync(new URL('./test-packed-salesforce-source.mjs', import.meta.url), 'utf8');
  assert.ok(script.includes('for (const kind of optionalCases)'),
    'normal packed consumer must execute the pair without a special flag');
  assert.ok(script.includes('...optionalEffectFixtureFiles'));
});

test('JSON pair differs only by the terminal Effect', () => {
  const plain = JSON.parse(optionalEffectSubmission('native-json', false).document);
  const effect = JSON.parse(optionalEffectSubmission('native-json', true, 'fixture-mapping').document);
  assert.deepEqual(effect.stages.at(-1).effects, {save: {update: {
    target: 'connector://crm-main/Test_Record__c', mapping: 'fixture-mapping',
    from: {result: 'rows'}, id: 'target_id', set: {Name: {field: 'next_name'}}}}});
  delete effect.stages.at(-1).effects;
  assert.deepEqual(effect, plain);
  assert.equal(plain.stages[0].steps[0].filter, 'id >= 0');
  assert.equal(plain.stages[1].steps[0].filter, 'id >= 0');
  assert.equal(plain.stages[2].steps[0].join.max_output_rows, 100);
  assert.deepEqual(Object.keys(plain.results), ['updates']);
});

test('text pair shares exact submitted bytes up to the terminal Effect', () => {
  const plain = optionalEffectSubmission('broad-text', false);
  const effect = optionalEffectSubmission('broad-text', true, 'fixture-mapping');
  assert.equal(plain.format, 'aql-text');
  assert.equal(effect.format, 'aql-text');
  assert.equal(effect.document.slice(0, effect.document.indexOf('  |> EFFECT')), plain.document);
  assert.equal(plain.document.match(/WHERE id >= 0/gu).length, 2);
  assert.ok(plain.document.includes('MAX_OUTPUT_ROWS 100'));
  assert.ok(effect.document.includes('FROM RESULT updates ID target_id SET (Name = next_name)'));
});

test('binding preserves authored inputs and rejects malformed text MappingRefs', () => {
  for (const kind of ['native-json', 'broad-text']) {
    const first = optionalEffectSubmission(kind, true, 'fixture-first');
    const second = optionalEffectSubmission(kind, true, 'fixture-second');
    assert.equal(first.document.replace('fixture-first', '__PUBLICATION_MAPPING_REF__'),
      second.document.replace('fixture-second', '__PUBLICATION_MAPPING_REF__'));
    for (const bad of ['', 'bad`reference', 'bad\nreference', 'bad\\reference']) {
      assert.throws(() => optionalEffectSubmission(kind, true, bad));
    }
  }
  for (const file of optionalEffectFixtureFiles) {
    assert.ok(readFileSync(new URL('./fixtures/' + file, import.meta.url)).length);
  }
});

test('independent expected rows, type order and replay counts retain NULL and one write', () => {
  assert.deepEqual(optionalEffectExpectations.rows, [{id: 1, left_amount: null, right_amount: 100,
    risk: 'high', target_id: 'a00000000000002', next_name: 'review-required'}]);
  assert.deepEqual(optionalEffectExpectations.columns.map(column => column.name),
    ['id', 'left_amount', 'right_amount', 'risk', 'target_id', 'next_name']);
  assert.deepEqual(optionalEffectExpectations.writes,
    [{id: 'a00000000000002', body: {Name: 'review-required'}}]);
  assert.deepEqual(optionalEffectExpectations.withoutEffect.sourceReadSessions, [2, 0, 0]);
  assert.deepEqual(optionalEffectExpectations.withEffect.sourceReadSessions, [2, 0, 0, 0]);
  assert.deepEqual(optionalEffectExpectations.withoutEffect.writeCounts, [0, 0, 0]);
  assert.deepEqual(optionalEffectExpectations.withEffect.writeCounts, [0, 0, 1, 1]);
});
