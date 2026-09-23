import assert from 'node:assert/strict';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {openEffectLedger} from './effect-ledger.mjs';
import {captureClaimedEffectResponse} from './effect-physical-dispatch.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const authorityScopeCid = cid('a');
const control = runtimeCore(moon).effectApplicationControl;

async function fixture(t) {
  const root = await mkdtemp(join(tmpdir(), 'actql-effect-physical-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const open = () => openEffectLedger({moon, root, authorityScopeCid,
    callerRequestId: 'request-1', maxEntryBytes: 4096});
  const scope = control.logicalRequestScope(authorityScopeCid,
    'request-1', 32);
  const key = control.dispatchKey(scope, cid('b'), '"row-1"', 32, 8, 3);
  const locator = control.logicalItemLocator(scope, 'program-1', 'node-1',
    'WriteOne', '{"row":"record-1"}', 64, 128, 8, 3);
  const canonicalRequestCid = cid('f');
  const basis = control.ledgerBasis(scope, locator, key,
    cid('c'), cid('d'), cid('e'), canonicalRequestCid, cid('0'),
    'unavailable', cid('1'), cid('2'));
  return {open, claim: {scope, locator, key, basis,
    intentFingerprintCid: cid('e'), canonicalRequestCid}};
}

test('one durable claim captures the physical response without resending',
  async t => {
    const {open, claim} = await fixture(t);
    const first = open();
    const concurrent = open();
    t.after(() => first.close());
    t.after(() => concurrent.close());
    let calls = 0;
    const execute = async () => {
      calls += 1;
      return {kind: 'unclassified-response', observation: {
        useCid: cid('4'), statusCode: 201,
        body: Buffer.from('{"success":true}'),
      }};
    };
    const [sent, joined] = await Promise.all([
      captureClaimedEffectResponse({ledger: first, claim,
        requestCid: claim.canonicalRequestCid, execute}),
      captureClaimedEffectResponse({ledger: concurrent, claim,
        requestCid: claim.canonicalRequestCid, execute}),
    ]);
    assert.equal(sent.claimed, true);
    assert.equal(joined.claimed, false);
    assert.equal(joined.ownership.action, 3);
    assert.equal(calls, 1);
    assert.deepEqual(sent.response.responseBytes,
      Buffer.from('{"success":true}'));
    first.close();
    concurrent.close();
    const restarted = open();
    t.after(() => restarted.close());
    const retry = await captureClaimedEffectResponse({ledger: restarted,
      claim, requestCid: claim.canonicalRequestCid, execute});
    assert.equal(retry.claimed, false);
    assert.equal(retry.ownership.action, 3);
    assert.deepEqual(retry.ownership.response.responseBytes,
      Buffer.from('{"success":true}'));
    assert.equal(calls, 1);
  });

test('a lost physical response remains possible dispatch after restart',
  async t => {
    const {open, claim} = await fixture(t);
    const first = open();
    t.after(() => first.close());
    let calls = 0;
    const execute = async () => {
      calls += 1;
      throw new Error('connection lost after send');
    };
    await assert.rejects(captureClaimedEffectResponse({ledger: first,
      claim, requestCid: claim.canonicalRequestCid, execute}),
    /connection lost after send/);
    first.close();
    const restarted = open();
    t.after(() => restarted.close());
    const retry = await captureClaimedEffectResponse({ledger: restarted,
      claim, requestCid: claim.canonicalRequestCid, execute});
    assert.equal(retry.claimed, false);
    assert.equal(retry.ownership.action, 3);
    assert.equal(retry.ownership.response, undefined);
    assert.equal(calls, 1);
  });

test('foreign request identity is rejected before a durable claim',
  async t => {
    const {open, claim} = await fixture(t);
    const ledger = open();
    t.after(() => ledger.close());
    let calls = 0;
    await assert.rejects(captureClaimedEffectResponse({ledger, claim,
      requestCid: cid('9'), execute: async () => { calls += 1; }}),
    {code: 'InvalidEffectPhysicalDispatch'});
    assert.equal(calls, 0);
    assert.equal(ledger.current(control.logicalItemLocatorCid(claim.locator)),
      undefined);
  });
