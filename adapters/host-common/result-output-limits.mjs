export const outputLimitFields = Object.freeze([
  'maxRows',
  'maxValueNodes',
  'maxValueTextBytes',
  'maxValueDepth',
  'maxValueWork',
  'maxWireBytes',
  'maxWireNodes',
  'maxWireDepth',
  'maxColumns',
  'maxOrderWork',
  'maxLogicalWireBytes',
  'maxLogicalWireNodes',
  'maxLogicalWireDepth',
  'maxSchemaFields',
  'maxSchemaBytes',
  'maxSchemaNodes',
  'maxSchemaDepth',
  'maxBatchBytes',
]);

export const resultOutputLimitFields = Object.freeze([
  'maxResultFields',
  'maxResultMappingWork',
  'maxResultOrderWork',
  'maxResultWorkspaceEntries',
  ...outputLimitFields,
]);

const validLimits = (limits, expected) =>
  limits !== null && typeof limits === 'object' &&
  !Array.isArray(limits) &&
  Object.keys(limits).sort().join('\0') ===
    [...expected].sort().join('\0') &&
  expected.every(name => Number.isSafeInteger(limits[name]) &&
    limits[name] >= 0);

export const validOutputLimits = limits =>
  validLimits(limits, outputLimitFields);

export const validResultOutputLimits = limits =>
  validLimits(limits, resultOutputLimitFields);
