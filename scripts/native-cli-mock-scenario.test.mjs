// These are acceptance-harness unit tests with explicit doubles. A green result
// here does not establish that the Native mock workflow is implemented.
import assert from 'node:assert/strict';
import {test} from 'node:test';
import {mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {scaffoldProject} from '../packages/native-cli/lib/project-scaffold.mjs';
import {mockTemplates, runNativeCliMockScenario} from './native-cli-mock-scenario.mjs';

async function fixture(t, template, mutate = () => {}) {
  const root = await mkdtemp(join(tmpdir(), 'actql-mock-scenario-unit-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const file = join(root, template, 'mock/data.json');
  let approved = false, reads = 0;
  const calls = [];
  const run = async (args, cwd) => {
    calls.push({args: [...args], cwd});
    let value;
    if (args[0] === 'init') scaffoldProject(args[3], args[2]);
    else if (args[0] === 'run' || args[0] === 'status') {
      value = {version: 'actql-run-state/0.1', run_id: 'unit-original-run',
        status: approved ? 'succeeded' : 'waiting_checkpoint',
        ...(approved ? {} : {checkpoint: {checkpoint_id: 'unit-original-checkpoint',
          checkpoint_cid: `sha256:${'a'.repeat(64)}`}})};
    } else if (args[0] === 'approve') {
      approved = true;
      const data = JSON.parse(await readFile(file, 'utf8'));
      if (template === 'deal-review-mock') {
        Object.assign(data.salesforce.Opportunity.rows[0],
          {StageName: 'Negotiation', NextStep: 'Send revised pricing by Friday'});
        Object.assign(data.salesforce.Opportunity.rows[1],
          {StageName: 'Closed Lost', NextStep: 'Revisit next fiscal year'});
      } else {
        Object.assign(data.salesforce.Account.rows[0],
          {Churn_Risk__c: 'high', Risk_Reason__c: 'falling usage and a competitor evaluation'});
        Object.assign(data.salesforce.Account.rows[1],
          {Churn_Risk__c: 'high', Risk_Reason__c: 'support tickets about pricing'});
      }
      await writeFile(file, JSON.stringify(data));
      value = {resolved: true};
    }
    const record = {code: 0, signal: null, stderr: '', stdout: value ? JSON.stringify(value) : ''};
    if (args[0] === 'result') {
      reads++;
      const ids = template === 'deal-review-mock' ? ['006Acme', '006Globex'] : ['001Acme', '001Globex'];
      const values = template === 'deal-review-mock' ? [
        {id: ids[0], StageName: 'Proposal', NextStep: null, review: {outcome: 'ok', value:
          {changed: true, stage: 'Negotiation', next_step: 'Send revised pricing by Friday'}}},
        {id: ids[1], StageName: 'Negotiation', NextStep: 'Legal review', review: {outcome: 'ok', value:
          {changed: true, stage: 'Closed Lost', next_step: 'Revisit next fiscal year'}}},
      ] : [
        {id: ids[0], risk: {outcome: 'ok', value: {level: 'high', reason: 'falling usage and a competitor evaluation'}}},
        {id: ids[1], risk: {outcome: 'ok', value: {level: 'high', reason: 'support tickets about pricing'}}},
      ];
      record.stdout = values.map(value => JSON.stringify(value)).join('\n') + '\n';
    }
    await mutate({args, record, file, reads});
    return record;
  };
  return {root, template, run, calls};
}

for (const template of mockTemplates) test(`harness requires the public ${template} approval and retained reread sequence`, async t => {
  const options = await fixture(t, template);
  const receipt = await runNativeCliMockScenario(options);
  assert.equal(receipt.runId, 'unit-original-run');
  assert.equal(receipt.resultRows, 2);
  assert.deepEqual(options.calls.map(({args}) => args[0]),
    ['init', 'run', 'status', 'approve', 'status', 'result', 'status', 'result']);
  assert.equal(options.calls.filter(({args}) => args[0] === 'run').length, 1);
});

for (const [name, mutate, pattern] of [
  ['unavailable bindings', ({args, record}) => {
    if (args[0] === 'run') Object.assign(record, {code: 1, stderr: 'LocalProjectBindingsUnavailable'});
  }, /LocalProjectBindingsUnavailable/u],
  ['success receipt without Run state', ({args, record}) => {
    if (args[0] === 'run') record.stdout = '{"kind":"prepared"}';
  }, /command receipt/u],
  ['changed recovered Run', ({args, record}) => {
    if (args[0] === 'status') record.stdout = record.stdout.replace('unit-original-run', 'replacement-run');
  }, /original Run/u],
  ['changed recovered preview', ({args, record}) => {
    if (args[0] === 'status') record.stdout = record.stdout.replace('a'.repeat(64), 'b'.repeat(64));
  }, /strictly equal/u],
  ['write before approval', async ({args, file}) => {
    if (args[0] === 'run') await writeFile(file, '{}');
  }, /before approval/u],
  ['unrelated changes on approval', async ({args, file}) => {
    if (args[0] === 'approve') {
      const data = JSON.parse(await readFile(file, 'utf8')); data.unrequested = true;
      await writeFile(file, JSON.stringify(data));
    }
  }, /expected target fields/u],
  ['missing Result row', ({args, record}) => {
    if (args[0] === 'result') record.stdout = '{"id":"006Acme"}\n';
  }, /expected updates/u],
  ['missing retained Model outcome', ({args, record}) => {
    if (args[0] === 'result') record.stdout = '{"id":"006Acme"}\n{"id":"006Globex"}\n';
  }, /Model outcome/u],
  ['replacement post-write Source result', ({args, record}) => {
    if (args[0] === 'result') record.stdout = record.stdout.replace('"StageName":"Proposal"', '"StageName":"Negotiation"');
  }, /pre-write Source/u],
  ['changed retained Result', ({args, record, reads}) => {
    if (args[0] === 'result' && reads === 2) record.stdout += '\n';
  }, /original bytes/u],
  ['same-byte Effect replay during reread', async ({args, file, reads}) => {
    if (args[0] === 'result' && reads === 2) await writeFile(file, await readFile(file));
  }, /rewrite the target/u],
]) test(`harness refuses ${name} instead of counting a skip or acceptance`, async t => {
  const options = await fixture(t, 'deal-review-mock', mutate);
  await assert.rejects(runNativeCliMockScenario(options), pattern);
});
