import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {machineCid} from './actql-spec-family.mjs';

export const modelRetryOrder = Object.freeze([
  'rate_limit', 'timeout', 'provider_error',
]);
const cid = {type: 'string', pattern: '^sha256:[0-9a-f]{64}$'};
const nonnegative = {type: 'integer', minimum: 0,
  maximum: Number.MAX_SAFE_INTEGER};
const envelope = (version, field, value) => ({
  $schema: 'https://json-schema.org/draft/2020-12/schema',
  type: 'object', additionalProperties: false,
  required: ['version', field, 'self_cid'],
  properties: {version: {const: version}, [field]: value, self_cid: cid},
});

export function modelDependencySchemas() {
  return {
    model_prompt: envelope('actql-model-prompt/0.1', 'payload', {}),
    model_retry_policy: envelope('actql-model-retry-policy/0.1',
      'retryable_failures', {type: 'array', uniqueItems: true, maxItems: 3,
        items: {enum: [...modelRetryOrder]}}),
    model_backoff: envelope('actql-model-backoff/0.1', 'delays_ms',
      {type: 'array', items: nonnegative}),
  };
}

export function checkModelDependencySchemas(registry) {
  for (const [kind, schema] of Object.entries(modelDependencySchemas())) {
    assert.deepEqual(registry.artifact_schemas[kind], schema);
    assert.equal(registry.artifact_schema_cids[kind], machineCid(schema));
  }
  assert.equal(registry.artifact_registry_cid, machineCid(registry.artifact_schemas));
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const path = 'spec/contracts/actql-protocol-schemas.json';
  const registry = JSON.parse(readFileSync(path, 'utf8'));
  if (process.argv.includes('--write')) {
    const manifestPath = 'spec/spec-family.json';
    const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));
    const owner = manifest.documents.find(item => item.document_id === 'contracts');
    assert.ok(owner);
    let source = readFileSync(owner.path, 'utf8');
    const anchor = source.split('\n').find(line => line.startsWith(
      '../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/model_call_slot '));
    assert.ok(anchor);
    const additions = [];
    for (const [kind, schema] of Object.entries(modelDependencySchemas())) {
      const pointer = `/artifact_schemas/${kind}`;
      const pin = machineCid(schema);
      registry.artifact_schemas[kind] = schema;
      registry.artifact_schema_cids[kind] = pin;
      const reference = owner.machine_contracts.find(item =>
        item.path === path && item.pointer === pointer);
      if (reference) {
        source = source.replace(`../../../${path}#${pointer} ${reference.cid}`,
          `../../../${path}#${pointer} ${pin}`);
        reference.cid = pin;
      } else {
        owner.machine_contracts.push({path, pointer, cid: pin,
          version: registry.version});
        additions.push(`../../../${path}#${pointer} ${pin}`);
      }
    }
    registry.artifact_registry_cid = machineCid(registry.artifact_schemas);
    if (additions.length) source = source.replace(anchor,
      anchor + '\n' + additions.join('\n'));
    writeFileSync(path, JSON.stringify(registry, null, 2) + '\n');
    writeFileSync(owner.path, source);
    writeFileSync(manifestPath, JSON.stringify(manifest, null, 2) + '\n');
  }
  checkModelDependencySchemas(registry);
}
