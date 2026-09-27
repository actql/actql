import assert from 'node:assert/strict';
import test from 'node:test';
import {publicationAction} from './publication-action.mjs';

test('publication ABI rejects undefined numeric actions', () => {
  assert.equal(publicationAction('resultAccess', 0), 'authorize_request');
  assert.equal(publicationAction('existingDelivery', 3), 'invalid');
  for (const code of [-1, 7, 1.5, Number.NaN, undefined]) {
    assert.throws(() => publicationAction('resultAccess', code),
      {name: 'TypeError', message: 'InvalidRunHostPublicationAction'});
  }
  assert.throws(() => publicationAction('unknown', 0),
    {name: 'TypeError', message: 'InvalidRunHostPublicationAction'});
});
