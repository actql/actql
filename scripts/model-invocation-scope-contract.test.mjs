import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {createPublicKey, verify} from 'node:crypto';
import {machineCid} from './actql-spec-family.mjs';
import {verifyIdentity} from './check-canonical-json.mjs';
import {checkModelInvocationScopeSchemas} from './model-invocation-scope-contract.mjs';
import {checkModelAttemptEvidenceSchemas} from './model-attempt-evidence-contract.mjs';

const read = path => JSON.parse(readFileSync(path, 'utf8'));
const corpus = read('portability/corpus/model-invocation-scope.json');
const registry = read('spec/contracts/actql-protocol-schemas.json');
const originals = Object.fromEntries(corpus.cases.map(c => [c.kind, c.artifact]));
const without = (object, ...fields) => Object.fromEntries(
  Object.entries(object).filter(([key]) => !fields.includes(key)));
const isCid = value => typeof value === 'string' && /^sha256:[0-9a-f]{64}$/u.test(value);
const text = value => typeof value === 'string' && value.length > 0;
const keys = (value, names) => value !== null && typeof value === 'object' &&
  !Array.isArray(value) && names.length === Object.keys(value).length &&
  names.every(name => Object.hasOwn(value, name));

// Bounded JSON Schema oracle for these fixtures. Unknown keywords fail the
// test rather than silently weakening a registered contract.
function acceptsSchema(value, schema) {
  const known = new Set(['$schema', '$id', 'title', 'description', 'type',
    'const', 'enum', 'allOf', 'oneOf', 'anyOf', 'not', 'if', 'then', 'else',
    'properties', 'required', 'additionalProperties', 'items', 'uniqueItems',
    'minItems', 'maxItems', 'minimum', 'maximum', 'minLength', 'pattern', 'format']);
  for (const key of Object.keys(schema)) assert.ok(known.has(key), key);
  const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
  if ('const' in schema && !same(value, schema.const)) return false;
  if (schema.enum && !schema.enum.some(item => same(value, item))) return false;
  if (schema.allOf && !schema.allOf.every(item => acceptsSchema(value, item))) return false;
  if (schema.oneOf && schema.oneOf.filter(item => acceptsSchema(value, item)).length !== 1) return false;
  if (schema.anyOf && !schema.anyOf.some(item => acceptsSchema(value, item))) return false;
  if (schema.not && acceptsSchema(value, schema.not)) return false;
  if (schema.if && !acceptsSchema(value,
    acceptsSchema(value, schema.if) ? schema.then ?? {} : schema.else ?? {})) return false;
  const object = value !== null && typeof value === 'object' && !Array.isArray(value);
  if (schema.type && !({object, array: Array.isArray(value),
    integer: Number.isSafeInteger(value), string: typeof value === 'string',
    boolean: typeof value === 'boolean', null: value === null})[schema.type]) return false;
  if (typeof value === 'number' &&
      (value < (schema.minimum ?? -Infinity) || value > (schema.maximum ?? Infinity))) return false;
  if (typeof value === 'string' && (value.length < (schema.minLength ?? 0) ||
      schema.pattern && !new RegExp(schema.pattern, 'u').test(value))) return false;
  if (schema.format) {
    assert.equal(schema.format, 'date-time');
    if (typeof value !== 'string' || !Number.isFinite(Date.parse(value))) return false;
  }
  if (Array.isArray(value)) {
    if (value.length < (schema.minItems ?? 0) || value.length > (schema.maxItems ?? Infinity)) return false;
    if (schema.uniqueItems && new Set(value.map(JSON.stringify)).size !== value.length) return false;
    if (schema.items && !value.every(item => acceptsSchema(item, schema.items))) return false;
  }
  if (object) {
    if (schema.required?.some(key => !Object.hasOwn(value, key))) return false;
    for (const [key, item] of Object.entries(value)) {
      const property = schema.properties?.[key];
      if (property && !acceptsSchema(item, property)) return false;
      if (!property && schema.additionalProperties === false) return false;
      if (!property && typeof schema.additionalProperties === 'object' &&
          !acceptsSchema(item, schema.additionalProperties)) return false;
    }
  }
  return true;
}

// Independent closed-shape oracle from the adopted prose, not generated from
// the schema or the Model/Host implementation under test.
function scopeShape(value) {
  return keys(value, ['version', 'run_definition_cid', 'task_index',
    'strategy_revision', 'inference_barrier_cid', 'input_artifact_cid',
    'model_call_slot_cids', 'provider_binding_cid', 'authorization_context', 'self_cid']) &&
    value.version === 'actql-model-invocation-scope/0.1' &&
    ['run_definition_cid', 'inference_barrier_cid', 'input_artifact_cid',
      'provider_binding_cid', 'self_cid'].every(key => isCid(value[key])) &&
    [value.task_index, value.strategy_revision].every(n => Number.isSafeInteger(n) && n >= 0) &&
    Array.isArray(value.model_call_slot_cids) && value.model_call_slot_cids.every(isCid) &&
    new Set(value.model_call_slot_cids).size === value.model_call_slot_cids.length &&
    keys(value.authorization_context, ['account_id', 'configuration_cid', 'entry_id',
      'principal', 'connection', 'resource', 'operation', 'boundary', 'context_cid']) &&
    ['account_id', 'entry_id', 'principal', 'connection', 'resource']
      .every(key => text(value.authorization_context[key])) &&
    ['configuration_cid', 'context_cid'].every(key => isCid(value.authorization_context[key])) &&
    value.authorization_context.operation === 'infer' &&
    value.authorization_context.boundary === 'activation';
}

test('registered scope and provider originals are closed, pinned and stable under regeneration', () => {
  checkModelInvocationScopeSchemas(registry);
  checkModelAttemptEvidenceSchemas(registry);
  for (const name of ['model_invocation_scope', 'model_provider_binding']) {
    const schema = registry.artifact_schemas[name];
    assert.equal(schema.additionalProperties, false);
    assert.deepEqual(schema.required.toSorted(), Object.keys(originals[name]).toSorted());
    assert.equal(registry.artifact_schema_cids[name], machineCid(schema));
  }
  assert.equal(scopeShape(originals.model_invocation_scope), true);
});

test('scope rejects duplicate calls, self-cycle, stale operation and open fields', () => {
  const scope = originals.model_invocation_scope;
  for (const invalid of [
    {...scope, model_call_slot_cids: [...scope.model_call_slot_cids, scope.model_call_slot_cids[0]]},
    {...scope, authorization_context: {...scope.authorization_context, subject_cid: scope.self_cid}},
    {...scope, authorization_context: {...scope.authorization_context, operation: 'read'}},
    {...scope, authorization_context: {...scope.authorization_context, boundary: 'acquisition'}},
    {...scope, fixed_request_cid: scope.self_cid},
    {...scope, prepared_invocation_cid: scope.self_cid},
    {...scope, task_index: -1}, {...scope, strategy_revision: 1.5},
    without(scope, 'provider_binding_cid'),
  ]) {
    assert.equal(scopeShape(invalid), false);
    assert.equal(acceptsSchema(invalid, registry.artifact_schemas.model_invocation_scope), false);
  }
  assert.equal(scopeShape({...scope, model_call_slot_cids: []}), true);
});

test('fixed wire originals pass registered schemas and cross-product mutations fail', () => {
  for (const c of corpus.cases) assert.equal(
    acceptsSchema(c.artifact, registry.artifact_schemas[c.kind]), true, c.kind);
  const checkpoint = originals.execution_checkpoint;
  for (const value of [
    {...checkpoint, phase: 'commit'},
    {...checkpoint, required_artifact: {...checkpoint.required_artifact, artifact_type: 'prepared_invocation'}},
    {...checkpoint, requirements: ['effect_scope_approved']},
    {...checkpoint, subject: {kind: 'prepare_attempt', prepare_attempt_id: 'p', continuation: 'start_run'}},
    {...checkpoint, kind: 'future_model_invocation'},
  ]) assert.equal(acceptsSchema(value, registry.artifact_schemas.execution_checkpoint), false);
  const provider = originals.model_provider_binding;
  assert.equal(acceptsSchema({...provider, credential_secret: 'synthetic-only'},
    registry.artifact_schemas.model_provider_binding), false);
  assert.equal(acceptsSchema({...provider, function_text: 'synthetic-only'},
    registry.artifact_schemas.model_provider_binding), false);
  const review = originals.run_review_projection;
  for (const field of ['model_invocation_scope_cid', 'model_call_slot_cids']) {
    assert.equal(acceptsSchema({...review, displayed_scope: without(review.displayed_scope, field)},
      registry.artifact_schemas.run_review_projection), false);
  }
});

test('fixed Python CIDs cover exact bodies and changed inventory identities', () => {
  for (const c of corpus.cases) {
    verifyIdentity(without(c.artifact, c.identity_field), c.expected_cid,
      c.expected_canonical_bytes);
    assert.equal(c.artifact[c.identity_field], c.expected_cid);
  }
  for (const c of corpus.identity_mutations) {
    verifyIdentity(c.body, c.expected_cid);
    assert.notEqual(c.expected_cid, originals.model_invocation_scope.self_cid, c.id);
  }
});

test('Model approval signature binds scope and actual PreparedInvocation separately', () => {
  const key = createPublicKey({format: 'der', type: 'spki', key: Buffer.concat([
    Buffer.from('302a300506032b6570032100', 'hex'), Buffer.from(corpus.public_key, 'base64')])});
  for (const [name, identity] of [['run_scope_approval', 'run_scope_approval_cid'],
    ['checkpoint_resolution', 'resolution_cid']]) {
    const original = originals[name];
    const unsigned = machineCid(without(original, identity, 'proof'));
    assert.ok(verify(null, Buffer.from(unsigned), key, Buffer.from(original.proof.signature, 'base64')));
    assert.equal(verify(null, Buffer.from(original[identity]), key,
      Buffer.from(original.proof.signature, 'base64')), false);
  }
  const scope = originals.model_invocation_scope;
  assert.equal(originals.checkpoint_resolution.required_artifact_cid, scope.self_cid);
  assert.equal(originals.run_scope_approval.prepared_invocation_cid,
    originals.run_review_projection.prepared_invocation_cid);
  assert.notEqual(originals.run_scope_approval.prepared_invocation_cid, scope.self_cid);
  assert.equal(originals.run_review_projection.displayed_scope.model_invocation_scope_cid, scope.self_cid);
  assert.deepEqual(originals.run_review_projection.displayed_scope.model_call_slot_cids, scope.model_call_slot_cids);
  const altered = {...originals.checkpoint_resolution,
    required_artifact_cid: corpus.identity_mutations[0].expected_cid};
  assert.equal(verify(null, Buffer.from(machineCid(without(altered, 'proof', 'resolution_cid'))),
    key, Buffer.from(altered.proof.signature, 'base64')), false);
});

test('Host verification signature binds exact Model approval and retained authorization evidence', () => {
  const wrapper = originals.verified_checkpoint_resolution;
  assert.deepEqual(wrapper.resolution, originals.checkpoint_resolution);
  assert.deepEqual(wrapper.approval_evidence, corpus.approval_evidence);
  verifyIdentity(wrapper.authorization_evidence, wrapper.authorization_evidence_cid);
  assert.equal(wrapper.authorization_context_cid,
    originals.model_invocation_scope.authorization_context.context_cid);
  const host = createPublicKey({format: 'der', type: 'spki', key: Buffer.concat([
    Buffer.from('302a300506032b6570032100', 'hex'), Buffer.from(corpus.host_public_key, 'base64')])});
  const unsigned = without(wrapper, 'host_attestation', 'verified_resolution_cid');
  assert.ok(verify(null, Buffer.from(machineCid(unsigned)), host,
    Buffer.from(wrapper.host_attestation.signature, 'base64')));
  assert.equal(verify(null, Buffer.from(machineCid({...unsigned,
    resolution: {...wrapper.resolution, required_artifact_cid: corpus.identity_mutations[0].expected_cid}})),
    host, Buffer.from(wrapper.host_attestation.signature, 'base64')), false);
});

test('historical authority remains byte-valid without manufacturing the optional send scope', () => {
  const historical = originals.model_dispatch_authority;
  assert.equal(Object.hasOwn(historical, 'model_invocation_scope_cid'), false);
  assert.equal(acceptsSchema(historical, registry.artifact_schemas.model_dispatch_authority), true);
  assert.notEqual(machineCid({...without(historical, 'self_cid'),
    model_invocation_scope_cid: originals.model_invocation_scope.self_cid}), historical.self_cid);
  assert.equal(historical.fixed_request_cid === originals.model_invocation_scope.self_cid, false);
});

test('new Checkpoint combination and approval/public-state unions remain explicit', () => {
  const checkpoint = registry.artifact_schemas.execution_checkpoint;
  const branch = checkpoint.oneOf.find(c => c.properties.kind.const === 'model_invocation').properties;
  assert.equal(checkpoint.oneOf.length, 6);
  assert.equal(branch.subject.properties.kind.const, 'run_unit');
  assert.equal(branch.phase.const, 'preflight');
  assert.equal(branch.required_artifact.properties.artifact_type.const, 'model_invocation_scope');
  assert.deepEqual(branch.requirements.const, ['invocation_scope_approved']);
  assert.ok(registry.artifact_schemas.run_state.properties.checkpoint.properties.kind.enum.includes('model_invocation'));
  assert.ok(registry.artifact_schemas.verified_checkpoint_resolution.properties.approval_evidence
    .oneOf[0].properties.kind.enum.includes('model_invocation'));
  const authority = registry.artifact_schemas.model_dispatch_authority;
  assert.ok(authority.properties.model_invocation_scope_cid);
  assert.equal(authority.required.includes('model_invocation_scope_cid'), false,
    'historical no-send originals keep their bytes');
});

test('per-call restart vectors specify saved, unknown and proven-unsent dispositions', () => {
  // A normative oracle only: this deliberately does not simulate a journal or
  // claim Host execution coverage. Actual owners must execute these cases.
  for (const c of corpus.recovery_cases) {
    const permit = c.approved && c.currentAuthority && c.currentProvider &&
      c.egress && !c.cancelled && !c.expired;
    const indices = state => c.states.flatMap((value, index) => value === state ? [index] : []);
    assert.deepEqual(c.sendable, permit ? indices('unsent') : [], c.id);
    assert.deepEqual(c.reuse, indices('response'), c.id);
    assert.deepEqual(c.unknown, indices('send_started'), c.id);
    assert.ok(c.sendable.every(index => !c.reuse.includes(index) && !c.unknown.includes(index)), c.id);
  }
  assert.deepEqual(corpus.single_call_counts, [0, 1, 1]);
  assert.deepEqual(corpus.recovery_cases.find(c => c.id === 'multi-restart').sendable, [2]);
});
