import assert from 'node:assert/strict';
import {readFile, writeFile} from 'node:fs/promises';
import {open} from '@actql/node';
import type {Execution, LocalSession, RunReference} from '@actql/node';

// The parent never opens a Host. Each phase imports the selected ordinary
// package in its own process; only the public Run reference crosses restart.
const [phase, directory, referencePath, countText] = process.argv.slice(2);
const count = Number(countText);
assert.ok(['produce', 'produce-source', 'restore'].includes(phase));
assert.ok([1000, 10000, 10001, 100000].includes(count));

// Preserve the explicit finite 100k acceptance profile on both capture and
// Saved. Smaller controls keep the ordinary installation defaults. This is
// fixture selection before Host/Request construction, not a product cap change.
const installation = count === 100000 ? {
  requestMemory: {retainedBytes: 1073741824, executionBytes: 1073741824},
  sourceFreeMaxWork: 30000000,
} : undefined;

async function assertAllRows(run: Execution) {
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

let db: LocalSession | undefined, primary: unknown, failed = false, inputWireBytes: number | undefined;
try {
  db = await open({stateDir: directory,
    ...(installation === undefined ? {} : {installation})});
  let run;
  if (phase === 'produce' || phase === 'produce-source') {
    const program = {
      version: 'actql/0.1', id: 'numeric-scale',
      stages: [{id: 'main', inputs: {}, steps: [{as: 'v', values: {
        schema: {v0: {type: 'number', nullable: false}},
        rows: Array.from({length: count}, (_, v0) => ({v0})),
      }}], results: {rows: {from: 'v', fields: ['v0']}}}],
      results: {answer0: {from: {stage: 'main', result: 'rows'}}},
    };
    if (phase === 'produce-source') {
      const text = JSON.stringify(program);
      // Every authored key, string and numeric value in this fixture is ASCII.
      // The emitted wire's UTF16 length is therefore its exact UTF8 byte count;
      // no second serialization or size-only input traversal is needed.
      inputWireBytes = text.length;
      assert(inputWireBytes > 1048576);
      run = await db.startSource(text, {format: 'json'});
    } else {
      run = await db.start(program);
    }
    const outcome = await run.wait({signal: AbortSignal.timeout(300000)});
    assert.equal(outcome.status, 'succeeded', JSON.stringify(outcome));
    await assertAllRows(run);
    await writeFile(referencePath, JSON.stringify(run.ref), {flag: 'wx', mode: 0o600});
  } else {
    run = await db.attach(JSON.parse(await readFile(referencePath, 'utf8')) as RunReference);
    assert.equal((await run.status()).control!.physical_stop, 'confirmed');
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
console.log(JSON.stringify({phase, rowsVerified: count, closeReturned: true, pid: process.pid,
  ...(inputWireBytes === undefined ? {} : {inputWireBytes})}));
