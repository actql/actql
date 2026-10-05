// Independent scalar IN expectations. Grouping does not turn a parameter
// into a JSON object value, nor a signed number into a dynamic list item.
// The common predicate owns NULL equality and duplicate input rows survive.
const rows = [{id: 3, amount: 30}, {id: 1, amount: null},
  {id: -2, amount: -2}, {id: 3, amount: 30}, {id: 2, amount: 20}];
const declarations = {p: {type: 'number'}};
const idColumn = {name: 'id', contract: {type: 'number', nullable: false}};
const flagColumns = [idColumn, ...['included', 'excluded'].map(name => ({name,
  contract: {type: 'boolean', nullable: true}}))];
const selected = [{id: -2}, {id: 3}, {id: 3}];
const flags = [{id: -2, included: true, excluded: false},
  {id: 1, included: null, excluded: null},
  {id: 2, included: null, excluded: null},
  {id: 3, included: true, excluded: false},
  {id: 3, included: true, excluded: false}];
const nullFlags = [{id: -2, included: true, excluded: false},
  {id: 1, included: null, excluded: null},
  {id: 2, included: null, excluded: null},
  {id: 3, included: null, excluded: null},
  {id: 3, included: null, excluded: null}];
// Hand-written machine input: no source compiler output is spliced into it.
const program = {version: 'actql/0.1', id: 'fixture.grouped_in',
  params: declarations,
  stages: [{id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{from: 'remote', filter: {literal: true}},
      {select: ['amount', 'id'], as: 'captured'}],
    results: {source: {from: 'captured', fields: ['amount', 'id']}}},
  {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
    steps: [{from: 'records', filter: {in: [{field: 'id'},
      {literal: [{$param: 'p'}, -2]}]}}, {select: ['id']},
      {sort: [{field: 'id', dir: 'asc', nulls: 'first'}], as: 'ordered'}],
    results: {rows: {from: 'ordered', fields: ['id']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const sql = 'SELECT id FROM records WHERE id IN (((@p)), -((2))) ORDER BY id';
const projection = 'SELECT id, amount IN ((@p), -(2), (NULL)) AS included, '
  + 'amount NOT IN (((@p)), -((2)), NULL) AS excluded FROM records ORDER BY id';
const success = (name, format, text, expected, extra = {}) => ({
  name: 'grouped-in-' + name, format, text, sourceRows: rows, expected,
  columns: [idColumn], sourceReadSessionCount: 1,
  parameterDeclarations: declarations, parameters: {p: 3}, ...extra,
});
export const groupedInSuccesses = [
  success('json-control', 'json', JSON.stringify(program), selected,
    {parameterDeclarations: undefined}),
  success('sql-filter', 'sql', sql, selected),
  success('pipe-filter', 'aql-text',
    'FROM records |> WHERE id IN ((@p), -(2)) |> SELECT id |> ORDER BY id', selected),
  success('not-in-null-filter', 'sql',
    'SELECT id FROM records WHERE id NOT IN ((@p), -(2), (NULL)) ORDER BY id', []),
  success('null-projection', 'sql', projection, flags,
    {columns: flagColumns, parameters: {p: 30}}),
  success('null-parameter', 'sql', projection, nullFlags,
    {columns: flagColumns, parameterDeclarations: {p: {type: 'number', nullable: true}},
      parameters: {p: null}}),
  success('empty', 'sql', sql, [], {sourceRows: []}),
];
export const groupedInRefusals = [
  {name: 'undeclared', text: sql, parameters: {p: 3}},
  {name: 'missing-value', text: sql, parameterDeclarations: declarations},
  {name: 'wrong-type', text: sql, parameterDeclarations: declarations,
    parameters: {p: 'secret-value'}},
  {name: 'dynamic-column', text: 'SELECT id FROM records WHERE id IN ((amount))'},
  {name: 'dynamic-expression', text: 'SELECT id FROM records WHERE id IN ((1 + 2))'},
  {name: 'negative-zero', text: 'SELECT id FROM records WHERE id IN (-(0))'},
].map(item => ({...item, name: 'grouped-in-' + item.name, format: 'sql'}));

// Common membership projections assert all three truth values directly. The
// independent JSON and source forms consume the same admitted source rows.
const truthRows = [{id: 1, amount: null}, {id: 2, amount: 1}, {id: 3, amount: 2}];
const truthExpected = [{id: 1, included: null, excluded: null},
  {id: 2, included: false, excluded: true},
  {id: 3, included: true, excluded: false}];
const emptyExpected = [{id: 1, included: false, excluded: true},
  {id: 2, included: false, excluded: true},
  {id: 3, included: false, excluded: true}];
const unknownExpected = [{id: 1, included: null, excluded: null},
  {id: 2, included: null, excluded: null},
  {id: 3, included: null, excluded: null}];
const emptyColumns = [idColumn, ...['included', 'excluded'].map(name => ({name,
  contract: {type: 'boolean', nullable: false}}))];
const projectProgram = (right, params) => ({
  version: 'actql/0.1', id: 'fixture.common_membership',
  ...(params === undefined ? {} : {params}),
  stages: [{id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{from: 'remote', filter: {literal: true}},
      {select: ['amount', 'id'], as: 'captured'}],
    results: {source: {from: 'captured', fields: ['amount', 'id']}}},
  {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
    steps: [{from: 'records', derive: [
      {included: {in: [{field: 'amount'}, right]}},
      {excluded: {not_in: [{field: 'amount'}, right]}}]},
    {select: ['id', 'included', 'excluded']},
    {sort: [{field: 'id', dir: 'asc', nulls: 'first'}], as: 'ordered'}],
    results: {rows: {from: 'ordered', fields: ['id', 'included', 'excluded']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}},
});
const projectionCase = (name, format, text, expected, extra = {}) =>
  success(name, format, text, expected, {sourceRows: truthRows,
    parameterDeclarations: undefined, parameters: undefined,
    columns: flagColumns, ...extra});
groupedInSuccesses.push(
  projectionCase('truth-json', 'json', JSON.stringify(projectProgram({literal: [2]})), truthExpected),
  projectionCase('truth-sql', 'sql',
    'SELECT id, amount IN (2) AS included, amount NOT IN (2) AS excluded FROM records ORDER BY id', truthExpected),
  projectionCase('truth-pipe', 'aql-text',
    'FROM records |> SELECT id, amount IN (2) AS included, amount NOT IN (2) AS excluded |> ORDER BY id', truthExpected),
  projectionCase('empty-set-json', 'json', JSON.stringify(projectProgram({literal: []})),
    emptyExpected, {columns: emptyColumns}),
);
const arrayDeclaration = {xs: {type: 'array', nullable: true,
  items: {type: 'number', nullable: true}}};
const arrayProgram = JSON.stringify(projectProgram({$param: 'xs'}, arrayDeclaration));
for (const [name, xs, expected] of [
  ['null-array-json', null, emptyExpected], ['empty-array-json', [], emptyExpected],
  ['singleton-null-json', [null], unknownExpected],
]) groupedInSuccesses.push(projectionCase(name, 'json', arrayProgram, expected,
  {parameters: {xs}}));
// Empty-set semantics do not introduce SQL IN (), UNNEST or subqueries.
groupedInRefusals.push({name: 'grouped-in-empty-syntax', format: 'sql',
  text: 'SELECT id FROM records WHERE id IN ()'});

const nullableItemExpected = [{id: 1, included: null, excluded: null},
  {id: 2, included: true, excluded: false},
  {id: 3, included: null, excluded: null}];
groupedInSuccesses.push(
  projectionCase('null-item-truth-json', 'json',
    JSON.stringify(projectProgram({literal: [1, null]})), nullableItemExpected),
  projectionCase('null-item-truth-sql', 'sql',
    'SELECT id, amount IN (1, NULL) AS included, amount NOT IN (1, NULL) AS excluded FROM records ORDER BY id',
    nullableItemExpected),
  projectionCase('null-item-truth-pipe', 'aql-text',
    'FROM records |> SELECT id, amount IN (1, NULL) AS included, amount NOT IN (1, NULL) AS excluded |> ORDER BY id',
    nullableItemExpected),
);
