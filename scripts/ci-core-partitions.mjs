// Compiler-driver ownership, shared by the Native selector and checkpoint
// inventory. The workflow's literal matrix is checked against this inventory.
export const nativeCoreCiPartitions = Object.freeze([
  '1/4', '2/4', '3/4', '4/4', 'http', 'source', 'scoped',
]);
