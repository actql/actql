// Actual same-source native request, Form, target and response validators.
// Explicit Account/Site/read/send ports are component inputs, not ordinary
// Host approval, durable claims, physical cleanup or provider acceptance.
import assert from 'node:assert/strict';
import test from 'node:test';
import {createHash} from 'node:crypto';
import {recordCheckpointApproval} from '../../../host-common/checkpoint-approval.mjs';
import {kintoneUpdateDriver, KINTONE_UPDATE_TARGET_VERSION} from '../host/kintone-update-driver.mjs';
import {cid, encode, bytes, identity, revision, form, value, policy, observation, fixture as requestFixture} from './kintone-update.fixture.mjs';

const response = () => ({useCid: cid('1'), statusCode: 200,
  body: bytes({records: [{id: identity, revision: '9007199254740995'}]})});
function fixture(changes = {}) {
  const native = requestFixture(), state = {decisions: [], grants: [], originals: new WeakSet(),
    reads: [], writes: [], admitted: [], denied: false, response: response()};
  const site = {
    issueReadGrant(facts) {
      assert.strictEqual(this, site); state.grants.push(facts);
      const original = Object.freeze({grant: Object.freeze({ordinal: state.grants.length})});
      state.originals.add(original); return original;
    },
    admitCheckpointEffectTargetRead(decision, binding, operation) {
      assert.strictEqual(this, site); state.admitted.push({decision, binding, operation}); return decision;
    },
  };
  const authorization = {async authorize(boundary, tuple, options) {
    assert.strictEqual(this, authorization); assert.equal(boundary, 'acquisition');
    assert.match(options.subjectCid, /^sha256:/u); state.decisions.push(tuple);
    return Object.freeze({action: state.denied ? 'deny' : 'dispatch'});
  }};
  const config = {...native.options, site, authorization, connection: 'kintone:kintone',
    formResource: 'inquiries-form', fields: ['Computed', 'Subject', 'Tags'],
    maxRows: 2, maxMembers: 4, maxRecoveryBytes: 200000, ...changes};
  const driver = kintoneUpdateDriver(config), member = Object.freeze({kind: 'update', resource: 'inquiries',
    memberIndex: 0, effectId: 'update-inquiry', mapping: Object.freeze({mappingRef: native.adapter.mappingRef,
      mappingCid: native.adapter.mappingCid})});
  const describeOptions = {member, maxRows: config.maxRows, runInvocationCid: cid('d'), dispatchRequestCid: cid('e'),
    controlConstruction(receiver, method, args) {return Reflect.apply(method, receiver, args);},
    async readChild(authorization, input, row, slot, project) {
      assert.strictEqual(input.grant, authorization.grant);
      if (slot !== 'target') {
        assert(state.originals.has(authorization), 'same Site issuer original reaches the child');
        assert.equal(Object.hasOwn(authorization, 'useId'), false);
      }
      await input.currentBeforeSend(); state.reads.push({authorization, input, row, slot});
      const operation = [...input.operations.values()][0];
      assert.equal(operation.method, 'POST'); assert(operation.headers.some(([k,v]) => k === 'x-http-method-override' && v === 'GET'));
      const target = slot === 'target' ? observation({id: JSON.parse(operation.body).query.match(/\(([0-9]+)\)/u)[1]})
        : {statusCode: 200, body: bytes(form)};
      target.accepted = true; state.readHook?.(slot, target);
      return project(target);
    }};
  const describe = () => driver.describe(describeOptions);
  const prepare = (current, selector = identity) => driver.prepareRequest({member, current, selector, value});
  const target = Object.freeze({grant: Object.freeze({target: true}), useId: 'original-target'});
  const observe = (current, entries, options = {}) => driver.observeTargets({...describeOptions, current, entries,
    authorizationForRow: () => target, ...options});
  const finalize = logical => driver.finalizeRequest({request: logical.request, requestTag: cid('c')});
  const send = (current, request, changes = {}) => driver.send({member, current, request,
    credential: {binding: {}}, authorization: {grant: {}, useId: 'one-write',
      scope: {resourceOrigin: config.origin, connectorRegistration: 'kintone', operation: 'kintone:records:update'}},
    async callResource(input) {state.writes.push(input); if (state.writeError) throw state.writeError; return state.response;},
    ...changes});
  const recover = (entry, requestCid) => ({maxRows: config.maxRows, durable: {connectorRecovery: [{memberIndex: 0, ...entry}]},
    recorded: {members: [{claims: [{canonicalRequestCid: requestCid}]}]}, members: [member],
    body: {effects: [{changes: [{after: {value: structuredClone(value)}, target_row_identity: identity}]}]}, requestTags: [[cid('c')]]});
  return {native, state, config, driver, member, target, describeOptions, describe, prepare, observe, finalize, send, recover};
}

test('kintone driver preserves same-issued metadata and distinct serial original target reads before final PUT', async () => {
  const f = fixture(), current = await f.describe();
  const logical = [identity, '9007199254740996'].map(id => f.prepare(current, id));
  assert.throws(() => f.finalize(logical[0]), {code: 'KintoneUpdateFinalizationUnavailable'});
  const grants = logical.map((_, row) => Object.freeze({grant: {row}, useId: 'target-' + row})), uses = [];
  const rows = await f.observe(current, logical, {authorizationForRow(row) {uses.push(row); return grants[row];}});
  assert.deepEqual(rows.map(row => row.identity), [identity, '9007199254740996']);
  assert.deepEqual(rows.map(row => row.before.$id), [identity, '9007199254740996']);
  assert.deepEqual(uses, [0,1]);
  assert.deepEqual(f.state.reads.map(read => read.slot), ['schema',
    'schema-before', 'target', 'schema-after', 'schema-before', 'target', 'schema-after']);
  assert.deepEqual(f.state.reads.filter(read => read.slot === 'target').map(read => read.authorization), grants);
  assert(f.state.grants.every(grant => grant.resource === 'inquiries-form' &&
    grant.operation === 'kintone:form:read' && grant.maxUses === 1));
  for (const prepared of logical) {
    const final = f.finalize(prepared); f.driver.assertRequestFinalized(final.request, cid('c'));
    assert.equal(f.driver.capabilityRequestCid(final.request), prepared.requestCid);
  }
  const count = f.state.reads.length;
  await assert.rejects(f.observe(current, [...logical, logical[0]]), {code: 'InvalidKintoneUpdateRequests'});
  assert.equal(f.state.reads.length, count); assert.equal(f.state.writes.length, 0);
});

test('kintone driver keeps fresh Form denial, complete schema drift, target revision and current identity fences', async () => {
  const denied = fixture(); denied.state.denied = true;
  await assert.rejects(denied.describe(), {code: 'KintoneFormReadDenied'});
  assert.equal(denied.state.reads.length, 0);
  for (const changed of ['schema-after', 'target']) {
    const f = fixture(), current = await f.describe(), logical = f.prepare(current);
    await f.observe(current, [logical]); const final = f.finalize(logical);
    f.state.readHook = (slot, target) => {
      if (slot !== changed) return;
      if (slot === 'schema-after') {const changedForm = structuredClone(form);
        changedForm.properties.Computed.expression = 'changed'; target.body = bytes(changedForm);}
      else target.body = observation({rev: '9007199254740999'}).body;
    };
    await assert.rejects(f.observe(current, [final]), error => error.observations.length >= 2);
    assert.equal(f.state.writes.length, 0);
  }
  const f = fixture(), current = await f.describe();
  assert.throws(() => f.prepare({...current}), {code: 'ForeignKintoneUpdateCurrent'});
  const logical = f.prepare(current), abort = new AbortController(); abort.abort();
  await assert.rejects(f.observe(current, [logical], {signal: abort.signal}), error => error.cause === abort.signal.reason);
  assert.deepEqual(f.state.reads.map(read => read.slot), ['schema']);
});

test('kintone driver captures original ports before reentry and retains rejected physical read observations', async () => {
  const f = fixture();
  f.config.site.issueReadGrant = () => assert.fail('replacement issuer');
  f.config.authorization.authorize = () => assert.fail('replacement authorization');
  const current = await f.describe(), logical = f.prepare(current);
  f.state.readHook = (slot, target) => {if (slot === 'target') target.accepted = false;};
  await assert.rejects(f.observe(current, [logical]), error => error.code === 'KintoneUpdateReadRejected' &&
    error.observations.length === 2 && error.observations[1].accepted === false);
  assert.equal(f.state.writes.length, 0);
});

test('kintone driver sends one exact guarded PUT and projects only actual native correlated success', async () => {
  const f = fixture(), current = await f.describe(), logical = f.prepare(current);
  await f.observe(current, [logical]); const final = f.finalize(logical);
  f.driver.recheckRequests({member: f.member, entries: [final], current});
  const sent = await f.send(current, final.request), projected = f.driver.project({request: final.request, observation: sent.observation});
  assert.equal(projected.kind, 'typed-success-response');
  assert.deepEqual(projected.outcome, {state: 'applied', result: {record_id: identity, revision: '9007199254740995'}});
  assert.equal(f.state.writes.length, 1);
  const operation = f.state.writes[0].operations.get('kintone:records:update');
  assert.equal(operation.method, 'PUT'); assert.equal(operation.path, '/k/v1/records.json');
  assert.deepEqual(JSON.parse(operation.body), {app: '12', records: [{id: identity, revision,
    record: {Subject: {value: 'next 東京'}, Tags: {value: ['red', 'red']}}}], upsert: false});
  for (const bad of [{statusCode: 503, body: bytes({})}, {statusCode: 200, body: bytes({records: []})},
    {statusCode: 200, body: bytes({records: [{id: '9007199254740992', revision: '8'}]})}]) {
    assert.equal(f.driver.project({request: final.request, observation: bad}).kind, 'unclassified-response');
  }
  await assert.rejects(f.send(current, final.request, {authorization: {scope: {resourceOrigin: 'https://other.invalid'}}}),
    {code: 'ForeignKintoneUpdateOrigin'});
  assert.equal(f.state.writes.length, 1);
});

test('kintone driver does not discard an observed write on late abort or retry a lost response', async () => {
  const f = fixture(), current = await f.describe(), logical = f.prepare(current);
  await f.observe(current, [logical]); const final = f.finalize(logical), abort = new AbortController();
  const result = await f.send(current, final.request, {signal: abort.signal,
    async callResource() {abort.abort(); return response();}});
  assert.equal(result.observation.statusCode, 200);
  const lost = Object.assign(new Error('original response lost'), {code: 'ComponentReplyLost'});
  f.state.writeError = lost;
  await assert.rejects(f.send(current, final.request), error => error === lost);
  assert.equal(f.state.writes.length, 1, 'one explicit send call; no automatic retry');
});

test('kintone driver cold restoration binds original claims, values, member indexes and complete request without I/O', async () => {
  const warm = fixture(), current = await warm.describe(), logical = warm.prepare(current);
  await warm.observe(current, [logical]); const final = warm.finalize(logical);
  const entry = warm.driver.recoveryEntry({member: warm.member, current, entries: [final]});
  const cold = fixture(), input = cold.recover(entry, final.requestCid), restored = cold.driver.recoverRequests(input);
  const request = restored.requests[0][0];
  assert.equal(cold.driver.requestCid(request), final.requestCid);
  cold.driver.assertRequestFinalized(request, cid('c'));
  assert.deepEqual(cold.driver.requestFacts(request), {value, target: identity});
  for (const mutate of [x => {x.recorded.members[0].claims[0].canonicalRequestCid = cid('8');},
    x => {x.requestTags[0][0] = cid('9');}, x => {x.memberIndexes = [0,0];},
    x => {x.body.effects[0].changes[0].after.value.Subject = 'different';},
    x => {x.durable.connectorRecovery.push({...x.durable.connectorRecovery[0]});},
    x => {const saved = JSON.parse(x.durable.connectorRecovery[0].wire); saved.binding.appId = '13';
      const wire = encode(saved); x.durable.connectorRecovery[0] = {...entry, wire,
        observationCid: 'sha256:' + createHash('sha256').update(wire).digest('hex')};},
  ]) {const changed = cold.recover(entry, final.requestCid); mutate(changed);
    assert.throws(() => cold.driver.recoverRequests(changed));}
  assert.equal(cold.state.decisions.length, 0); assert.equal(cold.state.reads.length, 0); assert.equal(cold.state.writes.length, 0);
});

test('kintone driver delegates only the actual matching original Checkpoint physical binding', () => {
  const f = fixture(), physical = {version: KINTONE_UPDATE_TARGET_VERSION, site_binding_cid: cid('a'),
    generation_cid: cid('b'), effect_id: f.member.effectId, member_index: 0,
    mapping_ref: f.member.mapping.mappingRef, mapping_cid: f.member.mapping.mappingCid, resource: 'inquiries',
    effect_kind: 'update', key: '$id', fields: ['Computed', 'Subject', 'Tags']};
  const decision = recordCheckpointApproval(Object.freeze({componentDecision: true}), {physicalBindings: [physical]});
  assert.strictEqual(f.driver.admitTargetReadApproval({member: f.member, decision}), decision);
  assert.strictEqual(f.state.admitted[0].binding, physical);
  assert.equal(f.state.admitted[0].operation, 'kintone:records:target-read');
  assert.throws(() => f.driver.admitTargetReadApproval({member: f.member, decision: {...decision}}),
    {code: 'KintoneTargetReadApprovalNotAdmitted'});
  const changed = recordCheckpointApproval(Object.freeze({}), {physicalBindings: [{...physical, key: 'record_number'}]});
  assert.throws(() => f.driver.admitTargetReadApproval({member: f.member, decision: changed}),
    {code: 'KintoneTargetReadApprovalNotAdmitted'});
  assert.equal(f.state.admitted.length, 1); assert.equal(f.state.grants.length, 0);
});

test('kintone cold member refuses nested foreign binding before canonical recursion or I/O', async () => {
  const warm = fixture(), current = await warm.describe(), logical = warm.prepare(current);
  await warm.observe(current, [logical]); const final = warm.finalize(logical);
  const entry = warm.driver.recoveryEntry({member: warm.member, current, entries: [final]});
  const changed = JSON.parse(entry.wire); let nested = 'foreign';
  for (let index = 0; index < 200; index++) nested = {nested};
  changed.binding.appId = nested;
  const wire = JSON.stringify(changed), cold = fixture(), input = cold.recover({...entry, wire,
    observationCid: 'sha256:' + createHash('sha256').update(wire).digest('hex')}, final.requestCid);
  assert.throws(() => cold.driver.recoverRequests(input), {code: 'InvalidKintoneUpdateRecovery'});
  assert.equal(cold.state.decisions.length, 0); assert.equal(cold.state.reads.length, 0); assert.equal(cold.state.writes.length, 0);
});


test('kintone total targets follow the admitted caller bound while each native PUT remains one record', async () => {
  // Explicit per-call row DATA below is not itself admission or authority.
  // The shared owner test separately observes the same adopted Plan bound.
  const f = fixture({maxRows: 101, maxRecoveryBytes: 1000000}), current = await f.describe();
  const ids = Array.from({length: 101}, (_, index) => String(BigInt(identity) + BigInt(index)));
  const logical = ids.map(id => f.prepare(current, id));
  const rows = await f.observe(current, logical);
  assert.deepEqual(rows.map(row => row.identity), ids);
  const finals = logical.map(entry => f.finalize(entry));
  f.driver.recheckRequests({member: f.member, entries: finals, current});
  for (const [index, entry] of finals.entries()) {
    f.state.response = {useCid: cid('1'), statusCode: 200, body: bytes({records: [{id: ids[index], revision: '9007199254740995'}]})};
    const sent = await f.send(current, entry.request);
    const result = f.driver.project({request: entry.request, observation: sent.observation});
    assert.deepEqual(result.outcome, {state: 'applied', result: {record_id: ids[index], revision: '9007199254740995'}});
    const request = f.state.writes[index].operations.get('kintone:records:update');
    const body = JSON.parse(request.body);
    assert.equal(body.records.length, 1);
    assert.equal(body.records[0].id, ids[index]);
    assert.equal(body.records[0].revision, revision);
    assert.equal(body.upsert, false);
  }
  assert.equal(f.state.writes.length, 101);
  const saved = f.driver.recoveryEntry({member: f.member, current, entries: finals});
  const cold = fixture({maxRows: 101, maxRecoveryBytes: 1000000});
  const input = {maxRows: 101, durable: {connectorRecovery: [{memberIndex: 0, ...saved}]},
    members: [cold.member], requestTags: [finals.map(() => cid('c'))],
    recorded: {members: [{claims: finals.map(entry => ({canonicalRequestCid: entry.requestCid}))}]},
    body: {effects: [{changes: ids.map(id => ({after: {value}, target_row_identity: id}))}]}};
  const recovered = cold.driver.recoverRequests(input);
  assert.deepEqual(recovered.requests[0].map(request => cold.driver.requestFacts(request).target), ids);
  assert.equal(cold.state.reads.length + cold.state.writes.length, 0);
  assert.throws(() => cold.driver.recoverRequests({...input, maxRows: 100}), {code: 'InvalidKintoneUpdateRecovery'});
  assert.throws(() => f.driver.recheckRequests({member: f.member, entries: [...logical, logical[0]], current}),
    {code: 'InvalidKintoneUpdateRequests'});
  const missing = fixture(); delete missing.describeOptions.maxRows;
  await assert.rejects(missing.describe(), {code: 'InvalidKintoneUpdateRequests'});
  assert.equal(missing.state.reads.length, 0);
});
