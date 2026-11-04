// Projection controls only: admission is stubbed here. The real private-Result
// capture/apply/restart counter is exercised by Sheets' existing Host fixture.
import assert from 'node:assert/strict';
import test from 'node:test';
import * as common from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from './runtime-core.mjs';
const cid = `sha256:${'a'.repeat(64)}`;
function fixture() {
  const limits = Object.freeze({maxWireBytes: 1048576, maxNodes: 65536, maxDepth: 64});
  const moon = {
    ...common,
    strategyPublicationAdmit: (name, wire, maxWireBytes, maxNodes, maxDepth) => {
      assert.deepEqual({maxWireBytes, maxNodes, maxDepth}, limits);
      return {$tag: 1, _0: {name, wire}};
    },
    strategyPublicationContractName: value => value.name,
    strategyPublicationContractIdentityField: () => 'captured_run_cid',
    strategyPublicationContractIdentity: () => cid,
    strategyPublicationContractJson: value => value.wire,
  };
  const control = runtimeCore(moon).publicationControl;
  const capture = (inventory, name = 'captured_run') => control.admit(name,
    JSON.stringify({effect_context: {effect_dependency_inventory: inventory}}), limits);
  return {control, capture};
}

test('captured Effect schema projection preserves original bodies and separates physical payloads', () => {
  const {control, capture} = fixture();
  const body = {'line\r\n': {type: 'string', nullable: false},
    rows: {type: 'array', nullable: false, max_items: 2,
      items: {type: 'object', nullable: false, additional_properties: false,
        fields: {'e\u0301': {type: 'boolean', nullable: false}}}}};
  const captured = capture([{kind: 'result_artifact', cid},
    {kind: 'relation_schema', cid, body}]);
  const schemas = control.capturedEffectDependencySchemas(captured);
  assert.deepEqual(schemas, [{cid, wire: JSON.stringify(body)}]);
  assert(Object.isFrozen(schemas)); assert(Object.isFrozen(schemas[0]));
  assert.deepEqual(control.capturedEffectDependencySchemas(capture([])), []);
  assert.throws(() => control.capturedEffectDependencySchemas({...captured}), /Foreign publication contract/);
});

test('captured Effect schema projection refuses missing foreign or malformed inventory', () => {
  const {control, capture} = fixture();
  for (const inventory of [undefined, {}, [{kind: 'relation_schema', cid: 'invalid', body: {}}],
    [{kind: 'relation_schema', cid, body: null}], [{kind: 'relation_schema', cid, body: []}],
    Array.from({length: 4097}, () => ({kind: 'result_artifact', cid}))]) {
    assert.throws(() => control.capturedEffectDependencySchemas(capture(inventory)),
      /InvalidEffectDependencySchemas/);
  }
  assert.throws(() => control.capturedEffectDependencySchemas(capture([], 'run_receipt')),
    /InvalidEffectDependencySchemas/);
});
