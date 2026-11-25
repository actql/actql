// Independently authored Program and expectations, never extracted from
// MoonBit tests, a generated map or a returned Host result.
export const inputOnlyProgram = {
  version: 'actql/0.1', id: 'fixture.identity_stage_result', stages: [
    {id: 'producer', inputs: {}, steps: [{values: {
      schema: {A: {type: 'number', nullable: false}}, rows: [{A: 0}],
    }, as: 'out'}], results: {rows: {from: 'out', fields: ['A']}}},
    {id: 'main', inputs: {source: {result: {stage: 'producer', result: 'rows'}}},
      steps: [], results: {rows: {from: 'source', fields: ['A']}}},
  ], results: {answer: {from: {stage: 'main', result: 'rows'}}},
};
export const runSql = 'SELECT 1 AS n';
export const expectedRows = [{n: 1}];
