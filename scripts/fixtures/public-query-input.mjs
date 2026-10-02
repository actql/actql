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
export const pipeResultSuccesses = [
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
    text: 'FROM records AS old |> SET id = id + 10 |> RESULT changed |> SELECT old.id AS original, id AS current |> ORDER BY original |> RESULT final',
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
  {name: 'result-duplicate', format: 'aql-text', text: 'FROM records |> RESULT saved |> RESULT saved'},
  {name: 'result-case-duplicate', format: 'aql-text', text: 'FROM records |> RESULT Saved |> RESULT `SAVED`'},
  {name: 'result-primary-collision', format: 'aql-text', text: 'FROM records |> RESULT answer |> LIMIT 1'},
  {name: 'result-cte-body', format: 'sql', text: 'WITH base AS (FROM records |> RESULT saved) SELECT id FROM base'},
  {name: 'result-derived-body', format: 'sql', text: 'SELECT id FROM (FROM records |> RESULT saved) AS base'},
  {name: 'result-missing-name', format: 'aql-text', text: 'FROM records |> RESULT'},
  {name: 'result-removed-range', format: 'aql-text', text: 'FROM records AS old |> AS current |> RESULT saved |> SELECT old.id'},
];
export const queryCompositionSuccesses = [
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
export const queryCompositionRefusals = [
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
export const sourceFreeSuccesses = [
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
  {name: 'source-free-star', format: 'sql', text: 'SELECT *'},
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
// These syntactically valid source forms must remain non-executable until
// the common infer owner exists. Rejection is not a model outcome.
export const inferRefusals = [
  {name: 'infer-common-owner', format: 'aql-text',
    text: 'FROM records |> INFER `model-task:risk.v1` ITEM KEY (id) '
      + 'INPUT (n = amount) KEEP (id) AS assessment'},
  {name: 'infer-omitted-keep', format: 'aql-text',
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

// Run this unchanged with installed Local and HTTP connect options. The test
// owner supplies cumulative observations of real Run admission and source
// I/O, not a replacement provider or a Client-side alias map. This function
// does not lower source, manufacture schema, or call a test compiler bridge.
export async function exercisePublicQueryInput(connect, options,
  {requestPrefix, observe, successes = querySuccesses,
    refusals = queryRefusals, prepareCase}) {
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
    for (const {name, text, expected, columns, results, sourceRows, sourceReadCount, sourceReadSessionCount, ...input} of successes) {
      await prepareCase?.(sourceRows);
      const requestId = requestPrefix + '-' + name;
      const beforeSubmit = await counters();
      const execution = await client.aql(text, {...input, requestId});
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
      const expectedResults = results ?? {answer: {rows: expected, columns}};
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
      for (const [resultName, result] of Object.entries(expectedResults)) {
        compare(await execution.result(resultName).all(), result.rows, result.unordered);
        if (result.columns !== undefined) {
          assert.deepEqual((await execution.result(resultName).describe()).columns,
            result.columns, 'retained column order and contracts match the authored fixture');
        }
      }
      const attached = await client.attach(execution.ref);
      for (const [resultName, result] of Object.entries(expectedResults)) {
        compare(await attached.result(resultName).all(), result.rows, result.unordered);
      }
      const resent = await client.aql(text, {...input, requestId});
      assert.deepEqual(resent.ref, execution.ref);
      assert.deepEqual((await client.lookupRequest(requestId)).ref, execution.ref);
      assert.deepEqual(await counters(), beforeRead,
        'reading, attaching and resending must not accept or acquire again');
      console.log(`Public query passed: ${requestPrefix}/${name}`);
      if (name === 'sql') {
        await assert.rejects(execution.result('answer').all({maxRows: 1}),
          {code: 'ResultRetainedLimit'});
        await assert.rejects(client.aql(text, {...input, requestId,
          parameters: {minimum: 21}}), {code: 'ClientRequestIntentConflict'});
        assert.equal((await execution.status()).status, 'succeeded');
      }
    }
    for (const {name, text, ...input} of refusals) {
      await prepareCase?.();
      const requestId = requestPrefix + '-reject-' + name;
      const before = await counters();
      await assert.rejects(client.aql(text, {...input, requestId}), error => {
        assert.ok(inputCodes.has(error.code), String(error.code));
        assert.ok(!String(error.message).includes('secret-value'));
        return true;
      });
      assert.deepEqual(await counters(), before,
        'rejected source must not accept a Run or perform source I/O');
      assert.deepEqual(await client.lookupRequest(requestId), {kind: 'not_found'});
    }
  } finally {
    client.close();
  }
}
