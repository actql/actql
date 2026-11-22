// Consumes a supplied immutable normal installation. It never packs, installs,
// compiles or imports the repository Host. Required packed CI wiring owns when
// this runner is selected and supplies its existing bounded command recorder.
import assert from 'node:assert/strict';
import {copyFile, mkdir, readFile, readlink, symlink, unlink, writeFile} from 'node:fs/promises';
import {dirname, isAbsolute, join} from 'node:path';
import {verifyNodeBenchmarkPackages} from './node-benchmark-evidence.mjs';
import type {BenchmarkPackageManifest} from './node-benchmark-evidence.mjs';
import type {assertRecordWorkflowWork} from '../adapters/host-node/fixtures/work-observation.fixture.mjs';

export const packedProjectFileStoreInventoryCases = Object.freeze([
  Object.freeze({case: 'rows101', writes: 101, definitions: 1, rows: 101,
    sourceAcquisitions: 1, sourceAttempts: 101}),
  Object.freeze({case: 'members17', writes: 17, definitions: 17, rows: 1,
    sourceAcquisitions: 0, sourceAttempts: 0}),
]);
const fixtureMembers = [
  'scripts/fixtures/packed-project-file-store-inventory.mjs',
  'scripts/fixtures/project-file-store-inventory-cases.mjs',
  'scripts/fixtures/project-file-store-ledger-observation.mjs',
  'scripts/fixtures/project-file-store-progress-observation.mjs',
  'scripts/fixtures/project-effect-dependency-observation.mjs',
  'scripts/fixtures/record-approval/scoped-fds.fixture.mjs',
  'adapters/host-node/fixtures/work-observation.fixture.mjs',
];

type Phase = 'capture' | 'approve' | 'saved';
type SelectedCase = typeof packedProjectFileStoreInventoryCases[number];
type PhaseObservation = {
  case: unknown;
  phase: Phase;
  pid: number;
  complete: unknown;
  ref: unknown;
  runId: unknown;
  checkpointId: unknown;
  checkpointCid: unknown;
  submits: unknown;
  approvals: unknown;
  successfulStores: unknown;
  memberPreviews: unknown;
  newEffectCommits: unknown;
  modelAttempts: unknown;
  workObservation: Parameters<typeof assertRecordWorkflowWork>[0];
  sourceStarts: unknown;
  sourceAttempts: unknown;
  newSourceAttempts: unknown;
  sourceAcquisitionEvidence?: {receipts: unknown; attempts: unknown; capturedRunCid: string; snapshotCid: string};
  rows: unknown[];
  targets: unknown[];
  requestMemory: unknown;
  firstClose: unknown;
  firstCloseCalls: unknown;
  aliveScopedFD: unknown;
  cleanup: unknown;
  originalInputsAndProgramAbsent: unknown;
  zeroWritesBeforeApproval: unknown;
  captureState?: {status: unknown};
};
type OriginalHandoff = {
  captureComplete: unknown;
  ref: unknown;
  capturePid: unknown;
  checkpointId: unknown;
  runId: unknown;
  checkpoint: {checkpointCid: unknown};
  approveComplete: unknown;
  approvePid?: unknown;
  rows?: unknown;
  targets?: unknown;
  ledger?: {receipts: unknown[]};
};
type FailureView = {name?: unknown; code?: unknown; message?: unknown};
type PhaseRecord = {
  case: SelectedCase['case']; phase: Phase; status: 'running' | 'passed' | 'failed';
  completed: boolean; startedAt: string;
  observation?: PhaseObservation; error?: FailureView;
  pid?: number | null; exitCode?: number | null; signal?: NodeJS.Signals | null; endedAt?: string;
};
type Installation = {manifest: BenchmarkPackageManifest; manifestPath: string; consumer: string};
type CommandResult = {code: number | null; signal?: NodeJS.Signals | null; pid: number; stdout: string};
type RunnerOptions = {
  prepared: Installation; root: string; repository: string;
  command: (executable: string, args: string[], options: {cwd: string; env: NodeJS.ProcessEnv; name: string; timeout: number}) =>
    CommandResult | PromiseLike<CommandResult>;
  report?: {cases: PhaseRecord[]}; cleanup?: unknown[];
  verifyPreparedPackages?: (value: Installation) => unknown;
};

export function assertPackedProjectFileStorePhase({selected, phase, actual, pid, original, previous}: {
  selected: SelectedCase; phase: Phase; actual: PhaseObservation; pid: number;
  original: OriginalHandoff; previous: readonly PhaseObservation[];
}) {
  assert.equal(actual.case, selected.case); assert.equal(actual.phase, phase);
  assert(Number.isSafeInteger(pid) && pid > 0); assert.equal(actual.pid, pid);
  assert.equal(actual.complete, true);
  assert.deepEqual(previous.map(row => row.phase), phase === 'capture' ? [] :
    phase === 'approve' ? ['capture'] : ['capture', 'approve']);
  for (const earlier of previous) {
    assert.notEqual(actual.pid, earlier.pid, 'Each original phase requires a distinct process');
    assert.deepEqual(actual.ref, earlier.ref);
    assert.equal(actual.runId, earlier.runId); assert.equal(actual.checkpointId, earlier.checkpointId);
    assert.equal(actual.checkpointCid, earlier.checkpointCid);
  }
  assert.equal(actual.submits, phase === 'capture' ? 1 : 0);
  assert.equal(actual.approvals, phase === 'approve' ? 1 : 0);
  assert.equal(actual.successfulStores, phase === 'capture' ? 0 : selected.writes);
  assert.equal(actual.memberPreviews, phase === 'capture' ? 0 : selected.definitions);
  assert.equal(actual.newEffectCommits, phase === 'approve' ? selected.writes : 0);
  assert.equal(actual.modelAttempts, 0);
  assert.equal(actual.workObservation.complete, true);
  assert.equal(actual.workObservation.modelCallStarts, 0);
  assert.equal(actual.workObservation.totals.modelCallStarts, 0);
  assert.equal(actual.sourceStarts, actual.workObservation.sourceAcquisitionStarts);
  assert.equal(actual.sourceStarts, actual.workObservation.totals.sourceAcquisitionStarts);
  assert.equal(actual.sourceAttempts, selected.sourceAttempts);
  if (phase === 'capture' && selected.case === 'rows101') {
    assert.equal(actual.sourceStarts, selected.sourceAcquisitions);
    assert.equal(actual.newSourceAttempts, selected.sourceAttempts);
  } else {
    assert.equal(actual.sourceStarts, 0); assert.equal(actual.newSourceAttempts, 0);
  }
  if (selected.sourceAcquisitions > 0) {
    assert.equal(actual.sourceAcquisitionEvidence!.receipts, selected.sourceAcquisitions);
    assert.equal(actual.sourceAcquisitionEvidence!.attempts, selected.sourceAttempts);
    for (const key of ['capturedRunCid', 'snapshotCid'] as const)
      assert.match(actual.sourceAcquisitionEvidence![key], /^sha256:[0-9a-f]{64}$/u);
    for (const earlier of previous) assert.deepEqual(actual.sourceAcquisitionEvidence,
      earlier.sourceAcquisitionEvidence, 'Every cold phase preserves the exact authenticated Source inventory');
  }
  assert.equal(actual.rows.length, phase === 'capture' ? 0 : selected.rows);
  assert.equal(actual.targets.length, phase === 'capture' ? 0 : selected.writes);
  assert.deepEqual(actual.requestMemory, {retainedBytes: 536870912, executionBytes: 536870912});
  assert.equal(actual.firstClose, 'returned'); assert.equal(actual.firstCloseCalls, 1);
  assert.deepEqual(actual.aliveScopedFD, {before: 0, after: 0});
  assert.deepEqual(actual.cleanup, []); assert.equal(actual.originalInputsAndProgramAbsent, true);
  assert.equal(original.captureComplete, true); assert.deepEqual(original.ref, actual.ref);
  assert.equal(original.capturePid, previous[0]?.pid ?? actual.pid);
  assert.equal(original.checkpointId, actual.checkpointId); assert.equal(original.runId, actual.runId);
  assert.equal(original.checkpoint.checkpointCid, actual.checkpointCid);
  if (phase === 'capture') {
    assert.equal(actual.zeroWritesBeforeApproval, true); assert.equal(original.approveComplete, false);
    assert.equal(actual.captureState!.status, 'waiting_checkpoint');
  } else {
    assert.equal(original.approveComplete, true);
    assert.equal(original.approvePid, phase === 'approve' ? actual.pid : previous[1].pid);
    assert.deepEqual(original.rows, actual.rows); assert.deepEqual(original.targets, actual.targets);
    assert.equal(original.ledger!.receipts.length, selected.writes);
    if (phase === 'approve') assert.equal(actual.zeroWritesBeforeApproval, true);
    else {
      assert.deepEqual(actual.rows, previous[1].rows); assert.deepEqual(actual.targets, previous[1].targets);
      assert.equal(actual.sourceAttempts, previous[0].sourceAttempts);
    }
  }
}

export async function runPackedProjectFileStoreInventory({prepared, root, repository, command,
  report = {cases: []}, cleanup = [],
  verifyPreparedPackages = value => verifyNodeBenchmarkPackages(value.manifest, value.manifestPath, value.consumer)}: RunnerOptions) {
  assert(isAbsolute(root) && isAbsolute(repository));
  assert.equal(typeof command, 'function'); assert(Array.isArray(report.cases));
  assert.equal(typeof verifyPreparedPackages, 'function');
  assert(!process.env.NODE_OPTIONS && !process.env.NODE_PATH &&
    !process.env.ACTQL_LOCAL_SOURCE_PROFILE && !process.env.ACTQL_LOCAL_EFFECT_PROFILE,
  'Require the unchanged normal runtime without ambient overlays');
  await mkdir(root); // A new runner directory; never adopt another case's state.
  const software = join(prepared.consumer, 'node_modules');
  assert(isAbsolute(software));
  for (const selected of packedProjectFileStoreInventoryCases) {
    const application = join(root, selected.case); await mkdir(application);
    for (const member of fixtureMembers) {
      await mkdir(dirname(join(application, member)), {recursive: true});
      await copyFile(join(repository, member), join(application, member));
    }
    await writeFile(join(application, 'package.json'), '{"private":true,"type":"module"}\n');
    const home = join(application, 'home'); await mkdir(home);
    const env: NodeJS.ProcessEnv = {...process.env, HOME: home, PATH: [dirname(process.execPath), '/usr/bin', '/bin'].join(':')};
    delete env.ACTQL_PACKED_CLIENT_PACKAGES;
    const alias = join(application, 'node_modules'), handoff = join(application, 'original.json');
    await symlink(software, alias, 'dir');
    const previous: PhaseObservation[] = [];
    let primary: unknown;
    try {
      for (const phase of ['capture', 'approve', 'saved'] as const) {
        const record: PhaseRecord = {case: selected.case, phase, status: 'running', completed: false,
          startedAt: new Date().toISOString()};
        report.cases.push(record);
        let observed: CommandResult | undefined;
        try {
          await verifyPreparedPackages(prepared);
          observed = await command(process.execPath, [join(application, fixtureMembers[0]),
            phase, selected.case, handoff], {cwd: application, env,
            name: `project-store-${selected.case}-${phase}`,
            // Leave bounded time for cold open and first close around capture,
            // and for approval plus full Result verification of 101 writes.
            timeout: phase === 'capture' || selected.case === 'rows101' && phase === 'approve'
              ? 120_000 : 60_000});
          assert.equal(observed.code, 0); assert.equal(observed.signal ?? null, null);
          const actual = JSON.parse(observed.stdout.trim().split('\n').at(-1)!) as PhaseObservation;
          record.observation = actual;
          const original = JSON.parse(await readFile(handoff, 'utf8')) as OriginalHandoff;
          assertPackedProjectFileStorePhase({selected, phase, actual, pid: observed.pid, original, previous});
          previous.push(actual);
          await verifyPreparedPackages(prepared);
          record.status = 'passed'; record.completed = true;
        } catch (error) {
          observed ??= (error as {commandResult?: CommandResult} | undefined)?.commandResult;
          record.status = 'failed'; record.error = {name: (error as FailureView | undefined)?.name,
            code: (error as FailureView | undefined)?.code, message: (error as FailureView | undefined)?.message};
          throw error;
        } finally {
          Object.assign(record, {pid: observed?.pid ?? null, exitCode: observed?.code ?? null,
            signal: observed?.signal ?? null, endedAt: new Date().toISOString()});
        }
      }
    } catch (error) {primary = error; throw error;} finally {
      const errors: unknown[] = [];
      try {await verifyPreparedPackages(prepared);}
      catch (error) {errors.push(error);}
      try {assert.equal(await readlink(alias), software); await unlink(alias);}
      catch (error) {errors.push(error);}
      cleanup.push(...errors);
      if (errors.length) throw new AggregateError(
        [...(primary === undefined ? [] : [primary]), ...errors],
        'ProjectFileStorePackageCustodyFailed', {cause: primary});
    }
  }
  return report;
}
