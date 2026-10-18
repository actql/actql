// Real compiled Credential metadata, no key/issuer/claim/permission supplier.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import test from 'node:test';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {createLocalSigningMetadata} from '../host-common/local-signing-metadata.mjs';

const cid = digit => 'sha256:' + digit.repeat(64);
// Independent original vector already fixed in remote_credential's Local
// signing tests. Preserve its decomposed Unicode/newline and literal identity.
const body = {
  account_configuration_cid: cid('1'), account_id: 'fixture-account',
  attempt_id: 'original-signing', authority_scope_cid: cid('4'),
  checkpoint_cid: cid('5'), checkpoint_id: 'checkpoint_01', checkpoint_kind: 'effect_set',
  expires_unix_ms: '1791970559138', host_adoption_cid: cid('8'),
  issuer_authority: 'original-host-issuer', key_configuration_cid: cid('9'),
  key_generation_cid: cid('a'), key_id: 'reviewer-key', key_public_key_cid: cid('c'),
  max_uses: 1, preimage: cid('d'), principal: 'é\r\n', purpose: 'reviewer_proof',
  request_cid: cid('f'), request_scope_cid: cid('0'), run_definition_cid: cid('1'),
  run_invocation_cid: cid('2'), submission_scope_cid: cid('3'), unit_definition_cid: cid('4'),
  version: 'actql-local-signing-credential-grant/0.1',
};
const wire = JSON.stringify(body);
const originalCid = 'sha256:3a00533c843d11bd66205c306aa82f1f9f2a6dd9016d45b1889da31b8ca0959a';
const independentCid = text => 'sha256:' + createHash('sha256').update(text).digest('hex');
const metadata = () => runtimeCore(moon).localSigningMetadata();
const request = expectedScope => ({useId: 'original-signing',
  trustedNowMilliseconds: 1000n, usedCount: 0, revoked: false, expectedScope});
const original = control => {
  const grant = control.admitGrant(wire, originalCid), scope = control.originalScope(grant);
  return {grant, scope, use: control.prepareUse(grant, request(scope))};
};

test('same actual Credential Owner preserves independent signing grant and use identities', () => {
  assert.equal(independentCid(wire), originalCid);
  const control = metadata(), {grant, scope, use} = original(control);
  assert.equal(control.grantWire(grant), wire);
  assert.equal(control.grantCid(grant), originalCid);
  assert.deepEqual(control.grantLimits(grant), {maxUses: 1, expiresAt: 1791970559138n});
  const useWire = JSON.stringify({grant_cid: originalCid, use_id: 'original-signing',
    use_ordinal: 1, version: 'actql-local-signing-credential-use/0.1'});
  assert.equal(control.useWire(use), useWire);
  assert.equal(control.useCid(use), independentCid(useWire));
  assert.deepEqual(control.useProjection(use), {grantCid: originalCid, useId: 'original-signing', ordinal: 1});
  assert.equal(control.checkUseBinding(use, request(scope)), undefined);
});

test('the full expected original purpose/key/Checkpoint/Run/request scope is required', () => {
  const control = metadata(), {grant, use} = original(control);
  for (const change of [
    {purpose: 'host_attestation'}, {key_generation_cid: cid('b')},
    {checkpoint_cid: cid('b')}, {run_definition_cid: cid('b')},
    {request_scope_cid: cid('b')}, {authority_scope_cid: cid('b')},
    {attempt_id: 'foreign-attempt'}, {preimage: cid('b')},
  ]) {
    const changedWire = JSON.stringify({...body, ...change});
    const changedGrant = control.admitGrant(changedWire, independentCid(changedWire));
    const changedScope = control.originalScope(changedGrant);
    assert.throws(() => control.prepareUse(grant, request(changedScope)), {code: 'MoonBitHostFailure'});
    assert.throws(() => control.checkUseBinding(use, request(changedScope)), {code: 'MoonBitHostFailure'});
  }
});

test('copied and foreign view handles cannot substitute for the same runtime originals', () => {
  const control = metadata(), other = metadata(), {grant, scope, use} = original(control);
  for (const copy of [{...grant}, Object.create(grant), null, 'sha256:copied']) {
    assert.throws(() => control.grantCid(copy), {code: 'ForeignLocalSigningMetadata'});
  }
  assert.throws(() => other.grantCid(grant), {code: 'ForeignLocalSigningMetadata'});
  assert.throws(() => other.useCid(use), {code: 'ForeignLocalSigningMetadata'});
  const foreign = original(other);
  assert.throws(() => control.prepareUse(grant, request(foreign.scope)), {code: 'ForeignLocalSigningMetadata'});
  assert.throws(() => control.checkUseBinding(foreign.use, request(scope)), {code: 'ForeignLocalSigningMetadata'});
});

test('closed original grant decoding refuses HTTP roles, changed bytes and missing runtime', () => {
  const control = metadata();
  for (const changedWire of [wire.replace('reviewer_proof', 'provider_sign'),
    wire.replace('{', '{"request_method":"GET",'), ' ' + wire]) {
    assert.throws(() => control.admitGrant(changedWire, originalCid), {code: 'MoonBitHostFailure'});
  }
  assert.throws(() => control.admitGrant(wire, cid('0')), {code: 'MoonBitHostFailure'});
  assert.throws(() => createLocalSigningMetadata(null), {code: 'LocalSigningMetadataRuntimeUnavailable'});
  assert.throws(() => createLocalSigningMetadata({}), {code: 'LocalSigningMetadataRuntimeUnavailable'});
});

test('metadata time/expiry/revocation/use bounds never mint a permission or reset usage', () => {
  const control = metadata(), {grant, scope, use} = original(control);
  for (const change of [{trustedNowMilliseconds: 1791970559138n},
    {usedCount: 1}, {revoked: true}]) {
    assert.throws(() => control.prepareUse(grant, {...request(scope), ...change}), {code: 'MoonBitHostFailure'});
  }
  for (const value of [-1n, 9223372036854775808n, 1000, '1000']) {
    assert.throws(() => control.prepareUse(grant, {...request(scope), trustedNowMilliseconds: value}),
      {code: 'InvalidLocalSigningMetadataTime'});
  }
  assert.throws(() => control.checkUseBinding(use, {...request(scope), revoked: true}), {code: 'MoonBitHostFailure'});
  assert.throws(() => control.prepareUse(grant, {...request(scope), expectedScope: undefined}),
    {code: 'ForeignLocalSigningMetadata'});
});

test('exact saved use admission keeps its original ordinal and foreign grant refusal', () => {
  const control = metadata(), {grant, use} = original(control);
  const saved = control.useWire(use), identity = control.useCid(use);
  const restored = control.admitUse(grant, saved, identity);
  assert.deepEqual(control.useProjection(restored), control.useProjection(use));
  assert.equal(control.useWire(restored), saved);
  for (const changed of [saved.replace('original-signing', 'another-use'),
    saved.replace('"use_ordinal":1', '"use_ordinal":2'), saved.replace('credential-use/0.1', 'http-use/0.1')]) {
    assert.throws(() => control.admitUse(grant, changed, identity), {code: 'MoonBitHostFailure'});
  }
});

test('captured actual callbacks and original receiver do not change after view creation', () => {
  const selected = Object.create(moon), originalRead = moon.clientLocalSigningGrantAdmit;
  let calls = 0;
  Object.defineProperty(selected, 'clientLocalSigningGrantAdmit', {configurable: true, value(...args) {
    assert.equal(this, selected); calls++; return Reflect.apply(originalRead, moon, args);
  }});
  const control = createLocalSigningMetadata(selected);
  Object.defineProperty(selected, 'clientLocalSigningGrantAdmit', {value() {assert.fail('replacement callback');}});
  assert.equal(control.grantCid(control.admitGrant(wire, originalCid)), originalCid);
  assert.equal(calls, 1);
});

test('retiring only the metadata view refuses escaped references without retiring another view', () => {
  const control = metadata(), other = metadata(), {grant, scope, use} = original(control);
  const unaffected = original(other);
  assert.equal(control.retireMetadataView(), true);
  assert.equal(control.retireMetadataView(), false);
  for (const read of [() => control.grantWire(grant), () => control.useWire(use),
    () => control.prepareUse(grant, request(scope)), () => control.admitGrant(wire, originalCid)]) {
    assert.throws(read, {code: 'LocalSigningMetadataRetired'});
  }
  assert.equal(other.useProjection(unaffected.use).ordinal, 1);
});
