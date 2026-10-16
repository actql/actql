import assert from 'node:assert/strict';
import test from 'node:test';
import {publicationAction} from './publication-action.mjs';
import {actionBoundaries} from '../../scripts/js-action-boundaries.mjs';
import {readActionBoundary} from '../../scripts/generate-js-action-bindings.mjs';

const root = new URL('../../',import.meta.url);

test('publication names follow the existing Owner code projection, not a second numeric table', () => {
  for (const boundary of actionBoundaries.filter(value => value.family === 'publication')) {
    const rows = readActionBoundary(root,boundary);
    for (const {code,name} of rows) assert.equal(publicationAction(boundary.kind,code),name);
    for (const code of [-1,rows.length,0.5,Number.NaN,undefined]) {
      assert.throws(() => publicationAction(boundary.kind,code),
        {name:'TypeError',message:'InvalidRunHostPublicationAction'});
    }
  }
  assert.throws(() => publicationAction('unknown',0),
    {name:'TypeError',message:'InvalidRunHostPublicationAction'});
});
