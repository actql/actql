import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {canonicalText} from './check-canonical-json.mjs';
import {graphCheckSourceProfile, releaseGraphCheckFixturePaths}
  from './release-graph-argument-check-cases.mjs';

const environment = JSON.parse(readFileSync(new URL(
  '../adapters/host-node/fixtures/query-amount-environment.json', import.meta.url)));
const database = '/test/graph-check/records.duckdb';

test('Graph CHECK denied and absent profiles retain the same original environment and denial', () => {
  const before = structuredClone(environment);
  const denied = graphCheckSourceProfile(environment, database, 'denied');
  const absent = graphCheckSourceProfile(environment, database, 'absent');
  assert.deepEqual(environment, before);
  assert.equal(denied.checkEnvironmentWire, canonicalText(before));
  assert.equal(absent.checkEnvironmentWire, denied.checkEnvironmentWire);
  assert.equal(denied.database, database);
  assert.deepEqual(denied.queryAliases, [{name: 'records',
    sourceRef: before.schema_snapshots[0].source_ref,
    sourceViewContractCid: before.source_views[0].contract_cid,
    schemaContractCid: before.source_views[0].output.schema.cid}]);
  assert.deepEqual(absent, {...denied, queryAliases: []});
  const account = JSON.parse(denied.accountConfigurationWire);
  assert.equal(account.entries.length, 1);
  assert.equal(account.entries[0].outcome, 'deny');
  assert.deepEqual(account.entries[0].operation, {any_of: ['read']});
});

test('Graph CHECK fixture selection refuses invented modes and unbound Source identities', () => {
  for (const mode of ['allow', 'remote', '', undefined]) {
    assert.throws(() => graphCheckSourceProfile(environment, database, mode));
  }
  assert.throws(() => graphCheckSourceProfile(environment, 'relative.duckdb', 'denied'));
  for (const mutate of [
    value => { value.source_views = []; },
    value => { value.schema_snapshots.push(value.schema_snapshots[0]); },
    value => { value.schema_snapshots[0].source_view_contract_cid = 'different'; },
    value => { value.schema_snapshots[0].carrier_schema_contract_cid = 'different'; },
  ]) {
    const value = structuredClone(environment); mutate(value);
    assert.throws(() => graphCheckSourceProfile(value, database, 'denied'));
  }
});

test('Graph CHECK consumer copies test fixtures and original metadata, never a product overlay', () => {
  assert.equal(new Set(releaseGraphCheckFixturePaths).size, releaseGraphCheckFixturePaths.length);
  assert.ok(releaseGraphCheckFixturePaths.includes('scripts/fixtures/graph-argument-check.mjs'));
  assert.ok(releaseGraphCheckFixturePaths.includes('scripts/fixtures/graph-argument-origin-literals.json'));
  for (const path of releaseGraphCheckFixturePaths) {
    assert.ok(path.startsWith('scripts/') ||
      path === 'adapters/host-node/fixtures/query-amount-environment.json');
    assert.equal(path.includes('node_modules'), false);
    assert.equal(path.includes('_build'), false);
    assert.ok(readFileSync(new URL('../' + path, import.meta.url)).length > 0);
  }
});
