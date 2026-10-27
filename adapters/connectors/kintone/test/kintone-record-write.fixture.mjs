import {ledgerUsageFieldsFor} from '../../../host-node/fixtures/ledger-usage.mjs';
// Component assembly only: real Account, Credential Site, SQLite and Common
// RowRun with one fresh loopback service. This is no installed Effect claim.
import assert from 'node:assert/strict';
import {createHash, generateKeyPairSync} from 'node:crypto';
import {mkdir, mkdtemp, readFile, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
// The physical component must bind the bytes of the same loaded runtime.
const commonRuntime = process.env.ACTQL_TEST_KINTONE_COMMON_RUNTIME_URL ??
  new URL('../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js', import.meta.url).href;
const common = await import(commonRuntime);
import {checked} from '../../../host-common/runtime-result.mjs';
import {runtimePair} from '../../../host-common/compiler-binding.generated.mjs';
import {canonicalJson, createLocalAuthorizationGate} from '../../../host-node/local-account-config.mjs';
import {openRowSourceCredentialSite} from '../../../host-node/installed-row-source.mjs';
import {openHttpsCredentialBinding, closeHttpsCredentialBinding} from '../../../site-node/https-credential-resource.mjs';
import {openHttpsExchangeFixture} from '../../../site-node/https-exchange-fixture.mjs';
import {KINTONE_FORM_READ_OPERATION} from '../site/kintone-record-read.mjs';
import {KINTONE_TARGET_READ_OPERATION} from '../site/kintone-record-delete.mjs';
import {sendRawKintoneWrite, KINTONE_RECORD_CREATE_OPERATION, KINTONE_RECORD_UPDATE_OPERATION} from '../site/kintone-record-write.mjs';
import {accountedKintoneResponses} from './kintone-accounted-response.fixture.mjs';
import {originalForm as readForm, record} from './installed-kintone.fixture.mjs';

// A manual Text setting is original write evidence, not a default inferred
// from the readable field type. Keep the shared read-only fixture unchanged.
const originalForm = {...readForm, properties: {...readForm.properties,
  Subject: {...readForm.properties.Subject, expression: ''}}};

const repo = new URL('../../../../', import.meta.url);
const read = name => readFile(new URL(name, repo), 'utf8');
const bytes = value => Buffer.from(JSON.stringify(value));
const cid = value => 'sha256:' + createHash('sha256').update(value).digest('hex');
const ids = ['9007199254740992', '9007199254740993'];
const fields = ['RecordNumber', 'Subject', 'Tags'];
const limits = Object.freeze({maxResponseBytes: 8192, maxRequestBytes: 4096,
  maxNodes: 2000, maxDepth: 20, maxFields: 16, maxNameUnits: 512, maxRows: 2,
  maxColumns: 8, maxCells: 64, maxTableRows: 16, maxComparisonWork: 10000, maxIdentityBytes: 10000});


export async function writeFixture(t, {kind = 'update', guestSpaceId, effect = 'allow', faults = [],
  formDocument = originalForm} = {}) {
  const parent = new URL('../../../../_build/kintone-write-fixtures/', import.meta.url);
  await mkdir(parent, {recursive: true});
  const root = await mkdtemp(join(parent.pathname, kind + '-'));
  const state = {secret: 'original-test-kintone-token', resolutions: 0, forms: 0,
    targets: 0, writes: 0, charges: 0, consumed: 0, active: false, closing: false,
    fixtureFailures: [], form: undefined, records: undefined, reply: undefined,
    resolve: undefined, current: undefined, afterCharge: undefined};
  const prefix = guestSpaceId === undefined ? '/k/v1/' : `/k/guest/${guestSpaceId}/v1/`;
  const operation = kind === 'create' ? KINTONE_RECORD_CREATE_OPERATION : KINTONE_RECORD_UPDATE_OPERATION;
  const tls = await openHttpsExchangeFixture(t, {faults, routes: [
    {method: 'POST', pathname: prefix + 'app/form/fields.json', handle: exchange => serve(exchange, 'form')},
    {method: 'POST', pathname: prefix + 'records.json', handle: exchange => serve(exchange,
      exchange.headers['x-http-method-override'] === 'GET' ? 'target' : 'create')},
    {method: 'PUT', pathname: prefix + 'records.json', handle: exchange => serve(exchange, 'update')},
  ]});
  async function serve(exchange, kind) {
    try {
      assert.equal(exchange.authorized, true);
      const body = JSON.parse(exchange.body);
      if (kind === 'form') {
        state.forms++;
        assert.equal(exchange.headers['x-http-method-override'], 'GET');
        assert.deepEqual(body, {app: '12'});
        return {body: await state.form?.() ?? formDocument};
      }
      if (kind === 'target') {
        state.targets++;
        assert.equal(exchange.headers['x-http-method-override'], 'GET');
        assert.deepEqual(body, {app: '12', fields: ['$id', '$revision', ...fields],
          query: '$id in (9007199254740992,9007199254740993) order by $id asc limit 2'});
        return {body: await state.records?.() ?? {records: ids.map(id => record(id)), totalCount: null}};
      }
      state.writes++;
      assert.equal(exchange.headers['x-http-method-override'], undefined);
      if (kind === 'create') {
        assert.equal(exchange.method, 'POST');
        assert.deepEqual(body, {app: '12', records: [
          {Subject: {value: 'next 東京'}, Tags: {value: ['東京', 'red', '東京']}},
          {Subject: {value: 'next 東京'}, Tags: {value: ['東京', 'red', '東京']}},
        ]});
        return await state.reply?.() ?? {body: {ids: ['9007199254740994', '9007199254740995'], revisions: ['1', '1']}};
      }
      assert.equal(exchange.method, 'PUT');
      assert.deepEqual(body, {app: '12', upsert: false, records: ids.map(id => ({id, revision: '9',
        record: {Subject: {value: 'next 東京'}, Tags: {value: ['東京', 'red', '東京']}}}))});
      return await state.reply?.() ?? {body: {records: ids.map(id => ({id, revision: '10'}))}};
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
    t.diagnostic(`Retained owned kintone write fixture: ${root}`);
    if (failures.length) throw new AggregateError(failures, 'KintoneWriteFixtureCleanupUnconfirmed');
  });
  const key = generateKeyPairSync('ed25519');
  const keyPath = join(root, 'credential-authority.key');
  await writeFile(keyPath, key.privateKey.export({format: 'pem', type: 'pkcs8'}), {mode: 0o600});
  const accountPath = join(root, 'account.json');
  const writeAccount = (outcome = effect) => writeFile(accountPath, canonicalJson({
    version: 'actql-execution-account-config/0.1', account_id: 'kintone-write-fixture',
    entries: [{entry_id: 'a-reads', outcome: 'allow', principal: {all: true},
      connection: {any_of: ['kintone:fixture']}, resource: {any_of: ['form', 'inquiries']},
      operation: {any_of: ['read']}, exclusions: []},
    {entry_id: 'b-write', outcome, principal: {all: true}, connection: {any_of: ['kintone:fixture']},
      resource: {any_of: ['inquiries']}, operation: {any_of: ['effect']}, exclusions: []}]}));
  await writeAccount();
  const context = Object.freeze({principal: 'operator', contextCid: cid(root + '/account')});
  const gate = await createLocalAuthorizationGate({accountConfig: accountPath, principal: 'operator', context});
  const issued = new WeakSet();
  const authorization = Object.freeze({...gate, context, issued: decision => issued.has(decision),
    authorize: async (...args) => {const decision = await gate.authorize(...args); issued.add(decision); return decision;}});
  const subjectCid = cid(root + '/original-write-subject');
  const runInvocationCid = cid(root + '/original-invocation');
  const dispatchRequestCid = cid(root + '/original-dispatch');
  const decisionFor = selectedOperation => authorization.authorize(selectedOperation === operation
    ? 'effect_commit' : 'acquisition', {connection: 'kintone:fixture',
    resource: selectedOperation === KINTONE_FORM_READ_OPERATION ? 'form' : 'inquiries',
    operation: selectedOperation === operation ? 'effect' : 'read'}, {subjectCid});
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
    credentialAuthorityId: 'kintone-write-fixture', credentialKeyId: 'key',
    journalRoot: join(root, 'credential-journal'), resourceOrigin: tls.origin,
    namespaceId: 'kintone-fixture', environment: 'test', siteKey: 'original-site', siteGeneration: 1},
    principalId: 'operator', authorization, connection: 'kintone:fixture', connectorRegistration: 'kintone',
    connectorRevision: 'kintone/0.1', runtimeBundleCid: cid(await readFile(new URL(commonRuntime))),
    commonMoon: common, ca: tls.ca, admitsApprovalTarget: () => false,
    resolveSecret: async () => {state.resolutions++; await state.resolve?.(); return state.secret;}});
  const authorizations = new Map();
  const authorizationFor = async ({operation}) => {
    if (authorizations.has(operation)) return authorizations.get(operation);
    const decision = await decisionFor(operation);
    const args = {operation, decision, resource: operation === KINTONE_FORM_READ_OPERATION ? 'form' : 'inquiries',
      runInvocationCid, dispatchRequestCid, maxUses: 1, subjectCid};
    const grant = operation === KINTONE_RECORD_CREATE_OPERATION || operation === KINTONE_RECORD_UPDATE_OPERATION
      ? site.issueEffectGrant(args) : site.issueReadGrant(args);
    const original = Object.freeze({...grant, useId: operation + '/original'});
    authorizations.set(operation, original); return original;
  };
  const initialAuthorization = await authorizationFor({operation: KINTONE_FORM_READ_OPERATION});
  binding = openHttpsCredentialBinding({...site.credential, scope: initialAuthorization.scope,
    maxSecretBytes: 128, secretPresentation: 'kintone-api-token'});
  const formLimits = common.clientProgramKintoneFormLimits(8192, 2000, 20, 16, 512);
  const catalog = checked(common.clientProgramKintoneProjectForm(bytes(formDocument), '12', formLimits));
  const pageLimits = common.clientProgramKintonePageLimits(8192, 2000, 20, 2, 8, 64, 16);
  const page = checked(common.clientProgramKintoneProjectRecordPage(bytes({records: ids.map(id => record(id)),
    totalCount: null}), catalog, fields, pageLimits));
  const intended = checked(common.clientProgramKintoneProjectRecordPage(bytes({records: [{
    ...record(ids[0]), Subject: {type: 'SINGLE_LINE_TEXT', value: 'next 東京'},
    Tags: {type: 'MULTI_SELECT', value: ['東京', 'red', '東京']},
  }], totalCount: null}), catalog, ['Subject', 'Tags'], pageLimits));
  const admitted = checked(common.clientProgramKintoneCheckedRecordPage(intended, undefined,
    common.clientProgramKintoneValueLimits(8, 512, 1000, 16, 8192)));
  assert.deepEqual(common.clientProgramKintoneCheckedColumns(admitted), ['$id', 'Subject', 'Tags']);
  const cells = common.clientProgramKintoneCheckedRows(admitted)[0];
  const values = checked(common.clientProgramKintoneWriteValues(catalog,
    [runtimePair('Subject', cells[1]), runtimePair('Tags', cells[2])],
    common.clientProgramKintoneWriteLimits(16, 512, 2000, 20, 8192, 4096)));
  const mutation = common.clientProgramKintoneMutationLimits(100, 10000, 10000, 4096, 2000, 20);
  const targets = ids.map((_, index) => checked(common.clientProgramKintoneOriginalRecordTarget(page, index, 128)));
  const request = checked(kind === 'create' ? common.clientProgramKintoneCreateRequest(catalog, [values, values], mutation)
    : common.clientProgramKintoneUpdateRequest(targets.map(target => runtimePair(target, values)), mutation));

  row = await accountedKintoneResponses(catalog, () => !state.active && closeHttpsCredentialBinding(binding) === 'closed',
    {fields, programId: 'kintone-write-response-custody'});
  const options = {moon: common, kind, guestSpaceId, originalAppId: '12', request, initialAuthorization,
    credential: Object.freeze({...site.credential, binding}), limits, authorizationFor, current,
    chargeResponse: body => {state.charges++; const charge = row.charge(body); state.afterCharge?.(); return charge;},
    consumeObservation: charge => {state.consumed++; row.consume(charge);}, callResource: site.callResource};
  const send = async (overrides = {}) => {
    assert.equal(state.active, false); state.active = true;
    try {return await sendRawKintoneWrite({...options, ...overrides});} finally {state.active = false;}
  };
  return {root, tls, state, site, binding, row, options, common, catalog, request, send, writeAccount,
    closeRoot: () => {state.closing = true; return row.close();},
    journal: site.credential.journal, authorizationFor, operation};
}
