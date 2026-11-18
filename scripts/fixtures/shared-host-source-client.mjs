// Independent public CLI client of one installed Remote Host. No Source,
// scheduler, cancellation or Store implementation is supplied by this caller.
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {pathToFileURL} from 'node:url';
import {readFile, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {publishStandardRestBarrier} from './external-rest/cancel-conformance.mjs';

const [configurationPath, phase] = process.argv.slice(2);
assert(process.argv.length === 4 && ['first', 'second'].includes(phase));
const configuration = JSON.parse(await readFile(configurationPath, 'utf8'));
const require = createRequire(join(configuration.consumerRoot, 'package.json'));
const nodePath = require.resolve('@actql/node');
const {connect} = await import(pathToFileURL(nodePath).href);
const sdk = createRequire(nodePath)('@actql/sdk');
const save = (name, value) => writeFile(join(configuration.outputRoot, name),
  JSON.stringify(value, null, 2) + '\n', {flag: 'wx', mode: 0o600});
const report = {phase, passed: false};
let client, primary, failed = false;
try {
  client = await connect({mode: 'remote', endpoint: configuration.endpoint,
    token: 'fixture-token', durability: 'durable'});
  const program = JSON.parse(await readFile(configuration.programPath, 'utf8'));
  const pending = client.startSource(JSON.stringify(program), {format: 'json',
    attemptId: `shared-source-${phase}`});
  const settled = pending.then(value => ({value}), cause => ({failed: true, cause}));
  const input = sdk.getSubmissionInput(pending); assert(input);
  await save(`source-${phase}-original-input.json`, input);
  const submission = await settled;
  if (submission.failed) throw submission.cause;
  const execution = submission.value;
  await publishStandardRestBarrier(join(configuration.outputRoot, `source-${phase}-run.json`),
    JSON.stringify(execution.ref) + '\n');
  report.originalRefBeforeWait = true;
  const state = await execution.wait({signal: AbortSignal.timeout(30_000)});
  await save(`source-${phase}-terminal.json`, state);
  if (phase === 'first') {
    assert.equal(state.status, 'cancelled'); assert.equal(state.result_available, false);
    assert.equal(state.control.cancellation_requested, true);
    assert.equal(state.control.physical_stop, 'confirmed');
  } else {
    assert.equal(state.status, 'succeeded'); assert.equal(state.result_available, true);
    assert.equal(state.control.cancellation_requested, false);
    const rows = await execution.result('rows').all();
    await save('source-second-rows.json', rows);
    assert.deepEqual(rows, [{id: 'alpha', amount: 7, note: 'e\u0301'},
      {id: 'beta', amount: 2, note: '東京'}, {id: 'gamma', amount: 11, note: ''}]);
  }
  report.passed = true;
} catch (error) {
  failed = true; primary = error;
  report.failure = {name: error?.name, code: error?.code, message: error?.message};
  report.originalPublicAttempt = sdk.getSubmissionAttempt(error);
  report.originalPublicOutcome = sdk.getSubmissionOutcome(error);
} finally {
  if (client !== undefined) {
    try {await client.close(); report.clientCloseReturned = true;}
    catch (cleanup) {
      report.clientCloseReturned = false; report.passed = false;
      report.cleanupFailure = {name: cleanup?.name, code: cleanup?.code, message: cleanup?.message};
      primary = failed ? new AggregateError([primary, cleanup], 'Shared Source client and close failed') : cleanup;
      failed = true;
    }
  }
  await save(`source-${phase}-report.json`, report);
}
if (failed) throw primary;
console.log(JSON.stringify({stage: 'source-client-complete', phase, clientCloseReturned: report.clientCloseReturned}));
