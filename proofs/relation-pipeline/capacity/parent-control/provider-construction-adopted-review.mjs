import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {hash} from '../../inventory.mjs';
import {historicalConstructionSource, currentConstructionReview} from './provider-construction-current-review.mjs';

export const adoptedConstructionReview = JSON.parse(readFileSync(
  new URL('./provider-construction-adopted-review.json', import.meta.url)));

// Exact immutable source correspondence only. Reconstructed text is never
// executed and cannot authenticate an observation from a different layout.
export function beforeAdoptedConstructionSource(source, path) {
  const entry = adoptedConstructionReview.sources.find(entry => entry.path === path);
  if (!entry) return source;
  assert.equal(hash(source), entry.currentSha256, `Unreviewed adopted constructor source ${path}`);
  let previous = source;
  for (const {before, after} of entry.hunks) {
    assert(before && after && before !== after);
    assert.equal(previous.split(after).length, 2, 'Missing unique adopted constructor delta');
    previous = previous.replace(after, before);
  }
  assert.equal(hash(previous), entry.previousSha256, `Changed adopted constructor preimage ${path}`);
  return previous;
}

export function retainedConstructionRead(read) {
  return path => {
    const entry = currentConstructionReview.sources.find(entry => entry.path === path);
    return entry ? Buffer.from(historicalConstructionSource(beforeAdoptedConstructionSource(read(path).toString(), path), entry))
      : read(path);
  };
}
