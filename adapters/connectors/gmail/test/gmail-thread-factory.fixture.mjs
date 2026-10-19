// Actual Common/RowRun and installed Account/Site component composition.
// Explicit component capacity is not normal Host funding or a raw-alias ACK.
import assert from 'node:assert/strict';
import {readFile, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import * as common from '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {installRowSourceAuthorization, openRowSourceCredentialSite} from '../../../host-node/installed-row-source.mjs';
import {createGmailThreadReaderFactory} from '../host/thread-reader.mjs';
import {GMAIL_THREAD_LIST_OPERATION} from '../site/gmail-thread-read.mjs';
import {threadReadFixture, threadRowOwner, threadReadLimits, threadRowSchema} from './gmail-thread-read.fixture.mjs';

const pending = new Set();
export async function threadFactoryFixture(t, {account = 'allow'} = {}) {
  const f = await threadReadFixture(t, {accounted: false, account});
  const authorization = await installRowSourceAuthorization({root: f.root, principalId: 'operator',
    connectorRegistration: 'gmail', accountConfiguration: await readFile(join(f.root, 'account.json'), 'utf8')});
  const site = await openRowSourceCredentialSite({profile: {
    credentialPrivateKeyPath: join(f.root, 'credential-authority.key'),
    credentialAuthorityId: 'installed-gmail', credentialKeyId: 'key',
    journalRoot: join(f.root, 'installed-thread-journal'), namespaceId: 'installed-gmail',
    environment: 'test', siteKey: 'installed-gmail', siteGeneration: 1,
    resourceOrigin: f.scope.resourceOrigin}, principalId: 'operator', authorization,
    connection: 'gmail:fixture', connectorRegistration: 'gmail', connectorRevision: 'gmail/0.1',
    runtimeBundleCid: f.scope.runtimeBundleCid, commonMoon: common, ca: f.options.credential.ca,
    resolveSecret: f.options.credential.resolveSecret, admitsApprovalTarget: () => false});
  const row = await threadRowOwner(() => false, '{"relation_keys":{"candidate_keys":[["id"]]}}',
    'sql', 'id, labels, last_message_date, message_count, subject');
  const rowRun = Object.freeze({...row.originals, runInvocationCid: f.scope.runInvocationCid,
    dispatchRequestCid: f.scope.dispatchRequestCid});
  const hooks = {afterCurrent: undefined};
  const decisions = [], grants = [];
  const suppliedSite = {credential: site.credential,
    callResource(...args) {assert.equal(this, suppliedSite); return Reflect.apply(site.callResource, site, args);},
    issueReadGrant(options) {
      assert.equal(this, suppliedSite);
      const original = Reflect.apply(site.issueReadGrant, site, [options]);
      grants.push({options, original}); return original;
    }};
  const options = {resource: 'threads', operation: GMAIL_THREAD_LIST_OPERATION,
    rowRun, columns: Object.keys(threadRowSchema), signal: undefined,
    async verifyRead() {
      assert.equal(this, options);
      const decision = await authorization.authorize('acquisition',
        {connection: 'gmail:fixture', resource: 'threads', operation: 'read'},
        {subjectCid: rowRun.runInvocationCid});
      decisions.push(decision);
      await hooks.afterCurrent?.(decision);
      if (decision.action !== 'dispatch') throw Object.assign(new Error('GmailReadDenied'), {code: 'GmailReadDenied'});
      return decision;
    },
    async authorizationFor(index) {
      assert.equal(this, options);
      const decision = await options.verifyRead();
      const grant = suppliedSite.issueReadGrant({operation: GMAIL_THREAD_LIST_OPERATION,
        decision, resource: 'threads', runInvocationCid: rowRun.runInvocationCid,
        dispatchRequestCid: rowRun.dispatchRequestCid, maxUses: threadReadLimits.maxPages});
      return {...grant, useId: rowRun.requestId + '-list-' + index};
    },
    chargePage(body) {assert.equal(this, options); f.state.charges++; return row.charge(body);},
    consumeObservation(charge) {assert.equal(this, options); return row.observation(charge);},
    consumePage(rows, {charge}) {assert.equal(this, options); row.page(rows, charge); f.state.rows.push(...rows);},
  };
  const capacity = common.clientProgramRowSourceProviderCapacity(262144n, 262144n);
  assert.ok(capacity);
  const makeFactory = ({moon = f.options.moon, ...overrides} = {}) => createGmailThreadReaderFactory({moon,
    site: suppliedSite, capacity, mailbox: f.options.mailbox, limits: threadReadLimits, maxSecretBytes: 128, ...overrides});
  t.after(async () => {
    // Physical socket/journal close is separate from retained raw/callback/
    // error aliases and the original RowRun reservation. Keep their graph.
    pending.add({f, site, row, rowRun, options, suppliedSite, decisions, grants});
    row.close();
    await site.close();
    await writeFile(join(f.root, 'pending-thread-factory-custody.json'), JSON.stringify({cleanupConfirmed: false,
      reason: 'Original raw, row, callback and error aliases remain retained; no retirement receipt',
      usage: row.usage().map(value => typeof value === 'bigint' ? value.toString() : value)}));
  });
  return {...f, site, suppliedSite, authorization, row, rowRun, options, hooks, decisions, grants, capacity, makeFactory};
}
