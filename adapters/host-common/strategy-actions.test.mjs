import assert from 'node:assert/strict';
import test from 'node:test';
import {strategyAction} from './strategy-actions.mjs';
import {actionBoundaries} from '../../scripts/js-action-boundaries.mjs';
import {readActionBoundary} from '../../scripts/generate-js-action-bindings.mjs';

const root = new URL('../../',import.meta.url);
for (const boundary of actionBoundaries.filter(value => value.family === 'strategy')) {
  test(`Common ${boundary.kind} names follow the existing Owner declaration`, () => {
    const rows = readActionBoundary(root,boundary);
    for (const {code,name} of rows) assert.equal(strategyAction[boundary.kind](code),name);
    for (const code of [-1,rows.length,999,0.5,NaN,Infinity,undefined,null,'0',0n,true,{},[]]) {
      assert.throws(() => strategyAction[boundary.kind](code));
    }
    assert.equal(strategyAction[boundary.kind](rows[0].code),rows[0].name);
  });
}
