// Conditional, finite runtime contract for the first reusable action. This is
// an explicit trust boundary, not a proof of Node, Moon, Docker or the kernel.
// The reviewed mutation/test cohort enumerates deterministic histories and
// literal set/Nest fixtures; elapsed time, process IDs and temp names are not
// scientific observations. Future source/environment cohorts stay open until
// their effects are reviewed. Product inputs are still independently keyed:
// a product change executes fresh, without requiring a new experiment review.
// Normal execution remains available in all cases.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {encode} from '../bounded-session/action-inputs.mjs';

export const isolatedExperimentPaths = Object.freeze([
  'proofs/bounded-session/mutations.mjs',
  'proofs/bounded-session/evidence.mjs',
  'proofs/bounded-session/action-inputs.mjs',
  'src/bounded_execution/session_contract_wbtest.mbt',
  'src/bounded_execution/session_wbtest.mbt',
  'src/connectors/local/bounded_session_contract_wbtest.mbt',
  'src/query_integration/local_managed_set_wbtest.mbt',
  'src/query_integration/local_managed_nest_wbtest.mbt',
  'src/query_integration/physical_graph_wbtest.mbt',
  'src/query_integration/local_managed_group_wbtest.mbt',
]);

export function isolatedExperimentDigest(tree) {
  tree.prefetch?.(isolatedExperimentPaths);
  const inputs = [...isolatedExperimentPaths].sort().map(path => {
    const entry = tree.entries.get(path), bytes = tree.read(path);
    assert(entry?.kind === 'blob' && ['100644', '100755'].includes(entry.mode), 'Missing/unsupported experiment input');
    return {path, mode: entry.mode, bytes: bytes.length,
      digest: createHash('sha256').update(bytes).digest('hex')};
  });
  return createHash('sha256').update(`actql-isolated-experiment/0.1\0${encode(inputs)}`).digest('hex');
}
export const isolatedContract = Object.freeze({
  id: 'actql-isolated-session-mutations-contract/0.1',
  // The finite effect review and retained physical correspondence are recorded
  // in docs/reviews/2026-10-06-current-isolated-experiment-contract.md.
  reviewRevision: '8e090492aa323836bca86871602b8dd6109f5d4f',
  experimentDigest: '5fb3fc315c59e0c88123cc6824e9634729f84e81824ab18cf323e22c11f37a14',
  toolchainDigest: '8a3a1396f02ba4d5d780382960d1bcf95ccc8d6b97c3da446c0899b98874819a',
  hostImage: '20260927.320.1',
  kernelRelease: '6.17.0-1022-azure',
  trustedSemantics: Object.freeze([
    'pinned Node/Moon execute their specified deterministic language operations',
    'GitHub-hosted Linux/Docker preserve process and isolated filesystem semantics',
    'CPU implements the bound architecture and cryptographic digests are collision resistant',
    'the registered finite experiments have deterministic scientific verdicts under the bound execution contract',
  ]),
  observable: 'the thirteen registered running-assertion mutation detections and byte-exact restoration',
  excludedObservations: Object.freeze(['elapsed time', 'temporary names', 'process identifiers']),
});

export function matchesIsolatedContract(manifest) {
  return manifest.experimentDigest === isolatedContract.experimentDigest &&
    manifest.toolchainDigest === isolatedContract.toolchainDigest &&
    manifest.hostImage === isolatedContract.hostImage &&
    manifest.platformInputs?.kernelRelease === isolatedContract.kernelRelease;
}
