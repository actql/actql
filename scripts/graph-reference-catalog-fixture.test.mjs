import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';

// Independent ASCII fixture oracle: no product canonicalizer, issuer or reader.
const canonical = value => Array.isArray(value)
  ? `[${value.map(canonical).join(',')}]`
  : value !== null && typeof value === 'object'
    ? `{${Object.keys(value).sort().map(key => `${JSON.stringify(key)}:${canonical(value[key])}`).join(',')}}`
    : JSON.stringify(value);
const identity = (value, field) => `sha256:${createHash('sha256')
  .update(canonical(Object.fromEntries(Object.entries(value).filter(([key]) => key !== field))))
  .digest('hex')}`;
const source = readFileSync(new URL('../src/query_integration/graph_reference_catalog_wbtest.mbt', import.meta.url), 'utf8');
const fixtures = [...source.matchAll(/^\s+("\{.*\}")\s*,?$/gm)]
  .map(match => JSON.parse(JSON.parse(match[1])));

test('current Graph reference Catalog fixture bodies and all dependent CIDs agree', () => {
  assert.equal(fixtures.length, 2);
  for (const environment of fixtures) {
    assert.equal(environment.evidence_bundle_cid, identity(environment, 'evidence_bundle_cid'));
    assert.ok(source.includes(`expected=${JSON.stringify(environment.evidence_bundle_cid)}`));
    for (const name of ['schema_snapshots', 'connector_capabilities', 'mapping_contracts',
      'source_views', 'command_contracts', 'model_task_contracts', 'contract_registry', 'connector_catalogs']) {
      // Evidence section ordering hashes the complete member, including its self CID.
      const members = environment[name].map(member => identity(member, undefined));
      assert.deepEqual(members, [...members].sort());
    }
    const contracts = new Map(environment.contract_registry.map(contract => [contract.id, contract]));
    for (const contract of contracts.values()) assert.equal(contract.cid, identity(contract, 'cid'));
    for (const catalog of environment.connector_catalogs) {
      assert.equal(catalog.catalog_cid, identity(catalog, 'catalog_cid'));
      assert.deepEqual(catalog.contracts.map(contract => contract.cid),
        catalog.contracts.map(contract => contract.cid).sort());
      for (const contract of catalog.contracts) assert.deepEqual(contract, contracts.get(contract.id));
      assert.deepEqual(catalog.source_views, environment.source_views);
    }
    for (const view of environment.source_views) {
      assert.equal(view.contract_cid, identity(view, 'contract_cid'));
      for (const ref of [view.acquisition.request_schema, view.output.schema,
        view.output.data_policy, view.output.facts, view.pushdown.contract]) {
        const contract = contracts.get(ref.id);
        assert.ok(contract);
        assert.equal(ref.cid, contract.cid);
        assert.equal(ref.version, contract.version);
      }
    }
  }
});

test('both Graph reference Catalog layouts retain their independent key/property types', () => {
  const [resourceKey, contentKey] = fixtures.map(environment => environment.contract_registry
    .find(contract => contract.id === 'fixture-1').body.fields);
  assert.deepEqual(resourceKey, {
    key: {nullable: false, resource_kind: 'Issue', type: 'resource_ref'},
    property: {media_type: 'text/plain', nullable: false, type: 'content_ref'},
  });
  assert.deepEqual(contentKey, {
    key: {media_type: 'text/plain', nullable: false, type: 'content_ref'},
    property: {nullable: false, resource_kind: 'Issue', type: 'resource_ref'},
  });
});
