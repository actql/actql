import assert from 'node:assert/strict';
import test from 'node:test';
import {describeAuthorizedResult, installResultAccessAuthority,
  installResultAccessService} from './result-access.mjs';

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
  grantValid = () => true} = {}) {
  const calls = [];
  const index = {public_index_entry_cid: cid('2'), result_manifest_cid: cid('3')};
  const store = {
    async confirmCommittedIndex(ref) {
      calls.push(['index', ref]); return committed() ? index : undefined;
    },
    async readPublicationContract() { calls.push(['contract']); return {}; },
    async observeTrustedClock() { calls.push(['clock']); },
    async readCommittedResultRetentionExtension() {},
    async readCommittedResultDescriptionEvidence() {
      calls.push(['metadata']); return {bindings: [], definition: {}, schemaWire: '{}'};
    },
    async consumeManifestReadGrant() { calls.push(['consume']); },
  };
  const methods = ['issueResultReadGrant', 'resultReadAvailability',
    'resultReadExtendedAvailability', 'resultReadGrantValidAt',
    'beginResultAccessProgress', 'resultAccessProgressAction',
    'recordResultAccessRequestAuthorization', 'recordResultAccessResolution',
    'recordResultAccessInitialAvailability', 'recordResultAccessReadAdmission',
    'recordResultAccessGrant'];
  const control = {...Object.fromEntries(methods.map(name => [name, () => {}])),
    resultReadDefinitionCid: () => cid('d'),
    resultReadRetentionPolicyCid: () => cid('4'),
    resultRetentionClockContractCid: () => cid('5'),
    resultMetadataRetentionState: () => retained() ? 'retained' : 'delete_due',
    issueManifestReadGrant: () => ({wire: 'manifest grant'}),
    manifestReadGrantAllowsBytes: () => true,
    manifestReadGrantValidAt: grantValid,
    describeCommittedResult: () => projected,
  };
  const admission = {authorizationContextCid: cid('6'), dataCeilingCid: cid('7'),
    egressAdmissionCid: cid('8'), expiresAt: '2026-10-01T00:00:00.000Z',
    maxBytes: 1048576, maxUses: 1};
  const authority = installResultAccessAuthority({
    authorizeResultReadRequest() {}, admitResultRead() {}, authorizeResultRead() {},
    authorizeResultDescription: authorize,
    admitResultDescription: admit ?? (async () => admission),
  });
  return {calls, service: installResultAccessService({store, control, authority,
    now: () => '2026-09-30T00:00:00.000Z', createDigest() {},
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
