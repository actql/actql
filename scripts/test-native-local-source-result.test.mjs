import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {test} from 'node:test';
import {verifyNativeLocalCheckEnvironmentOriginal} from './test-native-local-source-result.mjs';

const original = await readFile(new URL('./fixtures/native-local-cli/environment.json', import.meta.url));

test('Native CLI preflight accepts the fixed canonical Environment original', () => {
  const admitted = verifyNativeLocalCheckEnvironmentOriginal(original);
  assert.equal(admitted.evidence_bundle_cid,
    'sha256:aa727ea3fb169143aa8b774d7ee16679166cdae133c990a128921eaad0c3d904');
});

test('Native CLI preflight refuses formatting changes without repairing the original', () => {
  const unchanged = JSON.parse(original);
  const pretty = Buffer.from(JSON.stringify(unchanged, null, 2));
  assert.throws(() => verifyNativeLocalCheckEnvironmentOriginal(pretty), /exact canonical bytes/u);
  assert.throws(() => verifyNativeLocalCheckEnvironmentOriginal(Buffer.concat([original, Buffer.from('\n')])),
    /exact canonical bytes/u);
});

test('Native CLI preflight refuses changed Environment preimages and declared identities', () => {
  const changed = JSON.parse(original);
  changed.host_policy_profile.capacity.max_artifact_rows = 999;
  assert.throws(() => verifyNativeLocalCheckEnvironmentOriginal(Buffer.from(JSON.stringify(changed))),
    /canonical CID/u);
  const foreign = JSON.parse(original);
  foreign.evidence_bundle_cid = `sha256:${'0'.repeat(64)}`;
  assert.throws(() => verifyNativeLocalCheckEnvironmentOriginal(Buffer.from(JSON.stringify(foreign))),
    /canonical CID/u);
});
