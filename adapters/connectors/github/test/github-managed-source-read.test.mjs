import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {types} from 'node:util';
import {parse} from 'acorn';
import {checked} from '../../../host-common/runtime-result.mjs';
import {canonicalJson} from '../../../host-node/local-account-config.mjs';
import {invokeScopedCredentialOperation, invocationBindingsMatch} from '../../../host-common/owned-invocation-context.mjs';
import {createInstalledCredentialSourceReader} from '../../../host-node/installed-credential-source-reader.mjs';

// Actual entire GitHub protocol and actual shared Reader; native codec,
// Site/authorization, original-response and capacity ports are explicit.
// This is a caller/lifetime component, not real Core/IO/funding or ACK proof.
function protocolFixture({foreign = false, pagePending, projectionFailure, resource = 'issues',
  beforeFinish, finishFailure, closeFailure, closeFailures = 0} = {}) {
  const events = [], grant = {}, scope = Object.freeze({operation:'github:graphql:read',
    runInvocationCid:'original-run',dispatchRequestCid:'original-dispatch'});
  const original = Object.freeze({grant,scope,useId:'nonce-read-0'});
  const facts = new WeakMap(), charge = {}, capacities = [];
  const credential = Object.freeze({control:Object.freeze({
    identity(actual) {assert.equal(actual,grant);return 'original-grant';},
    useProjection(value) {return value;},
  }),journal:{}});
  let commentReplies = 0, sends = 0, closeAttempts = 0;
  const methods = {
    githubIssuesRequestJson() {events.push('request');return '{"body":"original native request"}';},
    githubIssuePageReadBegin() {events.push('decode');if(projectionFailure)throw projectionFailure;return {$tag:1,_0:{}};},
    githubIssuePageReadNextRequestJson() {return {$tag:1,_0:'{"body":null}'};},
    githubIssuePageReadAccept(){assert.fail('No nested page');},
    githubIssuePageReadFinishJson() {beforeFinish?.();if(finishFailure!==undefined)throw finishFailure;return {$tag:1,_0:'{"rows":[{"id":"original"}],"hasNextPage":false,"endCursor":null}'};},
    githubIssuePageReadClose() {events.push('codec-close');if(closeAttempts++<closeFailures)throw closeFailure;},
    githubGraphqlReadIssueJson() {assert.fail('No codec refusal');},
    githubRequestHeadersJson(){return '[]';},githubResponseHeadersJson(){return '[]';},
    githubRateLimitBasisJson(){return '{"remaining":3}';},githubClassifyFailureJson(){assert.fail('No HTTP refusal');},
  };
  const moon=Object.freeze({...methods,
    githubPullRequestsRequestJson:methods.githubIssuesRequestJson,
    githubPullRequestPageReadBegin:methods.githubIssuePageReadBegin,
    githubPullRequestPageReadNextRequestJson:methods.githubIssuePageReadNextRequestJson,
    githubPullRequestPageReadAccept:methods.githubIssuePageReadAccept,
    githubPullRequestPageReadFinishJson:methods.githubIssuePageReadFinishJson,
    githubPullRequestPageReadClose:methods.githubIssuePageReadClose,
    githubIssueCommentsReadBegin(){return {$tag:1,_0:{}};},
    githubIssueCommentsReadNextRequestJson(){return {$tag:1,_0:commentReplies===2 ? '{"body":null}' : '{"body":"original native request"}'};},
    githubIssueCommentsReadAccept(){commentReplies++;return {$tag:1,_0:undefined};},
    githubIssueCommentsReadPageJson(){return {$tag:1,_0:commentReplies===1 ? '{"page":null}' : '{"page":{"rows":[{"id":"original"}]}}'};},
    githubIssueCommentsReadClose:methods.githubIssuePageReadClose,
  });
  const source = readFileSync(new URL('../site/github-issue-graphql-read.mjs',import.meta.url),'utf8');
  const tree = parse(source,{ecmaVersion:'latest',sourceType:'module'});
  const body = tree.body.filter(node => node.type !== 'ImportDeclaration').map(node => {
    const original = node.type === 'ExportNamedDeclaration' ? node.declaration : node;
    return source.slice(original.start,original.end);
  }).join('\n');
  const prepare = new Function('checked','withHttpsCredentialRunResponseOriginal',
    'invokeScopedCredentialOperation','invocationBindingsMatch','types',body+'\nreturn prepareGitHubSourceReadSequence;')(
      checked,(response,control,journal,project) => {
        assert.equal(control,credential.control);assert.equal(journal,credential.journal);
        const value=facts.get(response);assert(value);return project(value);
      },invokeScopedCredentialOperation,invocationBindingsMatch,types);
  let provider;
  const site = Object.freeze({credential});
  const acquisition = Object.freeze({credential,close(){events.push('binding-close');return 'closed';}});
  const originalSite = Object.freeze({site,referenceCurrent:()=>true,
    authorizationPurpose(actual){assert.equal(actual,original);return {kind:'read'};},
    bindRunAcquisition(actual,callbacks){assert.equal(actual,original);callbacks.assertCurrent();return acquisition;},
    readChildCredential(actual,authorization){assert.equal(actual,acquisition);assert.equal(authorization,original);return credential;},
    async callResource(input) {
      assert.equal(this,site);await input.currentBeforeSend();
      assert.equal(input.maxRequestBytes,16384);assert.equal(input.operations.get(scope.operation).body,'original native request');
      const response=Object.freeze({accepted:true,statusCode:200,headers:[],body:Buffer.from('original native bytes'),useCid:'original-use-'+sends});
      facts.set(response,Object.freeze({response,method:'POST',path:'/graphql',requestBodyText:'original native request',
        requestBodyBytes:Buffer.byteLength('original native request'),scope:input.scope,
        use:['original-use-'+sends,'original-grant',input.useId]}));
      sends++;input.responseCustody.retain(response);events.push('receive');return response;
    }});
  const factory=createInstalledCredentialSourceReader({capacity:{},originalSite,assertCurrent(){},
    maxResponses:10,maxResponseBytes:4000000,maxTotalResponseBytes:40000000,maxRequestBytes:16384,
    prepareReadSequence(input,retireProjection){
      assert.equal(input.originalAuthorization,original);
      provider=prepare({moon,site,repository:{nodeId:'R_original',databaseId:13,nameWithOwner:'o/r'},
        preparedRead:input.preparedRead,originalAuthorization:original,
        limits:{maxPages:10,maxRows:100,maxBytes:4000000,maxNodes:400000,maxDepth:32,perPage:100,maxRequestBytes:16384,maxSubjects:100},
        retireProjection,responseCapacity(bytes){events.push('grow-before-decode');return {bytes};}});
      return provider;
    }});
  const reader=factory.prepare(Object.freeze({resource,columns:['id'],originalAuthorization:original,
    preparedRead:Object.freeze({resource,nonce:'nonce',runInvocationCid:scope.runInvocationCid,dispatchRequestCid:scope.dispatchRequestCid}),
    verifyRead(){},authorizationFor(){return foreign ? {...original,grant:{}} : original;},
    authorizeReadChild(operation,index,occurrence,supplied){
      assert.equal(operation,scope.operation);assert.equal(index,sends);assert.equal(occurrence.grant,grant);
      assert.equal(supplied.authorization.useId,'nonce-read-'+index);
      assert.equal(occurrence.operations.get(operation).body,'original native request');
      assert.equal(supplied.originalAuthorization,original);assert.equal(supplied.authorization.grant,grant);
      assert.equal(supplied.authorization.scope,scope);events.push('original-occurrence');return supplied;
    },chargePage(){events.push('charge');return charge;},consumeObservation(original){assert.equal(resource,'issue_comments');assert.equal(original,charge);events.push('observation');},
    async consumePage(rows,metadata){assert.deepEqual(rows,[{id:'original'}]);assert.equal(metadata.charge,charge);
      events.push('consume');if(pagePending)await pagePending;},
  }),undefined,capacity=>{capacities.push(capacity);events.push('grow-retained');});
  return {events,reader,factory,capacities,provider:()=>provider};
}

test('GitHub native Source joins bounded POST original child charge growth and shared Reader retirement', async () => {
  const f=protocolFixture();
  assert.deepEqual(await f.reader.read(),{pages:1,rowCount:1});
  assert.deepEqual(f.events,['request','original-occurrence','receive','charge','grow-before-decode','grow-retained','decode','consume']);
  assert.equal(f.capacities.length,1);assert.equal(f.reader.observe().cleanupConfirmed,false);
  f.reader.requestStop();assert.equal(f.reader.observe().cleanupConfirmed,true);assert.equal(f.factory.retire(),true);
  assert.equal(f.provider().retire(),true);assert.equal(f.events.at(-1),'codec-close');
  assert(f.events.indexOf('binding-close')<f.events.indexOf('codec-close'));
});

test('GitHub native Source refuses foreign original before request or physical child', async () => {
  const f=protocolFixture({foreign:true});
  await assert.rejects(f.reader.read(),{code:'ForeignGitHubSourceRead'});
  assert.equal(f.events.includes('request'),false);assert.equal(f.events.includes('receive'),false);
  f.reader.requestStop();assert.equal(f.factory.retire(),true);
});

test('GitHub native Source keeps failed decoder prefix under original Reader until retirement', async () => {
  const primary=new Error('original native decode failure'),f=protocolFixture({projectionFailure:primary});
  await assert.rejects(f.reader.read(),error=>error===primary);
  assert.equal(f.events.filter(value=>value==='receive').length,1);assert.equal(f.events.includes('consume'),false);
  f.reader.requestStop();assert.equal(f.reader.observe().cleanupConfirmed,true);assert.equal(f.factory.retire(),true);
});

test('GitHub native Source cannot retire its original prefix while page consumption is pending', async () => {
  let complete;const pending=new Promise(resolve=>{complete=resolve;});
  const f=protocolFixture({pagePending:pending}),read=f.reader.read();
  while(!f.events.includes('consume'))await new Promise(resolve=>setImmediate(resolve));
  f.reader.requestStop();assert.equal(f.provider().retire(),false);assert.equal(f.factory.retire(),false);
  complete();await assert.rejects(read);assert.equal(f.reader.observe().cleanupConfirmed,true);assert.equal(f.factory.retire(),true);
});

test('GitHub actual loader forwards original native capacity sequence and complete RowRun preparation', async () => {
  const source=readFileSync(new URL('../host/installed-github-source.mjs',import.meta.url),'utf8');
  const tree=parse(source,{ecmaVersion:'latest',sourceType:'module'});
  const node=tree.body.find(node=>node.type==='ExportNamedDeclaration'&&node.declaration?.id?.name==='loadInstalledGitHubSource').declaration;
  const {prepareGitHubSourceReadSequence}=await import('../site/github-issue-graphql-read.mjs');
  const {installedJsonSourceReaderLimitNames}=await import('../../../host-node/installed-credential-source-reader.mjs');
  const limits=Object.freeze({maxPages:10,maxRows:100,maxBytes:4000000,maxNodes:400000,maxDepth:32,perPage:100,maxRequestBytes:16384,maxSubjects:100});
  const rowLimits=Object.freeze({maxPages:10,maxPageBytes:4000000,maxPageRows:100,maxCaptureRows:100});
  const site=Object.freeze({apiOrigin:'https://api.github.test',owner:'octo',repo:'hello'});
  const publication=Object.freeze({catalogCid:'original-catalog',repository:{node_id:'R_original',id:13}});
  const installationSite=Object.freeze({credential:{}}),native={},capacity={},implementation={},reader={};
  let sequence,readerOptions,rowOptions,quotes=0;
  const construction=Object.freeze({configurationReader:{async readOriginalText(){return 'original authored views';}},
    prepareDeclaration(text,catalog){assert.equal(text,'original authored views');assert.equal(catalog,publication.catalogCid);},
    async openRowSite(){return {site:installationSite,authorization:{context:{contextCid:'original-context'}}};},
    sourceReaderImplementation(options){sequence=options.readSequenceConstruction;
      assert.equal(sequence.capacity,capacity);assert.equal(sequence.originalLimits,limits);
      assert.equal(sequence.maxRequestBytes,16384);assert.equal(sequence.sequence.operation,'github:graphql:read');
      assert.equal(sequence.sequence.maxUses,10);assert.deepEqual(sequence.sequence.children,[]);return implementation;},
    createSourceReader(options){readerOptions=options;assert.equal(options.implementation,implementation);return reader;},
    async createRowSource(options){rowOptions=options;return {original:options};},
  });
  const moon=Object.freeze({clientProgramInstalledSourceReaderPolicy:()=>[128,4,64],
    clientProgramInstalledNativeSourceReaderCapacity(original,columns,secret,domain){
      assert.equal(original.length,16);assert.equal(original[0],4000000);assert.equal(original[6],10);
      assert.equal(columns,64);assert.equal(secret,128);assert.equal(domain,native);return capacity;}});
  const providerMoon=Object.freeze({githubSourceReadConstructionCapacity(...args){
    assert.deepEqual(args,[4000000,400000,32,100,10,100,0,16384]);quotes++;return native;}});
  const ports={readLimits:limits,rowLimits,httpsCredentialResponseHeaderByteLimit:16384,viewsUrl:new URL('file:///authored/views.json'),
    checkInstalledGitHubSourceProfile:profile=>profile,readSite:async()=>site,readGitHubPublication:async()=>publication,
    GITHUB_GRAPHQL_READ_OPERATION:'github:graphql:read',TARGET_VERSION:'actql-installed-github-target/0.1',
    contentCid:()=> 'original-binding',installedJsonSourceReaderLimitNames,prepareGitHubSourceReadSequence,
    fail(code){throw Object.assign(new Error(code),{code});}};
  const load=new Function(...Object.keys(ports),'return ('+source.slice(node.start,node.end)+');')(...Object.values(ports));
  const loaded=await load({siteProfilePath:'/authored/site',publicationPath:'/authored/publication',accountConfigurationWire:'original-account'},
    {moon,providerMoon,construction,resolveSecret(){assert.fail('No credential resolution at construction');}});
  assert.equal(loaded.original,rowOptions);assert.equal(rowOptions.providerReader,reader);assert.equal(Object.hasOwn(rowOptions,'readPages'),false);
  assert.equal(quotes,1);
  const prepared=await rowOptions.prepareRead({resource:'issues',nonce:'original-nonce',runInvocationCid:'original-run',dispatchRequestCid:'original-dispatch'});
  assert.deepEqual(prepared,{resource:'issues',nonce:'original-nonce',runInvocationCid:'original-run',dispatchRequestCid:'original-dispatch',signal:undefined});
  const originalAuthorization={grant:{},scope:{operation:'github:graphql:read',runInvocationCid:'original-run',dispatchRequestCid:'original-dispatch'}};
  const protocol=readerOptions.prepareReadSequence({preparedRead:prepared,originalAuthorization},
    (method,receiver,args)=>Reflect.apply(method,receiver,args));
  assert.equal(typeof protocol.read,'function');assert.equal(protocol.retire(),true);
});


test('GitHub managed PullRequest selects its original native family through the same Reader', async () => {
  const f=protocolFixture({resource:'pull_requests'});
  assert.deepEqual(await f.reader.read(),{pages:1,rowCount:1});
  assert.equal(f.events.filter(value=>value==='receive').length,1);
  assert.equal(f.events.filter(value=>value==='consume').length,1);
  f.reader.requestStop();assert.equal(f.factory.retire(),true);
});

test('GitHub managed comments consume the same enumeration charge before the dependent page', async () => {
  const f=protocolFixture({resource:'issue_comments'});
  assert.deepEqual(await f.reader.read(),{pages:2,rowCount:1});
  assert.equal(f.events.filter(value=>value==='receive').length,2);
  assert.equal(f.events.filter(value=>value==='charge').length,2);
  assert.equal(f.events.filter(value=>value==='observation').length,1);
  assert.equal(f.events.filter(value=>value==='consume').length,1);
  assert(f.events.indexOf('observation')<f.events.lastIndexOf('receive'));
  f.reader.requestStop();assert.equal(f.factory.retire(),true);
});


test('GitHub original decoder failure survives caller stop and its same close remains retryable', async () => {
  const primary=new Error('original native finish failure'),stop=new Error('same caller stop');
  const cleanup=new Error('original decoder close pending');
  let f;
  f=protocolFixture({beforeFinish(){f.reader.requestStop(stop);},finishFailure:primary,
    closeFailure:cleanup,closeFailures:1});
  await assert.rejects(f.reader.read(),error=>error===primary);
  assert.equal(f.events.filter(value=>value==='receive').length,1);
  assert.equal(f.events.includes('consume'),false);
  assert.equal(f.events.filter(value=>value==='codec-close').length,1);
  assert.equal(f.reader.observe().cleanupConfirmed,false);
  assert.equal(f.factory.retire(),true);
  assert.equal(f.events.filter(value=>value==='codec-close').length,2);
  assert.equal(f.events.filter(value=>value==='binding-close').length,1);
  assert.equal(f.reader.observe().cleanupConfirmed,true);
});

// Actual Source fixture callbacks with explicit transport/Host ports. These
// counters establish caller duties only, not a physical cleanup acknowledgment.
function sourceFixtureLifetimeCallbacks() {
  const source = readFileSync(new URL('./github-standard-host.integration.test.mjs', import.meta.url), 'utf8');
  const tree = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
  const closes = [], afters = [];
  const walk = node => {
    if (node === null || typeof node !== 'object') return;
    if (node.type === 'BlockStatement') {
      const index = node.body.findIndex(statement => statement.type === 'VariableDeclaration' &&
        statement.declarations.some(declaration => declaration.id.name === 'close' &&
          source.slice(declaration.init?.start, declaration.init?.end).includes('await host.close()')));
      if (index >= 0) {
        const selected = node.body[index].declarations.find(declaration => declaration.id.name === 'close');
        const controls = node.body.slice(0, index).filter(statement =>
          statement.type === 'VariableDeclaration' && statement.kind === 'let');
        closes.push(new Function('server', 'host', controls.map(statement =>
          source.slice(statement.start, statement.end)).join('\n') +
          '\nreturn (' + source.slice(selected.init.start, selected.init.end) + ');'));
      }
    }
    if (node.type === 'CallExpression' && node.callee.type === 'MemberExpression' &&
        node.callee.object.name === 't' && node.callee.property.name === 'after' &&
        source.slice(node.arguments[0]?.start, node.arguments[0]?.end)
          .includes('GitHub standard Host custody retained:')) {
      afters.push(new Function('closers', 'root', 'process', 'console', 'rm',
        'return (' + source.slice(node.arguments[0].start, node.arguments[0].end) + ');'));
    }
    for (const child of Object.values(node)) if (Array.isArray(child)) child.forEach(walk);
    else if (child && typeof child === 'object') walk(child);
  };
  walk(tree);
  assert.equal(closes.length, 1); assert.equal(afters.length, 1);
  return {close: closes[0], after: afters[0]};
}

test('GitHub Source fixture retries the same pending Host close after transport closure', async () => {
  for (const failure of [new Error('OriginalHostCleanupPending'), undefined]) {
    let serverCloses = 0, hostCloses = 0;
    const server = {closeAllConnections() {}, close(done) {serverCloses++; done();}};
    const host = {async close() {if (++hostCloses === 1) throw failure;}};
    const close = sourceFixtureLifetimeCallbacks().close(server, host);
    let threw = false;
    try {await close();} catch (error) {threw = true; assert.strictEqual(error, failure);}
    assert.equal(threw, true);
    assert.equal(serverCloses, 1); assert.equal(hostCloses, 1);
    await close();
    assert.equal(serverCloses, 1, 'an already closed transport is not a Host cleanup ACK');
    assert.equal(hostCloses, 2, 'the same original Host close still owns its retry');
    await close();
    assert.equal(serverCloses, 1); assert.equal(hostCloses, 2);
  }
});

test('GitHub Source fixture attempts every original closer and preserves failed cleanup evidence', async () => {
  const events = [], first = new Error('OriginalClientCleanupPending');
  const closers = [async () => {events.push('older');},
    async () => {events.push('middle'); throw undefined;},
    async () => {events.push('newer'); throw first;}];
  const after = sourceFixtureLifetimeCallbacks().after(closers, 'original-fixture-root',
    {env: {}}, {error() {}}, () => assert.fail('Unresolved originals and state must remain'));
  let failure;
  try {await after();} catch (error) {failure = error;}
  assert.deepEqual(events, ['newer', 'middle', 'older']);
  assert(failure instanceof AggregateError);
  assert.deepEqual(failure.errors, [first, undefined]);
});

test('GitHub Source fixture shares its pending original close instead of returning an early ACK', async () => {
  let hostCloses = 0, finish;
  const host = {close() {hostCloses++; return new Promise(resolve => {finish = resolve;});}};
  const server = {closeAllConnections() {}, close(done) {done();}};
  const close = sourceFixtureLifetimeCallbacks().close(server, host);
  const first = close(), second = close();
  assert.strictEqual(second, first);
  let settled = false;
  second.then(() => {settled = true;});
  for (let index = 0; index < 4; index++) await Promise.resolve();
  assert.equal(hostCloses, 1); assert.equal(settled, false);
  finish();
  await first;
  assert.equal(settled, true);
});


// Exact positive fixture Account, interpreted only by its original Core. The
// provider read grant does not imply the independent Host Run-creation grant.
test('GitHub Source Host fixture keeps finite Run admission separate from provider and result rights', async () => {
  const common = await import('../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js');
  const source = readFileSync(new URL('./github-standard-host.integration.test.mjs', import.meta.url), 'utf8');
  const tree = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
  const names = new Set(['hostReadEntry', 'hostRunEntry', 'sourceHostAuthorization']);
  const declarations = tree.body.flatMap(node => node.type === 'VariableDeclaration'
    ? node.declarations.filter(value => names.has(value.id.name)) : []);
  assert(declarations.some(value => value.id.name === 'hostReadEntry'));
  assert(declarations.some(value => value.id.name === 'sourceHostAuthorization'));
  const wire = new Function('canonicalJson', declarations.map(value =>
    'const ' + source.slice(value.start, value.end) + ';').join('\n') +
    '\nreturn sourceHostAuthorization.accountConfiguration;')(canonicalJson);
  const account = common.executionAuthorizationAdmit(wire);
  assert.equal(JSON.parse(common.executionAuthorizationAccountJson(account)).state, 'admitted');
  const evaluate = (original, resource, operation, connection = 'actql-remote-host') =>
    JSON.parse(common.executionAuthorizationEvaluationJson(common.executionAuthorizationEvaluate(
      original, 'source-reader', connection, resource, operation)));
  for (const resource of ['installed-multi-acquired', 'row-source-acquired']) {
    assert.deepEqual(evaluate(account, resource, 'write'),
      {outcome: 'allow', entry_id: 'host-run-acceptance'});
  }
  for (const resource of ['result/audit', 'result/consumed', 'result/consumed_a',
    'result/consumed_b', 'result/grouped', 'result/issues', 'result/joined', 'result/windowed', 'run']) {
    assert.deepEqual(evaluate(account, resource, 'read'),
      {outcome: 'allow', entry_id: 'host-original-observations'});
  }
  for (const [resource, operation, connection] of [
    ['source-free-values', 'write', 'actql-remote-host'],
    ['row-source-acquired', 'write', 'another-host'],
    ['result/not-declared', 'read', 'actql-remote-host'],
    ['issues', 'read', 'actql-remote-host'],
    ['run', 'write', 'actql-remote-host'],
  ]) assert.deepEqual(evaluate(account, resource, operation, connection),
    {outcome: 'deny', reason: 'no_match'});
  const document = JSON.parse(wire);
  assert.deepEqual(document.entries.map(value => value.entry_id),
    ['host-original-observations', 'host-run-acceptance']);
  const readOnly = common.executionAuthorizationAdmit(canonicalJson({...document,
    entries: document.entries.filter(value => value.entry_id !== 'host-run-acceptance')}));
  assert.deepEqual(evaluate(readOnly, 'row-source-acquired', 'write'),
    {outcome: 'deny', reason: 'no_match'});
  assert.equal(evaluate(readOnly, 'run', 'read').outcome, 'allow');
});
