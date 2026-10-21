// Synthetic timing observations for policy tests only, never product/baseline evidence.
import {createHash} from 'node:crypto';
import {sqliteQueryFixtures} from '../benchmark-node-sqlite.mjs';
const hash = value => createHash('sha256').update(JSON.stringify(value)).digest('hex');
export function syntheticSQLiteBaseline({queryMs = 2, durableMs = 3} = {}) {
  const samples = (ms, expected) => Array.from({length: 100}, (_, index) => ({index,
    wallNs: ms * 1e6, userUs: 1, systemUs: 1, pid: 1, verified: true,
    outputSha256: hash(expected), synthetic: true}));
  const protocol = {binding: 'node:sqlite DatabaseSync', concurrency: 1};
  return {schemaVersion: 1, kind: 'local-sqlite-comparator', synthetic: true,
    environment: {node: 'v22.22.0', platform: 'synthetic'}, load: 'isolated', profiled: false,
    executableSha256: '8'.repeat(64), collectorSha256: '9'.repeat(64),
    protocol, protocolSha256: hash(protocol), settings: {sqliteVersion: '3.50.4', journal_mode: 'wal',
      synchronous: 2, fullfsync: 0}, cleanup: {closed: true},
    savedFixture: {rows: 1, payload: '[{"id":1}]', plan: [{detail: 'SEARCH USING INTEGER PRIMARY KEY'}]},
    warm: [...sqliteQueryFixtures.map(fixture => ({operation: fixture.operation, mode: 'one-shot',
      fixture, samples: samples(queryMs, fixture.expected)})),
    ...['warm-result', 'warm-status', 'durable-transaction-read'].map(operation => ({operation,
      mode: 'prepared', samples: samples(operation === 'durable-transaction-read' ? durableMs : queryMs,
        operation === 'warm-status' ? {status: 'succeeded', revision: 0} : [{id: 1}])}))]};
}
