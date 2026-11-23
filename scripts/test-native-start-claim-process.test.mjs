import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {createHash} from 'node:crypto';
import {existsSync, readFileSync, realpathSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {test} from 'node:test';
import {setTimeout as delay} from 'node:timers/promises';
import {fileURLToPath} from 'node:url';
import {promisify} from 'node:util';
import {createOwnedScratch} from './owned-scratch.mjs';

const execute = promisify(execFile);
const repository = fileURLToPath(new URL('../', import.meta.url));
const filename = 'journal_native_wbtest.mbt';
const testName = 'native competing processes authorize one physical start for the same revision';

test('separate Native processes contend for one durable start revision', async () => {
  const root = await createOwnedScratch({parent: realpathSync(tmpdir()),
    prefix: 'actql-native-start-claim-', label: testName});
  const folder = join(repository, '_build/native/debug/test/platform_native/remote_journal');
  const binary = join(folder, 'remote_journal.whitebox_test.exe');
  const metadata = JSON.parse(readFileSync(join(folder, '__whitebox_test_info.json'), 'utf8'));
  const selected = metadata.tests[filename].filter(item => item.name === testName);
  assert.equal(selected.length, 1);
  const {index} = selected[0];
  const args = [`${filename}:${index}-${index + 1}`];
  const library = process.env.ACTQL_TEST_NATIVE_SQLITE_LIBRARY;
  assert.ok(library, 'Use the original selected Native SQLite library');
  const run = phase => execute(binary, args, {cwd: root.path, timeout: 15000,
    maxBuffer: 1024 * 1024, env: {...process.env,
      ACTQL_TEST_NATIVE_SQLITE_ROOT: root.path,
      ACTQL_TEST_NATIVE_START_CLAIM_PHASE: phase}});
  const snapshot = () => {
    const db = new DatabaseSync(join(root.path, 'start-claim.sqlite3'), {readOnly: true});
    try {
      const rows = kind => db.prepare(
        'SELECT record_key, revision, body FROM actql_records WHERE namespace = ?'
      ).all(kind);
      return {dispatch: rows('site_dispatch'), claims: rows('site_start_claim')};
    } finally { db.close(); }
  };
  const output = ({stdout}) => {
    const results = stdout.split('\n').filter(line => line.startsWith('\x7b'))
      .map(line => JSON.parse(line)).filter(line => line.type === 'result');
    assert.equal(results.length, 1, stdout);
    assert.deepEqual([results[0].file, results[0].index, results[0].message], [filename, index, '']);
    return stdout.split('\n').find(line => line.startsWith('NativeStartClaim: '));
  };

  const seed = run('seed');
  output(await seed);
  const initial = snapshot();
  assert.equal(initial.dispatch.length, 1);
  assert.equal(initial.dispatch[0].revision, 0);
  assert.deepEqual(initial.claims, []);
  const phases = ['claim-a', 'claim-b'];
  const workers = phases.map(run);
  try {
    const bothReady = (async () => {
      for (let attempt = 0; attempt < 250; attempt++) {
        if (phases.every(phase => existsSync(join(root.path, phase + '-ready')))) return;
        await delay(20);
      }
      assert.fail('Both original contenders must prepare before dispatch');
    })();
    await Promise.race([bothReady, ...workers.map(worker =>
      worker.then(() => assert.fail('A contender exited before the start barrier')))]);
    assert.deepEqual(snapshot(), initial);
    for (const worker of workers) worker.child.stdin.end('\n');
    const outcomes = (await Promise.all(workers)).map(output);
    assert.equal(new Set([seed, ...workers].map(worker => worker.child.pid)).size, 3);
    const winner = phases.find(phase => outcomes.includes('NativeStartClaim: ' + phase + ' won'));
    assert.ok(winner, 'One Native Journal must grant the start permit');
    const loser = phases.find(phase => phase !== winner);
    assert.deepEqual(new Set(outcomes), new Set([
      'NativeStartClaim: ' + winner + ' won',
      'NativeStartClaim: ' + loser + ' lost to ' + winner,
    ]));
    const finished = snapshot();
    const attemptKey = initial.dispatch[0].record_key;
    assert.deepEqual(finished.dispatch.map(row => [row.record_key, row.revision]), [[attemptKey, 1]]);
    assert.deepEqual(finished.claims.map(row => [row.record_key, row.revision]), [[attemptKey, 0]]);
    console.log(JSON.stringify({initialRevision: 0, finalRevision: 1,
      claimRecords: 1, permits: 1, rejectedPermits: 1,
      pids: [seed, ...workers].map(worker => worker.child.pid),
      binarySha256: createHash('sha256').update(readFileSync(binary)).digest('hex')}));
  } finally {
    for (const worker of workers) {
      if (worker.child.exitCode === null && worker.child.signalCode === null) worker.child.kill();
    }
    await Promise.allSettled(workers);
  }
  await root.passed();
});
