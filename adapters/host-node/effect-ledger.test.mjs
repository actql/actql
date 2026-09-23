import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
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
