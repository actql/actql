// Separate process is required to exercise DuckDB's file lock, not its
// same-process instance/configuration cache. Only tests invoke this fixture.
import { DuckDBInstance } from '@duckdb/node-api';

let instance;
let connection;
try {
  instance = await DuckDBInstance.create(process.argv[2]);
  connection = await instance.connect();
  process.send({ ready: true });
  await new Promise(resolve => {
    process.once('message', resolve);
    process.once('disconnect', resolve);
  });
} finally {
  connection?.closeSync();
  instance?.closeSync();
  process.disconnect?.();
}
