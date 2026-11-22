// Uses one verified normal installation; only fixtures and read-only oracles
// are copied. Each case owns its state and three separate public processes.
import assert from 'node:assert/strict';
import {copyFile, mkdir, readFile, readlink, symlink, unlink, writeFile} from 'node:fs/promises';
import {dirname, isAbsolute, join} from 'node:path';
import {verifyNodeBenchmarkPackages} from './node-benchmark-evidence.mjs';
import type {BenchmarkPackageManifest} from './node-benchmark-evidence.mjs';
import type {assertRecordWorkflowWork} from '../adapters/host-node/fixtures/work-observation.fixture.mjs';

export const packedDependencyBoundaryCases = Object.freeze([
  Object.freeze({case: 'count', sourceStarts: 1, writes: 8,
    fixture: 'scripts/fixtures/packed-project-dependency-boundary.mjs'}),
  Object.freeze({case: 'width', sourceStarts: 24, writes: 1,
    fixture: 'scripts/fixtures/packed-table-dependency-width.mjs'}),
]);
export const packedDependencyBoundaryPhases = Object.freeze(['capture', 'approve', 'saved'] as const);
const fixtureMembers = [
  'scripts/fixtures/packed-project-dependency-boundary.mjs',
  'scripts/fixtures/project-file-dependency-boundary-cases.mjs',
  'scripts/fixtures/project-effect-dependency-observation.mjs',
  'scripts/fixtures/packed-table-dependency-width.mjs',
  'scripts/fixtures/table-dependency-width-cases.mjs',
  'scripts/fixtures/project-file-store-ledger-observation.mjs',
  'scripts/fixtures/record-approval/scoped-fds.fixture.mjs',
  'adapters/host-node/fixtures/work-observation.fixture.mjs',
  'adapters/host-node/fixtures/table-test-modules.mjs',
  'adapters/host-common/connector-manifest.fixture.mjs',
  'adapters/host-common/publication-contract-control.fixture.mjs',
  'spec/local-check-environment.json',
  'spec/contracts/actql-table-effect.json',
  'spec/contracts/actql-run-publication.json',
  'spec/contracts/actql-protocol-schemas.json',
];

type Phase = typeof packedDependencyBoundaryPhases[number];
type SelectedCase = typeof packedDependencyBoundaryCases[number];
type DependencyInventory = {uniqueData: number; canonicalDataBodyBytes: number; snapshotCid: string};
type CatalogCommit = {
  operation: {request_cid: string; action?: unknown; catalog_identity_cid?: unknown;
    namespace?: unknown; table_name?: unknown};
  receipt: {request_cid: string; row_count?: unknown};
};
type PhaseObservation = {
  phase: Phase; pid: number; complete: unknown; firstClose: unknown; firstCloseCalls: unknown;
  aliveScopedFD: unknown; cleanup: unknown; submits: unknown; approvals: unknown; ref: unknown;
  dependencies: DependencyInventory;
  workObservation: Parameters<typeof assertRecordWorkflowWork>[0] & {unbound?: unknown};
  requestMemory: unknown; sourceFreeMaxWork: unknown; zeroWritesBeforeApproval?: unknown;
  results?: {answer: unknown}; case?: unknown; originalInputsAndProgramAbsent?: unknown;
  targets?: unknown[]; wholeSources?: {relationCid: string}[];
  target?: {record: CatalogCommit; rows: unknown[]; generation: unknown};
};
type OriginalHandoff = {
  ref: unknown; captureComplete: unknown; capturePid: unknown; dependencies: unknown;
  approveComplete?: unknown; approvePid?: unknown; results?: unknown;
  targets?: unknown; ledger?: {successfulStores: unknown};
  unavailableDataFiles?: unknown[]; seedRecords?: CatalogCommit[]; allCommits?: CatalogCommit[];
  catalog?: {catalogCid: unknown}; target?: unknown;
};
type FailureView = {name?: unknown; code?: unknown; message?: unknown};
type CommandResult = {code: number | null; signal?: NodeJS.Signals | null; pid: number};
type PhaseRecord = {
  case: SelectedCase['case']; phase: Phase; status: 'unexecuted' | 'running' | 'passed' | 'failed';
  completed: boolean; unexecutedReason?: string; startedAt?: string;
  observation?: PhaseObservation; error?: FailureView;
  pid?: number | null; exitCode?: number | null; signal?: NodeJS.Signals | null; endedAt?: string;
};
type RunnerOptions = {
  prepared: {manifest: BenchmarkPackageManifest; manifestPath: string; consumer: string};
  root: string; repository: string;
  command: (executable: string, args: string[], options: {cwd: string; env: NodeJS.ProcessEnv; name: string; timeout: number}) =>
    CommandResult | PromiseLike<CommandResult>;
  report?: {cases: PhaseRecord[]; complete?: boolean}; cleanup?: unknown[];
};

export function assertPackedDependencyBoundaryPhase({selected, phase, actual, pid, original, previous}: {
  selected: SelectedCase; phase: Phase; actual: PhaseObservation; pid: number;
  original: OriginalHandoff; previous: readonly PhaseObservation[];
}) {
  assert(packedDependencyBoundaryPhases.includes(phase));
  assert.equal(actual.phase, phase); assert.equal(actual.pid, pid);
  assert(Number.isSafeInteger(pid) && pid > 0);
  assert.equal(actual.complete, true);
  assert.equal(actual.firstClose, 'returned'); assert.equal(actual.firstCloseCalls, 1);
  assert.deepEqual(actual.aliveScopedFD, {before: 0, after: 0});
  assert.deepEqual(actual.cleanup, []);
  const index = packedDependencyBoundaryPhases.indexOf(phase);
  assert.deepEqual(previous.map(value => value.phase), packedDependencyBoundaryPhases.slice(0, index));
  assert.equal(actual.submits, phase === 'capture' ? 1 : 0);
  assert.equal(actual.approvals, phase === 'approve' ? 1 : 0);
  assert.deepEqual(actual.ref, original.ref);
  assert.equal(original.captureComplete, true);
  assert.equal(original.capturePid, previous[0]?.pid ?? pid);
  for (const earlier of previous) {
    assert.notEqual(pid, earlier.pid, 'Capture, approval and Saved require separate processes');
    assert.deepEqual(actual.ref, earlier.ref);
    assert.deepEqual(actual.dependencies, earlier.dependencies);
  }
  const data = actual.dependencies;
  assert(Number.isSafeInteger(data?.uniqueData) && data.uniqueData > 0);
  assert(Number.isSafeInteger(data.canonicalDataBodyBytes) && data.canonicalDataBodyBytes > 0);
  assert.match(data.snapshotCid, /^sha256:[0-9a-f]{64}$/u);
  assert.deepEqual(data, original.dependencies);
  if (selected.case === 'count') assert(data.uniqueData > 4096);
  else assert(data.canonicalDataBodyBytes > 16777216);
  const work = actual.workObservation;
  assert.equal(work?.complete, true);
  assert.equal(work.modelCallStarts, 0); assert.equal(work.totals.modelCallStarts, 0);
  assert.equal(work.sourceAcquisitionStarts, phase === 'capture' ? selected.sourceStarts : 0);
  assert.equal(work.totals.sourceAcquisitionStarts, work.sourceAcquisitionStarts);
  assert.deepEqual(work.unbound,
    {sourceAcquisitionStarts: 0, modelCallStarts: 0, effectReplacementReturns: 0});
  assert.deepEqual(actual.requestMemory, {retainedBytes: 1073741824, executionBytes: 1073741824});
  assert.equal(actual.sourceFreeMaxWork, 30000000);
  if (phase === 'capture') {
    assert.notEqual(original.approveComplete, true);
    assert.equal(actual.zeroWritesBeforeApproval, true);
  } else {
    assert.equal(original.approveComplete, true);
    assert.equal(original.approvePid, phase === 'approve' ? pid : previous[1].pid);
    assert.deepEqual(actual.results, original.results);
  }
  if (selected.case === 'count') {
    assert.equal(actual.case, 'count');
    assert.equal(actual.originalInputsAndProgramAbsent, true);
    if (phase !== 'capture') {
      assert.equal(actual.targets!.length, selected.writes);
      assert.deepEqual(actual.targets, original.targets);
      assert.equal(original.ledger!.successfulStores, selected.writes);
    }
  } else {
    assert.equal(actual.wholeSources!.length, selected.sourceStarts);
    assert.equal(new Set(actual.wholeSources!.map(value => value.relationCid)).size, selected.sourceStarts);
    assert.equal(original.unavailableDataFiles!.length, selected.sourceStarts);
    if (phase !== 'capture') {
      // A Table write is its actual new Catalog operation and generation,
      // not a File replacement diagnostic. Preserve every seed record and
      // bind the one authored target's complete read to that same operation.
      assert.equal(original.seedRecords!.length, selected.sourceStarts);
      const seeds = new Map(original.seedRecords!.map(record =>
        [record.operation.request_cid, record]));
      assert.equal(seeds.size, selected.sourceStarts);
      assert.equal(original.allCommits!.length, seeds.size + selected.writes);
      assert.equal(new Set(original.allCommits!.map(record => record.operation.request_cid)).size,
        original.allCommits!.length);
      const writes = [];
      for (const record of original.allCommits!) {
        assert.equal(record.receipt.request_cid, record.operation.request_cid);
        const seed = seeds.get(record.operation.request_cid);
        if (seed !== undefined) assert.deepEqual(record, seed);
        else writes.push(record);
      }
      assert.equal(writes.length, selected.writes);
      assert.deepEqual(actual.target!.record, writes[0]);
      assert.equal(actual.target!.record.operation.action, 'create');
      assert.equal(actual.target!.record.operation.catalog_identity_cid, original.catalog!.catalogCid);
      assert.deepEqual(actual.target!.record.operation.namespace, ['test']);
      assert.equal(actual.target!.record.operation.table_name, 'summary');
      assert.equal(actual.target!.record.receipt.row_count, actual.target!.rows.length);
      assert.deepEqual(actual.target!.rows, actual.results!.answer);
      assert.deepEqual(actual.target!.generation, actual.target!.record.receipt);
      assert.deepEqual(actual.target, original.target);
    }
  }
  if (phase === 'saved') {
    assert.deepEqual(actual.results, previous[1].results);
    if (selected.case === 'count') assert.deepEqual(actual.targets, previous[1].targets);
    else assert.deepEqual(actual.target, previous[1].target);
  }
}

export async function runPackedDependencyBoundaries({prepared, root, repository, command,
  report = {cases: []}, cleanup = []}: RunnerOptions) {
  assert(isAbsolute(root) && isAbsolute(repository));
  assert.equal(typeof command, 'function'); assert(Array.isArray(report.cases));
  assert(!process.env.NODE_OPTIONS && !process.env.NODE_PATH &&
    !process.env.ACTQL_LOCAL_SOURCE_PROFILE && !process.env.ACTQL_LOCAL_EFFECT_PROFILE &&
    !process.env.ACTQL_TEST_TABLE_PACKED_APPLICATION, 'No ambient product overrides');
  assert(isAbsolute(process.env.ACTQL_TABLE_PYTHON ?? ''), 'Require the locked Table interpreter');
  await mkdir(root);
  const software = join(prepared.consumer, 'node_modules');
  const failures: unknown[] = [], cleanupStart = cleanup.length;
  for (const selected of packedDependencyBoundaryCases) {
    const application = join(root, selected.case); await mkdir(application);
    for (const member of fixtureMembers) {
      await mkdir(dirname(join(application, member)), {recursive: true});
      await copyFile(join(repository, member), join(application, member));
    }
    await writeFile(join(application, 'package.json'), '{"private":true,"type":"module"}\n');
    const home = join(application, 'home'); await mkdir(home);
    const env: NodeJS.ProcessEnv = {...process.env, HOME: home, PYTHONDONTWRITEBYTECODE: '1',
      PATH: [dirname(process.execPath), '/usr/bin', '/bin'].join(':')};
    delete env.ACTQL_PACKED_CLIENT_PACKAGES;
    if (selected.case === 'width') env.ACTQL_TEST_TABLE_PACKED_APPLICATION = prepared.consumer;
    const alias = join(application, 'node_modules'), handoff = join(application, 'original.json');
    await symlink(software, alias, 'dir');
    const previous: PhaseObservation[] = [], records: PhaseRecord[] = packedDependencyBoundaryPhases.map(phase => ({
      case: selected.case, phase, status: 'unexecuted', completed: false,
      unexecutedReason: phase === 'capture' ? 'Requires verified normal packages'
        : 'Requires original capture, dependency inventory and FIRST close'}));
    report.cases.push(...records);
    try {
      await verifyNodeBenchmarkPackages(prepared.manifest, prepared.manifestPath, prepared.consumer);
      for (const record of records) {
        const {phase} = record;
        Object.assign(record, {status: 'running', startedAt: new Date().toISOString()});
        delete record.unexecutedReason;
        let observed: CommandResult | undefined, primary: unknown, failed = false;
        try {
          const args = [join(application, selected.fixture), phase,
            ...(selected.case === 'count' ? ['count'] : []), handoff];
          observed = await command(process.execPath, args, {cwd: application, env,
            name: `dependency-${selected.case}-${phase}`,
            timeout: phase === 'capture' ? selected.case === 'width' ? 300000 : 180000 : 120000});
          assert.equal(observed.code, 0); assert.equal(observed.signal ?? null, null);
          const actual = JSON.parse(await readFile(join(application,
            `${selected.case}-${phase}.observation.json`), 'utf8')) as PhaseObservation;
          record.observation = actual;
          const original = JSON.parse(await readFile(handoff, 'utf8')) as OriginalHandoff;
          assertPackedDependencyBoundaryPhase({selected, phase, actual, pid: observed.pid, original, previous});
          previous.push(actual); record.status = 'passed'; record.completed = true;
        } catch (error) {
          observed ??= (error as {commandResult?: CommandResult} | undefined)?.commandResult;
          record.status = 'failed'; record.error = {name: (error as FailureView | undefined)?.name,
            code: (error as FailureView | undefined)?.code, message: (error as FailureView | undefined)?.message};
          failed = true; primary = error;
        } finally {
          Object.assign(record, {pid: observed?.pid ?? null, exitCode: observed?.code ?? null,
            signal: observed?.signal ?? null, endedAt: new Date().toISOString()});
          try {await verifyNodeBenchmarkPackages(prepared.manifest, prepared.manifestPath, prepared.consumer);}
          catch (error) {
            cleanup.push(error); record.status = 'failed'; record.completed = false;
            if (!failed) {failed = true; primary = error;}
          }
        }
        if (failed) throw primary;
      }
    } catch (error) {failures.push(error);} finally {
      try {assert.equal(await readlink(alias), software); await unlink(alias);}
      catch (error) {cleanup.push(error);}
    }
  }
  report.complete = failures.length === 0 && cleanup.length === cleanupStart && report.cases.length === 6 &&
    report.cases.every(value => value.completed && value.status === 'passed');
  const errors = [...failures, ...cleanup.slice(cleanupStart)];
  if (errors.length) throw new AggregateError(errors, 'PackedDependencyBoundariesFailed', {cause: errors[0]});
  return report;
}
