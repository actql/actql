import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {checked} from '../host-common/runtime-result.mjs';

const control = runtimeCore(moon).publicationControl;
const limits = Object.freeze({maxWireBytes: 16384, maxNodes: 1024,
  maxDepth: 20, maxMembers: 10, maxWork: 100000});
const profiles = JSON.parse(readFileSync(new URL(
  '../../portability/corpus/model-response-profiles.json', import.meta.url)));
const raw = JSON.parse(readFileSync(new URL(
  '../../portability/corpus/model-raw-capture.json', import.meta.url))).cases[0];

test('installed Node profile reader consumes independent canonical vectors through Common', () => {
  // Declaration admission only: these independent artifacts are not installed
  // SDK/profile provenance, a capture grant or a funded public capability.
  for (const c of profiles.cases) {
    if (c.accepted) {
      assert.notEqual(control.readInstalledModelResponseProfile(c.wire,
        c.expected_cid, limits), undefined, c.id);
    } else {
      assert.throws(() => control.readInstalledModelResponseProfile(c.wire,
        c.expected_cid, limits), {code: 'MoonBitHostFailure'}, c.id);
    }
  }
});

test('installed profile reader preserves exact work and byte refusal boundaries', () => {
  const c = profiles.cases[0];
  const exact = {...limits, maxWireBytes: Buffer.byteLength(c.wire),
    maxNodes: c.expected_nodes, maxWork: c.expected_work};
  assert.notEqual(control.readInstalledModelResponseProfile(c.wire,
    c.expected_cid, exact), undefined);
  assert.throws(() => control.readInstalledModelResponseProfile(c.wire,
    c.expected_cid, {...exact, maxWork: exact.maxWork - 1}),
  {code: 'MoonBitHostFailure'});
  assert.throws(() => control.readInstalledModelResponseProfile(c.wire,
    c.expected_cid, {...exact, maxWireBytes: exact.maxWireBytes - 1}));
  assert.throws(() => control.readInstalledModelResponseProfile(c.wire,
    `sha256:${'0'.repeat(64)}`, exact), {code: 'MoonBitHostFailure'});
  for (const key of ['maxWireBytes', 'maxNodes', 'maxDepth', 'maxMembers', 'maxWork']) {
    assert.throws(() => control.readInstalledModelResponseProfile(c.wire,
      c.expected_cid, {...exact, [key]: 4294967296 + exact[key]}),
    {message: 'Invalid Model response profile limits'});
  }
});

test('Node raw selection resolves typed originals and refuses wrong order or copied evidence', () => {
  // Independent fixed policy body, not a real Run/scope or applicability claim.
  const wire = JSON.stringify({...raw.body, self_cid: raw.expected_cid},
    [...Object.keys(raw.body), 'self_cid'].sort());
  const policy = control.admitRunEvidence('model_raw_capture_policy', wire, limits);
  const originals = [
    ['retention_contract', 'raw-retention-fixture', raw.body.retention_contract_cid],
    ['metadata_retention_policy', 'raw-metadata-fixture', raw.body.metadata_retention_policy_cid],
    ['clock_contract', 'raw-clock-fixture', raw.body.clock_contract_cid],
  ].map(([kind, name, cid]) => checked(moon.clientProgramAdmitEffectDependencyBody(
    kind, cid, `{"name":"${name}","version":"actql-installed-local-policy/0.1"}`,
    limits.maxWireBytes, limits.maxNodes, limits.maxDepth)));
  originals.push(checked(moon.clientProgramAdmitEffectDependencyBody('data_policy',
    raw.body.effective_data_policy_cid,
    '{"classification":"unknown","source_data_policy_cids":[],"source_response_policy_cids":[],"unknown_provenance":true,"version":"actql-effective-data-policy/0.1"}',
    limits.maxWireBytes, limits.maxNodes, limits.maxDepth)));
  assert.notEqual(control.bindInstalledModelRawCapturePolicy(policy, ...originals), undefined);
  assert.throws(() => control.bindInstalledModelRawCapturePolicy(policy,
    originals[1], originals[0], originals[2], originals[3]),
  {code: 'MoonBitHostFailure'});
  assert.throws(() => control.bindInstalledModelRawCapturePolicy({...policy}, ...originals),
    {message: 'Foreign Run evidence'});
});

test('raw registration rejects a caller-created compiled Run before current callbacks', () => {
  let callbacks = 0;
  const observe = () => {callbacks++; throw new Error('MustNotObserve');};
  assert.throws(() => control.registerCheckedClientInferRawCapture(
    {kind: 'infer'}, {}, {}, {}, {selectionAvailable: observe,
      observeAccount: observe, observeAt: observe}),
  {message: 'Foreign Client compiled Infer raw capture'});
  assert.equal(callbacks, 0);
});
