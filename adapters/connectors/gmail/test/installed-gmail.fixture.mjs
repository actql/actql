import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {createHash} from 'node:crypto';
import * as common from '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import * as provider from '../../../../_build/js/release/build/connectors/gmail/host_node/host_node.js';
import {canonicalJson} from '../../../host-node/local-account-config.mjs';
import {loadInstalledGmailSource} from '../host/installed-gmail-source.mjs';
import {labelListFixture,labelListReadLimits} from './gmail-label-list.fixture.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import {installedConnectors} from '../../../connectors-builtin/installations.generated.mjs';
import {createInstalledConnectorTable,installedConnectorForTable} from '../../../host-node/installed-connectors.mjs';
import {installedSourceFixtureLifetime} from '../../../host-node/fixtures/installed-source-initialization.mjs';

// Only a test declaration. It is not C's normal installation quantity or a
// retirement receipt. Retain original handles/ledgers until this child exits;
// original DB/keys and a pending-custody receipt stay in the fixture directory.
import {threadReadLimits} from './gmail-thread-read.fixture.mjs';
const pending=new Set();
const repo=new URL('../../../../',import.meta.url);
export async function installedGmailFixture(t,{account='allow',resource='labels',accountResource=resource}={}){
  const lifetime=resource==='labels'?installedSourceFixtureLifetime(t):undefined;
  const f=await labelListFixture(lifetime?.transportContext??t,{accounted:false});
  const site={version:'actql-installed-gmail-site/0.1',apiOrigin:f.scope.resourceOrigin,
    credentialAuthorityId:'installed-gmail',credentialKeyId:'key',
    credentialPrivateKeyPath:join(f.root,'credential-authority.key'),environment:'test',
    journalRoot:join(f.root,'installed-journal'),namespaceId:'installed-gmail',
    siteGeneration:1,siteKey:'installed-gmail',caPath:join(f.root,'server.crt')};
  const siteProfilePath=join(f.root,'installed-site.json');
  await writeFile(siteProfilePath,JSON.stringify(site));
  const policy=canonicalJson({version:'actql-execution-account-config/0.1',account_id:'installed',entries:[{
    entry_id:'labels',outcome:account,principal:{all:true},connection:{any_of:['gmail:mailbox']},
    resource:{any_of:[accountResource]},operation:{any_of:['read']},exclusions:[]}]});
  const profile={version:'actql-installed-gmail-source/0.1',connectorId:'mailbox',mailbox:f.options.mailbox,
    ...(resource==='labels'?{}:{resource}),siteProfilePath,accountConfigurationWire:policy,
    limits:{...(resource==='threads'?threadReadLimits:labelListReadLimits),
      maxDeclarationBytes:4096,maxDeclarationNodes:1000,maxSecretBytes:128,maxCaBytes:16384}};
  // Only the not-yet-migrated thread sequence retains its old explicit
  // component declaration. Labels select their actual initial/service parent.
  const capacity=resource==='labels'?undefined:common.clientProgramRowSourceProviderCapacity(262144n,262144n);
  if(resource!=='labels')assert.ok(capacity);
  const sources=lifetime?.sources??[];
  const options={root:f.root,principalId:'operator',moon:common,providerMoon:provider,
    runtimeBundleCid:`sha256:${createHash('sha256').update(await readFile(new URL(
      '_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js',repo))).digest('hex')}`,
    baseEnvironmentWire:await readFile(new URL('spec/local-check-environment.json',repo),'utf8'),
    resolveSecret:async()=>{f.state.resolutions++;await f.state.resolved?.();return f.state.secret;},
    ...(capacity===undefined?{}:{readerCapacity:capacity})};
  let initial;
  if(lifetime!==undefined){
    const table=createInstalledConnectorTable(installedConnectors),installation=installedConnectorForTable(table,'source',profile);
    initial=lifetime.open({...options,installation});
  }
  const load=async(overrides={})=>{
    if(initial!==undefined)return initial.load(loadInstalledGmailSource,profile,{...options,...overrides});
    const source=await loadInstalledGmailSource(profile,{...options,...overrides});sources.push(source);return source;
  };
  const prepare=async(source,{format='sql',selection=resource==='threads'?'id, labels, last_message_date, message_count, subject':'id, name, type'}={})=>{
    const env=JSON.parse(source.environmentWire);
    const check=common.clientProgramCheckEnvironment(source.environmentWire,env.evidence_bundle_cid,
      false,false,true,false,false,false,false);assert.ok(check);
    const view=env.schema_snapshots.find(v=>v.source_ref===source.sourceReadAccesses[0].sourceRef);assert.ok(view);
    const publication=JSON.stringify({environmentCid:env.evidence_bundle_cid,aliases:[{name:`gmail.${resource}`,
      sourceRef:view.source_ref,sourceViewContractCid:view.source_view_contract_cid,
      schemaContractCid:view.carrier_schema_contract_cid}]});
    const text=format==='sql'?`SELECT ${selection} FROM gmail.${resource}`:`FROM gmail.${resource} |> SELECT ${selection}`;
    const outcome=common.clientProgramPrepareSourceWithParameters(text,format,check,publication,undefined,undefined);
    const preparedProgram=common.clientProgramPreparationReady(outcome);
    assert.ok(preparedProgram,common.clientProgramPreparationIssueCode(outcome));
    const [registry,aoa]=await Promise.all([readFile(new URL('spec/dependencies/aoa-pipeline-registry.json',repo),'utf8'),
      readFile(new URL('spec/contracts/actql-aoa.json',repo),'utf8').then(JSON.parse)]);
    const values=JSON.stringify(aoa.execution_contracts['REL.values']),
      fragment=JSON.stringify(aoa.execution_contracts['ACTQL.expression_fragment/0.1']),
      ordered=JSON.stringify(aoa.execution_contracts['REL.derive.ordered']);
    const contracts=resource==='labels'?checked(common.clientPrepareInstalledSequenceContracts(registry,values,fragment,ordered)):registry;
    const preparation={preparedProgram,registry:contracts,values,fragment,ordered};
    const preparedSource=await source.prepare(preparation),planned=source.ledgerCapacity(preparedSource);
    const ledger=common.clientProgramPrepareSingleCapturedLocalInstalledLedger(preparedProgram,
      planned.capacity,planned.transferBytes,planned.executionBytes,contracts,
      preparation.values,preparation.fragment,preparation.ordered);
    assert.ok(ledger,`original ${format} Source graph must prepare its same installed Ledger; tasks=${common.clientProgramTaskCount(preparedProgram)}`);
    return{...preparation,preparedSource,ledger};
  };
  const retain=async(capture,ledger)=>{
    pending.add({capture,ledger,sources,f});
    await writeFile(join(f.root,'pending-reader-custody.json'),JSON.stringify({cleanupConfirmed:false,
      reason:'Raw/Promise/callback aliases not transferred or retired; original RowRun reservation retained',
      usage:common.clientProgramMultiCapturedLedgerUsage(ledger).map(v=>typeof v==='bigint'?v.toString():v)}));
  };
  if(lifetime===undefined)t.after(async()=>{for(const s of sources)await s.close();});
  return{...f,profile,site,options,capacity,load,prepare,retain,common,initial};
}
