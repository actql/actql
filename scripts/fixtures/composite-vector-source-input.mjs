// Independent F04 controls for the existing ordered [b, a] Vectors identity.
// Explicit singleton-group pooling is authored, not a hidden NEAREST adapter.
const number = {type: 'number', nullable: false};
const string = {type: 'string', nullable: false, max_utf8_bytes: 1};
export const compositeVectorSchema = Object.freeze({a: string, b: number,
  embedding: {type: 'vector', dimensions: 2, nullable: false}});
export const compositeVectorFacts = Object.freeze({relation_keys: {candidate_keys: [['b', 'a']]}});
// Repeating b makes a singleton-ID substitution fail; each complete key is unique.
export const compositeVectorRows = Object.freeze({
  queries: [{b: 1, a: 'b', embedding: [0, 1]}, {b: 1, a: 'a', embedding: [1, 0]}],
  candidates: [{b: 1, a: 'a', embedding: [1, 0]}, {b: 1, a: 'b', embedding: [0, 1]}],
});
const key = {type: 'object', nullable: false, additional_properties: false,
  fields: {a: string, b: number}};
export const compositeVectorResults = {answer: {rows: ['a', 'b'].map(a => ({hit: {
  query_key: {b: 1, a}, candidate_key: {b: 1, a}, score: 1, rank: 1,
}})), columns: [{name: 'hit', contract: {type: 'object', nullable: false,
  additional_properties: false, fields: {query_key: key, candidate_key: key,
    score: number, rank: number}}}]}};
const property = (field, name) => ({property: {value: {field}, name}});
const identity = field => ({object: {b: property(field, '0'), a: property(field, '1')}});
const pool = {by: ['b', 'a'], method: 'mean', vector: 'embedding'};
// Source acquisitions retain the ordinary owned Filter/Select prefix. The
// declared Source key still owes complete input validation before that prefix.
export const compositeVectorProgram = {version: 'actql/0.1', id: 'fixture.composite_vectors',
  stages: ['queries', 'candidates'].map(resource => ({id: resource + '_source',
    inputs: {remote: {connector: 'composite_fixture', resource}}, steps: [
      {from: 'remote', filter: 'true', as: 'all_rows'},
      {from: 'all_rows', select: ['a', 'b', 'embedding'], as: 'captured'},
    ], results: {rows: {from: 'captured', fields: ['a', 'b', 'embedding']}}})).concat([
      {id: 'main', inputs: {queries: {result: {stage: 'queries_source', result: 'rows'}},
        candidates: {result: {stage: 'candidates_source', result: 'rows'}}}, steps: [
        {from: 'queries', pool_vectors: pool, as: 'qv'},
        {from: 'candidates', pool_vectors: pool, as: 'cv'},
        {from: 'cv', nearest: {queries: 'qv', metric: 'cosine', k: 1}, as: 'matches'},
        {from: 'matches', derive: {hit: {object: {query_key: identity('query_id'),
          candidate_key: identity('candidate_id'), score: {field: 'score'}, rank: {field: 'rank'}}},
          query_a: property('query_id', '1'), candidate_a: property('candidate_id', '1')}, as: 'projected'},
        {from: 'projected', sort: [{field: 'query_a', dir: 'asc', nulls: 'first'},
          {field: 'candidate_a', dir: 'asc', nulls: 'first'}], as: 'ordered'},
        {from: 'ordered', select: ['hit'], as: 'out'},
      ], results: {rows: {from: 'out', fields: ['hit']}}},
    ]), results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const bindings = "WITH qv AS (FROM queries |> pool_vectors(by: [b, a], method: 'mean', vector: embedding)), " +
  "cv AS (FROM candidates |> pool_vectors(by: [b, a], method: 'mean', vector: embedding))";
const roles = ' QUERY KEY (b, a) VECTOR embedding CANDIDATE KEY (corpus.b, corpus.a) VECTOR corpus.embedding';
function source(format, roleText) {
  const nearest = 'FROM qv |> NEAREST cv AS corpus' + roleText + ' METRIC cosine K 1 AS hit';
  const order = 'ORDER BY hit.query_key.a, hit.candidate_key.a';
  return format === 'sql'
    ? bindings + ', hits AS (' + nearest + ') SELECT hit FROM hits ' + order
    : bindings + ' ' + nearest + ' |> SELECT hit |> ' + order;
}
export const compositeVectorSuccesses = [{name: 'composite-vector-json', format: 'json',
  text: JSON.stringify(compositeVectorProgram), results: compositeVectorResults,
  sourceReadCount: 2, sourceReadSessionCount: 2},
...['implicit', 'explicit'].flatMap(role => ['sql', 'aql-text'].map(format => ({
  name: `composite-vector-${role}-${format}`, format,
  text: source(format, role === 'explicit' ? roles : ''),
  results: compositeVectorResults, sourceReadCount: 2, sourceReadSessionCount: 2,
})))];
export const compositeVectorRefusals = ['sql', 'aql-text'].map(format => ({
  name: `composite-vector-reordered-query-key-${format}`, format,
  text: source(format, roles.replace('QUERY KEY (b, a)', 'QUERY KEY (a, b)')),
  expectedCode: 'ClientProgramInvalidInput', sourceReadCount: 0, sourceReadSessionCount: 0,
}));
