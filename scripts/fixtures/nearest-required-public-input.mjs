// Adopted F04 tie/empty/shared-producer obligations. These inputs and results
// are authored independently; no lowering or runtime output is inspected.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {nearestCarrierFixtureDirectory, nearestCarrierSourceRows}
  from './nearest-carrier-source-data.mjs';
const json = async name => JSON.parse(await readFile(nearestCarrierFixtureDirectory + name, 'utf8'));
const base = await json('common-minimal.program.json');
const {columns} = await json('expected-schema.json');
const tieRows = {queries: structuredClone(nearestCarrierSourceRows.queries), candidates: [
  {item_id: 'z', embedding: [1, 0], label: 'tie z'},
  {item_id: 'b', embedding: [1, 0], label: 'tie b'},
  {item_id: 'a', embedding: [1, 0], label: 'tie a'},
]};
const emptyRows = {queries: [], candidates: structuredClone(nearestCarrierSourceRows.candidates)};
const pair = (candidate, rank, field = 'item_id') => ({query_key: {request_id: 'q1'},
  candidate_key: {[field]: candidate}, score: 1, rank});
const sharedContract = structuredClone(columns[2].contract);
sharedContract.fields.candidate_key.fields = {request_id: {type: 'string', nullable: false}};
const sharedColumns = [{name: 'neighbor', contract: sharedContract},
  {name: 'rank', contract: {type: 'number', nullable: false}}];
const definitions = [
  {name: 'ties', rows: tieRows, expected: [{note: null, label: 'tie a', neighbor: pair('a', 1)},
    {note: null, label: 'tie b', neighbor: pair('b', 2)}], columns, reads: 2},
  {name: 'empty', rows: emptyRows, expected: [], columns, reads: 2},
  {name: 'shared-producer', rows: structuredClone(nearestCarrierSourceRows),
    expected: [{neighbor: pair('q1', 1, 'request_id'), rank: 1}], columns: sharedColumns, reads: 1},
];
const kept = 'FROM queries AS q |> NEAREST candidates AS c QUERY KEY (q.request_id) VECTOR q.embedding CANDIDATE KEY (c.item_id) VECTOR c.embedding METRIC dot K 2 KEEP (q.note, c.label) AS neighbor |> ORDER BY neighbor.rank';
const shared = 'FROM queries AS q |> NEAREST queries AS c QUERY KEY (q.request_id) VECTOR q.embedding CANDIDATE KEY (c.request_id) VECTOR c.embedding METRIC dot K 1 AS neighbor |> SELECT neighbor, neighbor.rank AS rank |> ORDER BY rank';
function control(definition) {
  if (definition.name !== 'shared-producer') {
    const program = structuredClone(base);
    program.id += '.' + definition.name;
    program.stages[0].steps[0].values.rows = structuredClone(definition.rows.queries);
    program.stages[0].steps[1].values.rows = structuredClone(definition.rows.candidates);
    return program;
  }
  // One original Values producer occurs in both NEAREST operand roles.
  const query = structuredClone(base.stages[0].steps[0]);
  return {version: 'actql/0.1', id: 'fixture.nearest_same_producer', stages: [{id: 'main', inputs: {},
    steps: [query, {from: 'queries', nearest: {queries: 'queries', query_id: 'request_id',
      query_vector: 'embedding', candidate_id: 'request_id', candidate_vector: 'embedding', metric: 'dot', k: 1}},
    {derive: {neighbor: {object: {query_key: {object: {request_id: {field: 'query_id'}}},
      candidate_key: {object: {request_id: {field: 'candidate_id'}}}, score: {field: 'score'}, rank: {field: 'rank'}}}}},
    {sort: [{field: 'rank', dir: 'asc', nulls: 'first'}]}, {select: ['neighbor', 'rank'], as: 'out'}],
    results: {rows: {from: 'out', fields: ['neighbor', 'rank']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
}
export const nearestRequiredSuccesses = definitions.flatMap(definition => [
  {name: `nearest-required-${definition.name}-json`, format: 'json', text: JSON.stringify(control(definition)),
    results: {answer: {rows: structuredClone(definition.expected), columns: structuredClone(definition.columns), unordered: true}},
    sourceReadCount: 0, sourceReadSessionCount: 0},
  ...['sql', 'aql-text'].map(format => ({name: `nearest-required-${definition.name}-${format}`, format,
    text: definition.name === 'shared-producer' ? shared : kept,
    results: {answer: {rows: structuredClone(definition.expected), columns: structuredClone(definition.columns), unordered: false}},
    sourceRows: structuredClone(definition.rows), sourceReadCount: definition.reads, sourceReadSessionCount: definition.reads})),
]);
const rejected = [
  ['missing-query-vector', kept.replace(' VECTOR q.embedding', '')],
  ['missing-candidate-vector', kept.replace(' VECTOR c.embedding', '')],
  ['relation-roles-omitted', kept.replace('QUERY KEY (q.request_id) VECTOR q.embedding CANDIDATE KEY (c.item_id) VECTOR c.embedding ', '')],
  ['nullable-query-key', kept.replace('QUERY KEY (q.request_id)', 'QUERY KEY (q.note)')],
  ['dimension-mismatch', kept.replace('VECTOR q.embedding', 'VECTOR VECTOR_CONCAT(q.embedding,q.embedding)')],
];
export const nearestRequiredRefusals = rejected.flatMap(([name, text]) => ['sql', 'aql-text'].map(format => ({
  name: `nearest-required-${name}-${format}`, format, text, expectedCode: 'ClientProgramInvalidInput',
})));
export function createNearestRequiredRows() {
  let current = structuredClone(nearestCarrierSourceRows);
  return {
    prepare(value = nearestCarrierSourceRows) {
      assert.ok(definitions.some(definition => {
        try {assert.deepEqual(value, definition.rows); return true;} catch {return false;}
      }));
      current = structuredClone(value);
    },
    read(resource) {assert.ok(['queries', 'candidates'].includes(resource)); return structuredClone(current[resource]);},
  };
}
