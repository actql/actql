// Compiler-driver ownership, shared by the Native selector and checkpoint
// inventory. The workflow's literal matrix is checked against this inventory.
export const nativeCoreCiPartitions = Object.freeze([
  '1/2', '2/2', 'source', 'scoped',
]);
// Profiles are distinct from hosted jobs: the first Darwin ordinary job also
// executes the original HTTP profile; Source and scoped keep their own jobs.
export const nativeCorePhysicalProfiles = Object.freeze(['http', 'source', 'scoped']);
