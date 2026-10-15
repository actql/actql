// Independent real-system input and Result oracle. No compiler/runtime output
// is used to produce the expected values, ordered schema, or source rows.
export const realCrossConnectorControl = Object.freeze({
  name: 'real-duckdb-gcs-joined-table-restart',
  format: 'sql',
  document: `CREATE TABLE analytics.report AS (
 WITH objects AS (
  SELECT name FROM LIST_FILES(docs.files, paths => ['actql-content-test/a.csv'])
 )
 SELECT r.id AS id, f.name AS tag
 FROM records AS r JOIN objects AS f ON r.object_name = f.name
 ORDER BY r.id
 |> RESULT joined
)`,
  duckdbDDL: 'CREATE TABLE records(id DOUBLE NOT NULL, object_name VARCHAR NOT NULL)',
  duckdbRows: Object.freeze([
    Object.freeze([1, 'actql-content-test/a.csv']),
    Object.freeze([2, 'not-selected.csv']),
  ]),
  sourceSchema: Object.freeze({id: Object.freeze({type: 'number', nullable: false}),
    object_name: Object.freeze({type: 'string', nullable: false})}),
  expected: Object.freeze({name: 'joined',
    rows: Object.freeze([Object.freeze({id: 1, tag: 'actql-content-test/a.csv'})]),
    columns: Object.freeze([
      Object.freeze({name: 'id', contract: Object.freeze({type: 'number', nullable: false})}),
      Object.freeze({name: 'tag', contract: Object.freeze({type: 'string', nullable: false})}),
    ]),
  }),
});
