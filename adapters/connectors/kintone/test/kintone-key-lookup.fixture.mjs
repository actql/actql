import {ledgerUsageFieldsFor} from '../../../host-node/fixtures/ledger-usage.mjs';
// Component assembly only: real Account, Credential Site, SQLite and Common
// RowRun with one fresh loopback service. This is no installed Effect claim.
import assert from 'node:assert/strict';
import {createHash, generateKeyPairSync} from 'node:crypto';
import {mkdir, mkdtemp, readFile, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import * as common from '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {checked} from '../../../host-common/runtime-result.mjs';
import {canonicalJson, createLocalAuthorizationGate} from '../../../host-node/local-account-config.mjs';
import {openRowSourceCredentialSite} from '../../../host-node/installed-row-source.mjs';
import {openHttpsCredentialBinding, closeHttpsCredentialBinding} from '../../../site-node/https-credential-resource.mjs';
import {openHttpsExchangeFixture} from '../../../site-node/https-exchange-fixture.mjs';
import {KINTONE_FORM_READ_OPERATION} from '../site/kintone-record-read.mjs';
import {readRawKintoneKeyLookup} from '../site/kintone-key-lookup.mjs';
import {accountedKintoneResponses} from './kintone-accounted-response.fixture.mjs';
import {originalForm, record} from './installed-kintone.fixture.mjs';

const bytes = value => Buffer.from(JSON.stringify(value));
const cid = value => 'sha256:' + createHash('sha256').update(value).digest('hex');
export const lookupForm = Object.freeze({...originalForm, properties: {...originalForm.properties,
  ExternalKey: {code: 'ExternalKey', type: 'SINGLE_LINE_TEXT', unique: true, required: true}}});
export const lookupRecord = (id = '9007199254740993') => ({...record(id),
  ExternalKey: {type: 'SINGLE_LINE_TEXT', value: 'original-key'}});
const fields = ['RecordNumber', 'Subject', 'Tags'];
const limits = Object.freeze({maxResponseBytes: 8192, maxRequestBytes: 4096,
  maxNodes: 2000, maxDepth: 20, maxFields: 16, maxNameUnits: 512, maxRows: 2,
  maxColumns: 8, maxCells: 64, maxTableRows: 16, maxComparisonWork: 10000});

export async function lookupFixture(t, {faults = []} = {}) {
  const parent = new URL('../../../../_build/kintone-lookup-fixtures/', import.meta.url);
  await mkdir(parent, {recursive: true});
  const root = await mkdtemp(join(parent.pathname, 'lookup-'));
  const state = {secret: 'original-test-kintone-token', resolutions: 0, forms: 0,
    targets: 0, charges: 0, consumed: 0, active: false, closing: false,
    fixtureFailures: [], form: undefined, records: undefined,
    resolve: undefined, current: undefined, afterCharge: undefined};
  const tls = await openHttpsExchangeFixture(t, {faults, routes: [
    {method: 'POST', pathname: '/k/v1/app/form/fields.json', handle: exchange => serve(exchange, 'form')},
    {method: 'POST', pathname: '/k/v1/records.json', handle: exchange => serve(exchange, 'target')},
  ]});
  async function serve(exchange, kind) {
    try {
      assert.equal(exchange.authorized, true);
      const body = JSON.parse(exchange.body);
      if (kind === 'form') {
        state.forms++;
        assert.equal(exchange.headers['x-http-method-override'], 'GET');
        assert.deepEqual(body, {app: '12'});
        return await state.form?.() ?? {body: lookupForm};
      }
      if (kind === 'target') {
        state.targets++;
        assert.equal(exchange.headers['x-http-method-override'], 'GET');
        assert.deepEqual(body, {app: '12', fields: ['$id', '$revision', ...fields, 'ExternalKey'],
          query: 'ExternalKey = "original-key" limit 2', totalCount: true});
        return await state.records?.() ?? {body: {records: [lookupRecord()], totalCount: '1'}};
      }
      throw new Error('UnexpectedKintoneLookupRoute');
    } catch (cause) {
      state.fixtureFailures.push({kind, code: cause.code, message: cause.message,
        actual: cause.actual, expected: cause.expected});
      throw cause;
    }
  }
  let site, binding, row;
  t.after(async () => {
    const failures = [];
    try { if (binding) assert.equal(closeHttpsCredentialBinding(binding), 'closed'); }
    catch (cause) {failures.push(cause);}
    try { row?.close(); if (row) assert.deepEqual(ledgerUsageFieldsFor(row.usage(), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]), [0n, 0n, 0n, 0n]); }
    catch (cause) {failures.push(cause);}
    try {site?.close();} catch (cause) {failures.push(cause);}
    await writeFile(join(root, 'original-observations.json'), JSON.stringify({
      tlsCertificatePath: tls.caPath, exchanges: tls.seen(), fixtureFailures: state.fixtureFailures,
      charges: state.charges, consumed: state.consumed}, null, 2) + '\n', {mode: 0o600});
    t.diagnostic(`Retained owned kintone lookup fixture: ${root}`);
    if (failures.length) throw new AggregateError(failures, 'KintoneLookupFixtureCleanupUnconfirmed');
  });
  const key = generateKeyPairSync('ed25519');
  const keyPath = join(root, 'credential-authority.key');
  await writeFile(keyPath, key.privateKey.export({format: 'pem', type: 'pkcs8'}), {mode: 0o600});
  const accountPath = join(root, 'account.json');
  const writeAccount = (outcome = 'allow') => writeFile(accountPath, canonicalJson({
    version: 'actql-execution-account-config/0.1', account_id: 'kintone-lookup-fixture',
    entries: [{entry_id: 'a-reads', outcome, principal: {all: true},
      connection: {any_of: ['kintone:fixture']}, resource: {any_of: ['form', 'inquiries']},
      operation: {any_of: ['read']}, exclusions: []},
    {entry_id: 'b-effect', outcome: 'deny', principal: {all: true}, connection: {any_of: ['kintone:fixture']},
      resource: {any_of: ['inquiries']}, operation: {any_of: ['effect']}, exclusions: []}]}));
  await writeAccount();
  const context = Object.freeze({principal: 'operator', contextCid: cid(root + '/account')});
  const gate = await createLocalAuthorizationGate({accountConfig: accountPath, principal: 'operator', context});
  const issued = new WeakSet();
  const authorization = Object.freeze({...gate, context, issued: decision => issued.has(decision),
    authorize: async (...args) => {const decision = await gate.authorize(...args); issued.add(decision); return decision;}});
  const subjectCid = cid(root + '/original-lookup-subject');
  const runInvocationCid = cid(root + '/original-invocation');
  const dispatchRequestCid = cid(root + '/original-dispatch');
  const decisionFor = operation => authorization.authorize('acquisition', {
    connection: 'kintone:fixture', resource: operation === KINTONE_FORM_READ_OPERATION ? 'form' : 'inquiries',
    operation: 'read'}, {subjectCid});
  const current = async operation => {
    if (state.closing || !site.referenceCurrent()) throw Object.assign(new Error('OriginalAcquisitionRetiring'),
      {code: 'OriginalAcquisitionRetiring'});
    await state.current?.(operation);
    const decision = await decisionFor(operation);
    if (decision.action !== 'dispatch') throw Object.assign(new Error('ExecutionAuthorizationDenied'),
      {code: 'ExecutionAuthorizationDenied', decision});
    if (state.closing || !site.referenceCurrent()) throw Object.assign(new Error('OriginalAcquisitionRetiring'),
      {code: 'OriginalAcquisitionRetiring'});
  };
  site = await openRowSourceCredentialSite({profile: {credentialPrivateKeyPath: keyPath,
    credentialAuthorityId: 'kintone-lookup-fixture', credentialKeyId: 'key',
    journalRoot: join(root, 'credential-journal'), resourceOrigin: tls.origin,
    namespaceId: 'kintone-fixture', environment: 'test', siteKey: 'original-site', siteGeneration: 1},
    principalId: 'operator', authorization, connection: 'kintone:fixture', connectorRegistration: 'kintone',
    connectorRevision: 'kintone/0.1', runtimeBundleCid: cid(await readFile(new URL(
      '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js', import.meta.url))),
    commonMoon: common, ca: tls.ca, admitsApprovalTarget: () => false,
    resolveSecret: async () => {state.resolutions++; await state.resolve?.(); return state.secret;}});
  const grants = new Map();
  const authorizationFor = async ({operation, index = 0}) => {
    let grant = grants.get(operation);
    if (!grant) {
      const decision = await decisionFor(operation);
      grant = site.issueReadGrant({operation, decision,
        resource: operation === KINTONE_FORM_READ_OPERATION ? 'form' : 'inquiries',
        runInvocationCid, dispatchRequestCid, maxUses: operation === KINTONE_FORM_READ_OPERATION ? 2 : 1,
        subjectCid});
      grants.set(operation, grant);
    }
    return Object.freeze({...grant, useId: operation + '/original/' + index});
  };
  const initialAuthorization = await authorizationFor({operation: KINTONE_FORM_READ_OPERATION});
  binding = openHttpsCredentialBinding({...site.credential, scope: initialAuthorization.scope,
    maxSecretBytes: 128, secretPresentation: 'kintone-api-token'});
  const formLimits = common.clientProgramKintoneFormLimits(8192, 2000, 20, 16, 512);
  const catalog = checked(common.clientProgramKintoneProjectForm(bytes(lookupForm), '12', formLimits));
  const request = checked(common.clientProgramKintoneLookupRequest(catalog, 'ExternalKey', 'original-key', fields,
    common.clientProgramKintoneLookupLimits(512, 8, 10000, 4096, 2000, 20)));
  row = await accountedKintoneResponses(catalog, () => !state.active && closeHttpsCredentialBinding(binding) === 'closed',
    {fields, programId: 'kintone-lookup-response-custody'});
  const options = {moon: common, originalAppId: '12', request, initialAuthorization,
    credential: Object.freeze({...site.credential, binding}), limits, authorizationFor, current,
    chargeResponse: body => {state.charges++; const charge = row.charge(body); state.afterCharge?.(); return charge;},
    consumeObservation: charge => {state.consumed++; row.consume(charge);}, callResource: site.callResource};
  const send = async (overrides = {}) => {
    assert.equal(state.active, false); state.active = true;
    try {return await readRawKintoneKeyLookup({...options, ...overrides});} finally {state.active = false;}
  };
  return {root, tls, state, site, binding, row, options, common, request, send, writeAccount,
    closeRoot: () => {state.closing = true; return row.close();},
    journal: site.credential.journal, authorizationFor};
}
