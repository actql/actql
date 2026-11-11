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
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeField} from '../host-common/compiler-binding.generated.mjs';
import {prepareInstalledEffectControlConstruction} from './installed-effect-plan.mjs';
import {GITHUB_GRAPHQL_PATH, GITHUB_GRAPHQL_READ_OPERATION} from
  '../connectors/github/site/github-issue-graphql-read.mjs';
import {prepareSheetsAppend, sendSheetsAppend, SHEETS_APPEND_OPERATION,
  SHEETS_READ_OPERATION, SHEETS_LIMITS, prepareSheetsTargetRequest, projectSheetsTarget}
  from '../connectors/sheets/site/sheets-exchange.mjs';

// Execute the complete internal adapter with its actual transport callees.
// The constructor test below separately imports and exercises its real caller.
const rowSource = readFileSync(new URL('./installed-row-effect.mjs', import.meta.url), 'utf8');
const rowTree = parse(rowSource, {ecmaVersion: 'latest', sourceType: 'module'});
const derivedNode = rowTree.body.find(node => node.type === 'FunctionDeclaration' && node.id.name === 'deriveInstalledRowWrite');
assert.ok(derivedNode);
const deriveInstalledRowWriteOriginal = Function('createHash', 'nodeTypes', 'canonicalJson', 'ownHttpRequest', 'ownRequestHeaders',
  'ownResponseHeaderNames', 'invokeScopedCredentialOperation', 'localContractLimits', `return (${rowSource.slice(derivedNode.start, derivedNode.end)});`)(
  createHash, nodeTypes, canonicalJson, ownHttpRequest, ownRequestHeaders, ownResponseHeaderNames, invokeScopedCredentialOperation, localContractLimits);
const deriveInstalledRowWrite = (...args) => deriveInstalledRowWriteOriginal(...args).driver;

// Actual private member constructor and existing exact-JSON decoder. The
// explicit Core port counts work/ordering; no admission or identity is issued.
function createRowsFixture(parse) {
  const named = name => rowTree.body.find(node => node.type === 'VariableDeclaration' &&
    node.declarations.some(value => value.id.name === name));
  const fn = rowTree.body.find(node => node.type === 'FunctionDeclaration' && node.id.name === 'prepareInstalledCreateRows');
  assert(fn);
  return new Function('runtimeField', 'checked', 'JSON',
    [named('fail'), named('parseExactJson')].map(node => rowSource.slice(node.start, node.end)).join('\n') +
    '\nreturn (' + rowSource.slice(fn.start, fn.end) + ');')(runtimeField, checked, {parse, stringify: JSON.stringify});
}

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

test('standard declared GET metadata check preserves the original absent body',async()=>{
  let reads=0,projects=0;
  const check={resource:'forms',operation:'fixture:form',
    http:{origin,method:'GET',path:'/form',maxRequestBytes:200,maxResponseBytes:400},
    body(){return undefined;},project(){projects++;}};
  const driver=deriveInstalledRowWrite(declaration({check}),'fixture');
  const {request}=driver.prepareRequest({member,value:{name:'original'}});
  await driver.checkRequest({request,authorization:authorization('fixture:form'),credential:{},
    callResource(options){
      reads++;const operation=options.operations.get('fixture:form');
      assert.deepEqual(operation,{method:'GET',path:'/form'});
      assert.equal(Object.hasOwn(operation,'body'),false);return response;
    }});
  assert.deepEqual([reads,projects],[1,1]);
});

test('standard metadata projection uses its original managed control frame after HTTP', async () => {
  const events=[],parent={},prepared={},requestOriginal={},plan={};let active=false;
  const runtime={clientProgramInstalledEffectOperationControlConstructionBegin(p,v,r,selected){
    assert.deepEqual([p,v,r,selected],[parent,prepared,requestOriginal,plan]);assert(!active);active=true;events.push('begin');return {$tag:1};},
    clientProgramInstalledEffectOperationControlConstructionComplete(){assert(active);active=false;events.push('complete');return {$tag:1};}};
  const run={runtime,value:parent,prepared,request:requestOriginal,operationPlan:plan,readPlan(){},closed:false};
  const control=prepareInstalledEffectControlConstruction(run);run.controlConstruction=control;run.retireControlConstruction=control.retire;
  const check={resource:'forms',operation:'fixture:form',
    http:{origin,method:'GET',path:'/form',maxRequestBytes:200,maxResponseBytes:400},body(){return undefined;},
    project(context){assert.equal(this,check);assert(active);assert.equal(context.request,request);events.push('project');}};
  const driver=deriveInstalledRowWrite(declaration({check}),'fixture');
  const {request}=driver.prepareRequest({member,value:{name:'original'}});
  check.project=()=>assert.fail('the captured original projector is required');
  await driver.checkRequest({request,authorization:authorization('fixture:form'),credential:{},controlConstruction:control,
    callResource(){assert(!active);events.push('http');return response;}});
  assert.deepEqual(events,['begin','complete','http','begin','project','complete']);assert.equal(control.retire(),true);
});

test('standard metadata invalid async projection keeps the original control borrower until settlement', async () => {
  let resolve,completed=0;
  const pending=new Promise(yes=>{resolve=yes;});
  const runtime={clientProgramInstalledEffectOperationControlConstructionBegin:()=>({$tag:1}),
    clientProgramInstalledEffectOperationControlConstructionComplete(){completed++;return {$tag:1};}};
  const run={runtime,value:{},prepared:{},request:{},operationPlan:{},readPlan(){},closed:false};
  const control=prepareInstalledEffectControlConstruction(run);run.controlConstruction=control;run.retireControlConstruction=control.retire;
  const driver=deriveInstalledRowWrite(declaration({check:{resource:'forms',operation:'fixture:form',
    http:{origin,method:'GET',path:'/form',maxRequestBytes:200,maxResponseBytes:400},body(){return undefined;},
    project(){return pending;}}}),'fixture');
  const {request}=driver.prepareRequest({member,value:{name:'original'}});
  await assert.rejects(driver.checkRequest({request,authorization:authorization('fixture:form'),credential:{},
    controlConstruction:control,callResource:()=>response}),{code:'InvalidInstalledEffectControlConstruction'});
  assert.equal(completed,1,'only the earlier request body completed');assert.equal(run.selecting,true);assert.equal(control.retire(),false);
  resolve();await pending;await Promise.resolve();
  assert.equal(run.selecting,false);assert.equal(control.retire(),true);
});

test('absent declared metadata body preserves POST invalid-body and unsupported HEAD refusals',async()=>{
  let reads=0;
  const selected=(method,body)=>deriveInstalledRowWrite(declaration({check:{resource:'forms',operation:'fixture:form',
    http:{origin,method,path:'/form',maxRequestBytes:200,maxResponseBytes:400},body,project(){}}}),'fixture');
  const invoke=driver=>{
    const {request}=driver.prepareRequest({member,value:{name:'original'}});
    return driver.checkRequest({request,authorization:authorization('fixture:form'),credential:{},
      callResource(){reads++;assert.fail('no HTTP from refused metadata body');}});
  };
  assert.throws(()=>selected('HEAD',()=>undefined),{code:'InvalidHttpRequestMethod'});
  for(const [method,value] of [['POST',undefined],['GET',null]]){
    await assert.rejects(invoke(selected(method,()=>value)),{code:'InvalidInstalledRowWrite'});
  }
  assert.equal(reads,0);
});

test('invalid asynchronous metadata body stays joined and preserves an original undefined rejection',async()=>{
  for(const rejected of [false,true]){
    let resolve,reject,entered,settled=false;
    const original=new Promise((yes,no)=>{resolve=yes;reject=no;}),observed=new Promise(yes=>{entered=yes;});
    const driver=deriveInstalledRowWrite(declaration({check:{resource:'forms',operation:'fixture:form',
      http:{origin,method:'GET',path:'/form',maxRequestBytes:200,maxResponseBytes:400},
      body(){entered();return original;},project(){assert.fail('no projection after invalid body');}}}),'fixture');
    const {request}=driver.prepareRequest({member,value:{name:'original'}});
    const work=driver.checkRequest({request,authorization:authorization('fixture:form'),credential:{},
      callResource(){assert.fail('no HTTP from invalid asynchronous body');}}).then(
      ()=>assert.fail('invalid asynchronous body cannot succeed'),cause=>{
        settled=true;if(rejected)assert.strictEqual(cause,undefined);
        else assert.equal(cause.code,'InvalidInstalledRowWrite');
      });
    await observed;await new Promise(yes=>setImmediate(yes));assert.equal(settled,false);
    if(rejected)reject(undefined);else resolve(undefined);
    await work;assert.equal(settled,true);
  }
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
    ...githubComment,
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
  const logical = driver.prepareRequest({member, value});
  assert.deepEqual(logical.request, githubComment.prepareGitHubCommentLogicalRequest({origin,
    subjectId: value.subject_id, body: value.body}));
  assert.equal(driver.capabilityRequestCid(logical.request), logical.requestCid);
  assert.equal(driver.requestFacts(logical.request).value, value);
  assert.equal(await driver.checkRequest({request: logical.request,authorization:authorization(GITHUB_GRAPHQL_READ_OPERATION),
    credential:{},callResource:()=>({...response,statusCode:200})}), undefined); assert.equal(checks, 1);
  const requestTag = `sha256:${'e'.repeat(64)}`;
  const prepared = driver.finalizeRequest({request: logical.request, requestTag});
  assert.strictEqual(driver.finalizeRequest({request: logical.request, requestTag}), prepared);
  const old = prepareGitHubCommentRequest({moon: providerMoon, origin, subjectId: value.subject_id,
    body: `${value.body}\n\n<!-- actql:effect:${requestTag} -->`});
  assert.deepEqual(prepared.request, {...old, logicalBody: value.body, requestTag});
  assert.equal(prepared.requestCid, old.requestCid);
  assert.equal(driver.requestFacts(prepared.request).value, value);
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
    prepareSheetsTargetRequest, projectSheetsTarget(context) {
      assert.equal(context.spreadsheetId,site.spreadsheetId);assert.equal(context.response.body,response.body);
    },
    projectSheetsAppend: () => ({kind: 'provider-response'}),
  });
  const driver = deriveInstalledRowWrite(write, 'sheets');
  const value = {name: 'original'}, selectedMember = {...member, resource: 'append_rows'};
  const prepared = driver.prepareRequest({member: selectedMember, value});
  assert.equal(prepared.requestCid, providerCid); assert.equal(driver.requestFacts(prepared.request).value, value);
  let reads=0;
  await driver.checkRequest({request:prepared.request,authorization:authorization(SHEETS_READ_OPERATION),credential:{},
    callResource(options){reads++;const selected=options.operations.get(SHEETS_READ_OPERATION);
      assert.equal(selected.method,'GET');assert.equal(Object.hasOwn(selected,'body'),false);return response;}});
  assert.equal(reads,1);
  const calls = [], context = {request: prepared.request, authorization: authorization(SHEETS_APPEND_OPERATION),
    credential: {}, callResource: args => {calls.push(args); return response;}};
  assert.deepEqual(await driver.send(context), await sendSheetsAppend(context));
  assert.deepEqual(calls[0], calls[1]);
  assert.equal(calls[0].operations.get(SHEETS_APPEND_OPERATION).path, '/v4/spreadsheets/sheet_original:batchUpdate');
});

test('actual Sheets append exposes its original metadata HTTP phase to the same-parent Plan',()=>{
  const site={apiOrigin:origin,spreadsheetId:'sheet_original',appendSheetId:7,columns:['name'],gridRange:{}};
  const providerMoon={},write=selectedWrite('../connectors/sheets/host/installed-sheets.mjs',{
    site,providerMoon,boundaryCid,SHEETS_APPEND_OPERATION,SHEETS_READ_OPERATION,SHEETS_LIMITS,
    prepareSheetsAppend,prepareSheetsTargetRequest,
    projectSheetsTarget(){assert.fail('no metadata projection during original declaration');},
    projectSheetsAppend(){assert.fail('no output projection during original declaration');},
    fail:code=>{throw Object.assign(new Error(code),{code});},
  });
  const original=deriveInstalledRowWriteOriginal(write,'sheets');
  assert.deepEqual(original.construction.check,{resource:'rows',operation:SHEETS_READ_OPERATION,
    beforeSend:false,maxRequestBytes:SHEETS_LIMITS.maxRequestBytes,maxResponseBytes:SHEETS_LIMITS.maxResponseBytes});
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
    const validateRecoveredEntries = ${selected('validateRecoveredEntries')};
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

test('same Common CREATE inventory refuses before Host JSON materialization without another check', () => {
  const calls = [], primary = new Error('original Common inventory refusal');
  const construct = createRowsFixture(wire => {calls.push('host-parse'); return JSON.parse(wire);});
  const wire = '{not a Host JSON document';
  const moon = {clientProgramEffectCreateRowInventory(wires, rows, bytes, nodes, depth) {
    assert.deepEqual(wires, [wire]); assert.deepEqual([rows, bytes, nodes, depth], [1, 101, 17, 5]);
    calls.push('same-common-inventory'); throw primary;
  }};
  assert.throws(() => construct(moon, [{changesWire: wire}], {maxWireBytes: 101, maxNodes: 17, maxDepth: 5}),
    error => error === primary);
  assert.deepEqual(calls, ['same-common-inventory']);
});

test('CREATE materialization consumes the same admitted wires once in original Common order', () => {
  const a = '{"state":"present","value":{"name":"first"}}';
  const b = '{"state":"present","value":{"name":"second"}}';
  const aIdentity = '{"content_cid":"first","occurrence":0}';
  const bIdentity = '{"content_cid":"second","occurrence":0}';
  let reads = 0, checks = 0;
  const first = {get changesWire() {reads++; return a;}};
  const second = {get changesWire() {reads++; return b;}};
  const parsed = [];
  const construct = createRowsFixture(wire => {parsed.push(wire); return JSON.parse(wire);});
  const moon = {clientProgramEffectCreateRowInventory(wires, rows, bytes, nodes, depth) {
    checks++; assert.equal(parsed.length, 0); assert.deepEqual(wires, [a, b]);
    assert.deepEqual([rows, bytes, nodes, depth], [2, 101, 17, 5]);
    Object.defineProperty(first, 'changesWire', {get() {assert.fail('No wrapper reread after Common');}});
    Object.defineProperty(second, 'changesWire', {get() {assert.fail('No wrapper reread after Common');}});
    return {$tag: 1, _0: [{_0: 1, _1: bIdentity}, {_0: 0, _1: aIdentity}]};
  }};
  const selected = construct(moon, [first, second], {maxWireBytes: 101, maxNodes: 17, maxDepth: 5});
  assert.equal(checks, 1); assert.equal(reads, 2);
  assert.deepEqual(parsed, [b, bIdentity, a, aIdentity]);
  assert.deepEqual(selected.rows.map(row => row.value.name), ['second', 'first']);
  assert.deepEqual(selected.rows.map(row => row.proposalWire), [b, a]);
  selected.createRows.forEach((row, index) => {
    assert.strictEqual(row.entry, selected.rows[index]); assert(Object.isFrozen(row.identity));
  });
});

test('CREATE original Common failures and empty inventory do not start Host JSON construction', () => {
  const construct = createRowsFixture(() => assert.fail('No Host parse after a Common failure or for zero rows'));
  const primary = new Error('same original typed issue');
  assert.throws(() => construct({clientProgramEffectCreateRowInventory: () => ({$tag: 0, _0: primary})},
    [{changesWire: 'original'}], {maxWireBytes: 101, maxNodes: 17, maxDepth: 5}),
  error => error.code === 'MoonBitHostFailure' && error.cause === primary);
  let caught = false;
  try {construct({clientProgramEffectCreateRowInventory() {throw undefined;}}, [{changesWire: 'original'}],
    {maxWireBytes: 101, maxNodes: 17, maxDepth: 5});}
  catch (cause) {caught = true; assert.strictEqual(cause, undefined);}
  assert.equal(caught, true);
  let calls = 0;
  const empty = construct({clientProgramEffectCreateRowInventory(wires, rows) {
    assert.deepEqual(wires, []); assert.equal(rows, 0); calls++; return {$tag: 1, _0: []};}}, [],
  {maxWireBytes: 101, maxNodes: 17, maxDepth: 5});
  assert.deepEqual(empty, {rows: [], createRows: []}); assert.equal(calls, 1);
});

test('actual Sheets constructor binding forwards the original opaque profile with same metadata and receiver', () => {
  const source = readFileSync(new URL('../connectors/sheets/host/installed-sheets.mjs', import.meta.url), 'utf8');
  const node = parse(source, {ecmaVersion: 'latest', sourceType: 'module'}).body.find(value =>
    value.type === 'FunctionDeclaration' && value.id.name === 'bindSheetsAppendConstructionProfile');
  assert.ok(node);
  const bind = Function('nodeTypes', 'SHEETS_LIMITS', 'fail', `return (${source.slice(node.start,node.end)});`)(
    nodeTypes, SHEETS_LIMITS, code => {throw Object.assign(new Error(code), {code});});
  const columns = Object.freeze([Object.freeze({name:'é😀',type:'string',nullable:false})]);
  const original = Object.freeze({}), calls = [];
  const provider = {sheetsAppendRequestConstructionProfile(...args) {assert.equal(this,provider);calls.push(args);return original;}};
  const bound = bind(provider,columns);
  // Replacing the namespace property cannot substitute another original method.
  provider.sheetsAppendRequestConstructionProfile = () => assert.fail('replacement must not run');
  assert.equal(bound.installedStandardCreateConstructionProfile(512,32,8),original);
  assert.deepEqual(calls,[[Buffer.byteLength(JSON.stringify(columns)),1,512,32,8,
    SHEETS_LIMITS.maxRequestBytes,SHEETS_LIMITS.maxResponseBytes,SHEETS_LIMITS.maxNodes,SHEETS_LIMITS.maxDepth]]);
  assert.ok(Object.isFrozen(bound));
  let getters=0;
  const accessor = Object.defineProperty({},'sheetsAppendRequestConstructionProfile',{get(){getters++;return ()=>original;}});
  for (const bad of [accessor,new Proxy(provider,{}),{sheetsAppendRequestConstructionProfile:async()=>original},{}]) {
    assert.throws(()=>bind(bad,columns),{code:'InstalledStandardCreateRuntimeUnavailable'});
  }
  assert.equal(getters,0);
});

test('actual automatic CREATE factory forwards the same earlier proposal bounds separately from Preview', () => {
  const found=[];
  const walk=node=>{
    if(!node||typeof node!=='object')return;
    if(node.type==='VariableDeclarator'&&node.id.name==='planRecipe')found.push(node.init);
    for(const value of Object.values(node))if(Array.isArray(value))value.forEach(walk);else walk(value);
  };
  walk(rowTree);assert.equal(found.length,1);
  const node=found[0],moon={},providerMoon={},construction={},credential={},credentialSite={},selected={};
  const limits={preview:{maxWireBytes:1000000,maxNodes:100000,maxDepth:64},body:{maxBytes:100000,maxNodes:10000,maxDepth:16}};
  const choose=Function('automatic','prepareInstalledStandardCreatePlanRecipe','moon','providerMoon','construction',
    'installedRowCredentialOperationSite','site','limits','resourceTextUnits','suppliedRecipe',`return (${rowSource.slice(node.start,node.end)});`);
  const result=choose(true,options=>{
    assert.equal(options.moon,moon);assert.equal(options.providerMoon,providerMoon);assert.equal(options.construction,construction);
    assert.equal(options.credentialSite,credentialSite);assert.equal(options.limits,limits.preview);
    assert.deepEqual(options.requestInput,{maxWireBytes:100000,maxNodes:10000,maxDepth:16});assert(Object.isFrozen(options.requestInput));
    return selected;
  },moon,providerMoon,construction,original=>{assert.equal(original,credential);return credentialSite;},
  {credential},limits,7,undefined);
  assert.equal(result,selected);
});

function selectedSheetsInitialization(ports, name = 'load') {
  const source = readFileSync(new URL('../connectors/sheets/host/installed-sheets.mjs', import.meta.url), 'utf8');
  const names = new Set(['readJson','readSite','restore','mappingOf','readPublication','openSite',
    'bindSheetsAppendConstructionProfile','load']);
  const bodies = parse(source, {ecmaVersion:'latest',sourceType:'module'}).body
    .filter(node => node.type === 'FunctionDeclaration' && names.has(node.id.name))
    .map(node => source.slice(node.start,node.end)).join('\n');
  return Function(...Object.keys(ports), bodies + `\nreturn ${name};`)(...Object.values(ports));
}
const initializedSheetsSite = () => ({version:'actql-installed-sheets-site/0.1',
  apiOrigin:origin,spreadsheetId:'book',gridRange:{sheetId:0,startRow:0,endRow:1,startColumn:0,endColumn:1},
  appendSheetId:7,columns:[{name:'name',type:'string',nullable:false}],namespaceId:'namespace',
  environment:'test',siteKey:'site',siteGeneration:1,credentialAuthorityId:'authority',
  credentialKeyId:'key',credentialPrivateKeyPath:'/explicit/key',journalRoot:'/explicit/journal',
  tokenEnvironment:'SHEETS_TEST_TOKEN'});

test('actual Sheets initial caller keeps original configuration declaration Mapping and Site owner through installation', async () => {
  const site = initializedSheetsSite(), scope = {}, installation = {}, declaration = {},
    declared = {catalog_cid:providerCid}, environment = Object.freeze({wire:'original-environment'}),
    originalMappings = Object.freeze([Object.freeze({resource:'append_rows',mappingRef:'mapping',mappingCid:providerCid,body:'original-body'})]),
    adapter = {}, calls = [];
  const bindingFacts = value => ({api_origin:value.apiOrigin,spreadsheet_id:value.spreadsheetId,
    read_grid:value.gridRange,append_sheet_id:value.appendSheetId,columns:value.columns});
  const publicationBody = {version:'actql-sheets-publication/0.1',connectorId:'sheet',catalogCid:providerCid,binding:bindingFacts(site)};
  const publication = {...publicationBody,publication_cid:contentCid(publicationBody)};
  const reader = {async readJson(path,options) {assert.equal(this,reader);assert.equal(options.maxBytes,1048576);
    calls.push(path);return path==='/explicit/site'?site:publication;},readText(){assert.fail('No text read');}};
  const legacy = () => assert.fail('No legacy declaration Mapping Environment or raw file producer');
  scope.prepareAuthoredDeclaration = function(wire,expected) {assert.equal(this,scope);assert.equal(expected,undefined);
    assert.deepEqual(JSON.parse(wire),{views:[{resource:'rows',resource_kind:'sheet_rows',fields:site.columns}]});
    calls.push('declaration');return {declaration,declared};};
  scope.prepareMappings = function(wire,writes) {assert.equal(this,scope);assert.equal(JSON.parse(wire).writes[0].create.permission,SHEETS_APPEND_OPERATION);
    assert.equal(writes.length,1);assert.equal(writes[0].resource,'append_rows');assert(Object.isFrozen(writes));
    assert(Object.isFrozen(writes[0]));assert(Object.isFrozen(writes[0].sources));assert(Object.isFrozen(writes[0].sources[0]));
    calls.push('mappings');return {declaration,declared,environment,mappings:originalMappings};};
  const authorization={context:{contextCid:providerCid}},siteOwner={};
  const services={async openRowSite(options) {assert.equal(this,services);assert.equal(options.installation,installation);
    assert.equal(options.sourceInitialization,scope);assert.deepEqual(calls,['/explicit/site','declaration','/explicit/publication','mappings']);
    calls.push('site');return {authorization,site:siteOwner};}};
  const providerMoon={sheetsAppendRequestConstructionProfile(){assert.fail('No native quote before existing Effect factory');}};
  const {captureConfigurationReaders} = await import('./source-profile-json.mjs');
  const load=selectedSheetsInitialization({nodeTypes,captureConfigurationReaders,registration:'sheets',revision:'sheets/0.1',
    publicationVersion:'actql-sheets-publication/0.1',targetVersion:'actql-installed-sheets-target/0.1',
    SHEETS_SITE_VERSION:'actql-installed-sheets-site/0.1',siteKeys:Object.keys(site).filter(k=>k!=='version'),SHEETS_LIMITS,SHEETS_APPEND_OPERATION,SHEETS_READ_OPERATION,
    text:x=>typeof x==='string'&&x.length>0,absolute:x=>typeof x==='string'&&x.startsWith('/'),
    gridIndex:x=>Number.isInteger(x)&&x>=0&&x<=2147483647,
    exact:(x,keys)=>x&&Object.keys(x).sort().join('\0')===[...keys].sort().join('\0'),
    fail:code=>{throw Object.assign(new Error(code),{code});},checked,canonicalJson,contentCid,bindingFacts,
    readFile:legacy,rowSourceMapping:legacy,rowSourceCheckEnvironment:legacy,
    installRowSourceAuthorization:legacy,openRowSourceCredentialSite:legacy,
    checkSheetsGridConfiguration(moon,columns,range){assert.equal(moon,providerMoon);assert.equal(columns,site.columns);},
    prepareSheetsTargetRequest,prepareSheetsAppend,projectSheetsTarget,projectSheetsAppend:legacy,
    createInstalledRowEffect:async options=>{assert.equal(options.sourceInitialization,scope);
      assert.equal(options.declaration,declaration);assert.equal(options.declared,declared);assert.equal(options.environment,environment);
      assert.equal(options.mappings,originalMappings);assert.equal(options.site,siteOwner);assert.equal(options.authorization,authorization);
      assert.equal(typeof options.providerMoon.installedStandardCreateConstructionProfile,'function');calls.push('adapter');return adapter;},
    retainInstalledHostInitializationFailure:async error=>{throw error;}});
  const profile={siteProfilePath:'/explicit/site',publicationPath:'/explicit/publication',connectorId:'sheet',
    accountConfigurationWire:'original-account',sources:[{target:'name',field:'name',null_behavior:'reject'}]};
  assert.equal(await load(profile,{moon:{clientProgramRowSourceRestoreDeclaration:legacy},providerMoon,
    sourceInitialization:scope,configurationReader:reader,installationServices:services,installation,
    baseEnvironmentWire:'original-base',runtimeBundleCid:providerCid,ledgerRoot:'/explicit/ledger'},true),adapter);
  assert.deepEqual(calls,['/explicit/site','declaration','/explicit/publication','mappings','site','adapter']);
});

test('actual Sheets initial CA reader is captured before await and preserves the same original bytes', async () => {
  const site={...initializedSheetsSite(),caPath:'/explicit/original.pem'},ca=Buffer.from([0xef,0xbb,0xbf,0,0xff,13,10]);
  let complete,reads=0;
  const reader={readJson:()=>new Promise(done=>{complete=()=>done(site);}),readText(){assert.fail('No CA text conversion');},
    async readOriginalBytes(path){assert.equal(this,reader);assert.equal(path,site.caPath);reads++;return ca;}};
  const {captureConfigurationReaders} = await import('./source-profile-json.mjs');
  const readSite=selectedSheetsInitialization({captureConfigurationReaders,
    readFile(){assert.fail('No raw file fallback on the original initializer');},
    SHEETS_SITE_VERSION:site.version,SHEETS_LIMITS,
    exact:(x,keys)=>Object.keys(x).sort().join('\0')===[...keys].sort().join('\0'),
    gridIndex:x=>Number.isInteger(x)&&x>=0,absolute:x=>x.startsWith('/'),
    siteKeys:Object.keys(site).filter(key=>!['version','caPath'].includes(key)),
    fail:code=>{throw Object.assign(new Error(code),{code});},checkSheetsGridConfiguration(){}},'readSite');
  const pending=readSite('/explicit/site',{},reader);
  reader.readOriginalBytes=()=>assert.fail('No replacement byte reader after await');
  if (typeof complete !== 'function') await pending;
  assert.equal(typeof complete,'function');complete();
  const selected=await pending;assert.equal(selected.ca,ca);assert.equal(reads,1);
});

test('Sheets initialized loading refuses missing original reader before a legacy producer', async () => {
  const load=selectedSheetsInitialization({
    fail:code=>{throw Object.assign(new Error(code),{code});},
    readFile(){assert.fail('Missing initialized reader cannot select raw files');}});
  await assert.rejects(load({}, {sourceInitialization:{}}, true),
    {code:'InstalledSheetsConfigurationReaderUnavailable'});
});

test('Sheets registered loaders refuse absent Source ownership before any configuration or legacy producer', async () => {
  let reads=0;
  const load=selectedSheetsInitialization({
    fail:code=>{throw Object.assign(new Error(code),{code});},
    readSite(){reads++;throw new Error('Unexpected unfunded configuration read');}});
  for(const effect of [false,true]) {
    await assert.rejects(load({}, {moon:{},providerMoon:{}},effect),
      {code:'InstalledSheetsInitializationUnavailable'});
  }
  assert.equal(reads,0);
});

test('Sheets registered loaders refuse absent Site services before opening original configuration', async () => {
  let reads=0;
  const load=selectedSheetsInitialization({
    fail:code=>{throw Object.assign(new Error(code),{code});},
    readFile(){reads++;throw new Error('Unexpected configuration read before installed Site services');}});
  for(const effect of [false,true]) {
    await assert.rejects(load({}, {sourceInitialization:{},configurationReader:{}},effect),
      {code:'InvalidInstalledEffectSiteServices'});
  }
  assert.equal(reads,0);
});

test('Sheets original declaration method refuses missing inherited or accessor substitutions without invoking them', () => {
  const site=initializedSheetsSite(),profile={connectorId:'sheet'};
  const restore=selectedSheetsInitialization({registration:'sheets',revision:'sheets/0.1',checked,
    fail:code=>{throw Object.assign(new Error(code),{code});}},'restore');
  let getters=0,legacy=0;
  const accessor=Object.defineProperty({},'prepareAuthoredDeclaration',{get(){getters++;return ()=>{};}});
  for(const foreign of [{},accessor,Object.create({prepareAuthoredDeclaration(){assert.fail('Inherited constructor');}})]) {
    assert.throws(()=>restore({clientProgramRowSourceRestoreDeclaration(){legacy++;}}, {},profile,site,undefined,foreign),
      {code:'InstalledSheetsInitializationUnavailable'});
  }
  assert.equal(getters,0);assert.equal(legacy,0);
});

test('Sheets original Mapping constructor preserves thrown undefined without another Mapping or Site', () => {
  const mappingOf=selectedSheetsInitialization({SHEETS_APPEND_OPERATION,
    fail:code=>{throw Object.assign(new Error(code),{code});},rowSourceMapping(){assert.fail('No legacy fallback');}},'mappingOf');
  const original={prepareMappings(wire,writes){assert.equal(this,original);throw undefined;}};
  let caught=false,failure;
  try {mappingOf({}, {sources:[{target:'name',field:'name',null_behavior:'reject'}]},
    initializedSheetsSite(),{},original);}catch(error){caught=true;failure=error;}
  assert.equal(caught,true);assert.equal(failure,undefined);
});

test('actual managed Sheets Source selects same original request quantity before Site and common reader', async () => {
  const source=readFileSync(new URL('../connectors/sheets/host/installed-sheets.mjs',import.meta.url),'utf8');
  const selected=new Set(['loadManagedSheetsGridSource','sheetsGridReaderLimits','checkedSourceMethod']);
  const bodies=parse(source,{ecmaVersion:'latest',sourceType:'module'}).body
    .filter(n=>n.type==='FunctionDeclaration'&&selected.has(n.id.name)).map(n=>source.slice(n.start,n.end)).join('\n');
  assert.equal(selected.size,3);
  const {captureInstalledSourceServices}=await import('./installed-host-services.mjs');
  const site=initializedSheetsSite(),scope={},installation={},quantity=Object.freeze({}),capacity=Object.freeze({}),
    reader=Object.freeze({capacity}),runAcquisitionLimits=Object.freeze({}),implementation={capacity,runAcquisitionLimits},
    authorization={},physicalSite={},calls=[],adapter={};
  const environment={wire:'original-env'},prepared={declaration:{},declared:{catalog_cid:providerCid},environment};
  const moon={clientProgramInstalledSourceReaderPolicy(){assert.equal(this,moon);calls.push('policy');return[65536,100000,100];}};
  const native={sheetsGridReadConstructionCapacity(...args){assert.equal(this,native);calls.push('quote');
    assert.deepEqual(args,[Buffer.byteLength(JSON.stringify(site.columns)),1,0,0,1,0,1]);return quantity;}};
  const services={sourceReaderImplementationProfile(){assert.fail('Existing Sheets bounds must not be substituted');},
    sourceReaderImplementation(input){assert.equal(this,services);calls.push('implementation');
      assert.equal(input.sourceInitialization,scope);assert.equal(input.installation,installation);
      assert.equal(input.preservingRequestConstruction.capacity,quantity);assert.equal(input.preservingRequestConstruction.maxRequestBytes,300000);
      assert.equal(input.limits.maxResponseBytes,2000000);assert.equal(input.limits.maxPages,1);
      assert.equal(input.limits.maxIdentityBytes,1);assert.equal(input.limits.maxCursorBytes,1);
      assert.equal(input.limits.maxValueTextBytes,2000000);return implementation;},
    openRowSite(){assert.fail('Actual openSite body is an explicit port in this caller counter');},
    createSourceReader(input){assert.equal(this,services);calls.push('reader');assert.equal(input.implementation,implementation);
      assert.equal(input.sourceInitialization,scope);assert.equal(input.site,physicalSite);
      assert.equal(input.operation,SHEETS_READ_OPERATION);assert.equal(typeof input.preparePageReader,'function');
      assert.equal(Object.hasOwn(input,'readPages'),false);return reader;}};
  const open=Function('nodeTypes','captureInstalledSourceServices','SHEETS_LIMITS','SHEETS_READ_OPERATION','registration','revision',
    'targetVersion','bindingFacts','fail','openSite','createInstalledRowSource','prepareSheetsGridPages','retainInstalledHostInitializationFailure',
    bodies+'\nreturn loadManagedSheetsGridSource;')(
    nodeTypes,captureInstalledSourceServices,SHEETS_LIMITS,SHEETS_READ_OPERATION,'sheets','sheets/0.1','target',
    value=>({columns:value.columns}),code=>{throw Object.assign(new Error(code),{code});},
    async(profile,actualSite,options,publication,actualServices)=>{calls.push('site');assert.equal(actualSite,site);
      assert.equal(options.runAcquisitionLimits,runAcquisitionLimits);assert.equal(actualServices,services);
      return{site:physicalSite,authorization,bindingCid:providerCid};},
    async input=>{calls.push('adapter');assert.equal(input.providerReader,reader);assert.equal(input.environment,environment);
      assert.equal(input.declaration,prepared.declaration);assert.equal(input.declared,prepared.declared);
      assert.equal(input.sourceInitialization,scope);assert.equal(input.site,physicalSite);return adapter;},
    ()=>assert.fail('No callback before the common reader prepares its original acquisition'),async error=>{throw error;});
  const result=await open({connectorId:'sheet'},{moon,providerMoon:native,sourceInitialization:scope,installation,
    installationServices:services},site,{catalogCid:providerCid},prepared);
  assert.equal(result,adapter);assert.deepEqual(calls,['policy','quote','implementation','site','reader','adapter']);
});

for (const rangeCommand of [true, 'clear']) {
  test(`Sheets ${rangeCommand === true ? 'range' : 'clear'} caller consumes the original Command Environment once`, async () => {
    // Actual registered caller retains the original Source Environment.
    // Declaration, Site and Effect constructors are explicit ports, not admissions.
    const source=readFileSync(new URL('../connectors/sheets/host/installed-sheets.mjs',import.meta.url),'utf8');
    const node=parse(source,{ecmaVersion:'latest',sourceType:'module'}).body
      .find(value=>value.type==='FunctionDeclaration'&&value.id.name==='load');
    const {rowSourceCheckEnvironment}=await import('./installed-row-source.mjs');
    const command={contract_cid:providerCid,literal:'=e\u0301\r\n'},commandWire=JSON.stringify(command),
      declaration={},installed={body:commandWire},target={},siteOwner={referenceCurrent:()=>true},authorization={},adapter={},calls=[];
    const declared={catalog:JSON.stringify({commands:[command]}),command_bodies:[commandWire],
      contracts:[],view_bodies:[],evidence_schemas:[],evidence_capabilities:[],manifest_entry:'{}'};
    const base={version:'actql-check-environment/0.1',connector_catalogs:[],schema_snapshots:[],
      connector_capabilities:[],mapping_contracts:[],command_contracts:[]};
    const sourceInitialization={},configurationReader={},installationServices={};
    let environment;

    const profile={rangeCommand,connectorId:'sheet',siteProfilePath:'/unopened/site',publicationPath:'/unopened/publication'};
    const ports={captureConfigurationReaders(value){assert.equal(value,configurationReader);return value;},
      fail:code=>{throw Object.assign(new Error(code),{code});},readSite:async()=>({}),
      restore(...args){assert.equal(args[5],sourceInitialization);calls.push('environment');
        environment=rowSourceCheckEnvironment(JSON.stringify(base),declared,[]);
        return {declaration,declared,rangeCommand:{installed,command},environment};},
      readPublication:async()=>({}),
      rowSourceCheckEnvironment(){assert.fail('No second Environment assembly after original Source construction');},
      openSite:async()=>({site:siteOwner,authorization,bindingCid:providerCid}),
      checkedSourceMethod:(owner,name)=>owner[name],
      prepareInitializedSheetsEffectDriver(scope,moon,site,catalog,binding,selected,clear,current){
        assert.equal(scope,sourceInitialization);assert.equal(selected,installed);assert.equal(current(),true);
        calls.push(clear?'clear':'range');return {target,driver:{}};},
      createInstalledRowEffect:async input=>{assert.equal(input.environment,environment);assert.deepEqual(JSON.parse(input.environmentWire).command_contracts,[command]);
        assert.equal(input.site,siteOwner);assert.deepEqual(input.commands,[installed]);assert.equal(input.authorization,authorization);return adapter;},
      retainInstalledHostInitializationFailure:async error=>{throw error;},
      canonicalJson,contentCid,registration:'sheets',revision:'sheets/0.1'};
    const load=Function(...Object.keys(ports),`return (${source.slice(node.start,node.end)});`)(...Object.values(ports));
    assert.equal(await load(profile,{moon:{},providerMoon:{},sourceInitialization,configurationReader,installationServices,baseEnvironmentWire:JSON.stringify(base)},true),adapter);
    assert.deepEqual(calls,['environment',rangeCommand==='clear'?'clear':'range']);
  });
}

test('Sheets initialized driver invalidates current BEFORE failure cleanup can reenter the original Site', async () => {
  const source=readFileSync(new URL('../connectors/sheets/host/installed-sheets.mjs',import.meta.url),'utf8');
  const node=parse(source,{ecmaVersion:'latest',sourceType:'module'}).body
    .find(value=>value.type==='FunctionDeclaration'&&value.id.name==='load');
  const original={},sourceInitialization={},configurationReader={},installationServices={},site={referenceCurrent:()=>true};
  let driverCurrent,cleanupCalls=0;
  const ports={fail:code=>{throw Object.assign(new Error(code),{code});},
    captureConfigurationReaders:value=>value,readSite:async()=>({}),
    restore:()=>({declaration:{},declared:{},environment:{wire:'same'},commandDefinition:{installed:{}}}),
    readPublication:async()=>({}),openSite:async()=>({site}),checkedSourceMethod:(owner,name)=>owner[name],
    prepareInitializedSheetsEffectDriver(scope,provider,configuration,catalog,binding,command,clear,current){
      driverCurrent=current;assert.equal(current(),true);return {driver:{}};},
    async createInstalledRowEffect(){throw original;},
    async retainInstalledHostInitializationFailure(cause,owners){
      cleanupCalls++;assert.equal(cause,original);assert.equal(owners.installedEffect,site);
      assert.equal(site.referenceCurrent(),true,'Physical owner is still live; failure is not its ACK');
      assert.equal(driverCurrent(),false,'Invalidate the logical driver before original cleanup observation');
      return cause;},registration:'sheets',revision:'sheets/0.1'};
  const load=Function(...Object.keys(ports),`return (${source.slice(node.start,node.end)});`)(...Object.values(ports));
  let caught=false,failure;
  try{await load({rangeCommand:true},{moon:{},providerMoon:{},sourceInitialization,configurationReader,installationServices},true);}
  catch(cause){caught=true;failure=cause;}
  assert.equal(caught,true);assert.equal(failure,original);assert.equal(cleanupCalls,1);assert.equal(driverCurrent(),false);
});

for (const selectedClear of [false, true]) {
  test(`initialized Sheets ${selectedClear ? 'clear' : 'range'} declaration stays under the SAME Source constructor before original Native projection`, async () => {
    const source = readFileSync(new URL('../connectors/sheets/host/installed-sheets.mjs', import.meta.url), 'utf8');
    const tree = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
    const names = ['restore', 'checkedSourceMethod', 'prepareInitializedSheetsCommandDeclaration'];
    const bodies = tree.body.filter(node => node.type === 'FunctionDeclaration' && names.includes(node.id.name))
      .map(node => source.slice(node.start, node.end)).join('\n');
    const {sheetsOwnedResult} = await import('../connectors/sheets/site/sheets-owned-request.mjs');
    const {sheetsRangeCommand, withSheetsRangeCommand} = await import('../connectors/sheets/host/sheets-range-command.mjs');
    const {sheetsClearCommand} = await import('../connectors/sheets/host/sheets-clear-command.mjs');
    const columns = Object.freeze([Object.freeze({name: 'label', type: 'string', nullable: false})]);
    const gridRange = Object.freeze({sheetId: 0, startRow: 0, endRow: 2, startColumn: 0, endColumn: 1});
    const site = Object.freeze({columns, gridRange}), declaration = {}, environment = {}, quantity = {};
    const commandBody = {contract_cid: providerCid}, installed = {resource: 'range_target', body: JSON.stringify(commandBody)};
    const base = {catalog_cid: boundaryCid}, declared = {catalog_cid: providerCid, command_bodies: [installed.body]};
    const command = {command: commandBody, contracts: [], installed};
    const profile = {connectorId: 'sheet', rangeCommand: selectedClear ? 'clear' : true};
    let baseFunded = false, nativeFunded = false, prepared, captured, calls = [];
    const moon = {
      clientProgramRowSourceRestoreRelationDeclaration(...args) {
        assert.equal(baseFunded, true, 'original declaration must be under Source before Native construction');
        assert.equal(args[0], 'sheet');assert.equal(JSON.parse(args[3]).views.length, 2);return {$tag: 1, _0: declaration};
      },
      clientProgramRowSourceDeclarationJson(value) {assert.equal(value, declaration);return JSON.stringify(base);},
    };
    const providerMoon = {
      sheetsRangeDeclarationConstructionCapacity(schemaBytes, count, rangeBytes, connectorBytes, declaredBytes) {
        assert.equal(this, providerMoon);assert.equal(count, 1);assert.equal(connectorBytes, 5);
        assert.equal(schemaBytes, Buffer.byteLength(JSON.stringify(columns)));
        assert.equal(rangeBytes, Buffer.byteLength(JSON.stringify(gridRange)));
        assert.equal(declaredBytes, Buffer.byteLength(JSON.stringify(base)));calls.push('quantity');
        // Original methods must already be captured across the following
        // reserve/current boundary; a changed namespace is not a new choice.
        providerMoon[selectedClear ? 'sheetsClearCommandJson' : 'sheetsRangeCommandJson'] = () => assert.fail('replaced Native method');
        return quantity;
      },
      [selectedClear ? 'sheetsClearCommandJson' : 'sheetsRangeCommandJson'](...args) {
        assert.equal(this, providerMoon);assert.equal(nativeFunded, true);
        assert.equal(args[0], 'sheet');assert.deepEqual(JSON.parse(args[1]), columns);
        assert.deepEqual(JSON.parse(args[2]), gridRange);calls.push('command');return {$tag: 1, _0: JSON.stringify(command)};
      },
      sheetsRangeCatalogJson(original, selected) {
        assert.equal(this, providerMoon);assert.equal(nativeFunded, true);
        assert.deepEqual(JSON.parse(original), base);assert.deepEqual(JSON.parse(selected), command);
        calls.push('catalog');return {$tag: 1, _0: JSON.stringify(declared)};
      },
      sheetsRangeFailureJson() {assert.fail('No failure projection in this original-method positive');},
    };
    const context = Object.freeze({prepareDeclaredCommands(viewsWire, projection, expected) {
      assert.equal(this, context);assert.equal(expected, undefined);assert.equal(Object.isFrozen(projection), true);
      baseFunded = true;moon.clientProgramRowSourceRestoreRelationDeclaration('sheet', 'sheets', 'sheets/0.1', viewsWire);
      assert.equal(projection.capacity(JSON.stringify(base)), quantity);nativeFunded = true;
      captured = projection.project(JSON.stringify(base));
      assert.deepEqual(captured.declared, declared);assert.equal(captured.commands[0], captured.definition.installed);
      prepared = Object.freeze({declaration, declared: captured.declared, environment,
        commands: captured.commands, commandDefinition: captured.definition});return prepared;
    }});
    const restore = Function('checked', 'canonicalJson', 'contentCid', 'registration', 'revision', 'fail',
      'nodeTypes', 'sheetsRangeCommand', 'sheetsClearCommand', 'withSheetsRangeCommand', 'sheetsOwnedResult', 'SHEETS_LIMITS', bodies + '\nreturn restore;')(
      checked, canonicalJson, contentCid, 'sheets', 'sheets/0.1', code => {throw Object.assign(new Error(code), {code});},
      nodeTypes, sheetsRangeCommand, sheetsClearCommand, withSheetsRangeCommand, sheetsOwnedResult, SHEETS_LIMITS);
    assert.equal(restore(moon, providerMoon, profile, site, undefined, context), prepared);
    assert.deepEqual(calls, ['quantity', 'command', 'catalog']);assert.equal(captured.commands.length, 1);
  });
}

// Execute the actual loader/constructor body. Core/Site/provider constructors
// remain explicit ports, so this establishes original forwarding and lifetime,
// not native quantity sufficiency, transport or ordinary acceptance.
for (const rangeCommand of [true, 'clear']) {
  test(`initialized Sheets ${rangeCommand === true ? 'range' : 'clear'} load retains original Command Environment through SAME installed Site service`, async () => {
    const source = readFileSync(new URL('../connectors/sheets/host/installed-sheets.mjs', import.meta.url), 'utf8');
    const ast = parse(source, {ecmaVersion:'latest', sourceType:'module'});
    const names=new Set(['load','openSite','prepareInitializedSheetsEffectDriver','checkedSourceMethod']);
    const bodies = ast.body.filter(node => node.type === 'FunctionDeclaration' && names.has(node.id.name) ||
      node.type === 'VariableDeclaration' && node.declarations.some(value => value.id.name === 'bindingFacts'))
      .map(node => source.slice(node.start,node.end)).join('\n');
    const declaration = {}, command = {}, installed = {}, target = {}, adapter = {}, quantity={};
    const commands = Object.freeze([installed]), environment = Object.freeze({wire:'same-original-command-environment'});
    const declared = {}, configurationReader = {}, installation = {}, events = [];
    const site = initializedSheetsSite();
    let closing=false,driverCurrent;
    const authorization = {context:{contextCid:providerCid}}, ownedSite = {
      referenceCurrent(){assert.equal(this,ownedSite);return !closing;},close(){assert.equal(this,ownedSite);closing=true;events.push('close');return true;}};
    const managedPlanDefinition={},managedPlanConstruction={},managedPlanProvider={};
    const driver=Object.freeze({managedPlanDefinition,managedPlanConstruction,managedPlanProvider});
    const providerMoon={sheetsRangeInstallationConstructionCapacity(...args){assert.equal(this,providerMoon);
      assert.deepEqual(args,[441,1,Buffer.byteLength(site.apiOrigin),Buffer.byteLength(site.spreadsheetId)]);
      events.push('quantity');return quantity;}};
    const methodNames=['sheetsRangeReferenceJson','sheetsRangeFailureJson',...(rangeCommand==='clear'
      ?['sheetsClearBinding','sheetsClearPrepare','sheetsClearTargetMatches','sheetsClearRequestJson','sheetsClearRequestBody','sheetsClearRequestCid',
        'sheetsClearOutcomeJson','sheetsClearRecoveryEntryJson','sheetsClearRecover','sheetsClearConstructionProfile','sheetsClearCaptureConstructionProfile']
      :['sheetsRangeBinding','sheetsRangePrepare','sheetsRangeTargetMatches','sheetsRangeRequestJson','sheetsRangeRequestBody','sheetsRangeRequestCid',
        'sheetsAppendOutcomeJson','sheetsRangeRecoveryEntryJson','sheetsRangeRecover','sheetsRangeConstructionProfile','sheetsRangeCaptureConstructionProfile'])];
    for(const name of methodNames)providerMoon[name]=function(){assert.equal(this,providerMoon);return name;};
    const originalProfile=rangeCommand==='clear'?'sheetsClearConstructionProfile':'sheetsRangeConstructionProfile';
    const sourceInitialization=Object.freeze({prepareEffectDriverConstruction(projection){
      assert.equal(this,sourceInitialization);events.push('effect-reserve');assert.equal(projection.capacity(),quantity);
      // Original callback capture must survive replacement at reserve/current.
      providerMoon[originalProfile]=()=>assert.fail('No late mutable provider lookup');
      return projection.project();}});
    const services = Object.freeze({async openRowSite(input) {
      assert.equal(this,services);assert.equal(input.sourceInitialization,sourceInitialization);
      assert.equal(input.installation,installation);assert.equal(input.accountConfiguration,'original-account');
      events.push('same-site');return {authorization,site:ownedSite};
    }});
    const forbidden = () => assert.fail('No legacy Environment, Site or Mapping producer for initialized Command');
    const makeDriver=input=>{assert.equal(input.target,target);assert.equal(input.moon[originalProfile](),originalProfile);
      driverCurrent=input.isCurrent;assert.equal(driverCurrent(),true);events.push(rangeCommand==='clear'?'clear-driver':'range-driver');return driver;};
    const ports = {registration:'sheets',revision:'sheets/0.1',targetVersion:'actql-sheets-source-target/0.1',nodeTypes,
      fail:code=>{throw Object.assign(new Error(code),{code});},canonicalJson,contentCid,text:()=>true,
      captureConfigurationReaders(value){assert.equal(value,configurationReader);return value;},
      readSite:async()=>site,restore(...args){assert.equal(args[5],sourceInitialization);return {declaration,declared,
        commandDefinition:{command,installed},commands,environment};},
      readPublication:async()=>({catalogCid:providerCid}),rowSourceCheckEnvironment:forbidden,mappingOf:forbidden,
      installRowSourceAuthorization:forbidden,openRowSourceCredentialSite:forbidden,
      sheetsRangeConfigurationBytes(value){assert.equal(value,site);return 441;},
      sheetsRangeReference({moon}){assert.equal(moon.sheetsRangeReferenceJson(),'sheetsRangeReferenceJson');events.push('reference');return target;},
      createSheetsRangeDriver:makeDriver,createSheetsClearDriver:makeDriver,
      async createInstalledRowEffect(input) {
        assert.equal(input.sourceInitialization,sourceInitialization);assert.equal(input.commands,commands);
        assert.equal(input.declaration,declaration);assert.equal(input.declared,declared);assert.equal(input.environment,environment);
        assert.equal(input.environmentWire,environment.wire);assert.equal(input.authorization,authorization);
        assert.equal(input.site,ownedSite);assert.equal(input.driver,driver);assert.equal(input.providerMoon,managedPlanProvider);
        assert.equal(input.managedPlanDefinition,managedPlanDefinition);assert.equal(input.managedPlanConstruction,managedPlanConstruction);
        assert.equal(input.site.close(),true);assert.equal(driverCurrent(),false);events.push('same-adapter');return adapter;
      },retainInstalledHostInitializationFailure:async cause=>{throw cause;}};
    const load = Function(...Object.keys(ports),bodies+'\nreturn load;')(...Object.values(ports));
    assert.equal(await load({rangeCommand,connectorId:'sheet',siteProfilePath:'/unopened/site',publicationPath:'/unopened/publication',
      accountConfigurationWire:'original-account'}, {moon:{},providerMoon,sourceInitialization,configurationReader,installationServices:services,
      installation,baseEnvironmentWire:'original-base',principalId:'fixture',root:'/unopened/root',runtimeBundleCid:providerCid},true),adapter);
    assert.deepEqual(events,['same-site','effect-reserve','quantity','reference',rangeCommand==='clear'?'clear-driver':'range-driver','close','same-adapter']);
  });
}

for(const rangeCommand of [true,'clear']){
  test(`managed Sheets ${rangeCommand===true?'range':'clear'} Source retains original target before Reader and routes metadata without legacy I/O`,async()=>{
    const source=readFileSync(new URL('../connectors/sheets/host/installed-sheets.mjs',import.meta.url),'utf8');
    const names=new Set(['loadManagedSheetsGridSource','sheetsGridReaderLimits','checkedSourceMethod','prepareInitializedSheetsReadTarget']);
    const bodies=parse(source,{ecmaVersion:'latest',sourceType:'module'}).body.filter(node=>node.type==='FunctionDeclaration'&&names.has(node.id.name))
      .map(node=>source.slice(node.start,node.end)).join('\n');
    const {captureInstalledSourceServices}=await import('./installed-host-services.mjs');
    const {prepareSheetsGridPages,prepareSheetsRangeTargetPages}=await import('../connectors/sheets/site/sheets-grid-pages.mjs');
    const quantity={},sourceQuantity={},capacity={},installation={},calls=[],site=initializedSheetsSite(),
      target=Object.freeze({original:'provider-reference'}),commands=Object.freeze([{}]),environment={wire:'same-env'},declaration={},declared={catalog_cid:providerCid};
    let selectedPage,issuer,closed=0,siteClosing=false;
    const physicalSite={referenceCurrent(){return !siteClosing;},close(){siteClosing=true;return true;}};
    const adapter={close(){closed++;return physicalSite.close();}};
    const sourceInitialization=Object.freeze({prepareReadTarget(projection){calls.push('source-target-reserve');
      assert.equal(projection.capacity(),sourceQuantity);return projection.project();}});
    const moon={clientProgramInstalledSourceReaderPolicy:()=>[65536,100000,100],
      clientProgramResourceReferenceIssuer(admit,current){issuer={admit,current};return issuer;}};
    const native={sheetsRangeReadConstructionCapacity(...args){assert.equal(this,native);calls.push('reader-quantity');
      assert.deepEqual(args,[Buffer.byteLength(JSON.stringify(site.columns)),1,0,0,1,0,1,200000,32]);return quantity;},
      sheetsRangeReferenceConstructionCapacity(...args){assert.equal(this,native);calls.push('reference-quantity');
        assert.deepEqual(args,[Buffer.byteLength(site.apiOrigin),Buffer.byteLength(site.spreadsheetId)]);return sourceQuantity;},
      sheetsRangeReferenceJson(){assert.equal(this,native);calls.push('reference');return target;},
      sheetsRangeFailureJson(){assert.fail('No failure projection');},
      sheetsTargetJson(){assert.equal(this,native);calls.push('metadata');return '{"checked":true}';}};
    const runAcquisitionLimits={},implementation={capacity,runAcquisitionLimits},reader={capacity};
    const authorization={};
    const services={sourceReaderImplementationProfile(){assert.fail('No substituted policy');},openRowSite(){assert.fail('Original Site is a port');},
      sourceReaderImplementation(input){calls.push('implementation');assert.equal(input.sourceInitialization,sourceInitialization);
        assert.equal(input.preservingRequestConstruction.capacity,quantity);return implementation;},
      createSourceReader(input){calls.push('reader');assert.equal(input.site,physicalSite);assert.equal(input.operation,SHEETS_READ_OPERATION);
        assert.equal(Object.hasOwn(input,'readPages'),false);selectedPage=input.preparePageReader;return reader;}};
    const load=Function('nodeTypes','captureInstalledSourceServices','SHEETS_LIMITS','SHEETS_READ_OPERATION','registration','revision','targetVersion',
      'bindingFacts','fail','canonicalJson','openSite','createInstalledRowSource','prepareSheetsGridPages','prepareSheetsRangeTargetPages','sheetsRangeReference',
      'retainInstalledHostInitializationFailure',bodies+'\nreturn loadManagedSheetsGridSource;')(
      nodeTypes,captureInstalledSourceServices,SHEETS_LIMITS,SHEETS_READ_OPERATION,'sheets','sheets/0.1','target',
      value=>({columns:value.columns}),code=>{throw Object.assign(new Error(code),{code});},canonicalJson,
      async()=>{calls.push('site');return{site:physicalSite,authorization,bindingCid:providerCid};},
      async input=>{calls.push('adapter');assert.equal(input.providerReader,reader);assert.equal(input.commands,commands);
        assert.equal(input.environment,environment);assert.equal(input.referenceIssuer,issuer);return adapter;},
      prepareSheetsGridPages,prepareSheetsRangeTargetPages,({moon})=>moon.sheetsRangeReferenceJson(),async cause=>{throw cause;});
    const result=await load({rangeCommand,connectorId:'sheets'},{moon,providerMoon:native,sourceInitialization,installation,installationServices:services},
      site,{catalogCid:providerCid},{declaration,declared,environment,commands});
    assert.equal(result,adapter,'Return SAME nominal Source adapter');
    assert.deepEqual(calls,['reader-quantity','implementation','site','source-target-reserve','reference-quantity','reference','reader','adapter']);
    const page=selectedPage({resource:'range_target',columns:['target']},Reflect.apply);
    assert.equal(page.fetchPage({pageIndex:0,rowCount:0}).method,'GET');
    assert.equal(page.decodePage({accepted:true,statusCode:200,body:new Uint8Array()}, {pageIndex:0,rowCount:0}).rows[0].target,target);
    assert.equal(issuer.admit('sheet_range',canonicalJson(target)),true);assert.equal(issuer.current(),true);
    assert.equal(result.close(),true);assert.equal(closed,1);assert.equal(issuer.current(),false);
    assert.equal(issuer.admit('sheet_range',canonicalJson(target)),false);
  });
}


test('Command construction requires SAME driver definition provider and immutable metadata before Plan construction',()=>{
  const names=new Set(['captureManagedPlanDefinition','captureManagedDriverConstruction']);
  const bodies=rowTree.body.filter(node=>node.type==='FunctionDeclaration'&&names.has(node.id.name)).map(node=>rowSource.slice(node.start,node.end)).join('\n');
  const capture=Function('nodeTypes','text','fail',bodies+'\nreturn (definition,driver,provider,construction)=>captureManagedDriverConstruction(construction,captureManagedPlanDefinition(definition,driver),driver,provider);')(
    nodeTypes,value=>typeof value==='string'&&value.length>0,code=>{throw Object.assign(new Error(code),{code});});
  const definition=Object.freeze({kind:'command',memberOperations:Object.freeze([]),rowOperations:Object.freeze([Object.freeze({role:'write',operation:'sheets:update'})])});
  const construction=Object.freeze({write:Object.freeze({operation:'sheets:update',maxRequestBytes:300000,maxResponseBytes:1000000}),check:undefined,metadataTextUnits:117});
  const provider=Object.freeze({}),driver=Object.freeze({kinds:Object.freeze(['command']),managedPlanDefinition:definition,managedPlanConstruction:construction,managedPlanProvider:provider});
  assert.equal(capture(definition,driver,provider,construction),construction);
  assert.throws(()=>capture({...definition},driver,provider,construction),{code:'InvalidInstalledEffectPlanDefinition'});
  assert.throws(()=>capture(definition,driver,provider,Object.freeze({...construction})),{code:'InvalidInstalledEffectDriverConstruction'});
  assert.throws(()=>capture(definition,driver,Object.freeze({}),construction),{code:'InvalidInstalledEffectDriverConstruction'});
  const bad=Object.freeze({...construction,write:Object.freeze({...construction.write,operation:'sheets:clear'})});
  assert.throws(()=>capture(definition,Object.freeze({...driver,managedPlanConstruction:bad}),provider,bad),{code:'InvalidInstalledEffectDriverConstruction'});
});


test('actual member capture caller defers SAME original recovery until Preview and retains failing siblings', async () => {
  const {prepareInstalledEffectRequestChild} = await import('./installed-effect-plan.mjs');
  const {retainInstalledRowCaptureChild} = await import('./installed-row-capture-cleanup.mjs');
  const matches = [];
  const visit = node => {
    if (!node || typeof node !== 'object') return;
    if (node.type === 'FunctionDeclaration' && node.id.name === 'captureStage') matches.push(node);
    for (const value of Object.values(node)) {
      if (Array.isArray(value)) value.forEach(visit);
      else if (value && typeof value === 'object') visit(value);
    }
  };
  visit(rowTree); assert.equal(matches.length, 1);
  const statements = matches[0].body.body;
  const slice = node => rowSource.slice(node.start, node.end);
  const initialize = statements.filter(node => node.type === 'ForOfStatement' &&
    slice(node).includes('retainInstalledRowCaptureChild('));
  const recovery = statements.filter(node => node.type === 'ForOfStatement' &&
    slice(node).includes('await retained.prepare()'));
  assert.equal(initialize.length, 1); assert.equal(recovery.length, 1);
  const vector = statements.filter(node => node.type === 'VariableDeclaration' &&
    node.declarations.some(value=>value.id.name==='memberCaptures'));
  assert.equal(vector.length,1);
  const source = 'const requestChildren=[],proposals=[],currents=[]; let entries;' + slice(vector[0]) +
    slice(initialize[0]) + '\nreturn {requestChildren,proposals,currents,finish:async originalEntries=>{' +
    'entries=originalEntries; const connectorRecovery=[];' + slice(recovery[0]) + ';return connectorRecovery;}};';
  const open = Function('members','ownerOf','managedEffect','moon','prepared','identity',
    'retainInstalledRowCaptureChild','prepareInstalledEffectRequestChild','retireRequestAliases',
    'assertCurrent','signal','fail','recipeOf',source);
  for (const failing of [false,true]) {
    const events=[],members=[{memberIndex:0},{memberIndex:1}],parent={},prepared={},identity={},plan={};
    const tokens=members.map(()=>({})); let retired=false;
    const moon={clientProgramInstalledEffectManagedOperationPlan:()=>({$tag:1,_0:plan}),
      clientProgramInstalledEffectOperationConstructionRetain(p,original,intent,selected,index,perRow) {
        assert.strictEqual(p,parent);assert.strictEqual(original,prepared);assert.strictEqual(intent,identity);
        assert.strictEqual(selected,plan);assert.equal(perRow,false);events.push('borrow'+index);
        return {$tag:1,_0:tokens[index]};
      } ,clientProgramInstalledEffectOperationConstructionBegin(token) {
        assert(tokens.includes(token));return {$tag:1,_0:undefined};
      },clientProgramInstalledEffectOperationConstructionComplete(token) {
        events.push('complete'+tokens.indexOf(token));return {$tag:1,_0:undefined};
      },clientProgramInstalledEffectOperationRetire(token) {assert(retired);return {$tag:1,_0:true};}};
    const managedEffect={controlConstruction:(receiver,method,args)=>Reflect.apply(method,receiver,args),runtime:moon,value:parent,prepared,request:identity,operationPlan:plan,
      readPlan:moon.clientProgramInstalledEffectManagedOperationPlan};
    const descriptions=[{},{}],entries=[[{}],[{}]];
    const owners=members.map((member,index)=>({managedPlanRecipe:{captureConstruction:{operationIndex:0},
      memberOperations:[{operation:'capture'}]},owned:{recoveryEntry(context) {
        assert.strictEqual(this,owners[index].owned);assert.strictEqual(context.member,member);
        assert.strictEqual(context.current,descriptions[index]);assert.strictEqual(context.entries,entries[index]);
        events.push('recovery'+index);if(failing&&index===1)throw undefined;
        return {kind:'original',wire:'wire'+index,observationCid:'cid'+index};
      }}}));
    const capture=open(members,member=>owners[member.memberIndex],managedEffect,moon,prepared,identity,
      retainInstalledRowCaptureChild,prepareInstalledEffectRequestChild,()=>retired,undefined,undefined,
      code=>{throw Object.assign(new Error(code),{code});},member=>owners[member.memberIndex].managedPlanRecipe);
    assert.deepEqual(events,['borrow0','borrow1']);assert.equal(capture.requestChildren.length,2);
    assert.deepEqual(capture.proposals,[[],[]]);capture.currents.push(...descriptions);events.push('Preview');
    if(failing){let caught=false;try{await capture.finish(entries);}catch(error){caught=true;assert.strictEqual(error,undefined);}
      assert(caught);assert.deepEqual(events,['borrow0','borrow1','Preview','recovery0','complete0','recovery1']);}
    else assert.deepEqual(await capture.finish(entries),[
      {memberIndex:0,kind:'original',wire:'wire0',observationCid:'cid0'},
      {memberIndex:1,kind:'original',wire:'wire1',observationCid:'cid1'}]);
    assert(capture.requestChildren.every(value=>value.prepared.status().pending));
    retired=true;for(const child of capture.requestChildren)await child.prepared.release();
    assert(capture.requestChildren.every(value=>value.prepared.status().pending===false));
  }
});
