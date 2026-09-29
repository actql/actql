// Read→Compute→Effect acceptance through the public Client on the Remote HTTP
// Host: a Program acquires Salesforce records, filters and derives a value
// locally, previews an update of the same records, waits for approval across
// a Host restart, writes, and publishes its Named Result. The org is a local
// stateful HTTPS mock; expected values come from read-compute-effect.fixture.
//
// Until the common Host runs an Effect from an acquisition, the path tests
// fail with ReadComputeEffectNotConnected: that is the path not being
// connected, not a Salesforce defect, and never counts as passing.
import assert from 'node:assert/strict';
import {request as httpsRequest} from 'node:https';
import test from 'node:test';
import {approveHeldSet, expectedBodies, expectedOrgAfterSuccess,
  expectedUpdates, fourRecords, hostAccountConfiguration,
  readComputeEffectInstallation, submitReadComputeEffect, waitFor} from
  './read-compute-effect.fixture.mjs';

const byId = rows => [...rows].sort((a, b) => a.Id < b.Id ? -1 : 1);
const targetOf = write => decodeURIComponent(write.path.split('/').at(-1));

// Submit the acceptance Program and wait until its Set is held for approval.
async function heldForApproval(setup, host, requestId, options) {
  const client = await host.as('owner-token');
  const execution = await submitReadComputeEffect(client,
    setup.program(options), requestId);
  await waitFor(async () => (await execution.status()).status ===
    'waiting_checkpoint');
  return execution;
}

// Resume the approved Run in a new Host process and wait for its end.
async function resumed(setup, execution, options) {
  const host = await setup.openHost(options);
  const attached = await (await host.as('owner-token')).attach(execution.ref);
  const state = await waitFor(async () => {
    const current = await attached.status();
    return ['succeeded', 'failed', 'needs_reconciliation', 'cancelled']
      .includes(current.status) ? current : undefined;
  });
  return {host, attached, state};
}

// One direct request to the mock org, outside ActQL.
function orgRequest(org, method, path, body) {
  return new Promise((resolve, reject) => {
    const request = httpsRequest(`${org.origin}${path}`, {method,
      ca: org.credential.ca,
      headers: {authorization: 'Bearer test-only-secret',
        'content-type': 'application/json'}}, response => {
      const chunks = [];
      response.on('data', chunk => chunks.push(chunk));
      response.on('end', () => resolve({status: response.statusCode,
        body: Buffer.concat(chunks).toString('utf8')}));
    });
    request.on('error', reject);
    request.end(body);
  });
}

test('the stateful org applies, loses and refuses writes as configured',
  async t => {
    const setup = await readComputeEffectInstallation(t, {records: fourRecords,
      org: {patchFields: ['Name'], loseReplyAfterApply: [2],
        rejectWrites: [3]}});
    const {org} = setup;
    const path = id => `/services/data/v62.0/sobjects/Test_Record__c/${id}`;
    const before = org.seen.length;
    // Applied with a reply.
    assert.equal((await orgRequest(org, 'PATCH', path('a00000000000001'),
      '{"Name":"one"}')).status, 204);
    // Applied, then the reply is lost.
    await assert.rejects(orgRequest(org, 'PATCH', path('a00000000000003'),
      '{"Name":"three"}'));
    // Rejected before saving: nothing changes.
    assert.equal((await orgRequest(org, 'PATCH', path('a00000000000004'),
      '{"Name":"four"}')).status, 400);
    assert.deepEqual(org.records().map(record => record.Name),
      ['one', 'record-2', 'three', 'record-4']);
    // A target read answers the current record; a deleted one is 404.
    assert.equal(JSON.parse((await orgRequest(org, 'GET',
      path('a00000000000001'))).body).Name, 'one');
    org.deleteRecord('a00000000000004');
    assert.equal((await orgRequest(org, 'GET', path('a00000000000004')))
      .status, 404);
    assert.equal(org.seen.length, before + 5);
  });

test('Read→Compute→Effect previews, waits across a restart, writes once and publishes',
  async t => {
    const setup = await readComputeEffectInstallation(t);
    const first = await setup.openHost();
    const execution = await heldForApproval(setup, first, 'rce-success');
    // Held: the source was acquired once, nothing was written.
    assert.equal(setup.queries(), 1);
    assert.equal(setup.writes().length, 0);
    await first.close();
    const second = await setup.openHost();
    await approveHeldSet(second, execution);
    await second.close();
    const queriesBeforeResume = setup.queries();
    const {host: third, attached, state} = await resumed(setup, execution);
    assert.equal(state.status, 'succeeded', JSON.stringify(state));
    // The approved rows were written once each, as their exact bodies; the
    // filtered-out record was not written.
    assert.deepEqual(setup.writes().map(write =>
      [write.method, targetOf(write), write.body]).sort(), [
      ['PATCH', 'a00000000000001', expectedBodies.a00000000000001],
      ['PATCH', 'a00000000000003', expectedBodies.a00000000000003],
    ]);
    // No re-acquisition after the restart: the write used the durable input.
    assert.equal(setup.queries(), queriesBeforeResume);
    assert.deepEqual(byId(await attached.result('updates').all()),
      expectedUpdates);
    assert.deepEqual(setup.org.records(), expectedOrgAfterSuccess);
    await third.close();
    // A further restart writes and acquires nothing more.
    const writes = setup.writes().length;
    const queries = setup.queries();
    const fourth = await setup.openHost();
    const again = await (await fourth.as('owner-token')).attach(execution.ref);
    assert.equal((await again.status()).status, 'succeeded');
    assert.equal(setup.writes().length, writes);
    assert.equal(setup.queries(), queries);
  });

test('a target changed after acquisition but before the Preview is previewed as it now is',
  async t => {
    // The change happens as soon as the source query is answered, before
    // the target check reads that author the Preview.
    let changed = false;
    const setup = await readComputeEffectInstallation(t, {org: {
      onQuery: () => {
        if (changed) return;
        changed = true;
        setup.org.setRecord('a00000000000001', {Name: 'changed-outside'});
      }}});
    const first = await setup.openHost();
    const execution = await heldForApproval(setup, first, 'rce-pre-preview');
    await first.close();
    const second = await setup.openHost();
    await approveHeldSet(second, execution);
    await second.close();
    const {state} = await resumed(setup, execution);
    // Per the existing guard: the approved Preview still matches the target
    // at send time, so the Set is written.
    assert.equal(state.status, 'succeeded', JSON.stringify(state));
    assert.equal(setup.writes().length, 2);
    assert.deepEqual(setup.org.records(), expectedOrgAfterSuccess);
  });

test('a target changed after the Preview is refused before any write',
  async t => {
    const setup = await readComputeEffectInstallation(t);
    const first = await setup.openHost();
    const execution = await heldForApproval(setup, first, 'rce-post-preview');
    await first.close();
    // Changed outside ActQL after the Preview, before the send.
    setup.org.setRecord('a00000000000003', {Name: 'changed-after-preview'});
    const second = await setup.openHost();
    await approveHeldSet(second, execution);
    await second.close();
    const {state} = await resumed(setup, execution);
    assert.equal(state.status, 'failed', JSON.stringify(state));
    assert.equal(setup.writes().length, 0);
    assert.equal(setup.org.records()[0].Name, 'record-1');
  });

test('an expired approval writes nothing', async t => {
  const setup = await readComputeEffectInstallation(t);
  const ttl = {checkpointTtlMs: 8000};
  const first = await setup.openHost({authorization: ttl});
  const execution = await heldForApproval(setup, first, 'rce-expired');
  const reviewer = await first.as('reviewer-token');
  const [checkpoint] = (await reviewer.checkpoints()).items;
  await first.close();
  // Wait, bounded, until the approval window has surely passed.
  const expiresAt = Date.parse(checkpoint.expiresAt);
  assert.ok(Number.isFinite(expiresAt) && expiresAt - Date.now() < 10_000);
  await new Promise(resolve => setTimeout(resolve,
    Math.max(0, expiresAt + 500 - Date.now())));
  assert.ok(Date.now() > expiresAt);
  const second = await setup.openHost({authorization: ttl});
  const attached = await (await second.as('owner-token')).attach(
    execution.ref);
  await waitFor(async () => ['failed', 'cancelled'].includes(
    (await attached.status()).status));
  assert.equal(setup.writes().length, 0);
});

test('a commit permission revoked after approval writes nothing',
  async t => {
    // (a) The Host's account configuration now denies the Effect commit.
    // This checks refusal on a configuration change only.
    {
      const setup = await readComputeEffectInstallation(t);
      const first = await setup.openHost();
      const execution = await heldForApproval(setup, first, 'rce-denied');
      await first.close();
      const second = await setup.openHost();
      await approveHeldSet(second, execution);
      await second.close();
      const {state} = await resumed(setup, execution, {accountConfiguration:
        hostAccountConfiguration(setup.org.orgId, {effect: 'deny'})});
      assert.equal(state.status, 'failed', JSON.stringify(state));
      assert.equal(setup.writes().length, 0);
    }
    // (b) Same installation and configuration: the org no longer lets this
    // user update Name. The pre-send recheck of the target field refuses.
    {
      const setup = await readComputeEffectInstallation(t);
      const first = await setup.openHost();
      const execution = await heldForApproval(setup, first, 'rce-lapsed');
      await first.close();
      const second = await setup.openHost();
      await approveHeldSet(second, execution);
      await second.close();
      setup.org.setNameUpdateable(false);
      const {state} = await resumed(setup, execution);
      assert.equal(state.status, 'failed', JSON.stringify(state));
      assert.equal(setup.writes().length, 0);
    }
  });

test('a reply lost after the org applied the write is unknown and never resent',
  async t => {
    // The second write is applied by the org, and its reply is lost.
    const setup = await readComputeEffectInstallation(t, {
      org: {loseReplyAfterApply: [2]}});
    const first = await setup.openHost();
    const execution = await heldForApproval(setup, first, 'rce-lost');
    await first.close();
    const second = await setup.openHost();
    await approveHeldSet(second, execution);
    await second.close();
    const {host: third, state} = await resumed(setup, execution);
    assert.equal(state.status, 'needs_reconciliation', JSON.stringify(state));
    // Each row was sent once; both are applied in the org.
    assert.equal(setup.writes().length, 2);
    assert.deepEqual(setup.org.records(), expectedOrgAfterSuccess);
    await third.close();
    // A restart does not resend the unknown row.
    const fourth = await setup.openHost();
    const again = await (await fourth.as('owner-token')).attach(execution.ref);
    assert.equal((await again.status()).status, 'needs_reconciliation');
    assert.equal(setup.writes().length, 2);
  });

test('halt: a failed row stops the Set after the earlier row was applied',
  async t => {
    // Three targets; the org rejects the second write.
    const setup = await readComputeEffectInstallation(t, {
      records: fourRecords, org: {rejectWrites: [2]}});
    const first = await setup.openHost();
    const execution = await heldForApproval(setup, first, 'rce-halt');
    await first.close();
    const second = await setup.openHost();
    await approveHeldSet(second, execution);
    await second.close();
    const {state} = await resumed(setup, execution);
    assert.equal(state.status, 'failed', JSON.stringify(state));
    // First applied, second refused, third never sent.
    const writes = setup.writes();
    assert.equal(writes.length, 2);
    const names = setup.org.records().map(record => record.Name);
    assert.equal(names.filter(name => name.endsWith('-processed')).length, 1);
    assert.equal(names.filter(name => name.startsWith('record-')).length, 3);
  });

test('continue: applied and failed rows are settled independently',
  async t => {
    // Three independent targets; the org rejects the second.
    const setup = await readComputeEffectInstallation(t, {
      records: fourRecords, org: {rejectWrites: [2]}});
    const first = await setup.openHost();
    const execution = await heldForApproval(setup, first, 'rce-continue',
      {onItemFailure: 'continue'});
    await first.close();
    const second = await setup.openHost();
    await approveHeldSet(second, execution);
    await second.close();
    const {state} = await resumed(setup, execution);
    assert.equal(state.status, 'failed', JSON.stringify(state));
    // Every row was sent once: two applied, one refused, none resent.
    assert.equal(setup.writes().length, 3);
    assert.equal(setup.org.records().filter(record =>
      record.Name.endsWith('-processed')).length, 2);
  });

// --- Embedded Local: each step is its own process, so each is a restart ----

// Submit on Embedded; not being connected is reported as such.
async function embeddedHeld(steps) {
  const submitted = await steps('submit');
  if (submitted.notConnected) {
    throw Object.assign(new Error('ReadComputeEffectNotConnected: ' +
      'Embedded Local refuses the Program (ClientProgramUnsupported).'),
    {code: 'ReadComputeEffectNotConnected'});
  }
  assert.deepEqual(submitted, {held: true});
}

test('Embedded: previews, waits across restarts, writes once and publishes',
  async t => {
    const setup = await readComputeEffectInstallation(t);
    const steps = await setup.embedded('rce-embedded', setup.program());
    await embeddedHeld(steps);
    assert.equal(setup.queries(), 1);
    assert.equal(setup.writes().length, 0);
    assert.deepEqual(await steps('answer'), {answered: ['committed']});
    assert.equal(setup.writes().length, 0);
    const queries = setup.queries();
    const done = await steps('resume');
    assert.equal(done.status, 'succeeded', JSON.stringify(done));
    assert.deepEqual(byId(done.rows), expectedUpdates);
    assert.deepEqual(setup.writes().map(write => [targetOf(write), write.body])
      .sort(), [
      ['a00000000000001', expectedBodies.a00000000000001],
      ['a00000000000003', expectedBodies.a00000000000003]]);
    assert.equal(setup.queries(), queries);
    assert.deepEqual(setup.org.records(), expectedOrgAfterSuccess);
    // A further restart writes nothing more.
    assert.equal((await steps('resume')).status, 'succeeded');
    assert.equal(setup.writes().length, 2);
  });

test('Embedded: a target changed after the Preview is refused before any write',
  async t => {
    const setup = await readComputeEffectInstallation(t);
    const steps = await setup.embedded('rce-embedded-stale', setup.program());
    await embeddedHeld(steps);
    setup.org.setRecord('a00000000000003', {Name: 'changed-after-preview'});
    assert.deepEqual(await steps('answer'), {answered: ['committed']});
    const done = await steps('resume');
    assert.equal(done.status, 'failed', JSON.stringify(done));
    assert.equal(setup.writes().length, 0);
  });
