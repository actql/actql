import assert from 'node:assert/strict';
import test from 'node:test';
import * as moon from
  '../../_build/js/release/build/remote_coordinator_abi/remote_coordinator_abi.js';
import {checked} from './runtime-result.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;

function dispatch(dispatchId = 'dispatch-a') {
  return checked(moon.coordinatorPrepareDispatch(
    'coordinator-a', cid('0'), 'task-a', 1, dispatchId, 'site-a', 1,
    cid('a'), 'local', 'local/1', 'strategy/1', cid('1'), cid('2'),
    cid('3'), cid('b'), cid('4'),
  ));
}

test('common Coordinator owner survives durable dispatch recovery', () => {
  const journal = checked(moon.coordinatorCreateJournal('coordinator-a'));
  const request = dispatch();
  const requestCid = moon.coordinatorDispatchCid(request);
  const admission = checked(moon.coordinatorPrepareIntent(journal, request));
  const initialBody = checked(moon.coordinatorAdmissionDurableJson(admission));
  const initial = checked(moon.coordinatorAdmitDurableJson(initialBody));
  assert.equal(moon.coordinatorDurableRevision(initial), 0);
  assert.equal(moon.coordinatorDurableDispatchCid(initial), requestCid);

  // A physical adapter must durably persist these exact bytes before commit.
  let persisted = initialBody;
  const record = checked(moon.coordinatorCommitIntent(admission));
  const unknown = checked(moon.coordinatorPrepareUnknown(record));
  assert.equal(moon.coordinatorTransitionExpectedRevision(unknown), 0);
  const unknownBody = checked(
    moon.coordinatorTransitionDurableJson(initial, unknown));
  assert.equal(JSON.parse(unknownBody).revision, 1);
  persisted = unknownBody;
  checked(moon.coordinatorCommitTransition(unknown));

  const restarted = checked(moon.coordinatorCreateJournal('coordinator-a'));
  const durable = checked(moon.coordinatorAdmitDurableJson(persisted));
  const restored = checked(moon.coordinatorRestoreDurable(restarted, durable));
  assert.equal(moon.coordinatorDurableRevision(durable), 1);
  assert.equal(moon.coordinatorDurableDispatchCid(durable), requestCid);
  assert.deepEqual(moon.coordinatorRecordStateCodes(restored),
    moon.coordinatorRecordStateCodes(record));

  const duplicate = checked(moon.coordinatorPrepareIntent(restarted, request));
  assert.equal(checked(moon.coordinatorCommitIntent(duplicate)), restored);
  assert.throws(() => checked(moon.coordinatorPrepareIntent(
    restarted, dispatch('dispatch-other'))),
  {code: 'MoonBitHostFailure'});
  assert.throws(() => checked(moon.coordinatorAdmitDurableJson(
    `${persisted} `)), {code: 'MoonBitHostFailure'});
});
