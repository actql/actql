import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import test from 'node:test';
import {buildControlRegistry, controlRegistryPath, logicalOperators} from './interactive-run-control-contract.mjs';
import {canonicalText, verifyIdentity} from './check-canonical-json.mjs';
import * as wire from '../packages/client-wire/interactive-control.generated.js';
import {validRunStateShape} from '../packages/client-wire/client-host.generated.js';
import {identityVectors, shapeVectors, negativeVectors, legacyState, profile,
  command, cid, bindingVectors, running} from './fixtures/interactive-run-control-vectors.mjs';
import {explanationBody, explanationCid, explanationFacts, explanationLeakageVectors,
  runExplanation, unprojectedRunExplanation} from './fixtures/explanation-facts-vectors.mjs';

const schemaName = name => 'validWire' + name.split('_')
  .map(part => part[0].toUpperCase() + part.slice(1)).join('') + 'Shape';
const hash = body => `sha256:${createHash('sha256').update(canonicalText(body)).digest('hex')}`;

test('ExplanationFacts uses the existing complete-body identity domain and independent preimage', () => {
  verifyIdentity(explanationBody, explanationCid);
  assert.equal(wire.validWireExplanationFactsShape(explanationFacts), true);
  assert.deepEqual(buildControlRegistry().identity_domains.explanation_facts, {
    version: 'actql-explanation-facts/0.1', identity_field: 'self_cid',
    preimage: 'complete_body_except_self_cid', algorithm: 'sha256',
  });
  for (const field of ['compiled_plan_cid', 'logical_map_cid', 'program_definition_cid', 'parameter_values_cid']) {
    assert.notEqual(hash({...explanationBody, [field]: cid('9')}), explanationCid, field);
  }
  // A valid shape/self-CID is still not an original compiler or an access grant.
  assert.equal(wire.validWireExplanationFactsShape({...explanationFacts, self_cid: cid('9')}), true);
  assert.throws(() => verifyIdentity(explanationBody, cid('9')));
});

test('ExplanationFacts structural profile rejects literal metadata and permission fabrication', () => {
  for (const {field, value} of explanationLeakageVectors) {
    assert.equal(wire.validWireExplanationFactsShape(value), false, field);
  }
  const original = explanationFacts.steps[0].meaning.predicate.nodes[2];
  assert.deepEqual(original, {form: 'literal_redacted',
    type: {projection: 'shape_and_nullability', kind: 'number', nullable: false}});
});

test('ExplanationFacts preserves parameter names/types without bound values or length evidence', () => {
  const value = structuredClone(explanationFacts);
  value.steps[0].meaning.predicate.nodes[2] = {form: 'parameter', name: 'threshold',
    type: {projection: 'shape_and_nullability', kind: 'number', nullable: false}};
  assert.equal(wire.validWireExplanationFactsShape(value), true);
  value.steps[0].meaning.predicate.nodes[2].bound_value = 42;
  assert.equal(wire.validWireExplanationFactsShape(value), false);
});

test('ExplanationFacts missing retained original is explicit and cannot carry repaired facts', () => {
  assert.equal(wire.validWireRunExplanationViewShape(runExplanation), true);
  assert.equal(wire.validWireRunExplanationViewShape(unprojectedRunExplanation), true);
  for (const additional of [{facts: explanationFacts}, {compiled: true}, {rows: []}]) {
    assert.equal(wire.validWireRunExplanationViewShape({...unprojectedRunExplanation,
      explanation: {...unprojectedRunExplanation.explanation, ...additional}}), false);
  }
  assert.equal(wire.validWireRunExplanationViewShape({...unprojectedRunExplanation,
    explanation: {state: 'not_projected', reason: 'success'}}), false);
});

test('interactive registry is generated, pinned, closed and grants no runtime support', () => {
  const registry = JSON.parse(readFileSync(controlRegistryPath, 'utf8'));
  assert.deepEqual(registry, buildControlRegistry());
  assert.ok(registry.errors.includes('ControlRevisionExhausted'));
  for (const domain of Object.values(registry.identity_domains)) {
    assert.equal(domain.identity_field, 'self_cid');
    assert.equal(domain.preimage, 'complete_body_except_self_cid');
    assert.match(domain.version, /^actql-[a-z-]+\/0\.1$/u);
  }
  // The common checker's Steps phase delegates to this original operation owner.
  const checker = readFileSync('src/pipeline_typing/core_operation_read.mbt', 'utf8');
  for (const operator of logicalOperators)
    assert.ok(checker.includes(`"${operator}"`), operator);
  assert.equal(logicalOperators.includes('effect'), false);
});

test('independent canonical preimages distinguish input-only output and operation', () => {
  for (const vector of [...identityVectors, ...bindingVectors]) {
    verifyIdentity(vector.body, vector.cid);
    assert.ok(wire[schemaName(vector.name)]({...vector.body, self_cid: vector.cid}));
    assert.notEqual(hash({...vector.body, version: '<registered-version>'}), vector.cid);
  }
  assert.notEqual(identityVectors[2].cid, identityVectors[3].cid);
  assert.notEqual(hash({...command, operation_id: 'different'}), identityVectors[1].cid);
  assert.notEqual(hash({...profile, retain: {samples: {max_items: 1}}}), identityVectors[0].cid);
});

test('independent state, four Carrier and honest availability positives', () => {
  for (const {name, value} of shapeVectors)
    assert.ok(wire[schemaName(name)](value), name);
});

test('closed negative vectors reject revision drift, leakage and invented evidence', () => {
  for (const {name, value} of negativeVectors)
    assert.equal(wire[schemaName(name)](value), false, name);
});

test('pending flags preserve unknown absence independently of unsupported capability', () => {
  const states = shapeVectors.filter(vector => vector.name === 'controlled_run_state');
  for (const field of ['pause_pending', 'expiry_pending', 'cleanup_pending']) {
    const absent = states.find(vector => !Object.hasOwn(vector.value, field)).value;
    const before = structuredClone(absent);
    assert.equal(wire.validWireControlledRunStateShape(absent), true);
    assert.equal(Object.hasOwn(absent, field), false);
    assert.deepEqual(absent, before, 'validation must not synthesize false');
    for (const value of [false, true]) {
      assert.equal(wire.validWireControlledRunStateShape({...absent, [field]: value}), true);
    }
  }
  const schema = buildControlRegistry().schemas.controlled_run_state;
  for (const field of ['pause_pending', 'expiry_pending', 'cleanup_pending']) {
    assert.equal(schema.required.includes(field), false);
    assert.equal(schema.properties[field].type, 'boolean');
  }
});

test('legacy RunState identity and consumer remain unchanged as registries expand', () => {
  const registry = JSON.parse(readFileSync('spec/contracts/actql-protocol-schemas.json', 'utf8'));
  assert.equal(registry.artifact_schema_cids.run_state,
    'sha256:3fbfc2cc5a79449fd05fce58e0fad25f6eef0ecde8314a222417a2e233db28c2');
  assert.equal(hash(registry.artifact_schemas.run_state), registry.artifact_schema_cids.run_state);
  // Aggregate identities cover every current member. New Model/Plan contracts
  // may change them while the independent original RunState pin stays exact.
  assert.equal(registry.registry_cid, hash(registry.schemas));
  assert.equal(registry.artifact_registry_cid, hash(registry.artifact_schemas));
  assert.ok(validRunStateShape(legacyState));
  assert.equal(validRunStateShape({...legacyState, status: 'paused'}), false);
  assert.equal(validRunStateShape({...legacyState, previous_stop_reason: 'entry'}), false);
  assert.equal(wire.validWireControlCommandShape({...command, self_cid: cid('1'),
    operation: 'pause'}), false);
});

test('state observation revision is independently required and preserves legal zero', () => {
  assert.equal(legacyState.revision, 0);
  assert.equal(legacyState.control.revision, 17);
  assert.equal(running.control_revision, 17);
  assert.equal(wire.validWireControlledRunStateShape(running), true);
  assert.equal(wire.validWireControlledRunStateShape({...running,
    legacy_state: {...legacyState, revision: 1}}), true);
  const missing = Object.fromEntries(Object.entries(legacyState)
    .filter(([key]) => key !== 'revision'));
  assert.equal(validRunStateShape(missing), false);
  assert.equal(wire.validWireControlledRunStateShape({...running, legacy_state: missing}), false);
  for (const revision of [null, -1, 0.5, 9007199254740992]) {
    assert.equal(validRunStateShape({...legacyState, revision}), false);
    assert.equal(wire.validWireControlledRunStateShape({...running,
      legacy_state: {...legacyState, revision}}), false);
  }
  assert.equal(legacyState.revision, 0, 'validation cannot fill from control revision');
});
