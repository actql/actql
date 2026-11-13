// One local finite campaign; it never changes the complete part's obligations.
import assert from 'node:assert/strict';
import {mutationNamesByPart, logicalMutationNamesByPart} from './proof-parts.mjs';
export const fixedJsAction = Object.freeze({id: 'pipeline-l-m0-fixed-js-campaign',
  part: 'L-M0', mode: 'fixed', target: 'js', phases: Object.freeze(['mutated', 'pristine', 'post-restore'])});

export function mutationCampaignScope(options = {}) {
  assert(options && typeof options === 'object' && !Array.isArray(options));
  assert(Object.keys(options).every(key => ['profile', 'mode', 'partId', 'revision'].includes(key)), 'Unknown campaign option');
  const {profile = 'full', mode = 'explore', partId = null, revision = null} = options;
  assert(['full', 'local-fixed-js'].includes(profile), 'Unregistered campaign profile');
  assert(['fixed', 'explore', 'auto', 'verify'].includes(mode), 'Unregistered campaign mode');
  assert(partId === null || Object.hasOwn(profile === 'local-fixed-js' ? logicalMutationNamesByPart : mutationNamesByPart, partId), 'Unregistered mutation part');
  if (profile === 'local-fixed-js') {
    assert.equal(mode, 'fixed', 'Local campaign cannot select exploration');
    assert.equal(partId, fixedJsAction.part, 'Local campaign cannot change its part');
    assert(typeof revision === 'string' && /^[a-f0-9]{40}$/u.test(revision), 'Missing local candidate identity');
  } else assert.equal(revision, null, 'Full campaign obtains its revision from Git');
  return Object.freeze({profile, mode, partId, revision,
    targets: Object.freeze(profile === 'full' ? ['js', 'wasm', 'native'] : ['js'])});
}
