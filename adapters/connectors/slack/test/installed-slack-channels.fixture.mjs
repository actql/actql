import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {createHash} from 'node:crypto';
import * as common from '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import * as provider from '../../../../_build/js/release/build/connectors/slack/host_node/host_node.js';
import {canonicalJson} from '../../../host-node/local-account-config.mjs';
import {loadInstalledSlackSource} from '../host/installed-slack-source.mjs';
import {channelListFixture,channelListReadLimits} from './channel-list-read.fixture.mjs';

// Explicit private component capacity. It is not C's normal installation quantity or a
// retirement receipt. Raw responses and escaped callbacks remain retained;
// physical transport closure does not return the original reader reservation.
const pending=new Set();
const repo=new URL('../../../../',import.meta.url);
export async function installedSlackChannelsFixture(t,{account='allow',resource='channels'}={}){
  const f=await channelListFixture(t,{accounted:false});
  const site={version:'actql-installed-slack-site/0.1',apiOrigin:f.scope.resourceOrigin,
    credentialAuthorityId:'installed-slack',credentialKeyId:'key',
    credentialPrivateKeyPath:join(f.root,'credential-authority.key'),environment:'test',
    journalRoot:join(f.root,'installed-journal'),namespaceId:'installed-slack',
    siteGeneration:1,siteKey:'installed-slack',caPath:join(f.root,'server.crt')};
  const siteProfilePath=join(f.root,'installed-site.json');
  await writeFile(siteProfilePath,JSON.stringify(site));
  const policy=canonicalJson({version:'actql-execution-account-config/0.1',account_id:'installed',entries:[{
    entry_id:'channels',outcome:account,principal:{all:true},connection:{any_of:['slack:workspace']},
    resource:{any_of:[resource]},operation:{any_of:['read']},exclusions:[]}]});
  const profile={version:'actql-installed-slack-source/0.1',connectorId:'workspace',workspaceId:f.options.workspaceId,
    siteProfilePath,accountConfigurationWire:policy,limits:{...channelListReadLimits,
      maxDeclarationBytes:4096,maxDeclarationNodes:1000,maxSecretBytes:128,maxCaBytes:16384}};
  const capacity=common.clientProgramRowSourceProviderCapacity(262144n,262144n);
  assert.ok(capacity);
  const sources=[];
  const options={root:f.root,principalId:'operator',moon:common,providerMoon:provider,
    runtimeBundleCid:`sha256:${createHash('sha256').update(await readFile(new URL(
      '_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js',repo))).digest('hex')}`,
    baseEnvironmentWire:await readFile(new URL('spec/local-check-environment.json',repo),'utf8'),
    resolveSecret:async()=>{f.state.resolutions++;await f.state.resolved?.();return f.state.secret;},readerCapacity:capacity};
  const load=async(overrides={})=>{const source=await loadInstalledSlackSource(profile,{...options,...overrides});sources.push(source);return source;};
  const prepare=async(source,{format='sql',selection='id, name',resource:selectedResource=resource,predicate}={})=>{
    const env=JSON.parse(source.environmentWire);
    const check=common.clientProgramCheckEnvironment(source.environmentWire,env.evidence_bundle_cid,
      false,false,true,false,false,false,false);assert.ok(check);
    const view=env.schema_snapshots.find(v=>v.source_ref===source.sourceReadAccesses.find(v=>v.resource===selectedResource).sourceRef);assert.ok(view);
    const publication=JSON.stringify({environmentCid:env.evidence_bundle_cid,aliases:[{name:'slack.'+selectedResource,
      sourceRef:view.source_ref,sourceViewContractCid:view.source_view_contract_cid,
      schemaContractCid:view.carrier_schema_contract_cid}]});
    const text=format==='sql'?`SELECT ${selection} FROM slack.${selectedResource}${predicate===undefined?'':' WHERE '+predicate}`
      :`FROM slack.${selectedResource}${predicate===undefined?'':' |> WHERE '+predicate} |> SELECT ${selection}`;
    const outcome=common.clientProgramPrepareSourceWithParameters(text,format,check,publication,undefined,undefined);
    const preparedProgram=common.clientProgramPreparationReady(outcome);
    assert.ok(preparedProgram,common.clientProgramPreparationIssueCode(outcome));
    const [registry,aoa]=await Promise.all([readFile(new URL('spec/dependencies/aoa-pipeline-registry.json',repo),'utf8'),
      readFile(new URL('spec/contracts/actql-aoa.json',repo),'utf8').then(JSON.parse)]);
    const preparation={preparedProgram,registry,values:JSON.stringify(aoa.execution_contracts['REL.values']),
      fragment:JSON.stringify(aoa.execution_contracts['ACTQL.expression_fragment/0.1']),
      ordered:JSON.stringify(aoa.execution_contracts['REL.derive.ordered'])};
    const preparedSource=await source.prepare(preparation),planned=source.ledgerCapacity(preparedSource);
    const ledger=common.clientProgramPrepareSingleCapturedLocalInstalledLedger(preparedProgram,
      planned.capacity,planned.transferBytes,planned.executionBytes,registry,
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
  t.after(async()=>{for(const s of sources)await s.close();});
  return{...f,profile,site,options,capacity,load,prepare,retain,common};
}
