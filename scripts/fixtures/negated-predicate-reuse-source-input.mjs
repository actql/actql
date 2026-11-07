// Independent common Programs and fixed three-valued source expectations.
// IS tests are nonnullable even when their ordinary argument is nullable.
const rows = [{id: 2, amount: 2}, {id: 1, amount: 1}, {id: 3, amount: 2},
  {id: 4, amount: 3}, {id: 5, amount: null}, {id: 0, amount: 99}];
const number = {type: 'number', nullable: false};
const boolean = {type: 'boolean', nullable: false};
const columns = [{name: 'value', contract: boolean}, {name: 'n', contract: number}];
const nonnull = {not: {is_null: {field: 'amount'}}};
const equalTwo = {not: {is_distinct_from: [{field: 'amount'}, {literal: 2}]}};
const declaration = {p: {type: 'number', nullable: true}};
const parameterKey = {not: {is_distinct_from: [{field: 'amount'}, {$param: 'p'}]}};
const program = (key, grouped, params) => ({version: 'actql/0.1', id: 'fixture.negated_predicate_reuse',
  ...(params ? {params} : {}), stages: [
    {id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
      steps: [{from: 'remote', filter: {gt: [{field: 'id'}, {literal: 0}]}},
        {select: ['amount', 'id'], as: 'captured'}],
      results: {source: {from: 'captured', fields: ['amount', 'id']}}},
    {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
      steps: [{from: 'records', derive: {value: key}},
        ...(grouped ? [{group: {by: ['value'], aggregates: {n: {fn: 'count'}}}},
          {select: ['value', 'n']}] : [{select: ['value']}, {distinct: ['value']}]),
        {sort: [{field: 'value', dir: 'asc', nulls: 'first'}], as: 'ordered'}],
      results: {rows: {from: 'ordered', fields: grouped ? ['value', 'n'] : ['value']}}},
  ], results: {answer: {from: {stage: 'main', result: 'rows'}}}});
export const negatedPredicateGroupProgram = program(nonnull, true);
export const negatedPredicateDistinctProgram = program(equalTwo, false);
export const negatedPredicateParameterProgram = program(parameterKey, true, declaration);
const group = (selected, key) => `SELECT ${selected} AS value, COUNT(*) AS n FROM records WHERE id > 0 `
  + `GROUP BY ${key} ORDER BY value`;
const distinct = (selected, key) => `SELECT DISTINCT ${selected} AS value FROM records WHERE id > 0 ORDER BY ${key}`;
const success = (name, text, expected, extra = {}) => ({name: 'negated-predicate-reuse-' + name,
  format: 'aql-text', text, sourceRows: rows, expected, columns, sourceReadSessionCount: 1, ...extra});
const groupedNonnull = [{value: false, n: 1}, {value: true, n: 4}];
const groupedNotTrue = [{value: false, n: 3}, {value: true, n: 2}];
const groupedEqual = [{value: false, n: 3}, {value: true, n: 2}];
const distinctRows = [{value: false}, {value: true}];
const distinctColumns = [columns[0]];
const nullGroup = group('amount IS NOT NULL', 'NOT (records.amount IS NULL)');
const parameterGroup = group('amount IS NOT DISTINCT FROM @p', 'NOT (records.amount IS DISTINCT FROM (@p))');
const prefix = 'WITH pieces AS (SELECT id, amount, IF(amount = 1, NULL, 1) AS other FROM records WHERE id > 0) ';
const collision = ordered => prefix + 'SELECT id, amount IS NOT NULL AS original, other AS amount FROM pieces '
  + `ORDER BY ${ordered}, id`;
const collisionColumns = [{name: 'id', contract: number}, {name: 'original', contract: boolean},
  {name: 'amount', contract: {...number, nullable: true}}];
const collisionRows = [{id: 1, original: true, amount: null},
  {id: 2, original: true, amount: 1}, {id: 3, original: true, amount: 1},
  {id: 4, original: true, amount: 1}, {id: 5, original: false, amount: 1}];
export const negatedPredicateReuseSuccesses = [
  success('group-json-control', JSON.stringify(negatedPredicateGroupProgram), groupedNonnull, {format: 'json'}),
  success('group-null-direct', nullGroup, groupedNonnull),
  success('group-null-explicit', group('NOT (amount IS NULL)', 'records.amount IS NOT NULL'), groupedNonnull),
  success('group-true-direct', group('(amount > 1) IS NOT TRUE', 'NOT ((records.amount > 1) IS TRUE)'), groupedNotTrue),
  success('group-true-explicit', group('NOT ((amount > 1) IS TRUE)', '(records.amount > 1) IS NOT TRUE'), groupedNotTrue),
  success('group-false', group('(amount > 1) IS NOT FALSE', 'NOT ((records.amount > 1) IS FALSE)'), groupedNonnull),
  success('group-unknown', group('NOT ((amount > 1) IS UNKNOWN)', '(records.amount > 1) IS NOT UNKNOWN'), groupedNonnull),
  success('group-distinct-direct', group('amount IS NOT DISTINCT FROM 2', 'NOT (records.amount IS DISTINCT FROM 2)'), groupedEqual),
  success('group-distinct-explicit', group('NOT (amount IS DISTINCT FROM 2)', 'records.amount IS NOT DISTINCT FROM 2'), groupedEqual),
  success('distinct-json-control', JSON.stringify(negatedPredicateDistinctProgram), distinctRows,
    {format: 'json', columns: distinctColumns}),
  success('distinct-direct', distinct('amount IS NOT DISTINCT FROM 2', 'NOT (records.amount IS DISTINCT FROM 2)'),
    distinctRows, {columns: distinctColumns}),
  success('distinct-explicit', distinct('NOT (amount IS DISTINCT FROM 2)', 'records.amount IS NOT DISTINCT FROM 2'),
    distinctRows, {columns: distinctColumns}),
  success('distinct-pipe', 'FROM records |> WHERE id > 0 |> SELECT DISTINCT amount IS NOT NULL AS value '
    + '|> ORDER BY NOT (records.amount IS NULL)', distinctRows, {columns: distinctColumns}),
  success('group-empty', nullGroup, [], {sourceRows: []}),
  success('group-limit-offset', nullGroup + ' LIMIT 1 OFFSET 1', [{value: true, n: 4}]),
  success('output-alias-receiver', collision('NOT (amount IS NULL)'), collisionRows, {columns: collisionColumns}),
  success('qualified-input-receiver', collision('NOT (pieces.amount IS NULL)'),
    [collisionRows[4], ...collisionRows.slice(0, 4)], {columns: collisionColumns}),
  success('parameter-json-control', JSON.stringify(negatedPredicateParameterProgram),
    [{value: false, n: 4}, {value: true, n: 1}], {format: 'json', parameters: {p: null}}),
  success('parameter-source', parameterGroup, [{value: false, n: 4}, {value: true, n: 1}],
    {parameterDeclarations: declaration, parameters: {p: null}}),
];
// DISTINCT cannot recover an unselected input expression. These violate the
// selected-expression scope, rather than selecting an unimplemented ORDER path.
export const negatedPredicateReuseRefusals = [
  ['amount IS NOT NULL', 'amount IS NULL'],
  ['(amount > 1) IS NOT TRUE', 'NOT ((amount > 1) IS FALSE)'],
  ['(amount > 1) IS NOT UNKNOWN', 'NOT ((amount > 2) IS UNKNOWN)'],
  ['amount IS NOT DISTINCT FROM 2', 'NOT (amount IS DISTINCT FROM 1)'],
  ['amount IS NOT DISTINCT FROM 2', 'NOT (amount = 2)'],
  ['amount IS NOT NULL', 'NOT (id IS NULL)'],
  ['amount IS NOT NULL', 'NOT (NOT (amount IS NULL))'],
].map(([selected, ordered], index) => ({name: 'negated-predicate-reuse-unproven-' + index,
  format: 'sql', text: distinct(selected, ordered), expectedCode: 'ClientProgramInvalidInput'}));
negatedPredicateReuseRefusals.push({name: 'negated-predicate-reuse-boolean-input-required',
  format: 'sql', text: distinct('amount IS NOT TRUE', 'NOT (records.amount IS TRUE)'),
  expectedCode: 'ClientProgramInvalidInput'});
