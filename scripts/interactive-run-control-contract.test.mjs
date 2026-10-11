import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import test from 'node:test';
import {buildControlRegistry, controlRegistryPath, logicalOperators} from './interactive-run-control-contract.mjs';
import {canonicalText, verifyIdentity} from './check-canonical-json.mjs';
import * as wire from '../packages/client-wire/interactive-control.generated.js';
import {validRunStateShape} from '../packages/client-wire/client-host.generated.js';
import {identityVectors, shapeVectors, negativeVectors, legacyState, profile,
  command, cid, bindingVectors} from './fixtures/interactive-run-control-vectors.mjs';

const schemaName = name => 'validWire' + name.split('_')
  .map(part => part[0].toUpperCase() + part.slice(1)).join('') + 'Shape';
const hash = body => `sha256:${createHash('sha256').update(canonicalText(body)).digest('hex')}`;

test('interactive registry is generated, pinned, closed and grants no runtime support', () => {
  const registry = JSON.parse(readFileSync(controlRegistryPath, 'utf8'));
  assert.deepEqual(registry, buildControlRegistry());
  assert.ok(registry.errors.includes('ControlRevisionExhausted'));
  for (const domain of Object.values(registry.identity_domains)) {
    assert.equal(domain.identity_field, 'self_cid');
    assert.equal(domain.preimage, 'complete_body_except_self_cid');
    assert.match(domain.version, /^actql-[a-z-]+\/0\.1$/u);
  }
  const checker = readFileSync('src/pipeline_typing/check.mbt', 'utf8');
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

test('legacy consumer and original RunState schema remain unchanged', () => {
  const registry = JSON.parse(readFileSync('spec/contracts/actql-protocol-schemas.json', 'utf8'));
  assert.equal(registry.artifact_schema_cids.run_state,
    'sha256:70dc077a89465b8785fcc66fe471133e52004fc1dcc105df0efc7ac559c3fe30');
  assert.equal(hash(registry.artifact_schemas.run_state), registry.artifact_schema_cids.run_state);
  assert.equal(registry.registry_cid,
    'sha256:9733edd2e52626c724b1fa00ee705c4b82b57bec07c23de128d7c95ceedd9c46');
  assert.equal(registry.artifact_registry_cid,
    'sha256:d19722c3db238fad39d5b1e3b85ed6c88ae4bc18a946bbad7b74647075cd9491');
  assert.ok(validRunStateShape(legacyState));
  assert.equal(validRunStateShape({...legacyState, status: 'paused'}), false);
  assert.equal(validRunStateShape({...legacyState, previous_stop_reason: 'entry'}), false);
  assert.equal(wire.validWireControlCommandShape({...command, self_cid: cid('1'),
    operation: 'pause'}), false);
});
