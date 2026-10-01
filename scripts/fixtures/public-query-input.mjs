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
export const queryCompositionSuccesses = [
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
];
export const queryCompositionRefusals = [
  {name: 'derived-hidden-column', format: 'sql',
    text: 'SELECT chosen.amount FROM (FROM records |> SELECT id) AS chosen'},
  {name: 'derived-hidden-range', format: 'sql',
    text: 'SELECT old.id FROM (FROM records AS old |> SELECT id) AS chosen'},
  {name: 'derived-displaced-range', format: 'sql',
    text: 'SELECT id FROM (FROM records AS old |> AS fresh |> SELECT old.id) AS chosen'},
  {name: 'derived-inner-terminator', format: 'sql',
    text: 'SELECT id FROM (FROM records |> SELECT id;) AS chosen'},
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
    for (const {name, text, expected, columns, sourceRows, sourceReadCount, sourceReadSessionCount, ...input} of successes) {
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
      assert.deepEqual(await execution.result('answer').all(), expected);
      if (columns !== undefined) {
        assert.deepEqual((await execution.result('answer').describe()).columns,
          columns, 'retained column order and contracts match the authored fixture');
      }
      const attached = await client.attach(execution.ref);
      assert.deepEqual(await attached.result('answer').all(), expected);
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
