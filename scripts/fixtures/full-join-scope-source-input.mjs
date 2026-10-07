// Independent FULL semantics: unmatched sides survive, including nullable data.
const number = {type: 'number', nullable: false};
const nullable = {...number, nullable: true};
const columns = ['amount', 'id', 'rid'].map(name => ({name, contract: nullable}));
const sourceRows = [{id: 3, amount: 30}, {id: 1, amount: null}, {id: 2, amount: 20}];
const expected = [{amount: null, id: 1, rid: null},
  {amount: 20, id: 2, rid: 2}, {amount: null, id: null, rid: 3}];
export const fullJoinScopeProgram = {version: 'actql/0.1', id: 'fixture.full_join_scope',
  stages: [{id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{from: 'remote', filter: {literal: true}}, {select: ['amount', 'id'], as: 'captured'}],
    results: {source: {from: 'captured', fields: ['amount', 'id']}}},
  {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
    steps: [{from: 'records', assert_rows: {unique_by: ['id']}, as: 'keyed'},
      {from: 'keyed', filter: {lte: [{field: 'id'}, {literal: 2}]}, as: 'lefts'},
      {from: 'keyed', filter: {gte: [{field: 'id'}, {literal: 2}]}, as: 'rights'},
      {from: 'lefts', join: {with: 'rights', kind: 'full', on: [{left: 'id', right: 'id'}],
        max_output_rows: 10, select: {amount: 'left.amount', id: 'left.id', rid: 'right.id'}}, as: 'joined'},
      {sort: [{field: 'id', dir: 'asc', nulls: 'last'}, {field: 'rid', dir: 'asc', nulls: 'last'}], as: 'ordered'}],
    results: {rows: {from: 'ordered', fields: ['amount', 'id', 'rid']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const prefix = 'DATA base = FROM records |> ASSERT UNIQUE BY (id); '
  + 'DATA lefts = FROM base |> WHERE id <= 2; DATA rights = FROM base |> WHERE id >= 2; ';
const body = 'SELECT l.*, r.id AS rid FROM lefts AS l FULL JOIN rights AS r '
  + 'ON l.id = r.id MAX_OUTPUT_ROWS 10 ORDER BY id NULLS LAST, rid NULLS LAST';
const success = (name, text, extra = {}) => ({name: 'full-join-scope-' + name,
  format: 'aql-text', text, sourceRows, sourceReadSessionCount: 1, columns, expected, ...extra});
export const fullJoinScopeSuccesses = [
  success('independent-json', JSON.stringify(fullJoinScopeProgram), {format: 'json'}),
  success('qualified-star', prefix + body),
  success('pipe-current-row', prefix + body.replace('SELECT l.*, r.id AS rid FROM lefts AS l FULL JOIN rights AS r ',
    'FROM lefts AS l |> FULL JOIN rights AS r ').replace(' ORDER BY', ' |> SELECT l.*, r.id AS rid |> ORDER BY')),
  success('null-join-keys', prefix + body.replace('ON l.id = r.id', 'ON l.amount = r.amount'), {
    sourceRows: [{id: 3, amount: null}, {id: 1, amount: null}, {id: 2, amount: 20}],
  }),
  success('empty-typed', prefix + body, {sourceRows: [], expected: []}),
];
export const fullJoinScopeRefusals = [
  prefix + body.replace('ON l.id = r.id', 'USING (id)'),
  prefix + body.replace('ON l.id = r.id', 'ON l.id > r.id'),
  prefix + body.replace('MAX_OUTPUT_ROWS 10', 'MAX_OUTPUT_ROWS 0'),
].map((text, index) => ({name: 'full-join-scope-refuse-' + index, format: 'aql-text', text}));
