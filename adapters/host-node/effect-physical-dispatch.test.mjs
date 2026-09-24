import assert from 'node:assert/strict';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {openEffectLedger} from './effect-ledger.mjs';
import {openSqliteEffectLedger} from './sqlite-effect-ledger.mjs';
import {
  captureClaimedEffectCollectionResponse,
  captureClaimedEffectResponse,
} from './effect-physical-dispatch.mjs';
import {readAuthorizedEffectResponse,
  readAuthorizedEffectOutcomes,
  recoverProjectedEffectResponse} from './effect-response-recovery.mjs';

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
  return {root, open, claim: {scope, locator, key, basis,
    intentFingerprintCid: cid('e'), canonicalRequestCid}};
}

async function collectionFixture(t) {
  const {root, open} = await fixture(t);
  const scope = control.logicalRequestScope(authorityScopeCid,
    'request-1', 32);
  const claims = ['row-1', 'row-2'].map(row => {
    const key = control.dispatchKey(scope, cid('b'),
      JSON.stringify(row), 32, 8, 3);
    const locator = control.logicalItemLocator(scope, 'program-1',
      'node-1', 'WriteOne', JSON.stringify({row}), 64, 128, 8, 3);
    const canonicalRequestCid = cid('f');
    const basis = control.ledgerBasis(scope, locator, key,
      cid('c'), cid('d'), cid('e'), canonicalRequestCid, cid('0'),
      'unavailable', cid('1'), cid('2'));
    return {scope, locator, key, basis,
      intentFingerprintCid: cid('e'), canonicalRequestCid};
  });
  return {root, open, claims};
}

test('exact single claim reopens physical outcome custody without a send',
  async t => {
    const {root, open, claim} = await fixture(t);
    const first = open();
    let sends = 0;
    const sent = await captureClaimedEffectResponse({
      ledger: first, claim, requestCid: claim.canonicalRequestCid,
      execute: async () => {
        sends += 1;
        return {observation: {useCid: cid('4'), statusCode: 201,
          body: Buffer.from('{"success":true}')}};
      },
    });
    assert.equal(first.readClaimedOutcome(claim), undefined);
    const physical = openSqliteEffectLedger(root, {authorityScopeCid});
    try {
      physical.recordOutcome({
        logicalRequestScopeCid: first.scopeCid,
        logicalItemLocatorCid: control.logicalItemLocatorCid(claim.locator),
        dispatchEntryCid: control.ledgerEntryCid(sent.ownership.dispatching),
        responsePhysicalSha256: sent.response.responsePhysicalSha256,
        outcomeCid: cid('5'),
        outcomeJson: '{"result":{"record_id":"a001"},"state":"applied"}',
      });
    } finally {
      physical.close();
    }
    const applied = control.issueNextLedgerEntry(sent.ownership.dispatching,
      'applied', cid('5'), 4096, 64, 4);
    first.append(control.ledgerEntryWire(applied));
    first.close();
    const reopened = open();
    t.after(() => reopened.close());
    const outcome = reopened.readClaimedOutcome(claim);
    assert.equal(outcome.outcomeCid, cid('5'));
    assert.equal(reopened.readClaimedResponse(claim).dispatchEntryCid,
      control.ledgerEntryCid(sent.ownership.dispatching));
    assert.equal(outcome.responsePhysicalSha256,
      sent.response.responsePhysicalSha256);
    const authorized = await readAuthorizedEffectOutcomes({
      ledger: reopened, claims: claim, commonMoon: moon,
      expectedRequestCid: claim.canonicalRequestCid,
      authorizeEvidenceRead: () => true,
    });
    assert.equal(authorized.outcomes.outcomeCid, cid('5'));
    const mutableClaim = {...claim};
    let releaseRead;
    const readGate = new Promise(resolve => { releaseRead = resolve; });
    const pendingRead = readAuthorizedEffectOutcomes({
      ledger: reopened, claims: mutableClaim, commonMoon: moon,
      expectedRequestCid: claim.canonicalRequestCid,
      authorizeEvidenceRead: async () => {
        await readGate;
        return true;
      },
    });
    mutableClaim.canonicalRequestCid = cid('9');
    releaseRead();
    assert.equal((await pendingRead).outcomes.outcomeCid, cid('5'));
    await assert.rejects(readAuthorizedEffectOutcomes({
      ledger: reopened, claims: claim, commonMoon: moon,
      expectedRequestCid: claim.canonicalRequestCid,
      authorizeEvidenceRead: () => false,
    }), {code: 'EffectEvidenceAccessDenied'});
    assert.throws(() => reopened.readClaimedOutcome({
      ...claim, canonicalRequestCid: cid('9'),
    }), {code: 'EffectDispatchBindingMismatch'});
    const retry = await captureClaimedEffectResponse({
      ledger: reopened, claim, requestCid: claim.canonicalRequestCid,
      execute: async () => { sends += 1; },
    });
    assert.equal(retry.claimed, false);
    assert.equal(sends, 1);
  });

test('exact Collections claim reopens distinct row outcome custody',
  async t => {
    const {root, open, claims} = await collectionFixture(t);
    const first = open();
    let sends = 0;
    const sent = await captureClaimedEffectCollectionResponse({
      ledger: first, claims, requestCid: claims[0].canonicalRequestCid,
      execute: async () => {
        sends += 1;
        return {observation: {useCid: cid('4'), statusCode: 200,
          body: Buffer.from('[{"success":true},{"success":false}]')}};
      },
    });
    assert.deepEqual(first.readClaimedBatchOutcomes(claims),
      [undefined, undefined]);
    const stored = first.readClaimedBatchResponse(claims);
    const physical = openSqliteEffectLedger(root, {authorityScopeCid});
    try {
      for (let index = 0; index < claims.length; index++) {
        physical.recordOutcome({
          logicalRequestScopeCid: first.scopeCid,
          logicalItemLocatorCid: control.logicalItemLocatorCid(
            claims[index].locator),
          dispatchEntryCid: control.ledgerEntryCid(
            sent.ownership.dispatching[index]),
          responsePhysicalSha256: stored.responsePhysicalSha256,
          outcomeCid: cid(index === 0 ? '5' : '6'),
          outcomeJson: index === 0
            ? '{"result":{"record_id":"a001"},"state":"applied"}'
            : '{"error":{"code":"INVALID_FIELD","message":"Bad field"},"state":"failed"}',
        });
      }
    } finally {
      physical.close();
    }
    for (let index = 0; index < claims.length; index++) {
      const terminal = control.issueNextLedgerEntry(
        sent.ownership.dispatching[index],
        index === 0 ? 'applied' : 'failed',
        cid(index === 0 ? '5' : '6'), 4096, 64, 4);
      first.append(control.ledgerEntryWire(terminal));
    }
    first.close();
    const reopened = open();
    t.after(() => reopened.close());
    assert.deepEqual(reopened.readClaimedBatchOutcomes(claims)
      .map(outcome => outcome.outcomeCid), [cid('5'), cid('6')]);
    assert.equal(reopened.readClaimedBatchResponse(claims).dispatchEntryCid,
      control.ledgerEntryCid(sent.ownership.dispatching[0]));
    const authorized = await readAuthorizedEffectOutcomes({
      ledger: reopened, claims, batch: true, commonMoon: moon,
      expectedRequestCid: claims[0].canonicalRequestCid,
      authorizeEvidenceRead: () => true,
    });
    assert.deepEqual(authorized.outcomes.map(outcome => outcome.outcomeCid),
      [cid('5'), cid('6')]);
    const mutableClaims = [...claims];
    let releaseRead;
    const readGate = new Promise(resolve => { releaseRead = resolve; });
    const pendingRead = readAuthorizedEffectOutcomes({
      ledger: reopened, claims: mutableClaims, batch: true, commonMoon: moon,
      expectedRequestCid: claims[0].canonicalRequestCid,
      authorizeEvidenceRead: async () => {
        await readGate;
        return true;
      },
    });
    mutableClaims.reverse();
    releaseRead();
    assert.deepEqual((await pendingRead).outcomes.map(outcome =>
      outcome.outcomeCid), [cid('5'), cid('6')]);
    assert.throws(() => reopened.readClaimedBatchOutcomes(
      [...claims].reverse()), {code: 'EffectCollectionResponseBindingMismatch'});
    const retry = await captureClaimedEffectCollectionResponse({
      ledger: reopened, claims, requestCid: claims[0].canonicalRequestCid,
      execute: async () => { sends += 1; },
    });
    assert.equal(retry.claimed, false);
    assert.equal(sends, 1);
  });

test('single raw response is durable before provider projection', async t => {
  const {open, claim} = await fixture(t);
  const first = open();
  t.after(() => first.close());
  let sends = 0;
  const body = Buffer.from('{"success":true}');
  const execute = async () => {
    sends += 1;
    return {observation: {useCid: cid('4'), statusCode: 201, body}};
  };
  await assert.rejects(captureClaimedEffectResponse({
    ledger: first, claim, requestCid: cid('f'), execute,
    projectStored: (...args) => {
      assert.equal(args.length, 1);
      const [stored] = args;
      assert.deepEqual(stored.responseBytes, body);
      throw new Error('projection failed');
    },
  }), /projection failed/u);
  first.close();
  const restarted = open();
  t.after(() => restarted.close());
  const stored = restarted.readClaimedResponse(claim);
  assert.equal(stored.statusCode, 201);
  assert.deepEqual(stored.responseBytes, body);
  const retry = await captureClaimedEffectResponse({
    ledger: restarted, claim, requestCid: cid('f'), execute,
  });
  assert.equal(retry.claimed, false);
  assert.equal(sends, 1);
});

test('shared evidence read binds authorization before stored response access',
  async t => {
    const {open, claim} = await fixture(t);
    const ledger = open();
    t.after(() => ledger.close());
    const body = Buffer.from('{"success":true}');
    await captureClaimedEffectResponse({
      ledger, claim, requestCid: cid('f'),
      execute: async () => ({observation: {
        useCid: cid('4'), statusCode: 201, body,
      }}),
    });
    const observed = await readAuthorizedEffectResponse({
      ledger, claims: claim, commonMoon: moon,
      expectedRequestCid: cid('f'), providerBinding: {orgId: 'org-a'},
      authorizeEvidenceRead: binding => {
        assert.equal(binding.logicalRequestScopeCid, ledger.scopeCid);
        assert.equal(binding.canonicalRequestCid, cid('f'));
        assert.equal(binding.orgId, 'org-a');
        return true;
      },
    });
    assert.deepEqual(observed.stored.responseBytes, body);
    await assert.rejects(readAuthorizedEffectResponse({
      ledger, claims: claim, commonMoon: moon,
      expectedRequestCid: cid('f'),
      authorizeEvidenceRead: () => false,
    }), {code: 'EffectEvidenceAccessDenied'});
    await assert.rejects(readAuthorizedEffectResponse({
      ledger, claims: claim, commonMoon: moon,
      expectedRequestCid: cid('1'),
      authorizeEvidenceRead: () => true,
    }), {code: 'ForeignEffectResponse'});
  });

test('collection raw response is durable before provider projection',
  async t => {
    const {open, claims} = await collectionFixture(t);
    const first = open();
    t.after(() => first.close());
    let sends = 0;
    const body = Buffer.from('[{"success":true},{"success":false}]');
    const execute = async () => {
      sends += 1;
      return {observation: {useCid: cid('4'), statusCode: 200, body}};
    };
    await assert.rejects(captureClaimedEffectCollectionResponse({
      ledger: first, claims, requestCid: cid('f'), execute,
      projectStored: (...args) => {
        assert.equal(args.length, 1);
        const [stored] = args;
        assert.deepEqual(stored.responseBytes, body);
        throw new Error('projection failed');
      },
    }), /projection failed/u);
    first.close();
    const restarted = open();
    t.after(() => restarted.close());
    const stored = restarted.readClaimedBatchResponse(claims);
    assert.equal(stored.statusCode, 200);
    assert.deepEqual(stored.responseBytes, body);
    const retry = await captureClaimedEffectCollectionResponse({
      ledger: restarted, claims, requestCid: cid('f'), execute,
    });
    assert.equal(retry.claimed, false);
    assert.equal(sends, 1);
  });

test('one collection response covers every row without duplicate send',
  async t => {
    const {open, claims} = await collectionFixture(t);
    const first = open();
    const concurrent = open();
    t.after(() => first.close());
    t.after(() => concurrent.close());
    let calls = 0;
    const body = Buffer.from('[{"success":true},{"success":false}]');
    const execute = async () => {
      calls += 1;
      return {kind: 'unclassified-response', observation: {
        useCid: cid('4'), statusCode: 200, body,
      }};
    };
    const [sent, joined] = await Promise.all([
      captureClaimedEffectCollectionResponse({ledger: first,
        claims, requestCid: cid('f'), execute}),
      captureClaimedEffectCollectionResponse({ledger: concurrent,
        claims, requestCid: cid('f'), execute}),
    ]);
    assert.equal(sent.claimed, true);
    assert.equal(joined.claimed, false);
    assert.equal(calls, 1);
    first.close();
    concurrent.close();
    const restarted = open();
    t.after(() => restarted.close());
    assert.throws(() => restarted.readClaimedResponse(claims[0]),
      {code: 'EffectResponseKindMismatch'});
    const retry = await captureClaimedEffectCollectionResponse({
      ledger: restarted, claims, requestCid: cid('f'), execute,
    });
    assert.equal(retry.claimed, false);
    assert.equal(calls, 1);
    for (const dispatching of sent.ownership.dispatching) {
      assert.deepEqual(restarted.response(
        control.ledgerEntryCid(dispatching)).responseBytes, body);
    }
  });

test('a lost collection response leaves all rows possible-dispatch',
  async t => {
    const {open, claims} = await collectionFixture(t);
    const first = open();
    t.after(() => first.close());
    let calls = 0;
    const execute = async () => {
      calls += 1;
      throw new Error('response lost');
    };
    await assert.rejects(captureClaimedEffectCollectionResponse({
      ledger: first, claims, requestCid: cid('f'), execute,
    }), /response lost/);
    first.close();
    const restarted = open();
    t.after(() => restarted.close());
    const retry = await captureClaimedEffectCollectionResponse({
      ledger: restarted, claims, requestCid: cid('f'), execute,
    });
    assert.equal(retry.claimed, false);
    assert.deepEqual(retry.ownership.actions, [3, 3]);
    assert.equal(calls, 1);
    for (const claim of claims) {
      assert.equal(restarted.current(
        control.logicalItemLocatorCid(claim.locator)).revision, 2);
    }
  });

test('foreign collection request identity fails before any row claim',
  async t => {
    const {open, claims} = await collectionFixture(t);
    const ledger = open();
    t.after(() => ledger.close());
    let calls = 0;
    await assert.rejects(captureClaimedEffectCollectionResponse({
      ledger, claims, requestCid: cid('9'), execute: async () => {
        calls += 1;
      },
    }), {code: 'InvalidEffectPhysicalDispatch'});
    assert.equal(calls, 0);
    for (const claim of claims) {
      assert.equal(ledger.current(
        control.logicalItemLocatorCid(claim.locator)), undefined);
    }
  });

test('collection custody keeps original row binding across caller edits',
  async t => {
    const {open, claims} = await collectionFixture(t);
    const original = claims.map(claim => ({...claim}));
    const ledger = open();
    t.after(() => ledger.close());
    let entered;
    let release;
    const started = new Promise(resolve => { entered = resolve; });
    const gate = new Promise(resolve => { release = resolve; });
    let sends = 0;
    const body = Buffer.from('[{"success":true},{"success":false}]');
    const execute = async () => {
      sends += 1;
      entered();
      await gate;
      return {observation: {useCid: cid('4'), statusCode: 200, body}};
    };
    const pending = captureClaimedEffectCollectionResponse({
      ledger, claims, requestCid: cid('f'), execute,
    });
    await started;
    claims.reverse();
    claims.splice(0, 1);
    claims[0] = {...claims[0], canonicalRequestCid: cid('9')};
    release();
    const sent = await pending;
    assert.equal(sent.claimed, true);
    assert.equal(sends, 1);
    const stored = ledger.response(control.ledgerEntryCid(
      sent.ownership.dispatching[0]));
    assert.deepEqual(stored.batchMembers.map(member =>
      member.logicalItemLocatorCid), original.map(claim =>
      control.logicalItemLocatorCid(claim.locator)));
    ledger.close();
    const restarted = open();
    t.after(() => restarted.close());
    const retry = await captureClaimedEffectCollectionResponse({
      ledger: restarted, claims: original, requestCid: cid('f'), execute,
    });
    assert.equal(retry.claimed, false);
    assert.deepEqual(retry.ownership.actions, [3, 3]);
    assert.equal(sends, 1);
  });

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

test('single custody keeps original binding across caller edits',
  async t => {
    const {open, claim} = await fixture(t);
    const original = {...claim};
    const ledger = open();
    t.after(() => ledger.close());
    let entered;
    let release;
    const started = new Promise(resolve => { entered = resolve; });
    const gate = new Promise(resolve => { release = resolve; });
    let sends = 0;
    const execute = async () => {
      sends += 1;
      entered();
      await gate;
      return {observation: {useCid: cid('4'), statusCode: 201,
        body: Buffer.from('{"success":true}')}};
    };
    const pending = captureClaimedEffectResponse({
      ledger, claim, requestCid: cid('f'), execute,
    });
    await started;
    claim.canonicalRequestCid = cid('9');
    claim.scope = control.logicalRequestScope(authorityScopeCid,
      'foreign-request', 32);
    release();
    const sent = await pending;
    assert.equal(sent.claimed, true);
    assert.equal(sends, 1);
    assert.deepEqual(sent.response.responseBytes,
      Buffer.from('{"success":true}'));
    ledger.close();
    const restarted = open();
    t.after(() => restarted.close());
    const retry = await captureClaimedEffectResponse({
      ledger: restarted, claim: original, requestCid: cid('f'), execute,
    });
    assert.equal(retry.claimed, false);
    assert.equal(retry.ownership.action, 3);
    assert.equal(sends, 1);
  });

test('read-only recovery checks the exact durable claim without sending',
  async t => {
    const {open, claim} = await fixture(t);
    const ledger = open();
    t.after(() => ledger.close());
    assert.equal(ledger.readClaimedResponse(claim), undefined);
    assert.equal(ledger.current(control.logicalItemLocatorCid(claim.locator)),
      undefined);
    let sends = 0;
    const sent = await captureClaimedEffectResponse({
      ledger, claim, requestCid: claim.canonicalRequestCid,
      execute: async () => {
        sends += 1;
        return {observation: {useCid: cid('4'), statusCode: 429,
          body: Buffer.from('[{"errorCode":"REQUEST_LIMIT_EXCEEDED"}]')}};
      },
    });
    assert.equal(sent.claimed, true);
    ledger.close();
    const restarted = open();
    t.after(() => restarted.close());
    const stored = restarted.readClaimedResponse(claim);
    assert.deepEqual(stored.responseBytes,
      Buffer.from('[{"errorCode":"REQUEST_LIMIT_EXCEEDED"}]'));
    assert.equal(sends, 1);
    assert.throws(() => restarted.readClaimedResponse({
      ...claim, canonicalRequestCid: cid('9'),
    }), {code: 'EffectDispatchBindingMismatch'});
    assert.throws(() => restarted.readClaimedResponse({
      ...claim, basis: control.ledgerBasis(claim.scope, claim.locator,
        claim.key, cid('c'), cid('d'), cid('e'), cid('9'), cid('0'),
        'unavailable', cid('1'), cid('2')),
    }), {code: 'EffectLedgerIntentConflict'});
    assert.equal(sends, 1);
  });

test('common recovery projects only an authorized stored response',
  async t => {
    const {open, claim} = await fixture(t);
    const first = open();
    t.after(() => first.close());
    let projections = 0;
    let sends = 0;
    const options = {
      claims: claim, commonMoon: moon,
      expectedRequestCid: claim.canonicalRequestCid,
      providerBinding: {providerAccount: 'account-a'},
      authorizeEvidenceRead: binding => {
        assert.equal(binding.providerAccount, 'account-a');
        return true;
      },
      projectStored: stored => {
        projections += 1;
        return stored.responseBytes.toString('utf8');
      },
    };
    assert.deepEqual(await recoverProjectedEffectResponse({
      ...options, ledger: first,
    }), {recovered: undefined});
    assert.equal(projections, 0);
    await captureClaimedEffectResponse({
      ledger: first, claim, requestCid: claim.canonicalRequestCid,
      execute: async () => {
        sends += 1;
        return {observation: {useCid: cid('4'), statusCode: 201,
          body: Buffer.from('{"success":true}')}};
      },
    });
    first.close();
    const restarted = open();
    t.after(() => restarted.close());
    await assert.rejects(recoverProjectedEffectResponse({
      ...options, ledger: restarted,
      authorizeEvidenceRead: () => false,
    }), {code: 'EffectEvidenceAccessDenied'});
    assert.equal(projections, 0);
    assert.deepEqual(await recoverProjectedEffectResponse({
      ...options, ledger: restarted,
    }), {recovered: '{"success":true}'});
    assert.equal(projections, 1);
    assert.equal(sends, 1);
  });
