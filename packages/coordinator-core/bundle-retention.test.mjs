import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {bundleRetention as retention, createJournal} from '@actql/coordinator-core';

// Independent canonical fixture fields and CIDs shared with the Core vectors.
// No expected body or identity is obtained from the product serializer.
const member = `sha256:${'a'.repeat(64)}`;
const otherMember = `sha256:${'b'.repeat(64)}`;
const distributionCid = 'sha256:db2c1d1c2bcac2bac713db8b6065ef525014133c60b672540d20f9be0bdb4f06';
const scopeCid = 'sha256:a47fd39adfd002964881687963b875b86549365ebea8c4d89a82f2948e02f3c3';
const bindingCid = 'sha256:43996a2fa47f5c49b74175ad6906ee2d9c03ac74f5f1163fe3b087c5f79ad594';
const contextRequestCid = 'sha256:a712ca85e73d44f13bf30d46a3cb43da0f020438b005f5cf445bd9be8d2ee3f6';
const contextResponseCid = 'sha256:f97a5757e928d9d1117c850a8fe11ebb2872a42032b3cefb247a557075f6c3cd';
const requestCids = {
  retain: 'sha256:a823575b8877d19528e2e5e37c385ac42aa11dc6aa1049f80720a2c816a4a41d',
  query: 'sha256:1e8e00fe38cbc657887ffe8e2e6dabc4953307335402086cad63724be0abd952',
  release: 'sha256:090e6569f0486cd33fb70365630c85f6e556096681d4beeac3cdb5dae3606010',
};
const catalog = '123e4567-e89b-42d3-a456-426614174000';
const distributionBody = JSON.stringify({runtime_bundle_cids: [member, otherMember],
  version: 'actql-remote-runtime-bundle-distribution/0.1'});
const scopeFields = {
  attempt_id: 'hold-a', authority_scope_cid: `sha256:${'c'.repeat(64)}`,
  coordinator_authority: 'coordinator-a', distribution_cid: distributionCid,
  environment: 'production', runtime_bundle_cid: member,
  set_revision_cid: `sha256:${'d'.repeat(64)}`, site_generation: 7,
  site_key: 'site-a', version: 'actql-remote-runtime-bundle-hold-scope/0.1',
  workspace_id: 'workspace-a',
};
const scopeBody = JSON.stringify(scopeFields);
const bindingFields = {
  attempt_id: 'hold-a', authority_scope_cid: `sha256:${'c'.repeat(64)}`,
  catalog_incarnation: catalog, coordinator_authority: 'coordinator-a',
  distribution_cid: distributionCid, environment: 'production', initial_revision: 11,
  runtime_bundle_cid: member, set_revision_cid: `sha256:${'d'.repeat(64)}`,
  site_generation: 7, site_key: 'site-a',
  version: 'actql-remote-runtime-bundle-hold-binding/0.1', workspace_id: 'workspace-a',
};
const bindingBody = JSON.stringify(bindingFields);
const contextRequestBody = JSON.stringify({distribution: distributionBody,
  distribution_cid: distributionCid, operation: 'query', scope: scopeBody,
  scope_cid: scopeCid, version: 'actql-remote-runtime-bundle-custody-request/0.1'});
const contextResponseBody = JSON.stringify({binding: bindingBody, binding_cid: bindingCid,
  kind: 'context', request_cid: contextRequestCid,
  version: 'actql-remote-runtime-bundle-custody-response/0.1'});
const digest = body => `sha256:${createHash('sha256').update(body).digest('hex')}`;
const rejected = {code: 'CoordinatorOwnerRejected'};

function fixture() {
  const distribution = retention.prepareDistribution([otherMember, member]);
  const scope = retention.prepareHoldScope({distribution,
    coordinatorAuthority: 'coordinator-a', workspaceId: 'workspace-a',
    authorityScopeCid: scopeFields.authority_scope_cid, environment: 'production',
    setRevisionCid: scopeFields.set_revision_cid, runtimeBundleCid: member,
    siteKey: 'site-a', siteGeneration: 7, attemptId: 'hold-a'});
  const request = retention.prepareCustodyContextQuery(distribution, scope);
  return {distribution, scope, request};
}

function observationBody(status, revision, incarnation = catalog) {
  return JSON.stringify({binding_cid: bindingCid, catalog_incarnation: incarnation,
    kind: 'observation', observation: status, record_revision: revision,
    request_cid: requestCids.retain,
    version: 'actql-remote-runtime-bundle-custody-response/0.1'});
}

test('portable public namespace admits context without asserting retained readiness', () => {
  assert.equal(Object.isFrozen(retention), true);
  assert.equal(typeof createJournal, 'function');
  const {distribution, scope, request} = fixture();
  assert.equal(retention.distributionIdentity(distribution), distributionCid);
  assert.equal(retention.distributionJson(distribution), distributionBody);
  assert.deepEqual(retention.distributionProjection(distribution),
    [distributionCid, member, otherMember]);
  assert.equal(retention.distributionContains(distribution, member), true);
  assert.equal(retention.distributionContains(distribution, scopeFields.authority_scope_cid), false);
  assert.equal(retention.holdScopeIdentity(scope), scopeCid);
  assert.equal(retention.holdScopeJson(scope), scopeBody);
  assert.equal(retention.holdScopeIdentity(retention.admitHoldScopeJson(
    distribution, scopeBody, scopeCid)), scopeCid);
  assert.deepEqual(retention.holdScopeProjection(scope), [scopeCid, 'coordinator-a',
    'workspace-a', scopeFields.authority_scope_cid, 'production',
    scopeFields.set_revision_cid, distributionCid, member, 'site-a', '7', 'hold-a']);
  assert.equal(retention.custodyRequestIdentity(request), contextRequestCid);
  assert.equal(retention.custodyRequestJson(request), contextRequestBody);
  const admitted = retention.admitCustodyRequestJson(contextRequestBody, contextRequestCid);
  assert.equal(retention.custodyRequestOperation(admitted), 'query');
  assert.equal(retention.custodyRequestBinding(admitted), undefined);
  assert.equal(retention.holdScopeIdentity(retention.custodyRequestScope(admitted)), scopeCid);
  const response = retention.admitCustodyResponseJson(admitted,
    contextResponseBody, contextResponseCid);
  assert.equal(retention.custodyResponseIdentity(response), contextResponseCid);
  assert.equal(retention.custodyResponseJson(response), contextResponseBody);
  assert.equal(retention.custodyResponseKind(response), 'context');
  assert.equal(retention.custodyResponseObservation(response), '');
  assert.equal(retention.custodyResponseCatalog(response), catalog);
  assert.equal(retention.custodyResponseRevision(response), 11);
});

test('the original returned binding survives persistence and all three custody verbs', () => {
  const {request} = fixture();
  const response = retention.admitCustodyResponseJson(request,
    contextResponseBody, contextResponseCid);
  const received = retention.custodyResponseBinding(response);
  const persistedBody = retention.holdBindingJson(received);
  const persistedCid = retention.holdBindingIdentity(received);
  assert.equal(persistedBody, bindingBody);
  assert.equal(persistedCid, bindingCid);
  const distribution = retention.admitDistributionJson(distributionBody, distributionCid);
  const restored = retention.admitHoldBindingJson(distribution, persistedBody, persistedCid);
  assert.equal(retention.holdScopeIdentity(retention.holdBindingScope(restored)), scopeCid);
  assert.deepEqual(retention.holdBindingProjection(restored), [bindingCid, catalog,
    'coordinator-a', 'workspace-a', scopeFields.authority_scope_cid, 'production',
    scopeFields.set_revision_cid, distributionCid, member, 'site-a', '7', '11', 'hold-a']);
  for (const operation of ['retain', 'query', 'release']) {
    const outgoing = retention.prepareCustodyRequest(distribution, restored, operation);
    const expectedBody = JSON.stringify({binding: bindingBody, binding_cid: bindingCid,
      distribution: distributionBody, distribution_cid: distributionCid, operation,
      version: 'actql-remote-runtime-bundle-custody-request/0.1'});
    assert.equal(retention.custodyRequestJson(outgoing), expectedBody);
    assert.equal(retention.custodyRequestIdentity(outgoing), requestCids[operation]);
    const admitted = retention.admitCustodyRequestJson(expectedBody, requestCids[operation]);
    assert.equal(retention.custodyRequestOperation(admitted), operation);
    assert.equal(retention.holdBindingJson(retention.custodyRequestBinding(admitted)), persistedBody);
  }
  assert.equal(retention.holdBindingJson(restored), persistedBody);
});

test('response projections preserve absent catalog and revision and numeric zero', () => {
  const {distribution} = fixture();
  const binding = retention.admitHoldBindingJson(distribution, bindingBody, bindingCid);
  const request = retention.prepareCustodyRequest(distribution, binding, 'retain');
  for (const [status, revision, incarnation] of [
    ['retained', 12, catalog], ['unresolved', 11, catalog],
    ['unavailable', null, null], ['unavailable', 0, catalog],
  ]) {
    const body = observationBody(status, revision, incarnation);
    const response = retention.admitCustodyResponseJson(request, body, digest(body));
    assert.equal(retention.custodyResponseJson(response), body);
    assert.equal(retention.custodyResponseIdentity(response), digest(body));
    assert.equal(retention.custodyResponseKind(response), 'observation');
    assert.equal(retention.custodyResponseObservation(response), status);
    assert.equal(retention.custodyResponseCatalog(response), incarnation ?? undefined);
    assert.equal(retention.custodyResponseRevision(response), revision ?? undefined);
    assert.equal(retention.holdBindingJson(retention.custodyResponseBinding(response)), bindingBody);
  }
});

test('public admission rejects wrong verbs, foreign response scopes, and unknown formats', () => {
  const {distribution, request: context} = fixture();
  const binding = retention.admitHoldBindingJson(distribution, bindingBody, bindingCid);
  assert.throws(() => retention.prepareCustodyRequest(distribution, binding, 'install'), rejected);
  const retain = retention.prepareCustodyRequest(distribution, binding, 'retain');
  const query = retention.prepareCustodyRequest(distribution, binding, 'query');
  const retainedBody = observationBody('retained', 12);
  assert.throws(() => retention.admitCustodyResponseJson(query,
    retainedBody, digest(retainedBody)), rejected);
  assert.throws(() => retention.admitCustodyResponseJson(retain,
    contextResponseBody, contextResponseCid), rejected);

  // A correctly hashed foreign binding still cannot answer the original scope.
  const foreignBinding = JSON.stringify({...bindingFields, workspace_id: 'workspace-b'});
  const foreignResponse = JSON.stringify({binding: foreignBinding,
    binding_cid: digest(foreignBinding), kind: 'context', request_cid: contextRequestCid,
    version: 'actql-remote-runtime-bundle-custody-response/0.1'});
  assert.throws(() => retention.admitCustodyResponseJson(context,
    foreignResponse, digest(foreignResponse)), rejected);

  for (const [body, admit] of [
    [distributionBody, (body, cid) => retention.admitDistributionJson(body, cid)],
    [scopeBody, (body, cid) => retention.admitHoldScopeJson(distribution, body, cid)],
    [bindingBody, (body, cid) => retention.admitHoldBindingJson(distribution, body, cid)],
    [contextRequestBody, (body, cid) => retention.admitCustodyRequestJson(body, cid)],
    [contextResponseBody, (body, cid) => retention.admitCustodyResponseJson(context, body, cid)],
  ]) {
    const unknown = body.replace('/0.1', '/0.2');
    assert.throws(() => admit(unknown, digest(unknown)), rejected);
  }
  const changedVerb = retention.custodyRequestJson(retain).replace('"retain"', '"release"');
  assert.throws(() => retention.admitCustodyRequestJson(changedVerb, requestCids.retain), rejected);
});
