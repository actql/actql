// Finite F04 cases for the existing public-Client consumer and typed source
// installation. No Catalog/schema override or second execution driver is added.
import assert from 'node:assert/strict';
import {nearestPublicInputFixtures} from './nearest-public-input.mjs';
import {exercisePublicQueryInput} from './public-query-input.mjs';
export async function nearestCarrierPublicFixtures(directory) {
  const baseline = await nearestPublicInputFixtures(directory);
  const kept = baseline.successes.find(item => item.name === 'nearest-source-keep');
  const queryVector = 'qv AS (FROM queries |> to_vectors(id: request_id, vector: embedding))';
  const candidateVector = 'cv AS (FROM candidates |> to_vectors(id: item_id, vector: embedding))';
  const cases = [
    ['relation-relation','queries','candidates',
      'QUERY KEY (q.request_id) VECTOR q.embedding CANDIDATE KEY (c.item_id) VECTOR c.embedding'],
    ['relation-vectors','queries','cv','QUERY KEY (q.request_id) VECTOR q.embedding'],
    ['vectors-relation','qv','candidates','CANDIDATE KEY (c.item_id) VECTOR c.embedding'],
    ['vectors-vectors','qv','cv',''],
    ['vectors-restated','qv','cv',
      'QUERY KEY (qv.request_id) VECTOR qv.embedding CANDIDATE KEY (c.item_id) VECTOR c.embedding'],
  ];
  const successes = cases.flatMap(([name,query,candidate,roles]) => ['sql','aql-text'].map(format => ({
    name:`nearest-carrier-${name}-${format}`,format,
    text:`WITH ${queryVector}, ${candidateVector} FROM ${query === 'queries' ? 'queries AS q' : query}
      |> NEAREST ${candidate} AS c ${roles} METRIC dot K 2
      KEEP (${query === 'queries' ? 'q' : 'qv'}.note, c.label) AS neighbor
      |> ORDER BY neighbor.rank`,
    results:structuredClone(kept.results),
  })));
  const prefix = `WITH ${queryVector}, ${candidateVector} FROM qv |> NEAREST cv AS c `;
  const refusals = [
    ['query-role','QUERY KEY (note) VECTOR embedding METRIC dot K 2 AS neighbor'],
    ['query-component','QUERY KEY (request_id) VECTOR note METRIC dot K 2 AS neighbor'],
    ['candidate-role','CANDIDATE KEY (c.label) VECTOR c.embedding METRIC dot K 2 AS neighbor'],
    ['candidate-component','CANDIDATE KEY (c.item_id) VECTOR c.label METRIC dot K 2 AS neighbor'],
    ['old-output-scope','METRIC dot K 2 AS neighbor |> SELECT qv.note'],
  ].map(([name,tail]) => ({name:`nearest-carrier-refusal-${name}`,format:'aql-text',
    text:prefix+tail,expectedCode:'ClientProgramInvalidInput'}));
  const names = [...successes,...refusals].map(item => item.name);
  assert.equal(names.length,new Set(names).size);
  return {successes,refusals};
}
export async function exerciseNearestCarrierPublicInput(connect,options,{directory,requestPrefix,observe,completedCase}) {
  const fixtures = await nearestCarrierPublicFixtures(directory);
  return exercisePublicQueryInput(connect,options,{...fixtures,requestPrefix,observe,completedCase});
}
