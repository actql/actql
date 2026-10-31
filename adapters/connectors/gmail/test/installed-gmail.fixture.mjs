import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {createHash} from 'node:crypto';
const common=await import(process.env.ACTQL_TEST_GMAIL_COMMON_MODULE ??
  new URL('../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js',import.meta.url).href);
const provider=await import(process.env.ACTQL_TEST_GMAIL_PROVIDER_MODULE ??
  new URL('../../../../_build/js/release/build/connectors/gmail/host_node/host_node.js',import.meta.url).href);
import {canonicalJson} from '../../../host-node/local-account-config.mjs';
import {loadInstalledGmailSource} from '../host/installed-gmail-source.mjs';
import {labelListFixture,labelListReadLimits} from './gmail-label-list.fixture.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import {installedConnectors} from '../../../connectors-builtin/installations.generated.mjs';
import {createInstalledConnectorTable,installedConnectorForTable} from '../../../host-node/installed-connectors.mjs';
import {installedSourceFixtureLifetime} from '../../../host-node/fixtures/installed-source-initialization.mjs';

// Actual Source initialization/services, with explicit test current and Run
// ports. This component is not public Request backing or ordinary acceptance.
// Retained observations and their original state/keys stay in the fixture.
import {threadReadLimits} from './gmail-thread-read.fixture.mjs';
const pending=new Set();
const repo=new URL('../../../../',import.meta.url);
export async function installedGmailFixture(t,{account='allow',resource='labels',accountResource=resource}={}){
  const lifetime=installedSourceFixtureLifetime(t);
  const f=await labelListFixture(lifetime.transportContext,{accounted:false});
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
  const sources=lifetime.sources;
  const options={root:f.root,principalId:'operator',moon:common,providerMoon:provider,
    runtimeBundleCid:`sha256:${createHash('sha256').update(await readFile(new URL(
      '_build/js/release/build/connectors/gmail/host_node/host_node.js',repo))).digest('hex')}`,
    baseEnvironmentWire:await readFile(new URL('spec/local-check-environment.json',repo),'utf8'),
    resolveSecret:async()=>{f.state.resolutions++;await f.state.resolved?.();return f.state.secret;}};
  const table=createInstalledConnectorTable(installedConnectors),installation=installedConnectorForTable(table,'source',profile);
  const initial=lifetime.open({...options,installation});
  const load=async(overrides={})=>initial.load(loadInstalledGmailSource,profile,{...options,...overrides});
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
    const contracts=checked(common.clientPrepareInstalledSequenceContracts(registry,values,fragment,ordered));
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
  return{...f,profile,site,options,load,prepare,retain,common,initial};
}
