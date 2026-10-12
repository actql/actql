import assert from 'node:assert/strict';
import test from 'node:test';
import {nearestCarrierPublicFixtures} from './fixtures/nearest-carrier-public-input.mjs';
import {nearestPublicInputFixtures} from './fixtures/nearest-public-input.mjs';
test('F04 public recipes retain independent rows, full schema, roles and K/metric', async () => {
  const directory='spec/frontend/fixtures/nearest-keep';
  const {successes,refusals}=await nearestCarrierPublicFixtures(directory);
  const control=(await nearestPublicInputFixtures(directory)).successes.find(item=>item.name==='nearest-source-keep');
  assert.equal(successes.length,10);
  assert.equal(refusals.length,5);
  for(const item of successes) {
    assert.deepEqual(item.results,control.results);
    assert.match(item.text,/METRIC dot K 2/u);
    assert.match(item.text,/KEEP \([^\n]+\.note, c.label\)/u);
    assert.match(item.text,/ORDER BY neighbor.rank/u);
    if(item.name.includes('vectors-vectors')) {
      assert.doesNotMatch(item.text,/QUERY KEY|CANDIDATE KEY/u);
    }
  }
  assert.deepEqual(new Set(successes.map(item=>item.format)),new Set(['sql','aql-text']));
  assert.ok(refusals.every(item=>item.expectedCode==='ClientProgramInvalidInput'));
});
