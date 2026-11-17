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

// Scheduling hints from run43583078880's generated-C process elapsed samples
// (jobs132411952304/321). These are overlapping lower-bound observations, not
// exact cold compile durations, budgets or a claim that restored cache is cold.
// Keep each complete compiler package together. Unobserved drivers use20 units.
export const nativeCoreCompilerWeights = Object.freeze({
  'src/cmd/native_client': 398,
  'src/query_integration': 191,
  'src/native_values_integration': 154,
  'src/platform_native/remote_values_host': 127,
  'src/cmd/native_remote_resident_site': 118,
  'src/platform_native/row_source': 87,
  'src/cmd/native_retained_case_probe': 76,
});
