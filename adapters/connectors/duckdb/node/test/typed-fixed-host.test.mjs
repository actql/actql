import test from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { readFile } from 'node:fs/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { join } from 'node:path';
import { createHash } from 'node:crypto';
import { runFixedHostCompute } from '../host.mjs';
import {pinnedEngineContracts} from './pinned-engine-contracts.mjs';

const root = fileURLToPath(new URL('../../../../..', import.meta.url));
const limits = { maxRows: 100, maxCells: 1000, maxTransportBytes: 100000,
  maxSqlBytes: 10000, maxParameters: 10, maxColumns: 10,
  memoryBytes: 128 * 1024 * 1024, threads: 1 };
const hash = value => `sha256:${createHash('sha256').update(JSON.stringify(value)).digest('hex')}`;

test('standard fixed Host retains typed projected values through completion and checked consumer', async () => {
  const exec = promisify(execFile);
  await exec('moon', ['build', '--target', 'js', '--release', 'src/connectors/duckdb/host_node'], { cwd: root });
  await exec('moon', ['build', '--target', 'js', '--release', 'src/connectors/duckdb/conformance'], { cwd: root });
  const moon = await import(pathToFileURL(join(root, '_build/js/release/build/connectors/duckdb/conformance/conformance.js')));
  const contracts = await pinnedEngineContracts(root);
  const cases = [
    [{ type: 'string', nullable: true }, '日本語'],
    [{ type: 'boolean', nullable: true }, false],
    [{ type: 'boolean', nullable: true }, false, 'amount = false',
      [{ amount: false }, { amount: false }, { amount: false }]],
    [{ type: 'boolean', nullable: true }, false, 'amount = true', []],
    [{ type: 'number', nullable: true }, 9007199254740992],
    [{ type: 'number', nullable: true }, -1.5],
    [{ type: 'decimal', precision: 38, scale: 2, nullable: true }, '999999999999999999999999999999999999.99'],
    [{ type: 'date', nullable: true }, '2000-02-29'],
    [{ type: 'timestamp', nullable: true }, '1969-12-31T23:59:59.999Z'],
  ];
  for (const [contract, value, predicate = 'id > 2', expectedRows] of cases) {
    // Fixed oracle: numeric predicate drops the second row, projection drops id.
    // Neither the SQL result nor the Local result supplies the expected values.
    const expected = hash(expectedRows ?? [{ amount: value }, { amount: null }, { amount: value }]);
    const pipeline = JSON.stringify([
      { values: { schema: { id: { type: 'number', nullable: false }, amount: contract },
        rows: [{ id: 3, amount: value }, { id: 1, amount: value },
          { id: 4, amount: null }, { id: 3, amount: value }] }, as: 'seed' },
      { select: ['id', 'amount'] },
    ]);
    const fixture = moon.typedFixedCreate(pipeline, predicate, ...contracts);
    assert.equal(moon.ownedFixedLocalCid(fixture), expected, contract.type);
    const setup = moon.ownedFixedConfiguration(fixture);
    const result = await runFixedHostCompute(setup, limits, { maxRows: 4, maxCells: 8 });
    const output = result.output();
    try {
      assert.equal(result.importedRows, 4);
      assert.equal(result.importedCells, 8);
      assert.equal(moon.ownedFixedConsumeOutput(fixture, output), expected, contract.type);
      const foreign = moon.typedFixedCreate(pipeline, predicate, ...contracts);
      assert.equal(moon.ownedFixedConsumeOutput(foreign, output), 'null');
    } finally { result.close(); }
    assert.equal(moon.ownedFixedConsumeOutput(fixture, output), 'null');
    // Releasing native completion does not consume the shared fixed producer.
    assert.equal(moon.ownedFixedLocalCid(fixture), expected, contract.type);
  }
  // Group ordering and both count forms use literal independent expectations,
  // not a Native-vs-Local equality oracle. Every mapped ActQL scalar participates
  // as a grouping key and as the direct nullable count field.
  const groups = [
    [{ type: 'string', nullable: true }, '\ue000', '\u{10000}'],
    [{ type: 'boolean', nullable: true }, true, false],
    [{ type: 'number', nullable: true }, 9007199254740992, -1.5],
    [{ type: 'decimal', precision: 38, scale: 2, nullable: true },
      '999999999999999999999999999999999999.99', '-1.00'],
    [{ type: 'date', nullable: true }, '9999-12-31', '0000-01-01'],
    [{ type: 'timestamp', nullable: true }, '9999-12-31T23:59:59.999Z', '0000-01-01T00:00:00.000Z'],
  ];
  for (const [contract, high, low] of groups) {
    const expected = hash([{ amount: null, n: 1, p: 0 },
      { amount: low, n: 1, p: 1 }, { amount: high, n: 2, p: 2 }]);
    const pipeline = JSON.stringify([
      { values: { schema: { amount: contract }, rows: [high, null, low, high].map(amount => ({ amount })) }, as: 'seed' },
      { select: ['amount'] },
    ]);
    const fixture = moon.typedCountCreate(pipeline, ...contracts);
    assert.equal(moon.ownedFixedLocalCid(fixture), expected, `${contract.type} Local count`);
    const result = await runFixedHostCompute(moon.ownedFixedConfiguration(fixture), limits,
      { maxRows: 4, maxCells: 4 });
    try {
      assert.equal(result.importedRows, 4);
      assert.equal(moon.ownedFixedConsumeOutput(fixture, result.output()), expected, `${contract.type} DuckDB count`);
      const foreign = moon.typedCountCreate(pipeline, ...contracts);
      assert.equal(moon.ownedFixedConsumeOutput(foreign, result.output()), 'null');
    } finally { result.close(); }
    assert.equal(moon.ownedFixedLocalCid(fixture), expected);
    // The same scalar is an actual SQL join key, not only transported payload.
    // Left occurrence order differs from group order; NULL does not match NULL.
    const joinedExpected = hash([high, high, low, high, high].map(amount => ({ amount })));
    const joined = moon.typedJoinCreate(pipeline, ...contracts);
    assert.equal(moon.ownedFixedLocalCid(joined), joinedExpected, `${contract.type} Local join`);
    const joinedResult = await runFixedHostCompute(moon.ownedFixedConfiguration(joined), limits,
      { maxRows: 4, maxCells: 8 });
    try {
      assert.equal(joinedResult.importedRows, 8);
      assert.equal(joinedResult.importedCells, 8);
      assert.equal(moon.ownedFixedConsumeOutput(joined, joinedResult.output()), joinedExpected,
        `${contract.type} DuckDB join completion and consumer`);
      const foreignJoin = moon.typedJoinCreate(pipeline, ...contracts);
      assert.equal(moon.ownedFixedConsumeOutput(foreignJoin, joinedResult.output()), 'null');
    } finally { joinedResult.close(); }
    assert.equal(moon.ownedFixedLocalCid(joined), joinedExpected);
  }
});
