import assert from 'node:assert/strict';
import {inspect} from 'node:util';
import {createHash} from 'node:crypto';
import {readFile, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import * as common from '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {checked} from '../../../host-common/runtime-result.mjs';
import {canonicalJson} from '../../../host-node/local-account-config.mjs';
import {loadInstalledSource, installedSourceIdentity} from '../../../host-node/installed-source.mjs';
import {accountFixture} from './hubspot-account.fixture.mjs';
import {installedConnectors} from '../../../connectors-builtin/installations.generated.mjs';
import {installedSourceFixtureLifetime} from '../../../host-node/fixtures/installed-source-initialization.mjs';
import {observeOwnScopedStateFds} from '../../../../scripts/fixtures/external-rest/conformance.mjs';

const runtimeUrl = new URL('../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js', import.meta.url);
const base = await readFile(new URL('../../../../spec/local-check-environment.json', import.meta.url), 'utf8');
export const properties = {results: [
  {name: 'amount', type: 'number', fieldType: 'number'},
  {name: 'tags', type: 'enumeration', fieldType: 'checkbox', options: [{value: 'a'}, {value: 'b'}]},
]};
export const expected = {id: '9007199254740993', amount: '9007199254740993.0100000000', tags: ['a', 'b']};
export const objectBody = JSON.stringify({results: [{id: expected.id, archived: false,
  properties: {amount: '9007199254740993.01', tags: 'a;b'}}]});

export async function installedHubSpotFixture(t, {account = 'allow', propertyRead = 'allow'} = {}) {
  // The helper owns loopback TLS and a separate unused credential namespace.
  // The Source below opens its own actual installed Site/journal/binding.
  let closeInitial;const dependentCloses=[];
  const lifetime=installedSourceFixtureLifetime({after(close){closeInitial=close;},diagnostic:(...args)=>t.diagnostic(...args)});
  const f = await accountFixture({after(close){dependentCloses.push(close);},diagnostic:(...args)=>t.diagnostic(...args)}, {accounted: false});
  const site = {version: 'actql-installed-hubspot-site/0.1', apiOrigin: f.scope.resourceOrigin,
    credentialAuthorityId: 'installed-hubspot', credentialKeyId: 'key',
    credentialPrivateKeyPath: join(f.root, 'credential-authority.key'), environment: 'test',
    journalRoot: join(f.root, 'installed-credential-journal'), namespaceId: 'installed-hubspot',
    siteGeneration: 1, siteKey: 'installed-hubspot', tokenEnvironment: 'ACTQL_HUBSPOT_TEST_TOKEN',
    caPath: join(f.root, 'server.crt')};
  const siteProfilePath = join(f.root, 'installed-site.json');
  await writeFile(siteProfilePath, JSON.stringify(site));
  const metadata = {version: 'actql-hubspot-read-metadata/0.1', connectorId: 'hubspot',
    portalId: '7', apiOrigin: site.apiOrigin,
    accountBody: Buffer.from('{"portalId":7,"accountType":"STANDARD"}').toString('base64'),
    objects: [{resource: 'companies', objectType: 'companies',
      propertiesBody: Buffer.from(JSON.stringify(properties)).toString('base64')}]};
  const metadataPath = join(f.root, 'installed-metadata.json');
  await writeFile(metadataPath, JSON.stringify(metadata));
  const policy = canonicalJson({version: 'actql-execution-account-config/0.1', account_id: 'installed',
    entries: [['records', 'companies', 'allow'], ['identity', 'account', account],
      ['schema', 'properties', propertyRead]].sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0).map(([entry_id, resource, outcome]) => ({
      entry_id, outcome, principal: {all: true}, connection: {any_of: ['hubspot:hubspot']},
      resource: {any_of: [resource]}, operation: {any_of: ['read']}, exclusions: []}))});
  // Explicit test units, not adoption of a normal numerical Host profile.
  const profile = {version: 'actql-installed-hubspot-source/0.1', connectorId: 'hubspot', portalId: '7',
    resources: [{resource: 'companies', objectType: 'companies'}], metadataPath, siteProfilePath,
    metadataResources: {account: 'account', properties: 'properties'}, accountConfigurationWire: policy,
    limits: {maxResponseBytes: 4096, maxNodes: 1000, maxDepth: 20, maxProperties: 10,
      maxNameUnits: 100, maxPages: 2, maxRows: 2, maxRequests: 5, perPage: 1,
      maxColumns: 3, maxCursorUnits: 64, maxValueNodes: 100, maxValueTextBytes: 4096,
      maxRowsWireBytes: 4096, maxRowsWireNodes: 100, maxRowsWireDepth: 10,
      maxObjects: 2, maxDeclarationBytes: 4096, maxDeclarationNodes: 1000, maxSecretBytes: 128}};
  const path = join(f.root, 'installed-source.json');
  await writeFile(path, JSON.stringify(profile));
  const sources = [], captures = [];
  t.after(async () => {
    const failures=[];
    try{for(const captured of captures)await captured.close();await closeInitial();}catch(cause){failures.push(cause);}
    for(const close of dependentCloses)try{await close();}catch(cause){failures.push(cause);}
    assert.equal(observeOwnScopedStateFds([f.root]).scopedStateFd0,true);
    if(failures.length)throw new AggregateError(failures,'HubSpotFixtureCleanupUnconfirmed');
  });
  let initialized;
  const runtimeBundleCid='sha256:'+createHash('sha256').update(await readFile(runtimeUrl)).digest('hex');
  const load = async () => {
    initialized??=lifetime.open({root:f.root,moon:common,baseEnvironmentWire:base,runtimeBundleCid,
      installation:installedConnectors.find(value=>value.name==='hubspot')});
    try{
      const source=await loadInstalledSource(path,{root:f.root,principalId:'operator',moon:common,runtimeUrl,
        baseEnvironmentWire:base,resolveSecret:f.options.credential.resolveSecret,
        installationServices:initialized.installationServices});
      sources.push(source);lifetime.sources.push(source);return source;
    }catch(cause){
      const errors=[],pending=[cause],seen=new Set();while(pending.length&&errors.length<8){
        const value=pending.shift();if(!value||typeof value!=='object'||seen.has(value))continue;
        seen.add(value);errors.push({code:value.code,name:value.name,stack:typeof value.stack==='string'?value.stack.split('\n').slice(0,8):undefined});
        pending.push(value.cause,value.primaryFailure);
      }
      t.diagnostic(JSON.stringify({originalInitializationErrors:errors}));throw cause;
    }
  };
  let installedContracts;
  const prepare = async source => {
    const env = JSON.parse(source.environmentWire);
    const environment = common.clientProgramCheckEnvironment(source.environmentWire,
      env.evidence_bundle_cid, false, false, true, false, false, false, false);
    assert.ok(environment);
    const view = env.schema_snapshots.find(value =>
      value.source_ref === source.sourceReadAccesses[0].sourceRef);
    const publication = JSON.stringify({environmentCid: env.evidence_bundle_cid,
      aliases: [{name: 'hubspot.companies', sourceRef: view.source_ref,
        sourceViewContractCid: view.source_view_contract_cid,
        schemaContractCid: view.carrier_schema_contract_cid}]});
    const outcome = common.clientProgramPrepareSourceWithParameters(
      'SELECT id, amount, tags FROM hubspot.companies', 'sql', environment,
      publication, undefined, undefined);
    const program = common.clientProgramPreparationReady(outcome);
    assert.ok(program, inspect(common.clientProgramPreparationIssue(outcome), {depth: 8, maxStringLength: 2000}));
    const repo = new URL('../../../../', import.meta.url);
    const [registryWire, aoa, query, evidence] = await Promise.all([
      readFile(new URL('spec/dependencies/aoa-pipeline-registry.json', repo), 'utf8'),
      readFile(new URL('spec/contracts/actql-aoa.json', repo), 'utf8').then(JSON.parse),
      readFile(new URL('spec/contracts/actql-query-acquisition.json', repo), 'utf8'),
      readFile(new URL('spec/contracts/actql-query-process-evidence.json', repo), 'utf8')]);
    const values=JSON.stringify(aoa.execution_contracts['REL.values']);
    const fragment=JSON.stringify(aoa.execution_contracts['ACTQL.expression_fragment/0.1']);
    const ordered=JSON.stringify(aoa.execution_contracts['REL.derive.ordered']);
    installedContracts??=checked(common.clientPrepareInstalledSequenceContracts(registryWire,values,fragment,ordered));
    return {preparedProgram:program,registry:installedContracts,values,fragment,ordered,query,evidence};
  };
  const ledger = () => checked(common.clientProgramAcquisitionLedger(1, 1, 32768n,
    100000000n, 100000000n, 0));
  const requestBodies = [];
  f.state.onRequest = async (request, response) => {
    if (request.url === '/account-info/v3/details') return false;
    const body = request.url === '/crm/v3/properties/companies' ? JSON.stringify(properties)
      : request.url.startsWith('/crm/v3/objects/companies?') ? objectBody
      : assert.fail(`Unexpected request ${request.url}`);
    requestBodies.push(Buffer.from(body));
    response.writeHead(200, {'content-type': 'application/json'}); response.end(body); return true;
  };
  return {...f, site, siteProfilePath, metadata, metadataPath, profile, path,
    load, prepare, ledger, captures, requestBodies};
}
