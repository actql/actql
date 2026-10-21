// Existing bounded Checkpoint review and signed resolution operations.
import {checkedSigner, contentCid, reviewBytesMatchCid, signedAnswer} from '../checkpoints.mjs';
import {validAnswerEvidence, validAnswerResolution} from './checkpoint-answer-contract.generated.mjs';
import {captureResponse, freezeInput, positive} from './data.mjs';
import {ClientError, fail} from './errors.mjs';
import {reviewEnvelopeBytes} from './transport-response.mjs';
import {checkpointLimits, validCheckpointLookup, validCheckpointPage, validCheckpointReview, validResolveItem,
  validResolveResults} from '@actql/client-wire';

export function createCheckpointOperations(connection, exchange, responseValue,
  {answerOriginal, isClosed = () => false} = {}) {
  const without = (value, name) => Object.fromEntries(Object.entries(value)
    .filter(([key]) => key !== name));
  const answerMatches = async (answer, summary, decision, signer) => {
    try {
      if (!validResolveItem(answer) || answer.checkpointCid !== summary.checkpointCid) return false;
      const resolution = JSON.parse(answer.resolutionWire);
      if (!validAnswerResolution(resolution) || resolution.decision !== decision ||
          resolution.checkpoint_id !== summary.checkpointId ||
          resolution.checkpoint_cid !== summary.checkpointCid ||
          resolution.required_artifact_cid !== summary.requiredArtifact.cid ||
          resolution.review_projection_cid !== summary.reviewProjectionCid ||
          signer !== undefined && (resolution.actor !== signer.reviewerId ||
            resolution.proof.key_id !== signer.keyId)) return false;
      if (summary.subject.kind === 'run_unit'
        ? resolution.run_id !== summary.subject.runId ||
          resolution.run_definition_cid !== summary.subject.runDefinitionCid
        : resolution.prepare_attempt_id !== summary.subject.prepareAttemptId) return false;
      if (await contentCid(without(resolution, 'resolution_cid')) !== resolution.resolution_cid) return false;
      if (decision === 'rejected') return answer.approvalEvidenceWire === '';
      const evidence = JSON.parse(answer.approvalEvidenceWire);
      if (!validAnswerEvidence(evidence) || evidence.kind !== summary.kind ||
          evidence.checkpoint_cid !== summary.checkpointCid ||
          evidence.review_projection_cid !== summary.reviewProjectionCid ||
          await contentCid(evidence) !== resolution.approval_evidence_cid) return false;
      const approval = evidence.compatibility_approval;
      if (approval.approver !== resolution.actor ||
          approval.proof.key_id !== resolution.proof.key_id ||
          approval.review_projection_cid !== summary.reviewProjectionCid) return false;
      const effect = summary.kind === 'effect_set';
      if (effect ? approval.effect_preview_cid !== summary.requiredArtifact.cid ||
          approval.claims.length !== summary.requirements.length ||
          !approval.claims.every((claim, index) => claim === summary.requirements[index]) ||
          signer !== undefined && approval.authority_scope_cid !== signer.authorityScopeCid
        : approval.prepared_invocation_cid !== (summary.kind === 'model_invocation'
          ? summary.preparedInvocationCid : summary.requiredArtifact.cid) ||
          approval.expires_at !== summary.expiresAt) return false;
      const self = effect ? 'attestation_cid' : 'run_scope_approval_cid';
      return await contentCid(without(approval, self)) === approval[self];
    } catch { return false; }
  };
  const current = signal => {
    if (isClosed()) fail('ClientClosed');
    signal?.throwIfAborted();
  };
  const answerById = async (checkpointId, decision, {signer, signal} = {}) => {
    current(signal);
    if (!validCheckpointLookup({items: []}, checkpointId)) {
      fail('InvalidCheckpointReference');
    }
    let selectedSigner;
    if (signer !== undefined) {
      // Own the original application callback and receiver before lookup.
      // Neither lookup nor an awaited callback may switch the selected key.
      try {
        if (signer === null || typeof signer !== 'object') {
          fail('InvalidCheckpointSigner');
        }
        const keyId = signer.keyId, reviewerId = signer.reviewerId;
        const authorityScopeCid = signer.authorityScopeCid, sign = signer.sign;
        if (typeof sign !== 'function') fail('InvalidCheckpointSigner');
        selectedSigner = checkedSigner(Object.freeze({keyId, reviewerId,
          authorityScopeCid, sign(bytes) {
            current(signal);
            return Reflect.apply(sign, signer, [bytes]);
          }}));
      } catch { fail('InvalidCheckpointSigner'); }
    } else if (answerOriginal === undefined) {
      // Missing original Local signing custody is not permission to use a
      // Host-attestation key, create a key or send an unsigned approval.
      fail('CheckpointSignerUnavailable');
    }
    const page = await operations.checkpoints({checkpointId, limit: 1, signal});
    current(signal);
    if (page.items.length !== 1) fail('CheckpointUnavailable');
    const summary = freezeInput(page.items[0]);
    let answer;
    if (selectedSigner !== undefined) {
      answer = await signedAnswer(summary, decision, selectedSigner,
        new Date().toISOString());
    } else {
      // The installed provider must independently bind this DATA to its
      // actual original Checkpoint/key/use and current authority. This
      // callback returns an existing signed answer, never a generic signer.
      answer = await answerOriginal(summary, decision, signal);
    }
    current(signal);
    try { answer = freezeInput(captureResponse(answer)); }
    catch { fail('InvalidCheckpointAnswer'); }
    if (!validResolveItem(answer)) fail('InvalidCheckpointAnswer');
    if (!await answerMatches(answer, summary, decision, selectedSigner)) {
      // Preserve the actual returned bytes for inspection, not as a retry
      // permission. Never repair a foreign decision or ask for another sign.
      throw new ClientError('InvalidCheckpointAnswer', {signed: Object.freeze([answer])});
    }
    current(signal);
    // Retain the existing response-loss contract: ResolutionUnknown carries
    // these exact signed bytes. No automatic re-sign, retry or resend occurs.
    return operations.resolveCheckpoints([answer], {signal});
  };
  const operations = {
    checkpoints: async ({after, limit, checkpointId, signal} = {}) => {
      if (limit === undefined) limit = checkpointId === undefined ? 50 : 1;
      const lookup = checkpointId !== undefined;
      if (after !== undefined && (typeof after !== 'string' || !after) ||
          !positive(limit) || limit > checkpointLimits.maxPageItems) {
        fail('InvalidCheckpointPage');
      }
      if (lookup && (after !== undefined || limit !== 1 ||
          !validCheckpointLookup({items: []}, checkpointId))) {
        fail('InvalidCheckpointReference');
      }
      const response = await exchange('checkpoints',
        {after: after ?? '', limit,
          ...(lookup ? {checkpointId} : {})}, signal);
      let page;
      try { page = await responseValue(response); }
      catch (cause) { throw new ClientError('InvalidHostCheckpointPage', {cause}); }
      try { page = captureResponse(page); }
      catch { fail('InvalidHostCheckpointPage'); }
      if (!(lookup ? validCheckpointLookup(page, checkpointId)
        : validCheckpointPage(page, limit))) fail('InvalidHostCheckpointPage');
      return freezeInput(page);
    },
    // The exact review projection a Checkpoint names, when the caller is
    // authorized to read it. Bounded by `maxBytes` on both sides; the bytes
    // are verified against the named artifact CID before they are returned.
    // Aborting this read never cancels the request or Run.
    reviewCheckpoint: async (checkpoint, {maxBytes = 64 * 1024,
      signal} = {}) => {
      const checkpointCid = typeof checkpoint === 'string' ? checkpoint
        : checkpoint?.checkpointCid;
      if (typeof checkpointCid !== 'string' ||
          !/^sha256:[0-9a-f]{64}$/u.test(checkpointCid)) {
        fail('InvalidCheckpointReference');
      }
      if (!positive(maxBytes) || maxBytes > checkpointLimits.maxReviewBytes) {
        fail('InvalidReviewLimit');
      }
      const response = await exchange('checkpoint-review',
        {checkpointCid, maxBytes}, signal);
      let review;
      try { review = await responseValue(response,
        4 * Math.ceil(maxBytes / 3) + reviewEnvelopeBytes); }
      catch (cause) { throw new ClientError('ReviewReadUnknown', {cause}); }
      if (!validCheckpointReview(review, {checkpointCid, maxBytes})) {
        fail('InvalidHostCheckpointReview');
      }
      const bytes = Uint8Array.from(atob(review.contentBase64),
        character => character.charCodeAt(0));
      if (bytes.byteLength !== review.byteLength ||
          !await reviewBytesMatchCid(bytes, review.artifactCid) ||
          typeof checkpoint === 'object' &&
            checkpoint.reviewProjectionCid !== undefined &&
            checkpoint.reviewProjectionCid !== review.artifactCid) {
        fail('ReviewIntegrityFailed');
      }
      return Object.freeze({checkpointCid, artifactCid: review.artifactCid,
        bytes});
    },
    // Answer one or more Checkpoints. Each item is either {checkpoint,
    // decision} (a listed summary and 'approved' | 'rejected', signed here
    // by `signer`) or a previously signed item returned by an earlier call,
    // which is resent unchanged. Results are per Checkpoint; the batch is not
    // atomic. A stored answer is not a resumed or completed Run: follow the
    // request with lookupRequest, then status()/wait() once the Run exists.
    // When the reply is lost the error carries the exact signed items to
    // resend; they are never re-signed with a new decision time.
    resolveCheckpoints: async (items, {signer, signal} = {}) => {
      if (!Array.isArray(items) || items.length === 0 ||
          items.length > checkpointLimits.maxResolveItems) {
        fail('InvalidCheckpointAnswers');
      }
      const decidedAt = new Date().toISOString();
      const signed = [];
      for (const item of items) {
        if (validResolveItem(item)) {
          signed.push(Object.freeze({...item}));
          continue;
        }
        let key;
        try { key = checkedSigner(signer); }
        catch { fail('InvalidCheckpointSigner'); }
        try {
          signed.push(await signedAnswer(item?.checkpoint, item?.decision,
            key, decidedAt));
        } catch (cause) {
          throw new ClientError(cause.message ?? 'InvalidCheckpointAnswer',
            {cause});
        }
      }
      if (new Set(signed.map(item => item.checkpointCid)).size !==
          signed.length) fail('DuplicateCheckpointAnswer');
      const frozen = Object.freeze(signed);
      let answer;
      try {
        const response = await exchange('resolve', {items: frozen}, signal);
        answer = await responseValue(response);
      } catch (cause) {
        if (cause instanceof ClientError && cause.code !==
            'ClientTransportUnknown' && !(cause.status >= 500)) throw cause;
        throw new ClientError('ResolutionUnknown', {signed: frozen, cause});
      }
      if (!validResolveResults(answer, frozen)) {
        throw new ClientError('ResolutionUnknown', {signed: frozen,
          cause: new ClientError('InvalidHostResolveReply')});
      }
      return Object.freeze({
        results: Object.freeze(answer.results.map(result =>
          Object.freeze({...result}))),
        signed: frozen,
      });
    },
    approve: (checkpointId, options) => answerById(checkpointId, 'approved', options),
    reject: (checkpointId, options) => answerById(checkpointId, 'rejected', options),
  };
  return operations;
}
