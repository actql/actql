// Diagnostic only: compare native insertion overhead, not ActQL semantics,
// admission, CID generation, retention or end-to-end performance acceptance.
import assert from 'node:assert/strict';
import {DuckDBInstance} from '@duckdb/node-api';

const rows = Number(process.env.ACTQL_IMPORT_PROBE_ROWS ?? 10000);
const rounds = Number(process.env.ACTQL_IMPORT_PROBE_ROUNDS ?? 3);
if (!Number.isSafeInteger(rows) || rows < 1 || rows > 1000000 ||
    !Number.isSafeInteger(rounds) || rounds < 1 || rounds > 20) {
  throw Error('Invalid import probe bounds');
}
const modes = ['prepare-each-row', 'reuse-prepared', 'appender'];
for (let round = 0; round < rounds; round++) {
  for (let offset = 0; offset < modes.length; offset++) {
    const mode = modes[(round + offset) % modes.length];
    const db = await DuckDBInstance.create(':memory:', {threads: '1', memory_limit: '128MiB'});
    let connection, prepared, appender;
    try {
      connection = await db.connect();
      await connection.run('CREATE TEMP TABLE probe(id DOUBLE NOT NULL)');
      await connection.run('BEGIN TRANSACTION');
      const started = performance.now();
      if (mode === 'appender') {
        appender = await connection.createAppender('probe', 'main', 'temp');
        for (let row = 0; row < rows; row++) {
          appender.appendDouble(row);
          appender.endRow();
          if ((row + 1) % 128 === 0) appender.flushSync();
        }
        appender.closeSync();
        appender = undefined;
      } else {
        for (let row = 0; row < rows; row++) {
          if (!prepared) {
            const extracted = await connection.extractStatements('INSERT INTO probe VALUES (?)');
            prepared = await extracted.prepare(0);
          }
          prepared.bindDouble(1, row);
          const result = await prepared.stream();
          for (;;) {
            const chunk = await result.fetchChunk();
            if (!chunk || chunk.rowCount === 0) break;
          }
          if (mode === 'prepare-each-row') {
            prepared.destroySync();
            prepared = undefined;
          }
        }
        prepared?.destroySync();
        prepared = undefined;
      }
      const milliseconds = performance.now() - started;
      const result = await connection.runAndReadAll('SELECT count(*), min(id), max(id), sum(id) FROM probe');
      assert.deepEqual(result.getRows(), [[BigInt(rows), 0, rows - 1, rows * (rows - 1) / 2]]);
      console.log(JSON.stringify({kind: 'native-import-diagnostic', mode, round, rows,
        milliseconds, verification: 'count/min/max/sum',
        excludes: 'ActQL admission, guards, CID, independent retention, process start, final cleanup'}));
      await connection.run('ROLLBACK');
    } finally {
      // This isolated probe is not production cleanup evidence. In particular,
      // Appender destruction is SDK-finalizer managed, unlike prepared SQL.
      try { appender?.closeSync(); } finally {
        try { prepared?.destroySync(); } finally {
          try { connection?.closeSync(); } finally { db.closeSync(); }
        }
      }
    }
  }
}
