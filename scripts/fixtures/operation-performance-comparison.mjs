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
      synchronous: 2, fullfsync: 0, checkpoint_fullfsync: 0}, cleanup: {closed: true},
    savedFixture: {rows: 1, payload: '[{"id":1}]', plan: [{detail: 'SEARCH USING INTEGER PRIMARY KEY'}]},
    warm: [...sqliteQueryFixtures.map(fixture => ({operation: fixture.operation, mode: 'one-shot',
      fixture, samples: samples(queryMs, fixture.expected)})),
    ...['warm-result', 'warm-status', 'durable-transaction-read'].map(operation => ({operation,
      mode: 'prepared', samples: samples(operation === 'durable-transaction-read' ? durableMs : queryMs,
        operation === 'warm-status' ? {status: 'succeeded', revision: 0} : [{id: 1}])}))]};
}

export function syntheticResultStorageControl(baseline, ms = 4) {
  const groups = ['clock', 'start', 'end'];
  const protocol = {binding: 'node:sqlite DatabaseSync', concurrency: 1,
    preparation: 'prepared statements; fresh identities/envelopes inside each timed sample',
    groups: ['durable clock acceptance', 'atomic start before payload', 'atomic terminal after payload'],
    keyWidths: {namespaceId: 5, authorityScopeCid: 71, runDefinitionCid: 71,
      principalId: 4, purpose: 8, resultName: 4, attemptId: 36},
    bodyBytes: {grant: 1009, attempt: 740, streaming: 374, receipt: 963,
      terminalSucceeded: 657, totalCanonicalBusinessBytes: 3743, clock: 217, outputJsonlBytes: 9},
    payload: '{"id":1}\n', expected: [{id: 1}], coverage: 'Storage only; excludes Account/typed/cryptographic/new Run work'};
  return {schemaVersion: 1, kind: 'local-sqlite-result-control', synthetic: true, productAcceptance: false,
    environment: baseline.environment, load: baseline.load, executableSha256: baseline.executableSha256,
    collectorSha256: '7'.repeat(64), settings: baseline.settings, profiled: false, cleanup: {closed: true},
    ownerMapping: {source: '6'.repeat(40), sha256: '5'.repeat(64), groups: groups.map(id => ({id}))},
    protocol, protocolSha256: hash(protocol), warmSamples: 100,
    samples: Array.from({length: 100}, (_, index) => ({index, pid: 1, wallNs: ms * 1e6,
      userUs: 1, systemUs: 1, verified: true, outputSha256: hash([{id: 1}]), attemptCid: 'sha256:' + hash(index),
      phases: {fixtureConstructionNs: 1, payloadAndMaterializeNs: 1,
        ...Object.fromEntries(groups.map(key => [key, {totalNs: 2, commitNs: 1}]))},
      events: ['clock-committed', 'start-committed', 'payload-materialized', 'end-committed'],
      counts: {begins: 3, commits: 3, rollbacks: 0, reads: 3, writes: 8}}))};
}
