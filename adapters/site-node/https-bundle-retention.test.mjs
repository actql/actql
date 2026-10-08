import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {
  releaseRemoteDispatch,
  sendRemoteDispatch,
} from '../host-node/remote-site-client.mjs';
import {terminalStatus} from './https-agent-harness.mjs';
import {
  bundles, cid, control, digest, inputBindingBody, rawCustody,
  retentionFixture, runtime,
} from './fixtures/https-bundle-retention.mjs';

const observed = response => bundles.custodyResponseObservation(response);
const rejected = status => ({code: 'BundleRetentionRejected', status});

test('HTTPS retained preparation A still dispatches A after local selection of B',
  {timeout: 30_000}, async t => {
    const f = await retentionFixture(t);
    const [alpha, beta] = f.members;
    const preparedA = await f.prepare(alpha, {attemptId: 'prepare-a'});
    assert.equal(observed(await f.custody(preparedA, 'query')), 'unresolved');
    assert.equal(f.state(alpha)[2], '0');
    assert.equal(observed(await f.custody(preparedA, 'retain')), 'retained');
    let selected = preparedA;
    const acceptedA = await f.reload(selected);
    const originalBinding = bundles.holdBindingIdentity(acceptedA.binding);
    const preparedB = await f.prepare(beta, {
      setRevisionCid: cid('c'), attemptId: 'prepare-b',
    });
    assert.equal(observed(await f.custody(preparedB, 'retain')), 'retained');
    // This assignment exercises a consumer's pinned preparation. Cloud's
    // durable preparation/selection transaction and CAS remain untested here.
    selected = preparedB;
    assert.notEqual(alpha.siteKey, beta.siteKey);
    assert.notEqual(alpha.runtimeBundleCid, beta.runtimeBundleCid);
    for (const member of f.members) {
      assert.equal(bundles.identity(member.bundleStore.active(bundles).manifest),
        member.runtimeBundleCid);
      assert.deepEqual(f.state(member).slice(1), ['1', '1']);
    }
    const oldDispatch = f.dispatch(acceptedA, 'accepted-a-later');
    const newDispatch = f.dispatch(selected, 'selected-b-new');
    assert.equal(control.executionScope(oldDispatch)[2], alpha.runtimeBundleCid);
    assert.equal(control.executionScope(newDispatch)[2], beta.runtimeBundleCid);
    const crossedGrant = f.dispatch(acceptedA, 'crossed-member-grant', {
      grantCid: beta.operationCapabilityCid,
    });
    await assert.rejects(sendRemoteDispatch({
      ...f.tls(alpha), control, dispatch: crossedGrant, inputBindingBody,
    }), {code: 'RemoteSiteRejected', status: 409});
    assert.deepEqual(f.effects.providers, []);
    assert.deepEqual(f.effects.secrets, []);
    for (const [member, dispatch, output] of [
      [alpha, oldDispatch, '[8,9]\n'], [beta, newDispatch, '[14,21]\n'],
    ]) {
      const options = {...f.tls(member), control, dispatch, inputBindingBody};
      await sendRemoteDispatch(options);
      const completed = await terminalStatus(options);
      assert.deepEqual(completed.state, [3, 2, 0, 1, 0]);
      assert.equal(await readFile(f.outputPath(member), 'utf8'), output);
      assert.equal(f.state(member)[2], '2');
      await releaseRemoteDispatch(options);
      assert.equal(f.state(member)[2], '1');
    }
    assert.deepEqual(f.effects.providers, ['local-alpha', 'local-beta']);
    assert.deepEqual(f.effects.secrets, ['local-alpha', 'local-beta']);
    assert.equal(bundles.holdBindingIdentity(acceptedA.binding), originalBinding);
    assert.equal(observed(await f.custody(acceptedA, 'query')), 'retained');
    for (const prepared of [acceptedA, selected]) {
      assert.equal(observed(await f.custody(prepared, 'release')), 'fenced');
      assert.equal(f.state(prepared.member)[2], '0');
    }
  });

test('HTTPS custody requires mTLS, exact Site scope and current admission authority',
  {timeout: 30_000}, async t => {
    const f = await retentionFixture(t);
    const [alpha, beta] = f.members;
    const ownScope = f.scope(alpha);
    const ownQuery = bundles.prepareCustodyContextQuery(ownScope.distribution, ownScope.scope);
    const body = bundles.custodyRequestJson(ownQuery);
    const before = f.state(alpha);
    await assert.rejects(rawCustody(f, alpha, body, {cert: null, key: null}),
      error => /TLS|SSL|ECONNRESET|EPROTO/.test(error.code));
    assert.equal(await rawCustody(f, alpha, body, {
      cert: f.material.foreignCertificate, key: f.material.foreignKey,
    }), 404);
    assert.equal(alpha.seen.length, 0);
    const distribution = bundles.prepareDistribution([
      alpha.runtimeBundleCid, beta.runtimeBundleCid,
    ]);
    for (const [overrides, status] of [
      [{workspaceId: 'workspace-other'}, 400],
      [{environment: 'production'}, 400],
      [{authorityScopeCid: cid('d')}, 400],
      [{coordinatorAuthority: 'coordinator-other'}, 400],
      [{distribution, runtimeBundleCid: beta.runtimeBundleCid}, 400],
      [{siteKey: beta.siteKey}, 404],
      [{siteGeneration: 2}, 404],
    ]) {
      const value = f.scope(alpha, overrides);
      await assert.rejects(f.exchange(alpha,
        bundles.prepareCustodyContextQuery(value.distribution, value.scope)), rejected(status));
      assert.deepEqual(f.state(alpha), before);
    }
    assert.equal(await rawCustody(f, alpha, ' '.repeat(4097)), 400);
    const prepared = await f.prepare(alpha);
    assert.equal(observed(await f.custody(prepared, 'retain')), 'retained');
    const held = f.state(alpha);
    const foreignScope = f.scope(alpha, {workspaceId: 'workspace-other'});
    const ownBinding = bundles.holdBindingProjection(prepared.binding);
    const foreignBinding = bundles.prepareHoldBindingFromScope(
      foreignScope.scope, ownBinding[1], Number(ownBinding[11]),
    );
    for (const operation of ['retain', 'query', 'release']) {
      await assert.rejects(f.exchange(alpha, bundles.prepareCustodyRequest(
        foreignScope.distribution, foreignBinding, operation,
      )), rejected(400));
      assert.deepEqual(f.state(alpha), held);
    }
    // Revoking the existing authenticated Coordinator mapping cannot delete
    // its owned row or turn an unavailable query into absence.
    alpha.authorities.delete(f.material.coordinatorFingerprint);
    for (const operation of ['retain', 'query', 'release']) {
      await assert.rejects(f.custody(prepared, operation), rejected(404));
      assert.deepEqual(f.state(alpha), held);
    }
    alpha.authorities.set(f.material.coordinatorFingerprint, 'coordinator-a');
    assert.equal(observed(await f.custody(prepared, 'query')), 'retained');
    const pending = await f.prepare(alpha, {attemptId: 'after-revocation'});
    // Execution uses the existing Site owner's availability gate. Custody
    // cannot grant execution or revive a revoked Site owner.
    runtime.siteControl.revoke(alpha.site);
    assert.equal(runtime.siteControl.available(alpha.site), false);
    // Revocation invalidates the Site binding during prepareAdmission, before
    // the unsupported-runtime branch; the existing agent maps that error to 400.
    await assert.rejects(sendRemoteDispatch({
      ...f.tls(alpha), control, inputBindingBody,
      dispatch: f.dispatch(prepared, 'revoked-site-dispatch'),
    }), {code: 'RemoteSiteRejected', status: 400});
    alpha.agent.stopAdmission();
    await assert.rejects(f.custody(pending, 'retain'), rejected(400));
    assert.deepEqual(f.state(alpha), held);
    assert.equal(observed(await f.custody(prepared, 'query')), 'retained');
    assert.equal(observed(await f.custody(prepared, 'release')), 'fenced');
    assert.deepEqual(f.effects.providers, []);
    assert.deepEqual(f.effects.secrets, []);
    assert.equal(f.state(alpha)[2], '0');
  });

test('HTTPS lost replies and reordered retain reconcile the persisted binding after restart',
  {timeout: 30_000}, async t => {
    const f = await retentionFixture(t);
    const [alpha] = f.members;
    let prepared = await f.prepare(alpha);
    const bindingCid = bundles.holdBindingIdentity(prepared.binding);
    const loseReply = async operation => {
      const barrier = alpha.pause(operation);
      const abort = new AbortController();
      const failure = assert.rejects(f.custody(prepared, operation, {
        signal: abort.signal,
      }), {name: 'AbortError'});
      const committed = await barrier.reached;
      abort.abort();
      await failure;
      barrier.release();
      return observed(committed);
    };
    assert.equal(await loseReply('retain'), 'retained');
    assert.equal(f.state(alpha)[2], '1');
    assert.equal(observed(await f.custody(prepared, 'query')), 'retained');
    await alpha.restart();
    prepared = await f.reload(prepared);
    assert.equal(bundles.holdBindingIdentity(prepared.binding), bindingCid);
    assert.equal(observed(await f.custody(prepared, 'query')), 'retained');
    assert.equal(await loseReply('release'), 'fenced');
    await alpha.restart();
    prepared = await f.reload(prepared);
    assert.equal(bundles.holdBindingIdentity(prepared.binding), bindingCid);
    assert.equal(observed(await f.custody(prepared, 'query')), 'fenced');
    assert.equal(observed(await f.custody(prepared, 'retain')), 'fenced');
    assert.equal(f.state(alpha)[2], '0');
    const later = await f.prepare(alpha, {attemptId: 'release-before-retain'});
    const delayed = alpha.pause('retain', {before: true});
    const retaining = f.custody(later, 'retain');
    await delayed.reached;
    assert.equal(observed(await f.custody(later, 'release')), 'fenced');
    delayed.release();
    assert.equal(observed(await retaining), 'fenced');
    await alpha.restart();
    assert.equal(observed(await f.custody(await f.reload(later), 'query')), 'fenced');
    assert.equal(f.state(alpha)[2], '0');
    assert.deepEqual(f.effects.providers, []);
    assert.deepEqual(f.effects.secrets, []);
  });

test('HTTPS two Set scopes retain one member through independent cleanup and owner quota',
  {timeout: 30_000}, async t => {
    const f = await retentionFixture(t, {maxOwners: 2});
    const [alpha] = f.members;
    const first = await f.prepare(alpha, {attemptId: 'shared-first'});
    assert.equal(observed(await f.custody(first, 'retain')), 'retained');
    const second = await f.prepare(alpha, {
      setRevisionCid: cid('c'), attemptId: 'shared-second',
    });
    assert.equal(observed(await f.custody(second, 'retain')), 'retained');
    assert.notEqual(bundles.holdBindingIdentity(first.binding),
      bundles.holdBindingIdentity(second.binding));
    assert.deepEqual(f.state(alpha).slice(1), ['1', '2']);
    const overflow = await f.prepare(alpha, {attemptId: 'over-quota'});
    const full = f.state(alpha);
    await assert.rejects(f.custody(overflow, 'retain'), rejected(400));
    assert.deepEqual(f.state(alpha), full);
    assert.equal(observed(await f.custody(first, 'retain')), 'retained');
    assert.deepEqual(f.state(alpha), full);
    assert.equal(observed(await f.custody(first, 'release')), 'fenced');
    assert.deepEqual(f.state(alpha).slice(1), ['1', '1']);
    assert.equal(observed(await f.custody(second, 'query')), 'retained');
    await alpha.bundleStore.verify(alpha.runtimeBundleCid, bundles);
    assert.equal(observed(await f.custody(first, 'release')), 'fenced');
    assert.deepEqual(f.state(alpha).slice(1), ['1', '1']);
    assert.equal(observed(await f.custody(second, 'release')), 'fenced');
    assert.deepEqual(f.state(alpha).slice(1), ['1', '0']);
    // Ordinary local administrative cleanup occurs only after both owners
    // release. No remote drain or retained-bundle execution exception exists.
    alpha.bundleStore.drain(alpha.runtimeBundleCid, bundles);
    const reclaimed = await alpha.bundleStore.reclaim(alpha.runtimeBundleCid, bundles);
    await assert.rejects(readFile(reclaimed.artifactPath), {code: 'ENOENT'});
  });

test('HTTPS custody rejects substituted envelopes and unsupported agents without fallback',
  {timeout: 30_000}, async t => {
    const f = await retentionFixture(t);
    const [alpha, beta] = f.members;
    const first = await f.prepare(alpha);
    const retainRequest = f.request(first, 'retain');
    const validBody = bundles.custodyRequestJson(retainRequest);
    const replacementDistribution = bundles.prepareDistribution([
      alpha.runtimeBundleCid, beta.runtimeBundleCid,
    ]);
    const wrongDistribution = JSON.parse(validBody);
    wrongDistribution.distribution = bundles.distributionJson(replacementDistribution);
    wrongDistribution.distribution_cid = bundles.distributionIdentity(replacementDistribution);
    for (const body of [
      JSON.stringify(wrongDistribution),
      JSON.stringify({...JSON.parse(validBody), operation: 'activate'}),
      JSON.stringify({...JSON.parse(validBody), hold_id: 'arbitrary-owner'}),
    ]) {
      // Claim the changed body's own hash so linkage/closed-field validation,
      // rather than merely a stale outer hash, must reject the substitution.
      assert.equal(await rawCustody(f, alpha, body, {claimed: digest(body)}), 400);
      assert.equal(f.state(alpha)[2], '0');
    }
    assert.equal(await rawCustody(f, alpha, validBody, {claimed: cid('0')}), 400);
    const retainedReply = await f.custody(first, 'retain');
    const other = await f.prepare(alpha, {attemptId: 'other-scope'});
    const otherReply = await f.custody(other, 'query');
    for (const substituted of [retainedReply, otherReply]) {
      // Fault injection preserves a canonical response and its correct CID,
      // but substitutes another operation or binding on the real TLS channel.
      alpha.replacement = substituted;
      await assert.rejects(f.custody(first, 'query'),
        {code: 'InvalidBundleRetentionResponse'});
      assert.equal(f.state(alpha)[2], '1');
    }
    assert.equal(observed(await f.custody(first, 'query')), 'retained');
    await alpha.restart({retention: false});
    await assert.rejects(f.custody(first, 'query'), rejected(404));
    await assert.rejects(f.custody(first, 'retain'), rejected(404));
    assert.equal(f.state(alpha)[2], '1');
    assert.deepEqual(f.effects.providers, []);
    assert.deepEqual(f.effects.secrets, []);
    await alpha.restart();
    assert.equal(observed(await f.custody(await f.reload(first), 'release')), 'fenced');
    assert.equal(f.state(alpha)[2], '0');
  });
