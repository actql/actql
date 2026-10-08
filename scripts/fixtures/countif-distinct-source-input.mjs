// Independent Boolean cardinality obligations. Repeated TRUE observations count
// once in COUNTIF DISTINCT, but remain present for ordinary COUNTIF/SUM/COUNT.
const number = {type: 'number', nullable: false};
const sourceRows = [{id: 0, amount: 99}, {id: 1, amount: 1}, {id: 1, amount: 1},
  {id: 2, amount: 3}, {id: 3, amount: null}, {id: 4, amount: -2}];
const names = ['unique_true', 'every_true', 'observed', 'total'];
const columns = names.map(name => ({name, contract: name === 'total' ? {...number, nullable: true} : number}));
const expected = [{unique_true: 1, every_true: 3, observed: 5, total: 3}];
const predicate = {gt: [{field: 'amount'}, {literal: 0}]};
export const countifDistinctProgram = {version: 'actql/0.1', id: 'fixture.countif_distinct',
  stages: [{id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{from: 'remote', filter: {gt: [{field: 'id'}, {literal: 0}]}},
      {select: ['amount', 'id'], as: 'captured'}],
    results: {source: {from: 'captured', fields: ['amount', 'id']}}},
  {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
    steps: [{from: 'records', group: {by: [], aggregates: {
      unique_true: {fn: 'count', expr: {if: [predicate, {literal: true}, {literal: null}]}, distinct: true},
      every_true: {fn: 'count_if', expr: predicate}, observed: {fn: 'count'}, total: {fn: 'sum', field: 'amount'},
    }}}, {select: names, as: 'counts'}],
    results: {rows: {from: 'counts', fields: names}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const list = 'COUNTIF(DISTINCT amount > 0) AS unique_true, COUNTIF(amount > 0) AS every_true, '
  + 'COUNT(*) AS observed, SUM(amount) AS total';
const sql = `SELECT ${list} FROM records WHERE id > 0`;
const success = (name, text, extra = {}) => ({name: 'countif-distinct-' + name,
  format: 'sql', text, sourceRows, expected, columns, sourceReadSessionCount: 1, ...extra});
export const countifDistinctSuccesses = [
  success('independent-json', JSON.stringify(countifDistinctProgram), {format: 'json'}),
  success('sql-duplicates-and-null', sql),
  success('pipe-duplicates-and-null', `FROM records |> WHERE id > 0 |> AGGREGATE ${list}`, {format: 'aql-text'}),
  success('quoted-functions', 'SELECT `CoUnTiF`(DISTINCT records.amount > 0) AS unique_true, '
    + 'COUNTIF(amount > 0) AS every_true, COUNT(*) AS observed, SUM(amount) AS total FROM records WHERE id > 0'),
  success('per-call-filter', 'SELECT COUNTIF(DISTINCT amount > 0 WHERE id < 2) AS unique_true, '
    + 'COUNTIF(amount > 0) AS every_true, COUNT(*) AS observed, SUM(amount) AS total FROM records WHERE id > 0'),
  success('group-having-order-limit', `SELECT id, ${list} FROM records WHERE id > 0 `
    + 'GROUP BY id HAVING unique_true > 0 ORDER BY id DESC LIMIT 1 OFFSET 1',
    {expected: [{id: 1, unique_true: 1, every_true: 2, observed: 2, total: 2}],
      columns: [{name: 'id', contract: number}, ...columns]}),
  success('no-true', sql, {sourceRows: [{id: 1, amount: 0}, {id: 2, amount: -1}, {id: 2, amount: -1}, {id: 3, amount: null}],
    expected: [{unique_true: 0, every_true: 0, observed: 4, total: -2}]}),
  success('all-null', sql, {sourceRows: [{id: 1, amount: null}],
    expected: [{unique_true: 0, every_true: 0, observed: 1, total: null}]}),
  success('typed-empty', sql, {sourceRows: [], expected: [{unique_true: 0, every_true: 0, observed: 0, total: null}]}),
  success('parameter-preservation', 'SELECT COUNTIF(DISTINCT amount > @threshold) AS unique_true, '
    + 'COUNTIF(amount > 0) AS every_true, COUNT(*) AS observed, SUM(amount) AS total FROM records WHERE id > 0',
    {parameterDeclarations: {threshold: number}, parameters: {threshold: 2}}),
  success('source-free', 'SELECT COUNTIF(DISTINCT TRUE) AS one, COUNTIF(DISTINCT FALSE) AS zero, COUNTIF(DISTINCT NULL) AS none',
    {expected: [{one: 1, zero: 0, none: 0}], columns: ['one', 'zero', 'none'].map(name => ({name, contract: number})),
      sourceReadCount: 0, sourceReadSessionCount: 0}),
  success('filter-demand', 'SELECT COUNTIF(DISTINCT 1 / 0 > 0 WHERE FALSE) AS n',
    {expected: [{n: 0}], columns: [{name: 'n', contract: number}], sourceReadCount: 0, sourceReadSessionCount: 0}),
];
export const countifDistinctRefusals = [
  {text: 'SELECT COUNTIF(DISTINCT *) AS n FROM records'},
  {text: 'SELECT COUNTIF(DISTINCT) AS n FROM records'},
  {text: 'SELECT COUNTIF(DISTINCT amount > 0, id) AS n FROM records'},
  {text: 'SELECT COUNTIF(DISTINCT amount > @missing) AS n FROM records'},
  {text: 'SELECT COUNTIF(DISTINCT amount) AS n FROM records'},
  {text: "SELECT COUNTIF(DISTINCT JSON 'null') AS n FROM records"},
  {text: 'SELECT COUNTIF(DISTINCT missing > 0) AS n FROM records'},
  {text: 'SELECT COUNTIF(DISTINCT amount > 0) OVER () AS n FROM records', expectedCode: 'ClientProgramImplementationLimit'},
].map((item, index) => ({name: 'countif-distinct-refuse-' + index, format: 'sql', ...item}));
