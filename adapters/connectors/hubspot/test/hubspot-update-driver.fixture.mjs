// Real provider constructors/decoders with explicit Account/Site/physical
// ports. The common Host owns actual approval, Ledger claims and cleanup;
// these tests do not manufacture their acceptance or send to a real service.
import assert from 'node:assert/strict';
import test from 'node:test';
import {createHash} from 'node:crypto';
import {recordCheckpointApproval} from '../../../host-common/checkpoint-approval.mjs';
import {credentialInvocationBindingKeys} from '../../../host-common/credential-scope-fields.generated.mjs';
import {hubspotUpdateDriver, HUBSPOT_UPDATE_TARGET_VERSION} from '../host/hubspot-update-driver.mjs';
import {hubspotUpdateRequestFixture} from './hubspot-update-request.fixture.mjs';

const cid = unit => 'sha256:' + unit.repeat(64);
const origin = 'https://hubspot.invalid', id = '9007199254740993', tag = cid('c');
const value = Object.freeze({amount: '9007199254740993.0100000000', tags: ['a', 'b']});
const properties = {results: [
  {name: 'amount', type: 'number', fieldType: 'number', calculated: false, modificationMetadata: {readOnlyValue: false}},
  {name: 'tags', type: 'enumeration', fieldType: 'checkbox', calculated: false,
    modificationMetadata: {readOnlyValue: false}, options: [{value: 'a'}, {value: 'b'}]},
  {name: 'actql_request_id', type: 'string', fieldType: 'text', calculated: false, modificationMetadata: {readOnlyValue: false}},
]};
const response = () => ({useCid: cid('1'), statusCode: 200, accepted: true,
  body: Buffer.from(JSON.stringify({status: 'COMPLETE', results: [{id, archived: false, properties: {}}]}))});
const canonical = data => data !== null && typeof data === 'object'
  ? Array.isArray(data) ? '[' + data.map(canonical).join(',') + ']'
    : '{' + Object.keys(data).sort().map(key => JSON.stringify(key) + ':' + canonical(data[key])).join(',') + '}'
  : JSON.stringify(data);
const rehash = entry => ({...entry, observationCid: 'sha256:' + createHash('sha256').update(entry.wire).digest('hex')});
function fixture(moon, {maxRows = 10, responseRows = 10} = {}) {
  const native = hubspotUpdateRequestFixture(moon), selected = Object.freeze({...native.installed,
    fields: Object.freeze(['amount', 'tags'])});
  const member = Object.freeze({...native.member, effectId: 'update-companies', memberIndex: 0});
  const state = {gateCalls: [], grants: [], physical: [], writes: [], denied: undefined, admit: [], targetUses: [],
    response: response(), writeError: undefined};
  const site = {
    issueReadGrant(facts) {
      assert.strictEqual(this, site); state.grants.push(facts);
      return Object.freeze({grant: Object.freeze({original: state.grants.length}),
        scope: Object.freeze({operation: facts.operation, resourceOrigin: origin})});
    },
    admitCheckpointEffectTargetRead(decision, binding, operation) {
      assert.strictEqual(this, site); state.admit.push({decision, binding, operation}); return decision;
    },
  };
  const authorization = {async authorize(boundary, tuple, options) {
    assert.strictEqual(this, authorization); assert.equal(boundary, 'acquisition');
    assert.match(options.subjectCid, /^sha256:/u);
    state.gateCalls.push(tuple); return Object.freeze({action: tuple.resource === state.denied ? 'deny' : 'dispatch', tuple});
  }};
  const readLimits = {maxResponseBytes: 30000, maxRequestBytes: 10000, maxNodes: 3000, maxDepth: 24,
    maxProperties: 100, maxNameUnits: 256, maxRows: responseRows, maxColumns: 10, maxCursorUnits: 256,
    maxValueNodes: 3000, maxValueTextBytes: 8192, maxOutputBytes: 10000, maxOutputNodes: 3000,
    maxOutputDepth: 24, maxRequestNodes: 3000, maxRequestDepth: 24};
  const writeLimits = {maxResponseBytes: 30000, maxNodes: 3000, maxDepth: 24, maxRows: 1, maxRequestBytes: 20000};
  const config = {moon, site, authorization, connection: 'hubspot:hubspot', origin, portalId: '7', connectorId: 'hubspot',
    siteBindingCid: cid('a'), generationCid: cid('b'), installedFor: () => selected,
    metadataResources: {account: 'account', properties: 'properties'}, requestLimits: native.limits,
    readLimits, writeLimits, maxRows, maxMembers: 5, maxRecoveryBytes: 200000};
  const driver = hubspotUpdateDriver(config);
  const describeOptions = {member, runInvocationCid: cid('d'), dispatchRequestCid: cid('e'),
    controlConstruction(receiver, method, args) {return Reflect.apply(method, receiver, args);},
    async readChild(authorization, input, row, slot, project) {
      assert.strictEqual(input.grant, authorization.grant);
      state.physical.push({authorization, input, row, slot});
      await input.currentBeforeSend();
      const targetId = slot === 'target' ? JSON.parse([...input.operations.values()][0].body).inputs[0].id : id;
      const response = {accepted: true, statusCode: 200, body: Buffer.from(JSON.stringify(
        slot === 'account' ? {portalId: 7} : slot === 'target'
          ? {status: 'COMPLETE', results: [{id: targetId, archived: false, updatedAt: '2026-11-07T00:00:00.000Z',
            properties: {amount: '1', tags: 'a'}}]} : properties))};
      state.readResponseHook?.(slot, response);
      return project(response);
    }};
  const describe = () => driver.describe(describeOptions);
  const prepare = (current, selector = id) => {
    const logical = driver.prepareRequest({member, current, value, selector});
    return {logical, finalized: driver.finalizeRequest({member, request: logical.request, requestTag: tag})};
  };
  const send = (current, request, changed = {}) => driver.send({member, current, request,
    credential: {binding: {}}, authorization: {grant: {}, useId: 'original-write',
      scope: Object.freeze({...Object.fromEntries(credentialInvocationBindingKeys.map(key => [key, 'same'])),
        resourceOrigin: origin, operation: 'hubspot:objects:batch-update'})},
    async callResource(input) {
      state.writes.push(input);
      if (state.writeError) throw state.writeError;
      return state.response;
    }, ...changed});
  const recover = entry => ({durable: {connectorRecovery: [{memberIndex: 0, ...entry}]},
    members: [member], body: {effects: [{changes: [{after: {value}, target_row_identity: id}]}]},
    recorded: {members: [{claims: [{canonicalRequestCid: entry.expectedRequestCid}]}]}, requestTags: [[tag]]});
  return {driver, member, state, config, describeOptions, selected, prepare, send, describe, recover};
}

export function registerHubSpotUpdateDriverTests(moon) {
  test('HubSpot installed one-response decoder preserves two serial targets under the original member row bound', async () => {
    const decoderBounds = [];
    const counted = {...moon, hubspotProjectRecordRead(...args) {
      decoderBounds.push(args[5]); return moon.hubspotProjectRecordRead(...args);
    }};
    const f = fixture(counted, {maxRows: 2, responseRows: 1}), current = await f.describe();
    const ids = [id, '9007199254740994'];
    const entries = ids.map(selected => f.prepare(current, selected).finalized);
    const grants = ids.map((_, row) => Object.freeze({grant: Object.freeze({row}), useId: 'target-' + row}));
    const options = {member: f.member, entries, current, readChild: f.describeOptions.readChild,
      authorizationForRow(row) {f.state.targetUses.push(row); return grants[row];}};
    const rows = await f.driver.observeTargets(options);
    assert.deepEqual(rows.map(row => row.identity), ids);
    assert.deepEqual(decoderBounds, [1, 1]);
    assert.deepEqual(f.state.targetUses, [0, 1]);
    assert.deepEqual(f.state.physical.filter(p => p.slot === 'target').map(p => p.authorization), grants);
    assert.deepEqual(f.state.physical.map(p => p.slot), ['account', 'schema',
      'account', 'schema-before', 'target', 'schema-after', 'account', 'schema-before', 'target', 'schema-after']);
    const before = f.state.physical.length;
    await assert.rejects(f.driver.observeTargets({...options, entries: [...entries, entries[0]]}),
      {code: 'ForeignHubSpotUpdateCurrent'});
    assert.equal(f.state.physical.length, before);
    const bad = fixture(counted, {maxRows: 2, responseRows: 1}), badCurrent = await bad.describe();
    const entry = bad.prepare(badCurrent).finalized;
    bad.state.readResponseHook = (slot, response) => {
      if (slot !== 'target') return;
      const body = JSON.parse(response.body); body.results.push(body.results[0]);
      response.body = Buffer.from(JSON.stringify(body));
    };
    await assert.rejects(bad.driver.observeTargets({member: bad.member, entries: [entry], current: badCurrent,
      readChild: bad.describeOptions.readChild, authorizationForRow: () => grants[0]}));
    assert.equal(bad.state.physical.at(-1).slot, 'target');
    assert.equal(f.state.writes.length, 0); assert.equal(bad.state.writes.length, 0);
  });

  test('HubSpot driver keeps the original Site and Account methods captured before later reentry', async () => {
    const f = fixture(moon);
    f.config.site.issueReadGrant = () => {throw new Error('Substituted Site issuer');};
    f.config.authorization.authorize = () => {throw new Error('Substituted Account gate');};
    const current = await f.describe();
    const {finalized} = f.prepare(current);
    const originalTarget = Object.freeze({grant: {}, useId: 'original-target'});
    const rows = await f.driver.observeTargets({member: f.member, entries: [finalized], current,
      readChild: f.describeOptions.readChild, authorizationForRow: () => originalTarget});
    assert.equal(rows[0].identity, id); assert.equal(f.state.grants.length, 5);
    assert.equal(f.state.writes.length, 0);
  });

  test('HubSpot row driver preserves separate metadata grants and original same-row target authorization', async () => {
    const f = fixture(moon), current = await f.describe(), {finalized} = f.prepare(current);
    const originalTarget = Object.freeze({grant: {}, useId: 'same-target'});
    const rows = await f.driver.observeTargets({member: f.member, entries: [finalized], current,
      readChild: f.describeOptions.readChild,
      authorizationForRow(row) {f.state.targetUses.push(row); return originalTarget;}});
    assert.deepEqual(f.state.targetUses, [0]); assert.equal(rows[0].identity, id);
    assert.deepEqual(rows[0].before, {amount: '1.0000000000', tags: ['a']});
    assert.deepEqual(f.state.grants.map(g => [g.resource, g.operation, g.maxUses]), [
      ['account', 'hubspot:account:details', 33], ['properties', 'hubspot:properties:read', 63],
      ['account', 'hubspot:account:details', 33], ['properties', 'hubspot:properties:read', 63],
      ['properties', 'hubspot:properties:read', 63],
    ]);
    assert.strictEqual(f.state.physical.find(p => p.slot === 'target').authorization, originalTarget);
    assert(f.state.gateCalls.every(tuple => ['account', 'properties'].includes(tuple.resource)));
    assert.equal(new Set(f.state.physical.map(p => p.input.useId)).size, 6);
    assert.equal(f.state.writes.length, 0);
  });

  test('HubSpot row driver denied metadata cannot borrow the target approval or send any request', async () => {
    for (const denied of ['account', 'properties']) {
      const f = fixture(moon); f.state.denied = denied;
      await assert.rejects(f.describe(), {code: 'HubSpotMetadataReadDenied'});
      assert.equal(f.state.physical.length, denied === 'account' ? 0 : 1);
      assert.equal(f.state.grants.length, denied === 'account' ? 0 : 1);
      assert.equal(f.state.writes.length, 0); assert.equal(f.state.admit.length, 0);
    }
  });

  test('HubSpot row driver sends one exact finalized batch only and projects a complete correlated Native success', async () => {
    const f = fixture(moon), current = await f.describe(), {logical, finalized} = f.prepare(current);
    f.driver.assertRequestFinalized(finalized.request, tag);
    f.driver.recheckRequests({member: f.member, entries: [finalized], current});
    const sent = await f.send(current, finalized.request);
    assert.equal(f.state.writes.length, 1);
    const [[operation, http]] = [...f.state.writes[0].operations];
    assert.equal(operation, 'hubspot:objects:batch-update'); assert.equal(http.method, 'POST');
    assert.equal(http.path, '/crm/v3/objects/companies/batch/update');
    assert.deepEqual(JSON.parse(http.body), {inputs: [{id, objectWriteTraceId: logical.requestCid,
      properties: {actql_request_id: tag, amount: value.amount, tags: 'a;b'}}]});
    assert.equal(f.driver.capabilityRequestCid(finalized.request), logical.requestCid);
    assert.deepEqual(f.driver.project({request: finalized.request, observation: sent.observation}), {
      kind: 'typed-success-response', outcome: {state: 'applied', action: 'updated', result: {id}}});
    assert.throws(() => f.driver.prepareRequest({member: f.member, current: {...current}, value, selector: id}),
      {code: 'ForeignHubSpotUpdateCurrent'});
  });

  test('HubSpot row driver keeps transport errors and incomplete replies unclassified without retry', async () => {
    const f = fixture(moon), current = await f.describe(), {finalized} = f.prepare(current);
    const cause = new Error('Original reply lost'); f.state.writeError = cause;
    await assert.rejects(f.send(current, finalized.request), error => error === cause);
    assert.equal(f.state.writes.length, 1); f.state.writeError = undefined;
    for (const [statusCode, body] of [[503, '{}'], [200, '{'], [200, '{"status":"PENDING","results":[]}'],
      [200, '{"status":"COMPLETE","results":[{"id":"other","archived":false,"properties":{}}]}']]) {
      assert.deepEqual(f.driver.project({request: finalized.request, observation: {
        statusCode, body: Buffer.from(body)}}), {kind: 'unclassified-response'});
    }
    assert.equal(f.state.writes.length, 1);
    await assert.rejects(f.send(current, finalized.request, {authorization: {scope: {resourceOrigin: 'https://foreign.invalid'}}}),
      {code: 'ForeignHubSpotUpdateOrigin'});
    assert.equal(f.state.writes.length, 1);
  });

  test('HubSpot cold row driver reconstructs exact claimed requests from fresh Native originals without IO', async () => {
    const first = fixture(moon), current = await first.describe(), {finalized} = first.prepare(current);
    const entry = first.driver.recoveryEntry({member: first.member, entries: [finalized]});
    const second = fixture(moon), input = second.recover({...entry, expectedRequestCid: finalized.requestCid});
    const restored = second.driver.recoverRequests(input);
    assert.equal(restored.requests.length, 1); assert.equal(restored.requests[0].length, 1);
    assert.equal(second.driver.requestCid(restored.requests[0][0]), finalized.requestCid);
    assert.deepEqual(second.driver.requestFacts(restored.requests[0][0]), {value, target: id});
    assert.equal(second.driver.recoveryEntry({member: second.member,
      entries: [{request: restored.requests[0][0], requestCid: finalized.requestCid}]}).wire, entry.wire);
    assert.equal(second.state.gateCalls.length, 0); assert.equal(second.state.physical.length, 0);
    assert.equal(second.state.writes.length, 0);
    assert.throws(() => second.driver.requestCid(finalized.request), {code: 'ForeignHubSpotUpdateRequest'});
    const selected = second.driver.recoverMemberRequests({...input, memberIndexes: [0]});
    assert.equal(second.driver.requestCid(selected.requests[0][0]), finalized.requestCid);
  });

  test('HubSpot cold row driver refuses changed approved value target dispatch binding and claim rather than sending', async () => {
    const first = fixture(moon), current = await first.describe(), {finalized} = first.prepare(current);
    const entry = first.driver.recoveryEntry({member: first.member, entries: [finalized]});
    for (const mutate of [
      input => {input.body.effects[0].changes[0].after.value = {...value, amount: '2.0000000000'};},
      input => {input.body.effects[0].changes[0].target_row_identity = 'different';},
      input => {input.requestTags[0][0] = cid('f');},
      input => {input.recorded.members[0].claims[0].canonicalRequestCid = cid('f');},
      input => {const e = input.durable.connectorRecovery[0], b = JSON.parse(e.wire);
        b.binding.portalId = '8'; e.wire = canonical(b); Object.assign(e, rehash(e));},
      input => {input.durable.connectorRecovery.push(input.durable.connectorRecovery[0]);},
      input => {input.memberIndexes = [0, 0];},
    ]) {
      const f = fixture(moon), input = f.recover({...entry, expectedRequestCid: finalized.requestCid}); mutate(input);
      assert.throws(() => f.driver.recoverRequests(input));
      assert.equal(f.state.gateCalls.length, 0); assert.equal(f.state.physical.length, 0); assert.equal(f.state.writes.length, 0);
    }
  });

  test('HubSpot driver delegates only the original Checkpoint binding for this exact installed member', () => {
    const f = fixture(moon), physical = {version: HUBSPOT_UPDATE_TARGET_VERSION,
      site_binding_cid: cid('a'), generation_cid: cid('b'), effect_id: f.member.effectId,
      member_index: 0, mapping_ref: f.selected.mappingRef, mapping_cid: f.selected.mappingCid,
      resource: 'companies', effect_kind: 'update', key: 'id', fields: ['amount', 'tags']};
    const decision = recordCheckpointApproval(Object.freeze({componentDecision: true}), {physicalBindings: [physical]});
    assert.strictEqual(f.driver.admitTargetReadApproval({member: f.member, decision}), decision);
    assert.strictEqual(f.state.admit[0].binding, physical);
    assert.equal(f.state.admit[0].operation, 'hubspot:objects:batch-read');
    assert.throws(() => f.driver.admitTargetReadApproval({member: f.member, decision: {...decision}}),
      {code: 'HubSpotTargetReadApprovalNotAdmitted'});
    const changed = recordCheckpointApproval(Object.freeze({}), {physicalBindings: [{...physical, fields: ['tags']}]});
    assert.throws(() => f.driver.admitTargetReadApproval({member: f.member, decision: changed}),
      {code: 'HubSpotTargetReadApprovalNotAdmitted'});
    assert.equal(f.state.admit.length, 1); assert.equal(f.state.grants.length, 0); assert.equal(f.state.writes.length, 0);
  });
}
