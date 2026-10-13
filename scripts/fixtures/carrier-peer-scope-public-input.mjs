// Original F03 counterexamples and independent values, not compiler output.
import {readFile} from 'node:fs/promises';
const originalDirectory = new URL('../../reviews/2026-10-12-frontend-carrier-peer-scope/', import.meta.url);
export const carrierPeerProgramWire = await readFile(new URL('independent.program.json', originalDirectory), 'utf8');
export const carrierPeerOriginalExpectation = JSON.parse(await readFile(new URL('expected.json', originalDirectory), 'utf8'));
const originalSchema = JSON.parse(await readFile(new URL('../../spec/frontend/fixtures/nearest-keep/expected-schema.json', import.meta.url), 'utf8'));
const objectContract = originalSchema.columns[2].contract;
const string = {type: 'string', nullable: false};
const hit = (candidate, score, rank) => ({query_key: {request_id: 'q1'},
  candidate_key: {item_id: candidate}, score, rank});
const pair = {answer: {rows: [{label: 'first', hit: hit('a', 1, 1)},
  {label: 'second', hit: hit('b', 0, 2)}], columns: [
  {name: 'label', contract: string}, {name: 'hit', contract: objectContract}], unordered: true}};
const one = {answer: {...pair.answer, rows: [pair.answer.rows[0]]}};
const shared = {answer: {rows: [{label: 'same', hit: hit('q1', 1, 1)}], columns: [
  {name: 'label', contract: {...string, max_utf8_bytes: 4}},
  {name: 'hit', contract: objectContract}], unordered: true}};
const cosine = {answer: {rows: carrierPeerOriginalExpectation.rows,
  columns: [{name: 'neighbor', contract: objectContract}], unordered: true}};
const prefix = 'WITH v AS (FROM queries |> to_vectors(id: request_id, vector: embedding)), candidate_rows AS (SELECT item_id, embedding, label FROM candidates) ';
const suffix = ' |> NEAREST candidate_rows AS c QUERY KEY (request_id) VECTOR embedding CANDIDATE KEY (c.item_id) VECTOR c.embedding METRIC dot K 2 KEEP (c.label) AS hit';
// Keep these five original texts synchronized with carrier_peer_scope_test,
// including the nested predicate and the once-acquired shared queries input.
const texts = [
  ['flat', prefix + 'FROM v |> vectors()' + suffix, pair, 2],
  ['intermediate-with', prefix.replace('candidate_rows AS', '`rows` AS (FROM v |> vectors()), candidate_rows AS') + 'FROM rows' + suffix, pair, 2],
  ['nested-candidate', prefix + "FROM (WITH candidate_rows AS (SELECT item_id, embedding, label FROM candidates WHERE item_id = 'a') FROM v |> vectors() |> NEAREST candidate_rows AS c QUERY KEY (request_id) VECTOR embedding CANDIDATE KEY (c.item_id) VECTOR c.embedding METRIC dot K 1 KEEP (c.label) AS hit)", one, 2],
  ['shared-query', "WITH v AS (FROM queries |> to_vectors(id: request_id, vector: embedding)), candidate_rows AS (SELECT request_id AS item_id, embedding, 'same' AS label FROM queries) FROM v |> vectors() |> NEAREST candidate_rows AS c QUERY KEY (request_id) VECTOR embedding CANDIDATE KEY (c.item_id) VECTOR c.embedding METRIC dot K 1 KEEP (c.label) AS hit", shared, 1],
  ['cosine', 'WITH v AS (FROM queries |> to_vectors(id: request_id, vector: embedding)), candidate_rows AS (SELECT item_id, embedding FROM candidates) FROM v |> vectors() |> NEAREST candidate_rows AS c QUERY KEY (request_id) VECTOR embedding CANDIDATE KEY (c.item_id) VECTOR c.embedding METRIC cosine K 1 AS neighbor', cosine, 2],
];
export const carrierPeerSuccesses = [
  {name: 'carrier-peer-json-cosine', format: 'json', text: carrierPeerProgramWire,
    results: structuredClone(cosine), sourceReadCount: 0, sourceReadSessionCount: 0},
  ...texts.flatMap(([name, text, results, reads]) => ['sql', 'aql-text'].map(format => ({
    name: `carrier-peer-${name}-${format}`, format, text, results: structuredClone(results),
    sourceReadCount: reads, sourceReadSessionCount: reads,
  }))),
];
const shadow = prefix + 'FROM (WITH candidate_rows AS (SELECT 1 AS unrelated) FROM v |> vectors() |> NEAREST candidate_rows AS c QUERY KEY (request_id) VECTOR embedding CANDIDATE KEY (c.item_id) VECTOR c.embedding METRIC dot K 1 AS hit)';
export const carrierPeerRefusals = ['sql', 'aql-text'].map(format => ({
  name: `carrier-peer-wrong-shadow-${format}`, format, text: shadow,
  expectedCode: 'ClientProgramInvalidInput',
}));
