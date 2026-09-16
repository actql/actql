import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {retainedMatrix} from './fixtures.mjs';

test('direct-path requirement fixes all 21 large cases without changing the original experiment', () => {
  const original = readFileSync(new URL('experiment.json', import.meta.url));
  const experiment = JSON.parse(original);
  const registration = JSON.parse(readFileSync(new URL('direct-path-registration.json', import.meta.url)));
  assert.equal(createHash('sha256').update(original).digest('hex'), registration.experimentSha256);
  assert.equal(registration.retentionBytes, '1073741824');
  assert.equal(registration.status, 'registered-not-measured');
  const matrix = retainedMatrix();
  const expected = matrix.filter(f => (f.layout === 'narrow'
    ? experiment.narrowLargeRows : experiment.wideLargeRows).includes(f.rows)).map(f => f.id);
  assert.equal(matrix.length, 27);
  assert.equal(expected.length, 21);
  assert.equal(new Set(registration.largeCaseIds).size, 21);
  assert.deepEqual([...registration.largeCaseIds].sort(), expected.sort());
});
