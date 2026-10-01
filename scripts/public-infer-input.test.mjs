import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {exercisePublicInferInput} from './fixtures/public-infer-input.mjs';

const fixture = JSON.parse(await readFile(new URL(
  '../spec/frontend/fixtures/infer-keep/packed-acceptance.json',
  import.meta.url), 'utf8'));
const authored = JSON.parse(await readFile(new URL(
  '../spec/frontend/fixtures/infer-keep/expected-outcomes.json',
  import.meta.url), 'utf8'));

test('prepared packed expectations retain independent types and nullable values', () => {
  assert.equal(fixture.execution_status, 'not_run');
  assert.deepEqual(fixture.columns.kept, authored.result_columns);
  assert.deepEqual(fixture.expected_rows.kept, authored.kept_rows);
  assert.deepEqual(fixture.expected_rows.filtered, authored.filtered_rows);
  assert.deepEqual(fixture.expected_rows.omitted, [
    {assessment: {input_key: {id: 'a'}, outcome: 'ok',
      value: {risk: 'high', reason: null}}},
    {assessment: {input_key: {id: 'b'}, outcome: 'failed:refusal', value: null}},
  ]);
  assert.deepEqual(fixture.source_rows.empty, []);
  assert.deepEqual(fixture.expected_rows.empty, []);
  for (const item of fixture.successes) {
    assert.ok(Object.hasOwn(fixture.source_rows, item.source_rows));
    assert.ok(Object.hasOwn(fixture.columns, item.columns));
    assert.ok(Object.hasOwn(fixture.expected_rows, item.expected_rows));
  }
});

// Canned responses only test that the acceptance assertions fail closed.
// They do not execute a Program, implement INFER or count as packed evidence.
function assertionProbe({wrongRows = false, wrongColumns = false,
  repeatDispatch = false, missingCaptureObservation = false,
  wrongDispatchCount = false} = {}) {
  const one = structuredClone(fixture);
  one.successes = [one.successes[0]];
  one.preparation_refusals = [];
  one.preflight_failures = [];
  const counters = {acceptedRuns: 0, sourceIo: 0, modelDispatches: 0,
    capturedSlots: 0};
  const ref = {tenant: 'assertion-only', scope: 'assertion-only', run: 'run'};
  let closed = false;
  let submissions = 0;
  const columns = structuredClone(one.columns.kept);
  if (wrongColumns) columns[2].contract.fields.value.nullable = false;
  const rows = structuredClone(one.expected_rows.kept);
  if (wrongRows) rows[1].assessment.value = {};
  const description = {ref, resultName: 'answer', columns,
    serialization: {format: 'jsonl', version: 'actql-jsonl/0.1'}};
  const execution = {ref,
    wait: async () => ({status: 'succeeded'}),
    result: () => ({describe: async () => description,
      all: async () => {
        if (repeatDispatch) counters.modelDispatches++;
        return rows;
      }}),
  };
  const client = {
    aql: async text => {
      if (text.endsWith(' |> LIMIT 1')) {
        throw Object.assign(new Error('intent conflict'),
          {code: 'ClientRequestIntentConflict'});
      }
      if (submissions++ === 0) {
        counters.acceptedRuns++;
        counters.sourceIo++;
        counters.modelDispatches += wrongDispatchCount ? 1 : 2;
        counters.capturedSlots += 2;
      }
      return execution;
    },
    attach: async () => execution,
    lookupRequest: async () => ({kind: 'found', ref}),
    close: () => {closed = true;},
  };
  return {run: () => exercisePublicInferInput(async () => client, {},
    {fixture: one, requestPrefix: 'assertion-only', prepareCase: async () => {},
      observe: async () => missingCaptureObservation
        ? {...counters, capturedSlots: undefined} : counters}),
    isClosed: () => closed};
}

test('assertion-only control exercises the public call sequence', async () => {
  const probe = assertionProbe();
  assert.equal((await probe.run()).length, 1);
  assert.equal(probe.isClosed(), true);
});

for (const [name, option] of [
  ['wrong typed NULL', 'wrongRows'],
  ['wrong nested nullability', 'wrongColumns'],
  ['model dispatch on Result re-read', 'repeatDispatch'],
  ['missing retained capture observation', 'missingCaptureObservation'],
  ['wrong initial model dispatch count', 'wrongDispatchCount'],
]) {
  test(`acceptance assertion rejects ${name}`, async () => {
    const probe = assertionProbe({[option]: true});
    await assert.rejects(probe.run(), {code: 'ERR_ASSERTION'});
    assert.equal(probe.isClosed(), true);
  });
}
