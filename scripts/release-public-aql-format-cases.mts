// Independent values and ordered contracts; no compiler-generated oracle.
const id = {name: 'id', contract: {type: 'number', nullable: false}};
const common = {sourceReadCount: 0, sourceReadSessionCount: 0};
export const publicAqlFormatCases = Object.freeze({
  successes: Object.freeze([
    {name: 'aql-parameter', format: 'aql', text: 'SELECT @p AS id',
      parameterDeclarations: {p: {type: 'number', nullable: false}}, parameters: {p: 1},
      expected: [{id: 1}], columns: [id], ...common},
    {name: 'aql-with-pipe', format: 'aql',
      text: 'WITH records AS (SELECT 2 AS id UNION ALL SELECT 1 AS id UNION ALL SELECT 2 AS id) FROM records |> WHERE id > 0 |> SELECT id |> ORDER BY id',
      expected: [{id: 1}, {id: 2}, {id: 2}], columns: [id], ...common},
    {name: 'aql-null', format: 'aql', text: 'SELECT CAST(NULL AS FLOAT64) AS id',
      expected: [{id: null}], columns: [{name: 'id', contract: {type: 'number', nullable: true}}], ...common},
    {name: 'aql-json-control', format: 'json', text: JSON.stringify({version: 'actql/0.1',
      id: 'fixture.public_aql_format', stages: [{id: 'main', inputs: {}, steps: [
        {values: {schema: {id: id.contract}, rows: [{id: 1}]}, as: 'rows'},
      ], results: {rows: {from: 'rows', fields: ['id']}}}],
      results: {answer: {from: {stage: 'main', result: 'rows'}}}}),
      expected: [{id: 1}], columns: [id], ...common},
  ]),
  refusals: Object.freeze([
    {name: 'aql-retired-data', format: 'aql', text: 'DATA rows = SELECT 1 AS id; FROM rows |> SELECT id',
      expectedCode: 'ClientProgramInvalidInput'},
    {name: 'aql-undeclared', format: 'aql', text: 'SELECT @missing AS id',
      expectedCode: 'ClientProgramInvalidInput'},
  ]),
});
