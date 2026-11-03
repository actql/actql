// Actual installed driver/route/recovery source with real GitHub provider
// codecs. Authorization, physical child and Ledger ports are explicit protocol
// fixtures; none is Core issuance, a durable claim or physical backing proof.
import assert from 'node:assert/strict';
import test from 'node:test';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {types as nodeTypes} from 'node:util';
import {parse} from 'acorn';
import * as providerMoon from '../../_build/js/release/build/connectors/github/host_node/host_node.js';
import * as provider from '../connectors/github/site/github-comment-create.mjs';
import {canonicalJson} from './local-account-config.mjs';
import {localContractLimits} from './local-values-plan.mjs';
import {captureInstalledStandardCreateLimits} from './installed-effect-plan.mjs';
import {createInstalledRowEffect} from './installed-row-effect.mjs';
import {captureClaimedEffectResponse} from './effect-physical-dispatch.mjs';
import {ownHttpRequest, ownRequestHeaders, ownResponseHeaderNames} from '../host-common/http-exchange.mjs';

function parsed(source) {
  const nodes = [];
  function walk(node) {
    if (!node || typeof node !== 'object') return;
    if (typeof node.type === 'string') nodes.push(node);
    for (const value of Object.values(node)) {
      if (Array.isArray(value)) value.forEach(walk);
      else if (value && typeof value === 'object') walk(value);
    }
  }
  walk(parse(source, {ecmaVersion: 'latest', sourceType: 'module'}));
  const evaluate = (node, ports) => Function(...Object.keys(ports),
    `return (${source.slice(node.start, node.end)});`)(...Object.values(ports));
  return {nodes, evaluate,
    fn(name, ports = {}) {return evaluate(nodes.find(n => n.type === 'FunctionDeclaration' && n.id.name === name), ports);},
    variable(name, ports = {}) {return evaluate(nodes.find(n => n.type === 'VariableDeclarator' && n.id.name === name).init, ports);}};
}
const sourceText = await readFile(new URL('./installed-row-effect.mjs', import.meta.url), 'utf8');
const source = parsed(sourceText);
const installed = parsed(await readFile(new URL('../connectors/github/host/installed-github-effect.mjs', import.meta.url), 'utf8'));
const fail = source.variable('fail');
const text = value => typeof value === 'string' && value.length > 0;
const tag = 'sha256:' + 'a'.repeat(64);
const limits = captureInstalledStandardCreateLimits(providerMoon);
const repository = {nodeId: 'R_original', databaseId: 13, nameWithOwner: 'o/r'};
const value = {subject_id: 'I_original', body: ' e\u0301\r\n東京 '};
const member = {memberIndex: 0, kind: 'create', resource: 'issue_comments'};
const evidence = Object.freeze({kind: 'CreatedComment', comment_id: 7, node_id: 'IC_original'});
const pending = Object.freeze({kind: 'provider-response', providerEvidence: evidence});
const writeNode = installed.nodes.filter(n => n.type === 'Property' && n.key.name === 'write' && n.value.type === 'ObjectExpression');
assert.equal(writeNode.length, 1);
function originalWrite() {
  return installed.evaluate(writeNode[0].value, {...provider,
    GITHUB_GRAPHQL_PATH: '/graphql', GITHUB_GRAPHQL_READ_OPERATION: 'github:graphql:read',
    site: {apiOrigin: 'https://api.github.test'}, boundaryCid: tag, providerMoon,
    commentLimits: limits, repository, fail,
    commentValue: installed.fn('commentValue', {sameKeys: installed.variable('sameKeys'), fail}),
    commentOutcome: installed.fn('commentOutcome'),
  });
}
function recipe() {
  const op = 'github:graphql:read';
  return {requestConstruction: {operationIndex: 0}, requestFinalization: {operationIndex: 1},
    rowOperations: [{operation: 'logical'}, {operation: 'finalization'},
      {operation: provider.GITHUB_COMMENT_CREATE_OPERATION}, {operation: op}, {operation: op}],
    credentialOperations: [{phase: 'write', operationIndex: 2, ...limits},
      {phase: 'apply-confirm', operationIndex: 3, ...limits},
      {phase: 'resume-confirm', operationIndex: 4, ...limits}]};
}
const capture = source.fn('captureResponseConfirmation', {nodeTypes, text, fail});
function fixture(options = {}) {
  const events = [], readCalls = [];
  let current = true, grantCount = 0, decision = {action: options.action ?? 'dispatch'};
  const grant = Object.freeze({original: 'read authorization',
    scope: Object.freeze({resourceOrigin: 'https://api.github.test'})});
  const writeAuthorization = Object.freeze({original: 'write authorization',
    scope: Object.freeze({resourceOrigin: 'https://api.github.test'})});
  const credential = {}, callResource = () => assert.fail('No transport engine in this component');
  const write = originalWrite();
  if (options.project) write.confirmation.project = options.project;
  const derive = source.fn('deriveInstalledRowWrite', {nodeTypes, createHash, canonicalJson, localContractLimits,
    ownHttpRequest, ownRequestHeaders, ownResponseHeaderNames,
    async invokeScopedCredentialOperation(facts) {
      if (facts.operation === provider.GITHUB_COMMENT_CREATE_OPERATION && options.mutation) {
        assert.strictEqual(facts.authorization, writeAuthorization);
        assert.strictEqual(facts.credential, credential); assert.strictEqual(facts.callResource, callResource);
        assert.equal(facts.body, originalRequest.body); events.push('write');
        return options.mutation(facts);
      }
      assert.strictEqual(facts.authorization, grant); assert.strictEqual(facts.credential, credential);
      assert.strictEqual(facts.callResource, callResource); assert.equal(facts.operation, 'github:graphql:read');
      assert.equal(facts.method, 'POST'); assert.equal(facts.path, '/graphql');
      const body = JSON.parse(facts.body);
      assert.match(body.query, /^query ActqlConfirmComment/u); assert.deepEqual(body.variables, {id: 'IC_original'});
      readCalls.push(facts); events.push('read');
      if (options.read) return options.read(facts, originalRequest);
      return {accepted: true, useCid: tag, statusCode: 200, body: readReply(originalRequest), headers: []};
    }});
  const {driver, construction} = derive(write, 'github');
  const logical = driver.prepareRequest({member, value});
  const originalRequest = driver.finalizeRequest({request: logical.request, requestTag: tag}).request;
  const plan = recipe(), responseConfirmation = capture(driver, plan);
  const site = {issueReadGrant(facts) {
    assert.strictEqual(this, site); assert.strictEqual(facts.decision, decision);
    assert.equal(facts.operation, 'github:graphql:read'); assert.equal(facts.resource, 'issue_comments');
    assert.equal(facts.runInvocationCid, 'original invocation'); assert.equal(facts.dispatchRequestCid, 'original dispatch');
    assert.equal(facts.maxUses, 1); grantCount++; events.push('grant'); options.onGrant?.(() => {current = false;}); return grant;
  }, issueEffectGrant() {assert.fail('Confirmation never obtains a mutation grant');}};
  const owner = {owned: driver, responseConfirmation, managedPlanRecipe: plan, site,
    connection: 'original connection', authorization: {async authorize(kind, target, context) {
      assert.equal(kind, 'acquisition'); assert.deepEqual(target, {connection: 'original connection', resource: 'issue_comments', operation: 'read'});
      assert.equal(context.subjectCid, 'original subject'); events.push('decision');
      if (options.authorize) await options.authorize(() => {current = false;});
      return decision;
    }}};
  const ownerOf = original => {assert.strictEqual(original, member); return owner;};
  const readDecision = source.variable('readDecision', {ownerOf});
  const route = source.variable('physicalRoute', {ownerOf, fail, readDecision})({
    members: [member], entries: [[{request: originalRequest, requestCid: originalRequest.requestCid, value}]],
    previewRows: [[{}]], runInvocationCid: 'original invocation', dispatches: ['original dispatch'],
    subjectCid: 'original subject', dispatchIndexes: [[0]], operationPhase: options.phase ?? 'apply',
    assertCurrent() {if (!current) throw new Error('original current lost'); events.push('current');},
    controlConstruction(receiver, method, args) {events.push('control'); return Reflect.apply(method, receiver, args);},
    async physicalOperations(facts) {
      assert.strictEqual(facts.member, member); assert.equal(facts.rowIndex, 0);
      assert.equal(facts.phase, `${options.phase ?? 'apply'}-confirm`); assert.equal(facts.purpose, 'read');
      assert.strictEqual(facts.site, site); assert.strictEqual(facts.originalAuthorization, grant);
      assert.equal(facts.runInvocationCid, 'original invocation'); assert.equal(facts.dispatchRequestCid, 'original dispatch');
      events.push('child'); facts.assertCurrent();
      return facts.invoke({authorization: grant, credential, callResource});
    },
  });
  return {route, driver, write, construction, owner, events, readCalls, originalRequest, credential, callResource, writeAuthorization,
    grantCount: () => grantCount, revoke: () => {current = false;},
    confirm: projected => route.confirmResponse({memberIndex: 0, rowIndex: 0, projected, current: {}, signal: undefined})};
}
function readReply(request) {
  return Buffer.from(JSON.stringify({data: {node: {__typename: 'IssueComment', id: 'IC_original', databaseId: 7,
    body: JSON.parse(request.body).variables.body, issue: {__typename: 'Issue', id: value.subject_id},
    repository: {__typename: 'Repository', id: repository.nodeId, databaseId: repository.databaseId, nameWithOwner: repository.nameWithOwner}}}}));
}
function applied(result) {
  assert.deepEqual(result, {kind: 'typed-success-response', outcome: {state: 'applied', action: 'created',
    result: {id: '7', node_id: 'IC_original'}}});
}

test('confirmation captures only distinct bounded initial/cold read occurrences and original method', () => {
  const h = fixture();
  const original = capture(h.driver, recipe());
  assert.strictEqual(original.receiver, h.driver); assert.strictEqual(original.request, h.driver.confirmResponse);
  assert.deepEqual(h.construction.confirmation, {resource: 'issue_comments', operation: 'github:graphql:read',
    maxRequestBytes: limits.maxRequestBytes, maxResponseBytes: limits.maxResponseBytes});
  for (const change of [
    plan => plan.credentialOperations.pop(),
    plan => {plan.credentialOperations[1].operationIndex = 2;},
    plan => {plan.credentialOperations[2].operationIndex = 3;},
    plan => {plan.credentialOperations[1].maxRequestBytes--;},
    plan => {plan.credentialOperations[2].maxResponseBytes = undefined;},
  ]) {
    const plan = recipe(); change(plan);
    assert.throws(() => capture(h.driver, plan), {code: 'InstalledEffectConfirmationPlanUnavailable'});
  }
  let getters = 0;
  const changed = {...h.driver};
  Object.defineProperty(changed, 'confirmResponse', {get() {getters++; return h.driver.confirmResponse;}});
  assert.throws(() => capture(changed, recipe()), {code: 'InvalidInstalledEffectConfirmation'});
  assert.equal(getters, 0);
});

test('actual initial confirmation independently authorizes the original read and matches complete provider tuple', async () => {
  const h = fixture(); applied(await h.confirm(pending));
  assert.equal(h.grantCount(), 1); assert.equal(h.readCalls.length, 1);
  assert(h.events.indexOf('decision') < h.events.indexOf('grant'));
  assert(h.events.indexOf('grant') < h.events.indexOf('child'));
  assert(h.events.indexOf('child') < h.events.indexOf('read'));
  assert.equal(h.originalRequest.logicalBody, value.body); assert.equal(h.originalRequest.requestTag, tag);
});

test('actual pending responses without Created evidence or with failed read never become terminal or trigger another send', async () => {
  const h = fixture();
  for (const response of [{kind: 'provider-response'}, {kind: 'unclassified-response'},
    {kind: 'typed-failure-response', outcome: {state: 'failed'}}]) {
    assert.strictEqual(await h.confirm(response), response);
  }
  assert.equal(h.grantCount(), 0); assert.equal(h.readCalls.length, 0);
  for (const read of [() => ({accepted: false, statusCode: 403, body: Buffer.from('{}')}),
    () => ({accepted: true, statusCode: 503, body: Buffer.from('{}')}),
    () => ({accepted: true, statusCode: 200, body: Buffer.from('{"data":{"node":null}}')})]) {
    const failed = fixture({read}); assert.strictEqual(await failed.confirm(pending), pending);
    assert.equal(failed.readCalls.length, 1);
  }
});

test('actual Deny or lost current prevents a confirmation grant/use while retaining pending provider evidence', async () => {
  const denied = fixture({action: 'deny'});
  await assert.rejects(denied.confirm(pending), {code: 'InstalledRowEffectCheckNotAuthorized'});
  assert.equal(denied.grantCount(), 0); assert.equal(denied.readCalls.length, 0);
  for (const options of [{authorize: revoke => revoke()}, {onGrant: revoke => revoke()}]) {
    const h = fixture(options);
    await assert.rejects(h.confirm(pending), {code: 'InstalledRowEffectSelectionChangedAfterClaim'});
    assert.equal(h.readCalls.length, 0);
  }
});

test('actual initial and cold confirmation keep different physical phases and fresh original read authorizations', async () => {
  for (const phase of ['apply', 'resume']) {
    const h = fixture({phase}); applied(await h.confirm(pending));
    assert.equal(h.readCalls.length, 1); assert.equal(h.grantCount(), 1);
  }
});

test('actual route retains its original entries while the confirmation read is unsettled', async () => {
  let release, started;
  const entered = new Promise(resolve => {started = resolve;});
  const result = new Promise(resolve => {release = resolve;});
  const h = fixture({async read(_facts, request) {started(); await result;
    return {accepted: true, statusCode: 200, body: readReply(request)};}});
  const running = h.confirm(pending); await entered;
  assert.equal(h.route.retire(), false);
  release(); applied(await running);
  assert.equal(h.route.retire(), true);
  await assert.rejects(h.confirm(pending), {code: 'InstalledRowEffectRouteRetired'});
});

test('actual invalid asynchronous pure projector remains joined and cannot produce a typed outcome', async () => {
  let finish, started;
  const entered = new Promise(resolve => {started = resolve;});
  const projection = new Promise(resolve => {finish = resolve;});
  const h = fixture({project() {started(); return projection;}});
  const running = h.confirm(pending); await entered;
  assert.equal(h.route.retire(), false);
  finish({kind: 'typed-success-response', outcome: {state: 'applied'}});
  await assert.rejects(running, {code: 'InvalidInstalledRowWrite'});
  assert.equal(h.route.retire(), true);
});

const recoveryNode = source.nodes.find(n => n.type === 'VariableDeclarator' && n.id.name === 'reconcileStoredResponses');
function cold(h, {outcome, commitError, callSignal} = {}) {
  const claim = {}, preview = {}, events = [], ownedClaim = Object.freeze({});
  const response = Buffer.from(JSON.stringify({data: {addComment: {
    commentEdge: {node: {id: 'IC_original', databaseId: 7}}, subject: {__typename: 'Issue', id: value.subject_id}}}}));
  const stored = {credentialUseCid: tag, statusCode: 200, responseBytes: response};
  const entry = {request: h.originalRequest, requestCid: h.originalRequest.requestCid};
  const ledger = {readClaimedResponse(original) {assert.strictEqual(original, claim); return stored;},
    readClaimedOutcome(original) {assert.strictEqual(original, ownedClaim); events.push('outcome'); return outcome;},
    commitAdmittedRowOutcome(facts) {
      assert.strictEqual(facts.claim, ownedClaim); assert.strictEqual(facts.preview, preview);
      assert.equal(facts.memberIndex, 0); assert.equal(facts.previewRowIndex, 0); events.push('commit');
      if (commitError) throw commitError;
      return {receipt: {}, transition: {created: false}};
    }};
  const ports = {route: h.route, ledger, fail, dispatchIndexes: [[0]], entries: [[entry]],
    members: [member], currents: [{}], ownerOf: () => h.owner, applyPreview: preview, moon: {}, signal: undefined,
    previewRows: [[{}]], controlConstruction: (receiver, method, args) => Reflect.apply(method, receiver, args),
    admitRow(facts) {assert.strictEqual(facts.claim, claim); assert.strictEqual(facts.entry, entry); return ownedClaim;},
    async recoverProjectedEffectResponse(options) {
      assert.strictEqual(options.claims, ownedClaim); assert.equal(options.expectedRequestCid, entry.requestCid);
      assert.strictEqual(await options.authorizeEvidenceRead(), true); events.push('evidence access');
      return {recovered: options.projectStored(stored)};
    },
    settle(facts) {assert.strictEqual(facts.claim, ownedClaim); assert.strictEqual(facts.applyPreview, preview);
      applied(facts.projected); events.push('settle');},
  };
  // Evaluate only the original callback; its enclosing resource/lifetime
  // variables remain explicit, mutable protocol inputs to this component.
  return {events, run: Function(...Object.keys(ports), `let closing=false,closed=false,reconciling=0;
    return (${sourceText.slice(recoveryNode.init.start, recoveryNode.init.end)});`)(...Object.values(ports))({members: [{claims: [claim]}], preview, signal: callSignal})};
}

test('actual cold caller confirms the stored original response before typed settlement without another mutation', async () => {
  const h = fixture({phase: 'resume'}), c = cold(h); await c.run;
  assert.deepEqual(c.events, ['evidence access', 'outcome', 'settle']);
  assert.equal(h.grantCount(), 1); assert.equal(h.readCalls.length, 1);
});

test('actual cold caller re-admits existing receipt/CAS continuation instead of repeating a confirming read', async () => {
  const h = fixture({phase: 'resume'}), c = cold(h, {outcome: {original: 'retained receipt custody'}}); await c.run;
  assert.deepEqual(c.events, ['evidence access', 'outcome', 'commit']);
  assert.equal(h.grantCount(), 0); assert.equal(h.readCalls.length, 0);
  const original = new Error('original ambiguous COMMIT observation');
  const failed = fixture({phase: 'resume'}), ambiguous = cold(failed, {outcome: {}, commitError: original});
  await assert.rejects(ambiguous.run, error => error === original);
  assert.equal(failed.grantCount(), 0); assert.equal(failed.readCalls.length, 0);
});

test('actual cold confirmation uses the current apply caller AbortSignal instead of its older captured signal', async () => {
  const controller = new AbortController(), reason = new Error('original caller cancellation');
  controller.abort(reason);
  const h = fixture({phase: 'resume'}), c = cold(h, {callSignal: controller.signal});
  await assert.rejects(c.run, error => error === reason);
  assert.equal(h.grantCount(), 0); assert.equal(h.readCalls.length, 0);
  assert.deepEqual(c.events, ['evidence access', 'outcome']);
});

test('actual fresh dispatch stores the original mutation response before independently confirming and settling the same claim', async () => {
  const originalResponse = Buffer.from(JSON.stringify({data: {addComment: {
    commentEdge: {node: {id: 'IC_original', databaseId: 7}}, subject: {__typename: 'Issue', id: value.subject_id}}}}));
  const h = fixture({mutation: () => ({accepted: true, useCid: tag, statusCode: 200, body: originalResponse, headers: []})});
  const claim = Object.freeze({scope: {}, locator: {}, key: {}, basis: {},
    intentFingerprintCid: tag, canonicalRequestCid: h.originalRequest.requestCid});
  const preview = {}, preflight = {}, decision = {}, current = {};
  const entry = {request: h.originalRequest, requestCid: claim.canonicalRequestCid, value};
  const ledger = {claimDispatch(original) {
    assert.strictEqual(original.key, claim.key); assert.strictEqual(original.basis, claim.basis);
    h.events.push('claim'); return {claimed: true, dispatching: {}};
  }, beginPhysicalFlight(_dispatching, original) {
    assert.strictEqual(original.key, claim.key); return () => h.events.push('flight end');
  }, recordResponse(original) {
    assert.strictEqual(original.responseBytes, originalResponse); assert.strictEqual(original.key, claim.key);
    assert.equal(original.canonicalRequestCid, claim.canonicalRequestCid); h.events.push('stored original response');
    return {response: {original: true}};
  }};
  h.owner.site.issueEffectGrant = function(facts) {
    assert.strictEqual(this, h.owner.site); assert.strictEqual(facts.decision, decision); return h.writeAuthorization;
  };
  const ports = {fail, subjectCid: 'original subject', hasRefreshed: true, members: [member],
    requireOpen() {}, assertCurrent: h.route.assertClaimedCurrent, assertClaimedCurrent: h.route.assertClaimedCurrent,
    commitDecisions: () => new Map([['original', decision]]), scopeKey: () => 'original',
    currentsByPreflight: new WeakMap([[preflight, [current]]]), dispatchIndexes: [[0]], entries: [[entry]],
    ownerOf: () => h.owner, resourceFields: () => ({}), dispatches: ['original dispatch'],
    runInvocationCid: 'original invocation', applyPreview: preview, previewRows: [[{}]], ledger,
    requireApproval(_member, original) {assert.strictEqual(original, decision);},
    admitRow(facts) {assert.strictEqual(facts.claim, claim); assert.strictEqual(facts.entry, entry); return claim;},
    captureClaimedEffectResponse, controlConstruction: (receiver, method, args) => Reflect.apply(method, receiver, args),
    async physicalOperations(facts) {
      assert.equal(facts.phase, 'write'); assert.equal(facts.purpose, 'effect');
      assert.strictEqual(facts.originalAuthorization, h.writeAuthorization);
      return facts.invoke({authorization: h.writeAuthorization, credential: h.credential, callResource: h.callResource});
    }, confirmResponse: h.route.confirmResponse,
    settle(facts) {
      assert.strictEqual(facts.claim, claim); assert.strictEqual(facts.applyPreview, preview);
      applied(facts.projected); h.events.push('settle'); return {};
    }};
  const node = source.nodes.find(n => n.type === 'VariableDeclarator' && n.id.name === 'bindDispatch');
  const bind = Function(...Object.keys(ports), `let active=0;
    return (${sourceText.slice(node.init.start, node.init.end)});`)(...Object.values(ports));
  const dispatch = bind({members: [{claims: [claim]}], subjectCid: 'original subject', decisions: []});
  const result = await dispatch({memberIndex: 0, rowIndex: 0, claim, currentPreflight: preflight});
  applied(result.physical); assert.equal(result.claimed, true);
  assert.equal(h.events.filter(event => event === 'write').length, 1);
  assert(h.events.indexOf('claim') < h.events.indexOf('write'));
  assert(h.events.indexOf('stored original response') < h.events.indexOf('read'));
  assert(h.events.indexOf('read') < h.events.indexOf('settle'));
});

test('actual installer rejects an unpriced confirmation even without marker finalization before any provider work', async () => {
  const write = originalWrite(); delete write.finalization;
  write.request = () => assert.fail('No provider constructor before missing read-phase backing refusal');
  const unused = () => assert.fail('No grant/authorization before missing read-phase backing refusal');
  await assert.rejects(createInstalledRowEffect({
    moon: {}, write, connectorId: 'github-fixture', connectorRegistration: 'github', connectorRevision: 'github/0.1',
    connection: 'original connection', environmentWire: '{}', runtimeBundleCid: tag, bindingCid: tag,
    ledgerRoot: 'must-not-open-ledger', site: {issueEffectGrant: unused, issueReadGrant: unused},
    authorization: {authorize: unused},
    mappings: [{resource: 'issue_comments', mappingRef: 'mapping:github-fixture/create.v1', mappingCid: tag,
      body: JSON.stringify({mapping_contract_cid: tag, target_ref: 'connector://github-fixture/issue_comments',
        minimum_approval: 'required', permission_rules: [{effect_kind: 'create', permissions: ['write']}],
        primary_identity: ['id']})}],
  }), {code: 'InstalledEffectConfirmationPlanUnavailable'});
});
