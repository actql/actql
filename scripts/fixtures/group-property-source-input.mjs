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
const source = 'WITH objects AS (SELECT 2 AS id, @a AS payload, @oa AS other '
  + 'UNION ALL SELECT 1 AS id, @b AS payload, @ob AS other '
  + 'UNION ALL SELECT 3 AS id, @c AS payload, @oc AS other '
  + 'UNION ALL SELECT 4 AS id, @d AS payload, @od AS other '
  + 'UNION ALL SELECT 5 AS id, @e AS payload, @oe AS other) ';
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
// Implicit leaf names survive GROUP even when the object receiver itself does
// not. The machine control above independently defines values, NULL groups,
// multiplicity and the checked column contracts.
export const groupedImplicitPropertyNameSuccesses = [
  {name: 'group-property-implicit-grouped-independent-json', format: 'json',
    text: JSON.stringify(json), expected, columns, sourceReadCount: 0},
  text('implicit-grouped-path',
    'SELECT payload.score, COUNT(*) AS n FROM objects GROUP BY payload.score ORDER BY score'),
  text('implicit-grouped-qualified-path',
    'SELECT objects.payload.score, COUNT(*) AS n FROM objects GROUP BY payload.score ORDER BY score'),
  text('implicit-grouped-quoted-spelling',
    'SELECT `objects`.`payload`.`SCORE`, COUNT(*) AS n FROM objects GROUP BY objects.payload.score ORDER BY `SCORE` NULLS LAST',
    {expected: [{SCORE: 10, n: 1}, {SCORE: 20, n: 2}, {SCORE: null, n: 2}],
      columns: [{name: 'SCORE', contract: {...number, nullable: true}}, columns[1]]}),
  text('implicit-grouped-qualify',
    'SELECT id, payload.score, COUNT(*) AS n, ROW_NUMBER() OVER (ORDER BY id) AS rank '
      + 'FROM objects GROUP BY id, payload.score QUALIFY score > 10 AND rank > 0 ORDER BY id',
    {expected: [{id: 1, score: 20, n: 1, rank: 1}, {id: 4, score: 20, n: 1, rank: 4}],
      columns: [{name: 'id', contract: number}, columns[0], columns[1],
        {name: 'rank', contract: number}]}),
  text('implicit-grouped-join-qualify',
    'SELECT l.id, l.payload.score, COUNT(*) AS n, ROW_NUMBER() OVER (ORDER BY l.id) AS rank '
      + 'FROM objects AS l JOIN objects AS r ON l.id = r.id MAX_OUTPUT_ROWS 10 '
      + 'GROUP BY l.id, l.payload.score QUALIFY score > 10 AND rank > 0 ORDER BY id',
    {expected: [{id: 1, score: 20, n: 1, rank: 1}, {id: 4, score: 20, n: 1, rank: 4}],
      columns: [{name: 'id', contract: number}, columns[0], columns[1],
        {name: 'rank', contract: number}]}),
  text('implicit-grouped-cte',
    '(WITH summary AS (SELECT payload.score, COUNT(*) AS n FROM objects GROUP BY payload.score) '
      + 'SELECT score, n FROM summary ORDER BY score)'),
  text('implicit-grouped-join',
    'SELECT l.payload.score, COUNT(*) AS n FROM objects AS l JOIN objects AS r '
      + 'ON l.id = r.id MAX_OUTPUT_ROWS 10 GROUP BY l.payload.score ORDER BY score'),
  text('implicit-grouped-predicate-parameter-limit',
    'SELECT payload.score, COUNT(*) AS n FROM objects WHERE id > @cut GROUP BY payload.score '
      + 'ORDER BY score DESC NULLS LAST LIMIT 1',
    {parameterDeclarations: {...parameterDeclarations, cut: number},
      parameters: {...parameters, cut: 1}, expected: [{score: 20, n: 1}]}),
  text('implicit-grouped-empty',
    'SELECT payload.score, COUNT(*) AS n FROM objects WHERE FALSE GROUP BY payload.score ORDER BY score',
    {expected: []}),
];
export const groupedImplicitPropertyNameRefusals = [
  text('implicit-grouped-key-does-not-restore-receiver',
    'SELECT payload, COUNT(*) AS n FROM objects GROUP BY payload.score'),
  text('implicit-grouped-key-does-not-restore-member',
    'SELECT payload.score, COUNT(*) AS n FROM objects GROUP BY payload.score + 1'),
  text('implicit-grouped-ungrouped-receiver',
    'SELECT other.score, COUNT(*) AS n FROM objects GROUP BY payload.score'),
  text('implicit-grouped-removed-range',
    'SELECT objects.payload.score, COUNT(*) AS n FROM objects AS current GROUP BY current.payload.score'),
  text('implicit-grouped-duplicate-leaf-name',
    'SELECT payload.score, other.score, COUNT(*) AS n FROM objects GROUP BY payload.score, other.score'),
].map(item => ({...item, expectedCode: 'ClientProgramInvalidInput'}));
// Explicit and implicit SELECT aliases use the same GROUP/HAVING scope.
// The two collision controls deliberately keep a qualified input whose values
// select the opposite row; no implementation output supplies these expectations.
const havingImplicitRows = [{score: 20, n: 2}];
const havingImplicitJson = {version: 'actql/0.1', id: 'fixture.having_implicit_alias', stages: [
  {id: 'main', inputs: {}, steps: [
    {values: {schema: {id: number, payload, other}, rows}, as: 'objects'},
    {from: 'objects', derive: {key: {property: {name: 'score', value: {field: 'payload'}}}}},
    {group: {by: ['key'], aggregates: {n: {fn: 'count'}}}},
    {filter: {gt: [{field: 'key'}, {literal: 10}]}},
    {sort: [{field: 'key', dir: 'asc', nulls: 'first'}]},
    {select: [{score: 'key'}, 'n'], as: 'summary'},
  ], results: {rows: {from: 'summary', fields: ['score', 'n']}}},
], results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const havingCollisionSource = 'WITH colliding AS (SELECT 1 AS id, 100 AS score, @a AS payload '
  + 'UNION ALL SELECT 2 AS id, 0 AS score, @b AS payload) ';
const havingCollisionRows = [
  {id: 1, score: 100, payload: {score: 10}},
  {id: 2, score: 0, payload: {score: 20}},
];
const havingCollisionJson = {version: 'actql/0.1', id: 'fixture.having_collision', stages: [
  {id: 'main', inputs: {}, steps: [
    {values: {schema: {id: number, score: number, payload}, rows: havingCollisionRows}, as: 'colliding'},
    {from: 'colliding', derive: {key: {property: {name: 'score', value: {field: 'payload'}}}}},
    {group: {by: ['key', 'score'], aggregates: {n: {fn: 'count'}}}},
    {filter: {gt: [{field: 'key'}, {literal: 10}]}},
    {sort: [{field: 'key', dir: 'asc', nulls: 'first'}]},
    {select: [{score: 'key'}, 'n'], as: 'summary'},
  ], results: {rows: {from: 'summary', fields: ['score', 'n']}}},
], results: {answer: {from: {stage: 'main', result: 'rows'}}}};
export const groupHavingImplicitAliasSuccesses = [
  {name: 'group-property-having-implicit-independent-json', format: 'json',
    text: JSON.stringify(havingImplicitJson), expected: havingImplicitRows, columns, sourceReadCount: 0},
  text('having-implicit-retained-key',
    'SELECT payload.score, COUNT(*) AS n FROM objects GROUP BY payload.score HAVING score > 10 ORDER BY score',
    {expected: havingImplicitRows}),
  text('having-implicit-group-alias',
    'SELECT payload.score, COUNT(*) AS n FROM objects GROUP BY score HAVING score + 1 > 11 ORDER BY score',
    {expected: havingImplicitRows}),
  text('having-implicit-qualified-projection',
    'SELECT objects.payload.score, COUNT(*) AS n FROM objects GROUP BY score HAVING score > 10 ORDER BY score',
    {expected: havingImplicitRows}),
  text('having-implicit-member',
    'SELECT (payload).score, COUNT(*) AS n FROM objects GROUP BY score HAVING score > 10 ORDER BY score',
    {expected: havingImplicitRows}),
  text('having-implicit-quoted-alias',
    'SELECT `objects`.`payload`.`score`, COUNT(*) AS n FROM objects GROUP BY `SCORE` HAVING `SCORE` > 10 ORDER BY score',
    {expected: havingImplicitRows}),
  text('having-implicit-hidden-count',
    'SELECT payload.score, COUNT(*) AS n FROM objects GROUP BY score HAVING COUNT(score) > 1 ORDER BY score',
    {expected: havingImplicitRows}),
  text('having-implicit-cte',
    '(WITH summary AS (SELECT payload.score, COUNT(*) AS n FROM objects GROUP BY score HAVING score > 10) '
      + 'SELECT score, n FROM summary ORDER BY score)', {expected: havingImplicitRows}),
  text('having-implicit-join',
    'SELECT l.payload.score, COUNT(*) AS n FROM objects AS l JOIN objects AS r '
      + 'ON l.id = r.id MAX_OUTPUT_ROWS 10 GROUP BY score HAVING score > 10 ORDER BY score',
    {expected: havingImplicitRows}),
  text('having-implicit-object-receiver',
    'SELECT payload.score + 1 AS bucket, (@wrapper).payload, COUNT(*) AS n FROM objects '
      + 'GROUP BY objects.payload.score + 1 HAVING payload.score + 1 > 12 ORDER BY bucket',
    {parameterDeclarations: {...parameterDeclarations,
      wrapper: {type: 'object', nullable: false, fields: {payload}}},
      parameters: {...parameters, wrapper: {payload: {score: 20}}},
      expected: [{bucket: null, payload: {score: 20}, n: 2},
        {bucket: 11, payload: {score: 20}, n: 1}, {bucket: 21, payload: {score: 20}, n: 2}],
      columns: [{name: 'bucket', contract: {...number, nullable: true}},
        {name: 'payload', contract: {...payload, additional_properties: false}}, columns[1]]}),
  text('having-implicit-object-qualified-control',
    'SELECT payload.score + 1 AS bucket, (@wrapper).payload, COUNT(*) AS n FROM objects '
      + 'GROUP BY objects.payload.score + 1 HAVING objects.payload.score + 1 > 12 ORDER BY bucket',
    {parameterDeclarations: {...parameterDeclarations,
      wrapper: {type: 'object', nullable: false, fields: {payload}}},
      parameters: {...parameters, wrapper: {payload: {score: 20}}},
      expected: [{bucket: 21, payload: {score: 20}, n: 2}],
      columns: [{name: 'bucket', contract: {...number, nullable: true}},
        {name: 'payload', contract: {...payload, additional_properties: false}}, columns[1]]}),
  text('having-implicit-empty',
    'SELECT payload.score, COUNT(*) AS n FROM objects WHERE FALSE GROUP BY score HAVING score > 10 ORDER BY score',
    {expected: []}),
  {name: 'group-property-having-implicit-collision-independent-json', format: 'json',
    text: JSON.stringify(havingCollisionJson), expected: [{score: 20, n: 1}], columns, sourceReadCount: 0},
  {name: 'group-property-having-implicit-collision-alias', format: 'aql-text',
    text: havingCollisionSource + 'SELECT payload.score, COUNT(*) AS n FROM colliding '
      + 'GROUP BY score, colliding.score HAVING score > 10 ORDER BY score',
    parameterDeclarations: {a: payload, b: payload},
    parameters: {a: parameters.a, b: parameters.b}, expected: [{score: 20, n: 1}], columns, sourceReadCount: 0},
  {name: 'group-property-having-implicit-collision-qualified-input', format: 'aql-text',
    text: havingCollisionSource + 'SELECT payload.score, COUNT(*) AS n FROM colliding '
      + 'GROUP BY score, colliding.score HAVING colliding.score > 10 ORDER BY score',
    parameterDeclarations: {a: payload, b: payload},
    parameters: {a: parameters.a, b: parameters.b}, expected: [{score: 10, n: 1}], columns, sourceReadCount: 0},
  {name: 'group-property-having-implicit-collision-where-input', format: 'aql-text',
    text: havingCollisionSource + 'SELECT payload.score, COUNT(*) AS n FROM colliding '
      + 'WHERE score > 10 GROUP BY score ORDER BY score',
    parameterDeclarations: {a: payload, b: payload},
    parameters: {a: parameters.a, b: parameters.b}, expected: [{score: 10, n: 1}], columns, sourceReadCount: 0},
];
export const groupHavingImplicitAliasRefusals = [
  text('having-implicit-ambiguous-group',
    'SELECT payload.score, other.score, COUNT(*) AS n FROM objects GROUP BY score'),
  text('having-implicit-ambiguous-having',
    'SELECT payload.score, other.score, COUNT(*) AS n FROM objects GROUP BY payload.score HAVING score > 10'),
  text('having-implicit-computed-key-does-not-restore-member',
    'SELECT payload.score, COUNT(*) AS n FROM objects GROUP BY payload.score + 1 HAVING score > 10'),
  text('having-implicit-removed-range',
    'SELECT payload.score, COUNT(*) AS n FROM objects AS current GROUP BY score HAVING objects.payload.score > 10'),
  text('having-implicit-ungrouped-receiver',
    'SELECT payload.score, COUNT(*) AS n FROM objects GROUP BY score HAVING other.score > 10'),
  text('having-implicit-alias-not-visible-to-where',
    'SELECT payload.score, COUNT(*) AS n FROM objects WHERE score > 10 GROUP BY score'),
].map(item => ({...item, expectedCode: 'ClientProgramInvalidInput'}));
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
    text: 'WITH samples AS (SELECT 2 AS x UNION ALL SELECT 1 AS x UNION ALL SELECT 2 AS x '
      + 'UNION ALL SELECT 3 AS x UNION ALL SELECT 2 AS x UNION ALL SELECT 1 AS x) '
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
    '(WITH summary AS (SELECT payload.score + 1 AS bucket, COUNT(*) + (objects.payload.score + 1) AS n FROM objects GROUP BY payload.score + 1) SELECT bucket, n FROM summary ORDER BY bucket)',
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

// HAVING uses its own SELECT-alias scope while reusing complete evaluated keys.
// The independent filter is authored over the ordinary post-group columns.
const havingGroupedColumns = [{name: 'bucket', contract: {...number, nullable: true}},
  {name: 'n', contract: number}];
const havingGroupedRows = [{bucket: 21, n: 2}];
const havingGroupedJson = {version: 'actql/0.1', id: 'fixture.having_grouped_expression', stages: [
  {id: 'main', inputs: {}, steps: [
    {values: {schema: {id: number, payload, other}, rows}, as: 'objects'},
    {from: 'objects', derive: {key: {add: [
      {property: {name: 'score', value: {field: 'payload'}}}, {literal: 1}]}}},
    {group: {by: ['key'], aggregates: {n: {fn: 'count'}}}},
    {filter: {gt: [{add: [{field: 'n'}, {field: 'key'}]}, {literal: 12}]}},
    {sort: [{field: 'key', dir: 'asc', nulls: 'first'}]},
    {select: [{bucket: 'key'}, 'n'], as: 'summary'},
  ], results: {rows: {from: 'summary', fields: ['bucket', 'n']}}},
], results: {answer: {from: {stage: 'main', result: 'rows'}}}};
// The common checked object descriptor explicitly states closedness. The
// author declaration shorthand is not the complete Result.describe contract.
const havingAliasColumns = [havingGroupedColumns[0],
  {name: 'payload', contract: {...payload, additional_properties: false}}, havingGroupedColumns[1]];
const havingAliasRows = [{bucket: null, payload: {score: 20}, n: 2},
  {bucket: 11, payload: {score: 20}, n: 1}, {bucket: 21, payload: {score: 20}, n: 2}];
export const havingGroupedSubexpressionSuccesses = [
  {name: 'group-property-having-subexpression-independent-json', format: 'json',
    text: JSON.stringify(havingGroupedJson), expected: havingGroupedRows,
    columns: havingGroupedColumns, sourceReadCount: 0},
  text('having-subexpression-count-key',
    'SELECT payload.score + 1 AS bucket, COUNT(*) AS n FROM objects GROUP BY payload.score + 1 HAVING n + (objects.payload.score + 1) > 12 ORDER BY bucket',
    {expected: havingGroupedRows, columns: havingGroupedColumns}),
  text('having-subexpression-hidden-count-key',
    'SELECT payload.score + 1 AS bucket, COUNT(*) AS n FROM objects GROUP BY objects.payload.score + 1 HAVING COUNT(*) + (`objects`.`payload`.`score` + 1) > 12 ORDER BY bucket',
    {expected: havingGroupedRows, columns: havingGroupedColumns}),
  text('having-subexpression-computed-alias',
    'SELECT payload.score + 1 AS payload, COUNT(*) AS n FROM objects GROUP BY objects.payload.score + 1 HAVING payload + 1 > 12 ORDER BY payload',
    {expected: [{payload: 21, n: 2}], columns: [{name: 'payload', contract: {...number, nullable: true}}, havingGroupedColumns[1]]}),
  text('having-subexpression-alias-property',
    'SELECT payload.score + 1 AS bucket, @b AS payload, COUNT(*) AS n FROM objects GROUP BY objects.payload.score + 1 HAVING payload.score + 1 > 12 ORDER BY bucket',
    {expected: havingAliasRows, columns: havingAliasColumns}),
  text('having-subexpression-qualified-input-property',
    'SELECT payload.score + 1 AS bucket, @b AS payload, COUNT(*) AS n FROM objects GROUP BY objects.payload.score + 1 HAVING objects.payload.score + 1 > 12 ORDER BY bucket',
    {expected: [havingAliasRows[2]], columns: havingAliasColumns}),
  text('having-subexpression-join',
    'SELECT l.payload.score + 1 AS bucket, COUNT(*) AS n FROM objects AS l JOIN objects AS r ON l.id = r.id MAX_OUTPUT_ROWS 10 GROUP BY l.payload.score + 1 HAVING n + (l.payload.score + 1) > 12 ORDER BY bucket',
    {expected: havingGroupedRows, columns: havingGroupedColumns}),
  text('having-subexpression-empty',
    'SELECT payload.score + 1 AS bucket, COUNT(*) AS n FROM objects WHERE FALSE GROUP BY payload.score + 1 HAVING n + (payload.score + 1) > 12 ORDER BY bucket',
    {expected: [], columns: havingGroupedColumns}),
  {name: 'group-property-having-subexpression-negative-alias', format: 'aql-text',
    text: 'WITH samples AS (SELECT 2 AS x UNION ALL SELECT 1 AS x) '
      + 'SELECT -x AS x, COUNT(*) AS n FROM samples GROUP BY samples.x HAVING x + 1 > 0 ORDER BY x',
    expected: [], columns: [{name: 'x', contract: number}, {name: 'n', contract: number}], sourceReadCount: 0},
  {name: 'group-property-having-subexpression-positive-input', format: 'aql-text',
    text: 'WITH samples AS (SELECT 2 AS x UNION ALL SELECT 1 AS x) '
      + 'SELECT -x AS x, COUNT(*) AS n FROM samples GROUP BY samples.x HAVING samples.x + 1 > 0 ORDER BY x',
    expected: [{x: -2, n: 1}, {x: -1, n: 1}],
    columns: [{name: 'x', contract: number}, {name: 'n', contract: number}], sourceReadCount: 0},
  {name: 'group-property-having-subexpression-private-looking-input', format: 'aql-text',
    text: 'WITH samples AS (SELECT 100 AS aql_having_aggregate_0) '
      + 'SELECT COUNT(*) AS n FROM samples GROUP BY aql_having_aggregate_0 + 1 HAVING COUNT(*) + 1 > 10',
    expected: [], columns: [{name: 'n', contract: number}], sourceReadCount: 0},
];
export const havingGroupedSubexpressionRefusals = [
  text('having-subexpression-key-does-not-revive-receiver',
    'SELECT COUNT(*) AS n FROM objects GROUP BY payload.score + 1 HAVING payload.score > 10'),
  text('having-subexpression-ungrouped-receiver',
    'SELECT COUNT(*) AS n FROM objects GROUP BY payload.score + 1 HAVING other.score + 1 > 10'),
  text('having-subexpression-different-key',
    'SELECT COUNT(*) AS n FROM objects GROUP BY payload.score + 1 HAVING payload.score + 2 > 10'),
  text('having-subexpression-missing-range',
    'SELECT COUNT(*) AS n FROM objects AS current GROUP BY current.payload.score + 1 HAVING old.payload.score + 1 > 10'),
];

// COUNT+key orders the less frequent larger key first: sorting the grouping
// key alone instead would reverse these rows. The Program is hand-authored.
const orderGroupedRows = [{bucket: 3, n: 1}, {bucket: 2, n: 4}];
const orderGroupedColumns = [{name: 'bucket', contract: number}, {name: 'n', contract: number}];
const orderGroupedSource = 'WITH samples AS (SELECT 1 AS x UNION ALL SELECT 2 AS x '
  + 'UNION ALL SELECT 1 AS x UNION ALL SELECT 1 AS x UNION ALL SELECT 1 AS x) ';
const orderGroupedJson = {version: 'actql/0.1', id: 'fixture.order_grouped_subexpression', stages: [
  {id: 'main', inputs: {}, steps: [
    {values: {schema: {x: number}, rows: [{x: 1}, {x: 2}, {x: 1}, {x: 1}, {x: 1}]}, as: 'samples'},
    {from: 'samples', derive: {key: {add: [{field: 'x'}, {literal: 1}]}}},
    {group: {by: ['key'], aggregates: {n: {fn: 'count'}}}},
    {derive: {sort_key: {add: [{field: 'n'}, {field: 'key'}]}}},
    {sort: [{field: 'sort_key', dir: 'asc', nulls: 'first'}]},
    {select: [{bucket: 'key'}, 'n'], as: 'summary'},
  ], results: {rows: {from: 'summary', fields: ['bucket', 'n']}}},
], results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const orderPropertyRows = [{bucket: null, n: 2}, {bucket: 21, n: 2}, {bucket: 11, n: 1}];
const orderAliasColumns = [havingAliasColumns[0], havingAliasColumns[1], havingAliasColumns[2]];
export const orderGroupedSubexpressionSuccesses = [
  {name: 'group-property-order-subexpression-independent-json', format: 'json',
    text: JSON.stringify(orderGroupedJson), expected: orderGroupedRows,
    columns: orderGroupedColumns, sourceReadCount: 0},
  {name: 'group-property-order-subexpression-count-key', format: 'aql-text',
    text: orderGroupedSource + 'SELECT x + 1 AS bucket, COUNT(*) AS n FROM samples '
      + 'GROUP BY x + 1 ORDER BY n + (samples.x + 1)',
    expected: orderGroupedRows, columns: orderGroupedColumns, sourceReadCount: 0},
  {name: 'group-property-order-subexpression-unselected-key', format: 'aql-text',
    text: orderGroupedSource + 'SELECT COUNT(*) AS n FROM samples '
      + 'GROUP BY x + 1 ORDER BY n + (samples.x + 1)',
    expected: [{n: 1}, {n: 4}], columns: [{name: 'n', contract: number}], sourceReadCount: 0},
  text('order-subexpression-hidden-count-property',
    'SELECT payload.score + 1 AS bucket, COUNT(*) AS n FROM objects GROUP BY payload.score + 1 '
      + 'ORDER BY COUNT(*) - (`objects`.`payload`.`score` + 1) NULLS FIRST',
    {expected: orderPropertyRows, columns: havingGroupedColumns}),
  text('order-subexpression-distinct-selected-key',
    'SELECT DISTINCT payload.score + 1 AS bucket, COUNT(*) AS n FROM objects GROUP BY payload.score + 1 '
      + 'ORDER BY n - (objects.payload.score + 1) NULLS FIRST',
    {expected: orderPropertyRows, columns: havingGroupedColumns}),
  text('order-subexpression-alias-property',
    'SELECT payload.score + 1 AS bucket, @b AS payload, COUNT(*) AS n FROM objects GROUP BY objects.payload.score + 1 '
      + 'ORDER BY payload.score + 1 NULLS LAST, bucket DESC NULLS LAST',
    {expected: [havingAliasRows[2], havingAliasRows[1], havingAliasRows[0]], columns: orderAliasColumns}),
  text('order-subexpression-qualified-input-property',
    'SELECT payload.score + 1 AS bucket, @b AS payload, COUNT(*) AS n FROM objects GROUP BY objects.payload.score + 1 '
      + 'ORDER BY objects.payload.score + 1 NULLS LAST, bucket DESC NULLS LAST',
    {expected: [havingAliasRows[1], havingAliasRows[2], havingAliasRows[0]], columns: orderAliasColumns}),
  text('order-subexpression-join',
    'SELECT l.payload.score + 1 AS bucket, COUNT(*) AS n FROM objects AS l JOIN objects AS r ON l.id = r.id '
      + 'MAX_OUTPUT_ROWS 10 GROUP BY l.payload.score + 1 ORDER BY n - (l.payload.score + 1) NULLS FIRST',
    {expected: orderPropertyRows, columns: havingGroupedColumns}),
  text('order-subexpression-implicit-member-alias',
    ', shaped AS (SELECT id AS score, other AS payload FROM objects) '
      + 'SELECT (payload).score, COUNT(*) AS n FROM shaped GROUP BY (payload).score, score + 1 ORDER BY score + 1',
    {expected: [{score: 100, n: 1}, {score: 200, n: 1}, {score: 300, n: 1}, {score: 400, n: 1}, {score: 500, n: 1}],
      columns: [{name: 'score', contract: number}, {name: 'n', contract: number}]}),
  text('order-subexpression-empty',
    'SELECT payload.score + 1 AS bucket, COUNT(*) AS n FROM objects WHERE FALSE GROUP BY payload.score + 1 '
      + 'ORDER BY n + (objects.payload.score + 1)',
    {expected: [], columns: havingGroupedColumns}),
  {name: 'group-property-order-subexpression-negative-alias', format: 'aql-text',
    text: 'WITH samples AS (SELECT 2 AS x UNION ALL SELECT 1 AS x) '
      + 'SELECT -x AS x, COUNT(*) AS n FROM samples GROUP BY samples.x ORDER BY x + 1',
    expected: [{x: -2, n: 1}, {x: -1, n: 1}], columns: [{name: 'x', contract: number}, {name: 'n', contract: number}], sourceReadCount: 0},
  {name: 'group-property-order-subexpression-qualified-scalar-input', format: 'aql-text',
    text: 'WITH samples AS (SELECT 2 AS x UNION ALL SELECT 1 AS x) '
      + 'SELECT -x AS x, COUNT(*) AS n FROM samples GROUP BY samples.x ORDER BY samples.x + 1',
    expected: [{x: -1, n: 1}, {x: -2, n: 1}], columns: [{name: 'x', contract: number}, {name: 'n', contract: number}], sourceReadCount: 0},
];
export const orderGroupedSubexpressionRefusals = [
  text('order-subexpression-partial-key',
    'SELECT COUNT(*) AS n FROM objects GROUP BY payload.score + 1 ORDER BY payload.score'),
  text('order-subexpression-ungrouped-receiver',
    'SELECT COUNT(*) AS n FROM objects GROUP BY payload.score + 1 ORDER BY other.score + 1'),
  text('order-subexpression-distinct-removed-key',
    'SELECT DISTINCT COUNT(*) AS n FROM objects GROUP BY payload.score + 1 ORDER BY objects.payload.score + 1'),
  text('order-subexpression-distinct-overwritten-key',
    'SELECT DISTINCT -id AS id, COUNT(*) AS n FROM objects GROUP BY objects.id ORDER BY objects.id + 1'),
  text('order-subexpression-closed-pipe-scope',
    'SELECT payload.score + 1 AS bucket, COUNT(*) AS n FROM objects GROUP BY payload.score + 1 '
      + 'ORDER BY bucket |> ORDER BY objects.payload.score + 1'),
];

export const groupPropertySuccesses = [
  ...groupHavingImplicitAliasSuccesses,
  ...orderGroupedSubexpressionSuccesses,
  ...groupedImplicitPropertyNameSuccesses,
  ...havingGroupedSubexpressionSuccesses,
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
  format: 'aql-text', text: source + tail, parameterDeclarations, parameters})).concat(pipeAggregateOrderRefusals, pipeAggregateExpressionRefusals, sqlGroupedSubexpressionRefusals, havingGroupedSubexpressionRefusals, orderGroupedSubexpressionRefusals, groupedImplicitPropertyNameRefusals, groupHavingImplicitAliasRefusals);
