// Actual Common/Account/Credential/SQLite/TLS component fixture. Explicit
// diagnostic capacity is not the normal Host's startup/preparation supplier.
import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {createHash} from 'node:crypto';
import * as common from '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import * as provider from '../../../../_build/js/release/build/connectors/calendar/host_node/host_node.js';
import {canonicalJson} from '../../../host-node/local-account-config.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import {installedConnectors} from '../../../connectors-builtin/installations.generated.mjs';
import {createInstalledConnectorTable,installedConnectorForTable} from '../../../host-node/installed-connectors.mjs';
import {calendarFixture,calendarReadLimits} from './calendar-list.fixture.mjs';

const repo=new URL('../../../../',import.meta.url);
export async function installedCalendarFixture(t,{account='allow',accountResource='calendars'}={}){
  const f=await calendarFixture(t,{accounted:false}),sources=[];
  const site={version:'actql-installed-calendar-site/0.1',apiOrigin:f.scope.resourceOrigin,
    credentialAuthorityId:'installed-calendar',credentialKeyId:'key',
    credentialPrivateKeyPath:join(f.root,'credential-authority.key'),environment:'test',
    journalRoot:join(f.root,'installed-journal'),namespaceId:'installed-calendar',
    siteGeneration:1,siteKey:'installed-calendar',caPath:join(f.root,'server.crt')};
  const siteProfilePath=join(f.root,'installed-site.json');await writeFile(siteProfilePath,JSON.stringify(site));
  const profile={version:'actql-installed-calendar-source/0.1',connectorId:'fixture',siteProfilePath,
    accountConfigurationWire:canonicalJson({version:'actql-execution-account-config/0.1',account_id:'installed',entries:[{
      entry_id:'calendar-read',outcome:account,principal:{all:true},connection:{any_of:['calendar:fixture']},
      resource:{any_of:[accountResource]},operation:{any_of:['read']},exclusions:[]}]}),
    limits:{...calendarReadLimits,maxDeclarationBytes:4096,maxDeclarationNodes:1000,maxSecretBytes:128,maxCaBytes:16384}};
  const capacity=common.clientProgramRowSourceProviderCapacity(262144n,262144n);assert.ok(capacity);
  const options={root:f.root,principalId:'operator',moon:common,providerMoon:provider,
    runtimeBundleCid:`sha256:${createHash('sha256').update(await readFile(new URL(
      '_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js',repo))).digest('hex')}`,
    baseEnvironmentWire:await readFile(new URL('spec/local-check-environment.json',repo),'utf8'),
    resolveSecret:async()=>{f.state.resolutions++;await f.state.resolved?.();return f.state.secret;},readerCapacity:capacity};
  const table=createInstalledConnectorTable(installedConnectors),selected=installedConnectorForTable(table,'source',profile);
  const module=await selected.source.load();
  const load=async(overrides={})=>{const source=await module.load(profile,{...options,...overrides});sources.push(source);return source;};
  const prepare=async(source,{format='sql',selection='id, summary, time_zone, access_role'}={})=>{
    const env=JSON.parse(source.environmentWire),check=common.clientProgramCheckEnvironment(source.environmentWire,
      env.evidence_bundle_cid,false,false,true,false,false,false,false);assert.ok(check);
    const view=env.schema_snapshots.find(v=>v.source_ref===source.sourceReadAccesses[0].sourceRef);assert.ok(view);
    const publication=JSON.stringify({environmentCid:env.evidence_bundle_cid,aliases:[{name:'calendar.calendars',
      sourceRef:view.source_ref,sourceViewContractCid:view.source_view_contract_cid,schemaContractCid:view.carrier_schema_contract_cid}]});
    const text=format==='sql'?`SELECT ${selection} FROM calendar.calendars`:`FROM calendar.calendars |> SELECT ${selection}`;
    const outcome=common.clientProgramPrepareSourceWithParameters(text,format,check,publication,undefined,undefined);
    const preparedProgram=common.clientProgramPreparationReady(outcome);assert.ok(preparedProgram,common.clientProgramPreparationIssueCode(outcome));
    const[registry,aoa]=await Promise.all([readFile(new URL('spec/dependencies/aoa-pipeline-registry.json',repo),'utf8'),
      readFile(new URL('spec/contracts/actql-aoa.json',repo),'utf8').then(JSON.parse)]);
    const values=JSON.stringify(aoa.execution_contracts['REL.values']),
      fragment=JSON.stringify(aoa.execution_contracts['ACTQL.expression_fragment/0.1']),
      ordered=JSON.stringify(aoa.execution_contracts['REL.derive.ordered']);
    const contracts=checked(common.clientPrepareInstalledSequenceContracts(registry,values,fragment,ordered));
    const preparation={preparedProgram,registry:contracts,values,fragment,ordered};
    const preparedSource=await source.prepare(preparation),planned=source.ledgerCapacity(preparedSource);
    const ledger=common.clientProgramPrepareSingleCapturedLocalInstalledLedger(preparedProgram,planned.capacity,
      planned.transferBytes,planned.executionBytes,preparation.registry,preparation.values,preparation.fragment,preparation.ordered);assert.ok(ledger);
    return{...preparation,preparedSource,ledger};
  };
  t.after(async()=>{for(const source of sources)await source.close();});
  return{...f,profile,site,options,capacity,load,prepare,common,module};
}
