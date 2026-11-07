import assert from 'node:assert/strict';
import {after, before, test} from 'node:test';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {prepareNumericScaleConsumer} from '../../scripts/numeric-scale-installed-fixture.mjs';
import {verifyNodeBenchmarkPackages} from '../../scripts/benchmark-node-operations.mjs';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {verifyLocalSourceRuntime, assertSourceRuntimeReceiptCurrent} from '../../scripts/verify-local-source-runtime.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
let coherence, prepared, scratch, startedCases = 0, completedCases = 0;
before(async () => {
  coherence = await verifyLocalSourceRuntime(root);
  scratch = await createOwnedScratch({parent: join(root, '..', '.codex-scratch'), prefix: 'actql-numeric-consumer-',
    label: 'Matching normal numeric consumer'});
  prepared = await prepareNumericScaleConsumer({repository: root, directory: scratch.path,
    command(command, args, {cwd}) {
      const env = {...process.env}; delete env.NODE_PATH; delete env.NODE_OPTIONS;
      const child = spawnSync(command, args, {cwd, env, encoding: 'utf8', timeout: 120000,
        maxBuffer: 8 * 1024 * 1024});
      assert.ifError(child.error); assert.equal(child.signal, null, child.stderr);
      assert.equal(child.status, 0, child.stderr);
    }});
});
after(async () => {
  if (coherence) assertSourceRuntimeReceiptCurrent(coherence);
  if (prepared) await verifyNodeBenchmarkPackages(prepared.manifest, prepared.manifestPath, prepared.consumer);
  if (startedCases > 0 && completedCases === startedCases) scratch.passed();
});

function runPhase(phase, directory, referencePath, count) {
  const env = {...process.env}; delete env.NODE_PATH; delete env.NODE_OPTIONS;
  const child = spawnSync(process.execPath, [prepared.actor, phase, directory, referencePath, String(count)],
    {cwd: prepared.consumer, env, encoding: 'utf8', timeout: 360000, maxBuffer: 8 * 1024 * 1024});
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
    startedCases++;
    const directory = await mkdtemp(join(tmpdir(), 'actql-numeric-scale-test-'));
    let completed = false;
    try {
      const referencePath = join(directory, 'original-run-reference.json');
      runPhase(source ? 'produce-source' : 'produce', directory, referencePath, count);
      runPhase('restore', directory, referencePath, count);
      completed = true;
      completedCases++;
    } finally {
      assertSourceRuntimeReceiptCurrent(coherence);
      if (completed) await rm(directory, {recursive: true, force: true});
    }
  });
}
