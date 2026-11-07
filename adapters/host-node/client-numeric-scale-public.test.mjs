import assert from 'node:assert/strict';
import {before, test} from 'node:test';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {verifyLocalSourceRuntime, assertSourceRuntimeReceiptCurrent} from '../../scripts/verify-local-source-runtime.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
let coherence;
before(async () => {
  coherence = await verifyLocalSourceRuntime(root);
});

function runPhase(phase, directory, referencePath, count) {
  const actor = fileURLToPath(new URL('./fixtures/numeric-scale-public-process.mjs', import.meta.url));
  const child = spawnSync(process.execPath, [actor, phase, directory, referencePath, String(count)],
    {cwd: root, env: process.env, encoding: 'utf8', timeout: 360000, maxBuffer: 8 * 1024 * 1024});
  assert.ifError(child.error);
  assert.equal(child.signal, null, child.stderr);
  assert.equal(child.status, 0, child.stderr);
  const lines = child.stdout.trim().split('\n');
  const report = JSON.parse(lines.at(-1));
  const {inputWireBytes, ...completion} = report;
  assert.deepEqual(completion, {phase, rowsVerified: count, closeReturned: true, pid: child.pid});
  if (phase === 'produce-source') {
    assert(Number.isSafeInteger(inputWireBytes) && inputWireBytes > 1048576);
    console.log(`Numeric JSON Source input: ${inputWireBytes} UTF8 bytes, ${count} rows`);
  } else assert.equal(inputWireBytes, undefined);
}

for (const {count, source} of [
  ...[1000, 10000, 10001, 100000].map(count => ({count, source: false})),
  {count: 100000, source: true},
]) {
  test(`ordinary ${source ? 'JSON Source ' : ''}numeric ${count} rows streams exact values across separate-process Saved with confirmed stop`, async () => {
    const directory = await mkdtemp(join(tmpdir(), 'actql-numeric-scale-test-'));
    let completed = false;
    try {
      const referencePath = join(directory, 'original-run-reference.json');
      runPhase(source ? 'produce-source' : 'produce', directory, referencePath, count);
      runPhase('restore', directory, referencePath, count);
      completed = true;
    } finally {
      assertSourceRuntimeReceiptCurrent(coherence);
      if (completed) await rm(directory, {recursive: true, force: true});
    }
  });
}
