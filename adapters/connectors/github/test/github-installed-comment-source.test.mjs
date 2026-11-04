import {ledgerUsageFieldsFor} from '../../../host-node/fixtures/ledger-usage.mjs';
// Installed Source component acceptance with explicit fixture authority and
// reservations. This does not issue a normal Host/business-Run resource profile.
import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {mkdtemp, readFile, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {inspect} from 'node:util';
import test from 'node:test';
import * as common from '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {checked} from '../../../host-common/runtime-result.mjs';
import {canonicalJson} from '../../../host-node/local-account-config.mjs';
import {loadInstalledSource, publishInstalledSourceProfile} from '../../../host-node/installed-source.mjs';
import {openHttpsExchangeFixture} from '../../../site-node/https-exchange-fixture.mjs';
import {INSTALLED_GITHUB_SITE_VERSION, INSTALLED_GITHUB_SOURCE_VERSION} from '../host/installed-github-source.mjs';
import {graphqlRoute} from './github-graphql.fixture.mjs';
import {createInstalledLoaderParent} from '../../../host-node/fixtures/installed-loader-parent.fixture.mjs';

const repo = new URL('../../../../', import.meta.url);
const runtimeUrl = new URL('../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js', import.meta.url);
const read = path => readFile(new URL(path, repo), 'utf8');
const comment = (id, body) => ({id, nodeId: `IC_${id}`, author: null, body,
  createdAt: '2026-10-01T00:00:00Z', updatedAt: '2026-10-02T00:00:00Z'});

function diagnoseOriginalFailure(t, cause) {
  // Report only bounded codes and compiler tags. Inputs, credential material
  // and retained cleanup owners stay with the original failure.
  const pending = [cause], seen = new Set(), codes = [];
  try {
    while (pending.length && seen.size < 12) {
      const value = pending.shift();
      if (value === null || typeof value !== 'object' || seen.has(value)) continue;
      seen.add(value);
      const fields = Object.getOwnPropertyDescriptors(value);
      const constructor = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(value) ?? {}, 'constructor')?.value;
      const code = fields.code?.value, tag = fields.$tag?.value;
      codes.push({constructor: typeof constructor === 'function' ? constructor.name : undefined,
        code: typeof code === 'string' && /^[A-Za-z][A-Za-z0-9_:-]{0,127}$/u.test(code) ? code : undefined,
        tag: Number.isSafeInteger(tag) && tag >= 0 && tag <= 65535 ? tag : undefined});
      if (typeof constructor === 'function' && /RowHostIssue8Physical$/u.test(constructor.name) &&
          Number.isSafeInteger(fields._0?.value) && fields._0.value >= 0 && fields._0.value <= 16) {
        codes.push({ledgerIssue: fields._0.value});
      }
      for (const name of ['primaryFailure', 'cause', '_0', '_1']) {
        if (fields[name] && Object.hasOwn(fields[name], 'value')) pending.push(fields[name].value);
      }
    }
    t.diagnostic(`Original installed GitHub failure codes: ${JSON.stringify(codes)}`);
  } catch { /* Diagnostics never replace the original failure. */ }
}

async function fixture(t, {commentsRead = 'allow'} = {}) {
  const state = {repositories: new Map([['R_original', {databaseId: 1296269,
    nameWithOwner: 'octo/hello', issues: [{number: 7, id: 'I_original',
      commentRows: [comment('9007199254740993', ' é\n')]}],
    pullRequests: [{number: 8, id: 'PR_original',
      commentRows: [comment('9223372036854775807', '')]}]}]]),
    names: new Map([['octo/hello', 'R_original']]), pageSize: 1, commentPageSize: 1};
  const api = await openHttpsExchangeFixture(t, {routes: [graphqlRoute(() => state)]});
  const root = await mkdtemp(join(tmpdir(), 'actql-github-installed-comments-'));
  const authority = generateKeyPairSync('ed25519');
  const credentialPrivateKeyPath = join(root, 'credential.key');
  await writeFile(credentialPrivateKeyPath, authority.privateKey.export({type: 'pkcs8', format: 'pem'}), {mode: 0o600});
  const sitePath = join(root, 'site.json');
  await writeFile(sitePath, JSON.stringify({version: INSTALLED_GITHUB_SITE_VERSION,
    apiOrigin: api.origin, owner: 'octo', repo: 'hello', namespaceId: 'comments-fixture',
    environment: 'test', siteKey: 'comments-site', siteGeneration: 1,
    credentialAuthorityId: 'comments-authority', credentialKeyId: 'comments-key',
    credentialPrivateKeyPath, journalRoot: join(root, 'credential-journal'),
    tokenEnvironment: 'ACTQL_TEST_GITHUB_TOKEN', caPath: api.caPath}));
  const connection = `github:${new URL(api.origin).host}/octo/hello`;
  const profilePath = join(root, 'source.json');
  await writeFile(profilePath, canonicalJson({version: INSTALLED_GITHUB_SOURCE_VERSION,
    siteProfilePath: sitePath, publicationPath: join(root, 'publication.json'),
    connectorId: 'gh-original', accountConfigurationWire: canonicalJson({
      version: 'actql-execution-account-config/0.1', account_id: 'comments-account',
      entries: [['comments', 'issue_comments', commentsRead], ['publication', 'issues', 'allow']]
        .map(([entry_id, resource, outcome]) => ({entry_id, outcome, exclusions: [],
          principal: {all: true}, connection: {any_of: [connection]},
          resource: {any_of: [resource]}, operation: {any_of: ['read']}}))})}));
  let resolutions = 0;
  const resolveSecret = async () => {resolutions++; return 'test-only-token';};
  const options = {root: join(root, 'host'), principalId: 'operator', moon: common,
    runtimeUrl, resolveSecret};
  const sources = [], captures = [], loaderParents = [];
  t.after(async () => {
    const failures = [];
    for (const capture of captures) try {await capture.close();} catch (cause) {failures.push(cause);}
    for (const source of sources) try {await source.close();} catch (cause) {failures.push(cause);}
    for (const parent of loaderParents) try {await parent.close();} catch (cause) {failures.push(cause);}
    await writeFile(join(root, 'original-exchanges.json'), JSON.stringify(api.seen()), {mode: 0o600});
    t.diagnostic(`Retained installed GitHub comments fixture: ${root}`);
    if (failures.length) throw new AggregateError(failures, 'GitHubCommentsFixtureCleanupPending');
  });
  const publication = await publishInstalledSourceProfile(profilePath, options);
  const load = async () => {
    const parent = createInstalledLoaderParent({root: options.root,
      principalId: options.principalId, moon: options.moon});
    loaderParents.push(parent);parent.open();
    try {
      const source = await parent.load(loadInstalledSource, profilePath, {...options,
        baseEnvironmentWire: await read('spec/local-check-environment.json')});
      sources.push(source);return source;
    } catch (cause) {
      diagnoseOriginalFailure(t, cause);
      throw cause;
    }
  };
  // Match the installed Host boundary: interpret these fixed contracts once,
  // then reuse the same Common-issued original for each Program preparation.
  const aoa = JSON.parse(await read('spec/contracts/actql-aoa.json'));
  const values = JSON.stringify(aoa.execution_contracts['REL.values']);
  const fragment = JSON.stringify(aoa.execution_contracts['ACTQL.expression_fragment/0.1']);
  const ordered = JSON.stringify(aoa.execution_contracts['REL.derive.ordered']);
  const registry = checked(common.clientPrepareInstalledSequenceContracts(
    await read('spec/dependencies/aoa-pipeline-registry.json'), values, fragment, ordered));
  const prepare = async source => {
    const environment = JSON.parse(source.environmentWire);
    const checkedEnvironment = common.clientProgramCheckEnvironment(source.environmentWire,
      environment.evidence_bundle_cid, false, false, true, false, false, false, false);
    assert.ok(checkedEnvironment);
    const preparation = common.clientProgramPrepareEffectFreeWithParameters(JSON.stringify({
      version: 'actql/0.1', id: 'installed-comments', stages: [{id: 'scan',
        inputs: {remote: {connector: 'gh-original', resource: 'issue_comments'}},
        steps: [{filter: 'id > 0', as: 'positive_comment_ids'},
          {select: ['id', 'subject_number', 'author', 'body'], as: 'comments'},
          {from: 'comments', assert_rows: {unique_by: ['id']}, as: 'unique_comments'},
          {from: 'unique_comments', sort: [{id: 'asc'}], as: 'ordered_comments'}],
        results: {r: {from: 'ordered_comments', fields: ['id', 'subject_number', 'author', 'body']}}}],
      results: {comments: {from: {stage: 'scan', result: 'r'}}}}), 'json', checkedEnvironment, undefined);
    const preparedProgram = common.clientProgramPreparationReady(preparation);
    assert.ok(preparedProgram, inspect(common.clientProgramPreparationIssue(preparation), {depth: 8}));
    return {preparedProgram, registry, values, fragment, ordered};
  };
  // Explicit test allocations only, with the same original debt owner. Use
  // the existing Local retained/execution policy (resource_policy.mbt), not
  // the retired 100 MB fixture envelope that omitted the managed Reader.
  const ledger = () => checked(common.clientProgramAcquisitionLedger(1, 1,
    100000000n, 536870912n, 536870912n, 0));
  const prepareSource = async (source, inputs) => {
    try { return await source.prepare(inputs); }
    catch (cause) {
      t.diagnostic(`Original installed Source preparation cause: ${inspect(cause.cause, {depth: 10})}`);
      throw cause;
    }
  };
  return {root, state, api, publication, load, prepare, prepareSource, ledger, captures,
    resolutions: () => resolutions};
}

const released = ledger => assert.deepEqual(
  ledgerUsageFieldsFor(common.clientProgramMultiCapturedLedgerUsage(ledger), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]), [0n, 0n, 0n, 0n]);

test('installed GitHub comments retain their declared contracts through the original accounted Source capture', async t => {
  const f = await fixture(t), source = await f.load();
  assert.equal(source.connectorRegistration, 'github');
  assert.ok(source.sourceReadAccesses.some(value => value.resource === 'issue_comments'));
  const before = f.api.seen().length;
  const inputs = await f.prepare(source);
  const nextInputs = await f.prepare(source);
  assert.notStrictEqual(nextInputs.preparedProgram, inputs.preparedProgram);
  assert.strictEqual(nextInputs.registry, inputs.registry,
    'distinct Program preparations borrow the same installed contract original');
  const preparedSource = await f.prepareSource(source, inputs);
  assert.equal(f.api.seen().length, before, 'preparation performs no provider lookup');
  const ledger = f.ledger();
  const opened = await source.openCapture({...inputs, preparedSource, ledger}).catch(cause => {
    diagnoseOriginalFailure(t, cause); throw cause;
  });f.captures.push(opened);
  const exported = checked(common.clientProgramExportSourceCapture(opened.capture.source(),
    opened.requirement, 'installed-github-comments'));
  assert.deepEqual(common.clientProgramSourceCaptureExportRows(exported).map(JSON.parse), [
    {id: '9007199254740993', subject_number: '7', author: null, body: ' é\n'},
    {id: '9223372036854775807', subject_number: '8', author: null, body: ''}]);
  const requests = f.api.seen().slice(before).map(value => JSON.parse(value.body));
  assert.deepEqual(requests.map(value => value.variables.id),
    ['R_original', 'I_original', 'R_original', 'PR_original']);
  await opened.close();released(ledger);
});

test('installed GitHub comments do not inherit the publication Issue read permission', async t => {
  const f = await fixture(t, {commentsRead: 'deny'}), source = await f.load();
  const before = f.api.seen().length, resolutions = f.resolutions();
  await assert.rejects(f.prepareSource(source, await f.prepare(source)), {code: 'ACTQL_E_ACCOUNT_DENIED'});
  assert.equal(f.api.seen().length, before);
  assert.equal(f.resolutions(), resolutions);
});
