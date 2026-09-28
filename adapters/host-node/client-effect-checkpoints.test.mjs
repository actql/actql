// Installed Checkpoint service with its real MoonBit gate, SQLite journal,
// encrypted evidence Store and public Client signature format. Full Program
// capture/apply/publication acceptance is a separate installed-Host test.
import assert from 'node:assert/strict';
import {generateKeyPairSync, sign} from 'node:crypto';
import {mkdir, mkdtemp, rm} from 'node:fs/promises';
import {join} from 'node:path';
import test from 'node:test';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {installRemoteCheckpoints} from './client-checkpoints.mjs';
import {canonicalJson} from './local-account-config.mjs';
import {signedAnswer} from '../../packages/sdk/checkpoints.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const reviewer = generateKeyPairSync('ed25519');
const host = generateKeyPairSync('ed25519');
const pem = key => key.export({type: key.type === 'private' ? 'pkcs8'
  : 'spki', format: 'pem'});
const scope = {connection: 'reference', resource: 'records'};
const configuration = read => canonicalJson({
  version: 'actql-execution-account-config/0.1', account_id: 'local',
  entries: [
    {entry_id: 'read', outcome: read, principal: {all: true},
      connection: {any_of: ['reference']}, resource: {any_of: ['records']},
      operation: {any_of: ['read']}, exclusions: []},
    {entry_id: 'write', outcome: 'delegate', principal: {all: true},
      connection: {any_of: ['reference']}, resource: {any_of: ['records']},
      operation: {any_of: ['effect']}, exclusions: []},
  ],
});

async function fixture(t, {read = 'allow', effectRequiredClaims = []} = {}) {
  const scratch = new URL('../../_build/client-effect-checkpoints/',
    import.meta.url);
  await mkdir(scratch, {recursive: true});
  const root = await mkdtemp(join(scratch.pathname, 'host-'));
  const opened = new Set();
  const clock = Date.parse('2026-09-27T00:00:00.000Z');
  const open = async () => {
    const installed = await installRemoteCheckpoints({root, tenantId: 'local',
      authorityScopeCid: cid('3'), ownerPrincipal: 'owner', siteKey: 'local',
      realizationKey: 'source-free-values', environmentCid: cid('4'),
      contractControl: runtimeCore(moon).publicationControl, now: () => clock,
      authorization: {accountConfiguration: configuration(read),
        effectRequiredClaims, resumeAfterAnswer: false,
        reviewers: [{keyId: 'reviewer-key', reviewerId: 'reviewer',
          principalId: 'reviewer', publicKey: pem(reviewer.publicKey)}],
        reviewReaders: ['reviewer'],
        hostKey: {keyId: 'host-key', privateKey: pem(host.privateKey)}}});
    opened.add(installed);
    return installed;
  };
  const close = async installed => {
    await installed.close();
    opened.delete(installed);
  };
  t.after(async () => {
    for (const installed of opened) await close(installed);
    await rm(root, {recursive: true, force: true});
  });
  return {open, close, clock};
}

const continuation = beforeDefer => ({runId: 'run-a',
  runDefinitionCid: cid('1'), unitId: 'unit-a', declaredResults: ['answer'],
  reviewWire: canonicalJson({message: 'Review the whole Effect Set'}),
  continuationWire: canonicalJson({requestId: 'request-a'}), beforeDefer});

test('Effect review and signed answer survive installed service restart',
  async t => {
    const {open, close, clock} = await fixture(t);
    let installed = await open();
    let retained = 0;
    const gate = await installed.effectAuthorization(continuation(async () => {
      retained++;
    }));
    const waiting = await gate.authorize('effect_commit',
      {...scope, operation: 'effect'}, {subjectCid: cid('2')});
    assert.equal(waiting.action, 'waiting', JSON.stringify(waiting));
    assert.equal(retained, 1);
    const page = await installed.listCheckpoints({principalId: 'reviewer',
      after: '', limit: 10});
    const summary = page.items[0];
    assert.equal(summary.subject.runId, 'run-a');
    assert.deepEqual(summary.requirements, ['effect_scope_approved']);
    assert.equal(installed.effectRunState('run-a', cid('1')).status,
      'waiting_checkpoint');
    assert.throws(() => installed.effectRunState('run-a', cid('9')),
      {code: 'EffectContinuationRunMismatch'});
    assert.equal(installed.effectRunState('other-run', cid('1')),
      undefined);
    await close(installed);
    installed = await open();
    const view = installed.journal.listRunCheckpoints()[0];
    assert.equal(view.checkpointCid, summary.checkpointCid);
    assert.deepEqual(await installed.effectContinuation(view),
      {requestId: 'request-a'});
    const review = await installed.reviewCheckpoint({principalId: 'reviewer',
      checkpointCid: summary.checkpointCid, maxBytes: 4096});
    assert.deepEqual(JSON.parse(Buffer.from(review.contentBase64, 'base64')),
      {message: 'Review the whole Effect Set'});
    const signer = {keyId: 'reviewer-key', reviewerId: 'reviewer',
      authorityScopeCid: cid('3'),
      sign: bytes => sign(null, bytes, reviewer.privateKey)};
    const foreignScope = await signedAnswer(summary, 'approved',
      {...signer, authorityScopeCid: cid('9')},
      new Date(clock).toISOString());
    const refused = await installed.resolve({principalId: 'reviewer',
      items: [foreignScope]});
    assert.notEqual(refused.results[0].status, 'committed');
    assert.equal(installed.journal.getRunState('run-a').status,
      'waiting_checkpoint');
    const answer = await signedAnswer(summary, 'approved', signer,
      new Date(clock).toISOString());
    const resolved = await installed.resolve({principalId: 'reviewer',
      items: [answer]});
    assert.equal(resolved.results[0].status, 'committed',
      JSON.stringify(resolved));
    assert.equal(installed.effectRunState('run-a', cid('1')).status,
      'resuming');
    const duplicate = await installed.resolve({principalId: 'reviewer',
      items: [answer]});
    assert.equal(duplicate.results[0].status, 'duplicate');
    assert.equal(installed.journal.listRunCheckpoints().length, 1);
    const resumedGate = await installed.effectAuthorization(
      continuation(async () => { throw new Error('ResumeMustNotRecapture'); }));
    const claim = installed.journal.claimResume('run-a', {
      claimant: 'host-after-restart', leaseMs: 60_000,
      binding: installed.binding});
    const resumed = await resumedGate.resume('effect_commit',
      {...scope, operation: 'effect'}, {subjectCid: cid('2'),
        resumption: {claim}});
    assert.equal(resumed.action, 'dispatch', JSON.stringify(resumed));
    assert.equal(typeof resumed.admission?.enter, 'function');
    const foreign = await resumedGate.resume('effect_commit',
      {...scope, operation: 'effect'}, {subjectCid: cid('9'),
        resumption: {claim}});
    assert.notEqual(foreign.action, 'dispatch');
    assert.equal(retained, 1);
    gate.close();
    resumedGate.close();
    await assert.rejects(gate.authorize('effect_commit',
      {...scope, operation: 'effect'}, {subjectCid: cid('2')}),
    {code: 'AuthorizationDecisionScopeClosed'});
  });

test('only explicit Host policy requests partial-application acceptance',
  async t => {
    const {open} = await fixture(t, {
      effectRequiredClaims: ['partial_application_accepted']});
    const installed = await open();
    const gate = await installed.effectAuthorization(continuation(async () => {}));
    const waiting = await gate.authorize('effect_commit',
      {...scope, operation: 'effect'}, {subjectCid: cid('2')});
    assert.equal(waiting.action, 'waiting');
    const page = await installed.listCheckpoints({principalId: 'reviewer',
      after: '', limit: 10});
    assert.deepEqual(page.items[0].requirements,
      ['effect_scope_approved', 'partial_application_accepted']);
    gate.close();
  });

test('deferred target read is unsupported, not denied or checkpointed',
  async t => {
    const {open} = await fixture(t, {read: 'delegate'});
    const installed = await open();
    let retained = 0;
    const gate = await installed.effectAuthorization(continuation(async () => {
      retained++;
    }));
    const decision = await gate.authorize('acquisition',
      {...scope, operation: 'read'}, {subjectCid: cid('2')});
    assert.equal(decision.action, 'unsupported');
    assert.equal(retained, 0);
    assert.deepEqual(installed.journal.listRunCheckpoints(), []);
    assert.deepEqual(installed.journal.listPending(), []);
    gate.close();
  });
