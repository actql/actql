// Fixture installation only; the installed Host owns checking and disclosure.
import assert from 'node:assert/strict';
import {isAbsolute} from 'node:path';
import {canonicalText} from './check-canonical-json.mjs';

export const releaseGraphCheckFixturePaths = Object.freeze([
  'scripts/release-graph-argument-check-cases.mjs',
  'scripts/check-canonical-json.mjs',
  'scripts/fixtures/release-graph-argument-check-worker.mjs',
  'scripts/fixtures/graph-argument-check.mjs',
  'scripts/fixtures/graph-argument-origin-literals.json',
  'scripts/fixtures/two-source-public-query.mjs',
  'scripts/fixtures/public-query-input.mjs',
  'scripts/fixtures/packed-query-transport-owner.mjs',
  'adapters/host-node/fixtures/query-amount-environment.json',
]);

// Same declared Source and denied read account as the existing public CHECK
// harness. Omission removes only the published alias, not the normative input.
export function graphCheckSourceProfile(environment, database, name) {
  assert.ok(['absent', 'denied'].includes(name), 'Closed Graph CHECK installation');
  assert.ok(typeof database === 'string' && isAbsolute(database));
  assert.equal(environment.source_views.length, 1);
  assert.equal(environment.schema_snapshots.length, 1);
  const [view] = environment.source_views, [snapshot] = environment.schema_snapshots;
  assert.equal(snapshot.source_view_contract_cid, view.contract_cid);
  assert.equal(snapshot.carrier_schema_contract_cid, view.output.schema.cid);
  assert.equal(typeof snapshot.source_ref, 'string');
  return {
    version: 'actql-installed-duckdb-source/0.1', database,
    schema: 'main', table: 'records', sourceRef: snapshot.source_ref,
    acquisitionPlanning: {policy: 'priority', priority: ['nativeQuery', 'broadQuery']},
    queryAliases: name === 'absent' ? [] : [{name: 'records',
      sourceRef: snapshot.source_ref, sourceViewContractCid: view.contract_cid,
      schemaContractCid: view.output.schema.cid}],
    checkEnvironmentWire: canonicalText(environment),
    accountConfigurationWire: canonicalText({
      version: 'actql-execution-account-config/0.1', account_id: 'packed-query',
      entries: [{entry_id: 'read', outcome: 'deny', principal: {all: true},
        connection: {all: true}, resource: {all: true},
        operation: {any_of: ['read']}, exclusions: []}],
    }),
  };
}
