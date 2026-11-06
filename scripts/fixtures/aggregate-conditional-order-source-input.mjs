// Independent ordinary Programs and rows. No compiler output is an oracle.
import {aggregatePropertyOrderProgram, aggregatePropertyOrderArrayProgram, aggregatePropertyOrderSuccesses}
  from './aggregate-property-order-source-input.mjs';
const base = aggregatePropertyOrderSuccesses.find(item => item.name === 'aggregate-property-order-sql');
const data = 'WITH objects AS (SELECT id, '
  + "CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, "
  + 'CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, '
  + 'CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other '
  + 'FROM records WHERE id > 0) ';
const key = {coalesce: [{property: {name: 'score', value: {field: 'payload'}}}, {literal: 0}]};
export const aggregateConditionalOrderProgram = {
  ...aggregatePropertyOrderProgram, id: 'fixture.aggregate_conditional_order',
  stages: [aggregatePropertyOrderProgram.stages[0], {
    ...aggregatePropertyOrderProgram.stages[1],
    steps: [...aggregatePropertyOrderProgram.stages[1].steps.slice(0, 2),
      {derive: {key}}, aggregatePropertyOrderProgram.stages[1].steps[3]],
  }],
};
// A Boolean sort key uses the same ordinary derive/group contract as a
// numeric key. NULL object and NULL member both yield true for IS NULL.
export const aggregatePredicateOrderProgram = {
  ...aggregateConditionalOrderProgram, id: 'fixture.aggregate_predicate_order',
  stages: [aggregatePropertyOrderProgram.stages[0], {
    ...aggregatePropertyOrderProgram.stages[1],
    steps: [...aggregatePropertyOrderProgram.stages[1].steps.slice(0, 2),
      {derive: {key: {is_null: {property: {name: 'score', value: {field: 'payload'}}}}}},
      aggregatePropertyOrderProgram.stages[1].steps[3]],
  }],
};
export const aggregatePredicateArrayOrderProgram = {
  ...aggregatePropertyOrderArrayProgram, id: 'fixture.aggregate_predicate_array_order',
  stages: [aggregatePropertyOrderArrayProgram.stages[0], {
    ...aggregatePropertyOrderArrayProgram.stages[1],
    steps: [...aggregatePropertyOrderArrayProgram.stages[1].steps.slice(0, 5),
      {derive: {key: {is_null: {property: {name: 'score', value: {field: 'payload'}}}}}},
      aggregatePropertyOrderArrayProgram.stages[1].steps[6]],
  }],
};
// NULL-containing membership retains the common three-valued in node.
export const aggregateMembershipOrderProgram = {
  ...aggregateConditionalOrderProgram, id: 'fixture.aggregate_membership_order',
  stages: [aggregatePropertyOrderProgram.stages[0], {
    ...aggregatePropertyOrderProgram.stages[1],
    steps: [...aggregatePropertyOrderProgram.stages[1].steps.slice(0, 2),
      {derive: {key: {in: [{property: {name: 'score', value: {field: 'payload'}}}, {literal: [20, null]}]}}},
      aggregatePropertyOrderProgram.stages[1].steps[3]],
  }],
};
export const aggregateMembershipArrayOrderProgram = {
  ...aggregatePropertyOrderArrayProgram, id: 'fixture.aggregate_membership_array_order',
  stages: [aggregatePropertyOrderArrayProgram.stages[0], {
    ...aggregatePropertyOrderArrayProgram.stages[1],
    steps: [...aggregatePropertyOrderArrayProgram.stages[1].steps.slice(0, 5),
      {derive: {key: {in: [{property: {name: 'score', value: {field: 'payload'}}}, {literal: [20]}]}}},
      aggregatePropertyOrderArrayProgram.stages[1].steps[6]],
  }],
};
const sql = "SELECT STRING_AGG(name, '|' ORDER BY COALESCE(payload.score, 0) NULLS LAST, id) AS names FROM objects";
const success = (name, tail = sql, extra = {}) => ({...base,
  name: 'aggregate-conditional-order-' + name, text: data + tail,
  expected: [{names: 'c|b|b|a'}], ...extra});
export const aggregateConditionalOrderSuccesses = [
  success('independent-json', '', {format: 'json', text: JSON.stringify(aggregateConditionalOrderProgram),
    parameterDeclarations: undefined}),
  success('sql'),
  success('quoted-pipe', "FROM objects AS t |> AGGREGATE STRING_AGG(name, '|' ORDER BY `IFNULL`((t.payload).score, 0) NULLS LAST, id) AS names"),
  success('searched-case', sql.replace('COALESCE(payload.score, 0)', 'CASE WHEN id = 1 THEN 0 ELSE payload.score END'),
    {expected: [{names: 'a|b|b|c'}]}),
  success('nested-if', sql.replace('COALESCE(payload.score, 0)', 'IF(payload.score IS NULL, other.score, -payload.score)'),
    {expected: [{names: 'a|b|b|c'}]}),
  success('computed-receiver', sql.replace('COALESCE(payload.score, 0)', 'COALESCE(payload, other).score'),
    {expected: [{names: 'b|b|c|a'}]}),
  success('per-call-orders', "SELECT STRING_AGG(name, '|' ORDER BY IFNULL(payload.score, 0), id) AS names, "
    + "STRING_AGG(name, '|' ORDER BY IFNULL(payload.score, 0) DESC, id) AS reverse FROM objects", {
    expected: [{names: 'c|b|b|a', reverse: 'a|b|b|c'}],
    columns: ['names', 'reverse'].map(name => ({name, contract: {type: 'string', nullable: true}})),
  }),
  success('current-and-snapshot', 'FROM objects AS before |> SET payload = other '
    + "|> AGGREGATE STRING_AGG(name, '|' ORDER BY IFNULL(payload.score, 0), id) AS `current`, "
    + "STRING_AGG(name, '|' ORDER BY IFNULL(before.payload.score, 0), id) AS previous", {
    expected: [{current: 'a|c|b|b', previous: 'c|b|b|a'}],
    columns: ['current', 'previous'].map(name => ({name, contract: {type: 'string', nullable: true}})),
  }),
  success('filtered-argument', sql.replace("name, '|'", "name, '|' WHERE id <= 2"),
    {expected: [{names: 'b|b|a'}]}),
  success('masked-argument', sql.replace("name, '|'", "IF(id / (id - id) = 0, name, name), '|' WHERE FALSE"),
    {expected: [{names: null}]}),
  success('empty', sql, {sourceRows: [], expected: [{names: null}]}),
  success('typed-parameter', sql.replace('COALESCE(payload.score, 0)', 'COALESCE(payload.score, @fallback)'), {
    parameterDeclarations: {...base.parameterDeclarations, fallback: {type: 'number', nullable: false}},
    parameters: {...base.parameters, fallback: 0},
  }),
  success('distinct-same-argument', "SELECT STRING_AGG(DISTINCT IFNULL(name, 'missing'), '|' ORDER BY IFNULL(name, 'missing')) AS names FROM objects",
    {expected: [{names: 'a|b|c|missing'}]}),
  success('predicate-independent-json', '', {format: 'json', text: JSON.stringify(aggregatePredicateOrderProgram),
    parameterDeclarations: undefined, expected: [{names: 'a|b|b|c'}]}),
  success('predicate-is-null', sql.replace('COALESCE(payload.score, 0)', 'payload.score IS NULL'),
    {expected: [{names: 'a|b|b|c'}]}),
  success('predicate-comparison-pipe', "FROM objects AS t |> AGGREGATE STRING_AGG(name, '|' ORDER BY ((t.payload)).`SCORE` > 15 NULLS LAST, id) AS names",
    {expected: [{names: 'b|b|a|c'}]}),
  success('predicate-not', sql.replace('COALESCE(payload.score, 0)', 'NOT (payload.score > 15)'),
    {expected: [{names: 'a|b|b|c'}]}),
  success('predicate-and', sql.replace('COALESCE(payload.score, 0)', '(payload.score > 15) AND id != 3'),
    {expected: [{names: 'b|b|c|a'}]}),
  success('predicate-or', sql.replace('COALESCE(payload.score, 0)', '(payload.score > 15) OR id = 3'),
    {expected: [{names: 'b|b|a|c'}]}),
  success('predicate-unknown', sql.replace('COALESCE(payload.score, 0)', '(payload.score > 15) IS UNKNOWN'),
    {expected: [{names: 'a|b|b|c'}]}),
  success('predicate-empty', sql.replace('COALESCE(payload.score, 0)', 'payload.score IS NULL'),
    {sourceRows: [], expected: [{names: null}]}),
  success('predicate-masked', sql.replace('COALESCE(payload.score, 0)', 'payload.score IS NULL')
    .replace("name, '|'", "IF(id / (id - id) = 0, name, name), '|' WHERE FALSE"),
    {expected: [{names: null}]}),
  success('predicate-per-call', "SELECT STRING_AGG(name, '|' ORDER BY payload.score IS NULL, id) AS names, "
    + "STRING_AGG(name, '|' ORDER BY payload.score IS NULL DESC, id) AS reverse FROM objects", {
    expected: [{names: 'a|b|b|c', reverse: 'c|a|b|b'}],
    columns: ['names', 'reverse'].map(name => ({name, contract: {type: 'string', nullable: true}})),
  }),
  success('predicate-current-and-snapshot', 'FROM objects AS before |> SET payload = other '
    + "|> AGGREGATE STRING_AGG(name, '|' ORDER BY payload.score > 15 NULLS LAST, id) AS `current`, "
    + "STRING_AGG(name, '|' ORDER BY before.payload.score > 15 NULLS LAST, id) AS previous", {
    expected: [{current: 'a|c|b|b', previous: 'b|b|a|c'}],
    columns: ['current', 'previous'].map(name => ({name, contract: {type: 'string', nullable: true}})),
  }),
  success('predicate-parameter', sql.replace('COALESCE(payload.score, 0)', 'id = @selected'), {
    parameterDeclarations: {...base.parameterDeclarations, selected: {type: 'number', nullable: false}},
    parameters: {...base.parameters, selected: 2}, expected: [{names: 'a|c|b|b'}],
  }),
  success('predicate-input-over-sibling', "SELECT COUNT(*) AS payload, STRING_AGG(name, '|' ORDER BY payload.score IS NULL, id) AS names FROM objects", {
    expected: [{payload: 5, names: 'a|b|b|c'}],
    columns: [{name: 'payload', contract: {type: 'number', nullable: false}}, {name: 'names', contract: {type: 'string', nullable: true}}],
  }),
  success('predicate-independent-array-json', '', {format: 'json', text: JSON.stringify(aggregatePredicateArrayOrderProgram),
    parameterDeclarations: undefined, sourceRows: base.sourceRows.filter((row, index) => index !== 4),
    expected: [{ids: [1, 2, 3, 4]}],
    columns: [{name: 'ids', contract: {type: 'array', nullable: false, items: {type: 'number', nullable: false}}}],
  }),
  success('predicate-keyed-array', 'FROM objects |> ASSERT UNIQUE BY (id) |> ORDER BY id |> LIMIT 4 '
    + '|> AGGREGATE ARRAY_AGG(id IGNORE NULLS ORDER BY payload.score IS NULL, id) AS ids', {
    sourceRows: base.sourceRows.filter((row, index) => index !== 4), expected: [{ids: [1, 2, 3, 4]}],
    columns: [{name: 'ids', contract: {type: 'array', nullable: false, items: {type: 'number', nullable: false}}}],
  }),
  success('membership-independent-json', '', {format: 'json', text: JSON.stringify(aggregateMembershipOrderProgram),
    parameterDeclarations: undefined, expected: [{names: 'a|b|b|c'}]}),
  success('membership-null-list', sql.replace('COALESCE(payload.score, 0)', 'payload.score IN (20, NULL)'),
    {expected: [{names: 'a|b|b|c'}]}),
  success('membership-in-pipe', "FROM objects AS t |> AGGREGATE STRING_AGG(name, '|' ORDER BY ((t.payload)).`SCORE` IN (20, 20) NULLS LAST, id) AS names",
    {expected: [{names: 'b|b|a|c'}]}),
  success('membership-not-in', sql.replace('COALESCE(payload.score, 0)', 'payload.score NOT IN (20)'),
    {expected: [{names: 'a|b|b|c'}]}),
  success('membership-unnest', sql.replace('COALESCE(payload.score, 0)', 'payload.score IN UNNEST(ARRAY[20, NULL])'),
    {expected: [{names: 'a|b|b|c'}]}),
  success('membership-empty-list', sql.replace('COALESCE(payload.score, 0)', 'payload.score NOT IN UNNEST([])'),
    {expected: [{names: 'a|b|b|c'}]}),
  success('membership-between', sql.replace('COALESCE(payload.score, 0)', 'payload.score BETWEEN 5 AND 15'),
    {expected: [{names: 'a|b|b|c'}]}),
  success('membership-not-between', sql.replace('COALESCE(payload.score, 0)', 'payload.score NOT BETWEEN 5 AND 15'),
    {expected: [{names: 'b|b|a|c'}]}),
  success('membership-null-safe', sql.replace('COALESCE(payload.score, 0)', 'payload.score IS NOT DISTINCT FROM 20'),
    {expected: [{names: 'b|b|c|a'}]}),
  success('membership-null-safe-null', sql.replace('COALESCE(payload.score, 0)', 'payload.score IS DISTINCT FROM NULL'),
    {expected: [{names: 'c|a|b|b'}]}),
  success('membership-current-and-snapshot', 'FROM objects AS before |> SET payload = other '
    + "|> AGGREGATE STRING_AGG(name, '|' ORDER BY payload.score IN (25, 30) NULLS LAST, id) AS `current`, "
    + "STRING_AGG(name, '|' ORDER BY before.payload.score IN (25, 30) NULLS LAST, id) AS previous", {
    expected: [{current: 'a|c|b|b', previous: 'a|b|b|c'}],
    columns: ['current', 'previous'].map(name => ({name, contract: {type: 'string', nullable: true}})),
  }),
  success('membership-parameter', sql.replace('COALESCE(payload.score, 0)', 'payload.score IN (@wanted, NULL)'), {
    parameterDeclarations: {...base.parameterDeclarations, wanted: {type: 'number', nullable: true}},
    parameters: {...base.parameters, wanted: 20}, expected: [{names: 'a|b|b|c'}],
  }),
  success('membership-masked', sql.replace('COALESCE(payload.score, 0)', 'payload.score BETWEEN 5 AND 15')
    .replace("name, '|'", "IF(id / (id - id) = 0, name, name), '|' WHERE FALSE"),
    {expected: [{names: null}]}),
  success('membership-independent-array-json', '', {format: 'json', text: JSON.stringify(aggregateMembershipArrayOrderProgram),
    parameterDeclarations: undefined, sourceRows: base.sourceRows.filter((row, index) => index !== 4),
    expected: [{ids: [2, 1, 3, 4]}],
    columns: [{name: 'ids', contract: {type: 'array', nullable: false, items: {type: 'number', nullable: false}}}],
  }),
  success('membership-keyed-array', 'FROM objects |> ASSERT UNIQUE BY (id) |> ORDER BY id |> LIMIT 4 '
    + '|> AGGREGATE ARRAY_AGG(id IGNORE NULLS ORDER BY payload.score IN (20) NULLS LAST, id) AS ids', {
    sourceRows: base.sourceRows.filter((row, index) => index !== 4), expected: [{ids: [2, 1, 3, 4]}],
    columns: [{name: 'ids', contract: {type: 'array', nullable: false, items: {type: 'number', nullable: false}}}],
  }),
];
export const aggregateConditionalOrderRefusals = [
  {name: 'condition-type', text: sql.replace('COALESCE(payload.score, 0)', 'IF(id, 0, payload.score)')},
  {name: 'missing-member', text: sql.replace('COALESCE(payload.score, 0)', 'COALESCE(payload, other).missing')},
  {name: 'removed-range', text: 'FROM objects AS old |> AS current '
    + "|> AGGREGATE STRING_AGG(name, '|' ORDER BY COALESCE(old.payload.score, 0), id) AS names"},
  {name: 'unsafe-demand', text: sql.replace('COALESCE(payload.score, 0)', 'IF(FALSE, id / 0, id)'),
    expectedCode: 'ClientProgramImplementationLimit'},
  {name: 'distinct-different-argument', text: sql.replace('STRING_AGG(name', 'STRING_AGG(DISTINCT name'),
    expectedCode: 'ClientProgramImplementationLimit'},
  {name: 'predicate-operand-type', text: sql.replace('COALESCE(payload.score, 0)', 'id AND TRUE'),
    expectedCode: 'ClientProgramInvalidInput'},
  {name: 'predicate-missing-member', text: sql.replace('COALESCE(payload.score, 0)', 'payload.missing IS NULL'),
    expectedCode: 'ClientProgramInvalidInput'},
  {name: 'predicate-unsafe-demand', text: sql.replace('COALESCE(payload.score, 0)', '(id / 0) > 1'),
    expectedCode: 'ClientProgramImplementationLimit'},
  {name: 'predicate-removed-range', text: 'FROM objects AS old |> AS current '
    + "|> AGGREGATE STRING_AGG(name, '|' ORDER BY old.payload.score IS NULL, id) AS names",
    expectedCode: 'ClientProgramInvalidInput'},
  {name: 'membership-operand-type', text: sql.replace('COALESCE(payload.score, 0)', "payload.score IN ('wrong')"),
    expectedCode: 'ClientProgramInvalidInput'},
  {name: 'membership-removed-range', text: 'FROM objects AS old |> AS current '
    + "|> AGGREGATE STRING_AGG(name, '|' ORDER BY old.payload.score IN (20), id) AS names",
    expectedCode: 'ClientProgramInvalidInput'},
  {name: 'membership-unsafe-bound', text: sql.replace('COALESCE(payload.score, 0)', 'payload.score BETWEEN 0 AND id / 0'),
    expectedCode: 'ClientProgramImplementationLimit'},
  {name: 'membership-distinct-key', text: sql.replace('COALESCE(payload.score, 0)', 'payload.score IN (20)')
    .replace('STRING_AGG(name', 'STRING_AGG(DISTINCT name'), expectedCode: 'ClientProgramImplementationLimit'},
].map(item => ({format: 'aql-text', parameterDeclarations: base.parameterDeclarations,
  parameters: base.parameters, ...item, name: 'aggregate-conditional-order-refuse-' + item.name,
  text: data + item.text}));


// Independently authored JSON control: DISTINCT consumes the same expression
// whose admitted value is used by aggregate-local ordering.
const distinctName = {coalesce: [{field: 'name'}, {literal: 'missing'}]};
export const distinctConditionalOrderProgram = {
  ...aggregatePropertyOrderProgram, id: 'fixture.distinct_conditional_order',
  stages: [aggregatePropertyOrderProgram.stages[0], {
    ...aggregatePropertyOrderProgram.stages[1],
    steps: [...aggregatePropertyOrderProgram.stages[1].steps.slice(0, 2),
      {derive: {key: distinctName}},
      {group: {by: [], aggregates: {names: {fn: 'string_agg', expr: distinctName,
        distinct: true, max_bytes: 65536, delimiter: '|',
        order_by: [{field: 'key', dir: 'asc', nulls: 'first'}]}}}, as: 'out'}],
  }],
};
const distinctMember = {coalesce: [
  {property: {name: 'score', value: {field: 'payload'}}}, {literal: 0}]};
export const distinctConditionalMemberProgram = {
  ...aggregatePropertyOrderArrayProgram, id: 'fixture.distinct_conditional_member',
  stages: [aggregatePropertyOrderArrayProgram.stages[0], {
    ...aggregatePropertyOrderArrayProgram.stages[1],
    steps: [...aggregatePropertyOrderArrayProgram.stages[1].steps.slice(0, 5),
      {derive: {key: distinctMember}},
      {group: {by: [], aggregates: {ids: {fn: 'array_agg', expr: distinctMember,
        distinct: true, max_items: 1000000,
        order_by: [{field: 'key', dir: 'desc', nulls: 'last'}]}}}, as: 'out'}],
  }],
};
const distinctSql = "SELECT STRING_AGG(DISTINCT IFNULL(name, 'missing'), '|' ORDER BY IFNULL(objects.name, 'missing')) AS names FROM objects";
aggregateConditionalOrderSuccesses.push(
  success('distinct-independent-json', '', {format: 'json',
    text: JSON.stringify(distinctConditionalOrderProgram), parameterDeclarations: undefined,
    expected: [{names: 'a|b|c|missing'}]}),
  success('distinct-qualified-sql', distinctSql, {expected: [{names: 'a|b|c|missing'}]}),
  success('distinct-quoted-pipe', "FROM objects AS o |> AGGREGATE STRING_AGG(DISTINCT IFNULL(name, 'missing'), '|' ORDER BY IFNULL(`o`.`NAME`, 'missing')) AS names",
    {expected: [{names: 'a|b|c|missing'}]}),
  success('distinct-empty', distinctSql, {sourceRows: [], expected: [{names: null}]}),
  success('qualified-shared-key', "SELECT STRING_AGG(name, '|' ORDER BY IFNULL(name, 'missing')) AS names, STRING_AGG(name, '|' ORDER BY IFNULL(o.name, 'missing') DESC) AS reverse FROM objects AS o", {
    expected: [{names: 'a|b|b|c', reverse: 'c|b|b|a'}],
    columns: ['names', 'reverse'].map(name => ({name, contract: {type: 'string', nullable: true}})),
  }),
  success('distinct-case-qualified', "SELECT STRING_AGG(DISTINCT CASE WHEN id = 3 THEN 'third' ELSE IFNULL(name, 'missing') END, '|' ORDER BY CASE WHEN o.id = 3 THEN 'third' ELSE IFNULL(o.name, 'missing') END) AS names FROM objects AS o",
    {expected: [{names: 'a|b|missing|third'}]}),
);
const distinctArray = {sourceRows: base.sourceRows.filter((row, index) => index !== 4),
  expected: [{ids: [20, 10, 0]}], columns: [{name: 'ids', contract: {
    type: 'array', nullable: false, items: {type: 'number', nullable: false}}}]};
aggregateConditionalOrderSuccesses.push(
  success('distinct-member-independent-json', '', {...distinctArray,
    format: 'json', text: JSON.stringify(distinctConditionalMemberProgram), parameterDeclarations: undefined}),
  success('distinct-member-pipe', 'FROM objects AS o |> ASSERT UNIQUE BY (id) |> ORDER BY id |> LIMIT 4 '
    + '|> AGGREGATE ARRAY_AGG(DISTINCT IFNULL((payload).score, 0) IGNORE NULLS ORDER BY IFNULL((o.payload).`SCORE`, 0) DESC) AS ids', distinctArray),
);
aggregateConditionalOrderRefusals.push(...[
  {name: 'distinct-literal-mismatch', text: distinctSql.replace('IFNULL(objects.name, \'missing\')', 'IFNULL(objects.name, \'other\')')},
  {name: 'distinct-current-snapshot', text: 'FROM objects AS before |> SET name = \'changed\' '
    + "|> AGGREGATE STRING_AGG(DISTINCT IFNULL(name, 'missing'), '|' ORDER BY IFNULL(before.name, 'missing')) AS names"},
  {name: 'distinct-member-mismatch', text: 'SELECT ARRAY_AGG(DISTINCT IFNULL(payload.score, 0) IGNORE NULLS ORDER BY IFNULL(other.score, 0)) AS ids FROM objects'},
  {name: 'distinct-explicit-receiver', text: ', colliding AS (SELECT id, name, payload, other, other.score AS score FROM objects) '
    + 'SELECT ARRAY_AGG(DISTINCT IFNULL((payload.payload).score, 0) IGNORE NULLS ORDER BY IFNULL(payload.score, 0)) AS ids FROM colliding AS payload'},
].map(item => ({...base, ...item, name: 'aggregate-conditional-order-refuse-' + item.name,
  text: data + item.text, expectedCode: 'ClientProgramImplementationLimit'})));
