import assert from 'node:assert/strict';

// Install these rows through the ordinary source profile. The Host must
// publish the explicit relation alias "records" in that same generation.
// Expected output is independent of the frontend and its generated Program.
export const sourceRows = [
  {id: 3, amount: 30}, {id: 1, amount: null},
  {id: 2, amount: 20}, {id: 3, amount: 30},
];
const declarations = {minimum: {type: 'number'}};
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
export const queryRefusals = [
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
    return {acceptedRuns: current.acceptedRuns, sourceIo: current.sourceIo};
  };
  const client = await connect(options);
  try {
    for (const {name, text, expected, columns, sourceRows, sourceReadCount, ...input} of successes) {
      await prepareCase?.(sourceRows);
      const requestId = requestPrefix + '-' + name;
      const beforeSubmit = await counters();
      const execution = await client.aql(text, {...input, requestId});
      const state = await execution.wait();
      assert.equal(state.status, 'succeeded', JSON.stringify({name, state}));
      const beforeRead = await counters();
      if (sourceReadCount !== undefined) {
        assert.equal(beforeRead.sourceIo - beforeSubmit.sourceIo, sourceReadCount,
          'shared producers acquire once per authored source');
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
