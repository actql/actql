import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdir, mkdtemp, readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {inspect} from 'node:util';
import {setImmediate} from 'node:timers/promises';
import {connectEmbeddedLocal} from './embedded-local.mjs';
import {createHostObservationConnection} from '../host-common/observation.mjs';
import {scaffoldProject} from '../../packages/native-cli/lib/project-scaffold.mjs';

// Actual source-checkout Common/Host/Source/Model/Store and the original
// Quickstart Program. Optional telemetry is not send permission or an FD ACK.
test('actual Mock Effect Source attempts retain the same public Run correlation', async t => {
  const scratch = new URL('../../_build/effect-source-observation/', import.meta.url);
  await mkdir(scratch, {recursive: true});
  const directory = await mkdtemp(join(scratch.pathname, 'original-'));
  const project = scaffoldProject(join(directory, 'project'), 'churn-risk-mock');
  const records = [];
  const observation = createHostObservationConnection({deliver: record => records.push(record)});
  const cwd = process.cwd();
  let client, primary;
  process.chdir(project.directory);
  t.diagnostic(JSON.stringify({directory: project.directory}));
  try {
    const before = await readFile('mock/data.json');
    client = await connectEmbeddedLocal({mode: 'local', owner: 'local', profile: 'mock',
      installation: {directory: '.actql', observation}});
    const execution = await client.startSource(await readFile('churn-risk.aql', 'utf8'),
      {format: 'aql', stopBefore: 'commit'});
    const state = await execution.wait();
    assert.equal(state.status, 'waiting_checkpoint');
    const runCid = execution.ref.runDefinitionCid;
    assert.equal(typeof runCid, 'string');
    const sources = () => records.filter(record => record.operation === 'source' &&
      record.event === 'attempt_started' &&
      record.attributes['actql.run.definition_cid'] === runCid);
    for (let turn = 0; turn < 512 && sources().length < 2; turn++) await setImmediate();
    assert.equal(sources().length, 2, 'both actual Source occurrences must be observable on their same Run');
    assert.equal(records.filter(record => record.operation === 'source' &&
      record.event === 'attempt_completed' &&
      record.attributes['actql.run.definition_cid'] === runCid).length, 2);
    assert.deepEqual(sources().map(record => record.attributes['actql.task.ordinal']).sort(), [0, 1]);
    assert.deepEqual(await readFile('mock/data.json'), before,
      'capturing observations never approves or applies the Effect');
    for (const name of ['dropped', 'deliveryFailed', 'budgetUnavailable', 'queueOverflow', 'limited']) {
      assert.equal(observation.status()[name], 0, name);
    }
    assert.deepEqual(observation.status().loss, {});
  } catch (cause) {
    primary = cause;
    t.diagnostic(JSON.stringify({failure: inspect(cause, {depth: 4}),
      events: records.map(record => ({operation: record.operation, event: record.event,
        run: record.attributes['actql.run.definition_cid']}))}));
  } finally {
    try {await client?.close();}
    catch (cause) {primary = primary === undefined ? cause
      : new AggregateError([primary, cause], 'Original execution and Host cleanup failed');}
    process.chdir(cwd);
  }
  if (primary !== undefined) throw primary;
});
