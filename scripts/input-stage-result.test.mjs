import assert from 'node:assert/strict';
import test from 'node:test';
import {inputStageResultProgram, inputStageResultSuccesses}
  from './fixtures/input-stage-result.mjs';

test('independent input-only Program preserves the issue and empty steps', () => {
  assert.equal(inputStageResultProgram.id, 'fixture.identity_stage_result');
  assert.deepEqual(inputStageResultProgram.stages[1].steps, []);
  assert.deepEqual(inputStageResultProgram.stages[1].results,
    {rows: {from: 'source', fields: ['A']}});
  assert.deepEqual(inputStageResultSuccesses[0].results.answer,
    {rows: [{A: 0}], columns: [{name: 'A', contract: {type: 'number', nullable: false}}]});
  const shared = JSON.parse(inputStageResultSuccesses[2].text);
  assert.deepEqual(shared.stages.slice(1).map(stage => stage.steps), [[], []]);
  assert.deepEqual(Object.keys(inputStageResultSuccesses[2].results), ['answer', 'second']);
  assert.deepEqual(inputStageResultSuccesses[2].results.answer.rows,
    [{A: 2}, {A: 0}, {A: 2}]);
  assert.deepEqual(inputStageResultSuccesses[2].results.second.rows,
    [{A: 2}, {A: 0}, {A: 2}]);
  assert.notDeepEqual(inputStageResultSuccesses[2].results.answer.rows,
    [{A: 0}, {A: 2}, {A: 2}], 'canonical field sort is not inherited order');
});
