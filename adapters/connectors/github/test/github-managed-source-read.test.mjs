import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {types} from 'node:util';
import {parse} from 'acorn';
import {checked} from '../../../host-common/runtime-result.mjs';
import {invokeScopedCredentialOperation, invocationBindingsMatch} from '../../../host-common/owned-invocation-context.mjs';
import {createInstalledCredentialSourceReader} from '../../../host-node/installed-credential-source-reader.mjs';

// Actual entire GitHub protocol and actual shared Reader; native codec,
// Site/authorization, original-response and capacity ports are explicit.
// This is a caller/lifetime component, not real Core/IO/funding or ACK proof.
function protocolFixture({foreign = false, pagePending, projectionFailure, resource = 'issues'} = {}) {
  const events = [], grant = {}, scope = Object.freeze({operation:'github:graphql:read',
    runInvocationCid:'original-run',dispatchRequestCid:'original-dispatch'});
  const original = Object.freeze({grant,scope,useId:'nonce-read-0'});
  const facts = new WeakMap(), charge = {}, capacities = [];
  const credential = Object.freeze({control:Object.freeze({
    identity(actual) {assert.equal(actual,grant);return 'original-grant';},
    useProjection(value) {return value;},
  }),journal:{}});
  let commentReplies = 0, sends = 0;
  const methods = {
    githubIssuesRequestJson() {events.push('request');return '{"body":"original native request"}';},
    githubIssuePageReadBegin() {events.push('decode');if(projectionFailure)throw projectionFailure;return {$tag:1,_0:{}};},
    githubIssuePageReadNextRequestJson() {return {$tag:1,_0:'{"body":null}'};},
    githubIssuePageReadAccept(){assert.fail('No nested page');},
    githubIssuePageReadFinishJson() {return {$tag:1,_0:'{"rows":[{"id":"original"}],"hasNextPage":false,"endCursor":null}'};},
    githubIssuePageReadClose() {events.push('codec-close');},
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
    githubIssueCommentsReadAccept(){commentReplies++;},
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
    prepareReadSequence(input){
      assert.equal(input.originalAuthorization,original);
      provider=prepare({moon,site,repository:{nodeId:'R_original',databaseId:13,nameWithOwner:'o/r'},
        preparedRead:input.preparedRead,originalAuthorization:original,
        limits:{maxPages:10,maxRows:100,maxBytes:4000000,maxNodes:400000,maxDepth:32,perPage:100,maxRequestBytes:16384,maxSubjects:100},
        responseCapacity(bytes){events.push('grow-before-decode');return {bytes};}});
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
  assert.deepEqual(f.events,['request','original-occurrence','receive','charge','grow-before-decode','grow-retained','decode','codec-close','consume']);
  assert.equal(f.capacities.length,1);assert.equal(f.reader.observe().cleanupConfirmed,false);
  f.reader.requestStop();assert.equal(f.reader.observe().cleanupConfirmed,true);assert.equal(f.factory.retire(),true);
  assert.equal(f.provider().retire(),true);assert.equal(f.events.at(-1),'binding-close');
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
  const protocol=readerOptions.prepareReadSequence({preparedRead:prepared,originalAuthorization});
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
