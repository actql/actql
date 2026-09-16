import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {retainedCase, retainedMatrix, workloads} from './fixtures.mjs';

test('measurement fixture generator matches the preregistered content pin', async () => {
  const experiment = JSON.parse(await readFile(new URL('./experiment.json', import.meta.url), 'utf8'));
  const source = await readFile(new URL('./fixtures.mjs', import.meta.url));
  assert.equal(createHash('sha256').update(source).digest('hex'), experiment.fixtures.sha256);
  assert.equal(experiment.fixtures.caseCount, retainedMatrix().length);
});

test('preregistered matrix fixes all 27 workload/layout/size combinations', () => {
  const matrix = retainedMatrix();
  assert.equal(matrix.length, 27);
  assert.equal(new Set(matrix.map(value => value.id)).size, 27);
  for (const value of matrix) {
    assert(value.limits.sourceRows >= value.cardinalities.source);
    assert(value.limits.intermediateRows >= Math.max(...Object.entries(value.cardinalities)
      .filter(([name]) => name !== 'source').map(([, count]) => count)));
    assert(Object.isFrozen(value.limits));
    const program = value.program();
    assert.equal(program.stages.length, value.workload === workloads[1] ? 5 : 4);
    assert.equal(program.stages[0].steps[0].filter, 'id > $minimum');
    assert.deepEqual(program.stages[0].steps[1].select,
      value.workload === workloads[2] ? value.fields : ['id']);
    program.stages[0].steps[1].select.push('not-a-real-field');
    assert(!value.program().stages[0].steps[1].select.includes('not-a-real-field'));
  }
});

test('low selectivity validates all source rows but independently expects only the final two ids', () => {
  const value = retainedCase(workloads[0], 'text-1024', 100);
  assert.equal(value.sourceRow(0).payload.length, 1024);
  assert.deepEqual(value.cardinalities, {source: 100, capture: 2, a: 2, b: 2, c: 2});
  assert.deepEqual([value.outputRow(0), value.outputRow(1)], [{id: 98}, {id: 99}]);
  const wire = '[{"id":98},{"id":99}]';
  assert.deepEqual(value.identity(), {rows: 2, bytes: 21,
    rowsCid: `sha256:${createHash('sha256').update(wire).digest('hex')}`});
});

test('duplicate input pairs make exactly twice as many join rows before one-row count', () => {
  const value = retainedCase(workloads[1], 'narrow', 100);
  assert.deepEqual([0, 1, 2, 3].map(index => value.sourceRow(index).id), [0, 0, 1, 1]);
  let pairs = 0;
  for (let left = 0; left < 100; left++) for (let right = 0; right < 100; right++) {
    if (value.sourceRow(left).id === value.sourceRow(right).id) pairs++;
  }
  assert.equal(pairs, 200);
  assert.equal(value.cardinalities.join, pairs);
  assert.deepEqual(value.outputRow(0), {n: 200, present: 200});
});

test('wide reuse retains every column and uses canonical key order, not construction order', () => {
  const value = retainedCase(workloads[2], 'numeric-64', 100);
  assert.equal(Object.keys(value.sourceRow(0)).length, 64);
  assert.equal(value.outputRow(99).c63, 162);
  assert.equal(value.outputRow(99).id, 99);
  const rows = Array.from({length: 100}, (_, index) => {
    const row = value.sourceRow(index);
    return Object.fromEntries(Object.entries(row).sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0));
  });
  const wire = JSON.stringify(rows);
  assert.equal(value.identity().bytes, Buffer.byteLength(wire));
  assert.equal(value.identity().rowsCid, `sha256:${createHash('sha256').update(wire).digest('hex')}`);
  assert.throws(() => value.sourceRow(-1), RangeError);
  assert.throws(() => value.outputRow(100), RangeError);
});
