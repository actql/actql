import assert from 'node:assert/strict';
import {generateKeyPairSync,createHash} from 'node:crypto';
import {mkdir, mkdtemp, readFile, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {inspect} from 'node:util';
import * as common from '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {checked} from '../../../host-common/runtime-result.mjs';
import {canonicalJson} from '../../../host-node/local-account-config.mjs';
import {loadInstalledSource} from '../../../host-node/installed-source.mjs';
import {openHttpsExchangeFixture} from '../../../site-node/https-exchange-fixture.mjs';
import {installedConnectors} from '../../../connectors-builtin/installations.generated.mjs';
import {installedSourceFixtureLifetime} from '../../../host-node/fixtures/installed-source-initialization.mjs';
import {observeOwnScopedStateFds} from '../../../../scripts/fixtures/external-rest/conformance.mjs';

const repo = new URL('../../../../', import.meta.url);
const runtimeUrl = new URL('../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js', import.meta.url);
export const originalForm = {revision: '7', properties: {
  Subject: {code: 'Subject', type: 'SINGLE_LINE_TEXT'},
  Tags: {code: 'Tags', type: 'MULTI_SELECT', options: {
    red: {label: 'red', index: '0'}, 東京: {label: '東京', index: '1'}}},
  RecordNumber: {code: 'RecordNumber', type: 'RECORD_NUMBER'},
}};
export const record = (id, label = 'APP-7') => ({$id: {type: '__ID__', value: id},
  $revision: {type: '__REVISION__', value: '9'},
  Subject: {type: 'SINGLE_LINE_TEXT', value: '東京\r\nnext'},
  Tags: {type: 'MULTI_SELECT', value: ['red', '東京', 'red']},
  RecordNumber: {type: 'RECORD_NUMBER', value: label}});

export async function installedKintoneFixture(t, {formRead = 'allow', recordsRead = 'allow',
  guestSpaceId, faults = []} = {}) {
  let closeInitial;
  const lifetime=installedSourceFixtureLifetime({
    after(close){assert.equal(closeInitial,undefined);closeInitial=close;},
    diagnostic:(...args)=>t.diagnostic(...args),
  });
  const parent = new URL('../../../../_build/kintone-record-fixtures/', import.meta.url);
  await mkdir(parent, {recursive: true});
  const root = await mkdtemp(join(parent.pathname, 'read-'));
  const prefix = guestSpaceId === undefined ? '/k/v1/' : `/k/guest/${guestSpaceId}/v1/`;
  const state = {secret: 'kintone-test-api-token', resolutions: 0,
    forms: 0, pages: 0, responseBodies: [], resolve: undefined,
    form: undefined, page: undefined, fixtureFailures: []};
  const serve = async (exchange, kind) => {
    try {
      assert.equal(exchange.method, 'POST');
      assert.equal(exchange.headers['x-http-method-override'], 'GET');
      assert.equal(exchange.authorized, true);
      const parameters = JSON.parse(exchange.body);
      assert.equal(parameters.app, '12');
      let body;
      if (kind === 'form') {
        state.forms++;
        assert.deepEqual(parameters, {app: '12'});
        body = await state.form?.(state.forms, exchange) ?? originalForm;
      } else {
        state.pages++;
        // The original checked carrier orders its field map canonically. Keep
        // this independent literal projection, not an expectation generated
        // from the driver or copied from the observed request.
        assert.deepEqual(parameters.fields, ['$id', '$revision', 'RecordNumber', 'Subject', 'Tags']);
        assert.equal(parameters.query, state.pages === 1 ? 'order by $id asc limit 2'
          : '$id > 9007199254740993 order by $id asc limit 2');
        body = await state.page?.(state.pages, exchange) ?? {records: state.pages === 1
          ? [record('9007199254740992'), record('9007199254740993', 'APP-8')]
          : [record('9007199254740994', 'APP-9')], totalCount: '999999'};
      }
      state.responseBodies.push(Buffer.from(JSON.stringify(body)));
      return {body};
    } catch (cause) {
      // Private original harness evidence only. The HTTP fixture still loses
      // this response and the product still observes its original transport
      // failure; the assertion and request are not rewritten or retried.
      state.fixtureFailures.push({kind, method: exchange.method, path: exchange.path,
        requestBody: exchange.body, code: cause.code, message: cause.message,
        actual: cause.actual, expected: cause.expected});
      throw cause;
    }
  };
  const tls = await openHttpsExchangeFixture(lifetime.transportContext, {faults,
    routes: [{method: 'POST', pathname: prefix + 'app/form/fields.json',
      handle: exchange => serve(exchange, 'form')},
    {method: 'POST', pathname: prefix + 'records.json', handle: exchange => serve(exchange, 'page')}]});
  const authority = generateKeyPairSync('ed25519');
  const credentialPrivateKeyPath = join(root, 'credential-authority.key');
  await writeFile(credentialPrivateKeyPath, authority.privateKey.export({format: 'pem', type: 'pkcs8'}), {mode: 0o600});
  const site = {version: 'actql-installed-kintone-site/0.1', apiOrigin: tls.origin,
    credentialAuthorityId: 'kintone-fixture', credentialKeyId: 'key', credentialPrivateKeyPath,
    environment: 'test', journalRoot: join(root, 'credential-journal'), namespaceId: 'kintone-fixture',
    siteGeneration: 1, siteKey: 'kintone-test', tokenEnvironment: 'ACTQL_KINTONE_FIXTURE_TOKEN',
    caPath: tls.caPath, ...(guestSpaceId === undefined ? {} : {guestSpaceId})};
  const sitePath = join(root, 'site.json');
  await writeFile(sitePath, JSON.stringify(site));
  const metadata = {version: 'actql-kintone-record-metadata/0.1', connectorId: 'kintone',
    appId: '12', apiOrigin: tls.origin, formBody: Buffer.from(JSON.stringify(originalForm)).toString('base64')};
  const metadataPath = join(root, 'metadata.json');
  await writeFile(metadataPath, JSON.stringify(metadata));
  const policy = canonicalJson({version: 'actql-execution-account-config/0.1', account_id: 'kintone-fixture',
    entries: [['form', 'form', formRead], ['records', 'inquiries', recordsRead]]
      .map(([entry_id, resource, outcome]) => ({entry_id, outcome, principal: {all: true},
        connection: {any_of: ['kintone:kintone']}, resource: {any_of: [resource]},
        operation: {any_of: ['read']}, exclusions: []}))});
  // Explicit test reservation/decoder units, not a normal funding profile.
  const profile = {version: 'actql-installed-kintone-source/0.1', connectorId: 'kintone', appId: '12',
    resource: 'inquiries', formResource: 'form', fieldCodes: ['Subject', 'Tags', 'RecordNumber'],
    metadataPath, siteProfilePath: sitePath, accountConfigurationWire: policy,
    limits: {maxResponseBytes: 8192, maxNodes: 2000, maxDepth: 20, maxFields: 16, maxNameUnits: 512,
      maxColumns: 8, maxCells: 64, maxTableRows: 16, maxValueNodes: 1000, maxValueDepth: 16,
      maxValueTextBytes: 8192, maxContractPairs: 100, maxRequestBytes: 4096, maxRequests: 6,
      maxPages: 2, perPage: 2, maxSecretBytes: 128, maxRows: 4,
      maxDeclarationBytes: 200000, maxDeclarationNodes: 20000}};
  const path = join(root, 'source.json');
  await writeFile(path, JSON.stringify(profile));
  const sources = [], captures = [];
  t.after(async () => {
    const failures = [];
    for (const captured of captures) try {await captured.close();} catch (cause) {failures.push(cause);}
    try{await closeInitial();}catch(cause){failures.push(cause);}
    await writeFile(join(root, 'original-fixture-observations.json'), JSON.stringify({
      source: 'Fresh own namespace; original requests and assertions unchanged',
      exchanges: tls.seen(), fixtureFailures: state.fixtureFailures}, null, 2) + '\n', {mode: 0o600});
    t.diagnostic(`Retained owned kintone fixture: ${root}`);
    assert.equal(observeOwnScopedStateFds([root]).scopedStateFd0,true);
    if (failures.length) throw new AggregateError(failures, 'KintoneFixtureCleanupUnconfirmed');
  });
  const resolveSecret = async () => {
    state.resolutions++;
    await state.resolve?.();
    return state.secret;
  };
  let initialized;
  const baseEnvironmentWire=await readFile(new URL('spec/local-check-environment.json',repo),'utf8');
  const runtimeBundleCid='sha256:'+createHash('sha256').update(await readFile(runtimeUrl)).digest('hex');
  const load = async (moon = common) => {
    initialized??=lifetime.open({root,moon,baseEnvironmentWire,runtimeBundleCid,
      installation:installedConnectors.find(entry=>entry.name==='kintone')});
    try{
      const source = await loadInstalledSource(path, {root, principalId: 'operator', moon, runtimeUrl,
        baseEnvironmentWire,resolveSecret,installationServices:initialized.installationServices});
      sources.push(source);lifetime.sources.push(source);return source;
    }catch(cause){
      const pending=[cause],seen=new Set(),errors=[];
      while(pending.length&&errors.length<8){
        const value=pending.shift();if(!value||typeof value!=='object'||seen.has(value))continue;
        seen.add(value);errors.push({name:value.name,code:value.code,
          stack:typeof value.stack==='string'?value.stack.split('\n').slice(0,8):undefined});
        pending.push(value.cause,value.primaryFailure);
      }
      t.diagnostic(JSON.stringify({originalInitializationErrors:errors}));throw cause;
    }
  };
  let installedContracts;
  const prepare = async source => {
    const env = JSON.parse(source.environmentWire);
    const checkedEnvironment = common.clientProgramCheckEnvironment(source.environmentWire,
      env.evidence_bundle_cid, false, false, true, false, false, false, false);
    assert.ok(checkedEnvironment);
    const outcome = common.clientProgramPrepareEffectFreeWithParameters(JSON.stringify({
      version: 'actql/0.1', id: 'kintone-installed-source', stages: [{id: 'scan',
        inputs: {remote: {connector: 'kintone', resource: 'inquiries', view: 'records'}},
        steps: [{filter: "Subject <> ''", as: 'filtered'},
          {select: ['$id', 'Subject', 'Tags', 'RecordNumber'], as: 'captured'},
          {from: 'captured', assert_rows: {unique_by: ['$id']}, as: 'unique_records'},
          {from: 'unique_records', sort: [{$id: 'asc'}], as: 'ordered_records'}],
        results: {r: {from: 'ordered_records', fields: ['$id', 'Subject', 'Tags', 'RecordNumber']}}}],
      results: {records: {from: {stage: 'scan', result: 'r'}}}}), 'json', checkedEnvironment, undefined);
    const program = common.clientProgramPreparationReady(outcome);
    assert.ok(program, inspect(common.clientProgramPreparationIssue(outcome), {depth: 8}));
    const [registryWire, aoa, query, evidence] = await Promise.all([
      readFile(new URL('spec/dependencies/aoa-pipeline-registry.json', repo), 'utf8'),
      readFile(new URL('spec/contracts/actql-aoa.json', repo), 'utf8').then(JSON.parse),
      readFile(new URL('spec/contracts/actql-query-acquisition.json', repo), 'utf8'),
      readFile(new URL('spec/contracts/actql-query-process-evidence.json', repo), 'utf8')]);
    const values=JSON.stringify(aoa.execution_contracts['REL.values']);
    const fragment=JSON.stringify(aoa.execution_contracts['ACTQL.expression_fragment/0.1']);
    const ordered=JSON.stringify(aoa.execution_contracts['REL.derive.ordered']);
    installedContracts??=checked(common.clientPrepareInstalledSequenceContracts(registryWire,values,fragment,ordered));
    // The standalone prefix component consumes the same nominal installed
    // sequence contract, never its old wire in a typed Core slot.
    return {preparedProgram:program,registry:installedContracts,values,fragment,ordered,query,evidence};
  };
  const ledger = () => checked(common.clientProgramAcquisitionLedger(1, 1, 65536n,
    100000000n, 100000000n, 0));
  return {root, tls, state, site, sitePath, metadata, metadataPath, profile, path,
    sources, captures, load, prepare, ledger, resolveSecret};
}
