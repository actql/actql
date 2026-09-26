import test from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { fileURLToPath } from 'node:url';
import { DuckDBInstance } from '@duckdb/node-api';

const root = fileURLToPath(new URL('../../../../..', import.meta.url));

function logicalGroupRows(rows) {
  return rows.map(row => ({
    k: row.__actql_output_0,
    n: row.__actql_output_1,
    p: row.__actql_output_2,
  }));
}

test('owned MoonBit group SQL preserves NULL counts and UTF16 key order in DuckDB', async () => {
  const { stdout } = await promisify(execFile)('moon', [
    'test', '--target', 'js', 'src/query_integration/duckdb_count_group_wbtest.mbt',
  ], { cwd: root, maxBuffer: 2 * 1024 * 1024 });
  assert.match(stdout, /Total tests: 5, passed: 5, failed: 0/);
  const fixtures = stdout.split('\n').filter(line => line.startsWith('ACTQL_COUNT_GROUP '))
    .map(line => JSON.parse(line.slice('ACTQL_COUNT_GROUP '.length)));
  assert.deepEqual(fixtures.map(f => f.name), ['number', 'text']);
  // Inputs and expected answers are fixed independently of emitted SQL.
  const cases = {
    number: {
      type: 'DOUBLE', values: '(2),(NULL),(1),(2),(NULL),(-1)',
      expected: [{ k: null, n: 2, p: 0 }, { k: -1, n: 1, p: 1 },
        { k: 1, n: 1, p: 1 }, { k: 2, n: 2, p: 2 }],
    },
    text: {
      type: 'VARCHAR',
      values: '(chr(57344)),(chr(65536)),(NULL),(chr(65536)),(\'a\'),' +
        '(\'a\'),(\'A\'),(chr(55295))',
      expected: [{ k: null, n: 1, p: 0 }, { k: 'A', n: 1, p: 1 },
        { k: 'a', n: 2, p: 2 }, { k: '\ud7ff', n: 1, p: 1 },
        { k: '\u{10000}', n: 2, p: 2 }, { k: '\ue000', n: 1, p: 1 }],
    },
  };
  for (const fixture of fixtures) {
    const c = cases[fixture.name];
    const db = await DuckDBInstance.create(':memory:');
    const connection = await db.connect();
    try {
      if (fixture.name === 'text') {
        await connection.run("SET default_collation = 'nocase'");
      }
      await connection.run(`CREATE TABLE fixed(k ${c.type})`);
      await connection.run(`INSERT INTO fixed VALUES ${c.values}`);
      const result = await connection.runAndReadAll(fixture.sql);
      assert.deepEqual(logicalGroupRows(result.getRowObjects()), c.expected);
      await connection.run('DELETE FROM fixed');
      assert.deepEqual(
        logicalGroupRows(
          (await connection.runAndReadAll(fixture.sql)).getRowObjects(),
        ),
        [],
      );
    } finally {
      connection.closeSync();
      db.closeSync();
    }
  }
  const countIfFixtures = stdout.split('\n')
    .filter(line => line.startsWith('ACTQL_COUNT_IF '))
    .map(line => JSON.parse(line.slice('ACTQL_COUNT_IF '.length)));
  assert.equal(countIfFixtures.length, 1);
  const db = await DuckDBInstance.create(':memory:');
  const connection = await db.connect();
  try {
    await connection.run('CREATE TABLE fixed(k BOOLEAN)');
    await connection.run('INSERT INTO fixed VALUES (true),(false),(NULL),(true)');
    assert.deepEqual(
      (await connection.runAndReadAll(countIfFixtures[0].sql)).getRowObjects(),
      [{ __actql_output_0: 2 }],
    );
    await connection.run('DELETE FROM fixed');
    assert.deepEqual(
      (await connection.runAndReadAll(countIfFixtures[0].sql)).getRowObjects(),
      [{ __actql_output_0: 0 }],
    );
  } finally {
    connection.closeSync();
    db.closeSync();
  }
  // SQL/type/order conformance only: this test does not issue Compute evidence
  // or claim completion of the standard Host group/count execution path.
});
