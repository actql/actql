// Original independent max/weighted controls. Physical JSON pages are Source
// transport, distinct from the frontend JSON Program's two connector inputs.
const number = Object.freeze({type: 'number', nullable: false});
export const sourceRankingSchema = Object.freeze({id: number, s: number});
export const sourceRankingRows = Object.freeze({
  left: Object.freeze([Object.freeze({id: 1, s: 0.5})]),
  right: Object.freeze([Object.freeze({id: 2, s: 0.5})]),
});
const columns = ['id', 'score', 'rank'].map(name => ({name, contract: number}));
const contract = Object.freeze({domain: 'Relevance', normalization: 'Identity', range: Object.freeze([0, 1])});
const policies = [
  {name: 'max', policy: 'max', text: "'max'", score: 0.5},
  {name: 'weighted', policy: {weighted_sum: {left: 0.5, right: 0.5}},
    text: '{weighted_sum: {left: 0.5, right: 0.5}}', score: 0.25},
];
export function sourceRankingControlProgram(policy) {
  return {version: 'actql/0.1', id: 'fixture.scored_catalog', stages: [{id: 'main',
    inputs: {left: {connector: 'score_fixture', resource: 'left'},
      right: {connector: 'score_fixture', resource: 'right'}},
    steps: [{from: 'left', merge_rankings: {with: 'right', by: [], candidate: 'id',
      score: 's', k: 3, score_policy: structuredClone(policy), score_contract: structuredClone(contract)}, as: 'fused'},
    {from: 'fused', sort: [{field: 'rank', dir: 'asc', nulls: 'first'}]},
    {select: ['id', 'score', 'rank'], as: 'out'}],
    results: {rows: {from: 'out', fields: ['id', 'score', 'rank']}}}],
    results: {answer: {from: {stage: 'main', result: 'rows'}}}};
}
function pipe(policy) {
  return `FROM l |> merge_rankings(with: r, by: [], candidate: id, score: s, k: 3, score_policy: ${policy}, score_contract: {domain: 'Relevance', normalization: 'Identity', range: [0, 1]}) |> SELECT id, score, rank |> ORDER BY rank`;
}
export const sourceRankingPublicSuccesses = policies.flatMap(policy => {
  const results = {answer: {columns, rows: [
    {id: 1, score: policy.score, rank: 1}, {id: 2, score: policy.score, rank: 2},
  ]}};
  const shared = {results, sourceReadCount: 2, sourceReadSessionCount: 2};
  return [{name: `source-score-json-${policy.name}`, format: 'json',
    text: JSON.stringify(sourceRankingControlProgram(policy.policy)), ...shared},
  {name: `source-score-pipe-${policy.name}`, format: 'aql-text', text: pipe(policy.text), ...shared},
  {name: `source-score-with-${policy.name}`, format: 'sql',
    text: `WITH fused AS (${pipe(policy.text)}) SELECT id, score, rank FROM fused ORDER BY rank`, ...shared}];
});
export const sourceRankingPublicRefusals = policies.flatMap(policy => [
  {name: `source-score-argument-only-field-${policy.name}`, format: 'aql-text',
    text: pipe(policy.text).replace('score: s', 'score: id'),
    expectedCode: 'ClientProgramInvalidInput', sourceReadCount: 0},
  {name: `source-score-contract-mismatch-${policy.name}`, format: 'aql-text',
    text: pipe(policy.text).replace("normalization: 'Identity'", "normalization: 'Other'"),
    expectedCode: 'ClientProgramInvalidInput', sourceReadCount: 0},
]);
