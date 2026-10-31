import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {parse} from 'acorn';
import {createHash} from 'node:crypto';
import {types as nodeTypes} from 'node:util';
import {canonicalJson, contentCid} from './local-account-config.mjs';
import {localContractLimits} from './local-values-plan.mjs';
import {ownHttpRequest, ownRequestHeaders, ownResponseHeaderNames} from '../host-common/http-exchange.mjs';
import {invokeScopedCredentialOperation} from '../host-common/owned-invocation-context.mjs';
import {createInstalledRowEffect} from './installed-row-effect.mjs';
import {prepareGitHubCommentRequest, sendGitHubIssueComment,
  GITHUB_COMMENT_CREATE_OPERATION} from '../connectors/github/site/github-comment-create.mjs';
import * as githubComment from '../connectors/github/site/github-comment-create.mjs';
import {isEffectPreparationRefusal} from '../host-common/effect-preparation-result.mjs';
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
const deriveInstalledRowWriteOriginal = Function('createHash', 'nodeTypes', 'ownHttpRequest', 'ownRequestHeaders',
  'ownResponseHeaderNames', 'invokeScopedCredentialOperation', 'localContractLimits', `return (${rowSource.slice(derivedNode.start, derivedNode.end)});`)(
  createHash, nodeTypes, ownHttpRequest, ownRequestHeaders, ownResponseHeaderNames, invokeScopedCredentialOperation, localContractLimits);
const deriveInstalledRowWrite = (...args) => deriveInstalledRowWriteOriginal(...args).driver;

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

test('standard declared read check owns fixed HTTP while pure callbacks retain only original provider DATA',async()=>{
  let bodyCalls=0,projectCalls=0,reads=0;
  const nativeObservation=Object.freeze({accepted:false,useCid:providerCid,statusCode:200,body:Buffer.from('{"revision":"7"}'),headers:[]});
  const check={resource:'forms',operation:'fixture:form',beforeSend:true,
    http:{origin,method:'POST',path:'/form',headers:[['x-http-method-override','GET']],maxRequestBytes:200,maxResponseBytes:400},
    body(context){assert.equal(this,check);assert.deepEqual(Object.keys(context),['resource','value','request']);assert(Object.isFrozen(context));
      assert.equal(context.resource,'forms');assert.equal(context.request,prepared.request);bodyCalls++;return '{"app":"12"}';},
    project(context){assert.equal(this,check);assert.deepEqual(Object.keys(context),['resource','value','request','accepted','observation','headers']);
      assert.equal(context.accepted,nativeObservation.accepted);
      assert.equal(context.resource,'forms');assert.equal(context.request,prepared.request);assert.equal(context.observation.body,nativeObservation.body);
      assert.equal(context.observation.statusCode,200);assert.equal(context.headers,nativeObservation.headers);assert(Object.isFrozen(context));projectCalls++;}};
  const driver=deriveInstalledRowWrite(declaration({check}),'fixture');
  const prepared=driver.prepareRequest({member,value:{name:'intended'}}),raw=authorization('fixture:form');
  check.body=()=>assert.fail('original body method changed');check.project=()=>assert.fail('original projection changed');check.http.path='/foreign';
  await driver.checkRequest({member,request:prepared.request,authorization:raw,credential:{},
    callResource(options){reads++;assert.equal(options.grant,raw.grant);assert.equal(options.useId,raw.useId);
      assert.deepEqual([...options.operations],[['fixture:form',{method:'POST',path:'/form',body:'{"app":"12"}',headers:[['x-http-method-override','GET']]}]]);
      return nativeObservation;}});
  assert.deepEqual([bodyCalls,projectCalls,reads],[1,1,1]);
  assert.deepEqual(driver.check,{resource:'forms',operation:'fixture:form',beforeSend:true});
});

test('declared read refuses foreign input origin or mixed callback mode before HTTP',async()=>{
  const check={resource:'forms',operation:'fixture:form',http:{origin,method:'POST',path:'/form',maxRequestBytes:200,maxResponseBytes:400},
    body:()=> '{}',project(){}};
  assert.throws(()=>deriveInstalledRowWrite(declaration({check:{...check,request(){}}}),'fixture'),{code:'InvalidInstalledRowWrite'});
  assert.throws(()=>deriveInstalledRowWrite(declaration({check:{...check,http:{...check.http,origin:'https://foreign.test'}}}),'fixture'),{code:'InvalidInstalledRowWrite'});
  let calls=0;
  const driver=deriveInstalledRowWrite(declaration({check}),'fixture'),{request}=driver.prepareRequest({member,value:{}});
  for(const [change,code] of [[{request:{...request}},'InvalidInstalledRowWrite'],
    [{authorization:authorization('foreign-operation')},'InvalidOwnedInvocationContext'],
    [{authorization:{...authorization('fixture:form'),scope:{operation:'fixture:form',resourceOrigin:'https://foreign.test'}}},'InvalidInstalledRowWrite']]){
    await assert.rejects(driver.checkRequest({request,authorization:authorization('fixture:form'),credential:{},
      callResource(){calls++;return response;},...change}),{code});
  }
  assert.equal(calls,0);
});

test('invalid asynchronous declared read projection stays joined through original fulfillment and rejection',async()=>{
  for(const rejected of [false,true]){
    let resolve,reject,entered;
    const original=new Promise((yes,no)=>{resolve=yes;reject=no;}),observed=new Promise(yes=>{entered=yes;});
    const primary=new Error('original read projection rejection');
    const driver=deriveInstalledRowWrite(declaration({check:{resource:'forms',operation:'fixture:form',
      http:{origin,method:'POST',path:'/form',maxRequestBytes:200,maxResponseBytes:400},body:()=> '{}',
      project(){entered();return original;}}}),'fixture');
    const {request}=driver.prepareRequest({member,value:{}});let completed=false;
    const preparing=assert.rejects(driver.checkRequest({request,authorization:authorization('fixture:form'),credential:{},callResource:()=>response}),
      error=>rejected?error===primary:error.code==='InvalidInstalledRowWrite').then(()=>{completed=true;});
    await observed;await new Promise(setImmediate);assert.equal(completed,false);
    if(rejected)reject(primary);else resolve(undefined);
    await preparing;
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

function normalGitHubReadFixture({reply, transportFailure, nativeFailure = 'Unknown', nativeProjection} = {}) {
  const events = [], repository = Object.freeze({nodeId: 'R_original', databaseId: 7,
    nameWithOwner: 'owner/original'}), site = {apiOrigin: origin};
  const commentLimits = {maxRequestBytes: 300_000, maxResponseBytes: 100_000, maxNodes: 10_000, maxDepth: 32};
  const originalBody = Buffer.from('{"original":"response"}');
  const providerMoon = {
    githubAddCommentRequestJson: (subject, body) => JSON.stringify({body: JSON.stringify({subject, body})}),
    githubCommentOutcomeJson() {}, githubRequestHeadersJson: () => '[["accept","application/json"]]',
    githubResponseHeadersJson: () => '["x-ratelimit-remaining"]',
    githubCommentSubjectRequestJson(subject) {
      assert.equal(subject, 'I_original'); events.push('body'); return '{"body":"original-subject-request"}';
    },
    githubCommentSubjectJson(bytes, ...bounds) {
      assert.equal(bytes, originalBody);
      assert.deepEqual(bounds, [100_000, 10_000, 32, 'I_original', 'R_original', 7, 'owner/original']);
      events.push('project');
      return JSON.stringify(nativeProjection ?? {subject: {node_id: 'I_original', number: 3}});
    },
    githubClassifyFailureJson(status, names, values) {
      assert.equal(status, reply.statusCode); assert.deepEqual(names, ['x-ratelimit-remaining']);
      assert.deepEqual(values, ['0']); events.push('classify'); return JSON.stringify({kind: nativeFailure});
    },
  };
  const write = selectedWrite('../connectors/github/host/installed-github-effect.mjs', {
    ...githubComment, GITHUB_GRAPHQL_PATH, GITHUB_GRAPHQL_READ_OPERATION,
    site, repository, boundaryCid, providerMoon, commentLimits,
    commentValue: (_resource, value) => value,
    fail: code => {throw Object.assign(new Error(code), {code});},
    commentOutcome: () => ({kind: 'provider-response'}),
  });
  assert.equal(write.check.request, undefined, 'standard caller cannot retain the provider-owned HTTP entrance');
  assert.deepEqual(write.check.http, {origin, method: 'POST', path: GITHUB_GRAPHQL_PATH,
    headers: [['accept', 'application/json']], responseHeaders: ['x-ratelimit-remaining'],
    maxRequestBytes: 300_000, maxResponseBytes: 100_000});
  const driver = deriveInstalledRowWrite(write, 'github');
  const {request} = driver.prepareRequest({member: {...member, resource: 'issue_comments'},
    value: {subject_id: 'I_original', body: 'same exact comment'}});
  const raw = authorization(GITHUB_GRAPHQL_READ_OPERATION);
  const check = changes => driver.checkRequest({request, authorization: raw, credential: {},
    callResource(options) {
      events.push('HTTP'); assert.equal(options.grant, raw.grant); assert.equal(options.useId, raw.useId);
      assert.deepEqual([...options.operations], [[GITHUB_GRAPHQL_READ_OPERATION, {
        method: 'POST', path: GITHUB_GRAPHQL_PATH, body: 'original-subject-request',
        headers: [['accept', 'application/json']], responseHeaders: ['x-ratelimit-remaining']}]]);
      if (transportFailure !== undefined) throw transportFailure;
      return Object.freeze({accepted: true, statusCode: 200, useCid: providerCid,
        body: originalBody, headers: [['x-ratelimit-remaining', '0']], ...reply});
    }, ...changes});
  return {check, events, request, write};
}

test('standard GitHub subject read uses common HTTP with the original body and repository projection', async () => {
  const f = normalGitHubReadFixture();
  f.write.check.body = () => assert.fail('late body substitution');
  f.write.check.project = () => assert.fail('late projection substitution');
  f.write.check.http.path = '/foreign';
  assert.equal(await f.check(), undefined);
  assert.deepEqual(f.events, ['body', 'HTTP', 'project']);
  await assert.rejects(f.check({request: {...f.request}}), {code: 'InvalidInstalledRowWrite'});
  assert.deepEqual(f.events, ['body', 'HTTP', 'project']);
});

test('standard GitHub subject read preserves observed refusal and uncertain reply categories', async () => {
  for (const [options, code, known] of [
    [{reply: {accepted: false, statusCode: 200}}, 'GitHubCommentSubjectUnverified', false],
    [{reply: {statusCode: 404}, nativeFailure: 'NotFound'}, 'GitHubCommentSubjectRejected', true],
    [{reply: {statusCode: 429}, nativeFailure: 'RateLimited'}, 'GitHubRateLimited', false],
    [{nativeProjection: {refused: {kind: 'ForeignRepository'}}}, 'GitHubCommentForeignRepository', true],
  ]) {
    const f = normalGitHubReadFixture(options);
    await assert.rejects(f.check(), error => {
      assert.equal(error.code, code); assert.equal(isEffectPreparationRefusal(error), known); return true;
    });
    assert.equal(f.events.filter(value => value === 'HTTP').length, 1);
  }
});

test('standard GitHub subject read keeps cancellation and the original transport failure without resend', async () => {
  const cancelled = new Error('cancelled original'), stopped = normalGitHubReadFixture();
  await assert.rejects(stopped.check({signal: AbortSignal.abort(cancelled)}), error => error === cancelled);
  assert.deepEqual(stopped.events, []);
  const lost = new Error('lost original'), failed = normalGitHubReadFixture({transportFailure: lost});
  await assert.rejects(failed.check(), error => error === lost);
  assert.deepEqual(failed.events, ['body', 'HTTP']);
});

// Actual provider factories and the complete changed normal-caller declaration,
// with explicit native codec/check/classifier DATA ports. No Common, Account,
// grant issuer, real provider or normal installed execution is substituted.
test('GitHub normal declaration keeps original GraphQL request, sender envelope and read-before-write check', async () => {
  let checks = 0;
  const providerMoon = {githubAddCommentRequestJson: (subject, body) => JSON.stringify({body: JSON.stringify({subject, body})}),
    githubCommentOutcomeJson() {}, githubRequestHeadersJson: () => '[["accept","application/json"]]',
    githubResponseHeadersJson: () => '["x-ratelimit-remaining"]',
    githubCommentSubjectRequestJson: () => '{"body":"original-subject-request"}',
    githubCommentSubjectJson() {checks++;return '{"subject":{"node_id":"I_original","number":7}}';}};
  const site = {apiOrigin: origin}, repository = Object.freeze({nodeId: 'repository',databaseId:7,nameWithOwner:'owner/original'});
  const write = selectedWrite('../connectors/github/host/installed-github-effect.mjs', {
    GITHUB_COMMENT_CREATE_OPERATION, GITHUB_GRAPHQL_PATH, GITHUB_GRAPHQL_READ_OPERATION,
    site, repository, boundaryCid, providerMoon, commentLimits: {maxRequestBytes: 300_000, maxResponseBytes: 100_000,maxNodes:10_000,maxDepth:32},
    prepareGitHubCommentRequest, commentValue: (_resource, value) => value,
    prepareGitHubCommentSubjectRequest:githubComment.prepareGitHubCommentSubjectRequest,
    projectGitHubCommentSubjectResponse:githubComment.projectGitHubCommentSubjectResponse,
    fail: code => {throw Object.assign(new Error(code), {code});},
    projectGitHubCommentObservation: () => ({kind: 'typed-success-response'}),
    commentOutcome: () => ({kind: 'provider-response'}),
  });
  const driver = deriveInstalledRowWrite(write, 'github');
  const value = {body: 'original comment', subject_id: 'I_original'};
  const prepared = driver.prepareRequest({member, value});
  const old = prepareGitHubCommentRequest({moon: providerMoon, origin, subjectId: value.subject_id, body: value.body});
  assert.deepEqual(prepared.request, old); assert.equal(prepared.requestCid, old.requestCid);
  assert.equal(driver.requestFacts(prepared.request).value, value);
  assert.equal(await driver.checkRequest({request: prepared.request,authorization:authorization(GITHUB_GRAPHQL_READ_OPERATION),
    credential:{},callResource:()=>({...response,statusCode:200})}), undefined); assert.equal(checks, 1);
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


// Complete provider Site helper bodies with explicit service/Account/Site ports.
// These exercise declaration delegation and unchanged legacy arguments, not a
// real Account, Credential, Common or physical Site admission.
for (const connector of ['github', 'sheets']) {
  test(`standard ${connector} Effect Site uses the same Host factory and provider binding`, async () => {
    const path = connector === 'github' ? '../connectors/github/host/installed-github-source.mjs'
      : '../connectors/sheets/host/installed-sheets.mjs';
    const source = readFileSync(new URL(path, import.meta.url), 'utf8');
    const node = parse(source, {ecmaVersion: 'latest', sourceType: 'module'}).body.find(value =>
      value.type === 'FunctionDeclaration' && value.id.name === 'openSite');
    assert.ok(node);
    const originalAuthorization = Object.freeze({context: {contextCid: providerCid}});
    const originalSite = Object.freeze({}), installation = Object.freeze({responseHeaders: ['etag']});
    const secret = async () => 'not-acquired-in-this-case';
    const site = Object.freeze({apiOrigin: origin, owner: 'owner', repo: 'repo',
      spreadsheetId: 'sheet', columns: [{name: 'name'}], siteKey: 'site', siteGeneration: 1,
      namespaceId: 'namespace', environment: 'test', credentialAuthorityId: 'authority', credentialKeyId: 'key'});
    const publication = {catalogCid: providerCid, repository: {id: 42, node_id: 'R_original'}};
    const targetVersion = 'fixture-target/0.1', binding = Object.freeze({spreadsheet: 'sheet'});
    const profile = {accountConfigurationWire: 'original-account-wire'};
    let legacyAccounts = 0, legacySites = 0, calls = 0, delegated;
    const ports = {registration: connector, revision: connector + '/0.1', TARGET_VERSION: targetVersion,
      targetVersion, contentCid, canonicalJson, bindingFacts: () => binding,
      environmentSecret: () => assert.fail('supplied original resolver must be retained'),
      fail: code => {throw Object.assign(new Error(code), {code});},
      async installRowSourceAuthorization(options) {
        legacyAccounts++; assert.equal(options.accountConfiguration, profile.accountConfigurationWire);
        return originalAuthorization;
      },
      async openRowSourceCredentialSite(options) {
        legacySites++; assert.equal(options.authorization, originalAuthorization);
        assert.equal(options.resolveSecret, secret); return originalSite;
      }};
    const open = Function(...Object.keys(ports), `return (${source.slice(node.start, node.end)});`)(...Object.values(ports));
    const options = {root: '/unused-port', principalId: 'principal', moon: {},
      runtimeBundleCid: providerCid, installation, resolveSecret: secret, publication};
    const invoke = services => connector === 'github' ? open(profile, site, options, services)
      : open(profile, site, options, publication, services);
    const services = {openRowSite(selected) {
      assert.equal(this, services); calls++; delegated = selected;
      return {authorization: originalAuthorization, site: originalSite};
    }};
    const result = await invoke(services);
    assert.equal(calls, 1, 'normal Effect must select the original Host Site factory');
    assert.equal(legacyAccounts, 0); assert.equal(legacySites, 0);
    assert.equal(result.authorization, originalAuthorization); assert.equal(result.site, originalSite);
    assert.equal(delegated.installation, installation); assert.equal(delegated.accountConfiguration, profile.accountConfigurationWire);
    assert.equal(delegated.resolveSecret, secret); assert.equal(delegated.responseHeaders, installation.responseHeaders);
    assert.ok(Object.isFrozen(delegated.profile)); assert.equal(delegated.profile.resourceOrigin, origin);
    for (const field of ['root', 'principalId', 'commonMoon', 'runtimeBundleCid', 'assertCurrent']) {
      assert.equal(Object.hasOwn(delegated, field), false, 'Host owns ' + field);
    }
    const target = connector === 'github' ? {version: targetVersion, api_origin: origin,
      repository_id: 42, repository_node_id: 'R_original', owner: 'owner', repo: 'repo',
      catalog_cid: providerCid, resource: 'issues', fields: ['id']}
      : {version: targetVersion, catalog_cid: providerCid, binding, fields: ['name']};
    const resource = connector === 'github' ? 'issues' : 'rows';
    assert.equal(delegated.admitsApprovalTarget(target, resource), true);
    assert.equal(delegated.admitsApprovalTarget({...target, catalog_cid: boundaryCid}, resource), false);
    if (connector === 'github') assert.equal(delegated.admitsApprovalTarget({...target, repository_id: 43}, resource), false);
    else assert.equal(delegated.admitsApprovalTarget({...target, fields: ['foreign']}, resource), false);
    const originalFailure = new Error('original factory failure');
    await assert.rejects(invoke({openRowSite() {throw originalFailure;}}), error => error === originalFailure);
    assert.equal(legacyAccounts, 0); assert.equal(legacySites, 0);
    const legacy = await invoke(undefined);
    assert.equal(legacy.authorization, originalAuthorization); assert.equal(legacy.site, originalSite);
    assert.equal(legacyAccounts, 1); assert.equal(legacySites, 1);
    if (connector === 'sheets') assert.equal(result.bindingCid, legacy.bindingCid);
    assert.equal(result.connection, legacy.connection);
  });
}

// The real existing recovery loop and entry/order comparators, with an explicit
// authenticated-capture DATA port. This is not capture authentication, a real
// Run/Ledger/Store, or physical provider qualification.
test('standard cold recovery uses saved original requests without calling the provider mapping again', () => {
  const selected = name => {
    const matches = [];
    const visit = node => {
      if (!node || typeof node !== 'object') return;
      if (node.type === 'VariableDeclarator' && node.id.name === name) matches.push(node.init);
      for (const value of Object.values(node)) {
        if (Array.isArray(value)) value.forEach(visit);
        else if (value && typeof value === 'object') visit(value);
      }
    };
    visit(rowTree); assert.equal(matches.length, 1, name);
    return rowSource.slice(matches[0].start, matches[0].end);
  };
  let mappings = 0;
  const write = declaration({request() {mappings++; return {path: '/records', body: '{"name":"original"}'};}});
  const driver = deriveInstalledRowWrite(write, 'fixture');
  const originalMember = Object.freeze({kind: 'create', resource: 'records', effectId: 'create'});
  const value = {name: 'original'}, prepared = driver.prepareRequest({member: originalMember, value});
  assert.equal(mappings, 1);
  const owner = {owned: driver};
  const ownerOf = member => {assert.equal(member, originalMember); return owner;};
  const fail = code => {throw Object.assign(new Error(code), {code});};
  const sameValue = (left, right) => canonicalJson(left) === canonicalJson(right);
  const targeted = kind => ['update', 'upsert', 'delete'].includes(kind);
  const ports = {singular: owner, ownerOf, resourceFields: () => ({}), fail,
    sameValue, targeted, cidPattern: /^sha256:[0-9a-f]{64}$/u};
  const recoveredEntries = Function(...Object.keys(ports), `
    const approvedValue = ${selected('approvedValue')};
    const sameEffectValue = ${selected('sameEffectValue')};
    const entryOf = ${selected('entryOf')};
    const orderedSourceIndexes = ${selected('orderedSourceIndexes')};
    return ${selected('recoveredEntries')};`)(...Object.values(ports));
  // If the standard driver supplies the existing capture codec, retain its
  // original output; a legacy driver has no such saved request material.
  const recovery = driver.recoveryEntry?.({member: originalMember,
    entries: [{...prepared, value}], current: undefined});
  const durable = {connectorRecovery: recovery === undefined ? [] : [{memberIndex: 0, ...recovery}]};
  const rowCid = `sha256:${'c'.repeat(64)}`;
  const result = recoveredEntries({members: [originalMember],
    body: {effects: [{effect_id: 'create', changes: [{row_preview_cid: rowCid,
      after: {value}, target_row_identity: {content_cid: providerCid, occurrence: 0}}], row_order: [rowCid]}]},
    durable, recorded: {members: [{claims: [{canonicalRequestCid: prepared.requestCid}]}]},
    previewWire: 'explicit admitted Preview port', runInvocationCid: providerCid, dispatches: [boundaryCid]});
  assert.equal(mappings, 1, 'cold restore must not re-execute request mapping or issue a new tag');
  assert.equal(result.entries[0][0].requestCid, prepared.requestCid);
  assert.equal(result.entries[0][0].request.body, prepared.request.body);
  assert.deepEqual(result.entries[0][0].value, value);
});

test('standard saved request preserves provider CID, full DATA and composed global member selection', () => {
  const selectedMember = Object.freeze({kind: 'create', resource: 'records', effectId: 'second'});
  const value = {name: 'é\r\n', nested: {items: [1, null, false]}};
  const write = declaration({request: () => ({path: '/records', body: '{"name":"é\\r\\n"}',
    requestCid: providerCid, metadata: {label: 'é\r\n', ordering: ['b', 'a']}})});
  const fresh = deriveInstalledRowWrite(write, 'fixture');
  const prepared = fresh.prepareRequest({member: selectedMember, value});
  const saved = fresh.recoveryEntry({member: selectedMember, entries: [{...prepared, value}]});
  const cold = deriveInstalledRowWrite({...write, request() {assert.fail('cold must not map or create a tag');}}, 'fixture');
  const restored = cold.recoverMemberRequests({members: [{kind: 'create', resource: 'unrelated'}, selectedMember],
    memberIndexes: [1], durable: {connectorRecovery: [{memberIndex: 1, ...saved}]}}).requests[0][0];
  assert.equal(cold.requestCid(restored), providerCid);
  assert.equal(restored.body, prepared.request.body);
  assert.deepEqual(restored.metadata, prepared.request.metadata);
  assert.deepEqual(cold.requestFacts(restored).value, value);
  assert.ok(Object.isFrozen(restored.metadata.ordering));
  assert.throws(() => cold.requestCid({...restored}), {code: 'InvalidInstalledRowWrite'});
  assert.throws(() => prepared.request.metadata.ordering.push('changed'), TypeError);
});

test('standard saved request refuses missing, changed, duplicate and foreign binding material', () => {
  const fresh = deriveInstalledRowWrite(declaration(), 'fixture');
  const value = {name: 'original'}, prepared = fresh.prepareRequest({member, value});
  const saved = fresh.recoveryEntry({member, entries: [{...prepared, value}]});
  const row = {memberIndex: 0, ...saved};
  const restore = (driver, records, members = [member]) => driver.recoverRequests({members,
    durable: {connectorRecovery: records}});
  for (const records of [[], [row, row], [{...row, wire: row.wire + ' '}],
    [{...row, observationCid: boundaryCid}], [{...row, memberIndex: 1}]]) {
    assert.throws(() => restore(fresh, records), {code: 'InvalidInstalledRowWrite'});
  }
  assert.throws(() => restore(fresh, [row], [{...member, resource: 'foreign'}]), {code: 'InvalidInstalledRowWrite'});
  for (const write of [declaration({boundaryCid: providerCid}),
    declaration({http: {...declaration().http, headers: [['accept', 'text/plain']]}}),
    declaration({http: {...declaration().http, maxResponseBytes: 401}})]) {
    assert.throws(() => restore(deriveInstalledRowWrite(write, 'fixture'), [row]), {code: 'InvalidInstalledRowWrite'});
  }
  assert.throws(() => fresh.recoveryEntry({member, entries: [{...prepared, value: {...value}}]}),
    {code: 'InvalidInstalledRowWrite'});
});

test('standard saved request bounds real JSON material and refuses opaque or effectful serialization', () => {
  let getters = 0;
  const accessor = Object.defineProperty({}, 'hidden', {enumerable: true, get() {getters++; return 'forbidden';}});
  const cyclic = {}; cyclic.self = cyclic;
  const opaque = Object.freeze(Object.create({nominal: true}));
  const hidden = Object.defineProperty({}, 'hidden', {value: 'not-on-wire'});
  for (const metadata of [accessor, cyclic, opaque, hidden, {missing: undefined},
    {toJSON() {getters++; return 'forbidden';}}, [,'hole'], {number: -0}, {number: Infinity}]) {
    const driver = deriveInstalledRowWrite(declaration({request: () => ({path: '/records', body: '{}', metadata})}), 'fixture');
    assert.throws(() => driver.prepareRequest({member, value: {name: 'original'}}), {code: 'InvalidInstalledRowWrite'});
  }
  assert.equal(getters, 0);
  const driver = deriveInstalledRowWrite(declaration({request: () => ({path: '/records', body: '{}',
    metadata: 'x'.repeat(localContractLimits.maxWireBytes)})}), 'fixture');
  const value = {name: 'original'}, prepared = driver.prepareRequest({member, value});
  assert.throws(() => driver.recoveryEntry({member, entries: [{...prepared, value}]}), {code: 'InvalidInstalledRowWrite'});
});

test('standard declared check retains the same independent mapped row on fresh and saved request restoration',async()=>{
  let expected,bodyCalls=0,projectCalls=0;
  const write=declaration({check:{resource:'forms',operation:'fixture:form',
    http:{origin,method:'POST',path:'/form',maxRequestBytes:200,maxResponseBytes:400},
    body(context){assert.equal(context.value,expected);assert(Object.isFrozen(context.value));bodyCalls++;return '{}';},
    project(context){assert.equal(context.value,expected);assert(Object.isFrozen(context.value));projectCalls++;}}});
  const driver=deriveInstalledRowWrite(write,'fixture'),value={name:'same approved value'};
  const prepared=driver.prepareRequest({member,value});
  expected=driver.requestFacts(prepared.request).value;
  const observe=request=>driver.checkRequest({request,authorization:authorization('fixture:form'),credential:{},callResource:()=>response});
  await observe(prepared.request);
  const saved=driver.recoveryEntry({member,entries:[{...prepared,value}]});
  const restored=driver.recoverRequests({durable:{connectorRecovery:[{...saved,memberIndex:0}]},members:[member]}).requests[0][0];
  expected=driver.requestFacts(restored).value;
  assert.notEqual(expected,value);
  assert.deepEqual(expected,value);
  await observe(restored);
  assert.deepEqual([bodyCalls,projectCalls],[2,2]);
});

test('standard mapper consumes and saves exact original proposal wire without reconstructing it on cold restore',()=>{
  const wire='{"state":"present","value":{"name":"same é"}}',value=JSON.parse(wire).value;
  let maps=0;
  const driver=deriveInstalledRowWrite(declaration({request(context){
    assert.equal(context.proposalWire,wire);assert.equal(context.value,value);maps++;
    return {path:'/records',body:'{"native":"same"}',proposalWire:context.proposalWire};
  }}),'fixture');
  const prepared=driver.prepareRequest({member,value,proposalWire:wire});
  const saved=driver.recoveryEntry({member,entries:[{...prepared,value}]});
  const restored=driver.recoverRequests({members:[member],durable:{connectorRecovery:[{...saved,memberIndex:0}]}}).requests[0][0];
  assert.equal(maps,1);
  assert.equal(restored.proposalWire,wire);
  assert.equal(driver.requestCid(restored),prepared.requestCid);
  assert.equal(restored.body,prepared.request.body);
});

test('standard declaration supplies its same immutable construction facts without calling a provider', () => {
  const unused = () => assert.fail('No provider constructor or I/O while selecting DATA');
  const write = declaration({request: unused, classify: unused, check: {
    resource: 'forms', operation: 'fixture:form', beforeSend: true,
    http: {origin, method: 'POST', path: '/form', headers: [['accept', 'application/json']],
      maxRequestBytes: 101, maxResponseBytes: 103}, body: unused, project: unused}});
  const original = deriveInstalledRowWriteOriginal(write, 'fixture');
  assert(Object.isFrozen(original)); assert(Object.isFrozen(original.driver));
  const facts = original.construction;
  assert(Object.isFrozen(facts)); assert(Object.isFrozen(facts.write)); assert(Object.isFrozen(facts.check));
  assert.deepEqual(facts.write, {operation: 'fixture:create', maxRequestBytes: 200, maxResponseBytes: 400});
  assert.deepEqual(facts.check, {resource: 'forms', operation: 'fixture:form', beforeSend: true,
    maxRequestBytes: 101, maxResponseBytes: 103});
  assert(Number.isSafeInteger(facts.metadataTextUnits) && facts.metadataTextUnits > origin.length);
  write.http.maxRequestBytes = 1; write.check.http.maxResponseBytes = 1;
  assert.equal(facts.write.maxRequestBytes, 200); assert.equal(facts.check.maxResponseBytes, 103);
});

test('standard construction facts distinguish no check from an original legacy check', () => {
  const plain = deriveInstalledRowWriteOriginal(declaration(), 'fixture');
  assert.strictEqual(plain.construction.check, undefined);
  const legacy = deriveInstalledRowWriteOriginal(declaration({check: {resource: 'forms', operation: 'fixture:form',
    request() {assert.fail('Legacy callback must not run during declaration selection');}}}), 'fixture');
  assert.strictEqual(legacy.construction.check, null);
  assert.equal(typeof legacy.driver.checkRequest, 'function');
});
