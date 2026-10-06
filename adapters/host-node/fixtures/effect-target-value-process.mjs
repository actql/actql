// Separate-process fixture over the real encrypted Checkpoint journal. The
// legacy modes use the unchanged old encoders only to create explicit
// previous-format evidence; production never takes those fallback paths.
import assert from 'node:assert/strict';
import {generateKeyPairSync, sign} from 'node:crypto';
import {readFile, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import * as moon from '../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../../host-common/runtime-core.mjs';
import {installRemoteCheckpoints} from '../client-checkpoints.mjs';
import {effectTargetReadContinuation} from '../effect-target-read-continuation.mjs';
import {canonicalJson as legacyConfigurationJson} from '../local-account-config.mjs';
import {canonicalJson as legacyValueJson, signedAnswer} from
  '../../../packages/sdk/checkpoints.mjs';
import {checkpointApprovalFacts} from '../../host-common/checkpoint-approval.mjs';

const [phase, root, variant] = process.argv.slice(2);
const cid = digit => `sha256:${digit.repeat(64)}`;
const pem = key => key.export({type: key.type === 'private' ? 'pkcs8' : 'spki', format: 'pem'});
const keysPath = join(root, 'fixture-keys.json');
if (phase === 'capture') {
  const host = generateKeyPairSync('ed25519');
  const reviewer = generateKeyPairSync('ed25519');
  await writeFile(keysPath, JSON.stringify({hostPrivate: pem(host.privateKey),
    reviewerPrivate: pem(reviewer.privateKey), reviewerPublic: pem(reviewer.publicKey)}));
}
const keys = JSON.parse(await readFile(keysPath, 'utf8'));
const original = ['legacy-ascii', 'legacy-keys'].includes(variant) ? 'plain\r\ntext'
  : variant === 'legacy-nfc' ? '\u00e9\r\ntext'
    : 'e\u0301\r\nline\rreturn\n' + JSON.stringify({nested: 'e\u0301'});
const submission = {requestId: 'process-request',
  input: {format: 'json', text: JSON.stringify({document: original})},
  parameters: {text: original}};
const readTuple = {connection: 'crm', resource: 'Account', operation: 'read'};
const physicalBinding = {version: 'fixture-target/0.1',
  text: variant.startsWith('legacy-') ? 'unchanged-provider-binding' : original};
if (variant === 'exact-keys' || variant === 'legacy-keys') {
  submission.input.literal = variant === 'exact-keys'
    ? {'é': 'composed', 'e\u0301': 'decomposed', '\r\n': 'CRLF', '\n': 'LF'}
    : {'e\u0301\r\n': 'stable'};
  if (variant === 'exact-keys') physicalBinding.json = submission.input.literal;
}
const configuration = legacyConfigurationJson({version: 'actql-execution-account-config/0.1',
  account_id: 'process-account', entries: [{entry_id: 'read', outcome: 'delegate',
    principal: {all: true}, connection: {any_of: ['crm']}, resource: {all: true},
    operation: {any_of: ['read']}, exclusions: []}]});
const now = () => Date.parse('2026-10-04T00:00:00.000Z');
const checkpoints = await installRemoteCheckpoints({root: join(root, 'host'),
  namespaceId: 'local', authorityScopeCid: cid('3'), ownerPrincipal: 'owner',
  siteKey: 'local', realizationKey: 'source-free-values', environmentCid: cid('4'),
  effectTarget: {accountConfiguration: configuration,
    context: {principal: 'owner', contextCid: cid('5')}},
  contractControl: runtimeCore(moon).publicationControl, now,
  authorization: {accountConfiguration: configuration, resumeAfterAnswer: false,
    reviewers: [{keyId: 'reviewer-key', reviewerId: 'reviewer', principalId: 'reviewer',
      publicKey: keys.reviewerPublic}], reviewReaders: ['reviewer'],
    hostKey: {keyId: 'host-key', privateKey: keys.hostPrivate}}});
const options = {checkpoints, runId: 'process-run', runDefinitionCid: cid('6'),
  unitId: 'effect', declaredResults: ['answer'], principalId: 'owner', submission,
  inventory: [{readTuple, physicalBinding}]};
let owner;
try {
  if (phase === 'capture') {
    if (variant.startsWith('legacy-')) {
      options.checkpoints = {...checkpoints,
        effectTargetAuthorization: args => checkpoints.effectTargetAuthorization({...args,
          continuation: async () => (variant === 'legacy-keys'
            ? legacyValueJson : legacyConfigurationJson)(
            JSON.parse(await args.continuation()))})};
    }
    owner = await effectTargetReadContinuation(options);
    assert.equal((await owner.prepare()).status, 'waiting_checkpoint');
  }
  const [summary] = (await checkpoints.listCheckpoints({principalId: 'reviewer',
    after: '', limit: 20})).items;
  const view = checkpoints.journal.inspect(summary.checkpointCid);
  const saved = await checkpoints.effectTargetContinuation(view);
  const review = await checkpoints.reviewCheckpoint({principalId: 'reviewer',
    checkpointCid: view.checkpointCid, maxBytes: 256 * 1024});
  let refused = false;
  let sends = 0;
  if (phase === 'resume') {
    const answer = await signedAnswer(summary, 'approved', {
      keyId: 'reviewer-key', reviewerId: 'reviewer', authorityScopeCid: cid('3'),
      sign: bytes => sign(null, bytes, keys.reviewerPrivate)}, new Date(now()).toISOString());
    const resolved = await checkpoints.resolve({principalId: 'reviewer', items: [answer]});
    assert.equal(resolved.results[0].status, 'committed');
    const claim = checkpoints.journal.claimResume('process-run', {claimant: 'process-host',
      leaseMs: 60_000, binding: checkpoints.binding, preserveStarted: true,
      expectedCheckpointCid: view.checkpointCid});
    assert.equal(claim.action, 'claimed');
    options.resume = {view, claim: claim.claim, continuation: saved,
      assertCurrent: () => checkpoints.journal.admitResume(claim.claim,
        {checkpointCid: view.checkpointCid})};
    if (variant === 'legacy-decomposed' || variant === 'legacy-keys') {
      await assert.rejects(async () => {
        owner = await effectTargetReadContinuation(options);
        await owner.prepare(); owner.enterComputation(); sends++;
      }, {code: 'EffectTargetBindingChanged'});
      refused = true;
      assert.equal(checkpoints.journal.hasStartedResume(view.checkpointCid), false);
    } else {
      owner = await effectTargetReadContinuation(options);
      assert.deepEqual(await owner.prepare(), {status: 'ready'});
      const approved = checkpointApprovalFacts(await owner.authorize(readTuple));
      assert.deepEqual(approved.physicalBindings, [physicalBinding]);
      owner.enterComputation();
      assert.equal(checkpoints.journal.hasStartedResume(view.checkpointCid), true);
    }
  }
  console.log(JSON.stringify({pid: process.pid, saved, review, refused, sends}));
} finally {
  owner?.close();
  await checkpoints.close();
}
