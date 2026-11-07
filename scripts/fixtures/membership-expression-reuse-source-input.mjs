// Independent ordinary Programs and three-valued membership results. Literal
// order, duplicates, parameter holes and input scope are retained explicitly.
const rows = [{id: 2, amount: 2}, {id: 1, amount: 1}, {id: 3, amount: 2},
  {id: 4, amount: 3}, {id: 5, amount: null}, {id: 0, amount: 99}];
const number = {type: 'number', nullable: false};
const boolean = {type: 'boolean', nullable: true};
const includedColumn = {name: 'included', contract: boolean};
const groupedColumns = [includedColumn, {name: 'n', contract: number}];
const grouped = [{included: false, n: 1}, {included: true, n: 3}, {included: null, n: 1}];
const unknownGrouped = [{included: true, n: 3}, {included: null, n: 2}];
const distinct = [{included: false}, {included: true}, {included: null}];
const declaration = {p: {type: 'number', nullable: true}};
const program = (operation, items, grouped, params) => ({version: 'actql/0.1',
  id: 'fixture.membership_expression_reuse', ...(params ? {params} : {}),
  stages: [{id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{from: 'remote', filter: {gt: [{field: 'id'}, {literal: 0}]}},
      {select: ['amount', 'id'], as: 'captured'}],
    results: {source: {from: 'captured', fields: ['amount', 'id']}}},
  {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
    steps: [{from: 'records', derive: {included: {[operation]: [{field: 'amount'}, {literal: items}]}}},
      ...(grouped ? [{group: {by: ['included'], aggregates: {n: {fn: 'count'}}}},
        {select: ['included', 'n']}] : [{select: ['included']}, {distinct: ['included']}]),
      {sort: [{field: 'included', dir: 'asc', nulls: 'last'}], as: 'ordered'}],
    results: {rows: {from: 'ordered', fields: grouped ? ['included', 'n'] : ['included']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}});
export const membershipGroupProgram = program('in', [1,2,2], true);
export const membershipDistinctProgram = program('not_in', [1,2,2], false);
export const membershipParameterProgram = program('in', [{$param: 'p'},2,2,null], true, declaration);
const sql = (selected, ordered, grouped = false) => `SELECT ${grouped ? '' : 'DISTINCT '}${selected} AS included`
  + (grouped ? ', COUNT(*) AS n' : '') + ' FROM records WHERE id > 0 '
  + (grouped ? `GROUP BY ${ordered} ORDER BY included NULLS LAST` : `ORDER BY ${ordered} NULLS LAST`);
const success = (name, text, expected, columns = groupedColumns, extra = {}) => ({
  name: 'membership-reuse-' + name, format: 'aql-text', text,
  sourceRows: rows, expected, columns, sourceReadSessionCount: 1, ...extra,
});
const groupSql = sql('amount IN (1,2,2)', 'records.amount IN UNNEST([1,2,2])', true);
const parameterSql = sql('amount IN UNNEST(ARRAY[((@p)),2,2,NULL])',
  'amount IN ((@p),2,2,NULL)', true);
const prefix = 'WITH pieces AS (SELECT id, amount = 2 AS needle, amount = 1 AS other '
  + 'FROM records WHERE id > 0) ';
const collisionSql = ordered => prefix + 'SELECT id, needle IN (TRUE) AS original, other AS needle '
  + `FROM pieces ORDER BY ${ordered} NULLS LAST, id`;
const collisionColumns = [{name: 'id', contract: number},
  {name: 'original', contract: boolean}, {name: 'needle', contract: boolean}];
const collisionRows = [{id: 2, original: true, needle: false},
  {id: 3, original: true, needle: false}, {id: 4, original: false, needle: false},
  {id: 1, original: false, needle: true}, {id: 5, original: null, needle: null}];
export const membershipReuseSuccesses = [
  success('group-json-control', JSON.stringify(membershipGroupProgram), grouped, groupedColumns, {format: 'json'}),
  success('group-list-selected', groupSql, grouped),
  success('group-array-selected', sql('amount IN UNNEST(ARRAY[1,2,2])', 'records.amount IN (1,2,2)', true), grouped),
  success('group-limit-offset', groupSql + ' LIMIT 1 OFFSET 1', [{included: true, n: 3}]),
  success('group-empty', groupSql, [], groupedColumns, {sourceRows: []}),
  success('parameter-json-control', JSON.stringify(membershipParameterProgram), unknownGrouped,
    groupedColumns, {format: 'json', parameters: {p: 1}}),
  success('parameter-source', parameterSql, unknownGrouped, groupedColumns,
    {parameterDeclarations: declaration, parameters: {p: 1}}),
  success('parameter-null', parameterSql, [{included: true, n: 2}, {included: null, n: 3}],
    groupedColumns, {parameterDeclarations: declaration, parameters: {p: null}}),
  success('distinct-json-control', JSON.stringify(membershipDistinctProgram), distinct, [includedColumn], {format: 'json'}),
  success('distinct-list-selected', sql('amount NOT IN (1,2,2)', 'amount NOT IN UNNEST([1,2,2])'), distinct, [includedColumn]),
  success('distinct-array-selected', sql('amount NOT IN UNNEST(ARRAY[1,2,2])', 'records.amount NOT IN (1,2,2)'), distinct, [includedColumn]),
  success('distinct-pipe', 'FROM records |> WHERE id > 0 |> SELECT DISTINCT amount NOT IN (1,2,2) AS included '
    + '|> ORDER BY records.amount NOT IN UNNEST(ARRAY[1,2,2]) NULLS LAST', distinct, [includedColumn]),
  success('output-alias-receiver', collisionSql('needle IN UNNEST([TRUE])'), collisionRows, collisionColumns),
  success('qualified-input-receiver', collisionSql('pieces.needle IN UNNEST([TRUE])'),
    [collisionRows[3], collisionRows[2], collisionRows[0], collisionRows[1], collisionRows[4]], collisionColumns),
];
// The selected DISTINCT predicate cannot restore these different input
// expressions. The existing common lowerer classifies them as InvalidQuery.
export const membershipReuseRefusals = [
  'amount NOT IN UNNEST([1,2])', 'amount IN UNNEST([2,1])',
  'amount IN UNNEST([1,2,2])', 'amount IN UNNEST(ARRAY<FLOAT64>[1,2])',
  'amount IN UNNEST([1,1+1])', 'id IN UNNEST([1,2])',
].map((ordered, i) => ({name: 'membership-reuse-unproven-' + i,
  format: 'sql', text: sql('amount IN (1,2)', ordered),
  expectedCode: 'ClientProgramInvalidInput'}));
membershipReuseRefusals.push(...[
  {name: 'undeclared', parameters: {p: 1}},
  {name: 'missing', parameterDeclarations: declaration},
  {name: 'wrong-type', parameterDeclarations: declaration, parameters: {p: 'wrong-type'}},
].map(item => ({...item, name: 'membership-reuse-parameter-' + item.name,
  format: 'sql', text: parameterSql})));

membershipReuseRefusals.push({name: 'membership-reuse-output-alias-type-mismatch',
  format: 'sql', text: 'SELECT DISTINCT amount IN (1,2) AS amount FROM records '
    + 'ORDER BY amount IN UNNEST([1,2])', expectedCode: 'ClientProgramInvalidInput'});
