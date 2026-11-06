// Hand-authored take operands, rows and complete column contracts. Neither
// Program expectations nor Result expectations come from compiler output.
const number = {type: 'number', nullable: false};
const nullableNumber = {...number, nullable: true};
const declarations = {count: number, skip: number};
const sourceRows = [{id: 3, amount: 30}, {id: 1, amount: null},
  {id: 2, amount: 20}, {id: 3, amount: 30}, {id: 0, amount: 99}];
const columns = [{name: 'amount', contract: nullableNumber},
  {name: 'id', contract: number}];
const expected = [{amount: 20, id: 2}, {amount: 30, id: 3}];
const sql = 'SELECT amount, id FROM records WHERE id > 0 ORDER BY id LIMIT @count OFFSET @skip';
export const limitParameterProgram = {version: 'actql/0.1',
  id: 'fixture.limit_parameter', params: declarations,
  stages: [{id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{from: 'remote', filter: {gt: [{field: 'id'}, {literal: 0}]}},
      {select: ['amount', 'id'], as: 'captured'}],
    results: {source: {from: 'captured', fields: ['amount', 'id']}}},
  {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
    steps: [{from: 'records', select: ['amount', 'id']},
      {sort: [{field: 'id', dir: 'asc', nulls: 'first'}]},
      {take: {count: {$param: 'count'}, offset: {$param: 'skip'}}, as: 'out'}],
    results: {rows: {from: 'out', fields: ['amount', 'id']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const success = (name, text, extra = {}) => ({name: 'limit-parameter-' + name,
  format: 'sql', text, parameterDeclarations: declarations,
  parameters: {count: 2, skip: 1}, sourceRows, sourceReadSessionCount: 1,
  columns, expected, ...extra});
export const limitParameterSuccesses = [
  success('independent-json', JSON.stringify(limitParameterProgram),
    {format: 'json', parameterDeclarations: undefined}),
  success('sql', sql),
  success('pipe-different-bindings', 'FROM records |> WHERE id > 0 |> SELECT amount, id |> ORDER BY id |> LIMIT @count OFFSET @skip',
    {format: 'aql-text', parameters: {count: 1, skip: 2}, expected: [{amount: 30, id: 3}]}),
  success('zero-offset-null-and-duplicates', sql, {parameters: {count: 4, skip: 0},
    expected: [{amount: null, id: 1}, ...expected, {amount: 30, id: 3}]}),
  success('literal-count', sql.replace('@count', '2'),
    {parameterDeclarations: {skip: number}, parameters: {skip: 1}}),
  success('omitted-offset', sql.replace(' OFFSET @skip', ''),
    {parameterDeclarations: {count: number}, parameters: {count: 1}, expected: [{amount: null, id: 1}]}),
  success('offset-past-end', sql, {parameters: {count: 1, skip: 8}, expected: []}),
  success('typed-empty', sql, {sourceRows: [], expected: []}),
  success('cte-body', 'WITH chosen AS (SELECT amount, id FROM records WHERE id > 0 ORDER BY id LIMIT @count OFFSET @skip) SELECT amount, id FROM chosen ORDER BY id'),
  success('set-final', 'WITH selected AS (SELECT amount, id FROM records WHERE id > 0) '
    + 'SELECT amount, id FROM selected UNION ALL SELECT amount, id FROM selected ORDER BY id LIMIT @count OFFSET @skip',
    {format: 'aql-text', expected: [{amount: null, id: 1}, {amount: 20, id: 2}]}),
  success('join-final', 'WITH selected AS (SELECT amount, id FROM records WHERE id > 0) '
    + ', keys AS (SELECT 1 AS id UNION ALL SELECT 2 AS id UNION ALL SELECT 3 AS id) '
    + 'SELECT l.amount AS amount, l.id AS id FROM selected AS l JOIN keys AS r ON l.id = r.id MAX_OUTPUT_ROWS 10 ORDER BY id LIMIT @count OFFSET @skip',
    {format: 'aql-text'}),
  success('case-insensitive-sql', sql.replace('@count', '@COUNT').replace('@skip', '@Skip')),
  success('quoted-parameter-names', sql.replace('@count', '@`COUNT`').replace('@skip', '@`\\x53kip`')),
  success('exact-declaration-spelling', sql, {parameterDeclarations: {COUNT: number, SKIP: number},
    parameters: {COUNT: 2, SKIP: 1}}),
  success('grouped-sql-bindings', sql.replace('@count', '((@count))').replace('@skip', '(@skip)')),
  success('grouped-pipe-different-bindings', 'FROM records |> WHERE id > 0 |> SELECT amount, id |> ORDER BY id |> LIMIT (@count) OFFSET ((@skip))',
    {format: 'aql-text', parameters: {count: 1, skip: 2}, expected: [{amount: 30, id: 3}]}),
  success('grouped-zero-offset-null-and-duplicates', sql.replace('@count', '(@count)').replace('@skip', '(0)'),
    {parameterDeclarations: {count: number}, parameters: {count: 4},
      expected: [{amount: null, id: 1}, ...expected, {amount: 30, id: 3}]}),
  success('grouped-literal-operands', sql.replace('@count', '((2))').replace('@skip', '(1)'),
    {parameterDeclarations: undefined, parameters: undefined}),
  success('grouped-typed-empty', sql.replace('@count', '((@count))').replace('@skip', '(@skip)'),
    {sourceRows: [], expected: []}),
];
export const limitParameterRefusals = [
  {name: 'undeclared', parameterDeclarations: undefined, parameters: undefined},
  {name: 'missing', parameters: {skip: 1}},
  {name: 'wrong-machine-value-case', parameters: {COUNT: 2, skip: 1}},
  {name: 'ambiguous-source-declarations', parameterDeclarations: {count: number, COUNT: number, skip: number},
    parameters: {count: 2, COUNT: 2, skip: 1}, expectedCode: 'ClientProgramRejected'},
  ...[0, -1, 1.5, null, 9007199254740992, 'private-value'].map((count, index) => ({
    name: 'invalid-count-' + index,
    parameterDeclarations: {count: count === null ? nullableNumber : number, skip: number},
    parameters: {count, skip: 1}})),
  {name: 'negative-offset', parameters: {count: 1, skip: -1}},
  {name: 'nullable-offset', parameterDeclarations: {count: number, skip: nullableNumber},
    parameters: {count: 1, skip: null}},
  {name: 'row-operand', text: sql.replace('@count', 'id')},
  {name: 'grouped-row-operand', text: sql.replace('@count', '(id)'), expectedCode: 'ClientProgramRejected'},
  {name: 'grouped-arithmetic', text: sql.replace('@count', '(@count + 1)'), expectedCode: 'ClientProgramRejected'},
  {name: 'grouped-zero-count', text: sql.replace('@count', '((0))'), expectedCode: 'ClientProgramRejected'},
  {name: 'grouped-overflow', text: sql.replace('@skip', '(9007199254740992)'), expectedCode: 'ClientProgramRejected'},
  {name: 'grouped-null-binding', text: sql.replace('@count', '(@count)'),
    parameterDeclarations: {count: nullableNumber, skip: number}, parameters: {count: null, skip: 1}},
].map(item => ({format: 'sql', text: sql,
  parameterDeclarations: declarations, parameters: {count: 2, skip: 1}, ...item,
  name: 'limit-parameter-refuse-' + item.name}));

// A second LIMIT consumes the first take, not the original sorted JOIN.
const joinDeclarations = {first_count: number, first_skip: number, ...declarations};
const joinParameters = {first_count: 3, first_skip: 1, count: 2, skip: 1};
const joinedExpected = [{amount: 30, id: 3}, {amount: 30, id: 3}];
export const joinLimitTailProgram = {version: 'actql/0.1', id: 'fixture.join_limit_tail',
  params: joinDeclarations,
  stages: [{id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{from: 'remote', filter: {literal: true}},
      {select: ['amount', 'id'], as: 'captured'}],
    results: {source: {from: 'captured', fields: ['amount', 'id']}}},
  {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
    steps: [{values: {schema: {k: number}, rows: [{k: 1}, {k: 2}, {k: 3}]}, as: 'keys'},
      {from: 'records', join: {with: 'keys', kind: 'inner',
        on: [{left: 'id', right: 'k'}], max_output_rows: 10,
        select: {amount: 'left.amount', id: 'left.id'}}, as: 'joined'},
      {sort: [{field: 'id', dir: 'asc', nulls: 'first'}]},
      {take: {count: {$param: 'first_count'}, offset: {$param: 'first_skip'}}},
      {take: {count: {$param: 'count'}, offset: {$param: 'skip'}}, as: 'out'}],
    results: {rows: {from: 'out', fields: ['amount', 'id']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const keys = '(SELECT 1 AS k UNION ALL SELECT 2 AS k UNION ALL SELECT 3 AS k) AS keys';
const joinPrefix = 'FROM records |> JOIN ' + keys
  + ' ON records.id = keys.k MAX_OUTPUT_ROWS 10 |> SELECT amount, id |> ORDER BY id '
  + '|> LIMIT @first_count OFFSET @first_skip';
const joinText = joinPrefix + ' |> LIMIT @count OFFSET @skip';
limitParameterSuccesses.push(...[
  ['join-tail-independent-json', JSON.stringify(joinLimitTailProgram), {format: 'json', parameterDeclarations: undefined}],
  ['join-tail-pipe', joinText, {}],
  ['join-tail-sql-head', 'SELECT records.amount AS amount, records.id AS id FROM records JOIN '
    + keys + ' ON records.id = keys.k MAX_OUTPUT_ROWS 10 ORDER BY id LIMIT @first_count OFFSET @first_skip '
    + '|> LIMIT @count OFFSET @skip', {}],
  ['join-tail-where-projection', joinText + ' |> WHERE id = 3 |> SELECT id, amount |> ORDER BY id',
    {columns: [columns[1], columns[0]], expected: [{id: 3, amount: 30}, {id: 3, amount: 30}]}],
  ['join-tail-empty', joinText, {sourceRows: [], expected: []}],
  ['join-tail-nullable', joinText, {sourceRows: sourceRows.map(row => row.id === 3 ? {...row, amount: null} : row),
    expected: [{amount: null, id: 3}, {amount: null, id: 3}]}],
  ['join-tail-different-operands', joinText, {parameters: {first_count: 4, first_skip: 0, count: 1, skip: 0},
    expected: [{amount: null, id: 1}]}],
].map(([name, text, extra]) => success(name, text,
  {format: 'aql-text', parameterDeclarations: joinDeclarations, parameters: joinParameters,
    expected: joinedExpected, ...extra})));
limitParameterRefusals.push(...[
  ['join-tail-invalid-first-count', joinText, {parameters: {...joinParameters, first_count: 0}}],
  ['join-tail-invalid-second-count', joinText, {parameters: {...joinParameters, count: 0}}],
  ['join-tail-removed-input-range', joinText + ' |> WHERE records.id = 3 |> SELECT id', {}],
].map(([name, text, extra]) => ({name: 'limit-parameter-refuse-' + name,
  format: 'aql-text', text, expectedCode: 'ClientProgramInvalidInput',
  parameterDeclarations: joinDeclarations, parameters: joinParameters, ...extra})));

// Current-row operators precede projection. These controls are authored from
// the operator sequence; filtering before a take has a different result.
const currentRowJoin = 'FROM records |> JOIN ' + keys
  + ' ON records.id = keys.k MAX_OUTPUT_ROWS 10';
const currentRowOrderTake = currentRowJoin
  + ' |> ORDER BY records.id |> LIMIT @count OFFSET @skip';
const selectCurrentRow = ' |> SELECT records.amount AS amount, records.id AS id';
const currentRowProgram = (operations, fields = ['amount', 'id']) => ({
  version: 'actql/0.1', id: 'fixture.join_current_row', params: declarations,
  stages: [{id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{from: 'remote', filter: {literal: true}},
      {select: ['amount', 'id'], as: 'captured'}],
    results: {source: {from: 'captured', fields: ['amount', 'id']}}},
  {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
    steps: [{values: {schema: {k: number}, rows: [{k: 1}, {k: 2}, {k: 3}]}, as: 'keys'},
      {from: 'records', join: {with: 'keys', kind: 'inner',
        on: [{left: 'id', right: 'k'}], max_output_rows: 10,
        select: {amount: 'left.amount', id: 'left.id', k: 'right.k'}}, as: 'joined'},
      ...operations, {select: fields, as: 'out'}],
    results: {rows: {from: 'out', fields}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}});
const currentRowSort = {sort: [{field: 'id', dir: 'asc', nulls: 'first'}]};
const currentRowTake = {take: {count: {$param: 'count'}, offset: {$param: 'skip'}}};
const currentRowFilter = {filter: {eq: [{field: 'k'}, {literal: 3}]}};
export const joinCurrentRowAfterTakeProgram = currentRowProgram([
  currentRowSort, currentRowTake, currentRowFilter]);
export const joinCurrentRowBeforeTakeProgram = currentRowProgram([
  currentRowFilter, currentRowSort, currentRowTake]);
export const joinCurrentRowVisibleProgram = currentRowProgram([
  currentRowSort, currentRowTake], ['amount', 'id', 'k']);
const oneRow = {parameters: {count: 1, skip: 0}};
limitParameterSuccesses.push(...[
  ['join-prefix-after-take-independent-json', JSON.stringify(joinCurrentRowAfterTakeProgram),
    {format: 'json', parameterDeclarations: undefined, ...oneRow, expected: []}],
  ['join-prefix-before-take-independent-json', JSON.stringify(joinCurrentRowBeforeTakeProgram),
    {format: 'json', parameterDeclarations: undefined, ...oneRow, expected: [{amount: 30, id: 3}]}],
  ['join-prefix-order-take', currentRowOrderTake + selectCurrentRow, {}],
  ['join-prefix-visible-independent-json', JSON.stringify(joinCurrentRowVisibleProgram),
    {format: 'json', parameterDeclarations: undefined,
      columns: [...columns, {name: 'k', contract: number}],
      expected: [{amount: 20, id: 2, k: 2}, {amount: 30, id: 3, k: 3}]}],
  ['join-prefix-visible-without-select', currentRowOrderTake,
    {columns: [...columns, {name: 'k', contract: number}],
      expected: [{amount: 20, id: 2, k: 2}, {amount: 30, id: 3, k: 3}]}],
  ['join-prefix-where-after-take', currentRowOrderTake + ' |> WHERE keys.k = 3' + selectCurrentRow,
    {...oneRow, expected: []}],
  ['join-prefix-where-before-take', currentRowJoin + ' |> WHERE keys.k = 3'
    + ' |> ORDER BY records.id |> LIMIT @count OFFSET @skip' + selectCurrentRow,
    {...oneRow, expected: [{amount: 30, id: 3}]}],
  ['join-prefix-consecutive-where', currentRowJoin
    + ' |> WHERE records.id > 0 |> WHERE keys.k = 3' + selectCurrentRow + ' |> ORDER BY id',
    {parameterDeclarations: undefined, parameters: undefined,
      expected: [{amount: 30, id: 3}, {amount: 30, id: 3}]}],
  ['join-prefix-fresh-as', currentRowJoin + ' |> AS `current`'
    + ' |> ORDER BY current.id |> LIMIT @count OFFSET @skip'
    + ' |> SELECT current.amount AS amount, current.id AS id', {}],
  ['join-prefix-quoted-as-nullable', currentRowJoin + ' |> AS `current`'
    + ' |> ORDER BY `current`.id |> LIMIT @count OFFSET @skip'
    + ' |> SELECT `current`.amount AS amount, `current`.id AS id',
    {...oneRow, expected: [{amount: null, id: 1}]}],
  ['join-prefix-typed-empty', currentRowOrderTake + selectCurrentRow,
    {sourceRows: [], expected: []}],
].map(([name, text, extra]) => success(name, text, {format: 'aql-text', ...extra})));
limitParameterRefusals.push(...[
  ['join-prefix-invalid-take', currentRowOrderTake + selectCurrentRow,
    {parameters: {count: 0, skip: 0}}],
  ['join-prefix-as-removed-left', currentRowJoin
    + ' |> AS current |> WHERE records.id = 1 |> SELECT current.id AS id',
    {parameterDeclarations: undefined, parameters: undefined}],
  ['join-prefix-as-removed-right', currentRowJoin
    + ' |> AS current |> ORDER BY keys.k |> SELECT current.id AS id',
    {parameterDeclarations: undefined, parameters: undefined}],
].map(([name, text, extra]) => ({name: 'limit-parameter-refuse-' + name,
  format: 'aql-text', text, expectedCode: 'ClientProgramInvalidInput',
  parameterDeclarations: declarations, parameters: {count: 2, skip: 1}, ...extra})));
