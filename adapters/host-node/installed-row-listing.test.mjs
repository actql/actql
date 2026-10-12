import assert from 'node:assert/strict';
import test from 'node:test';
import {rowListingCallbacks} from './installed-row-listing.mjs';

const ok = value => ({$tag: 1, _0: value});

test('listing transport forwards exact tokens and original charged body to the common owner', async () => {
  const run = {}, charge = {};
  const body = Buffer.from('{"items":[],"request_token":"é/%2F","next_token":null}');
  const calls = [];
  let clock = 100;
  let polls = 0;
  const moon = {
    clientProgramRowSourceBeginListingRequest(owner, token, elapsed) {
      assert.equal(owner, run); calls.push(['request', token, elapsed]); return ok(true);
    },
    clientProgramRowSourceBeginListingPage(owner, received, elapsed, ticket) {
      assert.equal(owner, run); assert.equal(received, body); assert.equal(ticket, charge);
      calls.push(['page', elapsed]); return ok(true);
    },
    clientProgramRowSourceAdvanceListingPage(owner, quantum, elapsed) {
      assert.equal(owner, run); assert.equal(quantum, 64);
      calls.push(['poll', elapsed]);
      return ok(JSON.stringify(++polls === 1
        ? {status: 'continue', work: 64}
        : {status: 'complete', rows: 0, work: 1}));
    },
  };
  const listing = rowListingCallbacks({moon, run, now: () => clock,
    currentRead: async () => { calls.push(['authority']); }});
  clock = 103;
  await listing.beginRequest('é/%2F');
  clock = 108;
  assert.equal(await listing.consumePage(body, {charge}), 0);
  assert.deepEqual(calls, [
    ['authority'], ['request', 'é/%2F', 3n],
    ['authority'], ['page', 8n],
    ['authority'], ['poll', 8n], ['authority'], ['poll', 8n],
  ]);
  assert.ok(Object.isFrozen(listing));
});

test('listing transport rechecks cancellation after authority awaits and between polls', async () => {
  const controller = new AbortController();
  const reason = new Error('fixture cancellation');
  let requests = 0;
  const listing = rowListingCallbacks({run: {}, signal: controller.signal,
    currentRead: async () => controller.abort(reason),
    moon: {clientProgramRowSourceBeginListingRequest() { requests++; return ok(true); }},
  });
  await assert.rejects(listing.beginRequest(undefined), error => error === reason);
  assert.equal(requests, 0);

  const other = new AbortController();
  let polls = 0;
  let checks = 0;
  const mid = rowListingCallbacks({run: {}, signal: other.signal,
    currentRead: async () => { if (++checks === 3) other.abort(reason); },
    moon: {
      clientProgramRowSourceBeginListingPage: () => ok(true),
      clientProgramRowSourceAdvanceListingPage() {
        polls++; return ok('{"status":"continue","work":64}');
      },
    },
  });
  await assert.rejects(mid.consumePage(Buffer.from('fixture')), error => error === reason);
  assert.equal(polls, 1);
});

test('listing transport does not accept unknown progress or a driver completion surrogate', async () => {
  for (const result of [
    {status: 'unknown', work: 1}, {status: 'continue', work: 0},
    {status: 'continue', work: 65},
  ]) {
    const listing = rowListingCallbacks({run: {}, currentRead: async () => {}, moon: {
      clientProgramRowSourceBeginListingPage: () => ok(true),
      clientProgramRowSourceAdvanceListingPage: () => ok(JSON.stringify(result)),
    }});
    await assert.rejects(listing.consumePage(Buffer.from('fixture')),
      {code: 'InvalidRowListingProgress'});
  }
  const issue = {fixture: 'incomplete'};
  const listing = rowListingCallbacks({run: {}, currentRead: async () => {}, moon: {
    clientProgramRowSourceBeginListingPage: () => ({$tag: 0, _0: issue}),
    clientProgramRowSourceAdvanceListingPage() { assert.fail('refused envelope cannot poll'); },
  }});
  await assert.rejects(listing.consumePage(Buffer.from('fixture')),
    error => error.code === 'MoonBitHostFailure' && error.cause === issue);
});
