// Provider-domain unit tests: the extracted loader uses an explicit facade
// double to inspect Job/request options. These are not lifecycle evidence;
// installed-bound-construction.actual.test.mjs runs the genuine common owners.
import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp,writeFile,readFile,readdir,rm,realpath} from 'node:fs/promises';
import {readFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,isAbsolute} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
import {types as nodeTypes} from 'node:util';
import {parse} from 'acorn';
import {checkInstalledBigQuerySourceProfile,checkInstalledBigQuerySiteProfile,
  installedBigQuerySourceIdentityParts,loadInstalledBigQuerySource,
  INSTALLED_BIGQUERY_SOURCE_VERSION,INSTALLED_BIGQUERY_SITE_VERSION}
  from '../host/installed-bigquery-source.mjs';
import {canonicalJson} from '../../../../packages/sdk/host-port.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import {readSourceProfileJson,readBoundedConfigurationText,captureConfigurationReaders} from '../../../host-node/source-profile-json.mjs';
import {readHostBundles,generateInstallations} from '../../../../scripts/connector-host-bundles.mjs';
import {installedConnectorTable,loadInstalledConnectorModule} from '../../../host-node/installed-connectors.mjs';
const root=fileURLToPath(new URL('../../../../',import.meta.url));
const canonical=x=>canonicalJson(x,{dataKeys:true});
const cid=x=>'sha256:'+createHash('sha256').update(canonical(x)).digest('hex');
const digest=n=>`sha256:${n.repeat(64)}`;
const ok=value=>({$tag:1,_0:value});
const limits=Object.freeze({maxBytes:8192,maxNodes:2000,maxDepth:24,maxFields:16,maxNameBytes:512,maxSchemaBytes:4096,
  maxRows:2,maxTotalRows:4,maxValueNodes:2000,maxValueTextBytes:8192,maxJobBytes:256,maxPageTokenBytes:256,
  maxPages:4,maxResults:2,timeoutMs:0,maxRequests:8,maxRequestBytes:8192,maxSecretBytes:2048,pollDelayMs:0,
  maximumBytesBilled:'9223372036854775807',maxDeclarationBytes:200000,maxDeclarationNodes:20000,maxCaBytes:8192});
const profile=()=>({version:INSTALLED_BIGQUERY_SOURCE_VERSION,connectorId:'bigquery',resource:'usage',project:'acme-project',
  dataset:'product',table:'usage',location:'EU',metadataPath:'/project/table.json',siteProfilePath:'/project/site.json',
  accountConfigurationWire:'{}',limits:{...limits}});
async function fixture(t){
  const path=await realpath(await mkdtemp(join(tmpdir(),'actql-bigquery-install-')));t.after(()=>rm(path,{recursive:true}));
  const caPath=join(path,'public-ca.pem'),sitePath=join(path,'site.json'),metadataPath=join(path,'metadata.json');
  const site={version:INSTALLED_BIGQUERY_SITE_VERSION,apiOrigin:'https://bigquery.example',credentialAuthorityId:'fixture-authority',
    credentialKeyId:'key',credentialPrivateKeyPath:join(path,'UNOPENED-key'),environment:'test',journalRoot:join(path,'UNOPENED-journal'),
    namespaceId:'fixture-source',siteGeneration:1,siteKey:'original-site',tokenEnvironment:'UNRESOLVED_BIGQUERY_TOKEN',caPath};
  const body=Buffer.from('{"kind":"bigquery#table","tableReference":{"projectId":"acme-project","datasetId":"product","tableId":"usage"},"schema":{"fields":[{"name":"ACCOUNT_ID","type":"STRING","mode":"REQUIRED"}]}}');
  const metadata={version:'actql-bigquery-read-metadata/0.1',connectorId:'bigquery',resource:'usage',project:'acme-project',
    dataset:'product',table:'usage',location:'EU',apiOrigin:site.apiOrigin,body:body.toString('base64')};
  await writeFile(caPath,'-----BEGIN CERTIFICATE-----\noriginal public CA\n-----END CERTIFICATE-----\n');
  await writeFile(sitePath,JSON.stringify(site));await writeFile(metadataPath,JSON.stringify(metadata));
  return {path,caPath,sitePath,metadataPath,site,metadata,body,profile:{...profile(),metadataPath,siteProfilePath:sitePath}};
}
function sourceLoader(ports){
  const source=readFileSync(new URL('../host/installed-bigquery-source.mjs',import.meta.url),'utf8');
  const ast=parse(source,{ecmaVersion:'latest',sourceType:'module'}),parts=[];
  for(const node of ast.body){if(node.type==='ImportDeclaration')continue;
    parts.push(source.slice(node.type==='ExportNamedDeclaration'?node.declaration.start:node.start,node.end));}
  const names=['createHash','isAbsolute','nodeTypes','canonicalJson','checked','readSourceProfileJson','readBoundedConfigurationText',
    'captureConfigurationReaders','readBigQuerySqlApi','BIGQUERY_SQL_READ_OPERATION'];
  const bindings={createHash,isAbsolute,nodeTypes,canonicalJson,checked,readSourceProfileJson,readBoundedConfigurationText,captureConfigurationReaders,
    BIGQUERY_SQL_READ_OPERATION:'bigquery:sql:read',...ports};
  // Only import/export syntax is removed. The complete actual module body is
  // retained; physical/nominal provider ports are not production suppliers.
  return new Function(...names,parts.join('\n')+'\nreturn loadInstalledBigQuerySource;')(...names.map(n=>bindings[n]));
}

test('BigQuery installed profile snapshots exact target bounded DATA without callbacks or coercion',()=>{
  const value=profile(),admitted=checkInstalledBigQuerySourceProfile(value);assert.deepEqual(admitted,value);
  assert.notEqual(admitted.limits,value.limits);value.limits.maxRows=99;assert.equal(admitted.limits.maxRows,2);
  assert(Object.isFrozen(admitted));assert(Object.isFrozen(admitted.limits));
  let gets=0;const getter=profile();Object.defineProperty(getter,'project',{get(){gets++;return 'foreign';}});
  for(const v of [getter,new Proxy(profile(),{}),{...profile(),extra:true},
    {...profile(),limits:{...limits,maximumBytesBilled:9223372036854775807n}},
    {...profile(),limits:{...limits,maximumBytesBilled:'9223372036854775808'}},
    {...profile(),limits:{...limits,maximumBytesBilled:'01'}},{...profile(),limits:{...limits,maxRows:5}},
    {...profile(),metadataPath:'relative'}])assert.throws(()=>checkInstalledBigQuerySourceProfile(v),{code:'InvalidInstalledBigQuerySourceProfile'});
  assert.equal(gets,0);
});

test('BigQuery source identity binds exact table metadata location and public TLS bytes before authority',async t=>{
  const f=await fixture(t),first=await installedBigQuerySourceIdentityParts(f.profile,f.profile);
  assert.equal(first[2].metadataCid,cid(f.metadata));const old=first[2].caSha256;
  await writeFile(f.caPath,'-----BEGIN CERTIFICATE-----\nchanged public CA\n-----END CERTIFICATE-----\n');
  assert.notEqual((await installedBigQuerySourceIdentityParts(f.profile,f.profile))[2].caSha256,old);
  await writeFile(f.metadataPath,JSON.stringify({...f.metadata,dataset:'foreign'}));
  await assert.rejects(installedBigQuerySourceIdentityParts(f.profile,f.profile),{code:'InvalidInstalledBigQueryMetadata'});
  await writeFile(f.metadataPath,JSON.stringify({...f.metadata,body:f.metadata.body+'\n'}));
  await assert.rejects(installedBigQuerySourceIdentityParts(f.profile,f.profile),{code:'InvalidInstalledBigQueryMetadata'});
  await writeFile(f.metadataPath,JSON.stringify(f.metadata));await assert.rejects(loadInstalledBigQuerySource(f.profile,{moon:{}}),
    {code:'BigQuerySourceConstructionUnavailable'});
  for(const change of [{...f.site,apiOrigin:f.site.apiOrigin+'/other'},{...f.site,extra:true}]){
    assert.throws(()=>checkInstalledBigQuerySiteProfile(change),{code:'InvalidInstalledBigQuerySite'});
  }
  assert(!(await readdir(f.path)).includes('UNOPENED-journal'));
});

test('BigQuery normal generated table selects the real source role without an invented Effect',async t=>{
  const f=await fixture(t),[entry]=readHostBundles(root,{names:['bigquery']});assert.equal(entry.source.profileVersion,INSTALLED_BIGQUERY_SOURCE_VERSION);
  assert.equal(entry.effect,undefined);assert.equal(entry.providerBundle,undefined);const path=join(f.path,'installations.mjs');
  await writeFile(path,generateInstallations([entry],path,root));const table=await import(pathToFileURL(path));
  const selected=installedConnectorTable(table.installedConnectors).get(INSTALLED_BIGQUERY_SOURCE_VERSION);
  const actual=await loadInstalledConnectorModule(selected);assert.equal(actual.load,loadInstalledBigQuerySource);
  assert.equal(actual.identityParts,installedBigQuerySourceIdentityParts);assert.equal(actual.check,checkInstalledBigQuerySourceProfile);
  assert(selected.implementationFiles.some(x=>x.path==='adapters/connectors/bigquery/host/installed-bigquery-source.mjs'));
});

test('BigQuery domain facade preserves original acquisition Job and request callbacks',async t=>{
  const f=await fixture(t),description=Object.freeze({}),declaration=Object.freeze({}),prepared=Object.freeze({}),acquisition=Object.freeze({});
  const names=['ReadDeclarationConstructionCapacity','DescriptionLimits','DeclarationLimits','DescribeTable','GenerateReadDeclaration','PrepareRead','ReadAcquisition','OriginalJob',
    'BorrowRead','QueryLimits','PrepareJob','NextRequest','RequestMaterial','AttemptRequest','ChargeResponse','AcceptResponse','RecordDecoderRefusal',
    'RecordResponseLoss','JobComplete','JobRemoteDone','JobOriginal','ReadUsage','InterruptRead','RetireReadBorrow','BindReadTransport',
    'JobRecordLimits','JobOriginalRecord','JobOriginalRecordWire','JobOriginalRecordMatchesRequest','JobReadMatchesRowRun'];
  const moon=Object.fromEntries(names.map(n=>['clientProgramBigQuery'+n,()=>assert.fail('unexpected runtime use '+n)]));
  const calls={job:0,read:0,site:0};let hooks,jobName,throwInitialization=false;
  const declared={catalog_cid:digest('a'),views:[{resource:'usage',fields:['ACCOUNT_ID']}],contracts:[]};
  Object.assign(moon,{
    clientProgramBigQueryReadDeclarationConstructionCapacity:()=>Object.freeze({domainQuote:true}),
    clientProgramBigQueryDescriptionLimits:(...args)=>Object.freeze(args),clientProgramBigQueryDeclarationLimits:(...args)=>Object.freeze(args),
    clientProgramBigQueryDescribeTable(project,dataset,table,bytes){assert.deepEqual([project,dataset,table],['acme-project','product','usage']);assert.deepEqual(bytes,f.body);return ok(description);},
    clientProgramBigQueryGenerateReadDeclaration(d,r,c,rev){assert.equal(d,description);assert.deepEqual([r,c,rev],['usage','bigquery','bigquery/0.1']);return ok(declaration);},
    clientProgramRowSourceDeclarationJson(d){assert.equal(d,declaration);return JSON.stringify(declared);},
    clientProgramBigQueryPrepareRead(d,decl,req,q,e){assert.equal(d,description);assert.equal(decl,declaration);assert.equal(req,requirement);
      assert.equal(q,'query body');assert.equal(e,'evidence body');return ok(prepared);},
    clientProgramBigQueryReadAcquisition(p){assert.equal(p,prepared);return acquisition;},
    clientProgramBigQueryOriginalJob(project,id,location,bound){calls.job++;assert.equal(project,'acme-project');assert.equal(location,'EU');assert.equal(bound,256);jobName=id;return ok(job);},
  });
  const requirement=Object.freeze({}),job=Object.freeze({}),site=Object.freeze({credential:Object.freeze({}),callResource(){assert.fail('no HTTP');}}),
    authorization=Object.freeze({context:Object.freeze({contextCid:digest('b')})}),source=Object.freeze({source:true});
  const initializeFailure=Object.freeze({});
  const construction = Object.freeze({
    configurationReader: Object.freeze({readJson: readSourceProfileJson, readText: readBoundedConfigurationText}),
    prepareNativeDeclaration(producer) {
      producer.capacity();
      const projected = producer.project();
      return Object.freeze({...projected, declared});
    },
    async openRowSite(options) {
      calls.site++;
      assert.equal(options.accountConfiguration, '{}');
      const target={version:'actql-installed-bigquery-target/0.1',apiOrigin:f.site.apiOrigin,project:'acme-project',dataset:'product',table:'usage',location:'EU',
        resource:'usage',metadataCid:cid(f.metadata),catalogCid:declared.catalog_cid,fields:['ACCOUNT_ID']};
      assert(options.admitsApprovalTarget(target,'usage'));assert(!options.admitsApprovalTarget({...target,location:'US'},'usage'));
      return {site,authorization};
    },
    async createRowSource(options) {hooks=options;if(throwInitialization)throw initializeFailure;return source;},
  });
  const load=sourceLoader({
    readBigQuerySqlApi:async options=>{calls.read++;assert.equal(options.prepared,prepared);assert.equal(options.rowRun,rowRun);assert.equal(options.withOriginalJob,originalPort);
      assert.equal(options.verifyRead,current);assert.equal(options.authorizationFor,authorize);assert.equal(options.job,job);
      assert.equal(options.credential,site.credential);assert.equal(options.callResource,site.callResource);
      assert.equal(options.limits.maximumBytesBilled,9223372036854775807n);assert.equal(options.limits.maxTotalRows,4n);},
  });
  const options={root:f.path,principalId:'operator',moon,runtimeBundleCid:digest('c'),baseEnvironmentWire:'base environment',construction};
  assert.equal(await load(f.profile,options),source);assert.equal(calls.site,1);
  assert.equal(hooks.prepareAcquisition({declaration,requirement,queryContract:'query body',evidenceContract:'evidence body'}),acquisition);
  const rowRun=Object.freeze({acquisition,run:Object.freeze({}),requestId:'original-source-attempt',runInvocationCid:digest('d'),dispatchRequestCid:digest('e')}),
    current=()=>{},authorize=()=>{},originalPort=()=>assert.fail('driver port must not issue an operation');
  await assert.rejects(hooks.readPages({rowRun,verifyRead:current,authorizationFor:authorize}),{code:'BigQueryOriginalOperationUnavailable'});assert.equal(calls.job,0);
  await hooks.readPages({rowRun,verifyRead:current,authorizationFor:authorize,withOriginalJob:originalPort});assert.equal(calls.read,1);
  assert.equal(jobName,'actql_'+createHash('sha256').update(JSON.stringify([rowRun.runInvocationCid,rowRun.dispatchRequestCid,rowRun.requestId])).digest('hex'));
  await assert.rejects(hooks.readPages({rowRun:{...rowRun,acquisition:{}},withOriginalJob:originalPort}),{code:'ForeignBigQueryReadPreparation'});assert.equal(calls.read,1);
  throwInitialization=true;await assert.rejects(load(f.profile,options),e=>e===initializeFailure);
});
