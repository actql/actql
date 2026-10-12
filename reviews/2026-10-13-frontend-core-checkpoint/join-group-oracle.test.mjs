import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';

test('flat JOIN GROUP oracle keeps original typed values and operator bodies', () => {
  const literals = readFileSync('src/query_program/single_join_group_test.mbt', 'utf8').split('\n')
    .map(line => line.trim()).filter(line => line.startsWith('#|')).map(line => line.slice(2));
  assert.equal(literals.length, 2);
  assert.equal(createHash('sha256').update(literals[0]).digest('hex'), "e2bedd9bc56b7f18eeb766a4feeda0733542e9c40720f6cc974c75c1861f58ea");
  const [staged, current] = literals.map(JSON.parse);
  const before = staged.stages[2].steps;
  const after = current.stages[0].steps;
  assert.equal(current.stages.length, 1);
  assert.deepEqual(current.stages[0].inputs, {});
  assert.deepEqual(after[0].values, staged.stages[0].steps[0].values);
  assert.deepEqual(after[1].values, staged.stages[1].steps[0].values);
  assert.equal(after[2].from, after[0].as);
  assert.equal(after[2].join.with, after[1].as);
  const {with: oldPeer, ...oldJoin} = before[0].join;
  const {with: newPeer, ...newJoin} = after[2].join;
  assert.deepEqual(newJoin, oldJoin);
  assert.equal(newJoin.max_output_rows, 10);
  assert.deepEqual(after[3].group, before[1].group);
  assert.equal(after[3].from, after[2].as);
  assert.deepEqual(after[4], before[2]);
  assert.deepEqual(after[5], before[3]);
  assert.deepEqual(after[6].select, before[4].select);
  assert.equal(current.stages[0].results.rows.from, after[6].as);
  assert.deepEqual(current.stages[0].results.rows.fields, staged.stages[2].results.rows.fields);
  assert.deepEqual(current.results, staged.results);
  assert.equal(current.version, staged.version);
  assert.equal(current.id, staged.id);
});
