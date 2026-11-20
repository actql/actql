// Finite RC-only business cases. The installed caller owns artifacts, process
// bounds and scratch; these same imported assertions run with explicit test ports.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {lstat, readFile, stat, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {mockTemplates, expectedChanges} from './native-cli-mock-scenario.mjs';
import {assertProjectStaticCheckControls, projectStaticCheckControls} from './release-project-node-action.mjs';
import type {runReleaseProjectNodeAction} from './release-project-node-action.mjs';
import type {RunReference, RunState} from '../packages/sdk/index.d.ts';

type Template = typeof mockTemplates[number];
type StaticControl = keyof typeof cliStaticFiles;
type Surface = 'cli' | 'node';
type Decision = 'approved' | 'rejected';
type Snapshot = Awaited<ReturnType<typeof projectTargetSnapshot>>;
type ActionRequest = Parameters<typeof runReleaseProjectNodeAction>[0]['request'];
type Request = ActionRequest & {beforeBytes?: string};
type ActionResult = Awaited<ReturnType<typeof runReleaseProjectNodeAction>>;
type ResultDescription = NonNullable<ActionResult['description']>;
type Check = NonNullable<ActionResult['check']>;
type Plan = Extract<NonNullable<ActionResult['plan']>, {version: 'actql-effectful-static-plan-view/0.1'}>;
type WorkCounts = {sourceAcquisitionStarts: number; modelCallStarts: number; effectReplacementReturns: number};
type Work = WorkCounts & {totals?: WorkCounts; complete: boolean};
type NodeObservation = ActionResult & {workObservation: Work};
type CliObservation = {pid?: number; code: number | string | null; signal: string | null;
  stdout: string; stderr: string; acceptance?: {modelAttempts: unknown; writes: unknown}};
type Label = {template: Template; family: string; ordinal: number; phase: string;
  surface: Surface; staticCheckControl?: StaticControl};
type Original = {ref: RunReference; runId: string; checkpointId: string; checkpointCid: string};
type Row = Record<string, unknown>;
type ModelValue = {outcome: string; value: unknown};
type ContentRef = {$actql_ref: string; media_type: string;
  metadata: {content_cid: string; size_bytes: number; truncated: boolean}};
type MockData = {salesforce: Record<string, {rows: (Row & {id: string})[]}>;
  snowflake: {usage_30d: {rows: {account_id: string; active_users: number; trend: string}[]}};
  drive: {files: {rows: {name: string; content_utf8: string}[]}}};
type RunRecord = {original: Original; before: Snapshot; decision: Decision | null;
  rows?: readonly Row[]; description?: ResultDescription; cliResult?: string};
type CaseRecord = {template: Template; family: string; project: string; complete: boolean; failedPhase?: string;
  runs: RunRecord[]; phases: {ordinal: number; phase: string; surface: Surface; pid?: number}[]};
type Ports = {root: string;
  cli: (args: readonly string[], project: string, label: Label) => Promise<CliObservation>;
  node: (request: Request, project: string, label: Label) => Promise<NodeObservation>;
  snapshot?: typeof projectTargetSnapshot; persist: (record: CaseRecord) => unknown};

const cid = /^sha256:[0-9a-f]{64}$/u;
export const releaseProjectFamilies: readonly string[] = Object.freeze([
  'native-while-waiting', 'native-after-approve', 'native-after-reject',
  'node-sequential',
]);

const cliStaticFiles = Object.freeze({
  'known-outcome-type-error': 'stage2-known-outcome-type-error.aql',
  'unknown-update-target': 'stage2-unknown-update-target.aql',
});

// Only the existing invalid CheckOutcome exits 1, after its JSON and original
// cleanup have returned. A label cannot make another command's failure pass.
export function projectCliExpectedExit(args: readonly string[], label: Label) {
  if (label.staticCheckControl === undefined) return 0;
  assert(mockTemplates.includes(label.template));
  assert.equal(label.surface, 'cli');
  assert.equal(label.family, 'native-while-waiting');
  assert.equal(label.ordinal, 0); assert.equal(label.phase, 'check');
  assert(Object.hasOwn(cliStaticFiles, label.staticCheckControl), 'Unknown CLI static control');
  assert.deepEqual(args, ['check', cliStaticFiles[label.staticCheckControl], '--json']);
  return label.staticCheckControl === 'known-outcome-type-error' ? 1 : 0;
}

// Independent expectations from the authored Catalog, ModelTask and SELECT.
// These are not learned from a first Result or emitted by the product compiler.
const text = {type: 'string', nullable: false};
const modelResult = (fields: Record<string, object>) => ({type: 'object', nullable: false, additional_properties: false, fields: {
  input_key: {type: 'object', nullable: false, additional_properties: false, fields: {id: text}},
  outcome: text,
  value: {type: 'object', nullable: false, additional_properties: false, fields},
}});
const expectedColumns = {
  'churn-risk-mock': [
    {name: 'id', contract: text}, {name: 'notes', contract: text},
    {name: 'active_users', contract: {type: 'int64', nullable: false}},
    {name: 'trend', contract: text},
    {name: 'risk', contract: modelResult({
      level: {...text, enum: ['low', 'medium', 'high']}, reason: text,
    })},
  ],
  'deal-review-mock': [
    {name: 'id', contract: text}, {name: 'StageName', contract: text},
    {name: 'NextStep', contract: {type: 'string', nullable: true}},
    {name: 'notes', contract: {type: 'content_ref', nullable: false, media_type: 'text/plain'}},
    {name: 'review', contract: modelResult({changed: {type: 'boolean', nullable: false},
      stage: text, next_step: text})},
  ],
};

export function assertProjectResultDescription(template: Template, description: ResultDescription, ref: RunReference) {
  assert(expectedColumns[template], 'Unknown authored template');
  assert.equal(description.resultName, 'updates');
  assert.deepEqual(description.ref, ref);
  assert.deepEqual(description.columns, expectedColumns[template], 'Complete ordered original Result contracts');
  for (const field of ['programDefinitionCid', 'resultDefinitionCid', 'resultArtifactCid', 'resultSchemaCid'] as const)
    assert(cid.test(description[field]), field);
}

export async function projectTargetSnapshot(project: string) {
  const path = join(project, 'mock/data.json'), info = await stat(path, {bigint: true});
  return {bytes: await readFile(path, 'utf8'), dev: String(info.dev), ino: String(info.ino),
    mtimeNs: String(info.mtimeNs), size: String(info.size)};
}

export function assertTemplateStatic(check: Check, plan: Plan) {
  assert.equal(check.outcome, 'completed');
  assert.equal(check.report?.verdict, 'verified');
  assert.equal(check.report.runnable?.verdict, 'yes');
  assert.deepEqual(check.report.runnable.reasons, []);
  assert.equal(plan.version, 'actql-effectful-static-plan-view/0.1');
  assert.equal(plan.observation, 'static'); assert.equal(plan.provider_io, 0);
  const steps = plan.computation?.plan_view?.logical_map?.steps;
  assert(Array.isArray(steps));
  for (const operator of ['join', 'infer']) assert(steps.some(step => step.operator === operator), operator);
  assert.equal(plan.effect_set?.members.length, 1);
  assert.equal(plan.effect_set.members[0].effect_kind, 'update');
  assert.deepEqual(plan.effect_set.members[0].input, {kind: 'result', result_name: 'updates'});
}

export function requiredProjectReplacements(template: Template, beforeBytes: string) {
  const change = expectedChanges[template];
  assert(change && typeof beforeBytes === 'string', 'Original template and before DATA required');
  const data = JSON.parse(beforeBytes) as MockData;
  return change.rows.filter(update => {
    const before = data.salesforce[change.resource].rows.find(row => row.id === update.id);
    assert(before, 'Original selected target row missing');
    return Object.entries(update).some(([field, value]) => before[field] !== value);
  }).length;
}

export function assertProjectNodeWork(work: Work, request: Request, rows: number, template: Template) {
  assert.equal(work?.complete, true, 'Missing or lost observation cannot prove zero/reused work');
  const starts = request.kind === 'start';
  const expected = {sourceAcquisitionStarts: starts ? 2 : 0, modelCallStarts: starts ? rows : 0};
  for (const [field, value] of Object.entries(expected) as ['sourceAcquisitionStarts' | 'modelCallStarts', number][]) {
    assert.equal(work[field], value, field);
    if (work.totals) assert.equal(work.totals[field], value, 'No hidden other-Run work: ' + field);
  }
  // Only the same captured before DATA can prove a later same-value no-op.
  // Initial/partly changed targets still require their actual replacements;
  // terminal outcome and complete target/Result checks remain independent.
  const approved = request.decision === 'approved';
  if (approved) assert.equal(rows, expectedChanges[template]?.rows.length);
  const minimum = approved ? requiredProjectReplacements(template, request.beforeBytes!) : 0;
  assert(Number.isSafeInteger(work.effectReplacementReturns) && work.effectReplacementReturns >= minimum &&
    work.effectReplacementReturns <= (approved ? rows : 0));
  if (work.totals) assert.equal(work.totals.effectReplacementReturns, work.effectReplacementReturns);
}

function originalRun(state: RunState, ref: RunReference): Original {
  assert.equal(state.version, 'actql-run-state/0.1');
  assert.equal(state.status, 'waiting_checkpoint'); assert(typeof state.run_id === 'string' && state.run_id.length);
  assert(typeof state.checkpoint?.checkpoint_id === 'string' && state.checkpoint.checkpoint_id.length);
  assert(cid.test(state.checkpoint.checkpoint_cid));
  assert(ref && typeof ref.namespaceId === 'string' && ref.namespaceId.length && cid.test(ref.authorityScopeCid) && cid.test(ref.runDefinitionCid));
  return {ref, runId: state.run_id, checkpointId: state.checkpoint.checkpoint_id,
    checkpointCid: state.checkpoint.checkpoint_cid};
}

export function assertProjectSequenceRows(template: Template, rows: readonly Row[], before: Snapshot) {
  const change = expectedChanges[template], source = JSON.parse(before.bytes) as MockData;
  assert.equal(rows.length, change.rows.length);
  assert.deepEqual(rows.map(row => row.id).sort(), change.rows.map(row => row.id).sort());
  const columns = template === 'churn-risk-mock' ? ['id', 'notes', 'active_users', 'trend', 'risk']
    : ['id', 'StageName', 'NextStep', 'notes', 'review'];
  for (const [index, update] of change.rows.entries()) {
    const row = rows.find(value => value.id === update.id);
    assert.deepEqual(Object.keys(row!).sort(), [...columns].sort(), 'Complete authored Result field set');
    assert.equal((row![change.model] as ModelValue | undefined)?.outcome, 'ok');
    assert.deepEqual((row![change.model] as ModelValue).value, change.answers[index]);
    const original = source.salesforce[change.resource].rows.find(value => value.id === update.id);
    assert(original);
    if (template === 'churn-risk-mock') {
      const usage = source.snowflake.usage_30d.rows.find(value => value.account_id === update.id);
      assert.equal(row!.notes, original.description);
      assert(Number.isSafeInteger(usage!.active_users), 'The authored Mock count must be exact before encoding');
      // The retained int64 contract requires decimal Strings even for small counts.
      assert.equal(row!.active_users, String(usage!.active_users));
      assert.equal(row!.trend, usage!.trend);
    } else {
      assert.equal(row!.StageName, original.StageName); assert.equal(row!.NextStep, original.NextStep);
      const notes = source.drive.files.rows.find(value => value.name === original.name);
      assert(notes && (row!.notes as ContentRef | undefined)?.$actql_ref === 'content');
      assert.equal((row!.notes as ContentRef).media_type, 'text/plain');
      assert.equal((row!.notes as ContentRef).metadata?.content_cid, 'sha256:' + createHash('sha256').update(notes.content_utf8).digest('hex'));
      assert.equal((row!.notes as ContentRef).metadata.size_bytes, Buffer.byteLength(notes.content_utf8));
      assert.equal((row!.notes as ContentRef).metadata.truncated, false);
    }
  }
  return columns;
}

function expectedTarget(template: Template, before: Snapshot) {
  const data = JSON.parse(before.bytes) as MockData, change = expectedChanges[template];
  for (const update of change.rows) {
    const original = data.salesforce[change.resource].rows.find(row => row.id === update.id);
    assert(original); Object.assign(original, update);
  }
  return data;
}

export async function runReleaseProjectSequences({root, cli, node, snapshot = projectTargetSnapshot, persist}: Ports) {
  const cases: CaseRecord[] = [], failures: unknown[] = [];
  for (const template of mockTemplates) for (const family of releaseProjectFamilies) {
    const project = join(root, template + '-' + family), record: CaseRecord = {template, family, project, complete: false, runs: [], phases: []};
    cases.push(record);
    let phase = 'init';
    const cliCommand = async (args: readonly string[], ordinal = 0, staticCheckControl?: StaticControl) => {
      phase = args[0];
      const label: Label = {template, family, ordinal, phase, surface: 'cli',
        ...(staticCheckControl === undefined ? {} : {staticCheckControl})};
      const expectedExit = projectCliExpectedExit(args, label);
      const value = await cli(args, project, label);
      record.phases.push({ordinal, phase, surface: 'cli', pid: value.pid});
      assert.equal(value.signal, null); assert.equal(value.code, expectedExit, value.stderr);
      return value;
    };
    const nodeCommand = async (request: Request, ordinal = 0) => {
      phase = request.kind;
      const value = await node(request, project, {template, family, ordinal, phase, surface: 'node'});
      assert.deepEqual(value.firstClose, {attempted: true, returned: true});
      assertProjectNodeWork(value.workObservation, request, expectedChanges[template].rows.length, template);
      assert(Number.isSafeInteger(value.pid) && value.pid > 0);
      assert(!record.phases.some(row => row.surface === 'node' && row.pid === value.pid), 'Use a new Node process for each phase');
      record.phases.push({ordinal, phase, surface: 'node', pid: value.pid}); return value;
    };
    const state = (value: RunState, original: Original, status: RunState['status']) => {
      assert.equal(value.version, 'actql-run-state/0.1'); assert.equal(value.run_id, original.runId);
      assert.equal(value.status, status);
      if (status === 'waiting_checkpoint') {
        assert.equal(value.checkpoint?.checkpoint_id, original.checkpointId);
        assert.equal(value.checkpoint?.checkpoint_cid, original.checkpointCid);
      }
    };
    const inspect = async (original: Original, surface: Surface, status: RunState['status'], ordinal: number) => {
      const before = await snapshot(project);
      const value = surface === 'cli' ? JSON.parse((await cliCommand(['status', original.runId, '--json'], ordinal)).stdout) as RunState
        : (await nodeCommand({kind: 'status', original}, ordinal)).state!;
      state(value, original, status); assert.deepEqual(await snapshot(project), before, 'Status must not write');
    };
    const readResult = async (run: RunRecord, surface: Surface) => {
      const before = await snapshot(project), ordinal = record.runs.indexOf(run) + 1;
      let rows: readonly Row[], description: ResultDescription | undefined;
      if (surface === 'cli') {
        const value = await cliCommand(['result', run.original.runId, '--result', 'updates', '--format', 'jsonl'], ordinal);
        rows = value.stdout.trim().split('\n').map(line => JSON.parse(line) as Row);
        if (run.cliResult !== undefined) assert.equal(value.stdout, run.cliResult, 'Original CLI Saved Result bytes');
        else run.cliResult = value.stdout;
      } else {
        const value = await nodeCommand({kind: 'result', original: run.original}, ordinal);
        state(value.state!, run.original, 'succeeded'); rows = value.rows!; description = value.description;
        assertProjectResultDescription(template, description!, run.original.ref);
      }
      assertProjectSequenceRows(template, rows, run.before);
      if (description) {
        if (run.description) assert.deepEqual(description, run.description, 'Original Result schema/artifact on reread');
        else run.description = description;
      }
      if (run.rows) assert.deepEqual(rows, run.rows, 'Same original rows across reads and surfaces');
      else run.rows = rows;
      assert.deepEqual(await snapshot(project), before, 'Result read must not replace target');
    };
    try {
      await cliCommand(['init', '--template', template, project]);
      const program = `${template.slice(0, -5)}.aql`;
      if (family === 'native-while-waiting') {
        const before = await snapshot(project);
        const check = JSON.parse((await cliCommand(['check', program, '--json'])).stdout) as Check;
        const plan = JSON.parse((await cliCommand(['explain', program, '--json'])).stdout) as Plan;
        assertTemplateStatic(check, plan);
        assert.deepEqual(await snapshot(project), before, 'Static template analysis must not write');
        const originalRoot = await lstat(project, {bigint: true});
        assert(originalRoot.isDirectory() && !originalRoot.isSymbolicLink(), 'Use the current original project root');
        const original = await readFile(join(project, program));
        assert(original.length > 0 && original.length <= 65536, 'Use the existing bounded Program input');
        const text = original.toString('utf8');
        assert.deepEqual(Buffer.from(text), original, 'Preserve exact UTF-8 Program bytes');
        const controls = [];
        for (const control of projectStaticCheckControls(program, text)) {
          const name = cliStaticFiles[control.name as StaticControl], path = join(project, name);
          // Fixed basenames stay under the current project input root. Never
          // replace the original Program, an existing control or a symlink.
          await writeFile(path, control.text, {flag: 'wx', mode: 0o600});
          const value = await cliCommand(['check', name, '--json'], 0, control.name as StaticControl);
          const check = JSON.parse(value.stdout) as Extract<Check, {outcome: 'completed'}>;
          assert.equal(check.version, 'actql-check-outcome/0.1');
          assert.equal(check.report?.inputs?.length, 1);
          const input = check.report.inputs[0];
          assert.equal(input.document_id, 'source'); assert.equal(input.kind, 'text');
          assert.equal(input.byte_length, Buffer.byteLength(control.text));
          assert(/^rev:[0-9a-f]{64}$/u.test(input.revision), 'Use the original CLI input revision, not a reconstructed one');
          assert.deepEqual(value.acceptance?.modelAttempts, []);
          assert.deepEqual(value.acceptance?.writes, []);
          controls.push({name: control.name, check});
          const currentRoot = await lstat(project, {bigint: true});
          assert(currentRoot.isDirectory() && !currentRoot.isSymbolicLink());
          assert.equal(currentRoot.dev, originalRoot.dev); assert.equal(currentRoot.ino, originalRoot.ino,
            'Original project root changed during check');
          assert.deepEqual(await readFile(path), Buffer.from(control.text), 'Original control changed during check');
          assert.deepEqual(await readFile(join(project, program)), original, 'Original Program changed during check');
          assert.deepEqual(await snapshot(project), before, 'Static control must not change the target');
        }
        assertProjectStaticCheckControls(controls);
      } else if (family === 'node-sequential') {
        const before = await snapshot(project);
        const observed = await nodeCommand({kind: 'static', program});
        assertTemplateStatic(observed.check!, observed.plan as Plan);
        assertProjectStaticCheckControls(observed.staticChecks!);
        assert.deepEqual(await snapshot(project), before, 'Static template analysis must not write');
      }
      const population = family === 'exclusive-cli-node-roundtrip' ? 2 : 3;
      for (let ordinal = 1; ordinal <= population; ordinal++) {
        const before = await snapshot(project);
        const surface = family === 'node-sequential' || family === 'exclusive-cli-node-roundtrip' && ordinal === 2 ? 'node' : 'cli';
        const decision: Decision | null = family === 'native-while-waiting' ? null
          : family === 'native-after-reject' || family === 'node-sequential' && ordinal === 2 ? 'rejected' : 'approved';
        const immediate = family === 'node-sequential';
        let original: Original;
        if (surface === 'cli') {
          const waiting = JSON.parse((await cliCommand(['run', program, '--stop-before', 'commit', '--json'], ordinal)).stdout) as RunState;
          const view = JSON.parse((await cliCommand(['explain', '--run', waiting.run_id, '--json'], ordinal)).stdout) as
            {version: string; run_ref: RunReference};
          assert.equal(view.version, 'actql-run-plan-view/0.1'); original = originalRun(waiting, view.run_ref);
          assert.deepEqual(await snapshot(project), before, 'Run must wait without writing');
        } else {
          const value = await nodeCommand({kind: 'start', program, beforeBytes: before.bytes,
            ...(immediate ? {decision} : {})} as Request, ordinal);
          original = value.original as Original;
          state(value.state!, original, immediate ? decision === 'approved' ? 'succeeded' : 'cancelled' : 'waiting_checkpoint');
          if (!immediate) assert.deepEqual(await snapshot(project), before, 'Run must wait without writing');
        }
        assert(!record.runs.some(run => run.original.runId === original.runId || run.original.checkpointId === original.checkpointId),
          'Run2/3 must be new original submissions');
        const run = {original, before, decision}; record.runs.push(run);
        if (!decision) {
          for (const pending of record.runs) await inspect(pending.original, 'cli', 'waiting_checkpoint', ordinal);
          continue;
        }
        if (!immediate) {
          const resolver = family === 'exclusive-cli-node-roundtrip' ? surface === 'cli' ? 'node' : 'cli' : 'cli';
          if (resolver === 'cli') await cliCommand([decision === 'approved' ? 'approve' : 'reject', original.checkpointId,
            ...(decision === 'approved' ? ['--wait'] : []), '--json'], ordinal);
          else await nodeCommand({kind: 'resolve', original, decision, beforeBytes: before.bytes}, ordinal);
          await inspect(original, resolver, decision === 'approved' ? 'succeeded' : 'cancelled', ordinal);
        }
        assert.deepEqual(JSON.parse((await snapshot(project)).bytes), decision === 'approved' ? expectedTarget(template, before) : JSON.parse(before.bytes),
          'Complete target must preserve every nonupdated field');
        if (decision === 'approved') {
          await readResult(run, surface); await readResult(run, surface);
          if (family === 'exclusive-cli-node-roundtrip') await readResult(run, surface === 'cli' ? 'node' : 'cli');
        }
      }
      if (family === 'native-while-waiting') for (const [index, run] of record.runs.entries()) {
        await cliCommand(['reject', run.original.checkpointId, '--json'], index + 1);
        await inspect(run.original, 'cli', 'cancelled', index + 1);
        assert.deepEqual(await snapshot(project), run.before, 'Rejected pending Runs must not write');
      }
      for (const run of record.runs) if (run.decision === 'approved') await readResult(run,
        family === 'node-sequential' || family === 'exclusive-cli-node-roundtrip' ? 'node' : 'cli');
      record.complete = true;
    } catch (cause) {record.failedPhase = phase; failures.push(cause);}
    try {await persist(record);} catch (cause) {record.complete = false; failures.push(cause);}
  }
  if (failures.length) throw new AggregateError(failures, 'ReleaseProjectSequencesFailed', {cause: failures[0]});
  return cases;
}
