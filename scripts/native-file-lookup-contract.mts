import assert from 'node:assert/strict';
import type {ProtocolSchema} from './interactive-run-control-schema.mjs';

// Narrow the registered INPUT shape to the fields this specialization owns.
type Kind = {enum?: string[]; const?: string};
type TransportProperties = {
  version: {const: string};
  batching: {properties: {kind: Kind; max_keys_per_batch: ProtocolSchema}};
  pagination: {properties: {
    kind: Kind;
    token_contract: {anyOf?: ProtocolSchema[]; type?: 'null'};
    max_pages_per_batch: ProtocolSchema;
  }};
  retry: {properties: {
    max_network_attempts_per_request: ProtocolSchema;
    retryable_error_codes: ProtocolSchema;
  }};
};
type LookupTransportRegistry = {schemas: {transport_plan: {
  properties: TransportProperties;
  $defs?: Record<string, ProtocolSchema>;
}}};

// Descriptor specialization for the actual existing Native file reader. The
// full transport schema and HTTP/cursor/native-batching capabilities stay
// unchanged. No generic recursive token grammar or default retry is added.
export function nativeFileLookupTransportSchema(registry: LookupTransportRegistry) {
  const schema = structuredClone(registry.schemas.transport_plan);
  assert.equal(schema.properties.version.const, 'actql-lookup-transport-plan/0.1');
  const {batching, pagination, retry} = schema.properties;
  assert.ok(batching.properties.kind.enum!.includes('single'));
  assert.ok(pagination.properties.kind.enum!.includes('none'));
  assert.ok(pagination.properties.token_contract.anyOf!.some(x => x.type === 'null'));
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
