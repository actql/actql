import assert from 'node:assert/strict';
import test from 'node:test';
import {createHash} from 'node:crypto';
import {mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {basename, join} from 'node:path';
import {runOriginalMockRegressions} from './native-cli-mock-regressions.mjs';

// Explicit owner-local ports, not Native/SQLite/SDK or physical lock evidence.
function fixture(t, {noopNode = false, corruptSaved = false, mutateControl = false,
  lostClose = false, missingReadonlyRow = false, failNode = false, orphanFinalLock = false,
  retireLockDuringStatus = false, failFinalStatus = false} = {}) {
  const root = mkdtempSync(join(realpathSync(tmpdir()), 'actql-original-mock-ports-'));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  const projects = new Map(), programs = new Map(), calls = [], records = [];
  let serial = 0, pid = 1000;
  const primary = new Error('original uncertain Node operation');
  const statusFailure = new Error('original final status failure');
  const initial = () => ({salesforce: {Opportunity: {key: ['id'], rows: [
    {id: '006Acme', name: 'Acme Corp - Renewal', StageName: 'Proposal', NextStep: null},
    {id: '006Globex', name: 'Globex - Expansion', StageName: 'Negotiation', NextStep: 'Legal review'},
  ]}}, drive: {files: {key: ['id'], rows: [
    {id: 'notes-acme', name: 'Acme Corp - Renewal', content_utf8: 'Acme original notes'},
    {id: 'notes-globex', name: 'Globex - Expansion', content_utf8: 'Globex original notes'},
  ]}}, control: {keep: 'untouched'}});
  const state = run => ({version: 'actql-run-state/0.1', run_id: run.original.runId, status: run.status,
    checkpoint: {checkpoint_id: run.original.checkpointId, checkpoint_cid: run.original.checkpointCid}});
  function start(project, surface, program, readonly = false) {
    const n = ++serial, value = projects.get(project);
    const original = {runId: 'run-' + n, ref: {namespaceId: surface + '-root',
      authorityScopeCid: 'sha256:' + 'a'.repeat(64), runDefinitionCid: 'sha256:' + n.toString(16).padStart(64, '0')},
    ...(readonly ? {} : {checkpointId: 'checkpoint-' + n, checkpointCid: 'sha256:' + 'b'.repeat(64)})};
    const run = {original, surface, program, readonly, before: structuredClone(value.data),
      status: readonly ? 'succeeded' : 'waiting_checkpoint'};
    value.runs.push(run); return run;
  }
  function own(value, surface, id) {
    const run = value.runs.find(run => [run.original.runId, run.original.checkpointId].includes(id));
    assert(run); assert.equal(run.surface, surface, 'Never attach/read/approve a foreign owning root'); return run;
  }
  function approve(value, run) {
    if (!(noopNode && run.surface === 'node')) {
      for (const row of value.data.salesforce.Opportunity.rows) {
        const first = row.id === '006Acme';
        row.StageName = first ? 'Negotiation' : 'Closed Lost';
        row.NextStep = run.program === 'handoff.aql' ? 'Confirm the cross-Host handoff'
          : first ? 'Send revised pricing by Friday' : 'Revisit next fiscal year';
      }
      if (mutateControl) value.data.control.keep = 'foreign mutation';
      value.generation++;
    }
    run.status = 'succeeded';
  }
  function rows(run) {
    let rows;
    if (run.readonly) {
      if (run.program.includes('join')) rows = run.before.salesforce.Opportunity.rows.map(row => ({
        id: row.id, StageName: row.StageName, file_name: row.name}));
      else rows = run.before.salesforce.Opportunity.rows.filter(row => !run.program.includes('where') || row.StageName === 'Proposal');
      if (missingReadonlyRow) rows = rows.slice(1);
    } else rows = run.before.salesforce.Opportunity.rows.map((row, i) => {
      const notes = run.before.drive.files.rows[i].content_utf8;
      return {id: row.id, StageName: row.StageName, NextStep: row.NextStep,
        notes: {$actql_ref: 'content', media_type: 'text/plain', metadata: {
          content_cid: 'sha256:' + createHash('sha256').update(notes).digest('hex'),
          size_bytes: Buffer.byteLength(notes), truncated: false}},
        review: {outcome: 'ok', input_key: {id: row.id}, value: {changed: true,
          stage: i === 0 ? 'Negotiation' : 'Closed Lost', next_step: i === 0
            ? 'Send revised pricing by Friday' : 'Revisit next fiscal year'}}};
    });
    const result = structuredClone(rows);
    if (corruptSaved) result[0].StageName = 'not original';
    return result;
  }
  const description = run => {
    const text = {type: 'string', nullable: false};
    const columns = run.readonly ? run.program.includes('join')
      ? [{name: 'id', contract: text}, {name: 'StageName', contract: text}, {name: 'file_name', contract: text}]
      : [{name: 'id', contract: text}, {name: 'name', contract: text}, {name: 'StageName', contract: text},
        {name: 'NextStep', contract: {type: 'string', nullable: true}}]
      : [{name: 'id', contract: text}, {name: 'StageName', contract: text},
        {name: 'NextStep', contract: {type: 'string', nullable: true}},
        {name: 'notes', contract: {type: 'content_ref', nullable: false, media_type: 'text/plain'}},
        {name: 'review', contract: {type: 'object', nullable: false, additional_properties: false, fields: {
          input_key: {type: 'object', nullable: false, additional_properties: false, fields: {id: text}},
          outcome: text, value: {type: 'object', nullable: false, additional_properties: false, fields: {
            changed: {type: 'boolean', nullable: false}, stage: text, next_step: text}}}}}];
    return {ref: run.original.ref, resultName: run.readonly ? 'main' : 'updates', columns,
      ...Object.fromEntries(['programDefinitionCid', 'resultDefinitionCid', 'resultArtifactCid', 'resultSchemaCid']
        .map(name => [name, 'sha256:' + 'f'.repeat(64)]))};
  };
  const options = {root,
    async persist(value) {records.push(structuredClone(value));},
    async snapshot(project) {const value = projects.get(project); return {bytes: JSON.stringify(value.data), generation: value.generation};},
    async readProgram() {return 'original template\nNextStep = review.value.next_step\n';},
    async writeProgram(path, source) {assert(!programs.has(path)); programs.set(path, source);},
    async cli(args, project, label) {
      calls.push({surface: 'cli', args, project});
      const acceptance = {writes: []}; let reply;
      if (args[0] === 'init') {
        assert(!projects.has(project));
        mkdirSync(join(project, 'mock'), {recursive: true});
        projects.set(project, {data: initial(), generation: 0, runs: []});
      }
      else {
        const value = projects.get(project);
        if (args[0] === 'check') reply = {outcome: 'completed', report: {verdict: 'verified', runnable: {verdict: 'yes'}}};
        else if (args[0] === 'run') reply = state(start(project, 'cli', args[1], label.readonly));
        else if (args[0] === 'explain') reply = {version: 'actql-run-plan-view/0.1', run_ref: own(value, 'cli', args[2]).original.ref};
        else {
          const run = own(value, 'cli', args[1]);
          if (args[0] === 'approve') {
            approve(value, run); acceptance.writes = [{ordinal: 0}, {ordinal: 1}];
            if ((orphanFinalLock || retireLockDuringStatus) && value.generation === 3) {
              writeFileSync(join(project, 'mock/data.json.actql-write.lock'), 'original writer lock', {flag: 'wx'});
            }
          }
          else if (args[0] === 'result') return {pid: ++pid, signal: null, code: 0, acceptance,
            stdout: rows(run).map(row => JSON.stringify(row)).join('\n') + '\n'};
          else {
            assert.equal(args[0], 'status');
            if (value.generation === 3) {
              if (failFinalStatus) throw statusFailure;
              if (retireLockDuringStatus) rmSync(join(project, 'mock/data.json.actql-write.lock'));
            }
            reply = state(run);
          }
        }
      }
      return {pid: ++pid, signal: null, code: 0, stdout: JSON.stringify(reply), acceptance};
    },
    async node(request, project) {
      calls.push({surface: 'node', request, project});
      if (failNode && request.kind === 'start') throw primary;
      const value = projects.get(project), readonly = request.kind === 'read' || request.resultName === 'main';
      const run = ['read', 'start'].includes(request.kind) ? start(project, 'node', request.program, readonly)
        : own(value, 'node', request.original.runId);
      if (request.kind === 'start') approve(value, run);
      const counts = {sourceAcquisitionStarts: request.kind === 'start' ? 2 : request.kind === 'read'
        ? request.program.includes('join') ? 2 : 1 : 0,
      modelCallStarts: request.kind === 'start' ? 2 : 0, effectReplacementReturns: request.kind === 'start' ? 2 : 0};
      return {pid: ++pid, original: run.original, state: state(run), rows: rows(run), description: description(run),
        firstClose: {attempted: true, returned: !lostClose}, workObservation: {...counts, totals: {...counts}, complete: true}};
    },
  };
  return {options, calls, records, projects, programs, primary, statusFailure};
}

const writerLockObservations = record => record.phases
  .filter(({phase}) => phase === 'approve' || phase === 'start')
  .map(({writeLockPathAbsent}) => writeLockPathAbsent);

test('Original Mock regressions observe the writer lock before status can retire it', async t => {
  const f = fixture(t, {retireLockDuringStatus: true});
  await assert.rejects(runOriginalMockRegressions(f.options),
    error => error instanceof AggregateError && /shared Mock write lock/u.test(error.cause?.message));
  const [writes] = f.records;
  assert.deepEqual(writerLockObservations(writes), [true, true, false]);
  assert(writes.runs.every(run => run.rows.length === 2), 'Keep all complete original Saved checks');
});

test('Original Mock regressions retain the original failure after observing a writer lock', async t => {
  const f = fixture(t, {orphanFinalLock: true, failFinalStatus: true});
  await assert.rejects(runOriginalMockRegressions(f.options), error => error.cause === f.statusFailure);
  const [writes] = f.records;
  assert.equal(writes.failedPhase, 'status');
  assert.deepEqual(writerLockObservations(writes), [true, true, false]);
});

test('Original Mock regressions keep own roots while real differing writes cross the same file in both directions', async t => {
  const f = fixture(t), cases = await runOriginalMockRegressions(f.options);
  assert.equal(cases.length, 2); assert(cases.every(value => value.complete));
  const writes = cases[0];
  assert.deepEqual(writes.runs.map(run => run.surface), ['cli', 'node', 'cli']);
  assert.deepEqual(writes.runs.map(run => run.original.ref.namespaceId), ['cli-root', 'node-root', 'cli-root']);
  assert.deepEqual(writerLockObservations(writes), [true, true, true]);
  assert.equal(new Set(writes.runs.map(run => run.original.runId)).size, 3);
  assert.equal(cases[1].runs.length, 6);
  assert.equal(f.projects.get(writes.project).generation, 3);
  assert.equal(f.calls.filter(row => row.args?.[0] === 'init').length, 2, 'No project/data reset between writers');
  assert.equal(f.calls.filter(row => row.args?.[0] === 'approve').length, 2);
  assert.equal(f.calls.filter(row => row.request?.kind === 'start').length, 1);
  assert.equal(f.calls.filter(row => row.request?.kind === 'resolve').length, 0);
  assert.equal(f.calls.filter(row => row.request?.kind === 'read').length, 3);
  assert([...f.programs.keys()].every(path => basename(path).endsWith('.aql')));
});

test('Original Mock regressions refuse a write lock left by the final Native owner', async t => {
  const f = fixture(t, {orphanFinalLock: true});
  await assert.rejects(runOriginalMockRegressions(f.options),
    error => error instanceof AggregateError && /shared Mock write lock/u.test(error.cause?.message));
  const [writes, readonly] = f.records;
  assert.equal(writes.complete, false);
  assert.equal(writes.failedPhase, 'write-lock-cleanup');
  assert.deepEqual(writerLockObservations(writes), [true, true, false]);
  assert.equal(readFileSync(join(writes.project, 'mock/data.json.actql-write.lock'), 'utf8'), 'original writer lock');
  assert.equal(readonly.complete, true);
  assert.equal(f.calls.filter(row => row.args?.[0] === 'approve').length, 2);
});

for (const [name, option] of [['no-op cannot establish lock transfer', {noopNode: true}],
  ['unrelated target mutation', {mutateControl: true}], ['changed original Saved', {corruptSaved: true}],
  ['missing first close', {lostClose: true}], ['missing readonly row', {missingReadonlyRow: true}]])
test('Original Mock regressions refuse ' + name, async t => {
  const f = fixture(t, option);
  await assert.rejects(runOriginalMockRegressions(f.options), AggregateError);
  assert(f.records.some(record => !record.complete));
});

test('Original Mock uncertain writer stays primary and is never resubmitted or resolved by the other root', async t => {
  const f = fixture(t, {failNode: true});
  await assert.rejects(runOriginalMockRegressions(f.options), error => error.cause === f.primary);
  assert.equal(f.calls.filter(row => row.request?.kind === 'start').length, 1);
  assert.equal(f.calls.filter(row => row.request?.kind === 'resolve').length, 0);
  assert.equal(f.records[0].runs.length, 1, 'Do not continue the CLI writer after uncertain Node outcome');
  assert.equal(f.records[1].complete, true, 'Independent readonly project may finish without touching failed state');
});
