// Conditional, finite runtime contract for the first reusable action. This is
// an explicit trust boundary, not a proof of Node, Moon, Docker or the kernel.
// The reviewed mutation/test cohort enumerates deterministic histories and
// literal set/Nest fixtures; elapsed time, process IDs and temp names are not
// scientific observations. Future source/environment cohorts stay open until
// their effects are reviewed. Normal execution remains available in all cases.
export const isolatedContract = Object.freeze({
  id: 'actql-isolated-session-mutations-contract/0.1',
  reviewRevision: '2034069ff171d09684b43cba21e9e9552dc3aa69',
  snapshotDigest: '81dec309e9796bf5b5a1168547c584183e3c8799c145ab27bb19ceba07af41f7',
  toolchainDigest: '8a3a1396f02ba4d5d780382960d1bcf95ccc8d6b97c3da446c0899b98874819a',
  hostImage: '20260927.320.1',
  kernelRelease: '6.17.0-1022-azure',
  trustedSemantics: Object.freeze([
    'pinned Node/Moon execute their specified deterministic language operations',
    'GitHub-hosted Linux/Docker preserve process and isolated filesystem semantics',
    'CPU implements the bound architecture and cryptographic digests are collision resistant',
  ]),
  observable: 'the thirteen registered running-assertion mutation detections and byte-exact restoration',
  excludedObservations: Object.freeze(['elapsed time', 'temporary names', 'process identifiers']),
});

export function matchesIsolatedContract(manifest) {
  return manifest.sourceSnapshotDigest === isolatedContract.snapshotDigest &&
    manifest.toolchainDigest === isolatedContract.toolchainDigest &&
    manifest.hostImage === isolatedContract.hostImage &&
    manifest.platformInputs?.kernelRelease === isolatedContract.kernelRelease;
}
