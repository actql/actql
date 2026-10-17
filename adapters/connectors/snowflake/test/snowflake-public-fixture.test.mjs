// Configuration preimages are independent test inputs, never an alternative
// Catalog/permission issuer. Actual Host conformance is tested separately.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import test from 'node:test';
import configuration from './snowflake-public-alias.fixture.json' with {type: 'json'};
import {metadataBody, pending, resultBody, decimal38} from './snowflake-response.fixture.mjs';

test('fixed operator alias retains independently hashed request/row/view preimages', () => {
  assert.equal(configuration.preimages.length, 6);
  const indexed = new Map();
  for (const entry of configuration.preimages) {
    assert(!indexed.has(entry.name));
    assert.equal('sha256:' + createHash('sha256').update(entry.canonicalPreimage).digest('hex'), entry.cid);
    assert(!Object.hasOwn(JSON.parse(entry.canonicalPreimage), entry.key));
    indexed.set(entry.name, entry);
  }
  assert.equal(configuration.alias.sourceRef, 'connector://snowflake/usage_30d#records');
  assert.equal(configuration.alias.schemaContractCid, indexed.get('row').cid);
  assert.equal(configuration.alias.sourceViewContractCid, indexed.get('view').cid);
  const view = JSON.parse(indexed.get('view').canonicalPreimage);
  assert.equal(view.output.schema.cid, indexed.get('row').cid);
  assert.equal(view.acquisition.request_schema.cid, indexed.get('request').cid);
  assert.equal(view.request_processing.mutates_business_state, false);
  assert.deepEqual(view.pushdown.operations, ['projection']);
});

test('shared response DATA preserves exact decimal38, SQL NULL and original statement identity', () => {
  assert.equal(JSON.parse(pending('original')).statementHandle, 'original');
  const value = JSON.parse(resultBody({handle: 'original'}));
  assert.equal(value.statementHandle, 'original');
  assert.equal(value.data[0][1], decimal38);
  assert.equal(typeof value.data[0][1], 'string');
  assert.equal(value.data[1][2], null);
  assert.equal(value.resultSetMetaData.rowType[1].precision, 38);
  const metadata = JSON.parse(metadataBody());
  assert.deepEqual(metadata.data.map(row => [row[3], row[6], row[7], row[8]]), [
    ['ACCOUNT_ID', 'TEXT', null, null], ['ACTIVE_USERS', 'NUMBER', '38', '0'],
    ['TREND', 'TEXT', null, null],
  ]);
});
