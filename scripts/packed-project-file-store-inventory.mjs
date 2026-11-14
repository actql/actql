// Consumes a supplied immutable normal installation. It never packs, installs,
// compiles or imports the repository Host. Required packed CI wiring owns when
// this runner is selected and supplies its existing bounded command recorder.
import assert from 'node:assert/strict';
import {copyFile, mkdir, readFile, readlink, symlink, unlink, writeFile} from 'node:fs/promises';
import {dirname, isAbsolute, join} from 'node:path';
import {verifyNodeBenchmarkPackages} from './benchmark-node-operations.mjs';

export const packedProjectFileStoreInventoryCases = Object.freeze([
  Object.freeze({case: 'rows101', writes: 101, definitions: 1, rows: 101}),
  Object.freeze({case: 'members17', writes: 17, definitions: 17, rows: 1}),
]);
const fixtureMembers = [
  'scripts/fixtures/packed-project-file-store-inventory.mjs',
  'scripts/fixtures/project-file-store-inventory-cases.mjs',
  'scripts/fixtures/project-file-store-ledger-observation.mjs',
  'scripts/fixtures/record-approval/scoped-fds.fixture.mjs',
];

export async function runPackedProjectFileStoreInventory({prepared, root, repository, command,
  report = {cases: []}, cleanup = []}) {
  assert(isAbsolute(root) && isAbsolute(repository));
  assert.equal(typeof command, 'function'); assert(Array.isArray(report.cases));
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
    const env = {...process.env, HOME: home, PATH: [dirname(process.execPath), '/usr/bin', '/bin'].join(':')};
    delete env.ACTQL_PACKED_CLIENT_PACKAGES;
    const alias = join(application, 'node_modules'), handoff = join(application, 'original.json');
    await symlink(software, alias, 'dir');
    let capture, primary;
    try {
      for (const phase of ['capture', 'saved']) {
        const record = {case: selected.case, phase, status: 'running', completed: false,
          startedAt: new Date().toISOString()};
        report.cases.push(record);
        let observed;
        try {
          await verifyNodeBenchmarkPackages(prepared.manifest, prepared.manifestPath, prepared.consumer);
          observed = await command(process.execPath, [join(application, fixtureMembers[0]),
            phase, selected.case, handoff], {cwd: application, env,
            name: `project-store-${selected.case}-${phase}`, timeout: 60_000});
          assert.equal(observed.code, 0); assert.equal(observed.signal ?? null, null);
          const actual = JSON.parse(observed.stdout.trim().split('\n').at(-1));
          record.observation = actual;
          assert.equal(actual.case, selected.case); assert.equal(actual.phase, phase);
          assert.equal(actual.pid, observed.pid); assert.equal(actual.complete, true);
          assert.equal(actual.submits, phase === 'capture' ? 1 : 0);
          assert.equal(actual.approvals, phase === 'capture' ? 1 : 0);
          assert.equal(actual.successfulStores, selected.writes);
          assert.equal(actual.memberPreviews, selected.definitions);
          assert.equal(actual.modelAttempts, 0);
          assert.equal(actual.rows.length, selected.rows);
          assert.deepEqual(actual.requestMemory, {retainedBytes: 536870912, executionBytes: 536870912});
          assert.equal(actual.firstClose, 'returned'); assert.equal(actual.firstCloseCalls, 1);
          assert.deepEqual(actual.aliveScopedFD, {before: 0, after: 0});
          assert.deepEqual(actual.cleanup, []); assert.equal(actual.originalInputsAndProgramAbsent, true);
          const original = JSON.parse(await readFile(handoff, 'utf8'));
          assert.equal(original.complete, true); assert.deepEqual(original.ref, actual.ref);
          assert.deepEqual(original.rows, actual.rows); assert.deepEqual(original.targets, actual.targets);
          assert.equal(original.ledger.receipts.length, selected.writes);
          if (phase === 'capture') {
            assert.equal(actual.zeroWritesBeforeApproval, true); capture = actual;
          } else {
            assert.notEqual(actual.pid, capture.pid); assert.deepEqual(actual.ref, capture.ref);
            assert.deepEqual(actual.rows, capture.rows); assert.deepEqual(actual.targets, capture.targets);
            assert.equal(actual.sourceAttempts, capture.sourceAttempts);
            assert.equal(actual.newEffectCommits, 0);
          }
          await verifyNodeBenchmarkPackages(prepared.manifest, prepared.manifestPath, prepared.consumer);
          record.status = 'passed'; record.completed = true;
        } catch (error) {
          observed ??= error?.commandResult;
          record.status = 'failed'; record.error = {name: error?.name, code: error?.code, message: error?.message};
          throw error;
        } finally {
          Object.assign(record, {pid: observed?.pid ?? null, exitCode: observed?.code ?? null,
            signal: observed?.signal ?? null, endedAt: new Date().toISOString()});
        }
      }
    } catch (error) {primary = error; throw error;} finally {
      const errors = [];
      try {await verifyNodeBenchmarkPackages(prepared.manifest, prepared.manifestPath, prepared.consumer);}
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
