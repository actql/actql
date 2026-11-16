import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp, mkdir, readFile, rm, writeFile, access} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {setTimeout as delay} from 'node:timers/promises';
import {openSqliteEffectLedger} from '../adapters/host-node/sqlite-effect-ledger.mjs';
import {projectFileStoreProgressObservation} from './fixtures/project-file-store-progress-observation.mjs';

async function fixture(t, size = 101) {
  const root = await mkdtemp(join(tmpdir(), 'actql-file-progress-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const ledgerRoot = join(root, 'state', 'effects', 'ledger');
  const ledger = openSqliteEffectLedger(ledgerRoot, {authorityScopeCid: 'sha256:' + 'a'.repeat(64)});
  ledger.close();
  const destinationRoot = join(root, 'destination'); await mkdir(destinationRoot);
  const expectedFiles = Array.from({length: size}, (_, i) => ({path: `file-${i}`}));
  const path = join(ledgerRoot, 'effect-ledger.sqlite3');
  return {root, path, destinationRoot, expectedFiles,
    observe: instrumented => projectFileStoreProgressObservation({stateDir: root,
      destinationRoot, expectedFiles, instrumented})};
}

// Independent raw DB fixtures over the real physical schema. The counted
// records are not admitted claims, receipts, write ACKs or business success.
function records(path, from, to, outcome = false) {
  const db = new DatabaseSync(path);
  try {
    db.exec('PRAGMA foreign_keys = OFF');
    const insert = db.prepare(`INSERT INTO effect_ledger_responses
      (logical_item_locator_cid, dispatch_entry_cid, logical_request_scope_cid,
       credential_use_cid, status_code, response_bytes, physical_sha256)
      VALUES (?, ?, 'scope', 'use', 200, ?, 'physical')`);
    for (let i = from; i < to; i++) insert.run(`locator-${i}`, `dispatch-${i}`, Buffer.from('private-response-body'));
    if (outcome) db.exec(`INSERT INTO effect_ledger_outcomes VALUES
      ('dispatch-0','locator-0','scope','physical','outcome','private-outcome-wire','digest')`);
  } finally {db.close();}
}

test('failure progress reads only counts from the actual Ledger and bounded physical directory', async t => {
  const f = await fixture(t, 2); records(f.path, 0, 2, true);
  await writeFile(join(f.destinationRoot, 'file-0'), 'private-file-body');
  await writeFile(join(f.destinationRoot, '.temporary'), 'partial');
  await mkdir(join(f.destinationRoot, 'directory'));
  const before = await readFile(f.path), observation = f.observe(false);
  await observation.failure();
  assert.deepEqual(observation.data.failure.ledger,
    {available: true, durableResponses: 2, recordedOutcomes: 1});
  assert.deepEqual(observation.data.failure.files,
    {available: true, complete: true, entries: 3, regularFiles: 2, expectedFilesPresent: 1});
  assert.deepEqual(await readFile(f.path), before, 'read-only diagnostics preserve actual DB bytes');
  const wire = JSON.stringify(observation.data);
  for (const secret of ['private-response-body', 'private-outcome-wire', 'private-file-body', f.root])
    assert.equal(wire.includes(secret), false);
  assert.match(observation.data.qualification, /not physical write acknowledgements/u);
});

test('default observations perform no progress polling and do not create a missing Ledger', async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-file-progress-missing-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const observation = projectFileStoreProgressObservation({stateDir: root,
    destinationRoot: join(root, 'absent'), expectedFiles: [{path: 'one'}]});
  observation.poll();
  assert.deepEqual(observation.data.milestones, []); assert.deepEqual(observation.data.errors, []);
  await observation.failure();
  assert.deepEqual(observation.data.failure.ledger, {available: false});
  assert.deepEqual(observation.data.failure.files, {available: false});
  await assert.rejects(access(join(root, 'state')), {code: 'ENOENT'});
});

test('instrumented existing-poll samples retain at most first per-ten and final observations', async t => {
  const f = await fixture(t), observation = f.observe(true);
  let previous = 0;
  for (const count of [0, 1, 9, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 101]) {
    records(f.path, previous, count); previous = count; observation.poll();
  }
  for (let i = 0; i < 5; i++) observation.poll();
  assert.equal(observation.data.milestones.length, 12);
  assert.deepEqual(observation.data.milestones.map(value => value.durableResponses),
    [1, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 101]);
  assert(observation.data.milestones.every(value => value.recordedOutcomes === 0));
  assert.equal(observation.data.instrumentedProgress, true);
  assert.match(observation.data.performanceQualification, /not formal performance/u);
});

test('diagnostic directory traversal stops at its bounded prefix', async t => {
  const f = await fixture(t, 1), observation = f.observe(false);
  for (let i = 0; i < 6; i++) await writeFile(join(f.destinationRoot, `extra-${i}`), '');
  await observation.failure();
  assert.equal(observation.data.failure.files.complete, false);
  assert.equal(observation.data.failure.files.entries, 3);
  assert.equal(observation.data.failure.files.expectedFilesPresent, 0);
});

test('unexpected extra Ledger rows are unavailable rather than truncated progress', async t => {
  const f = await fixture(t, 1), observation = f.observe(true);
  records(f.path, 0, 5);
  observation.poll();
  assert.deepEqual(observation.data.milestones, []);
  await observation.failure();
  assert.deepEqual(observation.data.failure.ledger, {available: false});
  assert(observation.data.errors.some(value => value.operation === 'ledger-count'));
});

test('schema refusal remains best effort and never replaces the original AbortError report', async t => {
  const f = await fixture(t), db = new DatabaseSync(f.path);
  db.exec('DROP TABLE effect_ledger_outcomes'); db.close();
  const observation = f.observe(false), signal = AbortSignal.timeout(1);
  observation.stamp('window-start');
  let primary;
  try {await delay(20, undefined, {signal});}
  catch (error) {primary = error; observation.stamp('terminal-or-abort'); await observation.failure();}
  observation.stamp('close-pending');
  const pending = JSON.parse(JSON.stringify({primary: {name: primary.name}, phaseTiming: observation.data}));
  assert.strictEqual(primary.cause, signal.reason); assert.equal(pending.primary.name, 'AbortError');
  assert.deepEqual(pending.phaseTiming.failure.ledger, {available: false});
  assert(pending.phaseTiming.stages.some(value => value.stage === 'terminal-or-abort'));
  observation.stamp('close-begin'); observation.stamp('close-end');
  for (const value of observation.data.stages) for (const field of ['wallMs', 'userCpuUs', 'systemCpuUs'])
    assert(Number.isFinite(value[field]) && value[field] >= 0);
  assert.deepEqual(observation.data.stages.slice(-2).map(value => value.stage), ['close-begin', 'close-end']);
  assert(observation.data.errors.length > 0);
});
