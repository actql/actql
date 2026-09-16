import test from 'node:test';
import assert from 'node:assert/strict';
import {selectReadinessCases} from './selection.mjs';

test('readiness selection distinguishes the full matrix from one exact diagnostic case', () => {
  const cases = [{id: 'a'}, {id: 'b'}];
  assert.deepEqual(selectReadinessCases(cases), {cases, scope: 'full-matrix'});
  const selected = selectReadinessCases(cases, 'b');
  assert.equal(selected.scope, 'single-case-diagnostic');
  assert.deepEqual(selected.cases, [cases[1]]);
  assert.equal(cases.length, 2);
  for (const id of ['', 'c', '*', 'a,b', null, 0]) {
    assert.throws(() => selectReadinessCases(cases, id));
  }
  assert.throws(() => selectReadinessCases([{id: 'a'}, {id: 'a'}], 'a'));
});
