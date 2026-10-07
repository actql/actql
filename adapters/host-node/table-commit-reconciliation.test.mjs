// Real checked Preview and durable common Ledger. Catalog lookup replies are
// explicit independent fixtures, not evidence of a physical/public commit.
import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {join} from 'node:path';
import {exerciseEffectSourceSet} from './client-program-bridge.test.mjs';
import {openEffectLedger} from './effect-ledger.mjs';
import {captureClaimedEffectResponse} from './effect-physical-dispatch.mjs';
import {reconcileOriginalTableCommit} from './table-commit-reconciliation.mjs';
import {canonicalJson} from '../../packages/sdk/host-port.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const seal = body => ({...body, receipt_cid: `sha256:${createHash('sha256')
  .update(canonicalJson(body, {dataKeys: true})).digest('hex')}`});
function receipt(operation, empty) {
  return seal({version: 'actql-table-receipt/0.1',
    request_cid: operation.request_cid, effect_identity_cid: operation.effect_identity_cid,
    catalog_identity_cid: operation.catalog_identity_cid, schema_cid: operation.schema_cid,
    storage_mapping_cid: operation.storage_mapping_cid,
    table_uuid: '11111111-2222-3333-4444-555555555555', generation_cid: cid('b'),
    metadata_location: 'file:///table/original-generation.json',
    snapshot_id: empty ? null : '123', row_count: empty ? 0 : 2});
}

for (const empty of [false, true]) {
  test(`Table original-operation reconciliation ${empty ? 'empty' : 'nonempty'} uses original durable dispatch without resend`,
    async t => exerciseEffectSourceSet(t, {empty, onTablePreview: async f => {
      const {moon, sourceControl: control, effect, tablePreview, tableLimits: limits} = f;
      const operation = f.operations[0];
      const binding = control.tablePreviewLedgerBinding(tablePreview);
      const member = JSON.parse(f.authored._0).effects[0];
      const key = f.authored._1[0][0];
      const locator = effect.logicalItemLocator(f.scope, 'captured-table', 'unit-1',
        member.effect_id, JSON.stringify(operation.request_cid), 128, 256, 16, 4);
      const basis = effect.ledgerBasis(f.scope, locator, key, cid('6'),
        member.effect_member_preview_cid, binding.rowPreviewCid,
        operation.request_cid, cid('0'), 'unavailable', cid('1'), cid('2'));
      const claim = {scope: f.scope, locator, key, basis,
        intentFingerprintCid: binding.rowPreviewCid, canonicalRequestCid: operation.request_cid};
      const expected = receipt(operation, empty), reply = {ok: true, result: expected};
      const responseBytes = Buffer.from(JSON.stringify(reply));
      const opens = [];
      const open = name => {
        const value = openEffectLedger({moon, root: join(f.directory, `reconcile-${name}`),
          authorityScopeCid: cid('e'), callerRequestId: 'table-bind', maxEntryBytes: 8192});
        opens.push(value);
        return value;
      };
      const possible = async name => {
        const first = open(name);
        await assert.rejects(captureClaimedEffectResponse({ledger: first, claim,
          requestCid: operation.request_cid, execute: () => {
            throw Object.assign(new Error('LostReplyFixture'), {code: 'LostReplyFixture'});
          }}), {code: 'LostReplyFixture'});
        first.close();
        return open(name);
      };
      const options = ledger => ({control, commonMoon: moon, ledger, tablePreview,
        claim, credentialUseCid: cid('7'), maxRevisions: 8, limits,
        entryLimits: {maxWireBytes: 8192, maxNodes: 64, maxDepth: 4},
        authorizeEvidenceRead: async evidence => {
          assert.equal(evidence.canonicalRequestCid, operation.request_cid);
          assert.equal(evidence.catalogIdentityCid, operation.catalog_identity_cid);
          assert.equal(evidence.logicalRequestScopeCid, ledger.scopeCid);
          return true;
        }, bridge: {async reconcileOperation(actual) {
          assert.deepEqual(actual, operation);
          return reply;
        }, execute() { assert.fail('Reconciliation must never write'); },
        inspect() { assert.fail('Current head is not original commit evidence'); },
        cleanup() { assert.fail('Unknown reconciliation cannot remove files'); }}});
      try {
        // Without a prior possible dispatch, no Catalog lookup or new claim.
        const absent = open('absent');
        assert.deepEqual(await reconcileOriginalTableCommit({...options(absent),
          bridge: {reconcileOperation: () => assert.fail('Missing intent cannot query')}}),
        {status: 'unknown'});
        assert.deepEqual(absent.history(effect.logicalItemLocatorCid(locator), 8), []);
        absent.append(effect.ledgerEntryWire(effect.issuePreparedLedgerEntry(basis, 8192, 64, 4)));
        assert.deepEqual(await reconcileOriginalTableCommit({...options(absent),
          bridge: {reconcileOperation: () => assert.fail('Prepared intent cannot query')}}),
        {status: 'unknown'});
        assert.equal(absent.history(effect.logicalItemLocatorCid(locator), 8).length, 1);

        const missing = await possible('missing');
        assert.deepEqual(await reconcileOriginalTableCommit({...options(missing),
          bridge: {reconcileOperation: async () => ({ok: true, result: null})}}),
        {status: 'unknown'});
        assert.equal(missing.readClaimedResponse(claim), undefined);
        assert.equal(missing.history(effect.logicalItemLocatorCid(locator), 8).length, 2);
        await assert.rejects(reconcileOriginalTableCommit({...options(missing),
          maxRevisions: 1, bridge: {reconcileOperation: () => assert.fail('History limit must precede I/O')}}),
        {code: 'EffectLedgerHistoryLimitExceeded'});

        const denied = await possible('denied');
        await assert.rejects(reconcileOriginalTableCommit({...options(denied),
          authorizeEvidenceRead: async () => false,
          bridge: {reconcileOperation: () => assert.fail('Denied evidence access cannot query')}}),
        {code: 'EffectEvidenceAccessDenied'});
        let access = 0;
        await assert.rejects(reconcileOriginalTableCommit({...options(denied),
          authorizeEvidenceRead: async () => ++access === 1}),
        {code: 'EffectEvidenceAccessDenied'});
        assert.equal(access, 2);
        assert.equal(denied.readClaimedResponse(claim), undefined);

        const foreign = await possible('foreign');
        const substituted = {...expected, request_cid: cid('9')};
        delete substituted.receipt_cid;
        await assert.rejects(reconcileOriginalTableCommit({...options(foreign),
          bridge: {reconcileOperation: async () => ({ok: true, result: seal(substituted)})}}),
        {code: 'MoonBitHostFailure'});
        assert.equal(foreign.readClaimedResponse(claim), undefined);

        const invalidSaved = open('invalid-saved');
        const invalidBytes = Buffer.from('{"accepted":true}');
        await captureClaimedEffectResponse({ledger: invalidSaved, claim,
          requestCid: operation.request_cid, execute: async () => ({observation: {
            useCid: cid('8'), statusCode: 200, body: invalidBytes}})});
        await assert.rejects(reconcileOriginalTableCommit({...options(invalidSaved),
          bridge: {reconcileOperation: () => assert.fail('Existing invalid evidence must not be replaced')}}),
        {code: 'MoonBitHostFailure'});
        assert.deepEqual(invalidSaved.readClaimedResponse(claim).responseBytes, invalidBytes);
        assert.equal(invalidSaved.readClaimedOutcome(claim), undefined);

        const explicitlyUnknown = await possible('unknown-state');
        explicitlyUnknown.append(effect.ledgerEntryWire(effect.issueNextLedgerEntry(
          explicitlyUnknown.currentAdmitted(effect.logicalItemLocatorCid(locator)),
          'unknown', '', 8192, 64, 4)));
        explicitlyUnknown.close();
        const unknownReopened = open('unknown-state');
        assert.equal((await reconcileOriginalTableCommit(options(unknownReopened))).status, 'applied');
        assert.equal(unknownReopened.history(effect.logicalItemLocatorCid(locator), 8).length, 4);

        // Saving evidence is fallible; no terminal fact exists until it succeeds.
        const saveFailure = await possible('save-failure');
        await assert.rejects(reconcileOriginalTableCommit({...options(saveFailure),
          ledger: {...saveFailure, recordResponse: () => {
            throw Object.assign(new Error('EffectLedgerCapacityExceeded'), {code: 'EffectLedgerCapacityExceeded'});
          }}}), {code: 'EffectLedgerCapacityExceeded'});
        assert.equal(saveFailure.readClaimedResponse(claim), undefined);

        // Two read-only recoveries overlap after the same original dispatch.
        const concurrent = await possible('concurrent');
        let lookups = 0, release;
        const barrier = new Promise(resolve => { release = resolve; });
        const concurrentOptions = {...options(concurrent), bridge: {async reconcileOperation(actual) {
          assert.deepEqual(actual, operation);
          if (++lookups === 2) release();
          await barrier;
          return reply;
        }}};
        const settled = await Promise.all([reconcileOriginalTableCommit(concurrentOptions),
          reconcileOriginalTableCommit({...concurrentOptions, credentialUseCid: cid('8')})]);
        assert.equal(lookups, 2);
        assert.ok(settled.every(value => value.status === 'applied'));
        assert.equal(settled[0].receipt.identity, settled[1].receipt.identity);
        assert.deepEqual(JSON.parse(settled[0].receipt.wire).typed_outcome.result, expected);
        const saved = concurrent.readClaimedResponse(claim);
        assert.deepEqual(saved.responseBytes, responseBytes);
        const terminalHistory = concurrent.history(effect.logicalItemLocatorCid(locator), 8);
        assert.equal(terminalHistory.length, 3);
        concurrent.close();
        const reopened = open('concurrent');
        assert.equal((await reconcileOriginalTableCommit({...options(reopened),
          bridge: {reconcileOperation: () => assert.fail('Saved evidence does not query again')}}))
          .receipt.identity, settled[0].receipt.identity);
        assert.deepEqual(reopened.history(effect.logicalItemLocatorCid(locator), 8), terminalHistory);
        assert.equal(reopened.readClaimedResponse(claim).credentialUseCid, saved.credentialUseCid);
        assert.equal((await captureClaimedEffectResponse({ledger: reopened, claim,
          requestCid: operation.request_cid,
          execute: () => assert.fail('Reconciled commit must not resend')})).claimed, false);

        // A late original reply wins the immutable response slot. Never replace
        // its credential use or bytes with our independently valid lookup reply.
        const late = await possible('late');
        const dispatching = late.currentAdmitted(effect.logicalItemLocatorCid(locator));
        let delivered = false;
        const recordLate = () => {
          if (delivered) return;
          delivered = true;
          late.recordResponse({dispatching, scope: claim.scope, locator, key,
            canonicalRequestCid: operation.request_cid, credentialUseCid: cid('8'),
            statusCode: 200, responseBytes});
        };
        const raced = {...late, recordResponse(value) {
          recordLate();
          return late.recordResponse(value);
        }};
        assert.equal((await reconcileOriginalTableCommit({...options(late), ledger: raced})).status, 'applied');
        assert.equal(late.readClaimedResponse(claim).credentialUseCid, cid('8'));
        assert.deepEqual(late.readClaimedResponse(claim).responseBytes, responseBytes);
      } finally {
        for (const ledger of opens) ledger.close();
      }
    }}));
}
