import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {openEffectLedger} from './effect-ledger.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const authorityScopeCid = cid('a');
const scopeCid =
  'sha256:caf2d10a1c26dfe7d79caf9a0d51645d5b29ad6c73fb2c6e036a3c2b04bf02c3';
const canonical = value => JSON.stringify(Object.fromEntries(
  Object.entries(value).sort(([left], [right]) => left.localeCompare(right)),
));
const hash = value => `sha256:${createHash('sha256').update(value).digest('hex')}`;
const entry = ({state = 'prepared', fence = 1, attempt = 0,
  prior = null, outcome = null, fingerprint = cid('4')} = {}) => {
  const body = {
    attempt_sequence: attempt,
    canonical_request_cid: cid('1'),
    capability: 'unavailable',
    dispatch_key: cid('2'),
    effect_preview_cid: cid('3'),
    fence,
    intent_fingerprint_cid: fingerprint,
    logical_item_locator_cid: cid('5'),
    logical_request_scope_cid: scopeCid,
    original_membership_cid: cid('7'),
    outcome_receipt_cid: outcome,
    prior_entry_cid: prior,
    recovery_contract_cid: cid('8'),
    reservation_evidence_cid: cid('9'),
    retention_contract_cid: cid('a'),
    state,
    unit_definition_cid: cid('b'),
    version: 'actql-logical-item-ledger-entry/0.1',
  };
  const entryCid = hash(canonical(body));
  return Object.freeze({cid: entryCid, wire: canonical({...body,
    self_cid: entryCid})});
};

async function fixture(t) {
  const root = await mkdtemp(join(tmpdir(), 'actql-effect-ledger-control-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  return root;
}

const open = root => openEffectLedger({moon, root, authorityScopeCid,
  callerRequestId: 'request-1', maxEntryBytes: 4096});
const effect = runtimeCore(moon).effectApplicationControl;

function batchClaims() {
  const scope = effect.logicalRequestScope(authorityScopeCid,
    'request-1', 32);
  return ['row-1', 'row-2'].map(row => {
    const key = effect.dispatchKey(scope, cid('b'),
      JSON.stringify(row), 32, 8, 3);
    const locator = effect.logicalItemLocator(scope, 'program-1',
      'node-1', 'WriteOne', JSON.stringify({row}), 64, 128, 8, 3);
    const canonicalRequestCid = cid('f');
    const basis = effect.ledgerBasis(scope, locator, key,
      cid('c'), cid('d'), cid('e'), canonicalRequestCid, cid('0'),
      'unavailable', cid('1'), cid('2'));
    return {scope, locator, key, basis,
      intentFingerprintCid: cid('e'), canonicalRequestCid};
  });
}

test('one collection request claims every row before physical I/O',
  async t => {
    const root = await fixture(t);
    const first = open(root);
    const concurrent = open(root);
    t.after(() => first.close());
    t.after(() => concurrent.close());
    const claims = batchClaims();
    const ownership = first.claimDispatchBatch(claims);
    assert.equal(ownership.claimed, true);
    assert.deepEqual(ownership.actions, [0, 0]);
    for (let index = 0; index < claims.length; index++) {
      const claim = claims[index];
      const locatorCid = effect.logicalItemLocatorCid(claim.locator);
      assert.equal(first.current(locatorCid).revision, 2);
      assert.equal(effect.ledgerEntryAdmitsDispatch(
        ownership.dispatching[index], claim.scope, claim.locator,
        claim.key, claim.canonicalRequestCid), true);
    }
    const responseBytes = Buffer.from('[{"success":true},{"success":false}]');
    const observation = {claims, ownership, credentialUseCid: cid('4'),
      statusCode: 200, responseBytes};
    assert.equal(first.recordBatchResponse(observation).created, true);
    assert.equal(concurrent.recordBatchResponse(observation).created, false);
    assert.throws(() => first.recordBatchResponse({
      ...observation, responseBytes: Buffer.from('[]'),
    }), {code: 'EffectPhysicalResponseCollision'});
    const retry = concurrent.claimDispatchBatch(claims);
    assert.equal(retry.claimed, false);
    assert.deepEqual(retry.actions, [3, 3]);
    first.close();
    concurrent.close();
    const restarted = open(root);
    t.after(() => restarted.close());
    assert.deepEqual(restarted.claimDispatchBatch(claims).actions, [3, 3]);
    assert.deepEqual(claims.map(claim => restarted.history(
      effect.logicalItemLocatorCid(claim.locator), 2).length), [2, 2]);
    for (const dispatching of ownership.dispatching) {
      const saved = restarted.response(effect.ledgerEntryCid(dispatching));
      assert.deepEqual(saved.responseBytes, responseBytes);
      assert.equal(saved.credentialUseCid, cid('4'));
    }
  });

test('collection claim never leaves a partial send when one row conflicts',
  async t => {
    const root = await fixture(t);
    const ledger = open(root);
    t.after(() => ledger.close());
    const claims = batchClaims();
    const foreignBasis = effect.ledgerBasis(
      claims[1].scope, claims[1].locator, claims[1].key,
      cid('9'), cid('d'), cid('e'), cid('f'), cid('0'),
      'unavailable', cid('1'), cid('2'));
    const foreign = effect.issuePreparedLedgerEntry(
      foreignBasis, 4096, 64, 4);
    ledger.append(effect.ledgerEntryWire(foreign));
    assert.throws(() => ledger.claimDispatchBatch(claims),
      {code: 'EffectLedgerIntentConflict'});
    assert.equal(ledger.current(
      effect.logicalItemLocatorCid(claims[0].locator)), undefined);
    assert.equal(ledger.current(
      effect.logicalItemLocatorCid(claims[1].locator)).revision, 1);
    assert.throws(() => ledger.claimDispatchBatch([
      claims[0], claims[0],
    ]), {code: 'EffectLedgerBatchBindingMismatch'});
    assert.throws(() => ledger.claimDispatchBatch([
      claims[0], {...claims[1], key: claims[0].key},
    ]), {code: 'EffectLedgerBatchBindingMismatch'});
    assert.equal(ledger.current(
      effect.logicalItemLocatorCid(claims[0].locator)), undefined);
  });

test('collection cannot combine rows from different Effect members',
  async t => {
    const root = await fixture(t);
    const ledger = open(root);
    t.after(() => ledger.close());
    const claims = batchClaims();
    const second = claims[1];
    const foreignLocator = effect.logicalItemLocator(
      second.scope, 'program-1', 'node-1', 'WriteTwo',
      JSON.stringify({row: 'row-2'}), 64, 128, 8, 3);
    const foreignBasis = effect.ledgerBasis(
      second.scope, foreignLocator, second.key,
      cid('c'), cid('d'), cid('e'), second.canonicalRequestCid,
      cid('0'), 'unavailable', cid('1'), cid('2'));
    assert.throws(() => ledger.claimDispatchBatch([
      claims[0], {...second, locator: foreignLocator, basis: foreignBasis},
    ]), {code: 'EffectLedgerBatchBindingMismatch'});
    const foreignKey = effect.dispatchKey(
      second.scope, cid('8'), JSON.stringify('row-2'), 32, 8, 3);
    const foreignPreviewBasis = effect.ledgerBasis(
      second.scope, second.locator, foreignKey,
      cid('c'), cid('d'), cid('e'), second.canonicalRequestCid,
      cid('0'), 'unavailable', cid('1'), cid('2'));
    assert.throws(() => ledger.claimDispatchBatch([
      claims[0], {...second, key: foreignKey, basis: foreignPreviewBasis},
    ]), {code: 'EffectLedgerBatchBindingMismatch'});
    for (const claim of claims) {
      assert.equal(ledger.current(
        effect.logicalItemLocatorCid(claim.locator)), undefined);
    }
  });

test('a previously dispatched row prevents a partial collection retry',
  async t => {
    const root = await fixture(t);
    const ledger = open(root);
    t.after(() => ledger.close());
    const claims = batchClaims();
    assert.equal(ledger.claimDispatch(claims[0]).claimed, true);
    assert.deepEqual(ledger.claimDispatchBatch(claims), {
      claimed: false, actions: [3, 0],
    });
    assert.equal(ledger.current(
      effect.logicalItemLocatorCid(claims[1].locator)), undefined);
  });

test('collection claim reserves aggregate entry capacity before any row',
  async t => {
    const root = await fixture(t);
    const ledger = openEffectLedger({moon, root, authorityScopeCid,
      callerRequestId: 'request-1', maxEntryBytes: 4096, maxEntries: 3});
    t.after(() => ledger.close());
    const claims = batchClaims();
    assert.throws(() => ledger.claimDispatchBatch(claims),
      {code: 'EffectLedgerCapacityExceeded'});
    for (const claim of claims) {
      assert.equal(ledger.current(
        effect.logicalItemLocatorCid(claim.locator)), undefined);
    }
    assert.equal(ledger.claimDispatchBatch([claims[0]]).claimed, true);
  });

test('MoonBit-issued prepared and dispatching entries are durable before use',
  async t => {
    const root = await fixture(t);
    const ledger = open(root);
    t.after(() => ledger.close());
    const scope = effect.logicalRequestScope(authorityScopeCid,
      'request-1', 32);
    const key = effect.dispatchKey(scope, cid('b'), '"row-1"', 32, 8, 3);
    const locator = effect.logicalItemLocator(scope, 'program-1', 'node-1',
      'WriteOne', '{"row":"record-1"}', 64, 128, 8, 3);
    const basis = effect.ledgerBasis(scope, locator, key,
      cid('c'), cid('d'), cid('e'), cid('f'), cid('0'), 'unavailable',
      cid('1'), cid('2'));
    assert.equal(effect.recoveryActionFromEntry(
      locator, cid('e'), key, cid('f'),
      ledger.currentAdmitted(effect.logicalItemLocatorCid(locator)), false), 0);
    const prepared = effect.issuePreparedLedgerEntry(basis, 4096, 64, 3);
    assert.equal(ledger.append(effect.ledgerEntryWire(prepared)).created, true);
    assert.equal(effect.ledgerEntryAdmitsDispatch(prepared, scope, locator,
      key, cid('f')), false);
    const dispatching = effect.issueNextLedgerEntry(prepared, 'dispatching',
      '', 4096, 64, 3);
    assert.equal(ledger.append(effect.ledgerEntryWire(dispatching)).created,
      true);
    assert.equal(effect.ledgerEntryAdmitsDispatch(dispatching, scope, locator,
      key, cid('f')), true);
    assert.equal(effect.ledgerEntryAdmitsDispatch(dispatching, scope, locator,
      key, cid('9')), false);
    const response = {
      dispatching, scope, locator, key,
      canonicalRequestCid: cid('f'),
      credentialUseCid: cid('a'),
      statusCode: 201,
      responseBytes: Buffer.from('{"success":true}'),
    };
    assert.equal(ledger.recordResponse(response).created, true);
    assert.equal(ledger.recordResponse(response).created, false);
    assert.throws(() => ledger.recordResponse({
      ...response, canonicalRequestCid: cid('9'),
    }), {code: 'EffectDispatchBindingMismatch'});
    ledger.close();
    const restarted = open(root);
    t.after(() => restarted.close());
    assert.equal(restarted.current(effect.logicalItemLocatorCid(locator)).entryCid,
      effect.ledgerEntryCid(dispatching));
    assert.equal(effect.recoveryActionFromEntry(
      locator, cid('e'), key, cid('f'),
      restarted.currentAdmitted(effect.logicalItemLocatorCid(locator)), false),
    3);
    assert.deepEqual(restarted.response(effect.ledgerEntryCid(dispatching))
      .responseBytes, response.responseBytes);
  });

test('exact Effect dispatch claim sends once and restart requires reconciliation',
  async t => {
    const root = await fixture(t);
    const first = open(root);
    const second = open(root);
    t.after(() => first.close());
    t.after(() => second.close());
    const scope = effect.logicalRequestScope(authorityScopeCid,
      'request-1', 32);
    const key = effect.dispatchKey(scope, cid('b'), '"row-1"', 32, 8, 3);
    const locator = effect.logicalItemLocator(scope, 'program-1', 'node-1',
      'WriteOne', '{"row":"record-1"}', 64, 128, 8, 3);
    const basis = effect.ledgerBasis(scope, locator, key,
      cid('c'), cid('d'), cid('e'), cid('f'), cid('0'), 'unavailable',
      cid('1'), cid('2'));
    const claim = {
      scope, locator, key, basis,
      intentFingerprintCid: cid('e'),
      canonicalRequestCid: cid('f'),
    };
    const initial = first.claimDispatch(claim);
    assert.equal(initial.claimed, true);
    assert.equal(initial.action, 1);
    assert.equal(second.claimDispatch(claim).claimed, false);
    assert.equal(second.claimDispatch(claim).action, 3);
    assert.equal(first.current(effect.logicalItemLocatorCid(locator)).revision,
      2);
    const unknown = effect.issueNextLedgerEntry(initial.dispatching,
      'unknown', '', 4096, 64, 3);
    assert.equal(first.append(effect.ledgerEntryWire(unknown)).created, true);
    first.recordResponse({
      dispatching: initial.dispatching,
      scope, locator, key, canonicalRequestCid: cid('f'),
      credentialUseCid: cid('a'), statusCode: 201,
      responseBytes: Buffer.from('{"success":true}'),
    });
    first.close();
    const restarted = open(root);
    t.after(() => restarted.close());
    const afterRestart = restarted.claimDispatch(claim);
    assert.equal(afterRestart.claimed, false);
    assert.equal(afterRestart.action, 4);
    assert.deepEqual(restarted.response(
      effect.ledgerEntryCid(initial.dispatching)).responseBytes,
      Buffer.from('{"success":true}'));
    const changedBasis = effect.ledgerBasis(scope, locator, key,
      cid('9'), cid('d'), cid('e'), cid('f'), cid('0'), 'unavailable',
      cid('1'), cid('2'));
    assert.throws(() => restarted.claimDispatch({
      ...claim, basis: changedBasis,
    }), {code: 'EffectLedgerIntentConflict'});
  });

test('MoonBit-admitted Effect facts survive restart without duplicate send',
  async t => {
    const root = await fixture(t);
    const ledger = open(root);
    t.after(() => ledger.close());
    assert.equal(ledger.scopeCid, scopeCid);
    const prepared = entry();
    const dispatching = entry({state: 'dispatching', fence: 2, attempt: 1,
      prior: prepared.cid});
    const applied = entry({state: 'applied', fence: 3, attempt: 1,
      prior: dispatching.cid, outcome: cid('c')});
    assert.equal(ledger.append(prepared.wire).created, true);
    assert.equal(ledger.append(prepared.wire).created, false);
    assert.equal(ledger.append(dispatching.wire).created, true);
    assert.equal(ledger.append(applied.wire).created, true);
    ledger.close();
    const reopened = open(root);
    t.after(() => reopened.close());
    assert.equal(reopened.current(cid('5')).entryCid, applied.cid);
    assert.deepEqual(reopened.history(cid('5'), 3).map(row => row.entryCid),
      [prepared.cid, dispatching.cid, applied.cid]);
    assert.equal(reopened.append(applied.wire).created, false);
    assert.throws(() => reopened.append(dispatching.wire), {
      code: 'EffectLedgerInvalidTransition',
    });
  });

test('Effect ledger rejects altered intent before CAS and preserves head',
  async t => {
    const root = await fixture(t);
    const ledger = open(root);
    t.after(() => ledger.close());
    const prepared = entry();
    ledger.append(prepared.wire);
    const changed = entry({state: 'dispatching', fence: 2, attempt: 1,
      prior: prepared.cid, fingerprint: cid('f')});
    assert.throws(() => ledger.append(changed.wire), {
      code: 'EffectLedgerInvalidTransition',
    });
    assert.equal(ledger.current(cid('5')).entryCid, prepared.cid);
    const malformed = prepared.wire.replace(cid('4'), cid('f'));
    assert.throws(() => ledger.append(malformed));
    assert.equal(ledger.current(cid('5')).entryCid, prepared.cid);
  });

test('one authority Store does not expose another logical request',
  async t => {
    const root = await fixture(t);
    const original = open(root);
    const other = openEffectLedger({moon, root, authorityScopeCid,
      callerRequestId: 'request-2', maxEntryBytes: 4096});
    t.after(() => original.close());
    t.after(() => other.close());
    const prepared = entry();
    original.append(prepared.wire);
    assert.throws(() => other.current(cid('5')), {
      code: 'EffectLedgerScopeMismatch',
    });
    assert.throws(() => other.append(prepared.wire), {
      code: 'EffectLedgerScopeMismatch',
    });
  });
