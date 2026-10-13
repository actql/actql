import assert from 'node:assert/strict';
import test from 'node:test';
import {selectReleaseSequenceQueryCases, releaseSequenceSuccessNames,
  releaseSequenceRefusalNames} from './release-sequence-query-cases.mjs';
import {sequenceSourceSuccesses, sequenceSourceRefusals}
  from './fixtures/sequence-source-input.mjs';

test('release Sequence selects all original 18 normal and 9 refusal inputs without rewriting them', () => {
  const selected = selectReleaseSequenceQueryCases();
  assert.equal(selected.successes.length, 18);
  assert.equal(selected.refusals.length, 9);
  assert.deepEqual(selected.successes.map(value => value.name), releaseSequenceSuccessNames);
  assert.deepEqual(selected.refusals.map(value => value.name), releaseSequenceRefusalNames);
  for (const [kind, original] of [['successes', sequenceSourceSuccesses],
    ['refusals', sequenceSourceRefusals]]) {
    assert.equal(Object.isFrozen(selected[kind]), true);
    for (let index = 0; index < original.length; index++) {
      assert.equal(selected[kind][index], original[index]);
    }
  }
  const nullable = selected.successes.find(value => value.name === 'sequence-json-nullable-case');
  assert.deepEqual(JSON.parse(nullable.text).stages[0].steps[1].sequence.pattern[0].where,
    {case: {when: [{when: {eq: [{field: 'kind'}, {literal: 1}]}, then: {literal: true}}],
      else: {literal: null}}});
  const parameters = selected.successes.find(value => value.name === 'sequence-sql-parameters');
  assert.deepEqual(parameters.parameters, {tag: 1, span: 20, cap: 2});
  assert.deepEqual(parameters.parameterDeclarations, {
    tag: {type: 'number', nullable: false}, span: {type: 'number', nullable: false},
    cap: {type: 'number', nullable: false}});
});

test('release Sequence refuses missing duplicate reordered or extra original cases', () => {
  const alternatives = [sequenceSourceSuccesses.slice(1),
    [sequenceSourceSuccesses[0], ...sequenceSourceSuccesses],
    [...sequenceSourceSuccesses].reverse()];
  for (const successes of alternatives) {
    assert.throws(() => selectReleaseSequenceQueryCases({successes}), {code: 'ERR_ASSERTION'});
  }
  for (const refusals of [sequenceSourceRefusals.slice(1),
    [...sequenceSourceRefusals, {name: 'unrelated-case'}]]) {
    assert.throws(() => selectReleaseSequenceQueryCases({refusals}), {code: 'ERR_ASSERTION'});
  }
});

test('release Sequence cannot quietly substitute a Source-backed acquisition', () => {
  for (const field of ['sourceReadCount', 'sourceReadSessionCount']) {
    const successes = sequenceSourceSuccesses.map((value, index) => index === 0
      ? {...value, [field]: 1} : value);
    assert.throws(() => selectReleaseSequenceQueryCases({successes}), {code: 'ERR_ASSERTION'});
  }
});
