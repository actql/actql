import assert from 'node:assert/strict';

// Descriptor specialization for the actual existing Native file reader. The
// full transport schema and HTTP/cursor/native-batching capabilities stay
// unchanged. No generic recursive token grammar or default retry is added.
export function nativeFileLookupTransportSchema(registry) {
  const schema = structuredClone(registry.schemas.transport_plan);
  assert.equal(schema.properties.version.const, 'actql-lookup-transport-plan/0.1');
  const {batching, pagination, retry} = schema.properties;
  assert.ok(batching.properties.kind.enum.includes('single'));
  assert.ok(pagination.properties.kind.enum.includes('none'));
  assert.ok(pagination.properties.token_contract.anyOf.some(x => x.type === 'null'));
  batching.properties.kind = {const: 'single'};
  batching.properties.max_keys_per_batch = {const: 1};
  pagination.properties.kind = {const: 'none'};
  pagination.properties.token_contract = {type: 'null'};
  pagination.properties.max_pages_per_batch = {const: 1};
  retry.properties.max_network_attempts_per_request = {const: 1};
  retry.properties.retryable_error_codes.maxItems = 0;
  delete schema.$defs;
  return schema;
}

