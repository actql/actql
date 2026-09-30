import assert from 'node:assert/strict';
import test from 'node:test';
import {describeAuthorizedResult, installResultAccessAuthority,
  installResultAccessService} from './result-access.mjs';
import * as packaged from '../../packages/run-host-core/result-access.mjs';
import {openResultDeliveryControl} from '../../packages/run-host-core/index.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const key = {namespaceId: 'description', authorityScopeCid: cid('a'),
  runDefinitionCid: cid('b')};
const request = () => ({indexKey: {...key}, principalId: 'principal',
  purpose: 'inspect', resultName: 'answer', format: 'jsonl', attemptId: 'metadata',
  maxWireBytes: 1048576, maxNodes: 10000, maxDepth: 64});
const projected = {programDefinitionCid: cid('c'), resultDefinitionCid: cid('d'),
  resultArtifactCid: cid('e'), resultSchemaCid: cid('f'), resultName: 'answer',
  columns: [{name: 'a', contract: {type: 'number', nullable: false}}],
  serialization: {format: 'jsonl', version: 'actql-jsonl/0.1', contractCid: cid('1')}};

// These test doubles verify adapter sequencing, not publication semantics.
// Packed acceptance separately exercises the real MoonBit and Store owners.
function fixture({authorize = async () => true, admit,
  retained = () => true, committed = () => true,
  grantValid = () => true, sampleClock, observeClock,
  now = () => '2026-09-30T00:00:00.000Z',
  api = {installResultAccessAuthority, installResultAccessService}} = {}) {
  const calls = [];
  const index = {public_index_entry_cid: cid('2'), result_manifest_cid: cid('3')};
  const store = {
    async confirmCommittedIndex(ref) {
      calls.push(['index', ref]); return committed() ? index : undefined;
    },
    async readPublicationContract() { calls.push(['contract']); return {}; },
    async observeTrustedClock(...args) {
      calls.push(['clock']); return observeClock?.(...args);
    },
    async readCommittedResultRetentionExtension() {},
    async readCommittedResultDescriptionEvidence() {
      calls.push(['metadata']); return {bindings: [], definition: {}, schemaWire: '{}'};
    },
    async consumeManifestReadGrant() { calls.push(['consume']); },
  };
  if (sampleClock !== undefined) store.sampleTrustedClock = sampleClock;
  const methods = ['issueResultReadGrant', 'resultReadAvailability',
    'resultReadExtendedAvailability', 'resultReadGrantValidAt',
    'beginResultAccessProgress', 'resultAccessProgressAction',
    'recordResultAccessRequestAuthorization', 'recordResultAccessResolution',
    'recordResultAccessInitialAvailability', 'recordResultAccessReadAdmission',
    'recordResultAccessGrant'];
  const control = {...Object.fromEntries(methods.map(name => [name, () => {}])),
    trustedClockNotBefore: openResultDeliveryControl().trustedClockNotBefore,
    resultReadDefinitionCid: () => cid('d'),
    resultReadRetentionPolicyCid: () => cid('4'),
    resultRetentionClockContractCid: () => cid('5'),
    resultMetadataRetentionState: (_retention, at) =>
      retained(at) ? 'retained' : 'delete_due',
    issueManifestReadGrant: () => ({wire: 'manifest grant'}),
    manifestReadGrantAllowsBytes: () => true,
    manifestReadGrantValidAt: grantValid,
    describeCommittedResult: () => projected,
  };
  const admission = {authorizationContextCid: cid('6'), dataCeilingCid: cid('7'),
    egressAdmissionCid: cid('8'), expiresAt: '2026-10-01T00:00:00.000Z',
    maxBytes: 1048576, maxUses: 1};
  const authority = api.installResultAccessAuthority({
    authorizeResultReadRequest() {}, admitResultRead() {}, authorizeResultRead() {},
    authorizeResultDescription: authorize,
    admitResultDescription: admit ?? (async () => admission),
  });
  return {calls, service: api.installResultAccessService({store, control, authority,
    now, createDigest() {},
    limits: {maxWireBytes: 1048576, maxNodes: 10000, maxDepth: 64},
    frameLimits: {maxRowBytes: 1024, maxDepth: 64, maxFrameBytes: 4096}})};
}

test('description denial occurs before Store I/O and hides publication', async () => {
  for (const authorize of [async () => false,
    async () => { throw new Error('offline authority'); }]) {
    const {service, calls} = fixture({authorize});
    await assert.rejects(describeAuthorizedResult(service, request()),
      {code: 'ResultAccessDenied'});
    assert.deepEqual(calls, []);
  }
  const {service} = fixture({committed: () => false});
  await assert.rejects(describeAuthorizedResult(service, request()),
    {code: 'ResultAccessDenied'});
});

test('description owns the authorized Run and request snapshot across await', async () => {
  let enter, resume, facts;
  const entered = new Promise(resolve => { enter = resolve; });
  const gate = new Promise(resolve => { resume = resolve; });
  const {service, calls} = fixture({authorize: async value => {
    if (value.stage === 'request') { facts = value; enter(); await gate; }
    return true;
  }});
  const input = request();
  const pending = describeAuthorizedResult(service, input);
  await entered;
  input.indexKey.namespaceId = 'foreign'; input.resultName = 'other';
  input.maxWireBytes = 1;
  resume();
  assert.deepEqual(await pending, {ref: key, ...projected});
  assert.equal(Object.isFrozen(facts.indexKey), true);
  assert.ok(calls.filter(([kind]) => kind === 'index')
    .every(([, ref]) => ref.namespaceId === key.namespaceId));
});

test('current authorization is rechecked after admission and before response', async () => {
  for (const deniedStage of ['read', 'response']) {
    const stages = [];
    const {service} = fixture({authorize: async value => {
      stages.push(value.stage); return value.stage !== deniedStage;
    }});
    await assert.rejects(describeAuthorizedResult(service, request()),
      {code: 'ResultAccessDenied'});
    assert.equal(stages.at(-1), deniedStage);
  }
});

test('expiry after async authorization never returns retained metadata', async () => {
  let retained = true;
  const {service} = fixture({retained: () => retained,
    authorize: async value => {
      if (value.stage === 'response') retained = false;
      return true;
    }});
  await assert.rejects(describeAuthorizedResult(service, request()),
    {code: 'ResultDescriptionUnavailable'});
});

test('grant expiry after response authorization remains access denial', async () => {
  let valid = true;
  const {service} = fixture({grantValid: () => valid,
    authorize: async value => {
      if (value.stage === 'response') valid = false;
      return true;
    }});
  await assert.rejects(describeAuthorizedResult(service, request()),
    {code: 'ResultAccessDenied'});
});

test('uncertain commit confirmation exposes no description and is not absence', async () => {
  const failure = Object.assign(new Error('confirmation unavailable'),
    {code: 'PublicationCommitUnknown'});
  const {service, calls} = fixture({committed: () => { throw failure; }});
  await assert.rejects(describeAuthorizedResult(service, request()),
    error => error === failure);
  assert.deepEqual(calls.map(([name]) => name), ['index']);
});

test('oversized descriptions fail before consuming the Manifest grant', async () => {
  const {service, calls} = fixture();
  await assert.rejects(describeAuthorizedResult(service,
    {...request(), maxNodes: 1}), {code: 'ResultDescriptionTooLarge'});
  assert.equal(calls.some(([kind]) => kind === 'consume'), false);
});

test('an aborted metadata request opens neither payload nor Run cancellation', async () => {
  const abort = new AbortController();
  const {service, calls} = fixture({authorize: async () => {
    abort.abort(); return true;
  }});
  await assert.rejects(describeAuthorizedResult(service, request(), abort.signal),
    {name: 'AbortError'});
  assert.deepEqual(calls, []);
});

const instant = value => `2026-09-30T00:00:00.${String(value).padStart(3, '0')}Z`;
for (const [name, api] of [['source', {describeAuthorizedResult,
  installResultAccessAuthority, installResultAccessService}], ['packaged', packaged]]) {
  test(`${name}: metadata sampling tolerates advancing concurrent observations`, async () => {
    const clock = openResultDeliveryControl();
    let wall = instant(0), bound = instant(0), admittedAt;
    const input = fixture({api, now: () => wall,
      admit(facts) { admittedAt = facts.observedAt; return {
        authorizationContextCid: cid('6'), dataCeilingCid: cid('7'),
        egressAdmissionCid: cid('8'), expiresAt: instant(100),
        maxBytes: 1048576, maxUses: 1,
      }; },
      observeClock(_cid, at) {
        wall = instant(1); bound = instant(1);
        if (!clock.trustedClockNotBefore(bound, at)) throw new Error('ClockRegressed');
      },
      sampleClock(_cid, now) {
        // Another observer has already advanced while this request waited
        // for its physical read. Sampling after that read is still valid.
        wall = instant(1); bound = instant(1);
        const at = now();
        assert.equal(clock.trustedClockNotBefore(bound, at), true);
        return at;
      }});
    assert.deepEqual(await api.describeAuthorizedResult(input.service, request()),
      {ref: key, ...projected});
    assert.equal(admittedAt, instant(1));
    assert.equal(input.calls.filter(([kind]) => kind === 'consume').length, 1);
    assert.equal(input.calls.some(([kind]) => kind === 'clock'), false);
  });

  test(`${name}: metadata checks use the accepted time and post-I/O deadline`, async () => {
    for (const phase of ['sample', 'persistence']) {
      let wall = instant(0);
      const input = fixture({api, now: () => wall,
        retained: at => at < instant(1),
        sampleClock(_cid, now) {
          if (phase === 'sample') wall = instant(1);
          const at = now();
          if (phase === 'persistence') wall = instant(1);
          return at;
        }});
      await assert.rejects(api.describeAuthorizedResult(input.service, request()),
        {code: 'ResultDescriptionUnavailable'});
      assert.equal(input.calls.some(([kind]) => kind === 'consume'), false);
    }
  });

  test(`${name}: grant expiry after sampled metadata persistence denies response`, async () => {
    for (const boundary of [2, 3]) {
      let wall = instant(0), samples = 0;
      const input = fixture({api, now: () => wall,
        grantValid: (_grant, at) => at <= instant(0),
        sampleClock(_cid, now) {
          const at = now();
          if (++samples === boundary) wall = instant(1);
          return at;
        }});
      await assert.rejects(api.describeAuthorizedResult(input.service, request()),
        {code: 'ResultAccessDenied'});
      assert.equal(input.calls.filter(([kind]) => kind === 'consume').length,
        boundary === 2 ? 0 : 1);
    }
  });

  test(`${name}: metadata grant equality remains valid but deletion equality does not`, async () => {
    const common = {api, now: () => instant(1), sampleClock: (_cid, now) => now(),
      grantValid: (_grant, at) => at <= instant(1)};
    const valid = fixture({...common, retained: at => at < instant(2)});
    assert.deepEqual(await api.describeAuthorizedResult(valid.service, request()),
      {ref: key, ...projected});
    const deleted = fixture({...common, retained: at => at < instant(1)});
    await assert.rejects(api.describeAuthorizedResult(deleted.service, request()),
      {code: 'ResultDescriptionUnavailable'});
  });

  test(`${name}: metadata refuses malformed observations and post-persistence rollback`, async () => {
    for (const returned of ['malformed', instant(2)]) {
      const input = fixture({api, now: () => instant(1),
        sampleClock: () => returned});
      await assert.rejects(api.describeAuthorizedResult(input.service, request()),
        {code: 'InvalidResultAccessClock'});
      assert.equal(input.calls.some(([kind]) => kind === 'consume'), false);
    }
  });
}
