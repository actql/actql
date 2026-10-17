// Actual ordinary Common RowRun/Site/Account/SQLite/TLS with an explicit
// component capacity. This is not normal installation/metadata funding.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile,writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import * as common from '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import * as provider from '../../../../_build/js/release/build/connectors/notion/host_node/host_node.js';
import {checked} from '../../../host-common/runtime-result.mjs';
import {canonicalJson,createLocalAuthorizationGate} from '../../../host-node/local-account-config.mjs';
import {createInstalledRowSource,installRowSourceAuthorization,openRowSourceCredentialSite,
  rowSourceCheckEnvironment} from '../../../host-node/installed-row-source.mjs';
import {createNotionDatabaseReaderFactory} from '../host/database-reader.mjs';
import {NOTION_DATA_SOURCE_READ_OPERATION} from '../site/data-source-read.mjs';
import {userListFixture} from './user-list-read.fixture.mjs';

const repo=new URL('../../../../',import.meta.url),pending=new Set();
const metadata=[16384,1024,20,8,8,128,128],readLimits=[...metadata,256,16,4096,16,100000];
export const databaseReaderLimits=Object.freeze({maxResponseBytes:16384,maxTotalResponseBytes:131072,
  maxRequestBytes:1024,maxTargetBytes:1024,maxPages:4,pageSize:10,maxTotalRows:8,maxNodes:1024,maxDepth:20,
  maxDataSources:8,maxProperties:8,maxIdentityBytes:128,maxNameBytes:128,maxCursorBytes:128,
  maxRowNodes:1024,maxRowDepth:20,maxRowTextBytes:8192,maxColumns:16,maxRowWork:1000000,maxPageWork:1000000,
  maxRowsWireBytes:16384,maxRowsWireNodes:2048,maxRowsWireDepth:20,maxPropertyPages:4,maxPropertyItems:128,
  maxPropertyBytes:65536,maxPropertyNodes:4096,maxPropertyTextBytes:32768,maxPropertyWork:1000000});
const savedLimits=[65536,8192,32],hash=wire=>'sha256:'+createHash('sha256').update(wire).digest('hex');
const stamp='2026-10-18T00:00:00.000Z';
function queryPage(id,cursor){
  return JSON.stringify({object:'list',type:'page_or_data_source',page_or_data_source:{},results:[{
    object:'page',id,url:'https://notion.example/'+id,created_time:stamp,last_edited_time:stamp,
    created_by:{object:'user',id:'U1'},last_edited_by:{object:'user',id:'U2'},
    parent:{type:'data_source_id',data_source_id:'s',database_id:'db'},properties:{
      title:{id:'t%3Ax',type:'rich_text',rich_text:[],has_more:true},
      amount:{id:'n',type:'number',number:'EXACT'},enabled:{id:'b',type:'checkbox',checkbox:true},
    }}],has_more:cursor!==null,next_cursor:cursor}).replace('"EXACT"','9007199254740993.25');
}
function propertyPage(text,cursor){return{object:'list',type:'property_item',results:[{
  object:'property_item',id:'t%3Ax',type:'rich_text',rich_text:{type:'text',text:{content:text},plain_text:text}}],
  has_more:cursor!==null,next_cursor:cursor,property_item:{id:'t%3Ax',type:'rich_text',rich_text:{},
    next_url:cursor===null?null:'https://foreign.example/not-followed'}};}
export function databaseSnapshot(){
  const declaration=checked(provider.notionReadDatabaseDeclaration(Buffer.from(JSON.stringify({id:'db',read_contracts:{
    n:[{column:'amount',projection:'value',contract:{type:'decimal',nullable:false,precision:20,scale:2}}],
    't%3Ax':[{column:'title',projection:'value',contract:{type:'string',nullable:false,enum:['ab','cd']}}]}})),...readLimits));
  const database=checked(provider.notionProjectDatabase(Buffer.from(JSON.stringify({object:'database',id:'db',
    data_sources:[{id:'s',name:'tasks'}]})),...metadata));
  const selection=checked(provider.notionSelectReadSource(declaration,database,100000));
  const source=checked(provider.notionProjectSelectedReadSource(selection,Buffer.from(JSON.stringify({object:'data_source',id:'s',
    parent:{type:'database_id',database_id:'db'},properties:{
      title:{id:'t%3Ax',name:'title',type:'rich_text',rich_text:{}},
      amount:{id:'n',name:'amount',type:'number',number:{format:'number'}},
      enabled:{id:'b',name:'enabled',type:'checkbox',checkbox:{}}}})),...metadata));
  const properties=checked(provider.notionBindSelectedReadContracts(selection,source,...readLimits));
  const contracts=checked(provider.notionSourceSystemReadContracts(properties,...readLimits));
  return checked(provider.notionCaptureDatabaseReadSnapshot(selection,source,contracts,...savedLimits));
}

export async function databaseRowReaderFixture(t,{currentAccountFile=false}={}){
  const f=await userListFixture(t,{accounted:false}),snapshot=databaseSnapshot();
  f.state.pages=[queryPage('page1','query cursor'),propertyPage('a','property cursor'),propertyPage('b',null),
    queryPage('page2',null),propertyPage('c','property cursor'),propertyPage('d',null)];
  const resource='tasks',connection='notion:workspace';
  const accountWire=canonicalJson({version:'actql-execution-account-config/0.1',account_id:'database-reader',entries:[{
    entry_id:'database',outcome:'allow',principal:{all:true},connection:{any_of:[connection]},
    resource:{any_of:[resource]},operation:{any_of:['read']},exclusions:[]}]});
  const accountPath=join(f.root,'database-account.json');await writeFile(accountPath,accountWire,{mode:0o600});
  let authorization;
  if(currentAccountFile){
    const context=Object.freeze({principal:'operator',contextCid:hash('original-database-account-context')});
    const gate=await createLocalAuthorizationGate({accountConfig:accountPath,principal:'operator',context}),issued=new WeakSet();
    authorization=Object.freeze({...gate,context,issued:decision=>issued.has(decision),authorize:async(...args)=>{
      const decision=await gate.authorize(...args);issued.add(decision);return decision;
    }});
  }else authorization=await installRowSourceAuthorization({root:f.root,principalId:'operator',connectorRegistration:'notion',
    accountConfiguration:accountWire});
  const specification=checked(provider.notionDatabaseReadSnapshotRelationSpecification(snapshot,resource,...savedLimits));
  const declaration=checked(common.clientProgramRowSourceRestoreRelationDeclaration('workspace','notion','notion/0.1',specification,undefined));
  const declared=JSON.parse(common.clientProgramRowSourceDeclarationJson(declaration));
  const environment=rowSourceCheckEnvironment(await readFile(new URL('spec/local-check-environment.json',repo),'utf8'),declared);
  const runtimeBundleCid=hash(await readFile(new URL('_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js',repo)));
  const site=await openRowSourceCredentialSite({profile:{credentialPrivateKeyPath:join(f.root,'credential-authority.key'),
    credentialAuthorityId:'notion-row-site',credentialKeyId:'key',journalRoot:join(f.root,'ordinary-database-journal'),
    resourceOrigin:f.scope.resourceOrigin,namespaceId:'original-database',environment:'fixture',siteKey:'database-site',siteGeneration:1},
    principalId:'operator',authorization,connection,connectorRegistration:'notion',connectorRevision:'notion/0.1',
    runtimeBundleCid,commonMoon:common,ca:f.options.credential.ca,resolveSecret:f.options.credential.resolveSecret,
    admitsApprovalTarget:()=>false});
  t.after(()=>site.close());
  const capacity=common.clientProgramRowSourceProviderCapacity(1048576n,1048576n);assert.ok(capacity);
  const factory=createNotionDatabaseReaderFactory({moon:provider,snapshot,site,capacity,resource,
    limits:databaseReaderLimits,maxSecretBytes:128});
  const source=await createInstalledRowSource({moon:common,declaration,declared,environmentWire:environment.wire,
    connectorId:'workspace',connectorRegistration:'notion',connectorRevision:'notion/0.1',site,authorization,
    readOperation:NOTION_DATA_SOURCE_READ_OPERATION,
    physicalTarget:(resource,fields)=>Object.freeze({resource,fields:Object.freeze([...fields]),snapshotCid:
      checked(provider.notionDatabaseReadSnapshotSourceCid(snapshot))}),
    bindingCid:hash('original-database-test-binding'),
    limits:{maxPages:databaseReaderLimits.maxPages,maxPageBytes:16384,maxPageRows:10,maxCaptureRows:8},
    providerReader:factory,readPages(){assert.fail('ordinary database cannot use legacy fallback');}});
  t.after(()=>source.close());
  const prepare=async()=>{
    const env=JSON.parse(source.environmentWire),view=env.schema_snapshots.find(x=>x.source_ref===source.sourceReadAccesses[0].sourceRef);
    const check=common.clientProgramCheckEnvironment(source.environmentWire,env.evidence_bundle_cid,false,false,true,false,false,false,false);assert.ok(check);
    const publication=JSON.stringify({environmentCid:env.evidence_bundle_cid,aliases:[{name:'notion.tasks',sourceRef:view.source_ref,
      sourceViewContractCid:view.source_view_contract_cid,schemaContractCid:view.carrier_schema_contract_cid}]});
    const outcome=common.clientProgramPrepareSourceWithParameters('SELECT id, title, amount FROM notion.tasks','sql',check,publication,undefined,undefined);
    const preparedProgram=common.clientProgramPreparationReady(outcome);assert.ok(preparedProgram,common.clientProgramPreparationIssueCode(outcome));
    const aoa=JSON.parse(await readFile(new URL('spec/contracts/actql-aoa.json',repo),'utf8'));
    const input={preparedProgram,registry:await readFile(new URL('spec/dependencies/aoa-pipeline-registry.json',repo),'utf8'),
      values:JSON.stringify(aoa.execution_contracts['REL.values']),fragment:JSON.stringify(aoa.execution_contracts['ACTQL.expression_fragment/0.1']),
      ordered:JSON.stringify(aoa.execution_contracts['REL.derive.ordered'])};
    const preparedSource=await source.prepare(input),plan=source.ledgerCapacity(preparedSource);
    const ledger=common.clientProgramPrepareSingleCapturedLocalInstalledLedger(preparedProgram,plan.capacity,
      plan.transferBytes,plan.executionBytes,input.registry,input.values,input.fragment,input.ordered);assert.ok(ledger);
    return{...input,preparedSource,ledger};
  };
  const retain=async(value,ledger)=>{
    pending.add({value,ledger,source,snapshot,f});
    await writeFile(join(f.root,'database-row-custody.json'),JSON.stringify({cleanupConfirmed:false,
      sourceCid:checked(provider.notionDatabaseReadSnapshotSourceCid(snapshot)),
      usage:common.clientProgramMultiCapturedLedgerUsage(ledger).map(x=>typeof x==='bigint'?x.toString():x)}),{mode:0o600});
  };
  return{...f,snapshot,source,site,factory,capacity,prepare,retain,common,provider,accountPath,accountWire};
}
