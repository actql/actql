import assert from 'node:assert/strict';

// Install these rows through the ordinary source profile. The Host must
// publish the explicit relation alias "records" in that same generation.
// Expected output is independent of the frontend and its generated Program.
export const sourceRows = [
  {id: 3, amount: 30}, {id: 1, amount: null},
  {id: 2, amount: 20}, {id: 3, amount: 30},
];
const declarations = {minimum: {type: 'number'}};
const relationNumber = (name, nullable = false) => ({name,
  contract: {type: 'number', nullable}});
// Hand-authored tap expectations: each Result retains the Relation at its
// own point, including duplicates, NULLs and declared column order.
// The pinned carrier_schema in query-amount-environment.json declares
// amount before id. Plain FROM retains that order, independently of the
// insertion order of keys in the sourceRows objects above.
const sourceColumns = [relationNumber('amount', true), relationNumber('id')];
// The ordered WITH repro has two roots, append, one hidden sort slot and LIMIT.
// The packed harness reuses main's independently authored JSON control.
export const relationDataSuccesses = [
  {name: 'data-set-order-reuses-hidden-slot', format: 'aql-text',
    text: 'WITH n AS (SELECT 2 AS id UNION ALL SELECT 1 AS other ORDER BY id + 1, id + 1 DESC LIMIT 1) FROM n |> SELECT id |> RESULT nodes',
    results: {nodes: {rows: [{id: 1}], columns: [relationNumber('id')]}}, sourceReadCount: 0},
  {name: 'data-quoted-set-order', format: 'aql-text',
    text: 'WITH `n` AS (SELECT 2 AS id UNION ALL SELECT 1 AS other ORDER BY id) FROM `n` |> SELECT id |> RESULT nodes',
    results: {nodes: {rows: [{id: 1}, {id: 2}], columns: [relationNumber('id')]}}, sourceReadCount: 0},
  {name: 'data-retained-results', format: 'aql-text',
    text: 'WITH n AS (SELECT 2 AS id) FROM n |> RESULT original |> WHERE id > 0 |> RESULT active',
    results: {original: {rows: [{id: 2}], columns: [relationNumber('id')]},
      active: {rows: [{id: 2}], columns: [relationNumber('id')]}}, sourceReadCount: 0},
  {name: 'data-anonymous-set-duplicate-order-limit', format: 'aql-text',
    text: 'WITH n AS (SELECT 2 AS id UNION ALL SELECT 1 + 0 UNION ALL SELECT 1) FROM n |> ORDER BY id |> LIMIT 2 |> RESULT nodes',
    results: {nodes: {rows: [{id: 1}, {id: 1}], columns: [relationNumber('id')]}}, sourceReadCount: 0},
  {name: 'data-anonymous-set-null-json-control', format: 'json',
    text: JSON.stringify({version: 'actql/0.1', id: 'fixture.data_anonymous_null',
      stages: [{id: 'main', inputs: {}, steps: [
        {values: {schema: {id: {type: 'number', nullable: true}}, rows: [{id: 2}, {id: null}]}, as: 'rows'},
        {from: 'rows', sort: [{field: 'id', dir: 'asc', nulls: 'first'}], as: 'sorted'},
      ], results: {nodes: {from: 'sorted', fields: ['id']}}}],
      results: {nodes: {from: {stage: 'main', result: 'nodes'}}}}),
    results: {nodes: {rows: [{id: null}, {id: 2}], columns: [relationNumber('id', true)]}}, sourceReadCount: 0},
  {name: 'data-anonymous-set-null-source', format: 'aql-text',
    text: 'WITH n AS (SELECT 2 AS id UNION ALL SELECT CAST(NULL AS FLOAT64)) FROM n |> ORDER BY id NULLS FIRST |> RESULT nodes',
    results: {nodes: {rows: [{id: null}, {id: 2}], columns: [relationNumber('id', true)]}}, sourceReadCount: 0},
  {name: 'data-anonymous-set-cte-source', format: 'aql-text',
    text: 'WITH n AS (WITH seed AS (SELECT 2 AS id) SELECT id FROM seed UNION ALL SELECT id - 1 FROM seed) FROM n |> ORDER BY id |> RESULT nodes',
    results: {nodes: {rows: [{id: 1}, {id: 2}], columns: [relationNumber('id')]}}, sourceReadCount: 0},
];
export const relationDataRefusals = [
  {name: 'data-forward-reference', format: 'aql-text', text: 'WITH n AS (FROM later |> SELECT id), later AS (SELECT 1 AS id) FROM n |> SELECT id'},
  {name: 'data-duplicate', format: 'aql-text', text: 'WITH n AS (SELECT 1 AS id), `N` AS (SELECT 2 AS id) FROM n |> SELECT id'},
  {name: 'data-sql-format', format: 'sql', text: 'DATA n = SELECT 1 AS id; FROM n |> SELECT id'},
  {name: 'data-anonymous-set-by-name', format: 'aql-text', expectedCode: 'ClientProgramImplementationLimit', text: 'WITH n AS (SELECT 1 AS id UNION ALL BY NAME SELECT 2) FROM n |> SELECT id'},
  {name: 'data-anonymous-set-private-field', format: 'aql-text', expectedCode: 'ClientProgramInvalidInput', text: 'WITH n AS (SELECT 1 AS id UNION ALL SELECT 2) FROM n |> WHERE aql_set_anonymous_0 > 0 |> SELECT id'},
];
export const pipeResultSuccesses = [
  {name: 'result-exact-string-prefix', format: 'sql',
    text: "SELECT r'\\n' 'e\\u0301' AS value |> RESULT original |> SET value = '\\r\\néx' |> RESULT updated",
    results: {
      original: {rows: [{value: '\\ne\u0301'}], columns: [{name: 'value',
        contract: {type: 'string', nullable: false, max_utf8_bytes: 5}}]},
      updated: {rows: [{value: '\r\néx'}], columns: [{name: 'value',
        contract: {type: 'string', nullable: false, max_utf8_bytes: 5}}]},
    }, sourceReadCount: 0},
  {name: 'result-cte-exact-string-octal', format: 'aql-text',
    text: "WITH base AS (SELECT id, r'\\n' 'e\\u0301' AS label FROM records) FROM base |> ORDER BY id |> RESULT original |> WHERE id = 1 |> SET label = '\\377' |> RESULT selected",
    results: {
      original: {rows: [{id: 1, label: '\\ne\u0301'}, {id: 2, label: '\\ne\u0301'},
        {id: 3, label: '\\ne\u0301'}, {id: 3, label: '\\ne\u0301'}],
        columns: [relationNumber('id'), {name: 'label',
          contract: {type: 'string', nullable: false, max_utf8_bytes: 5}}]},
      selected: {rows: [{id: 1, label: '\u00ff'}],
        columns: [relationNumber('id'), {name: 'label',
          contract: {type: 'string', nullable: false, max_utf8_bytes: 2}}]},
    }, sourceReadSessionCount: 1},
  {name: 'result-before-count', format: 'aql-text',
    text: 'FROM records |> RESULT original |> AGGREGATE COUNT(*) AS n |> RESULT summary',
    results: {
      original: {rows: sourceRows, columns: sourceColumns, unordered: true},
      summary: {rows: [{n: 4}], columns: [relationNumber('n')]},
    }, sourceReadSessionCount: 1},
  {name: 'result-before-grouped-count', format: 'aql-text',
    text: 'FROM records |> RESULT original |> AGGREGATE COUNT(*) AS n GROUP BY amount |> ORDER BY amount |> RESULT summary',
    results: {
      original: {rows: sourceRows, columns: sourceColumns, unordered: true},
      summary: {rows: [{amount: null, n: 1}, {amount: 20, n: 1}, {amount: 30, n: 2}],
        columns: [relationNumber('amount', true), relationNumber('n')]},
    }, sourceReadSessionCount: 1},
  {name: 'result-empty-before-count', format: 'aql-text',
    text: 'FROM records |> RESULT original |> AGGREGATE COUNT(*) AS n |> RESULT summary',
    sourceRows: [],
    results: {
      original: {rows: [], columns: sourceColumns},
      summary: {rows: [{n: 0}], columns: [relationNumber('n')]},
    }, sourceReadSessionCount: 1},
  {name: 'result-before-distinct', format: 'aql-text',
    text: 'FROM records |> RESULT original |> SELECT DISTINCT amount |> ORDER BY amount |> RESULT unique_amounts',
    results: {
      original: {rows: sourceRows, columns: sourceColumns, unordered: true},
      unique_amounts: {rows: [{amount: null}, {amount: 20}, {amount: 30}],
        columns: [relationNumber('amount', true)]},
    }, sourceReadSessionCount: 1},
  {name: 'result-before-limit', format: 'aql-text',
    text: 'FROM records |> ORDER BY id |> RESULT original |> LIMIT 1',
    results: {
      original: {rows: [{id: 1, amount: null}, {id: 2, amount: 20}, {id: 3, amount: 30}, {id: 3, amount: 30}], columns: sourceColumns},
      answer: {rows: [{id: 1, amount: null}], columns: sourceColumns},
    }, sourceReadSessionCount: 1},
  {name: 'terminal-result', format: 'sql',
    text: 'SELECT amount, id FROM records ORDER BY id |> RESULT complete',
    results: {complete: {rows: [{amount: null, id: 1}, {amount: 20, id: 2}, {amount: 30, id: 3}, {amount: 30, id: 3}],
      columns: [relationNumber('amount', true), relationNumber('id')]}}, sourceReadSessionCount: 1},
  {name: 'result-before-filter', format: 'aql-text',
    text: 'FROM records |> ORDER BY id |> RESULT original |> WHERE amount IS NOT NULL |> SELECT id |> RESULT active',
    results: {
      original: {rows: [{id: 1, amount: null}, {id: 2, amount: 20}, {id: 3, amount: 30}, {id: 3, amount: 30}], columns: sourceColumns},
      active: {rows: [{id: 2}, {id: 3}, {id: 3}], columns: [relationNumber('id')]},
    }, sourceReadSessionCount: 1},
  {name: 'result-after-set', format: 'aql-text',
    text: 'FROM records AS old |> SET id = id + 10 |> RESULT changed |> SELECT old.id AS original, id AS `current` |> ORDER BY original |> RESULT final',
    results: {
      changed: {rows: [{id: 13, amount: 30}, {id: 11, amount: null}, {id: 12, amount: 20}, {id: 13, amount: 30}], columns: sourceColumns, unordered: true},
      final: {rows: [{original: 1, current: 11}, {original: 2, current: 12}, {original: 3, current: 13}, {original: 3, current: 13}], columns: [relationNumber('original'), relationNumber('current')]},
    }, sourceReadSessionCount: 1},
  {name: 'result-after-drop', format: 'aql-text',
    text: 'FROM records AS old |> DROP amount |> RESULT ids |> SELECT old.amount AS previous, id |> ORDER BY id |> RESULT final',
    results: {
      ids: {rows: [{id: 3}, {id: 1}, {id: 2}, {id: 3}], columns: [relationNumber('id')], unordered: true},
      final: {rows: [{previous: null, id: 1}, {previous: 20, id: 2}, {previous: 30, id: 3}, {previous: 30, id: 3}], columns: [relationNumber('previous', true), relationNumber('id')]},
    }, sourceReadSessionCount: 1},
  {name: 'result-cte', format: 'aql-text',
    text: 'WITH base AS (SELECT amount, id FROM records ORDER BY id) FROM base |> RESULT original |> WHERE id = 1 |> RESULT selected',
    results: {
      original: {rows: [{amount: null, id: 1}, {amount: 20, id: 2}, {amount: 30, id: 3}, {amount: 30, id: 3}], columns: [relationNumber('amount', true), relationNumber('id')]},
      selected: {rows: [{amount: null, id: 1}], columns: [relationNumber('amount', true), relationNumber('id')]},
    }, sourceReadSessionCount: 1},
  {name: 'result-cte-join', format: 'sql',
    text: 'WITH base AS (SELECT id FROM records) SELECT l.id AS id FROM base l JOIN base r ON l.id = r.id ORDER BY id |> RESULT joined |> LIMIT 1 |> RESULT limited',
    results: {
      joined: {rows: [{id: 1}, {id: 2}, {id: 3}, {id: 3}, {id: 3}, {id: 3}], columns: [relationNumber('id')]},
      limited: {rows: [{id: 1}], columns: [relationNumber('id')]},
    }, sourceReadSessionCount: 1},
  {name: 'result-empty', format: 'sql',
    text: 'SELECT amount, id FROM records WHERE amount > 100 |> RESULT empty |> LIMIT 1 |> RESULT final',
    results: {empty: {rows: [], columns: [relationNumber('amount', true), relationNumber('id')]},
      final: {rows: [], columns: [relationNumber('amount', true), relationNumber('id')]}}, sourceReadSessionCount: 1},
  {name: 'result-source-free', format: 'sql',
    text: 'SELECT 2 AS x |> RESULT original |> SET x = x + 1 |> RESULT updated',
    results: {original: {rows: [{x: 2}], columns: [relationNumber('x')]},
      updated: {rows: [{x: 3}], columns: [relationNumber('x')]}}, sourceReadCount: 0},
];
export const pipeResultRefusals = [
  {name: 'result-octal-out-of-range', format: 'sql',
    text: "SELECT '\\400' AS value |> RESULT original"},
  {name: 'result-duplicate', format: 'aql-text', text: 'FROM records |> RESULT saved |> RESULT saved'},
  {name: 'result-case-duplicate', format: 'aql-text', text: 'FROM records |> RESULT Saved |> RESULT `SAVED`'},
  {name: 'result-primary-collision', format: 'aql-text', text: 'FROM records |> RESULT answer |> LIMIT 1'},
  {name: 'result-cte-body', format: 'sql', text: 'WITH base AS (FROM records |> RESULT saved) SELECT id FROM base'},
  {name: 'result-derived-body', format: 'sql', text: 'SELECT id FROM (FROM records |> RESULT saved) AS base'},
  {name: 'result-missing-name', format: 'aql-text', text: 'FROM records |> RESULT'},
  {name: 'result-removed-range', format: 'aql-text', text: 'FROM records AS old |> AS current |> RESULT saved |> SELECT old.id'},
];
// The retained prefix is only a candidate until the ordinary Run owner
// commits publication. A downstream expression failure must not expose it.
export const pipeResultExecutionFailures = [
  {name: 'result-before-division-failure', format: 'aql-text',
    text: 'FROM records |> RESULT original |> SET id = id / (id - id) |> RESULT invalid',
    resultNames: ['original', 'invalid'], sourceReadSessionCount: 1},
];
export const queryCompositionSuccesses = [
  ...['sql', 'aql-text'].map(format => ({
    name: `cte-join-right-shared-capture-${format}`, format,
    text: 'WITH chosen AS (SELECT id FROM records WHERE id = 1), pairs AS (SELECT r.id AS id FROM chosen AS l CROSS JOIN records AS r) SELECT id FROM pairs ORDER BY id',
    sourceRows: [{id: 1, amount: null}, {id: 2, amount: 20}],
    expected: [{id: 1}, {id: 2}], columns: [relationNumber('id')],
    sourceReadSessionCount: 1,
  })),
  {name: 'cte-outer-join-right-shared-capture', format: 'sql',
    text: 'WITH chosen AS (SELECT id FROM records WHERE id = 1) SELECT r.id AS id FROM chosen AS l CROSS JOIN records AS r ORDER BY id',
    sourceRows: [{id: 1, amount: null}, {id: 2, amount: 20}],
    expected: [{id: 1}, {id: 2}], columns: [relationNumber('id')],
    sourceReadSessionCount: 1},
  {name: 'cte-join-right-shadows-outer-capture', format: 'sql',
    text: 'WITH chosen AS (SELECT id FROM records WHERE id = 1), records AS (SELECT id FROM chosen), pairs AS (SELECT r.id AS id FROM chosen AS l CROSS JOIN records AS r) SELECT id FROM pairs ORDER BY id',
    sourceRows: [{id: 1, amount: null}, {id: 2, amount: 20}],
    expected: [{id: 1}], columns: [relationNumber('id')],
    sourceReadSessionCount: 1},
  {name: 'derived-exact-string-chunks', format: 'sql',
    text: "SELECT value FROM (SELECT r'\\n' 'e\\u0301' AS value) AS chosen",
    expected: [{value: '\\ne\u0301'}],
    columns: [{name: 'value', contract: {type: 'string', nullable: false,
      max_utf8_bytes: 5}}], sourceReadCount: 0},
  {name: 'captured-cte-set-exact-string-chunks', format: 'sql',
    text: "WITH chosen AS (SELECT r'\\n' 'e\\u0301' AS label FROM records WHERE id = 1) SELECT label FROM chosen UNION ALL SELECT '\\r\\néx' AS other FROM chosen ORDER BY label",
    expected: [{label: '\r\néx'}, {label: '\\ne\u0301'}],
    columns: [{name: 'label', contract: {type: 'string', nullable: false,
      max_utf8_bytes: 5}}], sourceReadSessionCount: 1},
  {name: 'set-output-alias-expression', format: 'sql',
    text: 'SELECT id AS amount FROM records UNION ALL SELECT id AS other FROM records ORDER BY 0 - amount, 0 - amount DESC LIMIT 3',
    expected: [{amount: 3}, {amount: 3}, {amount: 3}], columns: [relationNumber('amount')], sourceReadSessionCount: 1},
  {name: 'set-output-expression-null', format: 'sql',
    text: 'SELECT amount, id FROM records UNION DISTINCT SELECT amount, id FROM records ORDER BY COALESCE(amount, 0) + 1 DESC, id',
    expected: [{amount: 30, id: 3}, {amount: 20, id: 2}, {amount: null, id: 1}],
    columns: [relationNumber('amount', true), relationNumber('id')], sourceReadSessionCount: 1},
  {name: 'cte-set-output-expression', format: 'sql',
    text: 'WITH chosen AS (SELECT id FROM records WHERE amount >= 20 UNION ALL SELECT id FROM records WHERE amount IS NULL ORDER BY 0 - id LIMIT 2) SELECT id FROM chosen ORDER BY id',
    expected: [{id: 3}, {id: 3}], columns: [relationNumber('id')], sourceReadSessionCount: 1},
  {name: 'empty-set-output-expression', format: 'sql',
    text: 'SELECT id FROM records WHERE amount > 100 UNION ALL SELECT id FROM records WHERE amount < 0 ORDER BY id + 1',
    expected: [], columns: [relationNumber('id')], sourceReadSessionCount: 1},

  {name: 'quoted-cte-case', format: 'sql',
    text: 'WITH `Chosen` AS (SELECT id FROM records WHERE amount IS NULL) SELECT chosen.id FROM chosen ORDER BY id',
    expected: [{id: 1}], columns: [relationNumber('id')], sourceReadSessionCount: 1},
  {name: 'nested-with-quoted-case', format: 'sql',
    text: 'WITH chosen AS (WITH `Hidden` AS (SELECT id FROM records WHERE amount IS NULL) SELECT hidden.id FROM hidden) SELECT id FROM chosen ORDER BY id',
    expected: [{id: 1}], columns: [relationNumber('id')], sourceReadSessionCount: 1},
  {name: 'nested-with-shadow', format: 'sql',
    text: 'WITH base AS (SELECT id, amount FROM records), chosen AS (WITH base AS (SELECT id FROM base WHERE amount >= 20) SELECT base.id FROM base) SELECT id FROM chosen UNION ALL SELECT id FROM base WHERE amount IS NULL ORDER BY id',
    expected: [{id: 1}, {id: 2}, {id: 3}, {id: 3}], columns: [relationNumber('id')], sourceReadSessionCount: 1},
  {name: 'nested-with-quoted-range', format: 'sql',
    text: 'SELECT chosen.id FROM (WITH `Hidden` AS (SELECT id FROM records WHERE amount IS NULL) SELECT `Hidden`.id FROM `Hidden`) AS chosen ORDER BY id',
    expected: [{id: 1}], columns: [relationNumber('id')], sourceReadSessionCount: 1},
  {name: 'nested-with-pipe-range', format: 'aql-text',
    text: 'WITH chosen AS (WITH hidden AS (FROM records |> WHERE amount >= 20 |> SELECT id) FROM hidden |> SELECT hidden.id AS id) FROM chosen |> SELECT id |> ORDER BY id',
    expected: [{id: 2}, {id: 3}, {id: 3}], columns: [relationNumber('id')], sourceReadSessionCount: 1},
  {name: 'derived-pipe', format: 'sql',
    text: 'SELECT id FROM (FROM records |> WHERE amount >= @minimum |> SELECT id) AS chosen ORDER BY id',
    parameterDeclarations: declarations, parameters: {minimum: 20},
    expected: [{id: 2}, {id: 3}, {id: 3}], columns: [relationNumber('id')], sourceReadSessionCount: 1},
  {name: 'derived-select-pipe', format: 'sql',
    text: 'SELECT id FROM (SELECT id FROM records |> WHERE id > 1) AS chosen ORDER BY id',
    expected: [{id: 2}, {id: 3}, {id: 3}], columns: [relationNumber('id')], sourceReadSessionCount: 1},
  {name: 'derived-outer-pipe', format: 'aql-text',
    text: 'FROM (FROM records |> WHERE amount >= 20 |> SELECT id) AS chosen |> SELECT chosen.id AS id |> ORDER BY id',
    expected: [{id: 2}, {id: 3}, {id: 3}], columns: [relationNumber('id')], sourceReadSessionCount: 1},
  {name: 'derived-null', format: 'sql',
    text: 'SELECT amount, id FROM (FROM records |> WHERE amount IS NULL |> SELECT id, amount) AS chosen ORDER BY id',
    expected: [{amount: null, id: 1}], columns: [relationNumber('amount', true), relationNumber('id')], sourceReadSessionCount: 1},
  {name: 'derived-empty', format: 'sql',
    text: 'SELECT amount, id FROM (FROM records |> WHERE amount > 100 |> SELECT id, amount) AS chosen ORDER BY id',
    expected: [], columns: [relationNumber('amount', true), relationNumber('id')], sourceReadSessionCount: 1},
  {name: 'cte-query-order-limit', format: 'sql',
    text: 'WITH chosen AS (SELECT id, amount FROM records ORDER BY id LIMIT 1) SELECT amount, id FROM chosen ORDER BY id',
    expected: [{amount: null, id: 1}], columns: [relationNumber('amount', true), relationNumber('id')], sourceReadSessionCount: 1},
  {name: 'parenthesized-query', format: 'sql',
    text: '(SELECT id FROM records WHERE amount >= 20) |> WHERE id > 1 |> SELECT id |> ORDER BY id',
    expected: [{id: 2}, {id: 3}, {id: 3}], columns: [relationNumber('id')], sourceReadSessionCount: 1},
  {name: 'cte-set-differing-predicates', format: 'sql',
    text: 'WITH chosen AS (SELECT id FROM records WHERE amount >= 20 UNION ALL SELECT id FROM records WHERE amount IS NULL) SELECT id FROM chosen ORDER BY id',
    expected: [{id: 1}, {id: 2}, {id: 3}, {id: 3}], columns: [relationNumber('id')], sourceReadSessionCount: 1},
  {name: 'pipe-after-set', format: 'sql',
    text: 'SELECT id FROM records UNION ALL SELECT id FROM records |> WHERE id > 1 |> SELECT id |> ORDER BY id',
    expected: [{id: 2}, {id: 2}, {id: 3}, {id: 3}, {id: 3}, {id: 3}], columns: [relationNumber('id')], sourceReadSessionCount: 1},
  {name: 'set-reuses-cte', format: 'sql',
    text: 'WITH chosen AS (SELECT id FROM records WHERE amount >= 20) SELECT id FROM chosen UNION ALL SELECT id FROM chosen ORDER BY id',
    expected: [{id: 2}, {id: 2}, {id: 3}, {id: 3}, {id: 3}, {id: 3}], columns: [relationNumber('id')], sourceReadSessionCount: 1},
  {name: 'parenthesized-set-operand', format: 'sql',
    text: 'SELECT id FROM records WHERE amount IS NULL UNION ALL (SELECT id FROM records WHERE amount >= 20 ORDER BY id LIMIT 1) ORDER BY id',
    expected: [{id: 1}, {id: 2}], columns: [relationNumber('id')], sourceReadSessionCount: 1},
  {name: 'nested-set-operand', format: 'sql',
    text: 'SELECT id FROM records WHERE amount IS NULL UNION ALL (SELECT id FROM records WHERE amount >= 20 INTERSECT DISTINCT SELECT id FROM records WHERE amount >= 20) ORDER BY id',
    expected: [{id: 1}, {id: 2}, {id: 3}], columns: [relationNumber('id')], sourceReadSessionCount: 1},
  {name: 'pipe-set-operand', format: 'aql-text',
    text: 'FROM records |> SELECT id |> UNION ALL (FROM records |> WHERE amount IS NULL |> SELECT id) |> WHERE id = 1 |> SELECT id |> ORDER BY id',
    expected: [{id: 1}, {id: 1}], columns: [relationNumber('id')], sourceReadSessionCount: 1},
  {name: 'derived-set', format: 'sql',
    text: 'SELECT amount, id FROM (SELECT id, amount FROM records WHERE amount IS NULL UNION ALL SELECT id, amount FROM records WHERE amount IS NULL) AS chosen ORDER BY id',
    expected: [{amount: null, id: 1}, {amount: null, id: 1}], columns: [relationNumber('amount', true), relationNumber('id')], sourceReadSessionCount: 1},
  {name: 'empty-set', format: 'sql',
    text: '(SELECT id, amount FROM records WHERE amount > 100 UNION ALL SELECT id, amount FROM records WHERE amount < 0) |> SELECT amount, id |> ORDER BY id',
    expected: [], columns: [relationNumber('amount', true), relationNumber('id')], sourceReadSessionCount: 1},

];
// Independently authored unaliased table-query controls. Source aliases remain
// optional syntax; current columns, row scopes and explicit result order do not.
const optionalNumber = (name,nullable=false) => ({name,contract:{type:'number',nullable}});
const optionalCase = (name,text,expected,columns,extra={}) => ({name:'derived-optional-'+name,
 format:'sql',text,expected,columns,sourceReadCount:0,sourceReadSessionCount:0,...extra});
const optionalNullProgram={"version":"actql/0.1","id":"fixture.optional_derived_alias","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":true}},"rows":[{"id":1},{"id":null},{"id":2},{"id":1}]},"as":"rows"},{"from":"rows","filter":{"not":{"is_null":{"field":"id"}}}},{"sort":[{"field":"id","dir":"desc","nulls":"first"}]},{"take":3},{"select":["id"],"as":"out"}],"results":{"rows":{"from":"out","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}};
const optionalRangeHead="FROM (SELECT 1 AS x,20 AS y UNION ALL SELECT 2,10) base |> AS r |> SET x=x+10";
queryCompositionSuccesses.push(
 optionalCase('range-snapshot-json-control',JSON.stringify({"version":"actql/0.1","id":"fixture.optional_range_snapshot","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":1,"y":20},{"x":2,"y":10}]},"as":"rows"},{"from":"rows","derive":{"current":{"add":[{"field":"x"},{"literal":10}]}}},{"select":[{"original":"x"},"current","y"]},{"sort":[{"field":"original","dir":"asc","nulls":"first"}],"as":"out"}],"results":{"rows":{"from":"out","fields":["original","current","y"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}),[{original:1,current:11,y:20},{original:2,current:12,y:10}],[optionalNumber('original'),optionalNumber('current'),optionalNumber('y')],{format:'json'}),
 optionalCase('null-duplicate-json-control',JSON.stringify(optionalNullProgram),
  [{id:2},{id:1},{id:1}],[optionalNumber('id',true)],{format:'json'}),
 optionalCase('null-duplicate-set-source',"SELECT id FROM (SELECT 1 AS id UNION ALL SELECT CAST(NULL AS FLOAT64) UNION ALL SELECT 2 UNION ALL SELECT 1) WHERE id IS NOT NULL ORDER BY id DESC NULLS FIRST LIMIT 3",
  [{id:2},{id:1},{id:1}],[optionalNumber('id',true)]),
 optionalCase('identity-star',"SELECT * FROM (SELECT 1 AS id,'x' AS label)",[{id:1,label:'x'}],
  [optionalNumber('id'),{name:'label',contract:{type:'string',nullable:false,max_utf8_bytes:1}}]),
 optionalCase('range-snapshot',"SELECT r.x AS original,x AS `current`,y FROM ("+optionalRangeHead+") ORDER BY original",
  [{original:1,current:11,y:20},{original:2,current:12,y:10}],
  [optionalNumber('original'),optionalNumber('current'),optionalNumber('y')]),
 optionalCase('range-through-parentheses',"SELECT r.x AS original FROM ((FROM (SELECT 1 AS x UNION ALL SELECT 2) base |> AS r)) ORDER BY original",
  [{original:1},{original:2}],[optionalNumber('original')]),
 optionalCase('explicit-alias-replaces-ranges',"SELECT chosen.x AS `current`,chosen.y FROM ("+optionalRangeHead+") chosen ORDER BY current",
  [{current:11,y:20},{current:12,y:10}],[optionalNumber('current'),optionalNumber('y')]),
 optionalCase('scalar-value-table',"SELECT element AS value FROM (FROM UNNEST([1,CAST(NULL AS FLOAT64),2,1]) AS element) ORDER BY value DESC NULLS FIRST",
  [{value:null},{value:2},{value:1},{value:1}],[optionalNumber('value',true)]),
 optionalCase('left-and-right-join-sources',"SELECT lefts.id,right_value FROM (SELECT 1 AS id UNION ALL SELECT 2) lefts JOIN (SELECT 1 AS key,100 AS right_value) ON lefts.id=key MAX_OUTPUT_ROWS 10 ORDER BY lefts.id",
  [{id:1,right_value:100}],[optionalNumber('id'),optionalNumber('right_value')]),
 optionalCase('pipe-query-head',"FROM (SELECT 1 AS id UNION ALL SELECT 2) |> WHERE id>1 |> SELECT id |> ORDER BY id",
  [{id:2}],[optionalNumber('id')],{format:'aql-text'}),
 optionalCase('captured-null',"SELECT amount,id FROM (FROM records |> WHERE amount IS NULL |> SELECT id,amount) ORDER BY id",
  [{amount:null,id:1}],[optionalNumber('amount',true),optionalNumber('id')],
  {sourceReadCount:undefined,sourceReadSessionCount:1}),
 optionalCase('captured-range-snapshot',"SELECT id,r.amount AS original,amount AS `current` FROM (FROM records |> AS r |> SET amount=99) ORDER BY id",
  [{id:1,original:null,current:99},{id:2,original:20,current:99},{id:3,original:30,current:99},{id:3,original:30,current:99}],
  [optionalNumber('id'),optionalNumber('original',true),optionalNumber('current')],
  {sourceReadCount:undefined,sourceReadSessionCount:1}),
 optionalCase('closed-set-fields',"SELECT id FROM (SELECT 1 AS id UNION ALL BY NAME SELECT 2 AS id) ORDER BY id",
  [{id:1},{id:2}],[optionalNumber('id')]),
);

// A derived alias names the existing value-table receiver, including the
// whole nullable object. It does not manufacture a STRUCT around a scalar.
const derivedScalarDeclarations={items:{type:'array',nullable:true,max_items:3,
 items:{type:'number',nullable:true}}};
const derivedScalarItems=[2,null,2];
const derivedScalarControl={version:'actql/0.1',id:'fixture.derived_scalar_alias',
 params:derivedScalarDeclarations,stages:[{id:'main',inputs:{},steps:[
 {values:{schema:{unit:{type:'boolean',nullable:false}},rows:[{unit:true}]},as:'seed'},
 {from:'seed',derive:{items:{$param:'items'}}},
 {unnest:{column:'items',as:'value'}},
 {sort:[{field:'value',dir:'asc',nulls:'first'}]},
 {select:['value'],as:'out'},
 ],results:{rows:{from:'out',fields:['value']}}}],
 results:{answer:{from:{stage:'main',result:'rows'}}}};
const derivedValueCase=(name,text,expected,columns,extra={})=>({
 name:'derived-value-'+name,format:'sql',text,expected,columns,
 parameterDeclarations:derivedScalarDeclarations,parameters:{items:derivedScalarItems},
 sourceReadCount:0,sourceReadSessionCount:0,...extra});
const derivedValueColumns=[optionalNumber('value',true)];
const derivedScalarRows=[{value:null},{value:2},{value:2}];
const derivedScalarText='SELECT chosen AS value FROM (FROM UNNEST(@items) element) chosen ORDER BY value NULLS FIRST';
const derivedObjectContract={type:'object',nullable:true,fields:{id:{type:'number',nullable:false},label:{type:'string',nullable:true}}};
const derivedObjectDeclarations={items:{type:'array',nullable:true,max_items:3,items:derivedObjectContract}};
const derivedObjectItems=[{id:2,label:'kept'},null,{id:2,label:null}];
const derivedObjectRows=[{value:null,id:null},{value:{id:2,label:null},id:2},{value:{id:2,label:'kept'},id:2}];
const derivedObjectColumns=[{name:'value',contract:{...derivedObjectContract,additional_properties:false}},optionalNumber('id',true)];
const derivedObjectControl={version:'actql/0.1',id:'fixture.derived_object_alias',params:derivedObjectDeclarations,
 stages:[{id:'main',inputs:{},steps:[
 {values:{schema:{unit:{type:'boolean',nullable:false}},rows:[{unit:true}]},as:'seed'},
 {from:'seed',derive:{items:{$param:'items'}}},
 {unnest:{column:'items',as:'element'}},
 {derive:{id:{property:{value:{field:'element'},name:'id'}},label:{property:{value:{field:'element'},name:'label'}}}},
 {sort:[{field:'id',dir:'asc',nulls:'first'},{field:'label',dir:'asc',nulls:'first'}]},
 {select:[{value:'element'},'id'],as:'out'},
 ],results:{rows:{from:'out',fields:['value','id']}}}],results:{answer:{from:{stage:'main',result:'rows'}}}};
queryCompositionSuccesses.push(
 derivedValueCase('scalar-json-control',JSON.stringify(derivedScalarControl),derivedScalarRows,derivedValueColumns,{format:'json',parameterDeclarations:undefined}),
 derivedValueCase('scalar-receiver',derivedScalarText,derivedScalarRows,derivedValueColumns),
 derivedValueCase('quoted-scalar','FROM (FROM UNNEST(@items) element) `ORDER` |> SELECT `ORDER` AS value |> ORDER BY value NULLS FIRST',derivedScalarRows,derivedValueColumns,{format:'aql-text'}),
 derivedValueCase('scalar-empty',derivedScalarText,[],derivedValueColumns,{parameters:{items:[]}}),
 derivedValueCase('scalar-null-array',derivedScalarText,[],derivedValueColumns,{parameters:{items:null}}),
 derivedValueCase('object-json-control',JSON.stringify(derivedObjectControl),derivedObjectRows,derivedObjectColumns,{format:'json',parameterDeclarations:undefined,parameters:{items:derivedObjectItems}}),
 derivedValueCase('object-whole-and-property','SELECT chosen AS value,chosen.id AS id FROM (FROM UNNEST(@items) element) chosen ORDER BY id NULLS FIRST,value.label NULLS FIRST',derivedObjectRows,derivedObjectColumns,{parameterDeclarations:derivedObjectDeclarations,parameters:{items:derivedObjectItems}}),
 derivedValueCase('object-star','SELECT chosen.* FROM (FROM UNNEST(@items) element) chosen ORDER BY id NULLS FIRST,label NULLS FIRST',
 [{id:null,label:null},{id:2,label:null},{id:2,label:'kept'}],[optionalNumber('id',true),{name:'label',contract:{type:'string',nullable:true}}],{parameterDeclarations:derivedObjectDeclarations,parameters:{items:derivedObjectItems}}),
 derivedValueCase('object-empty','SELECT chosen AS value,chosen.id AS id FROM (FROM UNNEST(@items) element) chosen ORDER BY id NULLS FIRST,value.label NULLS FIRST',[],derivedObjectColumns,{parameterDeclarations:derivedObjectDeclarations,parameters:{items:[]}}),
 derivedValueCase('offset-row-columns','SELECT chosen.element AS value,chosen.position FROM (FROM UNNEST(@items) element WITH OFFSET position) chosen ORDER BY position',
 [{value:2,position:0},{value:null,position:1},{value:2,position:2}],[optionalNumber('value',true),optionalNumber('position')]),
 derivedValueCase('offset-row-star','SELECT chosen.* FROM (FROM UNNEST(@items) element WITH OFFSET position) chosen ORDER BY position',
 [{element:2,position:0},{element:null,position:1},{element:2,position:2}],[optionalNumber('element',true),optionalNumber('position')]),
);

// JOIN carries the admitted operand kind: a value-table receiver stays a
// value, while WITH OFFSET is an ordinary row. Controls are authored JSON.
export const joinValueControl={version:'actql/0.1',id:'fixture.join_value_receiver',params:derivedScalarDeclarations,
 stages:[{id:'main',inputs:{},steps:[
 {values:{schema:{id:{type:'number',nullable:false}},rows:[{id:7}]},as:'left'},
 {values:{schema:{unit:{type:'boolean',nullable:false}},rows:[{unit:true}]},as:'seed'},
 {from:'seed',derive:{items:{$param:'items'}}},
 {unnest:{column:'items',as:'element'},as:'right'},
 {from:'left',cross_join:{with:'right',max_output_rows:10,select:{value:'right.element'}},as:'joined'},
 {from:'joined',sort:[{field:'value',dir:'asc',nulls:'first'}]},
 {select:['value'],as:'out'},
 ],results:{rows:{from:'out',fields:['value']}}}],results:{answer:{from:{stage:'main',result:'rows'}}}};
const joinValueCase=(name,text,expected=derivedScalarRows,columns=derivedValueColumns,extra={})=>({
 name:'join-value-'+name,format:'sql',text,expected,columns,
 parameterDeclarations:derivedScalarDeclarations,parameters:{items:derivedScalarItems},
 sourceReadCount:0,sourceReadSessionCount:0,...extra});
const joinValueScalarText='SELECT r AS value FROM (SELECT 7 AS id) l CROSS JOIN (FROM UNNEST(@items) old_r) r MAX_OUTPUT_ROWS 10 ORDER BY value NULLS FIRST';
queryCompositionSuccesses.push(
 joinValueCase('json-control',JSON.stringify(joinValueControl),derivedScalarRows,derivedValueColumns,{format:'json',parameterDeclarations:undefined}),
 joinValueCase('right-null-duplicates',joinValueScalarText),
 joinValueCase('right-empty',joinValueScalarText,[],derivedValueColumns,{parameters:{items:[]}}),
 joinValueCase('quoted-right','FROM (SELECT 7 AS id) l |> CROSS JOIN (FROM UNNEST(@items) old_r) `ORDER` MAX_OUTPUT_ROWS 10 |> SELECT `ORDER` AS value |> ORDER BY value NULLS FIRST',derivedScalarRows,derivedValueColumns,{format:'aql-text'}),
 joinValueCase('both-scalar-on','SELECT l AS left_value,r AS right_value FROM (FROM UNNEST([1,2]) old_l) l JOIN (FROM UNNEST([2,3]) old_r) r ON l=r MAX_OUTPUT_ROWS 10 ORDER BY left_value',[{left_value:2,right_value:2}],[optionalNumber('left_value'),optionalNumber('right_value')],{parameterDeclarations:undefined,parameters:undefined}),
 joinValueCase('right-range-column-collision','SELECT r AS value FROM (SELECT 1 AS id,90 AS r) l JOIN (FROM UNNEST([1,2]) old_r) r ON l.id=r MAX_OUTPUT_ROWS 10',[{value:1}],[optionalNumber('value')],{parameterDeclarations:undefined,parameters:undefined}),
 joinValueCase('left-null-extension','SELECT l.id,r AS value FROM (SELECT 1 AS id UNION ALL SELECT 3) l LEFT JOIN (FROM UNNEST([1,2]) old_r) r ON l.id=r MAX_OUTPUT_ROWS 10 ORDER BY l.id',[{id:1,value:1},{id:3,value:null}],[optionalNumber('id'),optionalNumber('value',true)],{parameterDeclarations:undefined,parameters:undefined}),
 joinValueCase('right-object','SELECT r AS value,r.id AS id FROM (SELECT 7 AS key) l CROSS JOIN (FROM UNNEST(@items) old_r) r MAX_OUTPUT_ROWS 10 ORDER BY id NULLS FIRST,value.label NULLS FIRST',derivedObjectRows,derivedObjectColumns,{parameterDeclarations:derivedObjectDeclarations,parameters:{items:derivedObjectItems}}),
 joinValueCase('offset-row','SELECT r AS row,r.element AS value,r.position FROM (SELECT 7 AS id) l CROSS JOIN (FROM UNNEST(@items) element WITH OFFSET position) r MAX_OUTPUT_ROWS 10 ORDER BY position',
 [{row:{element:2,position:0},value:2,position:0},{row:{element:null,position:1},value:null,position:1},{row:{element:2,position:2},value:2,position:2}],
 [{name:'row',contract:{type:'object',nullable:false,fields:{element:{type:'number',nullable:true},position:{type:'number',nullable:false}},additional_properties:false}},optionalNumber('value',true),optionalNumber('position')]),
);


// Independent ordinary-row expectations. A NULL element is one NULL field,
// not a NULL row; the declared OFFSET remains non-NULL.
const wholeRowHead='FROM UNNEST(@items) element WITH OFFSET position';
const wholeRowFields={element:{type:'number',nullable:true},position:{type:'number',nullable:false}};
const wholeRowColumn={name:'row',contract:{type:'object',nullable:false,fields:wholeRowFields,additional_properties:false}};
const wholeRowRows=[{row:{element:2,position:0},value:2,position:0},{row:{element:null,position:1},value:null,position:1},{row:{element:2,position:2},value:2,position:2}];
const wholeRowColumns=[wholeRowColumn,optionalNumber('value',true),optionalNumber('position')];
const wholeRowSource='SELECT chosen AS row,chosen.element AS value,chosen.position FROM ('+wholeRowHead+') chosen ORDER BY position';
const wholeRowControl={version:'actql/0.1',id:'fixture.whole_row_range',params:derivedScalarDeclarations,stages:[{id:'main',inputs:{},steps:[
 {values:{schema:{unit:{type:'boolean',nullable:false}},rows:[{unit:true}]},as:'seed'},
 {from:'seed',derive:{items:{$param:'items'}}},
 {unnest:{column:'items',as:'element',with_index:'position'}},
 {derive:{row:{object:{element:{field:'element'},position:{field:'position'}}}}},
 {select:['row',{value:'element'},'position']},
 {sort:[{field:'position',dir:'asc',nulls:'first'}],as:'out'},
 ],results:{rows:{from:'out',fields:['row','value','position']}}}],results:{answer:{from:{stage:'main',result:'rows'}}}};
const wholeRowCase=(name,text,expected=wholeRowRows,columns=wholeRowColumns,extra={})=>({name:'whole-row-'+name,format:'sql',text,expected,columns,parameterDeclarations:derivedScalarDeclarations,parameters:{items:derivedScalarItems},sourceReadCount:0,sourceReadSessionCount:0,...extra});
queryCompositionSuccesses.push(
 wholeRowCase('json-control',JSON.stringify(wholeRowControl),wholeRowRows,wholeRowColumns,{format:'json',parameterDeclarations:undefined}),
 wholeRowCase('offset-receiver',wholeRowSource),
 wholeRowCase('empty',wholeRowSource,[],wholeRowColumns,{parameters:{items:[]}}),
 wholeRowCase('implicit-output-name','FROM ('+wholeRowHead+') chosen |> SELECT chosen |> ORDER BY chosen.position',wholeRowRows.map(r=>({chosen:r.row})),[{...wholeRowColumn,name:'chosen'}],{format:'aql-text'}),
 wholeRowCase('immutable-set','FROM ('+wholeRowHead+') chosen |> SET element = position + 10 |> SELECT chosen AS row,element AS value,position |> ORDER BY position',wholeRowRows.map(r=>({...r,value:r.position+10})),[wholeRowColumn,optionalNumber('value'),optionalNumber('position')],{format:'aql-text'}),
 wholeRowCase('rebound-set','FROM ('+wholeRowHead+') chosen |> SET element = position + 10 |> AS fresh |> SELECT fresh AS row,element AS value,position |> ORDER BY position',wholeRowRows.map(r=>({row:{element:r.position+10,position:r.position},value:r.position+10,position:r.position})),[{...wholeRowColumn,contract:{...wholeRowColumn.contract,fields:{...wholeRowFields,element:{type:'number',nullable:false}}}},optionalNumber('value'),optionalNumber('position')],{format:'aql-text'}),
 wholeRowCase('drop-rename-rebind','FROM ('+wholeRowHead+') chosen |> DROP element |> RENAME position AS index |> AS fresh |> SELECT fresh AS row,index |> ORDER BY index',[{row:{index:0},index:0},{row:{index:1},index:1},{row:{index:2},index:2}],[{name:'row',contract:{type:'object',nullable:false,fields:{index:{type:'number',nullable:false}},additional_properties:false}},optionalNumber('index')],{format:'aql-text'}),
 wholeRowCase('range-priority','FROM ('+wholeRowHead+') chosen |> AS element |> SELECT element AS value,position |> ORDER BY position',wholeRowRows.map(r=>({value:r.row,position:r.position})),[{...wholeRowColumn,name:'value'},optionalNumber('position')],{format:'aql-text'}),
 wholeRowCase('computed-order','FROM ('+wholeRowHead+') chosen |> AS fresh |> SELECT fresh AS row |> ORDER BY IF(TRUE,fresh,NULL).position DESC',wholeRowRows.toReversed().map(r=>({row:r.row})),[wholeRowColumn],{format:'aql-text'}),
);

// Fixed NameScope::AddNameTarget: an input range shadows a current column.
// CopyNameScopeWithOverridingNames gives ORDER aliases a separate nearer scope.
const shadowHead='FROM ('+wholeRowHead+') chosen |> AS element';
const shadowCase=(name,text,expected,columns,extra={})=>({...wholeRowCase(name,text,expected,columns),name:'range-shadow-'+name,format:'aql-text',...extra});
const shadowPayloadDeclaration={payload:{type:'object',nullable:true,fields:{score:{type:'number',nullable:false}}}};
const shadowPayloadText='FROM (SELECT 90 AS score,@payload AS payload) |> AS payload |> SELECT (payload).score AS value';
const shadowScoreControl={version:'actql/0.1',id:'fixture.range_shadow_score',stages:[{id:'main',inputs:{},steps:[{values:{schema:{score:{type:'number',nullable:false},payload:{type:'object',nullable:true,fields:{score:{type:'number',nullable:false}}}},rows:[{score:90,payload:{score:10}}]},as:'objects'},{from:'objects',select:[{value:'score'}],as:'out'}],results:{rows:{from:'out',fields:['value']}}}],results:{answer:{from:{stage:'main',result:'rows'}}}};
queryCompositionSuccesses.push(
 shadowCase('where-row',shadowHead+' |> WHERE COALESCE(element,NULL).position > 0 |> SELECT element AS row,position |> ORDER BY position',[{row:{element:null,position:1},position:1},{row:{element:2,position:2},position:2}],[wholeRowColumn,optionalNumber('position')]),
 shadowCase('set-removes-range',shadowHead+' |> SET element = position + 10 |> SELECT element AS value,position |> ORDER BY position',[{value:10,position:0},{value:11,position:1},{value:12,position:2}],[optionalNumber('value'),optionalNumber('position')]),
 shadowCase('order-alias',shadowHead+' |> SELECT position AS element |> ORDER BY element DESC',[{element:2},{element:1},{element:0}],[optionalNumber('element')]),
 shadowCase('extend-surviving-range','FROM ('+wholeRowHead+') chosen |> AS kept |> EXTEND 99 AS kept |> SELECT kept AS row,position |> ORDER BY position',wholeRowRows.map(r=>({row:r.row,position:r.position})),[wholeRowColumn,optionalNumber('position')]),
 shadowCase('object-column-json-control',JSON.stringify(shadowScoreControl),[{value:90}],[optionalNumber('value')],{format:'json',parameterDeclarations:undefined,parameters:undefined}),
 shadowCase('object-column',shadowPayloadText,[{value:90}],[optionalNumber('value')],{parameterDeclarations:shadowPayloadDeclaration,parameters:{payload:{score:10}}}),
 shadowCase('null-object-column',shadowPayloadText,[{value:90}],[optionalNumber('value')],{parameterDeclarations:shadowPayloadDeclaration,parameters:{payload:null}}),
);

// JOIN rows reuse the existing range/column scope and closed-object form.
// These rows and contracts are authored from SQL multiplicity/null extension,
// independently of compiler output. FULL retains explicit key evidence.
const joinedLeft='(SELECT 20 AS amount,2 AS id UNION ALL SELECT CAST(NULL AS FLOAT64),1 UNION ALL SELECT 20,2)';
const joinedRight='(SELECT 2 AS id,20 AS marker UNION ALL SELECT 4,40)';
const joinedLeftFields={amount:{type:'number',nullable:true},id:{type:'number',nullable:false}};
const joinedObject=(name,fields)=>({name,contract:{type:'object',nullable:false,fields,additional_properties:false}});
const joinedLeftColumn=joinedObject('left_row',joinedLeftFields);
const joinedRightColumn=joinedObject('right_row',{id:{type:'number',nullable:false}});
const joinedCrossRows=[
 {left_row:{amount:null,id:1},right_row:{id:7}},
 {left_row:{amount:20,id:2},right_row:{id:7}},
 {left_row:{amount:20,id:2},right_row:{id:7}},
];
export const joinedRowControl={version:'actql/0.1',id:'fixture.joined_rows',stages:[{id:'main',inputs:{},steps:[
 {values:{schema:joinedLeftFields,rows:[{amount:20,id:2},{amount:null,id:1},{amount:20,id:2}]},as:'left'},
 {values:{schema:{id:{type:'number',nullable:false}},rows:[{id:7}]},as:'right'},
 {from:'left',cross_join:{with:'right',max_output_rows:10,select:{left_amount:'left.amount',left_id:'left.id',right_id:'right.id'}},as:'joined'},
 {from:'joined',derive:{left_row:{object:{amount:{field:'left_amount'},id:{field:'left_id'}}},right_row:{object:{id:{field:'right_id'}}}}},
 {sort:[{field:'left_id',dir:'asc',nulls:'first'}]},
 {select:['left_row','right_row'],as:'out'},
 ],results:{rows:{from:'out',fields:['left_row','right_row']}}}],results:{answer:{from:{stage:'main',result:'rows'}}}};
const joinedCase=(name,text,expected=joinedCrossRows,columns=[joinedLeftColumn,joinedRightColumn],extra={})=>({name:'joined-row-'+name,format:'sql',text,expected,columns,sourceReadCount:0,sourceReadSessionCount:0,...extra});
const joinedCrossSource='SELECT l AS left_row,r AS right_row FROM '+joinedLeft+' l CROSS JOIN (SELECT 7 AS id) r MAX_OUTPUT_ROWS 10 ORDER BY l.id';
const joinedNullableRight=joinedObject('right_row',{id:{type:'number',nullable:true},marker:{type:'number',nullable:true}});
const joinedNonNullRight=joinedObject('right_row',{id:{type:'number',nullable:false},marker:{type:'number',nullable:false}});
const joinedNullableLeft=joinedObject('left_row',{amount:{type:'number',nullable:true},id:{type:'number',nullable:true}});
const joinedAliasSource='SELECT COALESCE(l,NULL).amount AS original,r AS l,l.id AS id FROM (SELECT 1 AS id,20 AS amount UNION ALL SELECT 2,10 UNION ALL SELECT 2,10) l JOIN (SELECT 1 AS id,10 AS amount UNION ALL SELECT 2,30) r ON l.id=r.id MAX_OUTPUT_ROWS 10 ORDER BY COALESCE(l,NULL).amount';
const joinedAliasColumns=[optionalNumber('original'),joinedObject('l',{amount:{type:'number',nullable:false},id:{type:'number',nullable:false}}),optionalNumber('id')];
queryCompositionSuccesses.push(
 joinedCase('json-control',JSON.stringify(joinedRowControl),joinedCrossRows,[joinedLeftColumn,joinedRightColumn],{format:'json'}),
 joinedCase('cross-null-duplicates',joinedCrossSource),
 joinedCase('empty',joinedCrossSource.replace(joinedLeft, '(SELECT CAST(NULL AS FLOAT64) AS amount,1 AS id WHERE FALSE)'),[],[joinedLeftColumn,joinedRightColumn]),
 joinedCase('range-column-collision','SELECT l AS row FROM (SELECT 7 AS l,9 AS id) l CROSS JOIN (SELECT 2 AS id) r MAX_OUTPUT_ROWS 10',[{row:{l:7,id:9}}],[joinedObject('row',{l:{type:'number',nullable:false},id:{type:'number',nullable:false}})]),
 joinedCase('quoted-range','SELECT `ORDER` AS left_row,r AS right_row FROM '+joinedLeft+' `ORDER` CROSS JOIN (SELECT 7 AS id) r MAX_OUTPUT_ROWS 10 ORDER BY `ORDER`.id'),
 joinedCase('left-null-extension','SELECT l AS left_row,r AS right_row FROM '+joinedLeft+' l LEFT JOIN '+joinedRight+' r ON l.id=r.id MAX_OUTPUT_ROWS 10 ORDER BY l.id',[
  {left_row:{amount:null,id:1},right_row:{id:null,marker:null}},
  {left_row:{amount:20,id:2},right_row:{id:2,marker:20}},
  {left_row:{amount:20,id:2},right_row:{id:2,marker:20}},
 ],[joinedLeftColumn,joinedNullableRight]),
 joinedCase('right-null-extension','SELECT l AS left_row,r AS right_row FROM '+joinedLeft+' l RIGHT JOIN '+joinedRight+' r ON l.id=r.id MAX_OUTPUT_ROWS 10 ORDER BY r.id',[
  {left_row:{amount:20,id:2},right_row:{id:2,marker:20}},
  {left_row:{amount:20,id:2},right_row:{id:2,marker:20}},
  {left_row:{amount:null,id:null},right_row:{id:4,marker:40}},
 ],[joinedNullableLeft,joinedNonNullRight]),
 joinedCase('full-using','WITH lefts AS (FROM (SELECT 1 AS id UNION ALL SELECT 2) |> ASSERT UNIQUE BY (id)), rights AS (FROM '+joinedRight+' |> ASSERT UNIQUE BY (id)) SELECT l AS left_row,r AS right_row FROM lefts l FULL JOIN rights r USING (id) MAX_OUTPUT_ROWS 10 ORDER BY id',[
  {left_row:{id:1},right_row:{id:null,marker:null}},
  {left_row:{id:2},right_row:{id:2,marker:20}},
  {left_row:{id:null},right_row:{id:4,marker:40}},
 ],[joinedObject('left_row',{id:{type:'number',nullable:true}}),joinedNullableRight],{format:'aql-text'}),
 joinedCase('pre-join-predicate','FROM '+joinedLeft+' l |> WHERE COALESCE(l,NULL).id > 1 |> LIMIT 1 |> CROSS JOIN (SELECT 7 AS id) r MAX_OUTPUT_ROWS 10 |> SELECT l AS left_row,r AS right_row',[{left_row:{amount:20,id:2},right_row:{id:7}}],[joinedLeftColumn,joinedRightColumn],{format:'aql-text'}),
 joinedCase('order-alias-not-input-reuse',joinedAliasSource,[
  {original:20,l:{amount:10,id:1},id:1},
  {original:10,l:{amount:30,id:2},id:2},
  {original:10,l:{amount:30,id:2},id:2},
 ],joinedAliasColumns),
 joinedCase('shared-acquired-cte','WITH chosen AS (SELECT amount,id FROM records) SELECT l AS left_row,r AS right_row FROM chosen l JOIN chosen r ON l.id=r.id MAX_OUTPUT_ROWS 10 ORDER BY l.id',[
  {left_row:{amount:null,id:1},right_row:{amount:null,id:1}},
  {left_row:{amount:20,id:2},right_row:{amount:20,id:2}},
  {left_row:{amount:30,id:3},right_row:{amount:30,id:3}},
  {left_row:{amount:30,id:3},right_row:{amount:30,id:3}},
  {left_row:{amount:30,id:3},right_row:{amount:30,id:3}},
  {left_row:{amount:30,id:3},right_row:{amount:30,id:3}},
 ],[joinedLeftColumn,joinedObject('right_row',joinedLeftFields)],{sourceReadCount:undefined,sourceReadSessionCount:1}),
);

export const queryCompositionRefusals = [
  {name: 'nested-cte-octal-range', format: 'sql',
    text: "WITH chosen AS (SELECT '\\400' AS label FROM records) SELECT label FROM chosen"},
  {name: 'literal-set-later-alias-hidden', format: 'sql',
    text: "WITH chosen AS (SELECT r'\\400' AS label FROM records) SELECT label FROM chosen UNION ALL SELECT label AS other FROM chosen ORDER BY other"},
  {name: 'set-order-operand-column', format: 'sql',
    text: 'SELECT id AS amount FROM records UNION ALL SELECT id AS other FROM records ORDER BY id + 1'},
  {name: 'set-order-right-alias', format: 'sql',
    text: 'SELECT id AS amount FROM records UNION ALL SELECT id AS other FROM records ORDER BY other + 1'},
  {name: 'set-order-qualified-input', format: 'sql',
    text: 'SELECT id FROM records UNION ALL SELECT id FROM records ORDER BY records.id + 1'},

  {name: 'nested-with-quoted-duplicate', format: 'sql',
    text: 'WITH chosen AS (WITH `Hidden` AS (SELECT id FROM records), hidden AS (SELECT id FROM records) SELECT id FROM hidden) SELECT id FROM chosen'},
  {name: 'nested-with-escaped-name', format: 'sql',
    text: 'WITH chosen AS (WITH hidden AS (SELECT id FROM records) SELECT id FROM hidden) SELECT id FROM chosen UNION ALL SELECT id FROM hidden'},
  {name: 'derived-with-escaped-name', format: 'sql',
    text: 'SELECT id FROM (WITH hidden AS (SELECT id FROM records) SELECT id FROM hidden) AS chosen UNION ALL SELECT id FROM hidden'},
  {name: 'nested-with-forward-reference', format: 'sql',
    text: 'WITH chosen AS (WITH hidden AS (SELECT id FROM later), later AS (SELECT id FROM records) SELECT id FROM hidden) SELECT id FROM chosen'},
  {name: 'nested-with-duplicate-name', format: 'sql',
    text: 'WITH chosen AS (WITH hidden AS (SELECT id FROM records), HIDDEN AS (SELECT id FROM records) SELECT id FROM hidden) SELECT id FROM chosen'},
  {name: 'derived-hidden-column', format: 'sql',
    text: 'SELECT chosen.amount FROM (FROM records |> SELECT id) AS chosen'},
  {name: 'derived-hidden-range', format: 'sql',
    text: 'SELECT old.id FROM (FROM records AS old |> SELECT id) AS chosen'},
  {name: 'derived-displaced-range', format: 'sql',
    text: 'SELECT id FROM (FROM records AS old |> AS fresh |> SELECT old.id) AS chosen'},
  {name: 'derived-inner-terminator', format: 'sql',
    text: 'SELECT id FROM (FROM records |> SELECT id;) AS chosen'},
  {name: 'parenthesized-hidden-range', format: 'sql',
    text: '(SELECT id FROM records) |> SELECT records.id'},
  {name: 'set-hidden-column', format: 'sql',
    text: 'SELECT id FROM records UNION ALL SELECT id FROM records |> SELECT amount'},
  {name: 'set-forward-cte', format: 'sql',
    text: 'WITH chosen AS (SELECT id FROM records UNION ALL SELECT id FROM later), later AS (SELECT id FROM records) SELECT id FROM chosen'},
  {name: 'parenthesized-inner-terminator', format: 'sql',
    text: '(SELECT id FROM records;)'},

];
queryCompositionRefusals.push(...[
 ['unregistered-qualifier','SELECT chosen.id FROM (SELECT 1 AS id)'],
 ['projected-old-range','SELECT r.x FROM (FROM (SELECT 1 AS x) base |> AS r |> SELECT x)'],
 ['explicit-alias-old-range','SELECT r.x FROM ('+optionalRangeHead+') chosen'],
 ['set-old-range','SELECT before.id FROM (SELECT 1 AS id UNION ALL SELECT 2)'],
 ['private-producer','SELECT aql_query_source_0.id FROM (SELECT 1 AS id)'],
 ['ambiguous-column','SELECT id FROM (SELECT 1 AS id) CROSS JOIN (SELECT 2 AS id) MAX_OUTPUT_ROWS 10'],
].map(([name,text])=>({name:'derived-optional-refusal-'+name,format:'sql',text,
 expectedCode:'ClientProgramInvalidInput'})));

queryCompositionRefusals.push(...[
 ['old-scalar-receiver','SELECT element AS value FROM (FROM UNNEST(@items) element) chosen'],
 ['scalar-star','SELECT chosen.* FROM (FROM UNNEST(@items) element) chosen'],
 ['unregistered-scalar-property','SELECT chosen.score AS value FROM (FROM UNNEST(@items) element) chosen'],
 ['duplicate-derived-alias','SELECT chosen.value FROM (FROM UNNEST(@items) element) chosen CROSS JOIN (SELECT 1 AS value) chosen MAX_OUTPUT_ROWS 10'],
].map(([name,text])=>({name:'derived-value-refusal-'+name,format:'sql',text,
 parameterDeclarations:derivedScalarDeclarations,parameters:{items:derivedScalarItems},expectedCode:'ClientProgramInvalidInput'})));

queryCompositionRefusals.push(...[
 ['displaced','aql-text','FROM ('+wholeRowHead+') chosen |> AS fresh |> SELECT chosen AS row'],
 ['removed','aql-text','FROM ('+wholeRowHead+') chosen |> SELECT element |> WHERE element > 0 |> SELECT chosen AS row'],
 ['missing-member','sql','SELECT (chosen).missing AS value FROM ('+wholeRowHead+') chosen'],
 ['distinct-hidden','aql-text','FROM ('+wholeRowHead+') chosen |> SELECT DISTINCT element |> ORDER BY IF(TRUE,chosen,NULL).position'],
].map(([name,format,text])=>({name:'whole-row-refusal-'+name,format,text,parameterDeclarations:derivedScalarDeclarations,parameters:{items:derivedScalarItems},expectedCode:'ClientProgramInvalidInput'})));

queryCompositionRefusals.push(...[
 ['drop-removes-range',shadowHead+' |> DROP element |> SELECT element AS row'],
 ['row-is-not-number',shadowHead+' |> SELECT element + 1 AS value'],
].map(([name,text])=>({name:'range-shadow-refusal-'+name,format:'aql-text',text,parameterDeclarations:derivedScalarDeclarations,parameters:{items:derivedScalarItems},expectedCode:'ClientProgramInvalidInput'})));

queryCompositionRefusals.push(...[
 ['missing-row-member','SELECT (l).missing AS value FROM '+joinedLeft+' l CROSS JOIN (SELECT 7 AS id) r MAX_OUTPUT_ROWS 10'],
 ['row-is-not-number','SELECT l+1 AS value FROM '+joinedLeft+' l CROSS JOIN (SELECT 7 AS id) r MAX_OUTPUT_ROWS 10'],
 ['displaced-range','FROM '+joinedLeft+' l |> CROSS JOIN (SELECT 7 AS id) r MAX_OUTPUT_ROWS 10 |> AS current |> SELECT l AS row'],
 ['duplicate-range','SELECT l AS row FROM '+joinedLeft+' l CROSS JOIN (SELECT 7 AS id) l MAX_OUTPUT_ROWS 10'],
].map(([name,text])=>({name:'joined-row-refusal-'+name,format:name==='displaced-range'?'aql-text':'sql',text,expectedCode:'ClientProgramInvalidInput'})));

export const querySuccesses = [
  {name: 'sql', format: 'sql',
    text: 'SELECT id FROM records WHERE amount >= @minimum ORDER BY id',
    parameterDeclarations: declarations, parameters: {minimum: 20},
    expected: [{id: 2}, {id: 3}, {id: 3}]},
  {name: 'pipe', format: 'aql-text',
    text: 'FROM records |> WHERE amount >= @minimum |> SELECT id |> ORDER BY id',
    parameterDeclarations: declarations, parameters: {minimum: 20},
    expected: [{id: 2}, {id: 3}, {id: 3}]},
  {name: 'nullable-parameter', format: 'sql',
    text: 'SELECT id FROM records WHERE @minimum IS NULL OR amount >= @minimum ORDER BY id',
    parameterDeclarations: {minimum: {type: 'number', nullable: true}},
    parameters: {minimum: null}, expected: [{id: 1}, {id: 2}, {id: 3}, {id: 3}]},
  {name: 'null', format: 'sql',
    text: 'SELECT id FROM records WHERE amount IS NULL ORDER BY id',
    expected: [{id: 1}]},
  {name: 'empty', format: 'sql',
    text: 'SELECT id FROM records WHERE amount > 100 ORDER BY id', expected: []},
];
// Hand-authored source-free expectations. No compiler or output snapshot
// generates these rows, contracts or order. Installed source aliases remain
// available in the Host, but none of these Programs acquires them.
const numberColumn = name => ({name, contract: {type: 'number', nullable: false}});
const octalQuotes = [['single', "'"], ['double', '"'],
  ['triple-single', "'''"], ['triple-double', '"""']];
export const sourceFreeSuccesses = [
  ...octalQuotes.flatMap(([name, quote]) => [
    {name: `octal-boundary-${name}`, format: 'sql',
      text: `SELECT ${quote}\\000${quote} AS low, ${quote}\\377${quote} AS high`,
      expected: [{low: '\u0000', high: '\u00ff'}],
      columns: [['low', 1], ['high', 2]].map(([name, bytes]) => ({name,
        contract: {type: 'string', nullable: false, max_utf8_bytes: bytes}})),
      sourceReadCount: 0},
    {name: `raw-octal-${name}`, format: 'sql',
      text: `SELECT r${quote}\\400${quote} AS four, R${quote}\\777${quote} AS seven`,
      expected: [{four: '\\400', seven: '\\777'}],
      columns: ['four', 'seven'].map(name => ({name,
        contract: {type: 'string', nullable: false, max_utf8_bytes: 4}})),
      sourceReadCount: 0},
  ]),
  {name: 'raw-string-chunks', format: 'sql',
    text: `SELECT r'\\n' AS slash_n, R"\\u0041" AS unicode_text, r'a\\'b' AS quoted`,
    expected: [{slash_n: '\\n', unicode_text: '\\u0041', quoted: "a\\'b"}],
    columns: [['slash_n', 2], ['unicode_text', 6], ['quoted', 4]].map(([name, bytes]) => ({name,
      contract: {type: 'string', nullable: false, max_utf8_bytes: bytes}})),
    sourceReadCount: 0},
  {name: 'triple-string-newlines', format: 'aql-text',
    text: `SELECT '''a\r\nb''' AS physical, """\\r""" AS escaped, '''e\u0301''' AS decomposed`,
    expected: [{physical: 'a\nb', escaped: '\r', decomposed: 'e\u0301'}],
    columns: [['physical', 3], ['escaped', 1], ['decomposed', 3]].map(([name, bytes]) => ({name,
      contract: {type: 'string', nullable: false, max_utf8_bytes: bytes}})),
    sourceReadCount: 0},
  {name: 'mixed-separated-string-chunks', format: 'sql',
    text: `SELECT r'\\n' /* only this chunk is raw */ '\\n' "é" '''e\u0301''' AS joined, '' "" '''''' AS empty`,
    expected: [{joined: '\\n\née\u0301', empty: ''}],
    columns: [['joined', 8], ['empty', 0]].map(([name, bytes]) => ({name,
      contract: {type: 'string', nullable: false, max_utf8_bytes: bytes}})),
    sourceReadCount: 0},
  {name: 'double-quoted-exact-values', format: 'sql',
    text: 'SELECT "\\r" AS cr, "\\n" AS lf, "\\r\\n" AS crlf, "é" AS composed, "e\\u0301" AS decomposed, "\\\\n" AS slash_n',
    expected: [{cr: '\r', lf: '\n', crlf: '\r\n', composed: 'é', decomposed: 'e\u0301', slash_n: '\\n'}],
    columns: [['cr', 1], ['lf', 1], ['crlf', 2], ['composed', 2],
      ['decomposed', 3], ['slash_n', 2]].map(([name, bytes]) => ({name,
        contract: {type: 'string', nullable: false, max_utf8_bytes: bytes}})),
    sourceReadCount: 0},
  {name: 'quoted-scalar-escapes', format: 'sql',
    text: `SELECT '\\101\\x42\\X43\\u65e5\\U0001F600' AS single_value, "\\101\\x42\\X43\\u65e5\\U0001F600" AS double_value`,
    expected: [{single_value: 'ABC日😀', double_value: 'ABC日😀'}],
    columns: ['single_value', 'double_value'].map(name => ({name,
      contract: {type: 'string', nullable: false, max_utf8_bytes: 10}})),
    sourceReadCount: 0},
  {name: 'exact-string-values', format: 'sql',
    // SQL escapes and direct decomposed text are decoded once. Expected values
    // below are authored independently, including a literal backslash plus n.
    text: "SELECT '\\r' AS cr, '\\n' AS lf, '\\r\\n' AS crlf, 'é' AS composed, 'e\u0301' AS decomposed, '\\\\n' AS slash_n",
    expected: [{cr: '\r', lf: '\n', crlf: '\r\n', composed: 'é', decomposed: 'e\u0301', slash_n: '\\n'}],
    columns: [['cr', 1], ['lf', 1], ['crlf', 2], ['composed', 2],
      ['decomposed', 3], ['slash_n', 2]].map(([name, bytes]) => ({name,
        contract: {type: 'string', nullable: false, max_utf8_bytes: bytes}})),
    sourceReadCount: 0},
  {name: 'literal-values', format: 'sql',
    text: "SELECT 1 AS id, 'hello' AS label",
    expected: [{id: 1, label: 'hello'}], sourceReadCount: 0,
    columns: [numberColumn('id'), {name: 'label', contract: {type: 'string', nullable: false,
      // The authored ASCII literal has five UTF-8 bytes; its extent is exact.
      max_utf8_bytes: 5}}]},
  {name: 'machine-values-migration', format: 'sql',
    text: 'SELECT 1 AS id UNION ALL SELECT 2 AS id ORDER BY id',
    expected: [{id: 1}, {id: 2}], columns: [numberColumn('id')], sourceReadCount: 0},
  {name: 'source-free-duplicates', format: 'sql',
    text: 'SELECT 2 AS id UNION ALL SELECT 1 AS id UNION ALL SELECT 2 AS id ORDER BY id',
    expected: [{id: 1}, {id: 2}, {id: 2}], columns: [numberColumn('id')], sourceReadCount: 0},
  {name: 'source-free-null', format: 'sql',
    text: 'SELECT CAST(NULL AS STRING) AS label', expected: [{label: null}],
    columns: [{name: 'label', contract: {type: 'string', nullable: true}}], sourceReadCount: 0},
  {name: 'source-free-empty', format: 'sql',
    text: 'SELECT 1 AS id WHERE FALSE', expected: [], columns: [numberColumn('id')], sourceReadCount: 0},
  {name: 'source-free-parameter', format: 'sql', text: 'SELECT @minimum AS amount',
    parameterDeclarations: declarations, parameters: {minimum: 20},
    expected: [{amount: 20}], columns: [numberColumn('amount')], sourceReadCount: 0},
  {name: 'source-free-pipe', format: 'aql-text',
    text: 'SELECT 2 AS x |> WHERE x > 0 |> SET x = x + 1 |> SELECT x',
    expected: [{x: 3}], columns: [numberColumn('x')], sourceReadCount: 0},
  {name: 'source-free-count', format: 'sql', text: 'SELECT COUNT(*) AS n',
    expected: [{n: 1}], columns: [numberColumn('n')], sourceReadCount: 0},
  {name: 'source-free-cte', format: 'sql',
    text: 'WITH seed AS (SELECT 2 AS x |> WHERE x > 0 |> SELECT x) SELECT x FROM seed ORDER BY x',
    expected: [{x: 2}], columns: [numberColumn('x')], sourceReadCount: 0},
];
export const sourceFreeRefusals = [
  ...octalQuotes.flatMap(([name, quote]) => ['400', '777'].map(digits => ({
    name: `octal-range-${name}-${digits}`, format: 'sql',
    // A valid published source is present. Lexical refusal must still occur
    // before Run admission or physical acquisition of that source.
    text: `SELECT ${quote}\\${digits}${quote} AS s FROM records`,
  }))),
  ...['SELECT "\\uD800" AS s', 'SELECT "\\U00110000" AS s',
    'SELECT "\\x4" AS s', 'SELECT "\\12" AS s',
    'SELECT "memory"."main"."table"', 'SELECT r"odd\\" AS s',
    'SELECT """unfinished"" AS s', 'SELECT b"bytes" AS s',
    'SELECT "a""b" AS s', 'SELECT "a" b"b" AS s',
    'SELECT rb"bytes" AS s', 'SELECT """bad\\\nline""" AS s'].map((text, index) => ({
    name: `quoted-input-refusal-${index}`, format: 'sql', text})),
  // The selected source-free profile cannot expand star without a relation.
  // The existing check owner reports an implementation limit, not bad input.
  {name: 'source-free-star', format: 'sql', text: 'SELECT *',
    expectedCode: 'ClientProgramImplementationLimit'},
  {name: 'source-free-private-column', format: 'sql', text: 'SELECT aql_source_free_unit AS x'},
  {name: 'source-free-private-range', format: 'sql', text: 'SELECT aql_source_free.aql_source_free_unit AS x'},
  {name: 'source-free-sibling', format: 'sql', text: 'SELECT 1 AS x, x AS y'},
  {name: 'source-free-before-select', format: 'sql', text: 'SELECT 1 AS x WHERE x > 0'},
  {name: 'source-free-undeclared', format: 'sql', text: 'SELECT @p AS x'},
  {name: 'source-free-missing-value', format: 'sql', text: 'SELECT @minimum AS x', parameterDeclarations: declarations},
];
export const queryRefusals = [
  ...['aql-text', 'sql'].flatMap(format => [
    {name: `retired-envelope-${format}`, format,
      text: "-- prefix\nAQL '0.1'; PROGRAM 'old' { STAGE s { STEP {}; } }"},
    {name: `retired-program-${format}`, format, text: "PROGRAM 'old' {}"},
    {name: `retired-stage-${format}`, format, text: 'STAGE s { STEP {}; }'},
    {name: `retired-step-${format}`, format, text: 'STEP {};'},
    {name: `retired-op-${format}`, format, text: 'OP values {};'},
  ]),
  {name: 'syntax', text: 'SELECT id FROM', format: 'sql'},
  {name: 'undeclared', text: 'SELECT id FROM records WHERE id = @p',
    format: 'sql'},
  {name: 'missing-value', text: querySuccesses[0].text, format: 'sql',
    parameterDeclarations: declarations},
  {name: 'wrong-type', text: querySuccesses[0].text, format: 'sql',
    parameterDeclarations: declarations, parameters: {minimum: 'secret-value'}},
  {name: 'missing-alias', text: 'SELECT id FROM unregistered', format: 'sql'},
  {name: 'wrong-language', text: 'FROM records |> SELECT id', format: 'sql'},
];
// This Host installs no ModelTask. Valid INFER syntax cannot grant a missing
// installation; scope/name failures are separate pre-admission refusals.
export const inferRefusals = [
  {name: 'infer-missing-model-task', format: 'aql-text',
    text: 'FROM records |> INFER `model-task:risk.v1` ITEM KEY (id) '
      + 'INPUT (n = amount) KEEP (id) AS assessment'},
  {name: 'infer-omitted-keep-missing-model-task', format: 'aql-text',
    text: 'FROM records |> INFER `model-task:risk.v1` ITEM KEY (id) '
      + 'INPUT (n = amount) AS assessment'},
  {name: 'infer-removed-alias', format: 'aql-text',
    text: 'FROM records AS old |> INFER score ITEM KEY (id) INPUT (n = amount) '
      + 'KEEP (id) AS assessment |> SELECT old.amount'},
  {name: 'infer-output-collision', format: 'aql-text',
    text: 'FROM records |> INFER score ITEM KEY (id) INPUT (n = amount) '
      + 'KEEP (id AS assessment) AS assessment'},
];
const inputCodes = new Set(['ClientProgramInvalidInput',
  'ClientParametersInvalid', 'ClientParametersTooLarge',
  'ClientProgramUnsupported', 'ClientProgramNeedsInputs',
  'ClientProgramRejected']);

// Public text without an explicit RESULT exports main. Explicit text names
// belong to authored fixture metadata; structured Programs retain their own
// declared exports. None of these names comes from a product reply.
export function publicQueryResultOracles(item, primaryResultName = 'main') {
  if (item.results !== undefined) return item.results;
  let resultName = item.resultName;
  if (resultName === undefined && ['json', 'aql-json'].includes(item.format)) {
    const names = Object.keys(JSON.parse(item.text).results ?? {});
    assert.equal(names.length, 1,
      'A structured fixture with multiple exports requires authored result oracles');
    [resultName] = names;
  }
  resultName ??= primaryResultName;
  assert.equal(typeof resultName, 'string');
  assert.ok(resultName.length > 0);
  return {[resultName]: {rows: item.expected, columns: item.columns}};
}

// Run this unchanged with installed Local and HTTP connect options. The test
// owner supplies cumulative observations of real Run admission and source
// I/O, not a replacement provider or a Client-side alias map. This function
// does not lower source, manufacture schema, or call a test compiler bridge.
export async function exercisePublicQueryInput(connect, options,
  {requestPrefix, observe, successes = querySuccesses, primaryResultName = 'main',
    refusals = queryRefusals, executionFailures = [], prepareCase, persistSubmission, completedCase, completedRefusal}) {
  assert.equal(typeof observe, 'function');
  const counters = async () => {
    const current = await observe();
    assert.ok(Number.isSafeInteger(current.acceptedRuns));
    assert.ok(Number.isSafeInteger(current.sourceIo));
    return {acceptedRuns: current.acceptedRuns, sourceIo: current.sourceIo,
      ...(current.sourceReads === undefined ? {} : {sourceReads: current.sourceReads}),
      ...(current.sourceReadSessions === undefined ? {} : {sourceReadSessions: current.sourceReadSessions})};
  };
  const client = await connect(options);
  try {
    for (const item of successes) {
      const {name, text, expected, columns, results, resultName, sourceRows,
        sourceReadCount, sourceReadSessionCount, ...input} = item;
      await prepareCase?.(sourceRows);
      const requestId = requestPrefix + '-' + name;
      const submissionRef = client.newSubmission({nonce: requestId});
      await persistSubmission?.({name, submissionRef});
      const beforeSubmit = await counters();
      const execution = await client.startSource(text, {...input, submissionRef});
      const state = await execution.wait();
      assert.equal(state.status, 'succeeded', JSON.stringify({name, state}));
      const beforeRead = await counters();
      if (sourceReadCount !== undefined) {
        assert.equal(beforeRead.sourceReads - beforeSubmit.sourceReads, sourceReadCount,
          'physical source row scan count: ' +
            JSON.stringify((await observe()).sourceReadCommands));
      }
      if (sourceReadSessionCount !== undefined) {
        assert.equal(beforeRead.sourceReadSessions - beforeSubmit.sourceReadSessions,
          sourceReadSessionCount, 'one acquisition session per authored source: ' +
            JSON.stringify((await observe()).sourceReadCommands));
      }
      const expectedResults = publicQueryResultOracles(item, primaryResultName);
      const compare = (actual, expected, unordered) => {
        // An unordered SQL Relation is compared as a multiset. Sorting this
        // test copy preserves duplicates and never changes the product output.
        const canonicalRow = value => Array.isArray(value)
          ? '[' + value.map(canonicalRow).join(',') + ']'
          : value !== null && typeof value === 'object'
            ? '{' + Object.keys(value).sort().map(key =>
              JSON.stringify(key) + ':' + canonicalRow(value[key])).join(',') + '}'
            : JSON.stringify(value);
        if (unordered) assert.deepEqual(actual.map(canonicalRow).sort(),
          expected.map(canonicalRow).sort());
        else assert.deepEqual(actual, expected);
      };
      const observedResults = Object.create(null);
      for (const [resultName, result] of Object.entries(expectedResults)) {
        const rows = await execution.result(resultName).all();
        compare(rows, result.rows, result.unordered);
        observedResults[resultName] = {rows};
        if (result.columns !== undefined) {
          const columns = (await execution.result(resultName).describe()).columns;
          assert.deepEqual(columns,
            result.columns, 'retained column order and contracts match the authored fixture');
          observedResults[resultName].columns = columns;
        }
      }
      const attached = await client.attach(execution.ref);
      for (const [resultName, result] of Object.entries(expectedResults)) {
        compare(await attached.result(resultName).all(), result.rows, result.unordered);
      }
      const resent = await client.startSource(text, {...input, submissionRef});
      assert.deepEqual(resent.ref, execution.ref);
      const lookup = await client.lookupSubmission(submissionRef);
      assert.equal(lookup.kind, 'ready');
      assert.deepEqual(lookup.submissionRef, submissionRef);
      assert.deepEqual(lookup.admission.ref, execution.ref);
      const afterReplay = await counters();
      assert.deepEqual(afterReplay, beforeRead,
        'reading, attaching and resending must not accept or acquire again');
      await completedCase?.({name, ref: execution.ref, submissionRef, execution, expected, columns,
        beforeSubmit, beforeRead, afterReplay, observedResults});
      console.log(`Public query passed: ${requestPrefix}/${name}`);
      if (name === 'sql') {
        assert.equal(Object.keys(expectedResults).length, 1);
        await assert.rejects(execution.result(Object.keys(expectedResults)[0]).all({maxRows: 1}),
          {code: 'ResultRetainedLimit'});
        const attemptId = requestId + '-changed-intent';
        const expectedAttemptRef = {operation: 'submit', attemptId};
        await assert.rejects(client.startSource(text, {...input, submissionRef,
          parameters: {minimum: 21}, attemptId}), error => {
          assert.equal(error.code, 'SubmissionConflict');
          assert.equal(error.cause, undefined);
          assert.deepEqual(error.submissionRef, submissionRef);
          assert.deepEqual(error.attemptRef, expectedAttemptRef);
          // The SDK exposes this validated invocation attempt on the error.
          // Its identity is authored above, independently of the returned reply.
          const attempt = error.outcome;
          assert.equal(attempt.kind, 'conflict');
          assert.equal(attempt.reason, 'intent');
          assert.deepEqual(attempt.attemptRef, expectedAttemptRef);
          assert.deepEqual(attempt.submissionRef, submissionRef);
          assert.equal(attempt.outcome, undefined);
          assert.ok(Object.isFrozen(attempt));
          return true;
        });
        assert.equal((await execution.status()).status, 'succeeded');
        assert.deepEqual(await client.lookupSubmission(submissionRef), lookup,
          'a conflicting invocation must preserve the original submission');
        assert.deepEqual(await counters(), beforeRead,
          'a conflicting invocation must not accept another Run or acquire source');
      }
    }
    for (const {name, text, resultNames, sourceRows, sourceReadSessionCount, ...input} of executionFailures) {
      await prepareCase?.(sourceRows);
      const requestId = requestPrefix + '-execution-failure-' + name;
      const submissionRef = client.newSubmission({nonce: requestId});
      const beforeSubmit = await counters();
      const execution = await client.startSource(text, {...input, submissionRef});
      const state = await execution.wait({signal: AbortSignal.timeout(60_000)});
      assert.equal(state.status, 'failed', JSON.stringify({name, state}));
      const beforeRead = await counters();
      assert.equal(beforeRead.acceptedRuns - beforeSubmit.acceptedRuns, 1);
      if (sourceReadSessionCount !== undefined) {
        assert.equal(beforeRead.sourceReadSessions - beforeSubmit.sourceReadSessions,
          sourceReadSessionCount);
      }
      for (const resultName of resultNames) {
        await assert.rejects(execution.result(resultName).all(), {code: 'ResultAccessDenied'});
        await assert.rejects(execution.result(resultName).describe(), {code: 'ResultAccessDenied'});
      }
      const attached = await client.attach(execution.ref);
      assert.equal((await attached.status()).status, 'failed');
      const resent = await client.startSource(text, {...input, submissionRef});
      assert.deepEqual(resent.ref, execution.ref);
      assert.equal((await resent.status()).status, 'failed');
      const lookup = await client.lookupSubmission(submissionRef);
      assert.equal(lookup.kind, 'ready');
      assert.deepEqual(lookup.submissionRef, submissionRef);
      assert.deepEqual(lookup.admission.ref, execution.ref);
      assert.deepEqual(await counters(), beforeRead,
        'failed Result reads, attach and resubmit must not recompute or acquire');
      console.log(`Public query execution failure passed: ${requestPrefix}/${name}`);
    }
    for (const {name, text, expectedCode, ...input} of refusals) {
      await prepareCase?.();
      const requestId = requestPrefix + '-reject-' + name;
      const submissionRef = client.newSubmission({nonce: requestId});
      const before = await counters();
      let outcome;
      await assert.rejects(client.startSource(text, {...input, submissionRef}), error => {
        assert.equal(error.code, 'SubmissionNotAccepted');
        outcome = error.outcome;
        assert.equal(outcome.kind, 'not_accepted');
        assert.deepEqual(outcome.submissionRef, submissionRef);
        if (expectedCode === undefined) {
          assert.ok(inputCodes.has(outcome.problem.code), JSON.stringify({name, code: outcome.problem.code}));
        } else {
          assert.equal(outcome.problem.code, expectedCode);
        }
        assert.ok(!String(error.message).includes('secret-value'));
        return true;
      }, `${requestPrefix}/${name}`);
      const afterRefusal = await counters();
      assert.deepEqual(afterRefusal, before,
        'rejected source must not accept a Run or perform source I/O');
      assert.deepEqual(await client.lookupSubmission(submissionRef), outcome);
      await completedRefusal?.({name, submissionRef, outcome, beforeSubmit: before, afterRefusal});
      if (expectedCode !== undefined) {
        console.log(`Public query refusal passed: ${requestPrefix}/${name} (${expectedCode}); no admission or source I/O`);
      }
    }
  } finally {
    await client.close();
  }
}

queryCompositionRefusals.push(...[
 ['old-receiver','SELECT old_r FROM (SELECT 7 AS id) l CROSS JOIN (FROM UNNEST([1,2]) old_r) r MAX_OUTPUT_ROWS 10'],
 ['scalar-star','SELECT r.* FROM (SELECT 7 AS id) l CROSS JOIN (FROM UNNEST([1,2]) old_r) r MAX_OUTPUT_ROWS 10'],
 ['duplicate-range','SELECT r AS value FROM (SELECT 7 AS id) r CROSS JOIN (FROM UNNEST([1,2]) old_r) r MAX_OUTPUT_ROWS 10'],
].map(([name,text])=>({name:'join-value-refusal-'+name,format:'sql',text,expectedCode:'ClientProgramInvalidInput'})));

// Bare ordinary range names are row objects, never same-named scalar columns
// in ON. The independent scalar-key JSON control remains executable.
export const joinOnColumnControl = {version:'actql/0.1',id:'fixture.join_on_column',
 stages:[{id:'main',inputs:{},steps:[
  {values:{schema:{l:{type:'number',nullable:false},id:{type:'number',nullable:false}},rows:[{l:1,id:2}]},as:'left'},
  {values:{schema:{id:{type:'number',nullable:false}},rows:[{id:1}]},as:'right'},
  {from:'left',join:{with:'right',kind:'inner',on:[{left:'l',right:'id'}],max_output_rows:10,select:{id:'left.id'}},as:'out'},
 ],results:{rows:{from:'out',fields:['id']}}}],results:{answer:{from:{stage:'main',result:'rows'}}}};
const joinOnCase=(name,text,id=2,format='sql')=>({name:'join-on-range-'+name,
 format,text,expected:[{id}],columns:[relationNumber('id')],sourceReadCount:0,sourceReadSessionCount:0});
queryCompositionSuccesses.push(
 joinOnCase('json-column-control',JSON.stringify(joinOnColumnControl),2,'json'),
 joinOnCase('qualified-left','SELECT l.id FROM (SELECT 1 AS l,2 AS id) l JOIN (SELECT 1 AS id) r ON l.l=r.id MAX_OUTPUT_ROWS 10'),
 joinOnCase('qualified-right','SELECT l.id FROM (SELECT 1 AS id) l JOIN (SELECT 1 AS r,2 AS id) r ON l.id=r.r MAX_OUTPUT_ROWS 10',1),
 joinOnCase('using-column','FROM (SELECT 1 AS l,2 AS id) l |> JOIN (SELECT 1 AS l) r USING(l) MAX_OUTPUT_ROWS 10 |> SELECT l.id',2,'aql-text'),
);
queryCompositionRefusals.push(...[
 ['left','sql','SELECT l.id FROM (SELECT 1 AS l,2 AS id) l JOIN (SELECT 1 AS id) r ON l=r.id MAX_OUTPUT_ROWS 10'],
 ['right-shared','sql','SELECT l AS row FROM (SELECT 1 AS id) l JOIN (SELECT 1 AS r,2 AS id) r ON l.id=r MAX_OUTPUT_ROWS 10'],
 ['quoted-cte','aql-text','WITH a AS (SELECT 1 AS l,2 AS id),b AS (SELECT 1 AS id) FROM a AS `L` |> JOIN b AS r ON `L`=r.id MAX_OUTPUT_ROWS 10 |> SELECT `L`.id'],
 ['acquired','sql','SELECT records.id FROM records JOIN (SELECT 1 AS id) r ON records=r.id MAX_OUTPUT_ROWS 10'],
].map(([name,format,text])=>({name:'join-on-range-refusal-'+name,format,text,expectedCode:'ClientProgramImplementationLimit'})));

// Grouping parentheses preserve the same common equality key mapping.
// NULL key rows do not match; duplicate keys retain all matching pairs.
export const parenthesizedJoinControl = {version:'actql/0.1',id:'fixture.parenthesized_join',
 stages:[{id:'main',inputs:{},steps:[
  {values:{schema:{id:{type:'number',nullable:true}},rows:[{id:2},{id:null},{id:1},{id:2}]},as:'left'},
  {values:{schema:{key:{type:'number',nullable:true},tag:{type:'number',nullable:false}},rows:[{key:2,tag:20},{key:null,tag:99},{key:2,tag:21},{key:3,tag:30}]},as:'right'},
  {from:'left',join:{with:'right',kind:'inner',on:[{left:'id',right:'key'}],max_output_rows:10,select:{id:'left.id',tag:'right.tag'}},as:'joined'},
  {from:'joined',sort:[{field:'tag',dir:'asc',nulls:'first'},{field:'id',dir:'asc',nulls:'first'}],as:'out'},
 ],results:{rows:{from:'out',fields:['id','tag']}}}],results:{answer:{from:{stage:'main',result:'rows'}}}};
// Explicit FLOAT64 NULLs match the independently declared Number control.
// Untyped NULL set inference is a separate retained frontend gap.
const parenthesizedLeft='SELECT 2 AS id UNION ALL SELECT CAST(NULL AS FLOAT64) UNION ALL SELECT 1 UNION ALL SELECT 2';
const parenthesizedRight='SELECT 2 AS key,20 AS tag UNION ALL SELECT CAST(NULL AS FLOAT64),99 UNION ALL SELECT 2,21 UNION ALL SELECT 3,30';
const parenthesizedJoinCase=(name,text,format='sql')=>({name:'join-parenthesized-'+name,format,text,
 expected:[{id:2,tag:20},{id:2,tag:20},{id:2,tag:21},{id:2,tag:21}],
 columns:[relationNumber('id',true),relationNumber('tag')],sourceReadCount:0,sourceReadSessionCount:0});
queryCompositionSuccesses.push(
 parenthesizedJoinCase('json-control',JSON.stringify(parenthesizedJoinControl),'json'),
 parenthesizedJoinCase('sql-null-duplicates',`SELECT l.id,r.tag FROM (${parenthesizedLeft}) l JOIN (${parenthesizedRight}) r ON (l.id)=((r.key)) MAX_OUTPUT_ROWS 10 ORDER BY tag,id`),
 parenthesizedJoinCase('pipe-conjunction',`FROM (${parenthesizedLeft}) l |> JOIN (${parenthesizedRight}) r ON (((l.id)=(r.key)) AND ((r.key)=((l.id)))) MAX_OUTPUT_ROWS 10 |> SELECT l.id,r.tag |> ORDER BY tag,id`,'aql-text'),
 {name:'join-parenthesized-quoted-cte',format:'aql-text',
  text:'WITH a AS (SELECT 1 AS id),b AS (SELECT 1 AS id) FROM a AS `L` |> JOIN b AS r ON ((`L`.id))=(r.id) MAX_OUTPUT_ROWS 10 |> SELECT `L`.id',
  expected:[{id:1}],columns:[relationNumber('id')],sourceReadCount:0,sourceReadSessionCount:0},
 {name:'join-parenthesized-scalar-receivers',format:'sql',
  text:'SELECT l AS value FROM (FROM UNNEST([1,2]) old_l) l JOIN (FROM UNNEST([2,3]) old_r) r ON ((l))=(r) MAX_OUTPUT_ROWS 10 ORDER BY value',
  expected:[{value:2}],columns:[relationNumber('value')],sourceReadCount:0,sourceReadSessionCount:0},
 {name:'join-parenthesized-acquired-source',format:'sql',
  text:'SELECT records.amount,records.id FROM records JOIN (SELECT 2 AS key UNION ALL SELECT 3) r ON ((records.id))=(r.key) MAX_OUTPUT_ROWS 10 ORDER BY id',
  expected:[{amount:20,id:2},{amount:30,id:3},{amount:30,id:3}],columns:[relationNumber('amount',true),relationNumber('id')],sourceReadSessionCount:1},
);
queryCompositionRefusals.push(...[
 ['ordinary-row','SELECT l.id FROM (SELECT 1 AS l,2 AS id) l JOIN (SELECT 1 AS id) r ON (l)=((r.id)) MAX_OUTPUT_ROWS 10'],
 ['arithmetic','SELECT l.id FROM (SELECT 1 AS id) l JOIN (SELECT 2 AS id) r ON (l.id+1)=(r.id) MAX_OUTPUT_ROWS 10'],
 ['acquired-row','SELECT records.id FROM records JOIN (SELECT 1 AS id) r ON ((records))=(r.id) MAX_OUTPUT_ROWS 10'],
].map(([name,text])=>({name:'join-parenthesized-refusal-'+name,format:'sql',text,expectedCode:'ClientProgramImplementationLimit'})));
