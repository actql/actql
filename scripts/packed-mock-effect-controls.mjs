// Required negative consumers of the SAME verified normal package installation.
// Each control owns a fresh original captured Run; no resubmit or private Host.
import assert from 'node:assert/strict';
import {mkdir, writeFile, readFile, copyFile, symlink, readlink, unlink} from 'node:fs/promises';
import {join, dirname} from 'node:path';
import {twoModelDealReviewFiles} from './fixtures/deal-review-two-models.mjs';
import {verifyNodeBenchmarkPackages, nodeBenchmarkFailure} from './benchmark-node-operations.mjs';

export const packedEffectControlCases = Object.freeze(['approve-deny', 'paused-cancel', 'changed-current']);

export function assertMockEffectControlOutcome(actual, mode, pid) {
  assert(packedEffectControlCases.includes(mode));
  assert.equal(actual.mode, mode); assert.equal(actual.pid, pid);
  assert.equal(actual.status, 'passed'); assert.equal(actual.primaryCode, undefined);
  assert.deepEqual(actual.firstClose, {attempted: true, returned: true});
  assert.deepEqual(actual.aliveScopedFD, {before: 0, after: 0});
  const work = actual.workObservation;
  assert.equal(work?.complete, true, 'Missing or lossy observation cannot prove zero writes');
  assert.equal(work.sourceAcquisitionStarts, 0);
  assert.equal(work.modelCallStarts, 0);
  assert.equal(work.effectReplacementReturns, 0);
  assert.equal(actual.targetUnchanged, true);
  assert.equal(actual.originalRun, true);
  if (mode === 'approve-deny') {
    assert.deepEqual(actual.refusal, {code: 'ExecutionAuthorizationDenied', action: 'deny', operation: 'sign'});
    assert.equal(actual.runStatus, 'waiting_checkpoint');
  } else if (mode === 'paused-cancel') {
    assert.equal(actual.cancellationKind, 'accepted');
    assert.equal(actual.runStatus, 'cancelled');
    assert.equal(actual.physicalStop, 'confirmed'); assert.equal(actual.resultAvailable, false);
  } else {
    assert.equal(actual.currentChanged, true);
    assert.equal(actual.runStatus, 'failed');
    assert.deepEqual(actual.refusal, {available: true, code: 'EffectTargetVersionMismatch',
      kind: 'target_version_mismatch', phase: 'effect_apply_preflight'});
    assert.equal(actual.staleApprovalRefused, true);
  }
}

async function runControl({prepared, root, repository, command, record}) {
  const {mode} = record;
  assert(packedEffectControlCases.includes(mode));
  await verifyNodeBenchmarkPackages(prepared.manifest, prepared.manifestPath, prepared.consumer);
  const project = join(root, `mock-effect-control-${mode}`); await mkdir(project);
  for (const [name, bytes] of Object.entries(twoModelDealReviewFiles())) {
    await mkdir(dirname(join(project, name)), {recursive: true});
    await writeFile(join(project, name), bytes, {flag: 'wx'});
  }
  for (const [source, target] of [
    ['adapters/host-node/fixtures/mock-project-effect-public.mjs', 'capture-original.mjs'],
    ['adapters/host-node/fixtures/work-observation.fixture.mjs', 'work-observation.fixture.mjs'],
    ['scripts/fixtures/mock-project-effect-control-capture.mjs', 'capture.mjs'],
    ['scripts/fixtures/mock-project-effect-cancel-public.mjs', 'control.mjs'],
    ['scripts/fixtures/record-approval/scoped-fds.fixture.mjs', 'record-approval/scoped-fds.fixture.mjs'],
  ]) {
    await mkdir(dirname(join(project, target)), {recursive: true});
    await copyFile(join(repository, source), join(project, target));
  }
  const software = join(prepared.consumer, 'node_modules'), alias = join(project, 'node_modules');
  await symlink(software, alias, 'dir');
  let failed = false, primary;
  try {
    const handoff = join(project, 'handoff.json');
    for (const phase of ['capture', 'control']) {
      const observation = {phase, completed: false, startedAt: new Date().toISOString()};
      record.phases.push(observation);
      const path = join(project, `${phase}.observation.json`);
      await writeFile(path, JSON.stringify(observation, null, 2) + '\n', {flag: 'wx'});
      try {
        const result = await command(process.execPath, phase === 'capture'
          ? [join(project, 'capture.mjs'), 'capture', handoff, 'deal-review-mock', 'two-models']
          : [join(project, 'control.mjs'), handoff, mode],
        {cwd: project, name: `effect-control-${mode}-${phase}`, timeout: 30_000});
        Object.assign(observation, {pid: result.pid, exitCode: result.code, signal: result.signal ?? null});
        assert.equal(result.code, 0); assert.equal(result.signal ?? null, null);
        const rows = result.stdout.trim().split('\n').map(line => JSON.parse(line));
        observation.actual = rows.at(-1);
        if (phase === 'capture') {
          assert.equal(rows.filter(row => row.step && row.status === 'passed').length, 10);
          const captured = rows.find(row => row.phase === 'capture' && row.firstClose);
          assert.equal(captured.status, 'passed'); assert.equal(captured.firstFailedStep, null);
          assert.deepEqual(captured.firstClose, {attempted: true, returned: true});
          assert.equal(captured.workObservation.complete, true);
          assert.equal(captured.workObservation.sourceAcquisitionStarts, 2);
          assert.equal(captured.workObservation.modelCallStarts, 4);
          assert.equal(captured.workObservation.effectReplacementReturns, 0);
          assert.equal(observation.actual.event, 'after-original-module');
          assert.equal(observation.actual.originalImportFailed, false);
          assert.equal(observation.actual.pid, result.pid);
          assert.deepEqual(observation.actual.aliveScopedFD, {after: 0});
        } else assertMockEffectControlOutcome(observation.actual, mode, result.pid);
        observation.completed = true;
      } catch (error) {
        observation.error = nodeBenchmarkFailure(error);
        const result = error.commandResult;
        if (result) {
          Object.assign(observation, {pid: result.pid, exitCode: result.code ?? null, signal: result.signal ?? null});
          try {
            const actual = JSON.parse(result.stdout.trim().split('\n').at(-1));
            if (phase === 'control' && actual.pid === result.pid && actual.mode === mode) observation.actual = actual;
          } catch { /* An absent final observation is not a successful close. */ }
        }
        // Keep an actual same-child pre-close primary when the final result or
        // first close is unobserved. Never infer success from process exit.
        if (phase === 'control') try {
          const partial = JSON.parse(await readFile(handoff + '.cancel.before-close.json', 'utf8'));
          assert.equal(partial.pid, error.commandResult?.pid);
          observation.partialObservation = partial;
        } catch { /* The original failure remains primary. */ }
        throw error;
      } finally {
        observation.endedAt = new Date().toISOString();
        await writeFile(path, JSON.stringify(observation, null, 2) + '\n');
      }
    }
  } catch (error) {failed = true; primary = error;}
  finally {
    try {assert.equal(await readlink(alias), software); await unlink(alias);}
    catch (cleanup) {
      if (failed) throw new AggregateError([primary, cleanup], 'MockEffectControlCleanupFailed', {cause: primary});
      throw cleanup;
    }
  }
  if (failed) throw primary;
}

export async function runMockEffectControls({prepared, root, repository, command, records, failures}) {
  assert.deepEqual(records.map(record => record.mode), packedEffectControlCases);
  for (const record of records) {
    record.status = 'running'; record.phases = []; delete record.unexecutedReason;
    try {
      await runControl({prepared, root, repository, command, record});
      record.completed = true; record.status = 'passed';
    } catch (error) {
      record.status = 'failed'; record.error = nodeBenchmarkFailure(error); failures.push(error);
    }
  }
}
