import assert from 'node:assert/strict';
import {mutationIds, mutationContracts} from './mutation-inventory.mjs';
import {encode} from '../bounded-session/action-inputs.mjs';
import {createHash} from 'node:crypto';

// Compare the scientific experiment result, not merely the total test count
// and not incidental timing/stack text or a rewritten source/revision label.
// Source, original owner, raw assertion logs and restoration are checked at
// their independent receipt/image boundaries before this digest is accepted.
export function mutationObservation(result) {
  assert(Array.isArray(result?.results) && result.results.length === mutationIds.length, 'Incomplete mutation result');
  assert.deepEqual(result.results.map(entry => entry.id).sort(), [...mutationIds].sort(), 'Changed/duplicate mutation experiment');
  const observations = result.results.map(entry => {
    const contract = mutationContracts[entry.id];
    for (const field of ['path', 'suite', 'filter']) assert.equal(entry[field], contract[field], 'Wrong mutation experiment location/selection');
    assert.equal(entry.target, 'js'); assert.equal(entry.killed, true);
    assert(Number.isSafeInteger(entry.failureCount) && entry.failureCount > 0, 'No running-assertion detection');
    return {id: entry.id, ...contract, target: entry.target, killed: entry.killed, failureCount: entry.failureCount};
  }).sort((a, b) => a.id.localeCompare(b.id));
  return {observations, digest: createHash('sha256').update(`actql-mutation-scientific-observation/0.1\0${encode(observations)}`).digest('hex')};
}
