import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {parse} from 'acorn';
import {createHash} from 'node:crypto';
import {types as nodeTypes} from 'node:util';
import {ownHttpRequest, ownRequestHeaders, ownResponseHeaderNames} from '../host-common/http-exchange.mjs';
import {invokeScopedCredentialOperation} from '../host-common/owned-invocation-context.mjs';
import {createInstalledRowEffect} from './installed-row-effect.mjs';
import {prepareGitHubCommentRequest, sendGitHubIssueComment,
  GITHUB_COMMENT_CREATE_OPERATION} from '../connectors/github/site/github-comment-create.mjs';
import {GITHUB_GRAPHQL_PATH, GITHUB_GRAPHQL_READ_OPERATION} from
  '../connectors/github/site/github-issue-graphql-read.mjs';
import {prepareSheetsAppend, sendSheetsAppend, SHEETS_APPEND_OPERATION,
  SHEETS_READ_OPERATION, SHEETS_LIMITS} from '../connectors/sheets/site/sheets-exchange.mjs';

// Execute the complete internal adapter with its actual transport callees.
// The constructor test below separately imports and exercises its real caller.
const rowSource = readFileSync(new URL('./installed-row-effect.mjs', import.meta.url), 'utf8');
const rowTree = parse(rowSource, {ecmaVersion: 'latest', sourceType: 'module'});
const derivedNode = rowTree.body.find(node => node.type === 'FunctionDeclaration' && node.id.name === 'deriveInstalledRowWrite');
assert.ok(derivedNode);
const deriveInstalledRowWrite = Function('createHash', 'nodeTypes', 'ownHttpRequest', 'ownRequestHeaders',
  'ownResponseHeaderNames', 'invokeScopedCredentialOperation', `return (${rowSource.slice(derivedNode.start, derivedNode.end)});`)(
  createHash, nodeTypes, ownHttpRequest, ownRequestHeaders, ownResponseHeaderNames, invokeScopedCredentialOperation);

const boundaryCid = `sha256:${'b'.repeat(64)}`;
const providerCid = `sha256:${'a'.repeat(64)}`;
const origin = 'https://api.example.test';
const member = Object.freeze({kind: 'create', resource: 'records'});
const declaration = overrides => ({kind: 'create', operation: 'fixture:create',
  resourceKind: 'records', boundaryCid,
  http: {origin, method: 'POST', path: '/records', headers: [['accept', 'application/json']],
    maxRequestBytes: 200, maxResponseBytes: 400},
  request: () => ({path: '/records', body: '{"name":"é"}'}),
  classify: () => ({kind: 'provider-response'}), ...overrides});
const authorization = operation => ({grant: Object.freeze({}), useId: 'original-use',
  scope: {operation, resourceOrigin: origin}});
const response = Object.freeze({accepted: true, useCid: providerCid,
  statusCode: 201, body: new Uint8Array([123, 125]), headers: []});

test('standard CREATE derives facts, operation, footprint and exact HTTP CID from one mapping', () => {
  const value = {name: 'é', nested: {items: [1, 2]}};
  let mappings = 0;
  const write = declaration({request(context) {
    assert.equal(this, write); assert.equal(context.value, value);
    assert.ok(Object.isFrozen(value.nested.items)); mappings++;
    return {path: '/records', body: '{"name":"é"}'};
  }});
  const driver = deriveInstalledRowWrite(write, 'fixture');
  const prepared = driver.prepareRequest({member, value});
  assert.equal(mappings, 1); assert.equal(driver.requestFacts(prepared.request).value, value);
  assert.equal(prepared.requestCid, 'sha256:f13c014776e8479ce3677159b13d62a2f052679b6b4c8aaf8635fefe290d3b7e');
  assert.deepEqual(driver.kinds, ['create']); assert.equal(driver.writeOperation(member), 'fixture:create');
  assert.deepEqual(driver.footprint({member, entries: [prepared]}),
    {providerNamespace: 'fixture', resourceKind: 'records', boundaryCid});
  assert.throws(() => driver.requestFacts({...prepared.request}), {code: 'InvalidInstalledRowWrite'});
  assert.throws(() => { value.nested.items.push(3); }, TypeError);
});

test('standard sender retains original CID, scoped transport, response and uncertainty without retry', async () => {
  let sends = 0;
  const driver = deriveInstalledRowWrite(declaration({
    request: () => ({origin, method: 'POST', path: '/records', body: '{}', requestCid: providerCid}),
    classify: ({headers}) => ({kind: headers === undefined ? 'stored-provider-response' : 'provider-response'}),
  }), 'fixture');
  const {request, requestCid} = driver.prepareRequest({member, value: {name: 'name'}});
  assert.equal(requestCid, providerCid);
  const context = {request, authorization: authorization('fixture:create'), credential: {},
    callResource(args) {
      sends++; assert.equal(args.grant, context.authorization.grant);
      assert.deepEqual([...args.operations], [['fixture:create',
        {method: 'POST', path: '/records', body: '{}', headers: [['accept', 'application/json']]}]]);
      assert.equal(args.maxRequestBytes, 200); assert.equal(args.maxResponseBytes, 400);
      return response;
    }};
  assert.equal(sends, 0, 'mapping and facts cannot send');
  const observed = await driver.send(context);
  assert.deepEqual(observed, {observation: {useCid: response.useCid,
    statusCode: 201, body: response.body}, headers: response.headers});
  assert.equal(sends, 1);
  assert.deepEqual(driver.project({request, ...observed}), {kind: 'provider-response'});
  assert.deepEqual(driver.project({request, observation: observed.observation}), {kind: 'stored-provider-response'});
  const lost = new Error('lost original response');
  await assert.rejects(driver.send({...context, callResource() {sends++; throw lost;}}), error => error === lost);
  assert.equal(sends, 2, 'one attempt per explicit owner call, never a retry');
  for (const selected of [{...context, request: {...request}}, {...context,
    authorization: {...context.authorization, scope: {operation: 'fixture:create', resourceOrigin: 'https://foreign.test'}}},
    {...context, authorization: authorization('wrong-operation')},
    {...context, signal: AbortSignal.abort(new Error('cancelled'))}]) {
    await assert.rejects(driver.send(selected));
  }
  assert.equal(sends, 2);
});

test('standard declaration captures callbacks and preserves the independent read check without granting it', () => {
  const originalGrant = Object.freeze({});
  const check = {resource: 'records', operation: 'fixture:read', request(context) {
    assert.equal(this, check); assert.equal(context.authorization, originalGrant); return 'checked';
  }};
  const write = declaration({check});
  const driver = deriveInstalledRowWrite(write, 'fixture');
  check.request = () => assert.fail('method replaced after capture');
  write.request = () => assert.fail('method replaced after capture');
  assert.deepEqual(driver.check, {resource: 'records', operation: 'fixture:read'});
  assert.equal(driver.checkRequest({authorization: originalGrant}), 'checked');
  driver.prepareRequest({member, value: {}});
  for (const request of [{path: '/foreign', body: '{}'}, {path: '/records', body: '{}', origin: 'https://foreign.test'},
    {path: '/records', body: '{}', method: 'DELETE'}, {path: '/records', body: '{}', headers: []}]) {
    assert.throws(() => deriveInstalledRowWrite(declaration({request: () => request}), 'fixture')
      .prepareRequest({member, value: {}}), {code: 'InvalidInstalledRowWrite'});
  }
});

test('standard request callbacks receive only original provider DATA, not the RSE lifetime context', () => {
  const value = {name: 'original'}, internal = Object.freeze({});
  const write = declaration({request(context) {
    assert.deepEqual(Object.keys(context).sort(), ['resource', 'value']);
    assert.equal(context.resource, member.resource); assert.equal(context.value, value);
    assert.ok(Object.isFrozen(context)); assert.ok(Object.isFrozen(context.value));
    return {path: '/records', body: '{}'};
  }});
  const driver = deriveInstalledRowWrite(write, 'fixture');
  const prepared = driver.prepareRequest({member, value, runOriginal: internal,
    requestOrigin: internal, createRowIdentity: internal, current: internal,
    authorization: internal, signal: internal, assertCurrent() {}, prepareOperationChild() {}});
  assert.equal(driver.requestFacts(prepared.request).value, value);
});

test('standard classification callbacks receive original provider DATA and preserve header absence', () => {
  const value = {name: 'original'}, internal = Object.freeze({}), observation = Object.freeze({body: new Uint8Array([123, 125])});
  const write = declaration({classify(context) {
    assert.deepEqual(Object.keys(context).sort(), ['observation', 'request', 'resource', 'value',
      ...(Object.hasOwn(context, 'headers') ? ['headers'] : [])].sort());
    assert.equal(context.resource, member.resource); assert.equal(context.value, value);
    assert.equal(context.observation, observation); assert.ok(Object.isFrozen(context));
    return Object.hasOwn(context, 'headers') ? 'present' : 'absent';
  }});
  const driver = deriveInstalledRowWrite(write, 'fixture');
  const {request} = driver.prepareRequest({member, value});
  const context = {request, observation, member, resource: 'foreign caller DATA',
    value: {name: 'foreign'}, runOriginal: internal, preview: internal,
    current: internal, authorization: internal, signal: internal, assertCurrent() {}, prepareOperationChild() {}};
  assert.equal(driver.project(context), 'absent');
  assert.equal(driver.project({...context, headers: undefined}), 'present');
});

test('actual Row Effect constructor consumes the declaration and refuses a simultaneous advanced driver before acquisition', async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-standard-create-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  let closed = 0;
  const unused = () => assert.fail('constructor cannot authorize, grant, map or send');
  const options = {moon: {strategyRemoteManagedOutputEvidenceKind: () => 'unused-kind'},
    mappings: [{resource: 'records', mappingRef: 'mapping:fixture/create.v1', mappingCid: providerCid,
      body: JSON.stringify({mapping_contract_cid: providerCid, target_ref: 'connector://fixture/records',
        primary_identity: ['id'], minimum_approval: 'required',
        permission_rules: [{effect_kind: 'create', permissions: ['write']}]})}],
    environmentWire: '{}', connectorId: 'fixture', connectorRegistration: 'fixture', connectorRevision: 'fixture/0.1',
    connection: 'original', site: {issueEffectGrant: unused, issueReadGrant: unused, close() {closed++;}},
    authorization: {authorize: unused}, runtimeBundleCid: providerCid, bindingCid: boundaryCid,
    ledgerRoot: root, write: declaration({request: unused, classify: unused})};
  await assert.rejects(createInstalledRowEffect({...options, driver: {}}), {code: 'InvalidInstalledRowEffectDriver'});
  assert.equal(closed, 0);
  const effect = await createInstalledRowEffect(options);
  assert.ok(Object.isFrozen(effect)); assert.equal(closed, 0);
  await effect.close(); assert.equal(closed, 1);
});

function selectedWrite(path, ports) {
  const source = readFileSync(new URL(path, import.meta.url), 'utf8');
  const selected = [];
  const visit = node => {
    if (node === null || typeof node !== 'object') return;
    if (node.type === 'Property' && node.key.name === 'write' && node.value.type === 'ObjectExpression' &&
        node.value.properties.some(p => p.key?.name === 'kind' && p.value.value === 'create')) selected.push(node.value);
    for (const value of Object.values(node)) {
      if (Array.isArray(value)) value.forEach(visit);
      else if (value && typeof value === 'object') visit(value);
    }
  };
  visit(parse(source, {ecmaVersion: 'latest', sourceType: 'module'}));
  assert.equal(selected.length, 1, 'normal caller must select the declaration, not the old driver');
  return Function(...Object.keys(ports), `return (${source.slice(selected[0].start, selected[0].end)});`)(...Object.values(ports));
}

// Actual provider factories and the complete changed normal-caller declaration,
// with explicit native codec/check/classifier DATA ports. No Common, Account,
// grant issuer, real provider or normal installed execution is substituted.
test('GitHub normal declaration keeps original GraphQL request, sender envelope and read-before-write check', async () => {
  const providerMoon = {githubAddCommentRequestJson: (subject, body) => JSON.stringify({body: JSON.stringify({subject, body})}),
    githubCommentOutcomeJson() {}, githubRequestHeadersJson: () => '[["accept","application/json"]]',
    githubResponseHeadersJson: () => '["x-ratelimit-remaining"]'};
  const site = {apiOrigin: origin}, repository = Object.freeze({nodeId: 'repository'});
  let checks = 0;
  const write = selectedWrite('../connectors/github/host/installed-github-effect.mjs', {
    GITHUB_COMMENT_CREATE_OPERATION, GITHUB_GRAPHQL_PATH, GITHUB_GRAPHQL_READ_OPERATION,
    site, repository, boundaryCid, providerMoon, commentLimits: {maxRequestBytes: 300_000, maxResponseBytes: 100_000},
    prepareGitHubCommentRequest, commentValue: (_resource, value) => value,
    fail: code => {throw Object.assign(new Error(code), {code});},
    checkGitHubCommentSubject(context) {checks++; assert.equal(context.repository, repository); return 'checked';},
    projectGitHubCommentObservation: () => ({kind: 'typed-success-response'}),
    commentOutcome: () => ({kind: 'provider-response'}),
  });
  const driver = deriveInstalledRowWrite(write, 'github');
  const value = {body: 'original comment', subject_id: 'I_original'};
  const prepared = driver.prepareRequest({member, value});
  const old = prepareGitHubCommentRequest({moon: providerMoon, origin, subjectId: value.subject_id, body: value.body});
  assert.deepEqual(prepared.request, old); assert.equal(prepared.requestCid, old.requestCid);
  assert.equal(driver.requestFacts(prepared.request).value, value);
  assert.equal(driver.checkRequest({request: prepared.request}), 'checked'); assert.equal(checks, 1);
  const calls = [], context = {request: prepared.request, authorization: authorization(GITHUB_COMMENT_CREATE_OPERATION),
    credential: {}, callResource: args => {calls.push(args); return response;}};
  const actual = await driver.send(context);
  const previous = await sendGitHubIssueComment({...context, moon: providerMoon,
    limits: {...write.http, maxNodes: 10_000, maxDepth: 32}});
  assert.deepEqual(actual, previous); assert.deepEqual(calls[0], calls[1]);
  assert.deepEqual(driver.project({request: prepared.request, ...actual}), {kind: 'provider-response'});
});

test('actual GitHub Created classifier retains provider evidence pending original scoped confirmation', () => {
  const source = readFileSync(new URL('../connectors/github/host/installed-github-effect.mjs', import.meta.url), 'utf8');
  const node = parse(source, {ecmaVersion: 'latest', sourceType: 'module'}).body.find(node =>
    node.type === 'FunctionDeclaration' && node.id.name === 'commentOutcome');
  assert.ok(node);
  const classify = Function(`return (${source.slice(node.start, node.end)});`)();
  const observation = Object.freeze({useCid: providerCid, statusCode: 200, body: new Uint8Array([123, 125])});
  const answer = classify({kind: 'typed-success-response', observation,
    result: {commentId: 123, nodeId: 'IC_original'}});
  assert.deepEqual(answer, {kind: 'provider-response', observation,
    providerEvidence: {kind: 'CreatedComment', comment_id: 123, node_id: 'IC_original'}});
  assert.equal(answer.observation, observation);
  assert.equal(Object.hasOwn(answer, 'outcome'), false);
  assert.ok(Object.isFrozen(answer)); assert.ok(Object.isFrozen(answer.providerEvidence));
});

test('Sheets normal declaration keeps full logical value, batch target, original CID and physical exchange', async () => {
  const site = {apiOrigin: origin, spreadsheetId: 'sheet_original', appendSheetId: 7, columns: ['name'], gridRange: {}};
  const providerMoon = {sheetsAppendRequestJson: () => '{"body":"{\\"requests\\":[]}"}',
    sheetsAppendRequestIdentity: () => ({$tag: 1, _0: providerCid})};
  const write = selectedWrite('../connectors/sheets/host/installed-sheets.mjs', {
    site, providerMoon, boundaryCid, SHEETS_APPEND_OPERATION, SHEETS_READ_OPERATION, SHEETS_LIMITS,
    prepareSheetsAppend, fail: code => {throw Object.assign(new Error(code), {code});},
    checkSheetsTarget: context => {assert.equal(context.spreadsheetId, site.spreadsheetId); return 'checked';},
    projectSheetsAppend: () => ({kind: 'provider-response'}),
  });
  const driver = deriveInstalledRowWrite(write, 'sheets');
  const value = {name: 'original'}, selectedMember = {...member, resource: 'append_rows'};
  const prepared = driver.prepareRequest({member: selectedMember, value});
  assert.equal(prepared.requestCid, providerCid); assert.equal(driver.requestFacts(prepared.request).value, value);
  assert.equal(driver.checkRequest({}), 'checked');
  const calls = [], context = {request: prepared.request, authorization: authorization(SHEETS_APPEND_OPERATION),
    credential: {}, callResource: args => {calls.push(args); return response;}};
  assert.deepEqual(await driver.send(context), await sendSheetsAppend(context));
  assert.deepEqual(calls[0], calls[1]);
  assert.equal(calls[0].operations.get(SHEETS_APPEND_OPERATION).path, '/v4/spreadsheets/sheet_original:batchUpdate');
});
