import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {compileFunction} from 'node:vm';
import test from 'node:test';
import {parse} from 'acorn';
import {selectInstalledLocalMaterializationEnvironment} from '../adapters/host-node/installed-host-policy.mjs';
import {contentCid} from '../adapters/host-node/local-account-config.mjs';

test('historical typed-value binding independently matches the same Local materialization environment', () => {
  const fixture = readFileSync(new URL('./fixtures/synthetic-historical-held-typed-values.mjs', import.meta.url), 'utf8');
  const host = readFileSync(new URL('../adapters/host-node/client-checkpoints.mjs', import.meta.url), 'utf8');
  const select = (source, predicate) => {
    const found = [];
    (function visit(node) {
      if (!node || typeof node !== 'object') return;
      if (predicate(node)) found.push(node);
      for (const value of Object.values(node)) {
        if (Array.isArray(value)) value.forEach(visit);
        else if (value && typeof value === 'object') visit(value);
      }
    })(parse(source, {ecmaVersion: 'latest', sourceType: 'module'}));
    assert.equal(found.length, 1);
    return source.slice(found[0].start, found[0].end);
  };
  const capacity = select(fixture, node => node.type === 'AssignmentExpression' &&
    node.left.property?.name === 'capacity' && node.left.object.property?.name === 'host_policy_profile' &&
    node.left.object.object?.name === 'environmentBody');
  const variable = (source, name) => select(source, node => node.type === 'VariableDeclarator' && node.id.name === name);
  const baseWire = readFileSync(new URL('../spec/local-check-environment.json', import.meta.url), 'utf8');
  const {evidence_bundle_cid: ignored, ...raw} = JSON.parse(baseWire); void ignored;
  const fixtureBody = compileFunction(capacity + '; return environmentBody;', ['environmentBody'])(structuredClone(raw));
  // Authored current-policy preimage, independent of the selected function's
  // output. Optional file listing uses the SAME 512MiB/256 nominal row ceiling.
  const expectedCapacity = {max_graph_construction_edges: 1000,
    max_graph_construction_input_rows: 1000, max_graph_construction_nodes: 1000,
    ...raw.host_policy_profile.capacity,
    max_relation_output_rows: 536870912 / 256,
    max_artifact_rows: 536870912 / 256,
    max_file_listing_items: 536870912 / 256,
    max_model_request_bytes_per_item: 65536};
  assert.deepEqual(fixtureBody.host_policy_profile.capacity, expectedCapacity);
  // Explicit component ports for the SAME fixed Local policy, not funding or
  // an executed CheckEnvironment/Core claim. These are the existing service windows.
  const original = Object.freeze({});
  const moon = {clientLocalResourcePolicyOriginal: () => original,
    clientLocalResourcePolicyRowCeiling(value) {assert.equal(value, original); return 536870912 / 256;},
    clientLocalResourcePolicyModelRequestByteCeiling(value) {assert.equal(value, original); return 65536n;},
    clientProgramCheckEnvironment: () => ({})};
  const {evidence_bundle_cid: selected, ...actualBody} = JSON.parse(
    selectInstalledLocalMaterializationEnvironment(moon, baseWire)); void selected;
  actualBody.host_policy_profile.capacity = {max_graph_construction_edges: 1000,
    max_graph_construction_input_rows: 1000, max_graph_construction_nodes: 1000, ...actualBody.host_policy_profile.capacity};
  const wire = value => value === null || typeof value !== 'object' ? JSON.stringify(value)
    : Array.isArray(value) ? '[' + value.map(wire).join(',') + ']'
      : '{' + Object.keys(value).sort().map(key => JSON.stringify(key) + ':' + wire(value[key])).join(',') + '}';
  const cid = value => 'sha256:' + createHash('sha256').update(wire(value)).digest('hex');
  assert.equal(cid(fixtureBody), 'sha256:cd9f929c74c3b55f40e94b9edf46e248f6c30e4fa970683e762e768fd5cc7470');
  const previousEnvironment = structuredClone(fixtureBody);
  delete previousEnvironment.host_policy_profile.capacity.max_file_listing_items;
  assert.notEqual(cid(previousEnvironment), cid(fixtureBody),
    'an original Environment without the optional policy keeps its distinct binding');
  const ownerPrincipal = 'fixture-owner', account = {account_id: 'fixture-account'}, configurationCid = 'sha256:' + 'a'.repeat(64);
  const siteKey = 'actql-remote-host', realizationKey = 'source-free-values', authorityScopeCid = 'sha256:' + 'b'.repeat(64);
  const fixtureBinding = compileFunction('const ' + variable(fixture, 'binding') + '; return binding;',
    ['environmentBody', 'cid', 'principalId', 'account', 'configurationCid', 'siteKey', 'realizationKey', 'authorityScopeCid']);
  const authored = fixtureBinding(
    fixtureBody, cid, ownerPrincipal, account, configurationCid, siteKey, realizationKey, authorityScopeCid);
  const current = compileFunction('const ' + variable(host, 'binding') + '; return binding;',
    ['contentCid', 'ownerPrincipal', 'gate', 'sourceGate', 'effectTargetGate', 'effectTargets', 'sources',
      'siteKey', 'realizationKey', 'environmentCid', 'authorityScopeCid'])(
    contentCid, ownerPrincipal, {accountId: account.account_id, configurationCid}, undefined, undefined, undefined, undefined,
    siteKey, realizationKey, contentCid(actualBody), authorityScopeCid);
  assert.equal(authored.authorization_context_cid, current.authorizationContextCid);
  assert.equal(authored.environment_binding_cid, current.environmentBindingCid);
  const previous = fixtureBinding(previousEnvironment, cid, ownerPrincipal, account,
    configurationCid, siteKey, realizationKey, authorityScopeCid);
  assert.equal(previous.authorization_context_cid, current.authorizationContextCid);
  assert.notEqual(previous.environment_binding_cid, current.environmentBindingCid,
    'the prior Environment binding cannot be relabeled as the current one');
  const changed = structuredClone(fixtureBody); changed.host_policy_profile.capacity.max_artifact_rows--;
  assert.notEqual(cid(changed), cid(actualBody), 'changed policy remains a distinct Environment preimage');
});
