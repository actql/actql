import assert from 'node:assert/strict';
import {createHash, generateKeyPairSync} from 'node:crypto';
import {writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {setImmediate} from 'node:timers/promises';
import test from 'node:test';
import * as commonMoon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import * as salesforceMoon from
  '../../_build/js/release/build/connectors/salesforce/host_node/host_node.js';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {installRowSourceAuthorization} from './installed-row-source.mjs';
import {sourceReadAccountConfiguration, contentCid} from './local-account-config.mjs';
import {openSqliteCredentialJournal} from '../site-node/sqlite-credential-journal.mjs';
import {installSalesforceAuthorization, installedSalesforceSiteBinding,
  loadInstalledSalesforceSite} from '../connectors/salesforce/host/installed-salesforce-site.mjs';
import {openSalesforceEffectSiteFixture} from
  '../connectors/salesforce/test/salesforce-effect-site.fixture.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const textCid = wire => `sha256:${createHash('sha256').update(wire, 'utf8').digest('hex')}`;
const principalId = 'installed-principal';
const connection = 'salesforce:00D000000000001EAA';
const resource = 'Test_Record__c';
const tuple = Object.freeze({connection, resource, operation: 'read'});
const accountConfiguration = outcome => sourceReadAccountConfiguration({
  connection, resource, outcome});
const originalContext = root => Object.freeze({principal: principalId,
  contextCid: textCid(JSON.stringify({version: 'actql-installed-salesforce-context/0.1',
    root, principalId}))});
const authorize = gate => gate.authorize('acquisition', tuple, {subjectCid: cid('5')});

async function installed(t, {outcome = 'allow', gateOptions, org} = {}) {
  const scratch = await createOwnedScratch({parent: new URL('../../_build/', import.meta.url).pathname,
    prefix: 'salesforce-shared-issuer-', label: 'Original Salesforce shared authorization issuer'});
  const root = scratch.path;
  const pair = generateKeyPairSync('ed25519');
  const profile = {version: 'actql-installed-salesforce-site/0.1',
    apiVersion: 'v62.0', cliAlias: 'fixture', cliUsername: 'fixture@example.test',
    connectionRevision: 'original-revision', credentialAuthorityId: 'fixture-authority',
    credentialKeyId: 'fixture-key', credentialPrivateKeyPath: join(root, 'credential.key'),
    environment: 'test', instanceOrigin: org?.origin ?? 'https://fixture.invalid',
    journalRoot: join(root, 'credential-journal'), orgId: '00D000000000001EAA',
    siteGeneration: 3, siteKey: 'fixture-site', namespaceId: 'fixture-namespace'};
  await writeFile(profile.credentialPrivateKeyPath,
    pair.privateKey.export({type: 'pkcs8', format: 'pem'}));
  if (org !== undefined) {
    profile.caPath = join(root, 'org-ca.crt');
    await writeFile(profile.caPath, org.credential.ca);
  }
  const path = join(root, 'site.json');
  await writeFile(path, JSON.stringify(profile));
  // The old Salesforce preimage preserves original text, including NFD text;
  // it must not become the provider-neutral context or NFC-canonical JSON.
  const contextRoot = root + '/e\u0301';
  const configuration = accountConfiguration(outcome);
  const authorization = await installSalesforceAuthorization({
    accountConfiguration: configuration, principalId, root: contextRoot, gateOptions});
  const state = {journals: 0, grants: 0, secretCalls: 0, allowClose: true};
  const site = await loadInstalledSalesforceSite(path, {commonMoon, salesforceMoon,
    authorization, runtimeBundleCid: cid('b'), resolveSecret: async () => {
      state.secretCalls++;
      return org === undefined ? 'test-only-unused-secret' : 'test-only-secret';
    },
    openCredentialJournal(root, options) {
      state.journals++;
      const journal = openSqliteCredentialJournal(root, options);
      return {...journal, acceptGrant(...args) {
        state.grants++;
        return journal.acceptGrant(...args);
      }, close() {
        if (!state.allowClose) throw Object.assign(new Error('fixture-close-failed'),
          {code: 'FixtureCloseFailed'});
        return journal.close();
      }};
    }});
  let assertionsPassed = false;
  t.after(() => {
    state.allowClose = true;
    site.close();
    authorization.close();
    if (assertionsPassed) scratch.passed();
  });
  return {root, contextRoot, configuration, path, profile, authorization,
    site, state, passed() { assertionsPassed = true; }};
}
const grant = (site, decision, extra = {}) => site.issueGrant({
  operation: 'salesforce:query:read', decision, resource,
  runInvocationCid: cid('3'), dispatchRequestCid: cid('4'), ...extra});

// These are actual compiled Account and Credential Owners with a fresh SQLite
// journal, not successful doubles. The final case also reaches the unchanged
// loopback Describe/query fixture; the other cases send no Provider request.
test('shared installer retains its default context and exact original decision issuer', async t => {
  const root = 'shared-installation';
  const options = {accountConfiguration: accountConfiguration('allow'), principalId,
    root, connectorRegistration: 'fixture'};
  const gate = await installRowSourceAuthorization(options);
  const other = await installRowSourceAuthorization(options);
  t.after(() => {gate.close(); other.close();});
  // This literal is the independent canonical preimage of the unchanged default.
  const expected = JSON.stringify({connectorRegistration: 'fixture', principalId,
    root, version: 'actql-installed-row-source-context/0.1'});
  assert.deepEqual(gate.context, {principal: principalId, contextCid: textCid(expected)});
  const decision = await authorize(gate);
  assert.equal(decision.action, 'dispatch');
  assert.equal(gate.issued(decision), true);
  assert.equal(gate.issued({...decision}), false);
  assert.equal(other.issued(decision), false);
  assert.equal(gate.issued(undefined), false);
});

test('shared installer keeps an explicit immutable original context and protects installation inputs', async t => {
  const context = originalContext('original-root/e\u0301');
  const gate = await installRowSourceAuthorization({accountConfiguration: accountConfiguration('allow'),
    principalId, root: 'original-root', connectorRegistration: 'salesforce', originalContext: context,
    gateOptions: {principal: 'foreign', context: {principal: 'foreign', contextCid: cid('a')},
      accountConfiguration: 'not-an-account'}});
  t.after(() => gate.close());
  assert.equal(gate.context, context);
  const decision = await authorize(gate);
  assert.equal(decision.action, 'dispatch');
  assert.equal(decision.tuple.principal, principalId);
  assert.equal(decision.contextCid, context.contextCid);
  for (const original of [{...context}, Object.freeze({...context, principal: 'foreign'}),
    Object.freeze({principal: principalId}), Object.freeze({...context, contextCid: 'missing'}),
    Object.freeze({...context, extra: 'not-original'}),
    Object.freeze(Object.assign(Object.create(context), {one: true, two: true})), null]) {
    await assert.rejects(installRowSourceAuthorization({accountConfiguration: 'not-json',
      principalId, root: 'root', connectorRegistration: 'salesforce', originalContext: original}),
    {code: 'InvalidRowSourceAuthorizationInstallation'});
  }
});

test('Salesforce compatibility installer preserves original context and Site-binding preimages', async t => {
  const f = await installed(t);
  assert.deepEqual(f.authorization.context, originalContext(f.contextRoot));
  assert.equal(Object.hasOwn(f.authorization, 'issued'), false);
  assert.equal(f.authorization.accountConfiguration, f.configuration);
  const p = f.profile;
  const expectedBinding = {version: 'actql-installed-salesforce-site-binding/0.1',
    contextCid: originalContext(f.contextRoot).contextCid,
    namespace_id: p.namespaceId, principal: principalId, environment: p.environment,
    connection, connectionRevision: p.connectionRevision, orgId: p.orgId,
    instanceOrigin: p.instanceOrigin, siteKey: p.siteKey, siteGeneration: p.siteGeneration,
    apiVersion: p.apiVersion, cliAlias: p.cliAlias, cliUsername: p.cliUsername,
    credentialAuthorityId: p.credentialAuthorityId, credentialKeyId: p.credentialKeyId,
    credentialPrivateKeyPath: p.credentialPrivateKeyPath};
  assert.deepEqual(installedSalesforceSiteBinding(f.site, 'crm/main'),
    {connectorId: 'crm/main', bindingCid: contentCid(expectedBinding)});
  const decision = await authorize(f.authorization);
  const issued = grant(f.site, decision, {taskAttempt: 2, maxUses: 3});
  assert.equal(issued.scope.taskAttempt, 2);
  assert.equal(issued.scope.siteGeneration, p.siteGeneration);
  assert.equal(issued.scope.operation, 'salesforce:query:read');
  assert.equal(issued.scope.maxUses, 3);
  assert.equal(f.state.grants, 1);
  assert.equal(f.state.secretCalls, 0);
  f.passed();
});

test('Salesforce rejects copied and foreign original decisions without signing replacement grants', async t => {
  const f = await installed(t);
  const foreign = await installSalesforceAuthorization({accountConfiguration: f.configuration,
    principalId, root: f.contextRoot});
  t.after(() => foreign.close());
  const original = await authorize(f.authorization);
  const other = await authorize(foreign);
  assert.equal(other.action, 'dispatch');
  for (const decision of [undefined, {...original}, other,
    {action: 'dispatch', boundary: 'acquisition', contextCid: original.contextCid, tuple}]) {
    assert.throws(() => grant(f.site, decision), {code: 'SalesforceCredentialGrantNotAuthorized'});
  }
  grant(f.site, original);
  assert.equal(f.state.grants, 1);
  assert.equal(f.state.secretCalls, 0);
  f.passed();
});

test('Salesforce retains delegated original issuer and current closure after an await', async t => {
  let answers = 0;
  const f = await installed(t, {outcome: 'delegate', gateOptions: {answeringAuthorities: ['host'],
    async decide(view) {answers++; await setImmediate();
      return {decision: 'permit', subject: view.subject, authority: 'host', claims: []};
    }}});
  const decision = await authorize(f.authorization);
  assert.equal(decision.action, 'dispatch');
  assert.equal(decision.basis, 'host_permit');
  grant(f.site, decision);
  await setImmediate();
  f.authorization.close();
  assert.throws(() => grant(f.site, decision), {code: 'AuthorizationDecisionScopeClosed'});
  assert.equal(answers, 1);
  assert.equal(f.state.grants, 1);
  assert.equal(f.state.secretCalls, 0);
  f.passed();
});

test('Salesforce resumed allow cannot replace missing original Checkpoint ownership', async t => {
  const f = await installed(t);
  const resumed = await f.authorization.resume('acquisition', tuple,
    {subjectCid: cid('5'), resumption: {claim: {action: 'claimed'}}});
  assert.equal(resumed.action, 'failure');
  assert.equal(resumed.detail, 'ResumeJournalUnavailable');
  assert.throws(() => grant(f.site, resumed), {code: 'SalesforceCredentialGrantNotAuthorized'});
  assert.equal(f.state.grants, 0);
  assert.equal(f.state.secretCalls, 0);
  f.passed();
});

test('Salesforce installer provenance rejects a forged shared issuer before Site I/O', async t => {
  const f = await installed(t);
  let acquisitions = 0;
  await assert.rejects(loadInstalledSalesforceSite(f.path, {commonMoon, salesforceMoon,
    authorization: Object.freeze({...f.authorization, issued: () => true}), runtimeBundleCid: cid('b'),
    openCredentialJournal() {acquisitions++; throw new Error('unexpected-journal');}}),
  {code: 'InvalidInstalledSalesforceSiteOptions'});
  assert.equal(acquisitions, 0);
  assert.equal(f.state.journals, 1);
  assert.equal(f.state.secretCalls, 0);
  f.passed();
});

test('Salesforce shared issuer keeps pending original journal cleanup and refuses all new grants', async t => {
  const f = await installed(t);
  const decision = await authorize(f.authorization);
  grant(f.site, decision);
  f.state.allowClose = false;
  assert.throws(() => f.site.close(), {code: 'FixtureCloseFailed'});
  assert.equal(f.site.cleanupPending(), true);
  assert.throws(() => grant(f.site, decision), {code: 'SalesforceSiteClosed'});
  f.state.allowClose = true;
  f.site.close();
  assert.equal(f.site.cleanupPending(), false);
  f.site.close();
  assert.equal(f.state.journals, 1);
  assert.equal(f.state.grants, 1);
  assert.equal(f.state.secretCalls, 0);
  f.passed();
});

test('Salesforce shared issuer preserves read versus Effect denial and invalid selected configuration', async t => {
  const f = await installed(t);
  const decision = await f.authorization.authorize('effect_commit', {...tuple, operation: 'effect'},
    {subjectCid: cid('6')});
  assert.equal(decision.action, 'deny');
  assert.throws(() => f.site.issueGrant({operation: 'salesforce:record:update', decision,
    resource, subjectCid: cid('6'), runInvocationCid: cid('3'), dispatchRequestCid: cid('4')}),
  {code: 'SalesforceCredentialGrantNotAuthorized'});
  await assert.rejects(installSalesforceAuthorization({accountConfiguration: 'not-json',
    principalId, root: f.root}), {code: 'ACTQL_E_ACCOUNT_CONFIG_INVALID'});
  assert.equal(f.state.grants, 0);
  assert.equal(f.state.secretCalls, 0);
  f.passed();
});

// Keep the existing independent provider oracle and exercise the two other
// original issuer consumers, named metadata admission and bounded preview.
test('Salesforce shared original issuer reaches unchanged loopback Describe and bounded peek', async t => {
  const org = await openSalesforceEffectSiteFixture(t, {commonMoon, salesforceMoon,
    runInvocationCid: cid('1'), dispatchRequestCid: cid('2')});
  const f = await installed(t, {org});
  const before = org.seen.length;
  const observed = await f.site.describeEffectCatalog({resources: [resource],
    occurrence: 'shared-issuer-description', runInvocationCid: cid('3'),
    dispatchRequestCid: cid('4')});
  assert.deepEqual(observed.evidence.names, [resource]);
  assert.match(observed.observationCid, /^sha256:[0-9a-f]{64}$/u);
  const decision = await authorize(f.authorization);
  const preview = await f.site.peek({decision, resource, fields: ['Id'], maxRows: 1});
  assert.deepEqual(preview.rows, [{Id: 'a00000000000001'}]);
  assert.equal(preview.limited, true);
  assert.deepEqual(org.seen.slice(before).map(item => decodeURIComponent(item.path)), [
    '/services/data/v62.0/sobjects/Test_Record__c/describe',
    '/services/data/v62.0/sobjects/Test_Record__c/describe',
    '/services/data/v62.0/sobjects/Test_Record__c/describe',
    '/services/data/v62.0/query?q=SELECT Id FROM Test_Record__c LIMIT 1',
  ]);
  await assert.rejects(f.site.peek({decision: {...decision}, resource, fields: ['Id'], maxRows: 1}),
    {code: 'SalesforcePeekNotAuthorized'});
  assert.equal(org.seen.length, before + 4);
  assert.equal(f.state.grants, 4);
  assert.equal(f.state.secretCalls, 4);
  f.passed();
});
