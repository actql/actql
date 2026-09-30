import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {mkdir, mkdtemp, readFile, readdir, unlink, writeFile} from 'node:fs/promises';
import {join, resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath, pathToFileURL} from 'node:url';

// Build a separate, unmodified checkout of the fixed pre-R1 baseline first.
// The current tree must also have its release Node bridge prepared.
if (!process.argv[2]) throw new Error('Usage: node scripts/test-coordinator-legacy-custody.mjs <legacy-worktree>');
const legacy = resolve(process.argv[2]);
const current = fileURLToPath(new URL('../', import.meta.url));
const legacySha = '8028e8a708db6a5ef2b82f6d559b3d2bf7e55041';
const exec = (command, args, options = {}) => {
  const result = spawnSync(command, args, {...options, encoding: 'utf8'});
  assert.equal(result.status, 0, `${command}: ${result.stderr}\n${result.stdout}`);
  return result.stdout;
};
assert.equal(exec('git', ['rev-parse', 'HEAD'], {cwd: legacy}).trim(), legacySha);
exec('git', ['diff', '--exit-code', 'HEAD', '--', 'adapters/host-common', 'adapters/host-node/sqlite-coordinator-journal.mjs', 'src'], {cwd: legacy});
const scratch = join(process.env.ACTQL_TEST_SCRATCH_ROOT ?? tmpdir(), 'coordinator-legacy-custody');
await mkdir(scratch, {recursive: true});
const root = await mkdtemp(join(scratch, 'case-'));
const priorRoot = join(root, 'prior');
const nextRoot = join(root, 'next');
await mkdir(priorRoot);

const child = `
  import assert from 'node:assert/strict';
  const root = process.argv[1];
  const worktree = process.argv[2];
  const mode = process.argv[3];
  const {runtimeCore} = await import(worktree + '/adapters/host-common/runtime-core.mjs');
  const moon = await import(worktree + '/_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js');
  const {openSqliteCoordinatorDispatchJournal: open} = await import(worktree + '/adapters/host-node/sqlite-coordinator-journal.mjs');
  const control = runtimeCore(moon).remoteSiteControl;
  const cid = digit => 'sha256:' + digit.repeat(64);
  const request = control.prepare({
    coordinatorAuthority: 'coordinator-a', runDefinitionCid: cid('0'),
    taskKey: 'task-a', taskAttempt: 1, dispatchId: 'legacy-custody-proof',
    siteKey: 'site-a', siteGeneration: 1, runtimeBundleCid: cid('a'),
    connectorRegistration: 'local', connectorRevision: 'local/1',
    strategyRevision: 'strategy/1', inputBindingCid: cid('1'),
    obligationsCid: cid('2'), budgetCid: cid('3'),
    evidenceIssuerCapabilityCid: cid('b'), grantCid: cid('4'),
  });
  const options = {coordinatorAuthority: 'coordinator-a'};
  if (mode === 'refuse-new') {
    assert.throws(() => open(root, options), {code: 'UnsupportedCoordinatorJournalVersion'});
    console.log(JSON.stringify({oldWriterRefusedNew: true}));
    process.exit(0);
  }
  const store = open(root, options);
  if (mode === 'create') {
    const record = store.accept(control.prepareCoordinatorIntent(
      control.createCoordinatorJournal('coordinator-a'), request), request, control);
    store.advance(control.prepareCoordinatorObservation(record, {
      revision: 4, state: [4, 0, 3, 0, 0],
    }), record, control);
    assert.equal(store.inspectState(request, control)[5], 3);
    console.log(JSON.stringify({key: control.journalKey(request), state: store.inspectState(request, control)}));
    // Deliberately bypass close so the actual old owner's committed WAL remains.
    process.exit(0);
  }
  const recovered = store.recoverJournal(control.createCoordinatorJournal('coordinator-a'), control);
  assert.equal(recovered.length, 1);
  const [{record}] = recovered;
  assert.equal(control.coordinatorIntentMatches(record, request), true);
  assert.equal(store.inspectState(request, control)[5], 3);
  store.advance(control.prepareCoordinatorObservation(record, {
    revision: 6, state: [4, 0, 2, 0, 0],
  }), record, control);
  assert.equal(store.inspectState(request, control)[5], 2);
  store.close();
  console.log(JSON.stringify({key: control.journalKey(request), oldOwnerCustodyContinued: true}));
`;
const old = mode => JSON.parse(exec(process.execPath,
  ['--input-type=module', '-e', child, mode === 'refuse-new' ? nextRoot : priorRoot, legacy, mode]).trim());
const created = old('create');
const path = join(priorRoot, 'coordinator-dispatch-journal.sqlite3');
assert.ok((await readFile(`${path}-wal`)).length > 0);
await unlink(`${path}-shm`);
const snapshot = async directory => {
  const result = {};
  for (const name of (await readdir(directory)).sort()) {
    result[name] = createHash('sha256').update(await readFile(join(directory, name))).digest('hex');
  }
  return result;
};
const before = await snapshot(priorRoot);
const {openSqliteCoordinatorDispatchJournal: openCurrent} = await import(
  pathToFileURL(join(current, 'adapters/host-node/sqlite-coordinator-journal.mjs')));
assert.throws(() => openCurrent(priorRoot, {coordinatorAuthority: 'coordinator-a'}),
  {code: 'CoordinatorJournalObservationHistoryRequired'});
assert.deepEqual(await snapshot(priorRoot), before);
const continued = old('continue');
assert.deepEqual(continued.key, created.key);

const moon = await import(pathToFileURL(join(current,
  '_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js')));
const {runtimeCore} = await import(pathToFileURL(join(current, 'adapters/host-common/runtime-core.mjs')));
const control = runtimeCore(moon).remoteSiteControl;
const cid = digit => `sha256:${digit.repeat(64)}`;
const request = control.prepare({coordinatorAuthority: 'coordinator-a', runDefinitionCid: cid('0'),
  taskKey: 'task-a', taskAttempt: 1, dispatchId: 'current-custody-proof', siteKey: 'site-a',
  siteGeneration: 1, runtimeBundleCid: cid('a'), connectorRegistration: 'local',
  connectorRevision: 'local/1', strategyRevision: 'strategy/1', inputBindingCid: cid('1'),
  obligationsCid: cid('2'), budgetCid: cid('3'), evidenceIssuerCapabilityCid: cid('b'), grantCid: cid('4')});
const initial = openCurrent(nextRoot, {coordinatorAuthority: 'coordinator-a'});
const record = initial.accept(control.prepareCoordinatorIntent(control.createCoordinatorJournal('coordinator-a'), request), request, control);
initial.advance(control.prepareCoordinatorObservation(record, {revision: 1, state: [2, 0, 0, 0, 0]}), record, control);
const projection = initial.inspectState(request, control);
const history = control.coordinatorRecordHistoryJson(record);
initial.close();
old('refuse-new');
const reopened = openCurrent(nextRoot, {coordinatorAuthority: 'coordinator-a'});
const [{record: restored}] = reopened.recoverJournal(control.createCoordinatorJournal('coordinator-a'), control);
assert.deepEqual(reopened.inspectState(request, control), projection);
assert.equal(control.coordinatorRecordHistoryJson(restored), history);
reopened.close();
const evidence = {legacySha, root, actualOldOwnerWalWithNoShm: true,
  refusalPreservedEverySourceFileAndBytes: true, oldOwnerCustodyContinued: true,
  oldWriterRejectedNewFormatWithoutLogicalUpdate: true, recoveredExactKey: continued.key,
  limitation: 'Coordinator custody continuation; typed release observation is not physical Site cleanup. Old writer is not claimed to preserve new-format physical SQLite bytes.'};
await writeFile(join(root, 'evidence.json'), JSON.stringify(evidence, null, 2));
console.log(JSON.stringify(evidence, null, 2));
