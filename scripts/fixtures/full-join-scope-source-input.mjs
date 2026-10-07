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
// Written from the common contracts, not generated from frontend output.
// COALESCE merges only the public key; both original keys stay observable.
export const fullUsingScopeProgram = {version: 'actql/0.1', id: 'fixture.full_using_scope',
  stages: [{id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{from: 'remote', filter: {literal: true}}, {select: ['amount', 'id'], as: 'captured'}],
    results: {source: {from: 'captured', fields: ['amount', 'id']}}},
  {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
    steps: [{from: 'records', assert_rows: {unique_by: ['id']}, as: 'keyed'},
      {from: 'keyed', filter: {lte: [{field: 'id'}, {literal: 2}]}, as: 'lefts'},
      {from: 'keyed', filter: {gte: [{field: 'id'}, {literal: 2}]}, as: 'rights'},
      {from: 'lefts', join: {with: 'rights', kind: 'full', on: [{left: 'id', right: 'id'}],
        max_output_rows: 10, select: {lid: 'left.id', rid: 'right.id'}}, as: 'joined'},
      {from: 'joined', derive: {id: {coalesce: [{field: 'lid'}, {field: 'rid'}]}}, as: 'merged'},
      {sort: [{field: 'id', dir: 'asc', nulls: 'last'}], as: 'ordered'}],
    results: {rows: {from: 'ordered', fields: ['id', 'lid', 'rid']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const usingBody = 'FROM lefts AS l FULL JOIN rights AS r USING (id) MAX_OUTPUT_ROWS 10';
const usingColumns = ['id', 'lid', 'rid'].map(name => ({name, contract: nullable}));
const usingExpected = [{id: 1, lid: 1, rid: null}, {id: 2, lid: 2, rid: 2},
  {id: 3, lid: null, rid: 3}];
const using = (name, text, extra = {}) => success('using-' + name, text,
  {columns: usingColumns, expected: usingExpected, ...extra});
export const fullUsingScopeSuccesses = [
  using('independent-json', JSON.stringify(fullUsingScopeProgram), {format: 'json'}),
  using('merged-star', prefix + 'SELECT * EXCEPT (amount), l.id AS lid, r.id AS rid '
    + usingBody + ' ORDER BY id'),
  using('pipe-current-row', prefix + 'FROM lefts AS l |> FULL JOIN rights AS r '
    + 'USING (id) MAX_OUTPUT_ROWS 10 |> SELECT id, l.id AS lid, r.id AS rid |> ORDER BY id'),
  using('alias-order', prefix + 'SELECT -id AS id, l.id AS lid, r.id AS rid '
    + usingBody + ' ORDER BY id', {expected: [
      {id: -3, lid: null, rid: 3}, {id: -2, lid: 2, rid: 2}, {id: -1, lid: 1, rid: null}]}),
  using('qualified-order', prefix + 'SELECT -id AS id, l.id AS lid, r.id AS rid '
    + usingBody + ' ORDER BY l.id NULLS LAST', {expected: [
      {id: -1, lid: 1, rid: null}, {id: -2, lid: 2, rid: 2}, {id: -3, lid: null, rid: 3}]}),
  using('composite-null-keys', prefix + 'SELECT *, l.id AS lid, r.id AS rid '
    + usingBody.replace('USING (id)', 'USING (`AMOUNT`, id)')
    + ' ORDER BY id, lid NULLS LAST', {
      sourceRows: [{id: 3, amount: 30}, {id: 1, amount: 20}, {id: 2, amount: null}],
      columns: ['amount', 'id', 'lid', 'rid'].map(name => ({name, contract: nullable})),
      expected: [{amount: 20, id: 1, lid: 1, rid: null},
        {amount: null, id: 2, lid: 2, rid: null}, {amount: null, id: 2, lid: null, rid: 2},
        {amount: 30, id: 3, lid: null, rid: 3}],
    }),
  using('later-join', prefix + 'SELECT id, l.id AS lid, r.id AS rid ' + usingBody
    + ' JOIN base AS s USING (id) MAX_OUTPUT_ROWS 10 ORDER BY id'),
  using('empty-typed', prefix + 'SELECT id, l.id AS lid, r.id AS rid ' + usingBody
    + ' ORDER BY id', {sourceRows: [], expected: []}),
];
export const fullJoinScopeSuccesses = [
  success('independent-json', JSON.stringify(fullJoinScopeProgram), {format: 'json'}),
  success('qualified-star', prefix + body),
  success('pipe-current-row', prefix + body.replace('SELECT l.*, r.id AS rid FROM lefts AS l FULL JOIN rights AS r ',
    'FROM lefts AS l |> FULL JOIN rights AS r ').replace(' ORDER BY', ' |> SELECT l.*, r.id AS rid |> ORDER BY')),
  success('null-join-keys', prefix + body.replace('ON l.id = r.id', 'ON l.amount = r.amount'), {
    sourceRows: [{id: 3, amount: null}, {id: 1, amount: null}, {id: 2, amount: 20}],
  }),
  success('empty-typed', prefix + body, {sourceRows: [], expected: []}),
  ...fullUsingScopeSuccesses,
];
export const fullJoinScopeRefusals = [
  prefix + body.replace('ON l.id = r.id', 'USING (id, `ID`)'),
  prefix + body.replace('ON l.id = r.id', 'ON l.id > r.id'),
  prefix + body.replace('MAX_OUTPUT_ROWS 10', 'MAX_OUTPUT_ROWS 0'),
].map((text, index) => ({name: 'full-join-scope-refuse-' + index, format: 'aql-text', text}));
