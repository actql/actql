// The common owner's authored Delta fixture is an independent machine control.
// Source cases below supply a typed identity as malformed JSON, intentionally:
// passing Check must not bypass the application's semantic Delta admission.
import {readFile} from 'node:fs/promises';

const json = {type: 'json', nullable: false};
const number = {type: 'number', nullable: false};
const labels = {type: 'array', nullable: false, items: {type: 'string', nullable: false}};
export async function graphDeltaSourceControls(fixtureRoot = new URL('./', import.meta.url)) {
  const {graphDeltaJsonSuccesses} = await import(new URL('graph-delta-json-source.mjs', fixtureRoot));
  const {deltaApplicationScenario} = await import(new URL('property-graph-delta-application.mjs', fixtureRoot));
  const presence = JSON.parse(await readFile(new URL('property-graph-presence.program.json', fixtureRoot), 'utf8'));
  const controls = ['node_rows', 'edge_rows'].map(projection => {
    const {document, expected, fields} = deltaApplicationScenario(presence, projection);
    const contracts = {id: json, src: json, dst: json, labels,
      edge_key: number, tenant_key: {type: 'string', nullable: false}};
    return {name: 'graph-delta-independent-json-' + projection, format: 'json',
      text: JSON.stringify(document), sourceReadCount: 0,
      results: {answer: {rows: expected.map(row => Object.fromEntries(fields.map(name =>
        [name, contracts[name].type === 'json' ? {$json: row[name]} : row[name]]))),
        columns: fields.map(name => ({name, contract: contracts[name]}))}}};
  });
  return [...graphDeltaJsonSuccesses, ...controls];
}
const prefix = 'DATA n = SELECT 1 AS node_key, 7 AS p; DATA g = PROPERTY GRAPH '
  + '(NODE TABLES (n AS N KEY (node_key) LABEL Person PROPERTIES (p))); '
  + 'DATA changes = FROM g |> node_rows() |> SELECT id AS delta; ';
export const graphDeltaSourceExecutionFailures = [
  ['inline-malformed-json', 'FROM g |> apply_graph_delta(with: changes, field: "delta") '
    + '|> node_rows() |> SELECT node_key, p |> RESULT answer'],
  ['quoted-data-before-match-malformed-json', 'DATA `saved changes` = FROM changes; '
    + 'DATA applied = FROM g |> normalize_graph() |> apply_graph_delta(field: "delta", with: `saved changes`); '
    + 'FROM GRAPH applied |> MATCH WALK (a:Person) |> SELECT a.p AS p |> RESULT answer'],
].map(([name, tail]) => ({name: 'graph-delta-' + name, format: 'aql-text',
  text: prefix + tail, resultNames: ['answer'], sourceReadSessionCount: 0}));
export const graphDeltaSourceRefusals = [
  ['unknown-producer', 'apply_graph_delta(with: missing, field: "delta")'],
  ['graph-as-relation', 'apply_graph_delta(with: g, field: "delta")'],
  ['string-producer', 'apply_graph_delta(with: "changes", field: "delta")'],
  ['missing-field', 'apply_graph_delta(with: changes, field: "missing")'],
  ['nonstring-field', 'apply_graph_delta(with: changes, field: 1)'],
  ['extra-argument', 'apply_graph_delta(with: changes, field: "delta", extra: true)'],
  ['missing-argument', 'apply_graph_delta(with: changes)'],
].map(([name, call]) => ({name: 'graph-delta-invalid-' + name, format: 'aql-text',
  text: prefix + 'FROM g |> ' + call + ' |> node_rows() |> SELECT node_key |> RESULT answer'}));
