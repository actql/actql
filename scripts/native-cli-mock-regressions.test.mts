import assert from 'node:assert/strict';
import test from 'node:test';
import {createHash} from 'node:crypto';
import {basename} from 'node:path';
import {runOriginalMockRegressions} from './native-cli-mock-regressions.mjs';

type Ports = Parameters<typeof runOriginalMockRegressions>[0];
type Request = Parameters<Ports['node']>[0];
type Label = Parameters<Ports['cli']>[2];
type Original = NonNullable<Awaited<ReturnType<Ports['node']>>['original']>;
type CaseRecord = Parameters<Ports['persist']>[0];
type Call = {surface: 'cli' | 'node'; project: string; args?: readonly string[]; request?: Request};

// Explicit owner-local ports, not Native/SQLite/SDK or physical lock evidence.
function fixture({noopNode = false, corruptSaved = false, mutateControl = false,
  lostClose = false, missingReadonlyRow = false, failNode = false} = {}) {
  type Data = ReturnType<typeof initial>;
  type Run = {original: Original; surface: Call['surface']; program: string; readonly: boolean;
    before: Data; status: string};
  type Project = {data: Data; generation: number; runs: Run[]};
  const projects = new Map<string, Project>(), programs = new Map<string, string>(),
    calls: Call[] = [], records: CaseRecord[] = [];
  let serial = 0, pid = 1000;
  const primary = new Error('original uncertain Node operation');
  const initial = () => ({salesforce: {Opportunity: {key: ['id'], rows: [
    {id: '006Acme', name: 'Acme Corp - Renewal', StageName: 'Proposal', NextStep: null},
    {id: '006Globex', name: 'Globex - Expansion', StageName: 'Negotiation', NextStep: 'Legal review'},
  ]}}, drive: {files: {key: ['id'], rows: [
    {id: 'notes-acme', name: 'Acme Corp - Renewal', content_utf8: 'Acme original notes'},
    {id: 'notes-globex', name: 'Globex - Expansion', content_utf8: 'Globex original notes'},
  ]}}, control: {keep: 'untouched'}});
  const state = (run: Run) => ({version: 'actql-run-state/0.1', run_id: run.original.runId, status: run.status,
    checkpoint: {checkpoint_id: run.original.checkpointId, checkpoint_cid: run.original.checkpointCid}});
  function start(project: string, surface: Call['surface'], program: string, readonly = false) {
    const n = ++serial, value = projects.get(project);
    const original = {runId: 'run-' + n, ref: {namespaceId: surface + '-root',
      authorityScopeCid: 'sha256:' + 'a'.repeat(64), runDefinitionCid: 'sha256:' + n.toString(16).padStart(64, '0')},
    ...(readonly ? {} : {checkpointId: 'checkpoint-' + n, checkpointCid: 'sha256:' + 'b'.repeat(64)})};
    const run = {original, surface, program, readonly, before: structuredClone(value!.data),
      status: readonly ? 'succeeded' : 'waiting_checkpoint'};
    value!.runs.push(run); return run;
  }
  function own(value: Project, surface: Call['surface'], id: string) {
    const run = value.runs.find(run => [run.original.runId, run.original.checkpointId].includes(id));
    assert(run); assert.equal(run.surface, surface, 'Never attach/read/approve a foreign owning root'); return run;
  }
  function approve(value: Project, run: Run) {
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
  function rows(run: Run) {
    let rows: {id: string; StageName: string; [field: string]: unknown}[];
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
  const description = (run: Run) => {
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
  const options = {root: '/own/fresh-consumer',
    async persist(value: CaseRecord) {records.push(structuredClone(value));},
    async snapshot(project: string) {const value = projects.get(project); return {bytes: JSON.stringify(value!.data), generation: value!.generation};},
    async readProgram() {return 'original template\nNextStep = review.value.next_step\n';},
    async writeProgram(path: string, source: string) {assert(!programs.has(path)); programs.set(path, source);},
    async cli(args: readonly string[], project: string, label: Label) {
      calls.push({surface: 'cli', args, project});
      const acceptance: {writes: {ordinal: number}[]} = {writes: []}; let reply: unknown;
      if (args[0] === 'init') {assert(!projects.has(project)); projects.set(project, {data: initial(), generation: 0, runs: []});}
      else {
        const value = projects.get(project);
        if (args[0] === 'check') reply = {outcome: 'completed', report: {verdict: 'verified', runnable: {verdict: 'yes'}}};
        else if (args[0] === 'run') reply = state(start(project, 'cli', args[1], label.readonly));
        else if (args[0] === 'explain') reply = {version: 'actql-run-plan-view/0.1', run_ref: own(value!, 'cli', args[2]).original.ref};
        else {
          const run = own(value!, 'cli', args[1]);
          if (args[0] === 'approve') {approve(value!, run); acceptance.writes = [{ordinal: 0}, {ordinal: 1}];}
          else if (args[0] === 'result') return {pid: ++pid, signal: null, code: 0, acceptance,
            stdout: rows(run).map(row => JSON.stringify(row)).join('\n') + '\n'};
          else {assert.equal(args[0], 'status'); reply = state(run);}
        }
      }
      return {pid: ++pid, signal: null, code: 0, stdout: JSON.stringify(reply), acceptance};
    },
    async node(request: Request, project: string) {
      calls.push({surface: 'node', request, project});
      if (failNode && request.kind === 'start') throw primary;
      const value = projects.get(project), readonly = request.kind === 'read' || request.resultName === 'main';
      const run = ['read', 'start'].includes(request.kind) ? start(project, 'node', request.program!, readonly)
        : own(value!, 'node', request.original!.runId);
      if (request.kind === 'start') approve(value!, run);
      const counts = {sourceAcquisitionStarts: request.kind === 'start' ? 2 : request.kind === 'read'
        ? request.program!.includes('join') ? 2 : 1 : 0,
      modelCallStarts: request.kind === 'start' ? 2 : 0, effectReplacementReturns: request.kind === 'start' ? 2 : 0};
      return {pid: ++pid, original: run.original, state: state(run), rows: rows(run), description: description(run),
        firstClose: {attempted: true, returned: !lostClose}, workObservation: {...counts, totals: {...counts}, complete: true}};
    },
  } as unknown as Ports;
  return {options, calls, records, projects, programs, primary};
}

test('Original Mock regressions keep own roots while real differing writes cross the same file in both directions', async () => {
  const f = fixture(), cases = await runOriginalMockRegressions(f.options);
  assert.equal(cases.length, 2); assert(cases.every(value => value.complete));
  const writes = cases[0];
  assert.deepEqual(writes.runs.map(run => run.surface), ['cli', 'node', 'cli']);
  assert.deepEqual(writes.runs.map(run => run.original.ref.namespaceId), ['cli-root', 'node-root', 'cli-root']);
  assert.equal(new Set(writes.runs.map(run => run.original.runId)).size, 3);
  assert.equal(cases[1].runs.length, 6);
  assert.equal(f.projects.get(writes.project)!.generation, 3);
  assert.equal(f.calls.filter(row => row.args?.[0] === 'init').length, 2, 'No project/data reset between writers');
  assert.equal(f.calls.filter(row => row.args?.[0] === 'approve').length, 2);
  assert.equal(f.calls.filter(row => row.request?.kind === 'start').length, 1);
  assert.equal(f.calls.filter(row => row.request?.kind === 'resolve').length, 0);
  assert.equal(f.calls.filter(row => row.request?.kind === 'read').length, 3);
  assert([...f.programs.keys()].every(path => basename(path).endsWith('.aql')));
});

for (const [name, option] of [['no-op cannot establish lock transfer', {noopNode: true}],
  ['unrelated target mutation', {mutateControl: true}], ['changed original Saved', {corruptSaved: true}],
  ['missing first close', {lostClose: true}], ['missing readonly row', {missingReadonlyRow: true}]] as const)
test('Original Mock regressions refuse ' + name, async () => {
  const f = fixture(option);
  await assert.rejects(runOriginalMockRegressions(f.options), AggregateError);
  assert(f.records.some(record => !record.complete));
});

test('Original Mock uncertain writer stays primary and is never resubmitted or resolved by the other root', async () => {
  const f = fixture({failNode: true});
  await assert.rejects(runOriginalMockRegressions(f.options), error => (error as Error).cause === f.primary);
  assert.equal(f.calls.filter(row => row.request?.kind === 'start').length, 1);
  assert.equal(f.calls.filter(row => row.request?.kind === 'resolve').length, 0);
  assert.equal(f.records[0].runs.length, 1, 'Do not continue the CLI writer after uncertain Node outcome');
  assert.equal(f.records[1].complete, true, 'Independent readonly project may finish without touching failed state');
});
