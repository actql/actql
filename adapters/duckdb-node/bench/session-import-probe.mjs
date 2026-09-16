// Real transport comparison; not the registered full ActQL performance gate.
import assert from 'node:assert/strict';
import {withComputeDatabase} from '../session.mjs';

const rows = Number(process.env.ACTQL_IMPORT_PROBE_ROWS ?? 10000);
const rounds = Number(process.env.ACTQL_IMPORT_PROBE_ROUNDS ?? 3);
if (!Number.isSafeInteger(rows) || rows < 1 || rows > 100000 ||
    !Number.isSafeInteger(rounds) || rounds < 1 || rounds > 20) throw Error('Invalid diagnostic bounds');
const limits = {maxRows: rows + 1, maxCells: rows + 4, maxTransportBytes: rows * 1000 + 10000,
  maxSqlBytes: 1000, maxParameters: 1, maxColumns: 4, maxChunkRows: 128, maxChunkBytes: 4096,
  memoryBytes: 128 * 1024 * 1024, threads: 1};
const modes = ['command', 'insert'];
let expectedUsage;
for (let round = 0; round < rounds; round++) {
  for (let offset = 0; offset < modes.length; offset++) {
    const mode = modes[(round + offset) % modes.length];
    const started = performance.now();
    const output = await withComputeDatabase(limits, async session => {
      await session.command('CREATE TEMP TABLE probe(id BIGINT)', [], () => {});
      for (let row = 0; row < rows; row++) {
        await session[mode]('INSERT INTO probe VALUES (?)', [{type: {id: 'BIGINT'}, value: String(row)}], () => {});
      }
      const result = [];
      await session.command('SELECT count(*)::VARCHAR, min(id)::VARCHAR, max(id)::VARCHAR, sum(id)::VARCHAR FROM probe',
        [], chunk => {
          for (let row = 0; row < chunk.rowCount; row++) result.push(chunk.columns.map(column => column[row]));
        });
      return result;
    });
    const milliseconds = performance.now() - started;
    assert.deepEqual(output.value, [[String(rows), '0', String(rows - 1), String(rows * (rows - 1) / 2)]]);
    const usage = Object.fromEntries(['rows', 'cells', 'transportBytes', 'statements', 'chunks']
      .map(key => [key, output.usage[key]]));
    expectedUsage ??= usage;
    assert.deepEqual(usage, expectedUsage);
    assert.equal(output.usage.preparations, mode === 'command' ? rows + 2 : 3);
    console.log(JSON.stringify({kind: 'session-import-diagnostic', mode, round, rows, milliseconds,
      usage: output.usage, includes: 'DB setup, bounded transport, verification query, explicit cleanup',
      excludes: 'MoonBit admission, logical guards, CID, independent holding, process start'}));
  }
}
