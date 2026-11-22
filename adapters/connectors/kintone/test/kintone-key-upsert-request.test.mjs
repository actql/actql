// The same generated Common runtime executes both branch codecs and the cold
// restoration. This fixture exercises request DATA before the physical owner.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import test from 'node:test';
import * as common from '../../../../_build/js/debug/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeField, runtimeUnboxedReferenceOption} from '../../../host-common/compiler-binding.generated.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import {selectInstalledEffectCredentialOperation, selectInstalledEffectWriteBranch}
  from '../../../host-node/installed-effect-plan.mjs';
import {captureKintoneEffectPlanRecipeBuilder} from '../host/kintone-effect-plan.mjs';
import {createKintoneKeyUpsertRequestAdapter} from '../host/kintone-key-upsert-request.mjs';
import {kintoneUpdateDriver} from '../host/kintone-update-driver.mjs';
import {form, cid, encode, bytes, identity as nativeId, revision, policy} from './kintone-update.fixture.mjs';

const key = 'Key 東京';
const app = '12';
const input = {Subject: 'next 東京', Tags: ['red', 'red']};
const keyedForm = {revision: form.revision, properties: {
  Subject: {...form.properties.Subject, required: true},
  Tags: {...form.properties.Tags, required: false},
  Computed: {...form.properties.Computed, required: false},
  CustomerKey: {type: 'SINGLE_LINE_TEXT', code: 'CustomerKey', expression: '', unique: true, required: true},
}};
const present = {records: [{
  $id: {type: '__ID__', value: nativeId}, $revision: {type: '__REVISION__', value: revision},
  CustomerKey: {type: 'SINGLE_LINE_TEXT', value: key},
  Subject: {type: 'SINGLE_LINE_TEXT', value: 'before'},
  Tags: {type: 'MULTI_SELECT', value: ['red']},
  Computed: {type: 'SINGLE_LINE_TEXT', value: 'server'},
}], totalCount: '1'};
const absent = {records: [], totalCount: '0'};
const observation = value => ({statusCode: 200, body: bytes(value)});

function fixture() {
  const catalog = checked(common.clientProgramKintoneProjectForm(bytes(keyedForm), app,
    common.clientProgramKintoneFormLimits(16384, 8000, 32, 16, 512)));
  const limits = common.clientProgramKintoneDeclarationLimits(65536, 8000, 32, 4, 16);
  const declaration = checked(common.clientProgramKintoneDeclareRecords(catalog, undefined,
    ['Subject', 'Tags', 'Computed', 'CustomerKey'], 'kintone', 'kintone/0.1', 'inquiries',
    common.clientProgramKintoneValueLimits(8, 512, 8000, 32, 16384), limits));
  const resource = 'inquiries', keyField = 'CustomerKey';
  const sources = [{target: 'Subject', field: 'subject', null_behavior: 'reject'},
    {target: 'Tags', field: 'tags', null_behavior: 'reject'}];
  const units = resource.length + sources.reduce((sum, fields) =>
    sum + fields.target.length + fields.field.length + fields.null_behavior.length, 0);
  const capacity = runtimeUnboxedReferenceOption(common.clientProgramKintoneKeyUpsertMappingConstructionCapacity(
    declaration, keyField, sources.length, BigInt(units), limits));
  assert(capacity);
  const quote = common.clientProgramSerializationCapacityBytes(capacity);
  assert(runtimeField(quote, 0) > 0n && runtimeField(quote, 1) > runtimeField(quote, 0));
  const mapping = checked(common.clientProgramKintonePrepareKeyUpsertMapping(declaration, resource,
    keyField, sources, limits));
  const calls = Object.create(null);
  const moon = {...common};
  for (const name of ['clientProgramKintoneLookupResponse', 'clientProgramKintoneRestoreKeyUpsertExecution']) {
    moon[name] = (...args) => {
      calls[name] = (calls[name] ?? 0) + 1;
      return common[name](...args);
    };
  }
  const options = {moon, declaration, mapping, origin: 'https://tenant.example.test', appId: app,
    connectorId: 'kintone', resource, siteBindingCid: cid('a'), generationCid: cid('b'),
    guestSpaceId: '23', limits: policy};
  return {adapter: createKintoneKeyUpsertRequestAdapter(options), calls, options};
}

test('keyed UPSERT quotes the original lookup and distinct approved write branches', () => {
  const {options, adapter} = fixture();
  const prepare = captureKintoneEffectPlanRecipeBuilder({moon: options.moon, kind: 'upsert'});
  const plan = prepare({mapping: options.mapping, fields: Object.freeze(['Computed', 'CustomerKey', 'Subject', 'Tags']),
    formResource: 'inquiries-form', bindingUnits: 1000, maxTargetBytes: adapter.binding.path.length,
    credentialSite: {construction: {scope: {connectorRegistration: 'kintone', resourceOrigin: options.origin},
      issuer: {keyId: 'component'}, limits: {maxSecretBytes: 256}}}, limits: options.limits,
    inputLimits: {body: {maxBytes: 2048, maxNodes: 8000, maxDepth: 32},
      preview: {maxWireBytes: 65536, maxNodes: 8000, maxDepth: 32}}, maxRecoveryBytes: 65536});
  assert.equal(plan.memberOperations.length, 2);
  assert.equal(plan.credentialOperations.length, 11);
  assert.equal(new Set(plan.credentialOperations.map(slot => slot.operationIndex)).size, 11);
  for (const phase of ['capture', 'apply', 'resume']) {
    assert.equal(selectInstalledEffectCredentialOperation(plan, phase + '-describe', 'schema'), undefined);
    for (const role of ['schema-before', 'target', 'schema-after']) {
      const slot = selectInstalledEffectCredentialOperation(plan, phase + '-target', role);
      const formRead = role !== 'target';
      assert.equal(slot.resource, formRead ? 'inquiries-form' : undefined);
      assert.equal(plan.rowOperations[slot.operationIndex].operation,
        formRead ? 'kintone:form:read' : 'kintone:records:target-read');
      const body = bytes(formRead ? keyedForm : present);
      assert(slot.responseExtent(body.byteLength, body));
      assert.throws(() => slot.responseExtent(body.byteLength - 1, body), {code: 'KintoneEffectRecipeUnavailable'});
    }
  }
  for (const [presence, guard, operation] of [['absent', 'not_applicable', 'create'], ['present', 'version', 'update']]) {
    const selected = selectInstalledEffectWriteBranch(plan, 'upsert', {before: {state: presence}, target_guard: {state: guard}});
    assert.equal(plan.rowOperations[selected.operationIndex].operation, 'kintone:records:' + operation);
    assert.throws(() => selectInstalledEffectWriteBranch(plan, 'upsert', {before: {state: presence}, target_guard: {state: 'none'}}),
      {code: 'InvalidInstalledEffectWriteBranch'});
  }
  assert(plan.recoveryConstruction.inputExtent('{}', [{memberIndex: 0, wire: '{"requests":[]}'}], 0));
  assert.throws(() => plan.recoveryConstruction.inputExtent('{}', [{memberIndex: 0, wire: 'x'.repeat(65537)}], 0),
    {code: 'KintoneEffectRecipeUnavailable'});
});

for (const [name, row] of [['create', absent], ['update', present]]) {
  test('keyed UPSERT retains the exact ' + name + ' branch across finalized request and cold restore', () => {
    const f = fixture(), adapter = f.adapter;
    const value = structuredClone(input), proposal = adapter.prepare({value, selector: key});
    value.Tags.push('changed');
    assert.deepEqual(adapter.requestFacts(proposal.request), {value: input, target: key});
    assert.throws(() => adapter.finalize({request: proposal.request, requestTag: cid('c')}),
      {code: 'KintoneKeyUpsertFinalizationUnavailable'});
    assert.deepEqual(JSON.parse(adapter.targetReadBody(proposal.request)), {
      app, fields: ['$id', '$revision', 'Subject', 'Tags', 'Computed', 'CustomerKey'],
      query: 'CustomerKey = "Key 東京" limit 2', totalCount: true,
    });
    adapter.recheckForm(proposal.request, observation(keyedForm));
    const target = adapter.projectTarget(proposal.request, observation(row));
    if (name === 'create') assert.deepEqual(target, {identity: key, state: 'absent'});
    else {
      assert.equal(target.identity, key);
      assert.equal(target.state, 'present');
      assert.match(target.versionCid, /^sha256:[0-9a-f]{64}$/u);
      assert.deepEqual(target.before, {$id: nativeId, Computed: 'server',
        CustomerKey: key, Subject: 'before', Tags: ['red']});
    }
    const final = adapter.finalize({request: proposal.request, requestTag: cid('c')});
    assert.notEqual(final.requestCid, proposal.requestCid);
    assert.equal(adapter.capabilityRequestCid(final.request), proposal.requestCid);
    adapter.assertFinalized(final.request, cid('c'));
    assert.throws(() => adapter.finalize({request: proposal.request, requestTag: cid('c')}),
      {code: 'KintoneKeyUpsertFinalizationUnavailable'});
    assert.throws(() => adapter.writeRequest({...final.request}), {code: 'ForeignKintoneKeyUpsertRequest'});
    const native = adapter.writeRequest(final.request);
    assert.equal(native.operation, 'kintone:records:' + name);
    assert.equal(native.method, name === 'create' ? 'POST' : 'PUT');
    assert.equal(native.path, '/k/guest/23/v1/records.json');
    const record = {Subject: {value: 'next 東京'}, Tags: {value: ['red', 'red']}};
    assert.deepEqual(JSON.parse(native.body), name === 'create'
      ? {app, records: [{...record, CustomerKey: {value: key}}]}
      : {app, records: [{id: nativeId, revision, record}], upsert: false});
    const wire = adapter.savedWire(final.request), cold = createKintoneKeyUpsertRequestAdapter(f.options);
    const restored = cold.restore({wire, requestTag: cid('c')});
    assert.deepEqual(cold.writeRequest(restored.request), native);
    assert.equal(restored.requestCid, final.requestCid);
    assert.equal(cold.savedWire(restored.request), wire);
    assert.equal(f.calls.clientProgramKintoneLookupResponse, 1);
    assert.equal(f.calls.clientProgramKintoneRestoreKeyUpsertExecution, 1);
    assert.throws(() => cold.projectTarget(restored.request, observation(name === 'create' ? present : absent)),
      {code: 'KintoneKeyUpsertTargetChanged'});
    const recordId = name === 'create' ? '9007199254740996' : nativeId;
    const resultRevision = '0009007199254740997';
    const reply = observation(name === 'create' ? {ids: [recordId], revisions: [resultRevision]}
      : {records: [{id: recordId, revision: resultRevision}]});
    const projected = cold.projectResponse(restored.request, reply);
    assert.equal(projected.kind, 'typed-success-response');
    assert.deepEqual(projected.outcome, {state: 'applied', action: name === 'create' ? 'created' : 'updated',
      result: {record_id: recordId, revision: resultRevision, ...(name === 'create' ? {created: true} : {})}});
    const wrongBranch = observation(name === 'create' ? {records: []} : {ids: [recordId], revisions: [resultRevision]});
    const rejected = cold.projectResponse(restored.request, wrongBranch);
    assert.equal(rejected.kind, 'unclassified-response');
    assert.strictEqual(rejected.observation, wrongBranch);
  });
}

test('keyed UPSERT refuses unstable Form, incomplete absence and a rehashed opposite saved branch', () => {
  const {adapter, options} = fixture(), proposal = adapter.prepare({value: input, selector: key});
  const changed = structuredClone(keyedForm);
  changed.properties.CustomerKey.unique = false;
  assert.throws(() => adapter.recheckForm(proposal.request, observation(changed)), {code: 'MoonBitHostFailure'});
  assert.throws(() => adapter.projectTarget(proposal.request, observation({records: [], totalCount: null})),
    {code: 'MoonBitHostFailure'});
  adapter.projectTarget(proposal.request, observation(absent));
  const final = adapter.finalize({request: proposal.request, requestTag: cid('c')});
  const original = JSON.parse(adapter.savedWire(final.request));
  const cold = createKintoneKeyUpsertRequestAdapter(options);
  assert.throws(() => cold.restore({wire: encode({...original, body: '{}'}), requestTag: cid('c')}),
    {code: 'ForeignKintoneKeyUpsertRecovery'});
  assert.throws(() => cold.restore({wire: encode(original), requestTag: cid('d')}),
    {code: 'ForeignKintoneKeyUpsertRecovery'});
  const forged = {...original, branch: 'update'};
  const hash = createHash('sha256').update(encode({binding: forged.binding, logicalCid: forged.logicalCid,
    requestTag: forged.requestTag, targetBodyCid: forged.targetBodyCid, branch: forged.branch, body: forged.body})).digest('hex');
  assert.throws(() => cold.restore({wire: encode({...forged, requestCid: 'sha256:' + hash}), requestTag: cid('c')}),
    {code: 'MoonBitHostFailure'});
});

for (const [kind, row, opposite] of [['create', absent, 'update'], ['update', present, 'create']]) {
  test('keyed UPSERT driver uses only the original scoped ' + kind + ' operation', async () => {
    const {adapter, options} = fixture(), reads = [], writes = [], forms = new WeakSet();
    const site = {
      issueReadGrant(facts) {
        assert.equal(facts.operation, 'kintone:form:read');
        assert.equal(facts.resource, 'inquiries-form');
        const original = Object.freeze({grant: {}});
        forms.add(original);
        return original;
      },
      admitCheckpointEffectTargetRead() {assert.fail('the component does not submit a Checkpoint');},
    };
    const authorization = {async authorize(boundary, subject) {
      assert.equal(boundary, 'acquisition');
      assert.deepEqual(subject, {connection: 'kintone:kintone', resource: 'inquiries-form', operation: 'read'});
      return {action: 'dispatch'};
    }};
    const config = {...options, site, authorization, connection: 'kintone:kintone', formResource: 'inquiries-form',
      fields: ['Computed', 'CustomerKey', 'Subject', 'Tags'], maxMembers: 1, maxRecoveryBytes: 65536, kind: 'upsert'};
    const driver = kintoneUpdateDriver(config);
    const member = {kind: 'upsert', effectId: 'upsert-inquiry', memberIndex: 0, resource: options.resource,
      mapping: {mappingRef: adapter.mappingRef, mappingCid: adapter.mappingCid}};
    const targetGrant = Object.freeze({grant: {}, useId: 'original-target'});
    const original = {member, maxRows: 1, runInvocationCid: cid('d'), dispatchRequestCid: cid('e'),
      authorizationForRow: () => targetGrant,
      async readChild(grant, invocation, rowIndex, slot, project) {
        await invocation.currentBeforeSend();
        assert.equal(rowIndex, 0);
        assert.strictEqual(invocation.grant, grant.grant);
        if (slot === 'target') assert.strictEqual(grant, targetGrant);
        else assert(forms.has(grant));
        reads.push(slot);
        return project({...observation(slot === 'target' ? row : keyedForm), accepted: true});
      },
    };
    assert.deepEqual(driver.kinds, ['upsert']);
    assert.throws(() => driver.writeOperation(member), {code: 'KintoneKeyUpsertWriteBranchUnavailable'});
    const current = await driver.describe(original);
    const planned = driver.prepareRequest({member, current, value: input, selector: key});
    const [target] = await driver.observeTargets({...original, current, entries: [planned]});
    assert.equal(target.state, kind === 'create' ? 'absent' : 'present');
    assert.deepEqual(reads, ['schema-before', 'target', 'schema-after']);
    assert.deepEqual(writes, []);
    const requestTag = cid('c');
    const final = driver.finalizeRequest({request: planned.request, requestTag});
    const entry = driver.recoveryEntry({member, current, entries: [final]});
    const cold = kintoneUpdateDriver(config);
    const restored = cold.recoverRequests({maxRows: 1, members: [member],
      durable: {connectorRecovery: [{memberIndex: 0, ...entry}]},
      recorded: {members: [{claims: [{canonicalRequestCid: final.requestCid}]}]},
      body: {effects: [{changes: [{target_row_identity: key, after: {value: input}}]}]}, requestTags: [[requestTag]]});
    assert.equal(cold.requestCid(restored.requests[0][0]), final.requestCid);
    assert.equal(reads.length, 3, 'restoration performs no physical reads');
    assert.equal(writes.length, 0, 'restoration performs no physical writes');
    const reply = {...observation(kind === 'create' ? {ids: [nativeId], revisions: [revision]}
      : {records: [{id: nativeId, revision}]}), useCid: cid('f')};
    const invoke = (operation, resourceOrigin = options.origin) => driver.send({member, current,
      request: final.request, authorization: {scope: {resourceOrigin, connectorRegistration: 'kintone',
        operation: 'kintone:records:' + operation}, grant: {}, useId: 'original-write'}, credential: {binding: {}},
      async callResource(value) {writes.push(value.operations); return reply;},
    });
    await assert.rejects(invoke(opposite), {code: 'ForeignKintoneKeyUpsertWriteScope'});
    await assert.rejects(invoke(kind, 'https://other.example.test'), {code: 'ForeignKintoneKeyUpsertWriteScope'});
    assert.deepEqual(writes, []);
    const result = await invoke(kind);
    assert.equal(writes.length, 1);
    assert.deepEqual([...writes[0].keys()], ['kintone:records:' + kind]);
    assert.equal([...writes[0].values()][0].method, kind === 'create' ? 'POST' : 'PUT');
    assert.equal(result.observation.useCid, reply.useCid);
    assert.strictEqual(result.observation.body, reply.body);
    assert.equal(driver.project({request: final.request, ...result}).outcome.action,
      kind === 'create' ? 'created' : 'updated');
  });
}
