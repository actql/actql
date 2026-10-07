// Independent grouping keys, multiplicities and ordered type contracts.
// Nullable receivers and nullable fields join one NULL group; duplicates
// contribute separately to COUNT. No lowerer computes these expectations.
const number = {type: 'number', nullable: false};
const payload = {type: 'object', nullable: true,
  fields: {score: {...number, nullable: true}}};
const other = {type: 'object', nullable: false, fields: {score: number}};
const rows = [
  {id: 2, payload: {score: 10}, other: {score: 100}},
  {id: 1, payload: {score: 20}, other: {score: 200}},
  {id: 3, payload: null, other: {score: 300}},
  {id: 4, payload: {score: 20}, other: {score: 400}},
  {id: 5, payload: {score: null}, other: {score: 500}},
];
const parameterDeclarations = {a: payload, b: payload, c: payload,
  d: payload, e: payload, oa: other, ob: other, oc: other, od: other, oe: other};
const parameters = {a: {score: 10}, b: {score: 20}, c: null,
  d: {score: 20}, e: {score: null}, oa: {score: 100}, ob: {score: 200},
  oc: {score: 300}, od: {score: 400}, oe: {score: 500}};
const source = 'DATA objects = SELECT 2 AS id, @a AS payload, @oa AS other '
  + 'UNION ALL SELECT 1 AS id, @b AS payload, @ob AS other '
  + 'UNION ALL SELECT 3 AS id, @c AS payload, @oc AS other '
  + 'UNION ALL SELECT 4 AS id, @d AS payload, @od AS other '
  + 'UNION ALL SELECT 5 AS id, @e AS payload, @oe AS other; ';
const expected = [{score: null, n: 2}, {score: 10, n: 1}, {score: 20, n: 2}];
const columns = [{name: 'score', contract: {...number, nullable: true}},
  {name: 'n', contract: number}];
const json = {version: 'actql/0.1', id: 'fixture.group_property', stages: [
  {id: 'main', inputs: {}, steps: [
    {values: {schema: {id: number, payload, other}, rows}, as: 'objects'},
    {from: 'objects', derive: {key: {property: {name: 'score', value: {field: 'payload'}}}}},
    {group: {by: ['key'], aggregates: {n: {fn: 'count'}}}},
    {sort: [{field: 'key', dir: 'asc', nulls: 'first'}]},
    {select: [{score: 'key'}, 'n'], as: 'summary'},
  ], results: {rows: {from: 'summary', fields: ['score', 'n']}}},
], results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const aliasedColumns = [{name: 'bucket', contract: {...number, nullable: true}},
  {name: 'n', contract: number}];
const aliasedRows = [{bucket: null, n: 2}, {bucket: 10, n: 1}, {bucket: 20, n: 2}];
const aliasedJson = {version: 'actql/0.1', id: 'fixture.group_key_alias', stages: [
  {id: 'main', inputs: {}, steps: [
    {values: {schema: {id: number, payload, other}, rows}, as: 'objects'},
    {from: 'objects', derive: {key: {property: {name: 'score', value: {field: 'payload'}}}}},
    {group: {by: ['key'], aggregates: {n: {fn: 'count'}}}},
    {sort: [{field: 'key', dir: 'asc', nulls: 'first'}]},
    {select: [{bucket: 'key'}, 'n'], as: 'summary'},
  ], results: {rows: {from: 'summary', fields: ['bucket', 'n']}}},
], results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const groupingOnlyRows = [{score: null}, {score: 10}, {score: 20}];
const groupingOnlyColumns = [{name: 'score', contract: {...number, nullable: true}}];
const groupingOnlyJson = {version: 'actql/0.1', id: 'fixture.group_only', stages: [
  {id: 'main', inputs: {}, steps: [
    {values: {schema: {id: number, payload, other}, rows}, as: 'objects'},
    {from: 'objects', derive: {key: {property: {name: 'score', value: {field: 'payload'}}}}},
    {group: {by: ['key'], aggregates: {}}},
    {sort: [{field: 'key', dir: 'asc', nulls: 'first'}]},
    {select: [{score: 'key'}], as: 'summary'},
  ], results: {rows: {from: 'summary', fields: ['score']}}},
], results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const globalGroupingOnlyJson = {version: 'actql/0.1', id: 'fixture.global_group_only', stages: [
  {id: 'main', inputs: {}, steps: [
    {values: {schema: {id: number}, rows: []}, as: 'empty'},
    {from: 'empty', group: {by: [], aggregates: {}}},
    {derive: {marker: {literal: 1}}, as: 'global'},
  ], results: {rows: {from: 'global', fields: ['marker']}}},
], results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const text = (name, tail, extra = {}) => ({
  name: 'group-property-' + name, format: 'aql-text', text: source + tail,
  parameterDeclarations, parameters, expected, columns, sourceReadCount: 0,
  ...extra,
});
// Fixed shorthand expectations include cases where grouping-first and
// aggregate-first sorting would produce different public row orders.
export const pipeAggregateOrderSuccesses = [
  {name: 'group-property-shorthand-independent-json', format: 'json',
    text: JSON.stringify(aliasedJson), expected: aliasedRows, columns: aliasedColumns, sourceReadCount: 0},
  text('shorthand-default-null-duplicates',
    'FROM objects |> AGGREGATE COUNT(*) AS n GROUP AND ORDER BY payload.score AS bucket',
    {expected: aliasedRows, columns: aliasedColumns}),
  text('shorthand-group-null-suffix-alone',
    'FROM objects |> AGGREGATE COUNT(*) AS n GROUP BY payload.score AS bucket NULLS LAST',
    {expected: [{bucket: 10, n: 1}, {bucket: 20, n: 2}, {bucket: null, n: 2}], columns: aliasedColumns}),
  text('shorthand-explicit-desc-null-first',
    'FROM objects |> AGGREGATE COUNT(*) AS n GROUP AND ORDER BY payload.score AS bucket DESC NULLS FIRST',
    {expected: [{bucket: null, n: 2}, {bucket: 20, n: 2}, {bucket: 10, n: 1}], columns: aliasedColumns}),
  text('shorthand-group-before-aggregate',
    'FROM objects |> AGGREGATE COUNT(*) AS n DESC GROUP BY payload.score AS bucket ASC NULLS LAST',
    {expected: [{bucket: 10, n: 1}, {bucket: 20, n: 2}, {bucket: null, n: 2}], columns: aliasedColumns}),
  text('shorthand-computed-key-predicate-limit',
    'FROM objects |> AGGREGATE COUNT(*) AS n GROUP AND ORDER BY payload.score + 1 AS bucket DESC NULLS LAST |> WHERE bucket > 10 |> LIMIT 1',
    {expected: [{bucket: 21, n: 2}], columns: aliasedColumns}),
  text('shorthand-group-only-empty',
    'FROM objects |> WHERE FALSE |> AGGREGATE GROUP AND ORDER BY payload.score AS bucket',
    {expected: [], columns: [{name: 'bucket', contract: {...number, nullable: true}}]}),
  text('shorthand-repeated-key',
    'FROM objects |> AGGREGATE COUNT(*) AS n GROUP AND ORDER BY payload.score AS first DESC NULLS LAST, payload.score AS second',
    {expected: [{first: 20, second: 20, n: 2}, {first: 10, second: 10, n: 1}, {first: null, second: null, n: 2}],
      columns: [{name: 'first', contract: {...number, nullable: true}},
        {name: 'second', contract: {...number, nullable: true}}, {name: 'n', contract: number}]}),
  {name: 'group-property-shorthand-aggregate-only-suffix', format: 'aql-text',
    text: 'DATA samples = SELECT 2 AS x UNION ALL SELECT 1 AS x UNION ALL SELECT 2 AS x '
      + 'UNION ALL SELECT 3 AS x UNION ALL SELECT 2 AS x UNION ALL SELECT 1 AS x; '
      + 'FROM samples |> AGGREGATE COUNT(*) AS n DESC GROUP BY x',
    expected: [{x: 2, n: 3}, {x: 1, n: 2}, {x: 3, n: 1}],
    columns: [{name: 'x', contract: number}, {name: 'n', contract: number}], sourceReadCount: 0},
];
export const pipeAggregateOrderRefusals = [
  text('shorthand-aggregate-null-suffix-needs-direction',
    'FROM objects |> AGGREGATE COUNT(*) AS n NULLS FIRST GROUP BY id'),
  text('shorthand-sql-placement', 'SELECT id FROM objects GROUP AND ORDER BY id'),
  text('shorthand-malformed-null-order',
    'FROM objects |> AGGREGATE COUNT(*) AS n GROUP BY id ASC NULLS MIDDLE'),
  text('shorthand-removed-range',
    'FROM objects AS old |> AGGREGATE COUNT(*) AS n GROUP AND ORDER BY old.payload.score AS bucket |> SELECT old.payload.score'),
  text('shorthand-alias-collision',
    'FROM objects |> AGGREGATE COUNT(*) AS n GROUP AND ORDER BY id AS n'),
];
// Independently authored scalar-aggregate control and row/type expectations.
const scalarAggregateRows = [{bucket: null, n: 3}, {bucket: 10, n: 2}, {bucket: 20, n: 3}];
const scalarAggregateJson = {version: 'actql/0.1', id: 'fixture.pipe_aggregate_expression', stages: [
  {id: 'main', inputs: {}, steps: [
    {values: {schema: {id: number, payload, other}, rows}, as: 'objects'},
    {from: 'objects', derive: {key: {property: {name: 'score', value: {field: 'payload'}}}}},
    {group: {by: ['key'], aggregates: {count: {fn: 'count'}}}},
    {derive: {next: {add: [{field: 'count'}, {literal: 1}]}}},
    {select: [{bucket: 'key'}, {n: 'next'}]},
    {sort: [{field: 'bucket', dir: 'asc', nulls: 'first'}]},
    {select: ['bucket', 'n'], as: 'summary'},
  ], results: {rows: {from: 'summary', fields: ['bucket', 'n']}}},
], results: {answer: {from: {stage: 'main', result: 'rows'}}}};
export const pipeAggregateExpressionSuccesses = [
  {name: 'group-property-scalar-independent-json', format: 'json', text: JSON.stringify(scalarAggregateJson),
    expected: scalarAggregateRows, columns: aliasedColumns, sourceReadCount: 0},
  text('scalar-null-duplicates',
    'FROM objects |> AGGREGATE COUNT(*) + 1 AS n GROUP AND ORDER BY payload.score AS bucket',
    {expected: scalarAggregateRows, columns: aliasedColumns}),
  text('scalar-repeated-calls',
    'FROM objects |> AGGREGATE COUNT(*) + COUNT(*) AS n GROUP AND ORDER BY payload.score AS bucket',
    {expected: [{bucket: null, n: 4}, {bucket: 10, n: 2}, {bucket: 20, n: 4}], columns: aliasedColumns}),
  text('scalar-key-property-preserves-null',
    'FROM objects |> AGGREGATE COUNT(*) + objects.payload.score AS n GROUP AND ORDER BY payload.score AS bucket',
    {expected: [{bucket: null, n: null}, {bucket: 10, n: 11}, {bucket: 20, n: 22}],
      columns: [aliasedColumns[0], {name: 'n', contract: {...number, nullable: true}}]}),
  text('scalar-key-expression-reuse',
    'FROM objects |> AGGREGATE COUNT(*) + (objects.payload.score + 1) AS n GROUP AND ORDER BY payload.score + 1 AS bucket',
    {expected: [{bucket: null, n: null}, {bucket: 11, n: 12}, {bucket: 21, n: 23}],
      columns: [aliasedColumns[0], {name: 'n', contract: {...number, nullable: true}}]}),
  text('scalar-input-output-collision',
    'FROM objects |> AGGREGATE COUNT(*) + id AS id GROUP AND ORDER BY id AS original',
    {expected: [1, 2, 3, 4, 5].map(original => ({original, id: original + 1})),
      columns: [{name: 'original', contract: number}, {name: 'id', contract: number}]}),
  text('scalar-atomic-input-output-collision',
    'FROM objects |> AGGREGATE COUNT(*) AS id GROUP AND ORDER BY id AS original',
    {expected: [1, 2, 3, 4, 5].map(original => ({original, id: 1})),
      columns: [{name: 'original', contract: number}, {name: 'id', contract: number}]}),
  text('scalar-predicate-limit',
    'FROM objects |> AGGREGATE COUNT(*) + 1 AS n DESC GROUP BY payload.score AS bucket DESC NULLS LAST |> WHERE n > 2 |> LIMIT 1',
    {expected: [{bucket: 20, n: 3}], columns: aliasedColumns}),
  text('scalar-empty-global',
    'FROM objects |> WHERE FALSE |> AGGREGATE COALESCE(SUM(id), 0) + 1 AS n',
    {expected: [{n: 1}], columns: [{name: 'n', contract: number}]}),
  text('scalar-empty-keyed',
    'FROM objects |> WHERE FALSE |> AGGREGATE COUNT(*) + 1 AS n GROUP BY id AS original',
    {expected: [], columns: [{name: 'original', contract: number}, {name: 'n', contract: number}]}),
];
export const pipeAggregateExpressionRefusals = [
  text('scalar-ungrouped-input', 'FROM objects |> AGGREGATE COUNT(*) + id AS n'),
  text('scalar-sibling-alias', 'FROM objects |> AGGREGATE COUNT(*) AS n, COUNT(*) + n AS next'),
  text('scalar-key-alias-is-not-input', 'FROM objects |> AGGREGATE COUNT(*) + bucket AS n GROUP BY id AS bucket'),
  text('scalar-removed-range', 'FROM objects AS old |> AS current |> AGGREGATE COUNT(*) + old.id AS n GROUP BY current.id'),
  text('scalar-nonaggregate', 'FROM objects |> AGGREGATE id + 1 AS n'),
  text('scalar-missing-output-name', 'FROM objects |> AGGREGATE COUNT(*) + 1'),
  text('scalar-window', 'FROM objects |> AGGREGATE COUNT(*) OVER () AS n'),
];
// SQL SELECT uses evaluated group keys inside scalar trees; JSON controls are
// authored independently and retain SQL NULLs, multiplicity and declared types.
const sqlGroupedRows = [{bucket: null, n: null}, {bucket: 11, n: 12}, {bucket: 21, n: 23}];
const sqlGroupedColumns = [{name: 'bucket', contract: {...number, nullable: true}},
  {name: 'n', contract: {...number, nullable: true}}];
const sqlGroupedJson = {version: 'actql/0.1', id: 'fixture.sql_grouped_subexpression', stages: [
  {id: 'main', inputs: {}, steps: [
    {values: {schema: {id: number, payload, other}, rows}, as: 'objects'},
    {from: 'objects', derive: {key: {add: [{property: {name: 'score', value: {field: 'payload'}}}, {literal: 1}]}}},
    {group: {by: ['key'], aggregates: {count: {fn: 'count'}}}},
    {derive: {next: {add: [{field: 'count'}, {field: 'key'}]}}},
    {select: [{bucket: 'key'}, {n: 'next'}]},
    {sort: [{field: 'bucket', dir: 'asc', nulls: 'first'}], as: 'grouped'},
  ], results: {rows: {from: 'grouped', fields: ['bucket', 'n']}}},
], results: {answer: {from: {stage: 'main', result: 'rows'}}}};
export const sqlGroupedSubexpressionSuccesses = [
  {name: 'group-property-sql-subexpression-independent-json', format: 'json', text: JSON.stringify(sqlGroupedJson),
    expected: sqlGroupedRows, columns: sqlGroupedColumns, sourceReadCount: 0},
  text('sql-subexpression-computed-key',
    'SELECT payload.score + 1 AS bucket, COUNT(*) + (objects.payload.score + 1) AS n FROM objects GROUP BY payload.score + 1 ORDER BY bucket',
    {expected: sqlGroupedRows, columns: sqlGroupedColumns}),
  text('sql-subexpression-property-key',
    'SELECT payload.score AS bucket, COUNT(*) + objects.payload.score AS n FROM objects GROUP BY payload.score ORDER BY bucket',
    {expected: [{bucket: null, n: null}, {bucket: 10, n: 11}, {bucket: 20, n: 22}], columns: sqlGroupedColumns}),
  text('sql-subexpression-alias-input-collision',
    'SELECT payload.score + 1 AS payload, COUNT(*) + (objects.payload.score + 1) AS n FROM objects GROUP BY objects.payload.score + 1 ORDER BY payload NULLS LAST',
    {expected: [{payload: 11, n: 12}, {payload: 21, n: 23}, {payload: null, n: null}],
      columns: [{name: 'payload', contract: {...number, nullable: true}}, sqlGroupedColumns[1]]}),
  text('sql-subexpression-predicate-limit',
    'SELECT payload.score + 1 AS bucket, COUNT(*) + (objects.payload.score + 1) AS n FROM objects WHERE id < 5 GROUP BY payload.score + 1 HAVING n > 11 ORDER BY bucket DESC NULLS LAST LIMIT 1',
    {expected: [{bucket: 21, n: 23}], columns: sqlGroupedColumns}),
  text('sql-subexpression-join-input',
    'SELECT objects.payload.score + 1 AS bucket, COUNT(*) + (objects.payload.score + 1) AS n FROM objects JOIN objects AS matched ON objects.id = matched.id MAX_OUTPUT_ROWS 10 GROUP BY objects.payload.score + 1 ORDER BY bucket',
    {expected: sqlGroupedRows, columns: sqlGroupedColumns}),
  text('sql-subexpression-cte-input',
    'WITH summary AS (SELECT payload.score + 1 AS bucket, COUNT(*) + (objects.payload.score + 1) AS n FROM objects GROUP BY payload.score + 1) SELECT bucket, n FROM summary ORDER BY bucket',
    {expected: sqlGroupedRows, columns: sqlGroupedColumns}),
  text('sql-subexpression-empty-keyed',
    'SELECT payload.score + 1 AS bucket, COUNT(*) + (objects.payload.score + 1) AS n FROM objects WHERE FALSE GROUP BY payload.score + 1 ORDER BY bucket',
    {expected: [], columns: sqlGroupedColumns}),
  text('sql-subexpression-repeated-key',
    'SELECT payload.score + 1 AS bucket, COUNT(*) + (payload.score + 1) + (objects.payload.score + 1) AS n FROM objects GROUP BY payload.score + 1 ORDER BY bucket',
    {expected: [{bucket: null, n: null}, {bucket: 11, n: 23}, {bucket: 21, n: 44}], columns: sqlGroupedColumns}),
];
export const sqlGroupedSubexpressionRefusals = [
  text('sql-subexpression-ungrouped-receiver',
    'SELECT COUNT(*) + objects.other.score AS n FROM objects GROUP BY payload.score'),
  text('sql-subexpression-key-does-not-revive-receiver',
    'SELECT COUNT(*) + payload.score AS n FROM objects GROUP BY payload.score + 1'),
  text('sql-subexpression-sibling-alias',
    'SELECT payload.score + 1 AS bucket, COUNT(*) + bucket AS n FROM objects GROUP BY payload.score + 1'),
  text('sql-subexpression-missing-range',
    'SELECT COUNT(*) + old.payload.score AS n FROM objects AS current GROUP BY current.payload.score'),
];
export const groupPropertySuccesses = [
  ...sqlGroupedSubexpressionSuccesses,
  ...pipeAggregateExpressionSuccesses,
  ...pipeAggregateOrderSuccesses,
  {name: 'group-property-key-alias-independent-json', format: 'json',
    text: JSON.stringify(aliasedJson), expected: aliasedRows, columns: aliasedColumns, sourceReadCount: 0},
  text('key-alias-explicit-null-duplicates',
    'FROM objects |> AGGREGATE COUNT(*) AS n GROUP BY payload.score AS bucket |> ORDER BY bucket NULLS FIRST',
    {expected: aliasedRows, columns: aliasedColumns}),
  text('key-alias-implicit-quoted',
    'FROM objects |> AGGREGATE COUNT(*) AS n GROUP BY payload.score `GROUP` |> ORDER BY `GROUP` NULLS FIRST',
    {expected: [{GROUP: null, n: 2}, {GROUP: 10, n: 1}, {GROUP: 20, n: 2}],
      columns: [{name: 'GROUP', contract: {...number, nullable: true}}, {name: 'n', contract: number}]}),
  text('key-alias-group-only-empty',
    'FROM objects |> WHERE FALSE |> AGGREGATE GROUP BY payload.score AS bucket |> ORDER BY bucket',
    {expected: [], columns: [{name: 'bucket', contract: {...number, nullable: true}}]}),
  text('key-alias-sibling-input-scope',
    'FROM objects |> AGGREGATE COUNT(*) AS n GROUP BY payload.score AS id, id AS original_id |> ORDER BY original_id',
    {expected: [{id: 20, original_id: 1, n: 1}, {id: 10, original_id: 2, n: 1},
      {id: null, original_id: 3, n: 1}, {id: 20, original_id: 4, n: 1},
      {id: null, original_id: 5, n: 1}],
      columns: [{name: 'id', contract: {...number, nullable: true}}, {name: 'original_id', contract: number},
        {name: 'n', contract: number}]}),
  text('key-alias-repeated-physical-key',
    'FROM objects |> AGGREGATE COUNT(*) AS n GROUP BY payload.score AS first, payload.score AS second |> ORDER BY first NULLS FIRST',
    {expected: [{first: null, second: null, n: 2}, {first: 10, second: 10, n: 1}, {first: 20, second: 20, n: 2}],
      columns: [{name: 'first', contract: {...number, nullable: true}},
        {name: 'second', contract: {...number, nullable: true}}, {name: 'n', contract: number}]}),
  text('key-alias-set-retained-input',
    'FROM objects AS before |> SET payload = other |> AGGREGATE COUNT(*) AS n GROUP BY before.payload.score AS bucket |> ORDER BY bucket NULLS FIRST',
    {expected: aliasedRows, columns: aliasedColumns}),
  text('key-alias-computed-predicate-limit',
    'FROM objects |> AGGREGATE COUNT(*) AS n GROUP BY payload.score + 1 AS bucket |> WHERE bucket > 15 |> ORDER BY bucket |> LIMIT 1',
    {expected: [{bucket: 21, n: 2}], columns: aliasedColumns}),
  {name: 'group-property-group-only-global-independent-json', format: 'json',
    text: JSON.stringify(globalGroupingOnlyJson), expected: [{marker: 1}], columns: [{name: 'marker', contract: number}], sourceReadCount: 0},
  text('group-only-global-nonempty', 'FROM objects |> AGGREGATE GROUP BY () |> EXTEND 1 AS marker',
    {expected: [{marker: 1}], columns: [{name: 'marker', contract: number}]}),
  text('group-only-global-empty', 'FROM objects |> WHERE FALSE |> AGGREGATE GROUP BY () |> EXTEND 1 AS marker',
    {expected: [{marker: 1}], columns: [{name: 'marker', contract: number}]}),
  {name: 'group-property-group-only-independent-json', format: 'json',
    text: JSON.stringify(groupingOnlyJson), expected: groupingOnlyRows,
    columns: groupingOnlyColumns, sourceReadCount: 0},
  text('group-only-null-and-duplicate-keys',
    'FROM objects |> AGGREGATE GROUP BY payload.score |> ORDER BY score NULLS FIRST',
    {expected: groupingOnlyRows, columns: groupingOnlyColumns}),
  text('group-only-post-group-predicate-limit',
    'FROM objects AS original |> AGGREGATE GROUP BY original.payload.score '
      + '|> WHERE score > 10 |> ORDER BY score DESC |> LIMIT 1',
    {expected: [{score: 20}], columns: groupingOnlyColumns}),
  text('group-only-empty-typed-groups',
    'FROM objects |> WHERE FALSE |> AGGREGATE GROUP BY payload.score |> ORDER BY score',
    {expected: [], columns: groupingOnlyColumns}),
  text('group-only-column-order',
    'FROM objects |> AGGREGATE GROUP BY id, payload.score |> ORDER BY id',
    {expected: [{id: 1, score: 20}, {id: 2, score: 10}, {id: 3, score: null},
      {id: 4, score: 20}, {id: 5, score: null}],
    columns: [{name: 'id', contract: number}, ...groupingOnlyColumns]}),
  {name: 'group-property-independent-json', format: 'json',
    text: JSON.stringify(json), expected, columns, sourceReadCount: 0},
  text('sql-null-and-duplicate-keys',
    'SELECT payload.score AS score, COUNT(*) AS n FROM objects GROUP BY payload.score ORDER BY score NULLS FIRST'),
  text('sql-qualified-key-reuse',
    'SELECT objects.payload.score AS score, COUNT(*) AS n FROM objects GROUP BY payload.score HAVING score IS NOT NULL ORDER BY score',
    {expected: [{score: 10, n: 1}, {score: 20, n: 2}]}),
  text('pipe-qualified-key',
    'FROM objects AS before |> AGGREGATE COUNT(*) AS n GROUP BY before.payload.score |> ORDER BY score NULLS FIRST'),
  text('pipe-set-retained-receiver',
    'FROM objects AS before |> SET payload = other |> AGGREGATE COUNT(*) AS n GROUP BY before.payload.score |> ORDER BY score NULLS FIRST'),
  text('pipe-set-current-receiver',
    'FROM objects AS before |> SET payload = other |> AGGREGATE COUNT(*) AS n GROUP BY payload.score |> ORDER BY score',
    {expected: [{score: 100, n: 1}, {score: 200, n: 1}, {score: 300, n: 1},
      {score: 400, n: 1}, {score: 500, n: 1}],
    columns: [{name: 'score', contract: number}, {name: 'n', contract: number}]}),
  text('empty-typed-groups',
    'SELECT payload.score AS score, COUNT(*) AS n FROM objects WHERE id > 99 GROUP BY score ORDER BY score',
    {expected: []}),
  text('parameter-predicate-limit',
    'SELECT `objects`.`payload`.`score` AS score, COUNT(*) AS n FROM objects WHERE id > @cut GROUP BY 1 ORDER BY score NULLS LAST LIMIT 2 OFFSET 1',
    {parameterDeclarations: {...parameterDeclarations, cut: number},
      parameters: {...parameters, cut: 1}, expected: [{score: 20, n: 1}, {score: null, n: 2}]}),
  text('member-parenthesized',
    'FROM objects |> AGGREGATE COUNT(*) AS n GROUP BY (payload).score |> ORDER BY score NULLS FIRST'),
  text('member-quoted-receiver',
    'FROM objects AS before |> AGGREGATE COUNT(*) AS n GROUP BY (before.`payload`).`score` |> ORDER BY score NULLS FIRST'),
  text('member-computed-receiver',
    'FROM objects |> AGGREGATE COUNT(*) AS n GROUP BY (IF(TRUE, payload, NULL)).score |> ORDER BY score NULLS FIRST'),
  text('member-set-retained-receiver',
    'FROM objects AS before |> SET payload = other |> AGGREGATE COUNT(*) AS n GROUP BY (before.payload).score |> ORDER BY score NULLS FIRST'),
  text('member-set-current-receiver',
    'FROM objects AS before |> SET payload = other |> AGGREGATE COUNT(*) AS n GROUP BY (payload).score |> ORDER BY score',
    {expected: [{score: 100, n: 1}, {score: 200, n: 1}, {score: 300, n: 1},
      {score: 400, n: 1}, {score: 500, n: 1}],
    columns: [{name: 'score', contract: number}, {name: 'n', contract: number}]}),
  text('member-post-group-predicate-limit',
    'FROM objects |> AGGREGATE COUNT(*) AS n GROUP BY (payload).score '
      + '|> WHERE score > 10 |> ORDER BY score DESC |> LIMIT 1 |> SELECT score, n',
    {expected: [{score: 20, n: 2}]}),
  text('member-empty-typed-groups',
    'FROM objects |> WHERE FALSE |> AGGREGATE COUNT(*) AS n GROUP BY (payload).score |> ORDER BY score NULLS FIRST',
    {expected: []}),
];
export const groupPropertyRefusals = [
  'FROM objects |> AGGREGATE COUNT(*) AS n GROUP BY payload.score AS n',
  'FROM objects |> AGGREGATE COUNT(*) AS n GROUP BY payload.score AS bucket, id AS `BUCKET`',
  'FROM objects |> AGGREGATE COUNT(*) AS n GROUP BY payload.score AS bucket |> SELECT score',
  'FROM objects AS old |> AGGREGATE COUNT(*) AS n GROUP BY old.payload.score AS bucket |> SELECT old.payload.score',

  'FROM objects AS original |> AGGREGATE GROUP BY original.payload.score |> SELECT original.payload.score',
  'FROM objects |> AGGREGATE',
  'SELECT payload AS value, COUNT(*) AS n FROM objects GROUP BY payload.score',
  'SELECT other.score AS score, COUNT(*) AS n FROM objects GROUP BY payload.score',
  'FROM objects AS old |> AS current |> AGGREGATE COUNT(*) AS n GROUP BY old.payload.score',
  'SELECT COUNT(*) AS n FROM objects GROUP BY payload.missing',
  'SELECT COUNT(*) AS n FROM objects GROUP BY id.score',
  'FROM objects |> AGGREGATE COUNT(*) AS score GROUP BY (payload).score',
  'FROM objects |> AGGREGATE COUNT(*) AS n GROUP BY (payload).score, (other).score',
  'FROM objects AS old |> AS current |> AGGREGATE COUNT(*) AS n GROUP BY (old.payload).score',
  'FROM objects AS old |> AGGREGATE COUNT(*) AS n GROUP BY (old.payload).score |> SELECT old.payload.score',
].map((tail, index) => ({name: 'group-property-invalid-' + index,
  format: 'aql-text', text: source + tail, parameterDeclarations, parameters})).concat(pipeAggregateOrderRefusals, pipeAggregateExpressionRefusals, sqlGroupedSubexpressionRefusals);
