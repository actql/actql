// Independent rows and full schemas from the existing fixed-window and
// aggregate contracts. This module never imports the compiler or evaluator.
const number = {type: 'number', nullable: false};
const nullableNumber = {...number, nullable: true};
const fields = ['window_start', 'window_end', 'cohort', 'n', 'total'];
const columns = fields.map(name => ({name, contract: name === 'cohort'
  ? {type: 'string', nullable: false, max_utf8_bytes: 1}
  : name === 'total' ? nullableNumber : number}));
export const windowGroupSourceRows = [
  {id: 3, amount: 30}, {id: 1, amount: null},
  {id: 2, amount: 20}, {id: 3, amount: 30},
];
const variants = [
  {name: 'field', rows: [
    {window_start: 0, window_end: 60000, cohort: 'a', n: 2, total: 20},
    {window_start: 0, window_end: 60000, cohort: 'b', n: 2, total: 60},
  ]},
  {name: 'expression-filter-distinct', expression: true, rows: [
    {window_start: 0, window_end: 60000, cohort: 'a', n: 2, total: 21},
    {window_start: 0, window_end: 60000, cohort: 'b', n: 2, total: 31},
  ]},
  {name: 'empty', empty: true, rows: []},
];
const raw = 'WITH raw AS (SELECT id, COALESCE(amount,0) AS occurred_ms, '
  + "IF(id <= 2,'a','b') AS cohort, amount FROM records) ";
const window = "row_window(kind:'fixed',time:r.occurred_ms,size:'1m')";
function source(v) {
  return raw + 'FROM raw AS r |> ' + window
    + '|> window_group(by:[r.cohort],aggregates:{n:{fn:\'count\'},total:{fn:\'sum\','
    + (v.expression ? 'expr:COALESCE(r.amount,0)+1,filter:r.amount IS NOT NULL,distinct:true'
      : 'field:r.amount') + '}}) |> SELECT ' + fields.join(',')
    + ' |> ORDER BY window_start,window_end,cohort';
}
function control(v) {
  const aggregates = {n: {fn: 'count'}, total: {fn: 'sum', ...(v.expression
    ? {expr: {add: [{coalesce: [{field: 'amount'}, {literal: 0}]}, {literal: 1}]},
      filter: {not: {is_null: {field: 'amount'}}}, distinct: true}
    : {field: 'amount'})}};
  return {version: 'actql/0.1', id: 'fixture.window_group_' + v.name,
    stages: [
      {id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
        steps: [{from: 'remote', filter: {literal: true}, as: 'scanned'},
          {from: 'scanned', select: ['amount', 'id'], as: 'captured'}],
        results: {source: {from: 'captured', fields: ['amount', 'id']}}},
      {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
        steps: [{from: 'records', derive: {
          occurred_ms: {coalesce: [{field: 'amount'}, {literal: 0}]},
          cohort: {if: [{lte: [{field: 'id'}, {literal: 2}]}, {literal: 'a'}, {literal: 'b'}]},
        }, as: 'raw'},
        {from: 'raw', row_window: {kind: 'fixed', time: 'occurred_ms', size: '1m'}, as: 'windowed'},
        {from: 'windowed', window_group: {by: ['cohort'], aggregates}, as: 'grouped'},
        {from: 'grouped', select: fields},
        {sort: ['window_start', 'window_end', 'cohort'].map(field =>
          ({field, dir: 'asc', nulls: 'first'})), as: 'out'}],
        results: {rows: {from: 'out', fields}}},
    ], results: {answer: {from: {stage: 'main', result: 'rows'}}}};
}
export const windowGroupSourceSuccesses = variants.flatMap(v => {
  const shared = {sourceRows: v.empty ? [] : windowGroupSourceRows,
    sourceReadSessionCount: 1, results: {answer: {rows: v.rows, columns}}};
  return [{name: 'window-group-json-' + v.name, format: 'json',
    text: JSON.stringify(control(v)), ...shared},
  ...['sql', 'aql-text'].map(format => ({name: 'window-group-' + format + '-' + v.name,
    format, text: source(v), ...shared, results: {main: shared.results.answer}}))];
});
const valid = source(variants[0]);
export const windowGroupSourceRefusals = [
  ['missing-window', valid.replace(window + '|> ', '')],
  ['fake-window-fields', valid.replace(window,
    'SELECT id AS window_start,id AS window_end,cohort,amount')],
  ['fn-enum-case', valid.replace("fn:'sum'", "fn:'SUM'")],
  ['literal-field', valid.replace('field:r.amount', "field:'amount'")],
  ['nonboolean-filter', valid.replace('field:r.amount', 'field:r.amount,filter:1')],
  ['unknown-expression', valid.replace('field:r.amount', 'expr:r.missing+1')],
  ['field-and-expression', valid.replace('field:r.amount', 'field:r.amount,expr:r.amount')],
  ['fn-option', valid.replace('field:r.amount', 'field:r.amount,max_items:2')],
  ['unresolved-order', valid.replace("fn:'sum',field:r.amount",
    "fn:'array_agg',field:r.amount,order_by:[{field:r.id,dir:'asc',nulls:'first'}],max_items:4")],
].map(([name, text]) => ({name: 'window-group-' + name, format: 'aql-text', text,
  expectedCode: 'ClientProgramInvalidInput'}));
