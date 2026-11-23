// Actual Common/Host request/Account/Credential/SQLite/TLS with explicitly
// selected private fixture signing material and observation-ticket doubles.
// No normal Site issuer, metadata reservation or raw-retirement supplier.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {generateKeyPairSync} from 'node:crypto';
import {mkdir,mkdtemp,readFile,writeFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {join} from 'node:path';
import {checked} from '../../../host-common/runtime-result.mjs';
import {canonicalJson,contentCid,createLocalAuthorizationGate} from '../../../host-node/local-account-config.mjs';
import {createInstalledConnectorTable} from '../../../host-node/installed-connectors.mjs';
import {publishInstalledSourceProfile,installedSourcePublicationRequestId,
  assertInstalledSourcePublicationRequest,observeInstalledSourcePublicationCurrent} from '../../../host-node/installed-source.mjs';
import {openSqliteCredentialJournal} from '../../../site-node/sqlite-credential-journal.mjs';
import {signRemoteCredentialGrant} from '../../../site-node/remote-credential-signature.mjs';
import {openHttpsCredentialBinding,closeHttpsCredentialBinding} from '../../../site-node/https-credential-resource.mjs';
import {createNotionDatabaseDiscovery,NOTION_DATABASE_RETRIEVE_OPERATION as databaseOperation,
  NOTION_DATA_SOURCE_RETRIEVE_OPERATION as sourceOperation} from '../site/database-discovery.mjs';

import type {IncomingMessage,ServerResponse} from 'node:http';
import type {AddressInfo} from 'node:net';
import type {TestContext} from 'node:test';
import type {createInstallationPreparationMetadata} from '../../../host-common/installation-preparation-metadata.mjs';
import type {OriginalPublication} from '../../../host-node/installed-source-publication.mjs';
import type {NotionReadObservation} from '../site/property-item-read.mjs';
import type {NotionMetadataBounds} from './catalog-bindings.fixture.mjs';
import type {NotionPropertyFixtureBindings} from './property-item-read.fixture.mjs';

type ReaderOptions = Parameters<typeof createNotionDatabaseDiscovery>[0];
type Reader = ReturnType<typeof createNotionDatabaseDiscovery>;
type MetadataSelection = Parameters<NonNullable<ReaderOptions['sourceAuthorizationFor']>>[0];
type MetadataOperation = Parameters<ReaderOptions['current']>[0];
type MetadataView = ReturnType<typeof createInstallationPreparationMetadata>;
type Control = ReturnType<MetadataView['forSubject']>;
type MetadataScope = ReturnType<MetadataView['prepareScope']>;
type Journal = ReturnType<typeof openSqliteCredentialJournal>;
type Charge = Readonly<{originalBody:NotionReadObservation['body']}>;
export type MetadataFixtureBindings = NotionPropertyFixtureBindings &
  Required<NonNullable<ReaderOptions['moon']>>;

type FixtureState = {
  requests:{path:string|undefined;method:string|undefined;version:string|string[]|undefined;originalMaterial:boolean}[];
  charges:Charge[];observations:Charge[];secrets:number;current:number;active:boolean;
  onCurrent?: (operation:MetadataOperation,count:number)=>unknown;
  onSchema?: (selection:MetadataSelection)=>unknown;
  reply(request:IncomingMessage,response:ServerResponse):unknown;
};
type PublicationBindings = NonNullable<OriginalPublication['bindings']>;
type PublishInput = Omit<PublicationBindings,'profile'> & {publicationRequest:object};
type FixtureProfile = Readonly<{version:string;connectorId:string}>;
type MetadataState = {
  root:string;state:FixtureState;journal:Journal|undefined;declaration:unknown;origin:string;
  profilePath:string;accountPath:string;provider:MetadataFixtureBindings;
};
type Fixture<Run> = MetadataState & {run(callback:(original:Run)=>unknown):Promise<unknown>};
export type MetadataRunReaderOptions = Pick<ReaderOptions,'authorizationFor'|'current'|'limits'> & {
  moon:MetadataFixtureBindings;declaration:unknown;initialAuthorization:Readonly<{grant:unknown;scope:MetadataScope;useId:string}>;
  credential:unknown;sourceAuthorizationFor(selection:MetadataSelection):unknown;
  chargeResponse(body:NotionReadObservation['body']):Charge;
  consumeObservation(charge:unknown):void;
};
type MetadataViewRun = MetadataState & {
  control:Control;view:MetadataView;subject:unknown;
  options: Omit<MetadataRunReaderOptions,'sourceAuthorizationFor'> & {
    sourceAuthorizationFor(selection:MetadataSelection):Promise<MetadataRunReaderOptions['initialAuthorization']>;
  };
  scopeFor(operation:MetadataOperation,path:string,occurrence:string):MetadataScope;
  authorize(scope:MetadataScope,useId:string):MetadataRunReaderOptions['initialAuthorization'];
  reader(changes?:Partial<ReaderOptions>):Reader;
};
type MetadataPublicationInput = MetadataState & {
  profile:FixtureProfile;options:PublishInput;resolveSecret:()=>Promise<string>;
  gate:Awaited<ReturnType<typeof createLocalAuthorizationGate>>;cert:Buffer;declarationBytes:Buffer;
};
type DelegatedPublication<Run> = (input:MetadataPublicationInput,callback:(original:Run)=>unknown)=>unknown;

const common:unknown=await import(new URL(
  '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js',import.meta.url).href);
const provider:MetadataFixtureBindings=await import(new URL(
  '../../../../_build/js/release/build/connectors/notion/host_node/host_node.js',import.meta.url).href);
const {runtimeCore}:{runtimeCore(moon:unknown):{installationPreparationMetadata():MetadataView}}=
  await import(new URL('../../../host-common/runtime-core.mjs',import.meta.url).href);

const emptyBody='sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
const version='actql-installed-notion-metadata-discovery-private-fixture/0.1';
const metadata:NotionMetadataBounds=[16384,1024,20,8,8,128,128];
export const metadataDiscoveryLimits=Object.freeze({maxResponseBytes:16384,maxTotalResponseBytes:32768,
  maxTargetBytes:1024,maxNodes:1024,maxDepth:20,maxDataSources:8,maxProperties:8,maxIdentityBytes:128,
  maxNameBytes:128,maxContractNodes:256,maxContractDepth:16,maxContractTextBytes:4096,maxColumns:16,
  maxWork:100000,maxWireBytes:8192,maxWireNodes:256,maxWireDepth:16});
const database=()=>({object:'database',id:'db',data_sources:[{id:'s',name:'tasks'}]});
const schema=()=>({object:'data_source',id:'s',parent:{type:'database_id',database_id:'db'},
  properties:{text:{id:'t',name:'text',type:'rich_text',rich_text:{}}}});

export function metadataDiscoveryFixture(t:TestContext):Promise<Fixture<MetadataViewRun> & {journal:Journal}>;
export function metadataDiscoveryFixture<Run>(t:TestContext,options:{publication:DelegatedPublication<Run>}):Promise<Fixture<Run>>;
export async function metadataDiscoveryFixture<Run>(t:TestContext,
  {publication}:{publication?:DelegatedPublication<Run>}={}):Promise<Fixture<Run>>{
  const parent=join(process.cwd(),'_build','notion-metadata-discovery-fixtures');
  await mkdir(parent,{recursive:true,mode:0o700});const root=await mkdtemp(join(parent,'original-'));
  execFileSync('openssl',['req','-x509','-newkey','rsa:2048','-nodes','-keyout','tls.key','-out','tls.crt',
    '-subj','/CN=localhost','-days','1','-addext','subjectAltName=DNS:localhost,IP:127.0.0.1'],{cwd:root,stdio:'ignore'});
  const cert=await readFile(join(root,'tls.crt')),key=await readFile(join(root,'tls.key'));
  const state:FixtureState={requests:[],charges:[],observations:[],secrets:0,current:0,onCurrent:undefined,
    onSchema:undefined,reply:request=>request.url==='/v1/databases/db'?database():schema(),active:true};
  const server=createServer({cert,key},async(req,res)=>{
    state.requests.push({path:req.url,method:req.method,version:req.headers['notion-version'],
      originalMaterial:req.headers.authorization==='Bearer original-notion-metadata-token'});
    try{assert(state.requests.at(-1)!.originalMaterial);const value=await state.reply(req,res);
      if(!res.destroyed&&!res.writableEnded)res.writeHead(200,{'content-type':'application/json'}).end(JSON.stringify(value));}
    catch(cause){res.destroy(cause as Error);}
  });
  await new Promise<void>((resolve,reject)=>{server.once('error',reject);server.listen(0,'127.0.0.1',resolve);});
  const origin='https://127.0.0.1:'+(server.address() as AddressInfo).port;
  const keys=generateKeyPairSync('ed25519');
  await writeFile(join(root,'issuer-private.pem'),keys.privateKey.export({type:'pkcs8',format:'pem'}),{mode:0o600});
  await writeFile(join(root,'issuer-public.pem'),keys.publicKey.export({type:'spki',format:'pem'}),{mode:0o600});
  const journal=publication===undefined?openSqliteCredentialJournal(join(root,'journal'),{credentialAuthorities:
    new Map([['notion-metadata-fixture',new Map([['key',keys.publicKey]])]]),maxGrants:16,maxUses:16}):undefined;
  const accountWire=canonicalJson({version:'actql-execution-account-config/0.1',account_id:'metadata-fixture',
    entries:[{entry_id:'metadata-read',outcome:'allow',principal:{all:true},connection:{any_of:['notion:fixture']},
      resource:{any_of:['database:db']},operation:{any_of:['read']},exclusions:[]}]});
  const accountPath=join(root,'account.json');await writeFile(accountPath,accountWire,{mode:0o600});
  const gate=await createLocalAuthorizationGate({accountConfig:accountPath,principal:'operator'});
  const profilePath=join(root,'profile.json');await writeFile(profilePath,JSON.stringify({version,connectorId:'fixture'}),{mode:0o600});
  const declarationBytes=Buffer.from(' \r\n{"id":"db","read_contracts":{"t":[{"column":"text","projection":"value","contract":{"type":"string","nullable":false}}]}}\n');
  const declaration=checked(provider.notionReadDatabaseDeclaration(declarationBytes,...metadata,256,16,4096,16,100000));
  const resolveSecret=async()=>{state.secrets++;return'original-notion-metadata-token';};
  let binding:ReturnType<typeof openHttpsCredentialBinding>|undefined;
  const f={root,state,journal,declaration,origin,profilePath,accountPath,provider} as Fixture<Run>;
  t.after(async()=>{
    if(binding)assert.equal(closeHttpsCredentialBinding(binding),'closed');journal?.close();
    await new Promise<void>((resolve,reject)=>server.close(cause=>cause?reject(cause):resolve()));
    await writeFile(join(root,'physical-observation.json'),JSON.stringify({requests:state.requests,
      responseCharges:state.charges.length,retainedObservations:state.observations.length,
      secretResolutions:state.secrets,currentChecks:state.current,cleanupConfirmed:false}),{mode:0o600});
    t.diagnostic('Retained original Notion metadata fixture: '+root);
  });
  f.run=async(callback)=>{
    const module={check:(profile:FixtureProfile)=>Object.freeze({...profile}),
      identityParts(){assert.fail('Metadata publication cannot recompute identity');},
      load(){assert.fail('Metadata publication cannot create a query Run');},
      async publish(profile:FixtureProfile,options:PublishInput){
        if(publication!==undefined)return publication({...f,profile,options,resolveSecret,gate,cert,declarationBytes},callback);
        const request=options.publicationRequest,originals={...options,profile};
        const view=runtimeCore(common).installationPreparationMetadata();
        const subject=view.prepareSubject({accountConfigurationCid:contentCid(JSON.parse(accountWire)),accountId:'metadata-fixture',
          connection:'notion:fixture',connectorRegistration:options.installation.registration,
          connectorRevision:options.installation.revision,declarationSourceCid:provider.notionReadDatabaseDeclarationSourceCid(declaration),
          installationRequestId:installedSourcePublicationRequestId(request),principal:options.principalId,
          runtimeBundleCid:options.runtimeBundleCid,siteGeneration:1,siteKey:'notion-metadata-fixture'});
        const control=view.forSubject(subject);
        const assertCurrent=()=>{assertInstalledSourcePublicationRequest(request,originals);
          if(!state.active)throw Object.assign(new Error('NotionMetadataFixtureRevoked'),{code:'NotionMetadataFixtureRevoked'});};
        const current=async(operation:MetadataOperation)=>{
          await observeInstalledSourcePublicationCurrent(request,originals);
          // Common's clientInstallationPreparationSubjectCid projects a String from this retained Subject.
          const decision=await gate.authorize('acquisition',{connection:'notion:fixture',resource:'database:db',operation:'read'},
            {subjectCid:view.subjectCid(subject) as string});
          if(decision.action!=='dispatch')throw Object.assign(new Error('NotionMetadataFixtureDenied'),{code:'NotionMetadataFixtureDenied'});
          state.current++;await state.onCurrent?.(operation,state.current);assertCurrent();
        };
        const scopeFor=(operation:MetadataOperation,path:string,occurrence:string)=>view.prepareScope(subject,{metadataOccurrenceId:occurrence,operation,
          requestBodyCid:emptyBody,requestMethod:'GET',requestPath:path,resourceOrigin:origin});
        const authorize=(scope:MetadataScope,useId:string)=>{
          const grant=control.prepare({issuerAuthority:'notion-metadata-fixture',scope,
            expiresUnixMilliseconds:BigInt(Date.now()+60000),maxUses:1});
          journal!.acceptGrant(signRemoteCredentialGrant(grant,control,{keyId:'key',privateKey:keys.privateKey}),control);
          return{grant,scope,useId};
        };
        const initial=authorize(scopeFor(databaseOperation,'/v1/databases/db','database'),requestId('database'));
        function requestId(name:string){return installedSourcePublicationRequestId(request)+':'+name;}
        binding=openHttpsCredentialBinding({scope:initial.scope,control,journal:journal!,resolveSecret,maxSecretBytes:128,assertCurrent});
        const optionsForReader={moon:provider,declaration,initialAuthorization:initial,
          credential:{binding,control,journal,resolveSecret,ca:cert},authorizationFor:({operation,index}:Parameters<ReaderOptions['authorizationFor']>[0])=>{
            assert.equal(operation,databaseOperation);assert.equal(index,0);return initial;},current,
          sourceAuthorizationFor:async (selected:MetadataSelection)=>{
            assert.equal(selected.declaration,declaration);assert.equal(selected.operation,sourceOperation);
            assert.equal(provider.notionReadSourceSelectionMatches(selected.selection,declaration,selected.database),true);
            assert.equal(selected.origin,origin);assert.equal(selected.path,'/v1/data_sources/s');
            await state.onSchema?.(selected);
            return authorize(scopeFor(sourceOperation,selected.path,'schema'),requestId('schema'));
          },
          chargeResponse:(body:NotionReadObservation['body'])=>{const charge=Object.freeze({originalBody:body});state.charges.push(charge);return charge;},
          consumeObservation:(charge:unknown)=>{assert(state.charges.includes(charge as Charge));assert(!state.observations.includes(charge as Charge));state.observations.push(charge as Charge);},
          limits:metadataDiscoveryLimits};
        // The default overload pairs this callback with the original metadata view.
        return (callback as (original:MetadataViewRun)=>unknown)({...f,control,view,subject,options:optionsForReader,scopeFor,authorize,
          reader:changes=>createNotionDatabaseDiscovery({...optionsForReader,...changes})});
      }};
    const connectorTable=createInstalledConnectorTable([{name:'notion',registration:'notion',revision:'notion/0.1',
      source:{profileVersion:version,load:async()=>module}}]);
    return publishInstalledSourceProfile(profilePath,{root,principalId:'operator',moon:common,
      runtimeUrl:new URL('../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js',import.meta.url),
      resolveSecret,connectorTable});
  };
  return f;
}
