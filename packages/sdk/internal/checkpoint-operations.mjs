// Existing bounded Checkpoint review and signed resolution operations.
import {checkedSigner, reviewBytesMatchCid, signedAnswer} from '../checkpoints.mjs';
import {positive} from './data.mjs';
import {ClientError, fail} from './errors.mjs';
import {reviewEnvelopeBytes} from './transport-response.mjs';
import {checkpointLimits, validCheckpointPage, validCheckpointReview, validResolveItem,
  validResolveResults} from '@actql/client-wire';

export function createCheckpointOperations(connection, exchange, responseValue) {
  const selected = {wire: connection};
  return {
    checkpoints: async ({after, limit = 50, signal} = {}) => {
      if (after !== undefined && (typeof after !== 'string' || !after) ||
          !positive(limit) || limit > checkpointLimits.maxPageItems) {
        fail('InvalidCheckpointPage');
      }
      const response = await exchange('checkpoints',
        {after: after ?? '', limit}, signal);
      let page;
      try { page = await responseValue(response); }
      catch (cause) { throw new ClientError('InvalidHostCheckpointPage', {cause}); }
      if (!validCheckpointPage(page, limit)) fail('InvalidHostCheckpointPage');
      return Object.freeze({items: Object.freeze(page.items.map(item =>
        Object.freeze(structuredClone(item)))),
      ...(page.next === undefined ? {} : {next: page.next})});
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
  };
}
