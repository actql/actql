// Reviewed static proof ownership. This module performs no toolchain or runtime
// discovery: changing an assignment changes the canonical sealed plan digest.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
const freeze = value => {
  if (value && typeof value === 'object') { Object.values(value).forEach(freeze); Object.freeze(value); }
  return value;
};
export const partIds = freeze(['L-C0', 'L-C1', 'L-M0', 'L-M1']);
export const mutationNamesByPart = freeze({
  'L-M0': ['handoff-wrong-port', 'stable-tie-reversed', 'rename-nullability-widened', 'rename-type-changed'],
  'L-M1': ['rename-swap-wrong-input', 'distinct-first-column-only', 'distinct-reversed-survivors', 'distinct-handoff-wrong-port'],
});
export const capacityObligationsByPart = freeze({
  'L-C0': {
    normal: { caseCount: 28, targets: ['js', 'wasm', 'native'] },
    boundaries: { values: [-1, 0, 1], caseCount: 28, targets: ['js', 'wasm', 'native'] },
    backingCore: ['js', 'wasm', 'native'], backingModel: true, structuralModel: true,
    custody: { healthy: 9, negative: 2 }, nativeParentStartup: true,
    finalNormal: { caseCount: 86, targets: ['js', 'wasm', 'native'] },
  },
  'L-C1': {
    mutations: ['missing-index-reservation', 'premature-keep-release', 'duplicate-index-release',
      'handoff-copy-without-accounting', 'oversized-metadata-map'],
    freshSearch: 'js', shrink: 'js', replayTargets: ['js', 'wasm', 'native'],
    healthy: 15, ownerLocalRestoration: { caseCount: 5, targets: ['js', 'wasm', 'native'] },
  },
});
export const plan = freeze({
  version: 'actql-pipeline-proof-parts/0.1',
  parts: Object.fromEntries(partIds.map(id => [id, id.startsWith('L-M')
    ? { family: 'mutations', variants: mutationNamesByPart[id], modes: ['fixed', 'explore'],
      baseline: 'js', replayTargets: ['js', 'wasm', 'native'],
      restoration: 'new-owner-restored-mutable-and-independent-pristine' }
    : { family: 'capacity', obligations: capacityObligationsByPart[id] }])),
});
export const planDigest = createHash('sha256').update(JSON.stringify(plan)).digest('hex');
export function partFamily(id) {
  assert(partIds.includes(id), `Unknown proof part ${id}`);
  return plan.parts[id].family;
}
