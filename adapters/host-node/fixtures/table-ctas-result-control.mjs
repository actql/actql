// Independent machine/text controls: the public Result precedes the filter,
// while the whole-Relation Table operation receives the typed empty output.
export const ctasRetainedResult = Object.freeze({
  name: 'before_write', rows: [{id: 1, tag: null}],
  columns: [{name: 'id', contract: {type: 'number', nullable: false}},
    {name: 'tag', contract: {type: 'string', nullable: true}}],
});

export function ctasResultControl(format, {targetRef, mappingRef}) {
  if (!['json', 'sql', 'aql'].includes(format)) throw new Error('Unknown CTAS control format');
  if (format !== 'json') return {
    format,
    document: 'CREATE TABLE analytics.report AS (' +
      'SELECT 1 AS id, CAST(NULL AS STRING) AS tag' +
      ' |> RESULT before_write |> WHERE id = 2)',
  };
  return {format, document: JSON.stringify({version: 'actql/0.1', id: 'ctas-retained-result',
    stages: [{id: 'main', inputs: {}, steps: [
      {values: {schema: {id: {type: 'number', nullable: false},
        tag: {type: 'string', nullable: true}}, rows: [{id: 1, tag: null}]}, as: 'original'},
      {from: 'original', filter: 'id = 2', as: 'filtered'},
    ], results: {before_write: {from: 'original', fields: ['id', 'tag']},
      written: {from: 'filtered', fields: ['id', 'tag']}},
    effects: {save: {store: {target: targetRef, mapping: mappingRef,
      from: {result: 'written'}}}}}],
    results: {before_write: {from: {stage: 'main', result: 'before_write'}}}})};
}
