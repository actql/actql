import test from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { readFile } from 'node:fs/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { join } from 'node:path';
import { createHash } from 'node:crypto';
import { runFixedHostCompute } from '../host.mjs';

const root = fileURLToPath(new URL('../../..', import.meta.url));
const limits = { maxRows: 100, maxCells: 1000, maxTransportBytes: 100000,
  maxSqlBytes: 10000, maxParameters: 10, maxColumns: 10,
  memoryBytes: 128 * 1024 * 1024, threads: 1 };
const hash = value => `sha256:${createHash('sha256').update(JSON.stringify(value)).digest('hex')}`;

test('standard fixed Host retains typed projected values through completion and checked consumer', async () => {
  const exec = promisify(execFile);
  await exec('moon', ['build', '--target', 'js', '--release', 'src/duckdb_host_node'], { cwd: root });
  await exec('moon', ['build', '--target', 'js', '--release', 'src/duckdb_conformance'], { cwd: root });
  const moon = await import(pathToFileURL(join(root, '_build/js/release/build/duckdb_conformance/duckdb_conformance.js')));
  const source = await readFile(join(root, 'src/query_integration/pinned_engine_contracts_wbtest.mbt'), 'utf8');
  const contracts = [...source.matchAll(/@json\.parse\(\s*("(?:[^"\\]|\\.)*")/g)].map(match => JSON.parse(match[1]));
  const cases = [
    [{ type: 'string', nullable: true }, '日本語'],
    [{ type: 'boolean', nullable: true }, false],
    [{ type: 'number', nullable: true }, 9007199254740992],
    [{ type: 'number', nullable: true }, -1.5],
    [{ type: 'decimal', precision: 38, scale: 2, nullable: true }, '999999999999999999999999999999999999.99'],
    [{ type: 'date', nullable: true }, '2000-02-29'],
    [{ type: 'timestamp', nullable: true }, '1969-12-31T23:59:59.999Z'],
  ];
  for (const [contract, value] of cases) {
    // Fixed oracle: numeric predicate drops the second row, projection drops id.
    // Neither the SQL result nor the Local result supplies the expected values.
    const expected = hash([{ amount: value }, { amount: null }, { amount: value }]);
    const pipeline = JSON.stringify([
      { values: { schema: { id: { type: 'number', nullable: false }, amount: contract },
        rows: [{ id: 3, amount: value }, { id: 1, amount: value },
          { id: 4, amount: null }, { id: 3, amount: value }] }, as: 'seed' },
      { select: ['id', 'amount'] },
    ]);
    const fixture = moon.typedFixedCreate(pipeline, ...contracts);
    assert.equal(moon.ownedFixedLocalCid(fixture), expected, contract.type);
    const setup = moon.ownedFixedConfiguration(fixture);
    const result = await runFixedHostCompute(setup, limits, { maxRows: 4, maxCells: 8 });
    const output = result.output();
    try {
      assert.equal(result.importedRows, 4);
      assert.equal(result.importedCells, 8);
      assert.equal(moon.ownedFixedConsumeOutput(fixture, output), expected, contract.type);
      const foreign = moon.typedFixedCreate(pipeline, ...contracts);
      assert.equal(moon.ownedFixedConsumeOutput(foreign, output), 'null');
    } finally { result.close(); }
    assert.equal(moon.ownedFixedConsumeOutput(fixture, output), 'null');
    // Releasing native completion does not consume the shared fixed producer.
    assert.equal(moon.ownedFixedLocalCid(fixture), expected, contract.type);
  }
});
