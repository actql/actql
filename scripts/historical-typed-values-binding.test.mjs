import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {selectInstalledHostEnvironment, selectInstalledLocalMaterializationEnvironment}
  from '../adapters/host-node/installed-host-policy.mjs';
import {contentCid} from '../adapters/host-node/local-account-config.mjs';

// Independent policy preimages for the historical recovery inputs. Exercise
// the actual selectors, without executing private snippets from a fixture or
// the Checkpoint service. Real held-request recovery tests admit the bindings.
const baseWire = readFileSync(new URL('../spec/local-check-environment.json', import.meta.url), 'utf8');
const {evidence_bundle_cid: ignored, ...base} = JSON.parse(baseWire); void ignored;
const genericCapacity = {max_graph_construction_edges: 1000,
  max_graph_construction_input_rows: 1000, max_graph_construction_nodes: 1000,
  ...base.host_policy_profile.capacity};
const localCapacity = {...genericCapacity, max_relation_output_rows: 536870912 / 256,
  max_artifact_rows: 536870912 / 256, max_file_listing_items: 536870912 / 256,
  max_model_request_bytes_per_item: 65536};
const wire = value => value === null || typeof value !== 'object' ? JSON.stringify(value)
  : Array.isArray(value) ? '[' + value.map(wire).join(',') + ']'
    : '{' + Object.keys(value).sort().map(key => JSON.stringify(key) + ':' + wire(value[key])).join(',') + '}';
const cid = value => 'sha256:' + createHash('sha256').update(wire(value)).digest('hex');
const environment = capacity => ({...structuredClone(base), host_policy_profile:
  {...structuredClone(base.host_policy_profile), capacity}});
const checkedEnvironment = selected => {
  const {evidence_bundle_cid: evidenceCid, ...body} = JSON.parse(selected);
  assert.equal(evidenceCid, cid(body), 'the selected Environment carries its actual canonical preimage');
  return body;
};
const admission = {clientProgramCheckEnvironment(selected, evidenceCid) {
  assert.equal(evidenceCid, cid(checkedEnvironment(selected)));
  return {};
}};
const localMoon = () => {
  const original = Object.freeze({});
  return {...admission, clientLocalResourcePolicyOriginal: () => original,
    clientLocalResourcePolicyRowCeiling(value) {assert.equal(value, original); return 536870912 / 256;},
    clientLocalResourcePolicyModelRequestByteCeiling(value) {assert.equal(value, original); return 65536n;}};
};

test('source-free Local selection retains the independent historical typed-value policy identities', () => {
  const expected = environment(localCapacity);
  const actual = checkedEnvironment(selectInstalledLocalMaterializationEnvironment(
    localMoon(), baseWire, undefined, undefined, undefined, true));
  assert.deepEqual(actual, expected);
  assert.equal(cid(expected), 'sha256:738a87cd0899ff9a3d27dee04de8ebb955d9d9c46b6eeba50c84697e8e1169bc');
  const beforeAnalyticCeilings = structuredClone(expected);
  for (const field of ['max_analytic_frame_memberships', 'max_analytic_input_wire_bytes',
    'max_analytic_output_wire_bytes', 'max_analytic_partition_wire_bytes']) {
    assert.equal(beforeAnalyticCeilings.host_policy_profile.capacity[field], 1000);
    delete beforeAnalyticCeilings.host_policy_profile.capacity[field];
  }
  assert.equal(cid(beforeAnalyticCeilings), 'sha256:cd9f929c74c3b55f40e94b9edf46e248f6c30e4fa970683e762e768fd5cc7470',
    'the previous policy retains its original identity rather than being relabeled');
  const previous = structuredClone(expected);
  delete previous.host_policy_profile.capacity.max_file_listing_items;
  const changed = structuredClone(expected);
  changed.host_policy_profile.capacity.max_artifact_rows--;
  const scope = 'sha256:' + 'b'.repeat(64);
  const binding = (environmentCid, authorityScopeCid = scope) => ({
    version: 'actql-remote-run-acceptance-environment/0.1', site_key: 'actql-remote-host',
    realization_key: 'source-free-values', environment_cid: environmentCid,
    authority_scope_cid: authorityScopeCid});
  assert.equal(contentCid(binding(contentCid(actual))), cid(binding(cid(expected))));
  for (const other of [previous, changed]) {
    assert.notEqual(contentCid(binding(contentCid(other))), cid(binding(cid(expected))),
      'a different original policy cannot be relabeled as the selected binding');
  }
  assert.notEqual(contentCid(binding(contentCid(actual), 'sha256:' + 'c'.repeat(64))),
    cid(binding(cid(expected))), 'the selected Environment cannot substitute another authority scope');
});

test('published Source and independent Effect selectors retain their generic declared policy', () => {
  // Salesforce installs a published Source profile, unlike source-free Values.
  // No Local resource-policy port is provided to this selector.
  assert.equal(selectInstalledHostEnvironment(admission, baseWire), baseWire);
  const actual = checkedEnvironment(selectInstalledHostEnvironment(admission, baseWire, genericCapacity));
  assert.deepEqual(actual, environment(genericCapacity));
  assert.equal(actual.host_policy_profile.capacity.max_artifact_rows, 1000);
  assert.equal(Object.hasOwn(actual.host_policy_profile.capacity, 'max_file_listing_items'), false);
  assert.notEqual(cid(actual), cid(environment(localCapacity)),
    'published generic policy is not the ordinary materialization Environment');
});

test('explicit Local selection preserves optional listing policy and its distinct original identity', () => {
  const explicit = {...genericCapacity, max_relation_output_rows: 31, max_artifact_rows: 17};
  delete explicit.max_file_listing_items;
  for (const original of [explicit, {...explicit, max_file_listing_items: 7}]) {
    const moon = localMoon();
    moon.clientLocalResourcePolicyModelRequestByteCeiling = () => {
      assert.fail('an explicit policy must not borrow the default Model window');
    };
    const actual = checkedEnvironment(selectInstalledLocalMaterializationEnvironment(
      moon, baseWire, original, undefined, undefined, true));
    assert.deepEqual(actual, environment(original));
    assert.notEqual(cid(actual), cid(environment(localCapacity)));
  }
  assert.deepEqual(JSON.parse(baseWire).host_policy_profile.capacity, base.host_policy_profile.capacity,
    'policy selection leaves the original Environment unchanged');
});
