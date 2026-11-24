// Original Checkpoint review and answer surfaces. Store reads and signed
// answers still pass the same granted principals, Journal and Host closure.
import {canonicalJson as canonicalValueJson} from '../../packages/sdk/host-port.mjs';
import {validCheckpointLookup} from '../../packages/client-wire/index.mjs';
import {ExecutionAuthorizationError} from '../host-common/authorization-gate.mjs';
import {INSTALLED_EFFECT_CHECKPOINT_LIMITS} from '../host-common/installed-checkpoint-codec-limits.mjs';
import {modelCheckpointMetadata} from './model-checkpoint-metadata.mjs';
import {coded, fail} from './client-checkpoint-admission-inputs.mjs';

import type {runtimeCore} from '../host-common/runtime-core.mjs';
import type {createLocalAuthorizationGate} from './local-account-config.mjs';
import type {openContinuationEvidence} from './local-continuation-evidence.mjs';
import type {openSqliteCheckpointJournal} from './sqlite-checkpoint-journal.mjs';

type Journal = ReturnType<typeof openSqliteCheckpointJournal>;
type View = NonNullable<ReturnType<Journal['inspect']>>;
type Gate = Awaited<ReturnType<typeof createLocalAuthorizationGate>>;
type ResolutionInputs = Parameters<Journal['submitResolutions']>[0];
type ResolutionInput = Readonly<{principalId: string; items: ResolutionInputs}>;
type ResolutionResult = Readonly<{
  checkpointCid: string; status: string; decision?: string; resolutionCid?: string; reason?: string;
}>;
type CheckpointList = Readonly<{principalId: string; after: string; limit: number; checkpointId?: string}>;
type SigningContext = Readonly<{
  principalId: string; summary?: Readonly<{checkpointCid: string}>;
  signingResource?: string; signal?: AbortSignal;
}>;
type ReviewInput = Readonly<{principalId: string; checkpointCid: string; maxBytes: number; signal?: AbortSignal}>;
type ErrorCode = Readonly<{code?: string}> | null | undefined;
type StoredContinuation = Readonly<{
  version: string; run_definition_cid: string; model_invocation_scope_cid: string;
  review_projection_cid: string; review_storage_cid: string; continuation_wire: string;
}>;
type Ports = Readonly<{
  journal: Journal; evidence: Pick<ReturnType<typeof openContinuationEvidence>, 'open'>;
  contractControl: Pick<ReturnType<typeof runtimeCore>['publicationControl'], 'admitRunEvidence'>;
  gate: Gate; authorityScopeCid: string; ownerPrincipal: string; siteKey: string;
  readers: ReadonlySet<string>; answerers: ReadonlySet<string>;
  trusted: ReadonlyMap<string, Readonly<{principalId: string}>>;
  maxReviewBytes: number; resumeAfterAnswer: boolean; closed: boolean;
  heldRequestId(prepareAttemptId: string): Promise<string>; sweep(): unknown;
}>;

const MAX_PAGE = 100;
export const MODEL_CHECKPOINT_STORAGE = 'actql-installed-model-checkpoint-storage/0.1';

export function createCheckpointReview(ports: Ports) {
  const {journal, evidence, contractControl, gate, authorityScopeCid, ownerPrincipal, siteKey,
    readers, answerers, trusted, maxReviewBytes, heldRequestId, resumeAfterAnswer, sweep} = ports;
  const summaryOf = async (view: View) => {
    let subject;
    if (view.prepareAttemptId !== null) {
      const requestId = await heldRequestId(view.prepareAttemptId!);
      if (requestId === undefined) fail('HeldRequestIndexMissing');
      subject = {kind: 'prepare_attempt',
        prepareAttemptId: view.prepareAttemptId, requestId};
    } else {
      subject = {kind: 'run_unit', runId: view.runId,
        runDefinitionCid: view.runDefinitionCid};
    }
    return Object.freeze({checkpointId: view.checkpointId,
      checkpointCid: view.checkpointCid, kind: view.kind, phase: view.phase,
      subject, requiredArtifact: {type: view.requiredArtifact.type,
        cid: view.requiredArtifact.cid},
      reviewProjectionCid: view.reviewProjectionCid,
      requirements: [...view.requirements], createdAt: view.createdAt,
      expiresAt: view.expiresAt, humanSummary: view.humanSummary,
      ...modelCheckpointMetadata(journal, view)});
  };

  async function modelStoredContinuation(view: View) {
    if (view?.kind !== 'model_invocation' || view.prepareAttemptId !== null) {
      fail('InvalidInstalledModelContinuation');
    }
    const held = await evidence.open(`model-${view.runId}`);
    if (held.requestCid !== view.runDefinitionCid) fail('ModelContinuationRunMismatch');
    const record = await held.record('continuation_record', view.continuationStateCid) as StoredContinuation | null;
    if (record?.version !== MODEL_CHECKPOINT_STORAGE ||
        record.run_definition_cid !== view.runDefinitionCid ||
        record.model_invocation_scope_cid !== view.requiredArtifact.cid ||
        record.review_projection_cid !== view.reviewProjectionCid ||
        !/^sha256:[0-9a-f]{64}$/u.test(record.review_storage_cid ?? '') ||
        typeof record.continuation_wire !== 'string') {
      fail('InvalidInstalledModelContinuation');
    }
    return {held, record};
  }

  return {modelStoredContinuation, review: {
    async listCheckpoints(input: CheckpointList) {
      const {principalId, after, limit, checkpointId} = input;
      if (!(principalId === ownerPrincipal || readers.has(principalId) ||
          answerers.has(principalId))) {
        fail('CheckpointListDenied');
      }
      const lookup = Object.hasOwn(input, 'checkpointId');
      // This empty shape probes only the public Owner's identifier class. It
      // is not a Journal observation or a fabricated lookup return value.
      if (lookup && (after !== '' || limit !== 1 ||
          !validCheckpointLookup({items: []}, checkpointId!))) {
        fail('InvalidCheckpointLookup');
      }
      journal.expire();
      if (lookup) {
        // Inspect uses this same Journal's exact ID/CID index and refuses
        // ambiguous IDs. A CID fallback is not an ID match or a new grant.
        const view = journal.inspect(checkpointId!);
        if (view === undefined || view.checkpointId !== checkpointId || view.closure !== 'open') {
          return Object.freeze({items: []});
        }
        const summary = await summaryOf(view);
        const current = journal.inspect(view.checkpointCid);
        if (current?.checkpointId !== checkpointId || current!.closure !== 'open') {
          return Object.freeze({items: []});
        }
        return Object.freeze({items: [summary]});
      }
      const bounded = Math.min(limit, MAX_PAGE);
      // Journal.listPending attaches the cursor whenever the caller supplies a limit.
      const rows = journal.listPending({after: after === '' ? undefined
        : after, limit: bounded + 1}) as readonly (View & Readonly<{cursor?: string}>)[];
      const page = rows.slice(0, bounded);
      return Object.freeze({items: await Promise.all(page.map(summaryOf)),
        ...(rows.length > bounded ? {next: page.at(-1)!.cursor} : {})});
    },

    // The ordinary Local default signs only an explicitly selected original
    // Checkpoint, never arbitrary caller DATA. These current decisions are
    // distinct from the Effect Delegate/approval and the actual key/use claim.
    async localSigningContext({principalId, summary, signingResource, signal}: SigningContext) {
      if (principalId !== ownerPrincipal || !answerers.has(principalId) ||
          !readers.has(principalId) || typeof signingResource !== 'string') {
        fail('CheckpointAnswerDenied');
      }
      const original = journal.originalCheckpointForSigning(summary?.checkpointCid!);
      if (original.view.kind !== 'effect_set' || original.view.prepareAttemptId !== null ||
          original.view.closure !== 'open' ||
          canonicalValueJson(await summaryOf(original.view)) !== canonicalValueJson(summary)) {
        fail('LocalSigningOriginalConflict');
      }
      const decisions: Awaited<ReturnType<Gate['authorize']>>[] = [];
      for (const [resource, operation] of [['run', 'read'], ['run', 'resolve'], [signingResource, 'sign']] as const) {
        signal?.throwIfAborted();
        const decision = await gate.authorize('preparation',
          {connection: siteKey, resource, operation},
          {subjectCid: original.view.checkpointCid, signal});
        if (decision.action !== 'dispatch') throw new ExecutionAuthorizationError(decision);
        decisions.push(decision);
      }
      const assertCurrent = () => {
        signal?.throwIfAborted();
        if (ports.closed) fail('ClientHostClosing');
        gate.assertConfigurationCurrent();
        for (const decision of decisions) gate.assertAccountCurrent(decision);
        const current = journal.originalCheckpointForSigning(original.view.checkpointCid);
        if (current.wire !== original.wire || current.view.closure !== 'open') {
          fail('LocalSigningOriginalConflict');
        }
        // Keep the original optional observation. The SQLite Run projection
        // currently only supplies the committed status here.
        const state = journal.getRunState(original.view.runId!) as
          (NonNullable<ReturnType<Journal['getRunState']>> & Readonly<{cancelRequested?: boolean}>) | undefined;
        if (state?.status !== 'waiting_checkpoint' || state.cancelRequested === true) {
          fail('LocalSigningOriginalConflict');
        }
      };
      assertCurrent();
      return Object.freeze({...original, configurationCid: gate.configurationCid,
        assertCurrent});
    },

    async reviewCheckpoint({principalId, checkpointCid, maxBytes, signal}: ReviewInput) {
      if (!readers.has(principalId)) fail('CheckpointReviewDenied');
      const view = journal.inspect(checkpointCid);
      // Only a Checkpoint of this Host scope, named by its exact CID, and
      // only its own review projection; never an arbitrary Store CID.
      if (view === undefined || view.checkpointCid !== checkpointCid ||
          view.prepareAttemptId === null &&
            !['effect_set', 'read_access', 'model_invocation'].includes(view.kind)) {
        fail('CheckpointReviewDenied');
      }
      if (view.closure === 'expired' || view.closure === 'cancelled') {
        fail('CheckpointReviewUnavailable');
      }
      signal?.throwIfAborted();
      const bound = Math.min(maxBytes, maxReviewBytes);
      let bytes;
      try {
        if (view.kind === 'model_invocation') {
          const {held, record} = await modelStoredContinuation(view);
          bytes = await held.bytes('review_projection', record.review_storage_cid,
            {maxBytes: bound});
          const wire = new TextDecoder('utf-8', {fatal: true}).decode(bytes);
          const review = contractControl.admitRunEvidence('run_review_projection', wire,
            {maxWireBytes: bound, maxNodes: 10000, maxDepth: 64});
          if (review.wire !== wire || review.identity !== view.reviewProjectionCid) {
            fail('ModelReviewProjectionMismatch');
          }
        } else if (view.kind === 'effect_set' && view.prepareAttemptId === null) {
          const opened = await evidence.open(`effect-${view.runId}`);
          if (opened.requestCid !== view.runDefinitionCid) fail('EffectContinuationRunMismatch');
          bytes = await opened.artifactBytes('review_projection', view.reviewProjectionCid,
            {maxBytes: bound});
          const wire = new TextDecoder('utf-8', {fatal: true}).decode(bytes);
          const review = contractControl.admitRunEvidence('review_projection', wire,
            {...INSTALLED_EFFECT_CHECKPOINT_LIMITS, maxWireBytes: bound});
          if (review.wire !== wire || review.identity !== view.reviewProjectionCid) {
            fail('EffectReviewProjectionMismatch');
          }
          const body = JSON.parse(wire);
          if (body.effect_preview_cid !== view.requiredArtifact.cid ||
              body.authority_scope_cid !== authorityScopeCid ||
              JSON.stringify(body.approval_claims) !== JSON.stringify(view.requirements)) {
            fail('EffectReviewProjectionMismatch');
          }
        } else {
          const opened = await evidence.open(view.prepareAttemptId ?? `effect-${view.runId}`);
          bytes = await opened.bytes('review_projection',
            view.reviewProjectionCid, {maxBytes: bound});
        }
      } catch (error) {
        if ((error as ErrorCode)?.code === 'EvidenceReadLimitExceeded') {
          fail('CheckpointReviewTooLarge');
        }
        fail('CheckpointReviewUnavailable', error);
      }
      signal?.throwIfAborted();
      return Object.freeze({kind: 'review', checkpointCid,
        artifactCid: view.reviewProjectionCid, byteLength: bytes.byteLength,
        contentBase64: bytes.toString('base64')});
    },

    // Admit each signed answer on its own. The authenticated principal must
    // be the principal of the trusted reviewer whose key signed it; the
    // caller's claims about itself are never used.
    async resolve({principalId, items}: ResolutionInput) {
      if (!answerers.has(principalId)) fail('CheckpointAnswerDenied');
      const results = new Array<ResolutionResult>(items.length);
      const admitted: ResolutionInputs[number][] = [];
      const positions: number[] = [];
      items.forEach((item, index) => {
        let reviewer;
        try {
          const resolution = JSON.parse(item.resolutionWire);
          reviewer = trusted.get(resolution?.proof?.key_id);
          if (resolution?.checkpoint_cid !== item.checkpointCid) {
            throw coded('ResolutionCheckpointMismatch');
          }
        } catch (error) {
          results[index] = {checkpointCid: item.checkpointCid,
            status: 'invalid', reason: (error as ErrorCode)?.code ?? 'InvalidResolution'};
          return;
        }
        if (reviewer === undefined || reviewer.principalId !== principalId) {
          results[index] = {checkpointCid: item.checkpointCid,
            status: 'invalid', reason: 'AnswerPrincipalMismatch'};
          return;
        }
        admitted.push({checkpointCid: item.checkpointCid,
          resolutionWire: item.resolutionWire,
          approvalEvidenceWire: item.approvalEvidenceWire});
        positions.push(index);
      });
      if (admitted.length > 0) {
        const answered = await journal.submitResolutions(admitted);
        answered.forEach((result: ResolutionResult, position) => {
          results[positions[position]] = Object.fromEntries(
            (['checkpointCid', 'status', 'decision', 'resolutionCid', 'reason'] as const)
              .filter(key => result[key] !== undefined && result[key] !== null)
              .map(key => [key, result[key]])) as ResolutionResult;
        });
      }
      // The answer is stored; resuming is this Host's separate work. A Host
      // that only records answers leaves the durable intent to the next
      // Host start (for example a separate executing Host process).
      if (resumeAfterAnswer && results.some(result =>
        result.status === 'committed' && result.decision === 'approved')) {
        void sweep();
      }
      return Object.freeze({results: results.map(item =>
        Object.freeze(item))});
    },

  }};
}
