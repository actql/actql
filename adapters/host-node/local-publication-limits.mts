const limits = Object.freeze({maxWireBytes: 1000000, maxNodes: 100000,
  maxDepth: 64});
export const localOutputLimits = Object.freeze({
  maxResultFields: 10, maxResultMappingWork: 1000,
  maxResultOrderWork: 10000, maxResultWorkspaceEntries: 100,
  maxRows: 10000, maxValueNodes: 1000000, maxValueTextBytes: 10000000,
  maxValueDepth: 64, maxValueWork: 1000000, maxWireBytes: 10000000,
  maxWireNodes: 1000000, maxWireDepth: 64, maxColumns: 100,
  maxOrderWork: 1000000, maxLogicalWireBytes: 10000000,
  maxLogicalWireNodes: 1000003, maxLogicalWireDepth: 66,
  maxSchemaFields: 100, maxSchemaBytes: 100000,
  maxSchemaNodes: 10000, maxSchemaDepth: 64, maxBatchBytes: 65536,
});
export const localContractLimits = limits;
