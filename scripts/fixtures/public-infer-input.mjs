import assert from 'node:assert/strict';

const inputCodes = new Set(['ClientProgramInvalidInput',
  'ClientParametersInvalid', 'ClientParametersTooLarge',
  'ClientProgramUnsupported', 'ClientProgramNeedsInputs',
  'ClientProgramRejected']);
const counterNames = ['acceptedRuns', 'sourceIo', 'modelDispatches',
  'capturedSlots'];

// Copy this application and its authored JSON fixture into the clean packed
// installation. connect is the installed public Client. prepareCase installs
// physical source rows through the real test Host; observe reads cumulative
// admission, I/O and common infer-owner observations. Neither hook executes
// INFER or substitutes a compiler, ModelTask owner or Result implementation.
export async function exercisePublicInferInput(connect, options,
  {fixture, requestPrefix, prepareCase, observe, signal}) {
  assert.equal(typeof prepareCase, 'function');
  assert.equal(typeof observe, 'function');
  assert.equal(typeof requestPrefix, 'string');
  assert.ok(requestPrefix.length > 0);
  const counters = async () => {
    const current = await observe();
    return Object.fromEntries(counterNames.map(name => {
      assert.ok(Number.isSafeInteger(current[name]) && current[name] >= 0,
        `missing or invalid common-owner observation: ${name}`);
      return [name, current[name]];
    }));
  };
  const prepare = async name => {
    assert.ok(Object.hasOwn(fixture.source_rows, name));
    await prepareCase(structuredClone(fixture.source_rows[name]));
  };
  const input = requestId => ({format: 'aql-text', requestId});
  const client = await connect(options);
  const records = [];
  try {
    for (const item of fixture.successes) {
      await prepare(item.source_rows);
      const before = await counters();
      const requestId = `${requestPrefix}-${item.name}`;
      const execution = await client.aql(item.source, input(requestId));
      const state = await execution.wait({signal});
      assert.equal(state.status, 'succeeded', item.name);
      const completed = await counters();
      assert.equal(completed.acceptedRuns - before.acceptedRuns, 1);
      assert.equal(completed.modelDispatches - before.modelDispatches,
        item.model_dispatches, `${item.name}: physical ModelTask dispatches`);
      assert.equal(completed.capturedSlots - before.capturedSlots,
        item.captured_slots, `${item.name}: retained common-owner captures`);

      const result = execution.result('answer');
      const description = await result.describe({signal});
      assert.deepEqual(description.ref, execution.ref);
      assert.equal(description.resultName, 'answer');
      assert.equal(description.serialization.format, 'jsonl');
      assert.equal(description.serialization.version, 'actql-jsonl/0.1');
      assert.deepEqual(description.columns, fixture.columns[item.columns],
        `${item.name}: declared column order and complete type contracts`);
      const expected = fixture.expected_rows[item.expected_rows];
      assert.deepEqual(await result.all({signal}), expected,
        `${item.name}: authored rows, order, nullable object and closed fields`);
      assert.deepEqual(await result.all({signal}), expected);

      const attached = await client.attach(execution.ref);
      assert.deepEqual(await attached.result('answer').describe({signal}),
        description);
      assert.deepEqual(await attached.result('answer').all({signal}), expected);
      const resent = await client.aql(item.source, input(requestId));
      assert.deepEqual(resent.ref, execution.ref);
      assert.deepEqual((await client.lookupRequest(requestId)).ref, execution.ref);
      assert.deepEqual(await resent.result('answer').all({signal}), expected);
      assert.deepEqual(await counters(), completed,
        `${item.name}: re-read, attach, lookup and resend do not execute again`);
      await assert.rejects(client.aql(item.source + ' |> LIMIT 1',
        input(requestId)), {code: 'ClientRequestIntentConflict'});
      assert.deepEqual(await counters(), completed);
      records.push({name: item.name, ref: execution.ref, columns: description.columns,
        rows: expected.length, modelDispatches: item.model_dispatches,
        capturedSlots: item.captured_slots});
    }

    for (const item of fixture.preparation_refusals) {
      await prepare('standard');
      const before = await counters();
      const requestId = `${requestPrefix}-reject-${item.name}`;
      await assert.rejects(client.aql(item.source, input(requestId)), error => {
        assert.ok(inputCodes.has(error.code), `${item.name}: ${error.code}`);
        return true;
      });
      assert.deepEqual(await counters(), before,
        `${item.name}: no Run acceptance, acquisition or model I/O`);
      assert.deepEqual(await client.lookupRequest(requestId), {kind: 'not_found'});
      records.push({name: item.name, rejectedBeforeAdmission: true});
    }

    for (const item of fixture.preflight_failures) {
      await prepare(item.source_rows);
      const before = await counters();
      const execution = await client.aql(item.source,
        input(`${requestPrefix}-preflight-${item.name}`));
      const state = await execution.wait({signal});
      assert.equal(state.status, 'failed',
        `${item.name}: invalid acquired keys are not model outcomes`);
      const after = await counters();
      assert.equal(after.acceptedRuns - before.acceptedRuns, 1);
      assert.equal(after.modelDispatches, before.modelDispatches,
        `${item.name}: validate the entire acquired key tuple before dispatch`);
      assert.equal(after.capturedSlots, before.capturedSlots);
      const attached = await client.attach(execution.ref);
      assert.equal((await attached.status()).status, 'failed');
      const resent = await client.aql(item.source,
        input(`${requestPrefix}-preflight-${item.name}`));
      assert.deepEqual(resent.ref, execution.ref);
      assert.deepEqual(await counters(), after);
      records.push({name: item.name, failedBeforeModelDispatch: true});
    }
    return records;
  } finally {
    client.close();
  }
}
