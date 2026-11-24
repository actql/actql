// Original3639/3642 follow-up in the existing installed RC consumer. Explicit
// ports test the assertions; only matching installed artifacts qualify products.
import assert from 'node:assert/strict';
import {lstat, readFile, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {expectedChanges} from './native-cli-mock-scenario.mjs';
import {projectTargetSnapshot, assertProjectSequenceRows, assertProjectResultDescription,
  assertProjectNodeWork} from './release-project-sequences.mjs';
import type {runReleaseProjectSequences} from './release-project-sequences.mjs';

type SequencePorts = Parameters<typeof runReleaseProjectSequences>[0];
type Request = Parameters<SequencePorts['node']>[0];
type Label = Parameters<SequencePorts['cli']>[2] & {readonly?: boolean};
type CliObservation = Awaited<ReturnType<SequencePorts['cli']>> & {acceptance?: {writes: readonly unknown[]}};
type NodeObservation = Awaited<ReturnType<SequencePorts['node']>>;
type State = NonNullable<NodeObservation['state']>;
type Original = NonNullable<NodeObservation['original']>;
type Description = NonNullable<NodeObservation['description']>;
type Snapshot = Awaited<ReturnType<typeof projectTargetSnapshot>>;
type Fixture = typeof originalMockReadonlyCases[number];
type Surface = 'cli' | 'node';
type Row = Record<string, unknown>;
type RegressionRun = {surface: Surface; original: Original; before: Snapshot; rows?: readonly Row[];
  description?: Description} & ({readonly: true; fixture: Fixture} | {readonly?: false});
type CaseRecord = {template: Label['template']; family: string; name: string; project: string; complete: boolean;
  failedPhase?: string; runs: RegressionRun[];
  phases: {surface: Surface; phase: string; ordinal: number; pid?: number; writeLockPathAbsent?: boolean}[]};
type Ports = Pick<SequencePorts, 'root' | 'node' | 'snapshot'> & {
  cli: (args: readonly string[], project: string, label: Label) => Promise<CliObservation>;
  persist: (record: CaseRecord) => unknown; readProgram?: (path: string) => Promise<string>;
  writeProgram?: (path: string, source: string) => Promise<void>};

const template = 'deal-review-mock', family = 'original-mock-regressions';
const cid = /^sha256:[0-9a-f]{64}$/u;
const string = {type: 'string', nullable: false};
export const originalMockReadonlyCases = Object.freeze([
  {name: 'opportunities', source: 'FROM salesforce.opportunities |> RESULT main', sources: 1,
    columns: [{name: 'id', contract: string}, {name: 'name', contract: string},
      {name: 'StageName', contract: string}, {name: 'NextStep', contract: {type: 'string', nullable: true}}],
    rows: [{id: '006Acme', name: 'Acme Corp - Renewal', StageName: 'Proposal', NextStep: null},
      {id: '006Globex', name: 'Globex - Expansion', StageName: 'Negotiation', NextStep: 'Legal review'}]},
  {name: 'opportunities-where', source: "FROM salesforce.opportunities |> WHERE StageName = 'Proposal' |> RESULT main", sources: 1,
    columns: [{name: 'id', contract: string}, {name: 'name', contract: string},
      {name: 'StageName', contract: string}, {name: 'NextStep', contract: {type: 'string', nullable: true}}],
    rows: [{id: '006Acme', name: 'Acme Corp - Renewal', StageName: 'Proposal', NextStep: null}]},
  {name: 'opportunities-join', source: 'SELECT o.id AS id, o.StageName, f.name AS file_name FROM salesforce.opportunities AS o JOIN drive.files AS f ON f.name = o.name |> RESULT main', sources: 2,
    columns: [{name: 'id', contract: string}, {name: 'StageName', contract: string}, {name: 'file_name', contract: string}],
    rows: [{id: '006Acme', StageName: 'Proposal', file_name: 'Acme Corp - Renewal'},
      {id: '006Globex', StageName: 'Negotiation', file_name: 'Globex - Expansion'}]},
]);
export const originalMockAlternateNextStep = 'Confirm the cross-Host handoff';

function original(state: State, ref: Original['ref'], expected: State['status']): Original {
  assert.equal(state.version, 'actql-run-state/0.1'); assert.equal(state.status, expected);
  assert(typeof state.run_id === 'string' && state.run_id.length);
  assert(typeof ref?.namespaceId === 'string' && ref.namespaceId.length);
  assert(cid.test(ref.authorityScopeCid) && cid.test(ref.runDefinitionCid));
  if (expected === 'waiting_checkpoint') {
    assert(typeof state.checkpoint?.checkpoint_id === 'string' && state.checkpoint.checkpoint_id.length);
    assert(cid.test(state.checkpoint.checkpoint_cid));
  }
  return {ref, runId: state.run_id, ...(expected === 'waiting_checkpoint' ? {
    checkpointId: state.checkpoint!.checkpoint_id, checkpointCid: state.checkpoint!.checkpoint_cid} : {})};
}
const jsonRows = (text: string) => text.trim().split('\n').filter(Boolean).map(line => JSON.parse(line) as Row);
const multiset = (rows: readonly Row[]) => rows.map(row => JSON.stringify(Object.fromEntries(Object.entries(row).sort()))).sort();
function assertReadonlyDescription(fixture: Fixture, description: Description) {
  assert.equal(description.resultName, 'main');
  // SELECT fixes the join column order; FROM retains the complete named
  // schema without inventing an ordering promise for catalog fields.
  const columns = (values: readonly {name: string}[]) => fixture.name === 'opportunities-join' ? values
    : [...values].sort((left, right) => left.name.localeCompare(right.name));
  assert.deepEqual(columns(description.columns), columns(fixture.columns));
  for (const field of ['programDefinitionCid', 'resultDefinitionCid', 'resultArtifactCid', 'resultSchemaCid'] as const)
    assert(cid.test(description[field]), field);
}

async function observeSharedMockWriteLock(project: string, writer: CaseRecord['phases'][number]) {
  try {
    await lstat(join(project, 'mock/data.json.actql-write.lock'));
  } catch (cause) {
    if ((cause as NodeJS.ErrnoException).code !== 'ENOENT') return cause;
    writer.writeLockPathAbsent = true;
    return;
  }
  writer.writeLockPathAbsent = false;
  return new Error('Completed writer must release the shared Mock write lock');
}

export async function runOriginalMockRegressions({root, cli, node, persist, snapshot = projectTargetSnapshot,
  readProgram = path => readFile(path, 'utf8'),
  writeProgram = (path, source) => writeFile(path, source, {flag: 'wx', mode: 0o600})}: Ports) {
  const cases: CaseRecord[] = [], failures: unknown[] = [];
  for (const name of ['same-file-cli-node-cli', 'readonly-opportunities']) {
    const project = join(root, name), record: CaseRecord = {template, family, name, project, runs: [], phases: [], complete: false};
    cases.push(record);
    let phase = 'init', ordinal = 0;
    const command = async (args: readonly string[], readonly = false) => {
      phase = args[0];
      const value = await cli(args, project, {template, family, ordinal, phase, surface: 'cli', readonly});
      record.phases.push({surface: 'cli', phase, ordinal, pid: value.pid});
      assert.equal(value.signal, null); assert.equal(value.code, 0, value.stderr);
      if (readonly) assert.deepEqual(value.acceptance?.writes, [], 'Readonly CLI must not replace targets');
      return value;
    };
    const nodeCommand = async (request: Request, readonly: boolean | undefined, sourceCount = 0) => {
      phase = request.kind;
      const value = await node(request, project, {template, family, ordinal, phase, surface: 'node'});
      assert.deepEqual(value.firstClose, {attempted: true, returned: true});
      assert(Number.isSafeInteger(value.pid) && value.pid > 0);
      assert(!record.phases.some(row => row.surface === 'node' && row.pid === value.pid));
      record.phases.push({surface: 'node', phase, ordinal, pid: value.pid});
      if (!readonly) assertProjectNodeWork(value.workObservation, request, 2, template);
      else {
        assert.equal(value.workObservation?.complete, true);
        for (const [key, count] of Object.entries({sourceAcquisitionStarts: sourceCount,
          modelCallStarts: 0, effectReplacementReturns: 0}) as
          [keyof NonNullable<NodeObservation['workObservation']['totals']>, number][]) {
          assert.equal(value.workObservation[key], count, key);
          assert.equal(value.workObservation.totals?.[key], count, 'No hidden other-Run work');
        }
      }
      return value;
    };
    const readSaved = async (run: RegressionRun) => {
      const before = await snapshot(project);
      let rows: readonly Row[], description: Description | undefined;
      if (run.surface === 'cli') {
        const value = await command(['result', run.original.runId, '--result', run.readonly ? 'main' : 'updates', '--format', 'jsonl'], run.readonly);
        rows = jsonRows(value.stdout);
      } else {
        const value = await nodeCommand({kind: 'result', original: run.original,
          ...(run.readonly ? {resultName: 'main'} : {})}, run.readonly);
        assert.equal(value.state!.run_id, run.original.runId); assert.equal(value.state!.status, 'succeeded');
        rows = value.rows!; description = value.description;
        assert.deepEqual(description!.ref, run.original.ref);
      }
      if (run.readonly) {
        assert.deepEqual(multiset(rows), multiset(run.fixture.rows), 'Complete independent readonly Result');
        if (description) assertReadonlyDescription(run.fixture, description);
      } else {
        assertProjectSequenceRows(template, rows, run.before);
        if (description) assertProjectResultDescription(template, description, run.original.ref);
      }
      if (run.rows) assert.deepEqual(run.readonly ? multiset(rows) : rows, run.readonly ? multiset(run.rows) : run.rows,
        'Same original Saved values after another Host writes');
      else run.rows = rows;
      if (description) {
        if (run.description) assert.deepEqual(description, run.description);
        else run.description = description;
      }
      assert.deepEqual(await snapshot(project), before, 'Saved lookup must not write shared target');
    };
    try {
      await command(['init', '--template', template, project]);
      const initial = await snapshot(project);
      if (name === 'same-file-cli-node-cli') {
        const canonical = await readProgram(join(project, 'deal-review.aql'));
        const needle = 'NextStep = review.value.next_step';
        assert.equal(canonical.split(needle).length, 2, 'Use the one original public SET field');
        await writeProgram(join(project, 'handoff.aql'), canonical.replace(needle,
          `NextStep = '${originalMockAlternateNextStep}'`));
        for (const surface of ['cli', 'node', 'cli'] as const) {
          ordinal++;
          const before = await snapshot(project), program = surface === 'node' ? 'handoff.aql' : 'deal-review.aql';
          let identity: Original;
          let lockFailure: unknown;
          if (surface === 'cli') {
            const waiting = JSON.parse((await command(['run', program, '--stop-before', 'commit', '--json'])).stdout) as State;
            const view = JSON.parse((await command(['explain', '--run', waiting.run_id, '--json'])).stdout) as {run_ref: Original['ref']};
            identity = original(waiting, view.run_ref, 'waiting_checkpoint');
            assert.deepEqual(await snapshot(project), before, 'No preapproval write');
            const reply = await command(['approve', identity.checkpointId!, '--wait', '--json']);
            assert.equal(reply.acceptance?.writes.length, 2, 'Both original rows require real Native replacements');
            lockFailure = await observeSharedMockWriteLock(project, record.phases.at(-1)!);
            const state = JSON.parse((await command(['status', identity.runId, '--json'])).stdout) as State;
            assert.equal(state.run_id, identity.runId); assert.equal(state.status, 'succeeded');
          } else {
            const value = await nodeCommand({kind: 'start', program, decision: 'approved', beforeBytes: before.bytes}, false);
            lockFailure = await observeSharedMockWriteLock(project, record.phases.at(-1)!);
            identity = value.original!;
            assert.equal(value.state!.run_id, identity.runId); assert.equal(value.state!.status, 'succeeded');
            assert.equal(value.workObservation.effectReplacementReturns, 2, 'No same-value no-op can prove lock transfer');
          }
          assert(!record.runs.some(run => run.original.runId === identity.runId && run.surface === surface));
          const expected = JSON.parse(before.bytes) as {salesforce: {Opportunity: {rows: Row[]}}};
          for (const update of expectedChanges[template].rows) {
            const row = expected.salesforce.Opportunity.rows.find(row => row.id === update.id); assert(row);
            assert.notEqual(row.NextStep, surface === 'node' ? originalMockAlternateNextStep : update.NextStep);
            Object.assign(row, update, surface === 'node' ? {NextStep: originalMockAlternateNextStep} : {});
          }
          const after = await snapshot(project);
          assert.notEqual(after.bytes, before.bytes, 'Each Host must actually change target DATA');
          assert.deepEqual(JSON.parse(after.bytes), expected, 'Preserve all unrelated/control fields and collections');
          const run = {surface, original: identity, before}; record.runs.push(run);
          await readSaved(run);
          // Each owner reads only its own originals; namespace/Run handles are
          // never attached to the other Host, even when sharing the file.
          for (const previous of record.runs.slice(0, -1)) await readSaved(previous);
          // Keep the original Result and Saved failures primary while
          // preserving the lock-path observation taken at writer return.
          if (lockFailure) {
            phase = 'write-lock-cleanup';
            throw lockFailure;
          }
        }
      } else {
        for (const fixture of originalMockReadonlyCases) {
          await writeProgram(join(project, fixture.name + '.aql'), fixture.source + '\n');
          for (const surface of ['cli', 'node'] as const) {
            ordinal++;
            const before = await snapshot(project), program = fixture.name + '.aql';
            let identity: Original;
            if (surface === 'cli') {
              const checked = JSON.parse((await command(['check', program, '--json'], true)).stdout) as NonNullable<NodeObservation['check']>;
              assert.equal(checked.outcome, 'completed'); assert.equal(checked.report?.verdict, 'verified');
              assert.equal(checked.report.runnable?.verdict, 'yes');
              const state = JSON.parse((await command(['run', program, '--json'], true)).stdout) as State;
              const view = JSON.parse((await command(['explain', '--run', state.run_id, '--json'], true)).stdout) as {run_ref: Original['ref']};
              identity = original(state, view.run_ref, 'succeeded');
            } else {
              const value = await nodeCommand({kind: 'read', program}, true, fixture.sources);
              identity = original(value.state!, value.original!.ref, 'succeeded');
              assert.deepEqual(multiset(value.rows!), multiset(fixture.rows));
              assert.deepEqual(value.description!.ref, identity.ref);
              assertReadonlyDescription(fixture, value.description!);
            }
            assert(!record.runs.some(run => run.surface === surface && run.original.runId === identity.runId),
              'Each readonly case is one new original submission');
            const run: RegressionRun = {surface, original: identity, before, readonly: true, fixture}; record.runs.push(run);
            await readSaved(run); await readSaved(run);
            assert.deepEqual(await snapshot(project), before, 'Readonly query must preserve bytes and physical metadata');
          }
        }
        assert.deepEqual(await snapshot(project), initial);
      }
      record.complete = true;
    } catch (cause) {record.failedPhase = phase; failures.push(cause);}
    try {await persist(record);} catch (cause) {record.complete = false; failures.push(cause);}
  }
  if (failures.length) throw new AggregateError(failures, 'OriginalMockRegressionsFailed', {cause: failures[0]});
  return cases;
}
