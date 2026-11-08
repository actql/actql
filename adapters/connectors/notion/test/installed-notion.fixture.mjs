import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {createHash} from 'node:crypto';
const commonUrl=process.env.ACTQL_TEST_COMMON_URL ?? new URL('../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js',import.meta.url).href;
const common=await import(commonUrl);
const provider=await import(process.env.ACTQL_TEST_NOTION_URL ?? new URL('../../../../_build/js/release/build/connectors/notion/host_node/host_node.js',import.meta.url).href);
import {canonicalJson} from '../../../host-node/local-account-config.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import {loadInstalledNotionSource} from '../host/installed-notion-source.mjs';
import {userListFixture,userListReadLimits} from './user-list-read.fixture.mjs';
import {installedConnectors} from '../../../connectors-builtin/installations.generated.mjs';
import {createInstalledConnectorTable,installedConnectorForTable} from '../../../host-node/installed-connectors.mjs';
import {installedSourceFixtureLifetime} from '../../../host-node/fixtures/installed-source-initialization.mjs';

// Explicit private test declaration only, not normal installation quantities.
// This fixture retains its original state files as evidence; the shared Host
// still owns the actual reader and RowRun cleanup.
const repo=new URL('../../../../',import.meta.url);
export async function installedNotionFixture(t,{account='allow'}={}){
  const lifetime=installedSourceFixtureLifetime(t);
  const f=await userListFixture(lifetime.transportContext,{accounted:false});
  const site={version:'actql-installed-notion-site/0.1',apiOrigin:f.scope.resourceOrigin,
    credentialAuthorityId:'installed-notion',credentialKeyId:'key',
    credentialPrivateKeyPath:join(f.root,'credential-authority.key'),environment:'test',
    journalRoot:join(f.root,'installed-journal'),namespaceId:'installed-notion',
    siteGeneration:1,siteKey:'installed-notion',caPath:join(f.root,'server.crt')};
  const siteProfilePath=join(f.root,'installed-site.json');await writeFile(siteProfilePath,JSON.stringify(site));
  const policy=canonicalJson({version:'actql-execution-account-config/0.1',account_id:'installed',entries:[{
    entry_id:'users',outcome:account,principal:{all:true},connection:{any_of:['notion:workspace']},
    resource:{any_of:['users']},operation:{any_of:['read']},exclusions:[]}]});
  const profile={version:'actql-installed-notion-source/0.1',connectorId:'workspace',siteProfilePath,
    accountConfigurationWire:policy,limits:{...userListReadLimits,
      maxDeclarationBytes:4096,maxDeclarationNodes:1000,maxSecretBytes:128,maxCaBytes:16384}};
  const options={root:f.root,principalId:'operator',moon:common,providerMoon:provider,
    runtimeBundleCid:`sha256:${createHash('sha256').update(await readFile(new URL(commonUrl))).digest('hex')}`,
    baseEnvironmentWire:await readFile(new URL('spec/local-check-environment.json',repo),'utf8'),
    resolveSecret:async()=>{f.state.resolutions++;await f.state.resolved?.();return f.state.secret;}};
  const table=createInstalledConnectorTable(installedConnectors),installation=installedConnectorForTable(table,'source',profile);
  const initial=lifetime.open({...options,installation});
  const load=(overrides={})=>initial.load(loadInstalledNotionSource,profile,{...options,...overrides});
  const prepare=async(source,{format='sql',selection='id, name'}={})=>{
    const env=JSON.parse(source.environmentWire),check=common.clientProgramCheckEnvironment(source.environmentWire,
      env.evidence_bundle_cid,false,false,true,false,false,false,false);assert.ok(check);
    const view=env.schema_snapshots.find(v=>v.source_ref===source.sourceReadAccesses[0].sourceRef);assert.ok(view);
    const publication=JSON.stringify({environmentCid:env.evidence_bundle_cid,aliases:[{name:'notion.users',
      sourceRef:view.source_ref,sourceViewContractCid:view.source_view_contract_cid,schemaContractCid:view.carrier_schema_contract_cid}]});
    // This fixture's explicit component ports require a Query acquisition.
    const text=format==='sql'?`SELECT ${selection} FROM notion.users WHERE TRUE`:`FROM notion.users |> WHERE TRUE |> SELECT ${selection}`;
    const outcome=common.clientProgramPrepareSourceWithParameters(text,format,check,publication,undefined,undefined);
    const preparedProgram=common.clientProgramPreparationReady(outcome);assert.ok(preparedProgram,common.clientProgramPreparationIssueCode(outcome));
    const [registry,aoa]=await Promise.all([readFile(new URL('spec/dependencies/aoa-pipeline-registry.json',repo),'utf8'),
      readFile(new URL('spec/contracts/actql-aoa.json',repo),'utf8').then(JSON.parse)]);
    const values=JSON.stringify(aoa.execution_contracts['REL.values']),
      fragment=JSON.stringify(aoa.execution_contracts['ACTQL.expression_fragment/0.1']),
      ordered=JSON.stringify(aoa.execution_contracts['REL.derive.ordered']);
    const contracts=checked(common.clientPrepareInstalledSequenceContracts(registry,values,fragment,ordered));
    const preparation={preparedProgram,registry:contracts,values,fragment,ordered};
    const preparedSource=await source.prepare(preparation),planned=source.ledgerCapacity(preparedSource);
    const ledger=common.clientProgramPrepareSingleCapturedLocalInstalledLedger(preparedProgram,
      planned.capacity,planned.transferBytes,planned.executionBytes,preparation.registry,
      preparation.values,preparation.fragment,preparation.ordered);assert.ok(ledger);
    return{...preparation,preparedSource,ledger};
  };
  const retain=async(capture,ledger)=>{
    assert.equal(typeof capture.close,'function');
    await writeFile(join(f.root,'reader-before-close.json'),JSON.stringify({phase:'before original close',
      usage:common.clientProgramMultiCapturedLedgerUsage(ledger).map(v=>typeof v==='bigint'?v.toString():v)}));
  };
  return{...f,profile,site,options,initial,load,prepare,retain,common};
}
