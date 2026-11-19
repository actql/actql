import assert from 'node:assert/strict';
import test from 'node:test';
import {createHash} from 'node:crypto';
import {runReleaseProjectSequences, assertProjectSequenceRows, assertTemplateStatic, assertProjectNodeWork} from './release-project-sequences.mjs';
import {readFileSync} from 'node:fs';
import {observeNativeMockHarnessPhase} from './native-approval-performance.mjs';
import {requireNativeMockWork} from './native-cli-mock-scenario.mjs';

// Independently authored port DATA, not a Native/SQLite/installed execution.
const sourceData = template => template === 'churn-risk-mock' ? {
  salesforce: {Account: {key: ['id'], rows: [
    {id: '001Acme', name: 'Acme Corp', description: 'Acme notes', Churn_Risk__c: 'low', Risk_Reason__c: null},
    {id: '001Globex', name: 'Globex Inc', description: 'Globex notes', Churn_Risk__c: 'medium', Risk_Reason__c: null},
  ]}}, snowflake: {usage_30d: {rows: [
    {account_id: '001Acme', active_users: 4, trend: 'down'}, {account_id: '001Globex', active_users: 12, trend: 'flat'},
  ]}},
} : {salesforce: {Opportunity: {key: ['id'], rows: [
  {id: '006Acme', name: 'Acme renewal', StageName: 'Proposal', NextStep: null},
  {id: '006Globex', name: 'Globex expansion', StageName: 'Negotiation', NextStep: 'Legal review'},
]}}, drive: {files: {rows: [
  {name: 'Acme renewal', content_utf8: 'Independent Acme notes\n'},
  {name: 'Globex expansion', content_utf8: 'Independent Globex notes\n'},
]}}};

function fixture({failApproval = false, replaceRun = false, mutateSavedRows = false, mutateUnrelated = false} = {}) {
  const projects = new Map(), records = [], calls = [], failure = new Error('original Unknown approval');
  let ordinal = 0, pid = 100;
  const plan = {version: 'actql-effectful-static-plan-view/0.1', observation: 'static', provider_io: 0,
    computation: {plan_view: {logical_map: {steps: [{operator: 'join'}, {operator: 'infer'}]}}},
    effect_set: {members: [{effect_kind: 'update', input: {kind: 'result', result_name: 'updates'}}]}};
  const check = {outcome: 'completed', report: {verdict: 'verified', runnable: {verdict: 'yes', reasons: []}}};
  const current = run => ({version: 'actql-run-state/0.1', run_id: run.original.runId, status: run.status,
    checkpoint: {id: run.original.checkpointId, checkpoint_id: run.original.checkpointId,
      checkpoint_cid: run.original.checkpointCid}});
  function start(project) {
    const value = projects.get(project), n = ++ordinal;
    const original = {runId: 'run-' + n, checkpointId: 'checkpoint-' + n,
      checkpointCid: 'sha256:' + n.toString(16).padStart(64, '0'),
      ref: {namespaceId: 'same-project', authorityScopeCid: 'sha256:' + 'a'.repeat(64),
        runDefinitionCid: 'sha256:' + (n + 100).toString(16).padStart(64, '0')}};
    const run = {original, before: structuredClone(value.data), status: 'waiting_checkpoint'};
    value.runs.push(run); return run;
  }
  function resolve(value, run, decision, label) {
    if (failApproval && label.family === 'native-after-approve' && label.ordinal === 2) throw failure;
    run.status = decision === 'approved' ? 'succeeded' : 'cancelled';
    if (decision === 'approved') {
      const resource = value.template === 'churn-risk-mock' ? 'Account' : 'Opportunity';
      for (const row of value.data.salesforce[resource].rows) {
        const first = row.id.endsWith('Acme');
        Object.assign(row, resource === 'Account' ? {Churn_Risk__c: 'high', Risk_Reason__c: first
          ? 'falling usage and a competitor evaluation' : 'support tickets about pricing'}
          : {StageName: first ? 'Negotiation' : 'Closed Lost', NextStep: first
            ? 'Send revised pricing by Friday' : 'Revisit next fiscal year'});
      }
      if (mutateUnrelated) value.data.unrelated = 'unexpected write';
      value.generation++;
    }
  }
  function rows(value, run) {
    const before = mutateSavedRows ? value.data : run.before;
    if (value.template === 'churn-risk-mock') return before.salesforce.Account.rows.map((row, i) => ({
      id: row.id, notes: row.description, active_users: before.snowflake.usage_30d.rows[i].active_users,
      trend: before.snowflake.usage_30d.rows[i].trend, risk: {outcome: 'ok', value: {level: 'high', reason: i === 0
        ? 'falling usage and a competitor evaluation' : 'support tickets about pricing'}},
    }));
    return before.salesforce.Opportunity.rows.map((row, i) => {
      const notes = before.drive.files.rows[i].content_utf8;
      return {id: row.id, StageName: row.StageName, NextStep: row.NextStep,
        notes: {$actql_ref: 'content', media_type: 'text/plain', metadata: {
          content_cid: 'sha256:' + createHash('sha256').update(notes).digest('hex'),
          size_bytes: Buffer.byteLength(notes), truncated: false}},
        review: {outcome: 'ok', value: {changed: true, stage: i === 0 ? 'Negotiation' : 'Closed Lost',
          next_step: i === 0 ? 'Send revised pricing by Friday' : 'Revisit next fiscal year'}}};
    });
  }
  return {projects, records, calls, failure, options: {root: '/owned-installed-consumer',
    async snapshot(project) {const p = projects.get(project); return {bytes: JSON.stringify(p.data), generation: p.generation};},
    async persist(record) {records.push(structuredClone(record));},
    async cli(args, project, label) {
      calls.push({surface: 'cli', args, project, ...label});
      if (args[0] === 'init') {
        assert(!projects.has(project), 'Never scaffold/reset an existing sequence project');
        projects.set(project, {template: args[2], data: sourceData(args[2]), generation: 0, runs: []});
        return {code: 0, signal: null, stdout: '', pid: ++pid};
      }
      const value = projects.get(project); let reply;
      if (args[0] === 'check') reply = check;
      else if (args[0] === 'explain' && args[1] !== '--run') reply = plan;
      else if (args[0] === 'explain') {
        const run = value.runs.find(run => run.original.runId === args[2]); assert(run);
        reply = {version: 'actql-run-plan-view/0.1', run_ref: run.original.ref};
      } else if (args[0] === 'run') {
        const run = replaceRun && value.runs.length ? value.runs[0] : start(project); reply = current(run);
      } else if (args[0] === 'approve' || args[0] === 'reject') {
        const run = value.runs.find(run => run.original.checkpointId === args[1]); assert(run);
        resolve(value, run, args[0] === 'approve' ? 'approved' : 'rejected', label); reply = {};
      } else {
        const run = value.runs.find(run => run.original.runId === args[1]); assert(run);
        if (args[0] === 'result') return {code: 0, signal: null, pid: ++pid,
          stdout: rows(value, run).map(row => JSON.stringify(row)).join('\n') + '\n'};
        assert.equal(args[0], 'status'); reply = current(run);
      }
      return {code: 0, signal: null, pid: ++pid, stdout: JSON.stringify(reply)};
    },
    async node(request, project, label) {
      calls.push({surface: 'node', kind: request.kind, project, ...label});
      const counts = {sourceAcquisitionStarts: request.kind === 'start' ? 2 : 0,
        modelCallStarts: request.kind === 'start' ? 2 : 0, effectReplacementReturns: request.decision === 'approved' ? 2 : 0};
      const value = projects.get(project), base = {pid: ++pid, firstClose: {attempted: true, returned: true},
        workObservation: {...counts, totals: {...counts}, complete: true}};
      if (request.kind === 'static') return {...base, check, plan};
      let run;
      if (request.kind === 'start') {
        run = start(project);
        if (request.decision) resolve(value, run, request.decision, label);
      } else {run = value.runs.find(run => run.original.runId === request.original.runId); assert(run);}
      if (request.kind === 'resolve') resolve(value, run, request.decision, label);
      const result = {...base, original: run.original, state: current(run)};
      if (request.kind === 'result') {
        result.rows = rows(value, run);
        result.description = {ref: run.original.ref, resultName: 'updates',
          columns: Object.keys(result.rows[0]).map(name => ({name, contract: {type: 'fixture-only'}})),
          resultArtifactCid: 'independent-original-artifact-' + run.original.runId};
      }
      return result;
    },
  }};
}

test('RC sequences retain one project for new Run2/3 and exclusive CLI/Node round trips', async () => {
  const f = fixture(), cases = await runReleaseProjectSequences(f.options);
  for (const template of ['churn-risk-mock', 'deal-review-mock']) for (const family of [
    'native-while-waiting', 'native-after-approve', 'native-after-reject', 'node-sequential', 'exclusive-cli-node-roundtrip']) {
    const entry = cases.find(row => row.template === template && row.family === family); assert(entry?.complete);
    const calls = f.calls.filter(row => row.project === entry.project);
    assert.equal(calls.filter(row => row.args?.[0] === 'init').length, 1);
    assert.equal(new Set(entry.runs.map(run => run.original.runId)).size, entry.runs.length);
    if (family.startsWith('native-')) assert.equal(entry.runs.length, 3);
    if (family === 'exclusive-cli-node-roundtrip') {
      assert(calls.some(row => row.surface === 'node' && row.kind === 'resolve'));
      assert(calls.some(row => row.surface === 'cli' && row.args?.[0] === 'approve'));
      assert(calls.some(row => row.surface === 'node' && row.kind === 'result'));
    }
    assert(entry.phases.some(row => row.phase === 'result') || family.includes('reject') || family.includes('waiting'));
  }
  assert(f.records.every(row => row.complete));
});

test('RC uncertain approval stops that project without replay or hiding independent case failures', async () => {
  const f = fixture({failApproval: true});
  await assert.rejects(runReleaseProjectSequences(f.options), error => error.cause === f.failure);
  for (const entry of f.records.filter(row => row.family === 'native-after-approve')) {
    assert.equal(entry.complete, false);
    const calls = f.calls.filter(row => row.project === entry.project);
    assert.equal(calls.filter(row => row.args?.[0] === 'run').length, 2);
    assert.equal(calls.filter(row => row.args?.[0] === 'approve' && row.ordinal === 2).length, 1);
  }
  assert(f.records.some(row => row.complete && row.family === 'native-after-reject'));
});

for (const [name, options] of [['reused Run', {replaceRun: true}], ['latest target as old Result', {mutateSavedRows: true}],
  ['unrelated target change', {mutateUnrelated: true}]]) test(`RC independent original/target oracle refuses ${name}`, async () => {
  const f = fixture(options);
  await assert.rejects(runReleaseProjectSequences(f.options), AggregateError);
  assert(f.records.some(row => !row.complete));
});

test('RC Result oracle rejects missing whole fields and changed Model values', () => {
  const before = {bytes: JSON.stringify(sourceData('churn-risk-mock'))};
  assert.throws(() => assertProjectSequenceRows('churn-risk-mock', [{id: '001Acme'}, {id: '001Globex'}], before));
  const rows = [
    {id: '001Acme', notes: 'Acme notes', active_users: 4, trend: 'down', risk: {outcome: 'ok', value: {
      level: 'high', reason: 'falling usage and a competitor evaluation'}}},
    {id: '001Globex', notes: 'Globex notes', active_users: 12, trend: 'flat', risk: {outcome: 'ok', value: {
      level: 'high', reason: 'support tickets about pricing'}}},
  ];
  assert.doesNotThrow(() => assertProjectSequenceRows('churn-risk-mock', rows, before));
  rows[0].risk.value.level = 'low';
  assert.throws(() => assertProjectSequenceRows('churn-risk-mock', rows, before));
});

test('RC template check uses the actual typed runnable verdict and refuses a boolean substitute', () => {
  const check = JSON.parse(readFileSync(new URL('../packages/client-wire/fixtures/check-outcome-pins.verified.json', import.meta.url), 'utf8'));
  const plan = {version: 'actql-effectful-static-plan-view/0.1', observation: 'static', provider_io: 0,
    computation: {plan_view: {logical_map: {steps: [{operator: 'infer'}, {operator: 'join'}]}}},
    effect_set: {members: [{effect_kind: 'update', input: {kind: 'result', result_name: 'updates'}}]}};
  assert.doesNotThrow(() => assertTemplateStatic(check, plan));
  for (const runnable of [true, {verdict: 'no', reasons: []}, {verdict: 'unknown', reasons: []}])
    assert.throws(() => assertTemplateStatic({...check, report: {...check.report, runnable}}, plan));
  assert.throws(() => assertTemplateStatic(check, {...plan, provider_io: 1}));
  assert.throws(() => assertTemplateStatic({...check, report: {...check.report, verdict: 'undetermined'}}, plan));
});

test('RC zero-work and reuse claims require complete same-Run observations', () => {
  const empty = {sourceAcquisitionStarts: 0, modelCallStarts: 0, effectReplacementReturns: 0};
  const work = {...empty, totals: {...empty}, complete: true};
  assert.doesNotThrow(() => assertProjectNodeWork(work, {kind: 'result'}, 2));
  for (const changed of [undefined, {...work, complete: false}, {...work, modelCallStarts: 1},
    {...work, totals: {...empty, modelCallStarts: 1}}])
    assert.throws(() => assertProjectNodeWork(changed, {kind: 'result'}, 2));
  const template = 'churn-risk-mock', changed = sourceData(template), same = sourceData(template);
  Object.assign(same.salesforce.Account.rows[0], {Churn_Risk__c: 'high',
    Risk_Reason__c: 'falling usage and a competitor evaluation'});
  Object.assign(same.salesforce.Account.rows[1], {Churn_Risk__c: 'high',
    Risk_Reason__c: 'support tickets about pricing'});
  const request = before => ({kind: 'resolve', decision: 'approved', beforeBytes: JSON.stringify(before)});
  assert.doesNotThrow(() => assertProjectNodeWork(work, request(same), 2, template),
    'An approved same-value no-op is not required to perform another replacement');
  assert.throws(() => assertProjectNodeWork(work, request(changed), 2, template),
    'An initial changed target requires actual replacements');
  const observed = count => ({...work, effectReplacementReturns: count,
    totals: {...empty, effectReplacementReturns: count}});
  assert.throws(() => assertProjectNodeWork(observed(1), request(changed), 2, template));
  assert.doesNotThrow(() => assertProjectNodeWork(observed(2), request(changed), 2, template));
  same.salesforce.Account.rows[1].Churn_Risk__c = 'medium';
  assert.throws(() => assertProjectNodeWork(work, request(same), 2, template));
  assert.doesNotThrow(() => assertProjectNodeWork(observed(1), request(same), 2, template));
  assert.throws(() => assertProjectNodeWork(work, {kind: 'resolve', decision: 'approved'}, 2, template),
    'Missing original before DATA cannot prove a no-op');
});

test('RC sequence phase uses the existing observer and preserves an original failed action', async () => {
  const records = [], primary = new Error('original RC failure');
  await assert.rejects(observeNativeMockHarnessPhase(records, 'release-project-sequences', async () => {throw primary;}),
    value => value === primary);
  assert.equal(records[0].state, 'failed'); assert(Number.isSafeInteger(records[0].wallNs));
});

test('RC same-value Native approval keeps original trace validation without requiring a redundant replacement', () => {
  assert.throws(() => requireNativeMockWork(['approve'], [{events: []}], 2));
  assert.deepEqual(requireNativeMockWork(['approve'], [{events: []}], 2, {minimumWrites: 0}).writes, []);
  assert.throws(() => requireNativeMockWork(['run'], [{events: []}], 2, {minimumWrites: 0}));
  assert.throws(() => requireNativeMockWork(['status'], [{events: [{tag: 0, ordinal: 0, identity: 'unexpected'}]}], 2));
});
