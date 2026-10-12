// Prepared public inputs, not execution evidence. Reuse the existing public
// query consumer and the ordinary typed candidates installation used by NEAREST.
// Values, component folds and complete output contracts are authored below.
const number = {type: 'number', nullable: false};
const string = {type: 'string', nullable: false};
const vector = {type: 'vector', dimensions: 2, nullable: false};
const fields = ['cohort', 'pooled_id', 'embedding', 'member_count'];
const columns = fields.map(name => ({name, contract: name === 'embedding' ? vector : number}));
const input = [{item_id: 'b', embedding: [0, 1], label: 'second'},
  {item_id: 'a', embedding: [1, 0], label: 'first'}];
const result = (method, empty = false) => ({answer: {columns,
  rows: empty ? [] : [{cohort: 1, pooled_id: 1,
    embedding: method === 'mean' ? [0.5, 0.5] : [1, 1], member_count: 2}]}});

function control(method, empty = false) {
  return {version: 'actql/0.1', id: 'fixture.vector_pool_' + method + (empty ? '_empty' : ''),
    stages: [{id: 'main', inputs: {}, steps: [
      {values: {schema: {item_id: string, embedding: vector, label: string},
        rows: empty ? [] : input}, as: 'candidates'},
      {from: 'candidates', derive: {cohort: {literal: 1}}},
      {select: ['item_id', 'embedding', 'cohort']},
      {assert_rows: {unique_by: ['item_id']}, as: 'members'},
      {from: 'members', pool_vectors: {vector: 'embedding', by: ['cohort'],
        method, output_id: 'pooled_id'}, as: 'pooled'},
      {from: 'pooled', vectors: true},
      {sort: [{field: 'cohort', dir: 'asc', nulls: 'first'}]},
      {select: fields, as: 'out'},
    ], results: {rows: {from: 'out', fields}}}],
    results: {answer: {from: {stage: 'main', result: 'rows'}}}};
}

const members = (relation, empty = false) =>
  'FROM candidates' + (empty ? ' |> WHERE FALSE' : '')
  + ' |> SELECT item_id, embedding, 1 AS cohort |> '
  + (relation ? 'ASSERT UNIQUE BY (item_id)' : 'to_vectors(id: item_id, vector: embedding)');
const source = (method, relation, empty = false) => 'WITH members AS (' + members(relation, empty)
  + '), pooled AS (FROM members |> pool_vectors(by: [COHORT], method: ' + JSON.stringify(method)
  + ', output_id: pooled_id' + (relation ? ', vector: EMBEDDING' : '')
  + ')), rows AS (FROM pooled |> vectors()) '
  + 'SELECT cohort, pooled_id, embedding, member_count FROM rows ORDER BY cohort';

export const vectorPoolSourceSuccesses = ['sum', 'mean', 'max'].flatMap(method => [
  {name: 'vector-pool-json-' + method, format: 'json', text: JSON.stringify(control(method)),
    results: result(method), sourceReadCount: 0, sourceReadSessionCount: 0},
  ...[true, false].map(relation => ({name: 'vector-pool-' + (relation ? 'relation-' : 'vectors-') + method,
    format: 'aql-text', text: source(method, relation), results: result(method),
    sourceReadSessionCount: 1})),
]);
vectorPoolSourceSuccesses.push(
  {name: 'vector-pool-json-empty', format: 'json', text: JSON.stringify(control('mean', true)),
    results: result('mean', true), sourceReadCount: 0, sourceReadSessionCount: 0},
  {name: 'vector-pool-source-empty', format: 'aql-text', text: source('mean', false, true),
    results: result('mean', true)},
);

const refusal = (name, call, prefix = members(false)) => ({
  name: 'vector-pool-' + name, format: 'aql-text',
  text: 'WITH members AS (' + prefix + ') FROM members |> ' + call
    + ' |> vectors() |> SELECT cohort', expectedCode: 'ClientProgramInvalidInput',
});
export const vectorPoolSourceRefusals = [
  refusal('missing-key', "pool_vectors(by: [cohort], method: 'sum', vector: embedding)",
    'FROM candidates |> SELECT item_id, embedding, 1 AS cohort'),
  refusal('duplicate-group', "pool_vectors(by: [cohort, COHORT], method: 'sum')"),
  refusal('method-is-exact', "pool_vectors(by: [cohort], method: 'SUM')"),
  refusal('output-collision', "pool_vectors(by: [cohort], method: 'sum', output_id: embedding)"),
  refusal('reserved-output', "pool_vectors(by: [cohort], method: 'sum', output_id: SELECT)"),
];
