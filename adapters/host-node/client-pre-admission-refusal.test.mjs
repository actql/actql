import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp, rm} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {open} from '../../packages/node/index.mjs';
import {getSubmissionOutcome} from '../../packages/sdk/index.mjs';

function overLimitProgram() {
  return {version: 'actql/0.1', id: 'original-capacity-refusal', stages: [{
    id: 'main', inputs: {}, steps: [{as: 'input', values: {
      schema: {id: {type: 'number', nullable: false}},
      rows: Array.from({length: 101}, (_, id) => ({id})),
    }}, {from: 'input', filter: 'id >= 50', as: 'filtered'}],
    results: {rows: {from: 'filtered', fields: ['id']}},
  }], results: {answer: {from: {stage: 'main', result: 'rows'}}}};
}

for (const named of [false, true]) {
  test(`${named ? 'named' : 'anonymous'} capacity refusal retains its original submission through reopen`, async () => {
    const directory = await mkdtemp(join(tmpdir(), 'actql-pre-admission-'));
    let client, closed = false;
    try {
      client = await open({stateDir: directory, installation: {valuesMaxRows: 100}});
      let original;
      await assert.rejects(client.start(overLimitProgram(), named ? {requestId: 'capacity-refusal'} : {}), error => {
        assert.equal(error.code, named ? 'SubmissionPreparationFailed' : 'SubmissionNotAccepted');
        original = getSubmissionOutcome(error);
        assert.equal(original.kind, named ? 'preparation_failed' : 'not_accepted');
        assert.deepEqual(original.problem, {code: 'ClientProgramUnsupported', classification: 'implementation_limit'});
        assert.equal('admission' in original, false);
        return true;
      });
      assert.deepEqual(await client.lookupSubmission(original.submissionRef), original);
      await client.close();
      client = await open({stateDir: directory, installation: {valuesMaxRows: 100}});
      assert.deepEqual(await client.lookupSubmission(original.submissionRef), original);
      const supported = overLimitProgram();
      supported.stages[0].steps[0].values.rows = [{id: 0}, {id: 1}];
      supported.stages[0].steps[1].filter = 'id >= 0';
      const run = await client.start(supported, {requestId: 'within-limit-control'});
      assert.equal((await run.wait({signal: AbortSignal.timeout(10000)})).status, 'succeeded');
      assert.deepEqual(await run.result('answer').all(), [{id: 0}, {id: 1}]);
    } finally {
      if (client) {await client.close(); closed = true;}
      if (closed) await rm(directory, {recursive: true, force: true});
    }
  });
}
