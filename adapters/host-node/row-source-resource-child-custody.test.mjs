import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {mkdtemp, rm} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import test from 'node:test';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {openSqliteCredentialJournal} from '../site-node/sqlite-credential-journal.mjs';
import {callHttpsCredentialResource} from '../site-node/https-credential-resource.mjs';
import {openHttpsExchangeFixture} from '../site-node/https-exchange-fixture.mjs';
import {openRowSourceCredentialCustody, installedRowCredentialOperationSite} from './installed-row-source.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const current = () => ({assertCurrent() {}, async observeCurrent() {}});
const foreign = {code: 'ForeignRowSourceCredentialResourceChild'};

// Actual credential/Journal/transport custody component. The private issuer's
// read purpose stands in for an already-issued Account decision, not evidence
// that an installed Account policy or a complete provider quote was exercised.
async function fixture(t, maxBindings = 8) {
  const exchange = await openHttpsExchangeFixture(t, {routes: [{method: 'GET',
    pathname: '/form', handle: () => ({body: {revision: '7'}})}]});
  const root = await mkdtemp(join(tmpdir(), 'actql-resource-child-'));
  const key = generateKeyPairSync('ed25519');
  let grants = 0, resolutions = 0, closes = 0;
  const custody = openRowSourceCredentialCustody({
    profile: Object.freeze({credentialAuthorityId: 'authority', credentialKeyId: 'issuer',
      journalRoot: join(root, 'journal'), resourceOrigin: exchange.origin,
      namespaceId: 'namespace', environment: 'test', siteKey: 'site', siteGeneration: 2}),
    principalId: 'principal', connectorRegistration: 'fixture', connectorRevision: 'fixture/0.1',
    runtimeBundleCid: cid('a'), commonMoon: moon, privateKey: key.privateKey, ca: exchange.ca,
    now: () => 1_700_000_000_000, grantLifetimeMs: 456,
    runAcquisitionLimits: {maxBindings, maxSecretBytes: 64},
    resolveSecret: async () => {resolutions++; return 'original-test-secret';},
    openCredentialJournal(path, options) {
      const journal = openSqliteCredentialJournal(path, options);
      return Object.freeze({...journal,
        acceptGrant(...args) {grants++; return journal.acceptGrant(...args);},
        close() {closes++; return journal.close();},
      });
    },
  });
  const site = Object.freeze({credential: custody.credential, connection: 'fixture:connection',
    callResource: callHttpsCredentialResource});
  custody.retainOperationSite(site);
  t.after(async () => {custody.closeOnce(); await rm(root, {recursive: true, force: true});});
  const sign = (resource, operation = 'fixture:read', overrides = {}) => custody.sign({operation,
    runInvocationCid: cid('b'), dispatchRequestCid: cid('c'), taskAttempt: 3, maxUses: 4,
    issuerPurpose: Object.freeze({kind: 'read', resource, decision: Object.freeze({resource})}), ...overrides});
  const invoke = child => callHttpsCredentialResource({...child.credential, ...child.authorization,
    useId: 'form-use', operations: new Map([['fixture:form', {method: 'GET', path: '/form'}]]),
    maxRequestBytes: 1024, maxResponseBytes: 1024});
  return {custody, exchange, sign, invoke, view: installedRowCredentialOperationSite(site.credential),
    counts: () => ({grants, resolutions, closes})};
}

test('separate Resource child keeps its own exact grant binding and both original currents', async t => {
  const f = await fixture(t);
  let parentChecks = 0, parentObservations = 0, formChecks = 0, formObservations = 0, replacements = 0;
  const parentMethods = {assertCurrent() {parentChecks++;}, async observeCurrent() {parentObservations++;}};
  const parentAuthorization = f.sign('records');
  const parent = f.view.bindRunAcquisition(parentAuthorization, parentMethods);
  const form = f.sign('form', 'fixture:form');
  const childMethods = {assertCurrent() {formChecks++;}, async observeCurrent() {formObservations++;}};
  const child = f.view.bindReadResourceChild(parent, form, childMethods);
  parentMethods.assertCurrent = childMethods.assertCurrent = () => {replacements++;};
  parentMethods.observeCurrent = childMethods.observeCurrent = async () => {replacements++;};
  assert.equal(child.authorization, form);
  assert.notEqual(child.credential, parent.credential);
  assert.notEqual(child.credential.binding, parent.credential.binding);
  assert.equal(child.credential.journal, parent.credential.journal);
  assert.equal(f.view.readResourceChildCredential(parent, child, form), child.credential);
  assert.throws(() => f.custody.readChildCredential(parent, form), {code: 'ForeignRowSourceCredentialReadChild'});
  assert.deepEqual(JSON.parse((await f.invoke(child)).body), {revision: '7'});
  assert.ok(parentChecks > 0 && formChecks > 0 && parentObservations > 0 && formObservations > 0);
  assert.equal(replacements, 0);
  assert.equal(f.counts().grants, 2);
  assert.equal(f.counts().resolutions, 1);
  assert.equal(child.close(), 'closed');
  assert.throws(() => f.view.readResourceChildCredential(parent, child, form), foreign);
  assert.equal(parent.close(), 'closed');
});

test('separate Resource child refuses equal foreign parents children authorizations and wrong invocation', async t => {
  const f = await fixture(t);
  const parent = f.custody.bindRunAcquisition(f.sign('records'), current());
  const form = f.sign('form', 'fixture:form');
  const untouched = {assertCurrent() {assert.fail('foreign input invoked current');}, async observeCurrent() {assert.fail('foreign input invoked current');}};
  for (const value of [{...parent}, Object.create(parent), {get authorization() {assert.fail('foreign accessor');}}]) {
    assert.throws(() => f.custody.bindReadResourceChild(value, form, untouched), foreign);
  }
  assert.throws(() => f.custody.bindReadResourceChild(parent, {...form}, untouched), foreign);
  assert.throws(() => f.custody.bindReadResourceChild(parent,
    f.sign('form', 'fixture:form', {dispatchRequestCid: cid('d')}), untouched), foreign);
  const otherParent = f.custody.bindRunAcquisition(f.sign('records'), current());
  const independent = f.custody.bindRunAcquisition(f.sign('form', 'fixture:form'), current());
  const child = f.custody.bindReadResourceChild(parent, form, current());
  for (const [p, c, a] of [[otherParent, child, form], [parent, {...child}, form],
    [parent, child, {...form}], [parent, independent, independent.authorization]]) {
    assert.throws(() => f.custody.readResourceChildCredential(p, c, a), foreign);
  }
  assert.throws(() => f.custody.bindReadResourceChild(child, f.sign('another'), current()), foreign);
  assert.equal(f.exchange.seen().length, 0);
  assert.equal(f.counts().resolutions, 0);
  for (const value of [child, independent, otherParent, parent]) assert.equal(value.close(), 'closed');
});

test('same Resource stays on the existing strict credential sharing path', async t => {
  const f = await fixture(t);
  const parent = f.custody.bindRunAcquisition(f.sign('records'), current());
  const same = f.sign('records', 'fixture:form');
  assert.throws(() => f.custody.bindReadResourceChild(parent, same, current()), foreign);
  assert.equal(f.custody.readChildCredential(parent, same), parent.credential);
  assert.equal(parent.close(), 'closed');
});

test('separate Resource child retains borrowed reader current and rejects its retired parent', async t => {
  const f = await fixture(t);
  let borrowedObservations = 0;
  const parent = f.view.bindRunAcquisition(f.sign('records'), current());
  const parentView = installedRowCredentialOperationSite(parent.credential);
  const borrowed = parentView.bindRunAcquisition(f.sign('records'), {
    assertCurrent() {}, async observeCurrent() {borrowedObservations++;},
  });
  const form = f.sign('form', 'fixture:form');
  const child = parentView.bindReadResourceChild(borrowed, form, current());
  assert.equal(parentView.readResourceChildCredential(borrowed, child, form), child.credential);
  await f.invoke(child);
  assert.ok(borrowedObservations > 0);
  assert.equal(borrowed.close(), 'closed');
  assert.equal(borrowed.retire(), true);
  assert.throws(() => parentView.readResourceChildCredential(borrowed, child, form), foreign);
  assert.equal(child.close(), 'closed');
  assert.equal(parent.close(), 'closed');
});

test('failed separate Resource opening consumes its original and preserves reentrant cleanup duty', async t => {
  const f = await fixture(t);
  const parent = f.custody.bindRunAcquisition(f.sign('records'), current());
  const form = f.sign('form', 'fixture:form');
  assert.throws(() => f.custody.bindReadResourceChild(parent, form, {
    assertCurrent() {
      assert.throws(() => f.custody.bindReadResourceChild(parent, form, current()), foreign);
      assert.throws(() => f.custody.closeOnce(), {code: 'RowSourceCredentialAcquisitionCleanupPending'});
      assert.equal(f.counts().closes, 0);
    }, async observeCurrent() {assert.fail('no failed physical send');},
  }), {code: 'RowSourceSiteClosed'});
  assert.equal(f.counts().resolutions, 0);
  assert.equal(f.exchange.seen().length, 0);
  f.custody.closeOnce();
  assert.equal(f.counts().closes, 1);
});

test('separate Resource constructor and lookup cannot outlive a closed original parent or child', async t => {
  const f = await fixture(t);
  const parent = f.custody.bindRunAcquisition(f.sign('records'), current());
  const failed = f.sign('form', 'fixture:form');
  const refusal = Object.assign(new Error('original Form refusal'), {code: 'FormRefused'});
  assert.throws(() => f.custody.bindReadResourceChild(parent, failed, {
    assertCurrent() {throw refusal;}, async observeCurrent() {},
  }), error => error === refusal);
  assert.throws(() => f.custody.bindReadResourceChild(parent, failed, current()), foreign);
  const form = f.sign('form', 'fixture:form');
  let closeChild = false, child;
  child = f.custody.bindReadResourceChild(parent, form, {
    assertCurrent() {if (closeChild) child.close();}, async observeCurrent() {},
  });
  closeChild = true;
  assert.throws(() => f.custody.readResourceChildCredential(parent, child, form), foreign);
  const late = f.sign('form', 'fixture:form');
  assert.throws(() => f.custody.bindReadResourceChild(parent, late, {
    assertCurrent() {parent.close();}, async observeCurrent() {},
  }), foreign);
  assert.throws(() => f.custody.bindReadResourceChild(parent, late, current()), foreign);
  assert.equal(f.exchange.seen().length, 0);
});

test('separate Resource child consumes actual second binding capacity rather than inheriting a grant allowance', async t => {
  const f = await fixture(t, 1);
  const parent = f.custody.bindRunAcquisition(f.sign('records'), current());
  const form = f.sign('form', 'fixture:form');
  assert.throws(() => f.custody.bindReadResourceChild(parent, form, current()),
    {code: 'RowSourceCredentialAcquisitionLimit'});
  assert.equal(f.counts().resolutions, 0);
  assert.equal(parent.close(), 'closed');
});
