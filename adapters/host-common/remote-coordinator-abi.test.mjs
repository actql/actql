import assert from 'node:assert/strict';
import test from 'node:test';
import * as moon from
  '../../_build/js/release/build/remote_coordinator_abi/remote_coordinator_abi.js';
import {checked} from './runtime-result.mjs';
import * as bridge from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {acceptedSiteOutput, admitDurableJson, admitPollNotSeen,
  issueOutputPlanPollJson, pollQueryJson, pollReleaseJson} from
  '../../packages/coordinator-core/index.mjs';
import {runtimeCore} from './runtime-core.mjs';

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
  assert.deepEqual(moon.coordinatorDispatchRoute(request).slice(0, 4),
    ['coordinator-a', 'site-a', '1', 'dispatch-a']);
  assert.equal(JSON.parse(checked(moon.coordinatorPollQueryJson(request)))
    .dispatch_request_cid, requestCid);
  assert.throws(() => checked(moon.coordinatorPollDispatchJson(
    request, '{}', 1024)), {code: 'MoonBitHostFailure'});
  const admission = checked(moon.coordinatorPrepareIntent(journal, request));
  assert.equal(moon.coordinatorIntentIsNew(admission), true);
  const initialBody = checked(moon.coordinatorAdmissionDurableJson(admission));
  const initial = checked(moon.coordinatorAdmitDurableJson(initialBody));
  assert.equal(acceptedSiteOutput(admitDurableJson(initialBody)), undefined);
  const outputInput = {
    storeAuthorityCid: cid('5'), publicationAttemptCid: cid('6'),
    resultDefinitionCid: cid('7'), orderingEvidenceCid: cid('8'),
    coordinatorAuthority: 'coordinator-a', transferAttempt: 'transfer-a',
    transferRoute: 'direct', destinationSiteKey: 'store-a',
    destinationSiteGeneration: 1, transferMaxBytes: 1048576,
    transferExpiresUnixMs: 2000000000000,
    sourceGrantCid: cid('9'), destinationGrantCid: cid('a'),
    routeCapabilityCid: cid('b'), transferOrigin: 'https://store.example',
  };
  assert.throws(() => issueOutputPlanPollJson(initial, outputInput),
    {code: 'CoordinatorOwnerRejected'});
  assert.throws(() => issueOutputPlanPollJson(initial,
    {...outputInput, transferMaxBytes: 0}),
  /InvalidCoordinatorOutputIntentInput/u);
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
  assert.equal(moon.coordinatorIntentIsNew(duplicate), false);
  assert.equal(checked(moon.coordinatorCommitIntent(duplicate)), restored);
  const reply = JSON.stringify({
    version: 'actql-remote-dispatch-response/0.1',
    dispatch_request_cid: requestCid,
    revision: 2,
    state: [3, 2, 0, 1, 0],
  });
  const response = checked(moon.coordinatorAdmitResponseJson(
    reply, moon.coordinatorDurableRequest(durable), false));
  const observed = checked(moon.coordinatorPrepareResponseObservation(
    restored, response));
  assert.equal(moon.coordinatorTransitionExpectedRevision(observed), 1);
  const observedBody = checked(moon.coordinatorResponseDurableJson(
    durable, observed, response));
  assert.equal(JSON.parse(observedBody).revision, 2);
  checked(moon.coordinatorCommitTransition(observed));
  const observedDurable = checked(moon.coordinatorAdmitDurableJson(
    observedBody));
  const finalJournal = checked(moon.coordinatorCreateJournal('coordinator-a'));
  const finalRecord = checked(moon.coordinatorRestoreDurable(
    finalJournal, observedDurable));
  assert.deepEqual(moon.coordinatorRecordStateCodes(finalRecord),
    moon.coordinatorRecordStateCodes(restored));
  assert.throws(() => checked(moon.coordinatorAdmitResponseJson(
    reply.replace(requestCid, `sha256:${'f'.repeat(64)}`),
    request, false)), {code: 'MoonBitHostFailure'});
  assert.throws(() => checked(moon.coordinatorAdmitResponseJson(
    reply, request, true)), {code: 'MoonBitHostFailure'});
  assert.throws(() => checked(moon.coordinatorPrepareIntent(
    restarted, dispatch('dispatch-other'))),
  {code: 'MoonBitHostFailure'});
  assert.throws(() => checked(moon.coordinatorAdmitDurableJson(
    `${persisted} `)), {code: 'MoonBitHostFailure'});
});

test('coordinator-core exposes the common release and not-seen owners unchanged',
  () => {
    const request = dispatch('dispatch-release');
    const requestCid = moon.coordinatorDispatchCid(request);
    const release = JSON.parse(pollReleaseJson(request));
    assert.deepEqual(Object.keys(release).sort(),
      ['dispatch_request_cid', 'request_json', 'version']);
    assert.equal(release.version, 'actql-remote-poll-release/0.1');
    assert.equal(release.dispatch_request_cid, requestCid);
    // The same request body as the query of that dispatch.
    assert.equal(release.request_json,
      JSON.parse(pollQueryJson(request)).request_json);

    const notSeen = cidValue => JSON.stringify({
      dispatch_request_cid: cidValue,
      version: 'actql-remote-dispatch-not-seen/0.1'});
    assert.equal(admitPollNotSeen(notSeen(requestCid), request), true);
    const other = moon.coordinatorDispatchCid(dispatch('dispatch-other'));
    for (const body of [notSeen(other),
      JSON.stringify({dispatch_request_cid: requestCid,
        version: 'actql-remote-poll-query/0.1'}),
      JSON.stringify({dispatch_request_cid: requestCid, extra: 1,
        version: 'actql-remote-dispatch-not-seen/0.1'}),
      'not json']) {
      assert.throws(() => admitPollNotSeen(body, request),
        {code: 'CoordinatorOwnerRejected'});
    }

    // The same bytes and decisions as the existing runtime-core owner.
    const site = runtimeCore(bridge).remoteSiteControl;
    assert.equal(pollReleaseJson(request), site.pollReleaseJson(request));
    assert.equal(site.admitPollNotSeen(notSeen(requestCid), request), true);
    assert.throws(() => site.admitPollNotSeen(notSeen(other), request));
    assert.equal(admitPollNotSeen(site.pollNotSeenJson(request), request), true);
  });
