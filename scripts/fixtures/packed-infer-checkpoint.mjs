import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {connect} from '@actql/node';

const fixture = JSON.parse(await readFile('infer-acceptance.json', 'utf8'));
const {openInferTestHost} = await import(pathToFileURL(resolve(process.argv[2])));
const failures = [];
for (const mode of ['local', 'remote']) {
  const host = await openInferTestHost({mode, fixture});
  let client;
  try {
    client = await connect(host.options);
    const signal = AbortSignal.timeout(60_000);
    for (const name of ['json-control', 'json-projected', 'source-as']) {
      const before = host.observe();
      try {
        const requestId = `packed-infer-${mode}-${name}`;
        const program = name === 'json-control' ? fixture.control_program : fixture.projected_program;
        const run = name !== 'source-as'
          ? await client.start(program, {requestId})
          : await client.aql(fixture.source, {format: 'aql-text', requestId});
        const state = await run.wait({signal});
        assert.equal(state.status, 'succeeded');
        const result = run.result('answer');
        const description = await result.describe({signal});
        if (name === 'json-control') {
          assert.deepEqual(description.columns, fixture.control_columns);
        }
        const expected = name === 'json-control'
          ? fixture.control_rows : fixture.source_rows;
        assert.deepEqual(await result.all({signal}), expected);
        await host.assertCapture(run);
        const after = host.observe();
        assert.equal(after.acceptedRuns - before.acceptedRuns, 1);
        assert.equal(after.modelDispatches - before.modelDispatches, 1);
        const resent = name !== 'source-as'
          ? await client.start(program, {requestId})
          : await client.aql(fixture.source, {format: 'aql-text', requestId});
        assert.deepEqual(resent.ref, run.ref);
        assert.deepEqual(await result.all({signal}), expected);
        assert.deepEqual(host.observe(), after);
        console.log(JSON.stringify({mode, name, status: 'passed',
          ref: run.ref, columns: description.columns, rows: expected, after}));
      } catch (error) {
        const record = {mode, name, status: 'failed', code: error.code,
          message: error.message, cause: error.cause,
          before, after: host.observe(), observations: host.observations};
        console.log(JSON.stringify(record, (_, value) =>
          typeof value === 'bigint' ? String(value) : value));
        failures.push(`${mode}:${name}`);
      }
    }
  } finally {
    await client?.close();
    await host.close();
  }
}
assert.deepEqual(failures, [], 'Every selected path must pass; refusals remain unfinished acceptance');
