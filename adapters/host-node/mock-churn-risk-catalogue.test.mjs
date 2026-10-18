import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import test from 'node:test';
import {mockChurnRiskCatalogue} from './mock-churn-risk-catalogue.mjs';

const canonical = value => value === null || typeof value !== 'object'
  ? JSON.stringify(value)
  : Array.isArray(value) ? '[' + value.map(canonical).join(',') + ']'
    : '{' + Object.keys(value).sort().map(key => JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}';

test('bundled mock catalogue declares the original two sources independently of rows and Task', () => {
  assert.deepEqual(mockChurnRiskCatalogue.map(entry => [entry.connection,
    entry.connectorId, entry.registration, entry.revision, entry.queryAliases]), [
    ['salesforce', 'salesforce', 'mock_salesforce', 'mock_salesforce/0.1',
      [{name: 'salesforce.accounts', resource: 'Account'}]],
    ['snowflake', 'snowflake', 'mock_snowflake', 'mock_snowflake/0.1',
      [{name: 'snowflake.usage_30d', resource: 'usage_30d'}]],
  ]);
  assert.deepEqual(mockChurnRiskCatalogue.map(entry => entry.updateAliases), [
    [{name: 'salesforce.Account', resource: 'Account'}], [],
  ]);
  const [salesforce, snowflake] = mockChurnRiskCatalogue.map(entry => entry.views[0]);
  assert.deepEqual(JSON.parse(salesforce.schema_wire), {
    id: {type: 'string', nullable: false},
    name: {type: 'string', nullable: false},
    description: {type: 'string', nullable: false},
    Churn_Risk__c: {type: 'string', nullable: false},
    Risk_Reason__c: {type: 'string', nullable: true},
  });
  assert.deepEqual(JSON.parse(snowflake.schema_wire), {
    account_id: {type: 'string', nullable: false},
    active_users: {type: 'int64', nullable: false},
    trend: {type: 'string', nullable: false},
  });
  assert.deepEqual(JSON.parse(salesforce.facts_wire),
    {relation_keys: {candidate_keys: [['id']]}});
  assert.deepEqual(JSON.parse(snowflake.facts_wire),
    {relation_keys: {candidate_keys: [['account_id']]}});
  for (const entry of mockChurnRiskCatalogue) {
    assert.equal(entry.views.length, 1);
    const view = entry.views[0];
    assert.deepEqual(Object.keys(view).sort(),
      ['resource', 'resource_kind', 'schema_wire', 'schema_cid', 'facts_wire'].sort());
    assert.equal(canonical(JSON.parse(view.schema_wire)), view.schema_wire);
    assert.equal('sha256:' + createHash('sha256').update(view.schema_wire).digest('hex'), view.schema_cid);
  }
});

test('bundled mock declarations cannot be mutated into a different selected contract', () => {
  assert.throws(() => mockChurnRiskCatalogue.push({}), TypeError);
  for (const entry of mockChurnRiskCatalogue) {
    assert.throws(() => {entry.connectorId = 'foreign';}, TypeError);
    assert.throws(() => entry.queryAliases.push({}), TypeError);
    assert.throws(() => entry.updateAliases.push({}), TypeError);
    for (const alias of entry.updateAliases) {
      assert.throws(() => {alias.resource = 'foreign';}, TypeError);
    }
    assert.throws(() => {entry.queryAliases[0].resource = 'foreign';}, TypeError);
    assert.throws(() => entry.views.push({}), TypeError);
    assert.throws(() => {entry.views[0].facts_wire = '{}';}, TypeError);
    assert.throws(() => {entry.views[0].schema_wire = '{}';}, TypeError);
  }
});
