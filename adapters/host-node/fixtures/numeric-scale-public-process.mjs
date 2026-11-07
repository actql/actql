import assert from 'node:assert/strict';
import {readFile, writeFile} from 'node:fs/promises';
import {open} from '@actql/node';

// The parent never opens a Host. Each phase imports the selected ordinary
// package in its own process; only the public Run reference crosses restart.
const [phase, directory, referencePath, countText] = process.argv.slice(2);
const count = Number(countText);
assert.ok(['produce', 'restore'].includes(phase));
assert.ok([1000, 10000, 10001, 100000].includes(count));

async function assertAllRows(run) {
  let read = 0, sum = 0n, squares = 0n;
  for await (const row of run.result('answer0').rows()) {
    assert.deepEqual(Object.keys(row), ['v0']);
    assert.equal(row.v0, read);
    const value = BigInt(row.v0);
    read++; sum += value; squares += value * value;
  }
  const n = BigInt(count);
  assert.equal(read, count);
  assert.equal(sum, n * (n - 1n) / 2n);
  assert.equal(squares, n * (n - 1n) * (2n * n - 1n) / 6n);
}

let db, primary, failed = false;
try {
  db = await open({stateDir: directory});
  let run;
  if (phase === 'produce') {
    const program = {
      version: 'actql/0.1', id: 'numeric-scale',
      stages: [{id: 'main', inputs: {}, steps: [{as: 'v', values: {
        schema: {v0: {type: 'number', nullable: false}},
        rows: Array.from({length: count}, (_, v0) => ({v0})),
      }}], results: {rows: {from: 'v', fields: ['v0']}}}],
      results: {answer0: {from: {stage: 'main', result: 'rows'}}},
    };
    run = await db.start(program);
    const outcome = await run.wait({signal: AbortSignal.timeout(300000)});
    assert.equal(outcome.status, 'succeeded', JSON.stringify(outcome));
    await assertAllRows(run);
    await writeFile(referencePath, JSON.stringify(run.ref), {flag: 'wx', mode: 0o600});
  } else {
    run = await db.attach(JSON.parse(await readFile(referencePath, 'utf8')));
    assert.equal((await run.status()).control.physical_stop, 'confirmed');
    await assertAllRows(run);
  }
} catch (cause) {failed = true; primary = cause;}
try {if (db !== undefined) await db.close();}
catch (cause) {
  if (failed) throw new AggregateError([primary, cause], 'Numeric phase and close failed', {cause: primary});
  throw cause;
}
if (failed) throw primary;
// This records the public close return. The parent separately requires a
// reaped successful process before it starts Saved, never a timeout/kill ACK.
console.log(JSON.stringify({phase, rowsVerified: count, closeReturned: true, pid: process.pid}));
