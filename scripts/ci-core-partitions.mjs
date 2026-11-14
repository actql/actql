// Compiler-driver ownership, shared by the Native selector and checkpoint
// inventory. The workflow's literal matrix is checked against this inventory.
export const nativeCoreCiPartitions = Object.freeze([
  '1/2', '2/2', 'source', 'scoped-runtime', 'scoped-review',
]);
// Profiles are distinct from hosted jobs: the first Darwin ordinary job also
// executes the original HTTP profile. Source and both original scoped allocation
// profiles have separate runners; the combined scoped profile remains local.
export const nativeCoreScopedCiProfiles = Object.freeze({
  'scoped-runtime': 'runtime-values', 'scoped-review': 'scoped-review-values',
});
export const nativeCorePhysicalProfiles = Object.freeze([
  'http', 'source', 'scoped', ...Object.keys(nativeCoreScopedCiProfiles),
]);
