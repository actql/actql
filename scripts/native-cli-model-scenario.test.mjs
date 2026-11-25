import assert from 'node:assert/strict';
import {test} from 'node:test';
import {nativeJoinedModelRun, requireModelAttempts} from './fixtures/native-joined-model-run.mjs';

test('Native joined Model fixture names two File sources and joins two distinct Model results', () => {
  const firstTask = 'model-task:churn-risk.v1';
  const secondTask = 'model-task:churn-risk-confirm.v1';
  const scenario = nativeJoinedModelRun(firstTask, secondTask);
  const {connection, catalog, payload, program} = scenario;
  const [source, first, second, combined] = program.stages;
  assert.deepEqual(Object.values(source.inputs).map(({resource}) => resource), ['accounts', 'usage']);
  for (const {resource, items_path} of catalog.connections[connection].data) {
    const [row] = items_path.reduce((value, part) => value[part], payload);
    assert.equal(row.id, 'joined-1');
    assert.equal(catalog.connections[connection].views.find(view => view.resource === resource).data_classification,
      'internal');
  }
  assert.deepEqual(source.steps[0].join.select, {
    id: 'left.id', notes: 'left.notes', active_users: 'right.active_users', trend: 'right.trend',
  });
  for (const [stage, contract] of [[first, firstTask], [second, secondTask]]) {
    assert.equal(stage.inputs.rows.result.stage, 'source');
    assert.equal(stage.steps[1].infer.contract, contract);
  }
  assert.deepEqual(Object.values(combined.inputs).map(({result}) => result.stage), ['first', 'second']);
  assert.deepEqual(combined.steps[0].join.select, {
    id: 'left.id', first_outcome: 'left.outcome', first_value: 'left.value',
    second_outcome: 'right.outcome', second_value: 'right.value',
  });
  assert.deepEqual(program.results, {answer: {from: {stage: 'combined', result: 'rows'}}});
  const [row] = scenario.expectedRows;
  assert.notEqual(row.first_value.level, row.second_value.level);
  scenario.answers[0].reason = 'wrong reply';
  assert.equal(row.first_value.reason, 'independent first Model reply');
});

const attempt = (tag, digit, ordinal = 0) => ({tag, identity: 'sha256:' + digit.repeat(64), ordinal});

test('Native Model observations preserve individual attempt order under interleaving', () => {
  assert.deepEqual(requireModelAttempts([
    attempt(0, 'a'), attempt(0, 'b'), attempt(1, 'a'), attempt(1, 'b'), attempt(2, 'b'), attempt(2, 'a'),
  ], 2), ['sha256:' + 'a'.repeat(64), 'sha256:' + 'b'.repeat(64)]);
});

test('Native Model observations refuse a second send, a foreign row and an incomplete attempt', () => {
  assert.throws(() => requireModelAttempts([
    attempt(0, 'a'), attempt(1, 'a'), attempt(1, 'a'), attempt(2, 'a'),
  ], 1), {name: 'AssertionError'});
  assert.throws(() => requireModelAttempts([
    attempt(0, 'a'), attempt(1, 'a', 1), attempt(2, 'a'),
  ], 1), {name: 'AssertionError'});
  assert.throws(() => requireModelAttempts([
    attempt(0, 'a'), attempt(1, 'a'), attempt(2, 'a'), attempt(0, 'b'), attempt(1, 'b'),
  ], 2), {name: 'AssertionError'});
});
