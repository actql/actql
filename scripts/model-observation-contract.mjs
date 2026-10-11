import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {machineCid} from './actql-spec-family.mjs';

const protocolPath = 'spec/contracts/actql-protocol-schemas.json';
const manifestPath = 'spec/spec-family.json';
const read = path => JSON.parse(readFileSync(path, 'utf8'));
const cid = {type: 'string', pattern: '^sha256:[0-9a-f]{64}$'};
const nullable = schema => ({oneOf: [structuredClone(schema), {type: 'null'}]});

// The historical descriptors remain registered unchanged. The generated
// compatibility roots discriminate versions instead of repairing old bodies.
export function modelObservationSchemas(artifacts) {
  const historical = artifacts.model_invocation_evidence;
  const evidence = structuredClone(historical);
  evidence.$id = 'https://smooth.dev/schemas/actql-model-invocation-evidence-0.2.json';
  evidence.title = 'actql-model-invocation-evidence-0.2';
  evidence.properties.version = {const: 'actql-model-invocation-evidence/0.2'};
  for (const field of ['provider_reported_model_id', 'provider_reported_revision',
    'provider_request_id', 'input_tokens', 'output_tokens']) {
    evidence.properties[field] = nullable(historical.properties[field]);
  }
  // A raw provider finish reason is distinct from the historical writer's
  // fixed stop assertion. Completeness comes from the selected checked profile.
  evidence.properties.finish_reason = nullable({type: 'string', minLength: 1,
    maxLength: 256});
  evidence.properties.gateway_request_id = nullable({type: 'string', minLength: 1,
    maxLength: 1024});
  evidence.properties.raw_response_artifact_cid = nullable(cid);
  evidence.properties.response_profile_cid = structuredClone(cid);
  evidence.properties.response_complete = {const: true};
  // Pure opaque observed data under the existing byte/node/depth envelope.
  // Null means unobserved; an empty object means an observed empty object.
  // No metadata entry grants authority, completeness, precision or retry.
  evidence.properties.provider_metadata = nullable({type: 'object'});
  for (const field of ['provider_reported_revision', 'gateway_request_id',
    'raw_response_artifact_cid', 'response_profile_cid', 'response_complete',
    'provider_metadata']) {
    if (!evidence.required.includes(field)) evidence.required.push(field);
  }
  const bundle = structuredClone(artifacts.model_capture_bundle);
  bundle.$id = 'https://smooth.dev/schemas/actql-model-capture-bundle-0.2.json';
  bundle.title = 'actql-model-capture-bundle-0.2';
  bundle.properties.version = {const: 'actql-model-capture-bundle/0.2'};
  const embedded = structuredClone(evidence);
  delete embedded.$schema;
  delete embedded.$id;
  delete embedded.title;
  bundle.properties.captures.items.properties.evidence = embedded;
  return {
    model_invocation_evidence_v02: evidence,
    model_capture_bundle_v02: bundle,
    model_invocation_evidence_compatible: {oneOf: [
      structuredClone(historical), structuredClone(evidence),
    ]},
    model_capture_bundle_compatible: {oneOf: [
      structuredClone(artifacts.model_capture_bundle), structuredClone(bundle),
    ]},
  };
}

export function checkModelObservationSchemas(registry) {
  for (const [name, value] of Object.entries(
    modelObservationSchemas(registry.artifact_schemas))) {
    assert.deepEqual(registry.artifact_schemas[name], value, name);
    assert.equal(registry.artifact_schema_cids[name], machineCid(value), name);
  }
  assert.equal(registry.artifact_registry_cid,
    machineCid(registry.artifact_schemas));
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const registry = read(protocolPath);
  if (process.argv.includes('--write')) {
    const manifest = read(manifestPath);
    const owner = manifest.documents.find(item => item.document_id === 'contracts');
    assert.ok(owner);
    let source = readFileSync(owner.path, 'utf8');
    const anchor = source.split('\n').find(line => line.startsWith(
      '../../../spec/contracts/actql-protocol-schemas.json#/schemas/model_task '));
    assert.ok(anchor);
    const additions = [];
    for (const [name, value] of Object.entries(
      modelObservationSchemas(registry.artifact_schemas))) {
      const pointer = `/artifact_schemas/${name}`;
      const pin = machineCid(value);
      registry.artifact_schemas[name] = value;
      registry.artifact_schema_cids[name] = pin;
      const reference = owner.machine_contracts.find(item =>
        item.path === protocolPath && item.pointer === pointer);
      if (reference) {
        source = source.replace(`../../../${protocolPath}#${pointer} ${reference.cid}`,
          `../../../${protocolPath}#${pointer} ${pin}`);
        reference.cid = pin;
      } else {
        owner.machine_contracts.push({path: protocolPath, pointer, cid: pin,
          version: registry.version});
        additions.push(`../../../${protocolPath}#${pointer} ${pin}`);
      }
    }
    registry.artifact_registry_cid = machineCid(registry.artifact_schemas);
    if (additions.length) source = source.replace(anchor,
      anchor + '\n' + additions.join('\n'));
    writeFileSync(protocolPath, JSON.stringify(registry, null, 2) + '\n');
    writeFileSync(manifestPath, JSON.stringify(manifest, null, 2) + '\n');
    writeFileSync(owner.path, source);
  }
  checkModelObservationSchemas(registry);
}
