// Reuse the required README job's exact verified package installation.
import assert from 'node:assert/strict';
import {mkdir, writeFile, readFile, copyFile, symlink, readlink, unlink, lstat} from 'node:fs/promises';
import {join, dirname} from 'node:path';
import {modelRegistrationProjectFiles} from './fixtures/model-registration-project.mjs';
import {verifyNodeBenchmarkPackages, nodeBenchmarkFailure} from './node-benchmark-evidence.mjs';
import type {BenchmarkPackageManifest} from './node-benchmark-evidence.mjs';
import type {assertRecordWorkflowWork} from '../adapters/host-node/fixtures/work-observation.fixture.mjs';

export const packedModelControlPhases = Object.freeze(['capture', 'approve', 'recover', 'budget'] as const);

type Phase = typeof packedModelControlPhases[number];
type Observation = {
  phase: Phase; pid: number; registeredMetadata?: unknown; kind?: unknown; status?: unknown;
  primaryCode?: unknown; cleanupCode?: unknown; diagnosticCode?: unknown; firstClose?: unknown;
  submits?: unknown; selectedModelTasks?: unknown;
  budgetRefusal?: {verified: unknown; scope: unknown; classification: unknown};
  sameHostSmallResult?: unknown; smallTerminal?: unknown; requestMemory?: unknown; budgetInputBytes?: unknown;
  originalImportFailed?: unknown; selectedCallsOnCapture?: unknown; claims129SelectedSlots?: unknown;
  inputsAbsentBeforeRecovery?: unknown; aliveScopedFD?: unknown; firstFailedStep?: unknown; code?: unknown;
  workObservation?: Parameters<typeof assertRecordWorkflowWork>[0];
};
type Failure = ReturnType<typeof nodeBenchmarkFailure>;
type CommandResult = {pid: number; code: number | null; signal?: NodeJS.Signals | null; stdout: string};
type ControlRecord = {
  phase: Phase; completed: boolean; status: string; unexecutedReason?: string; startedAt?: string; endedAt?: string;
  pid?: number; exitCode?: number | null; signal?: NodeJS.Signals | null; error?: Failure;
  actual?: Observation; summary?: Observation; partialObservation?: unknown;
  inputsAbsentBeforeRecovery?: boolean; inputsAbsentAfterSaved?: boolean;
  inputRemoval?: {completed: boolean; paths: string[]};
};
type ExecutionOptions = {
  prepared: {manifest: BenchmarkPackageManifest; manifestPath: string; consumer: string};
  root: string; repository: string;
  command: (executable: string, args: string[], options: {cwd: string; name: string; timeout: number}) =>
    CommandResult | PromiseLike<CommandResult>;
};

export function assertPackedModelOutcome(rows: readonly Observation[], phase: Phase, pid: number) {
  assert(packedModelControlPhases.includes(phase));
  const actual = rows.at(-1)!;
  assert.equal(actual.phase, phase); assert.equal(actual.pid, pid);
  assert.equal(actual.registeredMetadata, 129);
  if (phase === 'budget') {
    assert.equal(actual.kind, 'model-registry-budget'); assert.equal(actual.status, 'passed');
    assert.equal(actual.primaryCode, undefined); assert.equal(actual.cleanupCode, undefined);
    assert.equal(actual.diagnosticCode, undefined);
    assert.deepEqual(actual.firstClose, {attempted: true, returned: true});
    assert.equal(actual.submits, 2); assert.equal(actual.selectedModelTasks, 0);
    assert.equal(actual.budgetRefusal?.verified, true);
    assert.equal(actual.budgetRefusal!.scope, 'request_snapshot');
    assert.equal(actual.budgetRefusal!.classification, 'resource_limit');
    assert.equal(actual.sameHostSmallResult, true);
    assert.deepEqual(actual.smallTerminal, {status: 'succeeded'});
    assert.deepEqual(actual.requestMemory, {retainedBytes: 268435456, executionBytes: 268435456});
    assert.equal(actual.budgetInputBytes, 8 * 1024 * 1024 + Buffer.byteLength('/**/ SELECT 7 AS n'));
  } else {
    assert.equal(actual.kind, 'model-registry-workflow');
    assert.equal(actual.originalImportFailed, false); assert.equal(actual.diagnosticCode, undefined);
    assert.equal(actual.selectedModelTasks, 2); assert.equal(actual.selectedCallsOnCapture, 4);
    assert.equal(actual.claims129SelectedSlots, false);
    assert.equal(actual.inputsAbsentBeforeRecovery, phase !== 'capture');
  }
  assert.deepEqual(actual.aliveScopedFD, {after: 0});
  const summary = phase === 'budget' ? actual : rows.find(row => row.phase === phase && row.firstClose);
  assert(summary); assert.equal(summary.status, 'passed');
  assert.equal(summary.firstFailedStep ?? null, null);
  assert.equal(summary.code, undefined); assert.equal(summary.cleanupCode, undefined);
  assert.deepEqual(summary.firstClose, {attempted: true, returned: true});
  const work = summary.workObservation;
  assert.equal(work?.complete, true, 'Lossless actual work observation is required');
  assert.equal(work!.sourceAcquisitionStarts, phase === 'capture' ? 2 : 0);
  assert.equal(work!.modelCallStarts, phase === 'capture' ? 4 : 0);
  assert.equal(work!.effectReplacementReturns, phase === 'approve' ? 2 : 0);
  return {actual, summary};
}

async function stageModelProject({prepared, root, repository, name}: Pick<ExecutionOptions, 'prepared' | 'root' | 'repository'> & {name: string}) {
  const project = join(root, name); await mkdir(project);
  const files = modelRegistrationProjectFiles();
  for (const [name, bytes] of Object.entries(files)) {
    const target = join(project, name); await mkdir(dirname(target), {recursive: true});
    await writeFile(target, bytes, {flag: 'wx'});
  }
  for (const [source, target] of [
    ['adapters/host-node/fixtures/mock-project-effect-public.mjs', 'workflow-original.mjs'],
    ['adapters/host-node/fixtures/work-observation.fixture.mjs', 'work-observation.fixture.mjs'],
    ['adapters/host-node/fixtures/mock-project-effect-protocol.fixture.mjs', 'mock-project-effect-protocol.fixture.mjs'],
    ['scripts/fixtures/packed-model-workflow.mjs', 'workflow.mjs'],
    ['scripts/fixtures/packed-model-budget.mjs', 'budget.mjs'],
    ['scripts/fixtures/model-control-observations.mjs', 'model-control-observations.mjs'],
    ['scripts/fixtures/record-approval/scoped-fds.fixture.mjs', 'record-approval/scoped-fds.fixture.mjs'],
  ]) {
    await mkdir(dirname(join(project, target)), {recursive: true});
    await copyFile(join(repository, source), join(project, target));
  }
  const software = join(prepared.consumer, 'node_modules'), alias = join(project, 'node_modules');
  await symlink(software, alias, 'dir');
  return {project, files, software, alias};
}

// The second argument supplies explicit test ports, never product authority.
export async function runPackedModelControls({prepared, root, repository, command, records, failures}:
  ExecutionOptions & {records: ControlRecord[]; failures: unknown[]},
  {verifyPackages = verifyNodeBenchmarkPackages}: {verifyPackages?: (...args: Parameters<typeof verifyNodeBenchmarkPackages>) => unknown} = {}) {
  assert.deepEqual(records.map(record => record.phase), packedModelControlPhases);
  const diagnostics = join(root, 'collection'); await mkdir(diagnostics, {recursive: true});
  const staged: Awaited<ReturnType<typeof stageModelProject>>[] = [];
  let recovery: Awaited<ReturnType<typeof stageModelProject>>, captureComplete = false, approvalComplete = false;
  try {
    await verifyPackages(prepared.manifest, prepared.manifestPath, prepared.consumer);
    recovery = await stageModelProject({prepared, root, repository, name: 'model-registry-129'});
    staged.push(recovery);
    const config = JSON.parse(recovery.files['actql.config.json']) as {mock: {answers: Record<string, string>}};
    const removed = ['deal-review.program.json', ...Object.values(config.mock.answers).map(path => path.replace(/^\.\//u, ''))];
    const originals = new Map(await Promise.all(removed.map(async path => [path,
      await lstat(join(recovery.project, path))] as const)));
    for (const record of records) {
      const {phase} = record;
      if (phase === 'approve' && !captureComplete || phase === 'recover' && !approvalComplete) {
        record.unexecutedReason = 'Requires same original capture/approval and observed FIRST close'; continue;
      }
      record.status = 'running'; delete record.unexecutedReason;
      record.startedAt = new Date().toISOString();
      const path = join(diagnostics, `model-controls.${phase}.json`);
      await writeFile(path, JSON.stringify(record, null, 2) + '\n');
      let project = recovery.project;
      try {
        if (phase === 'budget') {
          const budget = await stageModelProject({prepared, root, repository, name: 'model-registry-129-budget'});
          staged.push(budget); project = budget.project;
        } else if (phase !== 'capture') {
          for (const input of removed) await assert.rejects(lstat(join(project, input)), {code: 'ENOENT'});
          record.inputsAbsentBeforeRecovery = true;
        }
        const handoff = join(project, 'handoff.json');
        const result = await command(process.execPath, phase === 'budget' ? [join(project, 'budget.mjs')]
          : [join(project, 'workflow.mjs'), phase, handoff, 'deal-review-mock', 'two-models'],
        {cwd: project, name: `model-registry-${phase}`, timeout: 120_000});
        Object.assign(record, {pid: result.pid, exitCode: result.code, signal: result.signal ?? null});
        const rows = result.stdout.trim().split('\n').filter(Boolean).map(line => JSON.parse(line) as Observation);
        // Keep the actual child receipt before checking success or removing inputs.
        record.actual = rows.at(-1); record.summary = rows.find(row => row.phase === phase && row.firstClose);
        assert.equal(result.code, 0); assert.equal(result.signal ?? null, null);
        Object.assign(record, assertPackedModelOutcome(rows, phase, result.pid));
        if (phase === 'capture') {
          record.inputRemoval = {completed: false, paths: []};
          for (const input of removed) {
            const info = await lstat(join(project, input)), original = originals.get(input);
            assert(info.isFile() && info.nlink === 1);
            assert.equal(info.ino, original!.ino); assert.equal(info.dev, original!.dev);
            assert.equal(await readFile(join(project, input), 'utf8'), recovery.files[input]);
          }
          for (const input of removed) {await unlink(join(project, input)); record.inputRemoval.paths.push(input);}
          record.inputRemoval.completed = true; captureComplete = true;
        } else if (phase === 'approve') approvalComplete = true;
        else if (phase === 'recover') {
          for (const input of removed) await assert.rejects(lstat(join(project, input)), {code: 'ENOENT'});
          record.inputsAbsentAfterSaved = true;
        }
        record.completed = true; record.status = 'passed';
      } catch (error) {
        record.status = 'failed'; record.error = nodeBenchmarkFailure(error);
        const result = (error as {commandResult?: CommandResult}).commandResult;
        if (result) Object.assign(record, {pid: result.pid, exitCode: result.code ?? null, signal: result.signal ?? null});
        try {
          const pending = JSON.parse(await readFile(join(project, `${phase}.pending.json`), 'utf8'));
          assert.equal(pending.pid, record.pid); record.partialObservation = pending;
        } catch { /* No same-child receipt means close remains unobserved. */ }
        failures.push(error);
      } finally {
        record.endedAt = new Date().toISOString();
        await writeFile(path, JSON.stringify(record, null, 2) + '\n');
      }
    }
    await verifyPackages(prepared.manifest, prepared.manifestPath, prepared.consumer);
  } catch (error) {failures.push(error);}
  finally {
    for (const {alias, software} of staged) try {assert.equal(await readlink(alias), software); await unlink(alias);}
    catch (error) {failures.push(error);}
  }
}
