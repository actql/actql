import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {nativeFileLookupTransportSchema} from './native-file-lookup-contract.mjs';

test('Native transport specialization preserves the full registry and narrows only actual implementation choices', () => {
  const registry = JSON.parse(readFileSync('spec/contracts/actql-lookup-identities.json', 'utf8'));
  const original = structuredClone(registry);
  const schema = nativeFileLookupTransportSchema(registry);
  assert.deepEqual(registry, original);
  const {batching, pagination, retry} = schema.properties;
  assert.deepEqual(batching.properties.kind, {const: 'single'});
  assert.deepEqual(batching.properties.max_keys_per_batch, {const: 1});
  assert.deepEqual(pagination.properties.kind, {const: 'none'});
  assert.deepEqual(pagination.properties.token_contract, {type: 'null'});
  assert.deepEqual(pagination.properties.max_pages_per_batch, {const: 1});
  assert.deepEqual(retry.properties.max_network_attempts_per_request, {const: 1});
  assert.equal(retry.properties.retryable_error_codes.maxItems, 0);
  // Restore exactly these choices and the unchanged generic recursive token definitions.
  batching.properties = original.schemas.transport_plan.properties.batching.properties;
  pagination.properties = original.schemas.transport_plan.properties.pagination.properties;
  retry.properties = original.schemas.transport_plan.properties.retry.properties;
  schema.$defs = original.schemas.transport_plan.$defs;
  assert.deepEqual(schema, original.schemas.transport_plan);
});
