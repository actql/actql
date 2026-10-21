import assert from 'node:assert/strict';
import test from 'node:test';
import * as source from './result-access.mjs';
import {deliverPublishedResult} from './result-delivery.mjs';
import * as packaged from '../../packages/run-host-core/result-access.mjs';
import {openResultDeliveryControl} from '../../packages/run-host-core/index.mjs';

const cid = value => `sha256:${value.repeat(64)}`;
const instant = value => `2026-09-30T00:00:00.${String(value).padStart(3, '0')}Z`;
const limits = {maxWireBytes: 10000, maxNodes: 1000, maxDepth: 20};
const contract = (name, value, body = {}) => Object.freeze({
  name, identityField: `${name}_cid`, identity: cid(value),
  wire: JSON.stringify(body),
});

// This fixture isolates the common owner's time handoff. The real MoonBit
// clock predicate and access progression are retained; physical IO and the
// already-covered Result contract/serializer decisions are bounded doubles.
function fixture(api, options = {}) {
  const semantic = openResultDeliveryControl();
  const state = {wall: instant(0), bound: undefined, observations: 0,
    admissions: [], authorizations: [], availability: [], grantChecks: [],
    attempts: [], records: [], chunks: [], finishes: 0,
    contractReads: [], indexObservations: 0, replacementIndex: undefined, operations: []};
  const retentionEnd = options.retentionEnd ?? instant(100);
  const grantEnd = options.grantEnd ?? instant(100);
  const publication = (name, value) => options.mutableContracts
    ? {...contract(name, value)} : contract(name, value);
  const index = publication('public_index_entry', '1');
  const manifest = publication('result_manifest', '2');
  const retention = contract('result_retention_policy', '3');
  const grant = contract('result_read_grant', '4');
  const request = {
    indexKey: {namespaceId: 'clock-test', authorityScopeCid: cid('a'),
      runDefinitionCid: cid('b')},
    principalId: 'principal', purpose: 'download', resultName: 'answer',
    attemptId: 'clock-attempt', format: 'jsonl',
  };
  const now = () => state.wall;
  const readClock = async () => {
    state.observations++;
    await options.beforeSample?.(state);
  };
  const acceptClock = at => {
    if (!semantic.trustedClockNotBefore(state.bound, at)) {
      throw new Error('ClockRegressed');
    }
    state.bound = at;
    return at;
  };
  const store = {
    async confirmCommittedIndex() {
      state.indexObservations++;
      if (state.replacementIndex !== undefined) return state.replacementIndex;
      return {public_index_entry_cid: index.identity,
        result_manifest_cid: manifest.identity};
    },
    async readPublicationContract(_cid, name) {
      state.contractReads.push(name);
      return {public_index_entry: index, result_manifest: manifest,
        result_retention_policy: retention}[name];
    },
    async readCommittedResultRetentionExtension() {},
    async observeTrustedClock(_cid, at) {
      await readClock();
      acceptClock(at);
      await options.afterSample?.(state);
    },
    async sampleTrustedClock(_cid, sample) {
      await readClock();
      const at = acceptClock(sample());
      await options.afterSample?.(state);
      return options.sampleResult === undefined ? at : options.sampleResult;
    },
    async createDeliveryAttempt(wire) {
      state.attempts.push(JSON.parse(wire));
      return {created: true, attempt: JSON.parse(wire)};
    },
    async latestDeliveryRecord() {},
    async latestDeliveryRecordContract() {},
    async confirmDeliveryRecord() {},
    async appendDeliveryRecord(wire) { state.records.push(JSON.parse(wire)); },
    async putPublicationContract() {},
    async withCommittedResultRows(_key, _definition, _authorize, _limits, use) {
      return use({durableResultBindingCid: cid('5'), logicalResultCid: cid('6'),
        resultSchemaCid: cid('7'), resultSchemaWire: '{}',
        resultFields: ['id'], rowCount: 1, payloadBytes: 9},
      async accept => { await accept('{"id":1}'); });
    },
  };
  if (options.legacy) delete store.sampleTrustedClock;
  const control = {...semantic,
    admit(name, wire, bounds) {
      return name === 'delivery_attempt'
        ? contract(name, 'a', JSON.parse(wire)) : semantic.admit(name, wire, bounds);
    },
    resultReadRetentionPolicyCid: () => retention.identity,
    resultReadDefinitionCid: () => cid('8'),
    resultRetentionClockContractCid: () => cid('9'),
    resultReadAvailability(_manifest, _name, _retention, at) {
      state.availability.push(at);
      return at <= retentionEnd ? 'available' : 'retention_expired';
    },
    issueResultReadGrant: () => grant,
    resultReadGrantValidAt(_grant, at) {
      state.grantChecks.push(at);
      return at <= grantEnd;
    },
    resultReadGrantAllowsBytes: () => true,
    issueDeliveryAttempt(_index, _manifest, _grant, value) {
      return contract('delivery_attempt', 'a',
        {...value, requested_at: value.requestedAt});
    },
    issueDeliveryRecord(_attempt, _previous, value) {
      return contract('delivery_record', 'b', value);
    },
    deliveryResultDefinitionCid: () => cid('8'),
    prepareResultDeliverySerializer: () => ({}),
    beginResultDelivery: () => '',
    nextResultDeliveryRow: (_serializer, row) => `${row}\n`,
    finishResultDelivery: () => '',
    issueResultDeliveryReceipt: () => contract('result_delivery_receipt', 'c'),
  };
  const authority = api.installResultAccessAuthority({
    authorizeResultReadRequest: (_facts, operation) => {state.operations.push(operation); return true;},
    admitResultRead(facts, operation) {
      state.operations.push(operation);
      state.admissions.push(facts);
      options.afterAdmission?.(state);
      return {authorizationContextCid: cid('a'), dataCeilingCid: cid('b'),
        egressAdmissionCid: cid('c'), expiresAt: grantEnd,
        maxBytes: 1000, maxUses: 1};
    },
    async authorizeResultRead(facts, operation) {
      state.operations.push(operation);
      state.authorizations.push(facts);
      return await options.authorize?.(state, facts) ?? true;
    },
  });
  const configuration = {store, control, authority, now, limits,
    frameLimits: {maxRowBytes: 1000, maxDepth: 20, maxFrameBytes: 1000},
    createDigest: () => ({update() {}, async finish() { return '0'.repeat(64); }})};
  const service = api.installResultAccessService(configuration);
  return {state, configuration, request, grant,
    publication: {store, control, index, manifest},
    deliver: () => api.deliverAuthorizedResult(service, request, {
      async write(bytes) {
        state.chunks.push(new TextDecoder().decode(bytes));
        return {confirmedBytes: bytes.byteLength};
      },
      async finish() { state.finishes++; return {confirmed: true}; },
    })};
}

test('one Result operation retains its admitted immutable publication contracts', async () => {
  const input = fixture(source);
  await input.deliver();
  assert.deepEqual(input.state.contractReads, [
    'public_index_entry', 'result_manifest', 'result_retention_policy',
  ]);
  assert.equal(input.state.indexObservations, 2,
    'delivery still observes the current committed head after admission');
  assert.equal(input.state.attempts.length, 1);
  await input.deliver();
  assert.deepEqual(input.state.contractReads, [
    'public_index_entry', 'result_manifest', 'result_retention_policy',
    'public_index_entry', 'result_manifest', 'result_retention_policy',
  ], 'a new operation owns a new read frame, not a cross-operation cache');
});

test('retained Result contracts refuse a changed committed head before an attempt', async () => {
  for (const field of ['public_index_entry_cid', 'result_manifest_cid']) {
    const input = fixture(source, {afterAdmission(state) {
      state.replacementIndex = {public_index_entry_cid: cid('1'),
        result_manifest_cid: cid('2'), [field]: cid('d')};
    }});
    await assert.rejects(input.deliver(), {code: 'ResultDeliveryDenied'});
    assert.equal(input.state.attempts.length, 0);
    assert.equal(input.state.chunks.length, 0);
    assert.equal(input.state.finishes, 0);
  }
});

test('mutable generic Result contracts retain the existing independent resolution', async () => {
  const input = fixture(source, {mutableContracts: true});
  await input.deliver();
  assert.deepEqual(input.state.contractReads, [
    'public_index_entry', 'result_manifest', 'result_retention_policy',
    'public_index_entry', 'result_manifest',
  ]);
  assert.deepEqual(input.state.chunks, ['{"id":1}\n']);
});

test('retained Result contracts cannot substitute a foreign Store or control', async () => {
  const input = fixture(source);
  const {configuration, request} = input;
  const options = {
    store: configuration.store, control: configuration.control,
    indexKey: request.indexKey, grant: input.grant,
    resultName: request.resultName, format: request.format,
    attemptId: request.attemptId, limits: configuration.limits,
    frameLimits: configuration.frameLimits, now: configuration.now,
    createDigest: configuration.createDigest, authorize: () => true,
    sink: {write() { assert.fail('no bytes before original binding'); },
      finish() { assert.fail('no completion before original binding'); }},
    signal: undefined,
  };
  for (const field of ['store', 'control']) {
    await assert.rejects(deliverPublishedResult(options,
      {...input.publication, [field]: {...input.publication[field]}}),
    {code: 'InvalidResultDeliveryRequest'});
  }
  assert.equal(input.state.indexObservations, 0);
  assert.equal(input.state.attempts.length, 0);
});

test('one public Result operation has one durable clock observation', async () => {
  const input = fixture(source);
  await input.deliver();
  assert.equal(input.state.observations, 1);
  const operation = input.state.operations[0];
  assert.ok(Object.isFrozen(operation));
  assert.ok(input.state.operations.every(value => value === operation),
    'request, admission and delivery consume the same existing owned request');
  assert.equal(input.state.records.at(-1).state, 'succeeded');
  await input.deliver();
  assert.equal(input.state.observations, 2, 'a new public operation observes its own clock');
  assert.notStrictEqual(input.state.operations.at(-1), operation);
});

test('explicit authority callback refusals cannot dispatch or complete delivery', async () => {
  for (const stage of ['attempt', 'read', 'write', 'finish', 'receipt']) {
    const input = fixture(source, {authorize(_state, facts) {
      return facts.delivery.stage !== stage;
    }});
    await assert.rejects(input.deliver(), {code: 'ResultDeliveryDenied'});
    assert.equal(input.state.records.some(record => record.state === 'succeeded'), false);
    if (['attempt', 'read', 'write'].includes(stage)) assert.equal(input.state.chunks.length, 0);
    if (stage !== 'receipt') assert.equal(input.state.finishes, 0);
  }
});

for (const [name, api] of [['source', source], ['packaged', packaged]]) {
  test(`${name}: later concurrent observation does not reject an earlier sample`, async () => {
    const input = fixture(api, {afterAdmission(state) {
      // Another operation may advance the head. Consuming the already
      // admitted floor here requires no second read or durable clock write.
      state.wall = instant(1);
      state.bound = instant(1);
    }});
    await input.deliver();
    assert.equal(input.state.attempts[0].requestedAt, instant(1));
    assert.equal(input.state.authorizations[0].delivery.observedAt, instant(1));
    assert.deepEqual(input.state.chunks, ['{"id":1}\n']);
    assert.equal(input.state.finishes, 1);
    assert.equal(input.state.records.at(-1).state, 'succeeded');
    assert.equal(input.state.bound, instant(1));
  });

  test(`${name}: initial availability uses the returned durable sample`, async () => {
    const input = fixture(api, {retentionEnd: instant(0),
      beforeSample(state) { state.wall = instant(1); }});
    await assert.rejects(input.deliver(), {code: 'ResultUnavailable'});
    assert.deepEqual(input.state.availability, [instant(1)]);
    assert.equal(input.state.admissions.length, 0);
    assert.equal(input.state.chunks.length, 0);
  });

  test(`${name}: authorization and persistence delays cannot extend expiry`, async () => {
    for (const phase of ['authorization', 'persistence']) {
      const input = fixture(api, {grantEnd: instant(0),
        authorize(state) {
          if (phase === 'authorization') state.wall = instant(1);
        },
        afterSample(state) {
          if (phase === 'persistence' && state.observations === 1) {
            state.wall = instant(1);
          }
        }});
      await assert.rejects(input.deliver(), {code: 'ResultDeliveryDenied'});
      assert.equal(input.state.chunks.length, 0);
      assert.equal(input.state.finishes, 0);
      assert.equal(input.state.attempts.length, 0);
    }
  });

  test(`${name}: exact grant and retention boundary keeps existing semantics`, async () => {
    const input = fixture(api, {grantEnd: instant(0), retentionEnd: instant(0)});
    await input.deliver();
    assert.deepEqual(input.state.chunks, ['{"id":1}\n']);
    assert.equal(input.state.records.at(-1).state, 'succeeded');
  });

  test(`${name}: true clock rollback is refused with no sink effect`, async () => {
    for (const phase of ['durable', 'callback', 'post-persistence']) {
      const input = fixture(api, {
        beforeSample(state) {
          if (phase !== 'callback') {
            state.wall = instant(2);
          }
          if (phase === 'durable') {
            state.bound = instant(2);
            state.wall = instant(1);
          }
        },
        afterSample(state) {
          if (phase === 'post-persistence') {
            state.wall = instant(1);
          }
        },
        afterAdmission(state) { if (phase === 'callback') state.wall = instant(2); },
        authorize(state) { if (phase === 'callback') state.wall = instant(1); }});
      await assert.rejects(input.deliver(), error =>
        error.message === (phase === 'durable' ? 'ClockRegressed' :
          'InvalidResultAccessClock'));
      assert.equal(input.state.chunks.length, 0);
      assert.equal(input.state.finishes, 0);
    }
  });

  test(`${name}: invalid sampling hook or returned clock is rejected`, async () => {
    const input = fixture(api, {sampleResult: 'not-a-timestamp'});
    await assert.rejects(input.deliver(), {code: 'InvalidResultAccessClock'});
    assert.equal(input.state.admissions.length, 0);
    for (const sampleTrustedClock of [null, 1]) {
      assert.throws(() => api.installResultAccessService({
        ...input.configuration,
        store: {...input.configuration.store, sampleTrustedClock},
      }), {code: 'InvalidResultAccessService'});
    }
  });

  test(`${name}: explicit observation rejects rollback at the one durable admission`, async () => {
    const input = fixture(api, {legacy: true, beforeSample(state) {
      state.wall = instant(1);
      state.bound = instant(1);
    }});
    await assert.rejects(input.deliver(), /ClockRegressed/u);
    assert.equal(input.state.chunks.length, 0);
  });
}
