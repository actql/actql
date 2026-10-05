// Diagnostic reproduction, separate from independent lowering/result oracles.
const number = {type: 'number', nullable: false};
const receiver = {type: 'object', nullable: true, fields: {score: number}};
const tail = 'SELECT l.payload.score FROM objects AS l JOIN others AS r '
  + 'ON l.id = r.id MAX_OUTPUT_ROWS 1';
export const sharedSeedJoinReproduction = {
  format: 'aql-text',
  text: 'DATA seed = SELECT 1 AS id; '
    + 'DATA objects = SELECT 1 AS id, @a AS payload FROM seed; '
    + 'DATA others = SELECT 1 AS id, @b AS other FROM seed; ' + tail,
  parameterDeclarations: {a: receiver, b: receiver},
  parameters: {a: {score: 10}, b: {score: 20}},
  expected: [{score: 10}],
  columns: [{name: 'score', contract: {...number, nullable: true}}],
};
export const independentSeedJoinControl = {
  ...sharedSeedJoinReproduction,
  text: 'DATA objects = SELECT 1 AS id, @a AS payload; '
    + 'DATA others = SELECT 1 AS id, @b AS other; ' + tail,
};
