// These are acceptance-harness unit tests with explicit doubles. A green result
// here does not establish that the Native mock workflow is implemented.
import assert from 'node:assert/strict';
import {test} from 'node:test';
import {mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {scaffoldProject} from '../packages/native-cli/lib/project-scaffold.mjs';
import {mockTemplates, runNativeCliMockScenario} from './native-cli-mock-scenario.mjs';

test('installed Mock acceptance requires both complete same-cohort public templates without skips', async () => {
  assert.deepEqual(mockTemplates, ['deal-review-mock', 'churn-risk-mock']);
  const installed = await readFile(new URL('./test-native-cli-mock-install.mjs', import.meta.url), 'utf8');
  for (const requirement of ['await verifyNativeCliRelease(directory)',
    "assert.equal(source.revision, manifest.sourceSha",
    'assert(expectedArtifact?.localRuntime',
    'for (const template of mockTemplates) scenarios.push(await runNativeCliMockScenario',
    "assert.equal(scenarios.length, 2, 'Both README and Quickstart must finish without skips')",
    "run(process.execPath, [launcher, ...args], cwd)",
    "records.push(record)", "await writeFile(join(root, 'commands.json')"]) {
    assert(installed.includes(requirement), requirement);
  }
  assert.equal(installed.indexOf('await registry.close()') < installed.indexOf('await writeFile(receiptFile'), true);
});

async function fixture(t, template, mutate = () => {}) {
  const root = await mkdtemp(join(tmpdir(), 'actql-mock-scenario-unit-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const file = join(root, template, 'mock/data.json');
  let approved = false, reads = 0;
  const updates = template === 'deal-review-mock' ? [
    {id: '006Acme', StageName: 'Negotiation', NextStep: 'Send revised pricing by Friday'},
    {id: '006Globex', StageName: 'Closed Lost', NextStep: 'Revisit next fiscal year'},
  ] : [
    {id: '001Acme', Churn_Risk__c: 'high', Risk_Reason__c: 'falling usage and a competitor evaluation'},
    {id: '001Globex', Churn_Risk__c: 'high', Risk_Reason__c: 'support tickets about pricing'},
  ];
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
    if (args[0] === 'status' && !args.includes('--json')) {
      assert.equal(approved, false);
      const resource = template === 'deal-review-mock' ? 'Opportunity' : 'Account';
      const originals = JSON.parse(await readFile(file, 'utf8')).salesforce[resource].rows;
      record.stdout = ['Run: "unit-original-run"', 'State: "waiting_checkpoint"',
        'Checkpoint: "unit-original-checkpoint"', `  Original CID: "sha256:${'a'.repeat(64)}"`,
        'Stored Effect Preview (read-only; not approval):',
        `  Effect: "update"  Target: "connector://salesforce/${resource}"`, '  Items: 2',
        '  Preview strength: "full_diff"', '  Changes:', ...updates.flatMap(update => [
          '    Row: ' + JSON.stringify(update.id),
          '      Before: ' + JSON.stringify({state: 'present', value: originals.find(row => row.id === update.id)}),
          '      After: ' + JSON.stringify({state: 'present', value:
            Object.fromEntries(Object.entries(update).filter(([name]) => name !== 'id'))}),
        ])].join('\n') + '\n';
    }
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
    ['init', 'run', 'status', 'status', 'approve', 'status', 'result', 'status', 'result']);
  assert.equal(options.calls.filter(({args}) => args[0] === 'run').length, 1);
  assert.equal(options.calls.filter(({args}) => args[0] === 'approve').length, 1);
  assert.deepEqual(receipt.humanWaiting, {runId: 'unit-original-run', checkpointId: 'unit-original-checkpoint',
    checkpointCid: `sha256:${'a'.repeat(64)}`, rows: 2});
  assert.deepEqual(options.calls.filter(({args}) => args[0] === 'status' && !args.includes('--json'))
    .map(({args}) => args), [['status', 'unit-original-run']]);
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


test('harness refuses deferring the approved Effect until status', async t => {
  let before, deferred;
  const options = await fixture(t, 'deal-review-mock', async ({args, file}) => {
    if (args[0] === 'run') before = await readFile(file);
    if (args[0] === 'approve') {
      deferred = await readFile(file);
      await writeFile(file, before);
    } else if (args[0] === 'status' && deferred) {
      await writeFile(file, deferred);
    }
  });
  await assert.rejects(runNativeCliMockScenario(options), /expected target fields/u);
});

test('harness refuses same-byte Effect replay during completed status', async t => {
  const options = await fixture(t, 'deal-review-mock', async ({args, record, file}) => {
    if (args[0] === 'status' && args.includes('--json') && JSON.parse(record.stdout).status === 'succeeded') {
      await writeFile(file, await readFile(file));
    }
  });
  await assert.rejects(runNativeCliMockScenario(options), /Completed status must not rewrite/u);
});


for (const operation of ['approve', 'result']) {
  test(`harness refuses consulting Model answers during ${operation} recovery`, async t => {
    const options = await fixture(t, 'deal-review-mock', async ({args, file}) => {
      if (args[0] === operation) {
        await readFile(join(file, '..', 'deal-review.v1.answers.yaml'));
      }
    });
    await assert.rejects(runNativeCliMockScenario(options), {code: 'ENOENT'});
  });
}


for (const [name, mutate, pattern] of [
  ['State-only output without the stored Preview', ({record}) => {
    record.stdout = record.stdout.split('Stored Effect Preview')[0];
  }, /Human waiting Preview/u],
  ['a replacement Run in human output', ({record}) => {
    record.stdout = record.stdout.replace('unit-original-run', 'replacement-run');
  }, /Human waiting Preview/u],
  ['a replacement Checkpoint in human output', ({record}) => {
    record.stdout = record.stdout.replace('a'.repeat(64), 'b'.repeat(64));
  }, /Human waiting Preview/u],
  ['a Program alias instead of the original target URI', ({record}) => {
    record.stdout = record.stdout.replace('connector://salesforce/Opportunity', 'salesforce.Opportunity');
  }, /Human waiting Preview/u],
  ['a different connector target resource', ({record}) => {
    record.stdout = record.stdout.replace('connector://salesforce/Opportunity', 'connector://salesforce/Account');
  }, /Human waiting Preview/u],
  ['incorrect displayed before evidence', ({record}) => {
    record.stdout = record.stdout.replace('"StageName":"Proposal"', '"StageName":"Other"');
  }, /original before StageName/u],
  ['incorrect displayed intended changes', ({record}) => {
    record.stdout = record.stdout.replace('"StageName":"Negotiation"', '"StageName":"Other"');
  }, /intended after fields/u],
]) test(`harness refuses ${name}`, async t => {
  const options = await fixture(t, 'deal-review-mock', context => {
    if (context.args[0] === 'status' && !context.args.includes('--json')) mutate(context);
  });
  await assert.rejects(runNativeCliMockScenario(options), pattern);
});

test('harness rejects restricted Preview contents added to canonical JSON state', async t => {
  const options = await fixture(t, 'deal-review-mock', ({args, record}) => {
    if (args[0] === 'run') record.stdout = JSON.stringify({...JSON.parse(record.stdout),
      effect_preview: {before: 'restricted original'}});
  });
  await assert.rejects(runNativeCliMockScenario(options), /JSON Run state must not embed restricted Preview/u);
});
