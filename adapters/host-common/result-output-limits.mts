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
] as const);

export const resultOutputLimitFields = Object.freeze([
  'maxResultFields',
  'maxResultMappingWork',
  'maxResultOrderWork',
  'maxResultWorkspaceEntries',
  ...outputLimitFields,
] as const);

type Limits<Field extends string> = Readonly<Record<Field, number>>;
type OutputLimits = Limits<typeof outputLimitFields[number]>;
type ResultOutputLimits = Limits<typeof resultOutputLimitFields[number]>;

const validLimits = <Field extends string,>(limits: unknown, expected: readonly Field[]): limits is Limits<Field> =>
  limits !== null && typeof limits === 'object' &&
  !Array.isArray(limits) &&
  Object.keys(limits).sort().join('\0') ===
    [...expected].sort().join('\0') &&
  expected.every(name => Number.isSafeInteger((limits as Limits<Field>)[name]) &&
    (limits as Limits<Field>)[name] >= 0);

export const validOutputLimits = (limits: unknown): limits is OutputLimits =>
  validLimits(limits, outputLimitFields);

export const validResultOutputLimits = (limits: unknown): limits is ResultOutputLimits =>
  validLimits(limits, resultOutputLimitFields);
