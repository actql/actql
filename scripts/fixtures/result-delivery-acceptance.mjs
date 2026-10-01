import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';

const cid = value => `sha256:${value.repeat(64)}`;
const limits = {maxWireBytes: 65536, maxNodes: 4096, maxDepth: 64};
const canonical = value => Array.isArray(value) ? value.map(canonical)
  : value !== null && typeof value === 'object'
    ? Object.fromEntries(Object.keys(value).sort().map(key => [key, canonical(value[key])]))
    : value;
const instant = seconds => `2026-10-01T00:00:${String(seconds).padStart(2, '0')}.000Z`;

// A bounded physical Store/CAS and sink fixture, not Cloud durability evidence.
// All contract admission, binding, grants, records, receipts and serialization
// use the actual portable owner through the public package API.
function fixture(api, control, options = {}) {
  const contracts = new Map();
  const retain = (name, field, body) => {
    const identity = `sha256:${createHash('sha256')
      .update(JSON.stringify(canonical(body))).digest('hex')}`;
    const value = control.admit(name, JSON.stringify({...body, [field]: identity}), limits);
    contracts.set(identity, value);
    return value;
  };
  const retention = retain('result_retention_policy', 'effective_retention_policy_cid', {
    version: 'actql-result-retention-policy/0.1', retention_contract_cid: cid('b'),
    effective_data_policy_cid: cid('a'), available_until: '2027-01-01T00:00:00.000Z',
    delete_by: '2027-01-02T00:00:00.000Z', extension_ceiling_at: '2027-01-03T00:00:00.000Z',
    metadata_retention_policy_cid: cid('c'), metadata_delete_by: '2027-01-04T00:00:00.000Z',
    clock_contract_cid: cid('d'),
  });
  const artifact = retain('result_artifact', 'result_artifact_cid', {
    version: 'actql-result-artifact/0.1', result_definition_cid: cid('1'),
    invocation_cid: cid('2'), logical_result_cid: cid('3'), result_schema_cid: cid('4'),
    ordering_evidence_cid: cid('5'), actual_row_count: 1, actual_completeness: 'complete',
    effective_data_policy_cid: cid('a'), effective_retention_policy_cid: retention.identity,
    provenance_evidence_cids: [cid('8')],
  });
  const manifest = retain('result_manifest', 'result_manifest_cid', {
    version: 'actql-result-manifest/0.1', run_definition_cid: cid('9'),
    invocation_cid: cid('2'), results: {answer: JSON.parse(artifact.wire)},
  });
  const index = retain('public_index_entry', 'public_index_entry_cid', {
    version: 'actql-public-index-entry/0.1', namespace_id: 'namespace',
    authority_scope_cid: cid('a'), run_definition_cid: cid('9'), invocation_cid: cid('2'),
    result_manifest_cid: manifest.identity, run_receipt_cid: cid('b'), captured_run_cid: cid('c'),
    durable_result_binding_cids: [cid('d')], publication_request_cid: cid('e'),
    publication_attempt_cid: cid('f'), committed_at: instant(0),
  });
  const state = {now: instant(1), allowed: true, selected: undefined, record: undefined,
    admissions: 0, grantUses: 0, readers: 0, records: [], chunks: [], finishes: 0,
    authorizations: [], receiptReads: 0};
  const read = (identity, name) => {
    const value = contracts.get(identity);
    assert.equal(value?.name, name, `missing ${name}: ${identity}`);
    if (name === 'result_delivery_receipt') state.receiptReads++;
    return value;
  };
  const store = {
    async confirmCommittedIndex() { return JSON.parse(index.wire); },
    async readPublicationContract(identity, name) { return read(identity, name); },
    async readCommittedResultRetentionExtension() {},
    async observeTrustedClock() {},
    async createDeliveryAttempt(wire, grantWire) {
      state.admissions++;
      const proposed = control.admit('delivery_attempt', wire, limits);
      const grant = control.admit('result_read_grant', grantWire, limits);
      if (!state.selected) {
        state.selected = proposed;
        state.grantUses++;
        return options.selection?.(proposed, {index, manifest, grant}) ??
          {created: true, attempt: JSON.parse(proposed.wire)};
      }
      return {created: false, attempt: JSON.parse(state.selected.wire)};
    },
    async latestDeliveryRecordContract(identity) {
      assert.equal(identity, state.selected.identity, 'lookup must use canonical attempt');
      return state.record;
    },
    async latestDeliveryRecord(identity) {
      const record = await store.latestDeliveryRecordContract(identity);
      return record && JSON.parse(record.wire);
    },
    async confirmDeliveryRecord(wire) { assert.equal(wire, state.record.wire); },
    async appendDeliveryRecord(wire) {
      const next = control.admit('delivery_record', wire, limits);
      assert.equal(JSON.parse(next.wire).delivery_attempt_cid, state.selected.identity);
      await options.beforeAppend?.(next);
      assert.equal(control.deliveryTransition(state.record, next), true);
      state.record = next;
      state.records.push(wire);
    },
    async putPublicationContract(name, wire) {
      const value = control.admit(name, wire, limits);
      contracts.set(value.identity, value);
    },
    async withCommittedResultRows(_key, definition, authorize, _limits, use, _control, attempt) {
      assert.equal(definition, cid('1'));
      assert.equal(attempt, state.selected.identity, 'reader must use canonical attempt');
      assert.equal(await authorize({resultDefinitionCid: definition}), true);
      state.readers++;
      return use({durableResultBindingCid: cid('d'), logicalResultCid: cid('3'),
        resultSchemaCid: cid('4'), resultSchemaWire: '{"value":{"nullable":false,"type":"integer"}}',
        resultFields: ['value'], rowCount: 1, payloadBytes: 13},
      async accept => { await accept('{"value":7}'); });
    },
  };
  const authority = api.installResultAccessAuthority({
    authorizeResultReadRequest: () => true,
    admitResultRead: () => ({authorizationContextCid: cid('2'), dataCeilingCid: cid('a'),
      egressAdmissionCid: cid('3'), expiresAt: '2026-10-02T00:00:00.000Z',
      maxBytes: 1024, maxUses: 1}),
    authorizeResultRead(facts) {
      state.authorizations.push(facts.delivery);
      return state.allowed;
    },
  });
  const service = api.installResultAccessService({store, control, authority,
    now: () => state.now, limits,
    frameLimits: {maxRowBytes: 4096, maxDepth: 32, maxFrameBytes: 4096},
    createDigest() {
      const digest = createHash('sha256');
      return {update: bytes => digest.update(bytes), finish: () => digest.digest('hex')};
    },
  });
  return {state, deliver: () => api.deliverAuthorizedResult(service, {
    indexKey: {namespaceId: 'namespace', authorityScopeCid: cid('a'), runDefinitionCid: cid('9')},
    principalId: 'principal', purpose: 'download', resultName: 'answer', format: 'json',
    attemptId: 'same-logical-attempt',
  }, {async write(bytes) {
    state.chunks.push(new TextDecoder().decode(bytes));
    return {confirmedBytes: bytes.byteLength};
  }, async finish() { state.finishes++; return {confirmed: true}; }})};
}

export const deliveryAcceptanceCases = {
  async 'advanced-time replay uses the retained attempt without another reader'(api, control) {
    const f = fixture(api, control);
    const first = await f.deliver();
    assert.equal(f.state.chunks.join(''), '[{"value":7}]');
    const before = {records: [...f.state.records], chunks: [...f.state.chunks],
      receipt: first.receipt.wire, record: first.record.wire};
    f.state.now = instant(2);
    const replay = await f.deliver();
    assert.equal(replay.idempotent, true);
    assert.equal(replay.attempt.identity, first.attempt.identity);
    assert.equal(replay.attempt.wire, first.attempt.wire);
    assert.equal(replay.receipt.wire, before.receipt);
    assert.equal(replay.record.wire, before.record);
    assert.deepEqual(f.state.records, before.records);
    assert.deepEqual(f.state.chunks, before.chunks);
    assert.equal(f.state.readers, 1);
    assert.equal(f.state.grantUses, 1);
    assert.equal(f.state.finishes, 1);
    assert.equal(f.state.receiptReads, 1);
    assert.equal(f.state.authorizations.at(-1).attempt.identity, first.attempt.identity);
    assert.equal(f.state.authorizations.at(-1).observedAt, instant(2));
    f.state.allowed = false;
    await assert.rejects(f.deliver(), {code: 'ResultDeliveryDenied'});
    assert.equal(f.state.receiptReads, 1);
    assert.equal(f.state.readers, 1);
    f.state.allowed = true;
    f.state.now = '2026-10-03T00:00:00.000Z';
    await assert.rejects(f.deliver(), {code: 'ResultDeliveryDenied'});
    assert.equal(f.state.readers, 1);
  },
  async 'concurrent first requests cannot start a second stream before the first record'(api, control) {
    let entered, release, appends = 0;
    const arrived = new Promise(resolve => { entered = resolve; });
    const gate = new Promise(resolve => { release = resolve; });
    const f = fixture(api, control, {beforeAppend: async () => {
      if (++appends === 1) { entered(); await gate; }
    }});
    const first = f.deliver();
    await arrived;
    try {
      await assert.rejects(f.deliver(), {code: 'ResultDeliveryAttemptUnresolved'});
      assert.equal(f.state.readers, 0);
      assert.equal(f.state.chunks.length, 0);
      assert.equal(f.state.records.length, 0);
      assert.equal(f.state.grantUses, 1);
    } finally { release(); await first; }
    assert.equal(f.state.readers, 1);
    assert.equal(f.state.finishes, 1);
    assert.equal(f.state.records.length, 2);
  },
  async 'malformed or differently bound Store selections never expose bytes'(api, control) {
    for (const variant of ['cid', 'format', 'attemptId', 'grant', 'created-time']) {
      const f = fixture(api, control, {selection(proposed, {index, manifest, grant}) {
        const body = JSON.parse(proposed.wire);
        if (variant === 'cid') return {created: false,
          attempt: {...body, delivery_attempt_cid: cid('e')}};
        const otherGrant = variant === 'format' || variant === 'grant'
          ? control.issueResultReadGrant(index, manifest, {
            resultNames: ['answer'], formats: ['json', 'jsonl'],
            principalId: 'principal', purpose: variant === 'grant' ? 'other' : 'download',
            dataCeilingCid: cid('a'), maxBytes: 1024, maxUses: 1,
            expiresAt: '2026-10-02T00:00:00.000Z',
            authorizationContextCid: cid('2'), egressAdmissionCid: cid('3'),
          }, limits) : grant;
        const other = control.issueDeliveryAttempt(index, manifest, otherGrant, {
          resultName: 'answer', format: variant === 'format' ? 'jsonl' : 'json',
          attemptId: variant === 'attemptId' ? 'foreign-attempt' : body.attempt_id,
          requestedAt: variant === 'created-time' ? instant(0) : body.requested_at,
        }, limits);
        return {created: variant === 'created-time', attempt: JSON.parse(other.wire)};
      }});
      await assert.rejects(f.deliver(), {code: 'InvalidResultDeliveryAttemptState'});
      assert.equal(f.state.readers, 0);
      assert.equal(f.state.records.length, 0);
      assert.equal(f.state.chunks.length, 0);
    }
  },
};

export async function exerciseResultDeliveryAcceptance(api, controlFactory) {
  const passed = [];
  for (const [name, run] of Object.entries(deliveryAcceptanceCases)) {
    await run(api, controlFactory());
    passed.push(name);
  }
  return passed;
}
