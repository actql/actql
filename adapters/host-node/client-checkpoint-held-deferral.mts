// The existing held Checkpoint owns these request, invocation and review
// bindings until approval. These projections do not issue a Run or grant
// the Source read; the installed authorization and Journal still decide.
import {canonicalJson, contentCid} from './local-account-config.mjs';
import {BOUND_SOURCE_SUBMISSION} from './ordinary-source-binding.mjs';
import {capturedValueCid, capturedValueWire, fail, hex, occurrenceIdentity, occurrenceKey,
  pluralCapture} from './client-checkpoint-admission-inputs.mjs';

import type {CapturedOccurrence, SourceCapture} from './client-checkpoint-admission-inputs.mjs';
import type {openContinuationEvidence} from './local-continuation-evidence.mjs';
import type {createLocalAuthorizationGate} from './local-account-config.mjs';
import type {openSqliteCheckpointJournal} from './sqlite-checkpoint-journal.mjs';
import type {ResumeBinding} from './sqlite-checkpoint-journal-wire.mjs';

type Journal = ReturnType<typeof openSqliteCheckpointJournal>;
type GateOptions = NonNullable<Parameters<typeof createLocalAuthorizationGate>[0]>;
type AuthorizationView = Parameters<NonNullable<GateOptions['deferral']>['describe']>[0];
type Gate = Pick<Awaited<ReturnType<typeof createLocalAuthorizationGate>>, 'contextCid' | 'configurationCid'>;
type RequestIdentity = Readonly<{logicalRequestScopeCid: string; intentFingerprintCid: string}>;
export type CapturedRequest = SourceCapture & Readonly<{
  requestId: string; principalId: string; parameters: unknown; resultNames: readonly string[];
  submission?: unknown;
}> & (Readonly<{kind: 'aql'; input: Readonly<{format: string; text: string}>}> |
  Readonly<{kind: 'program'; input: unknown}>);
type HeldRequest = Readonly<{
  prepareAttemptId: string; request: Readonly<{subject_cid: string}>;
  requestCid: string; captured: CapturedRequest; answering: readonly string[];
}>;
type HeldSourceRequest<Port> = HeldRequest & Readonly<{
  occurrence: CapturedOccurrence; port: Port; earlier?: readonly string[];
}>;
type Ports = Readonly<{
  authorityScopeCid: string; namespaceId: string; siteKey: string; realizationKey: string;
  journal: Journal; authorities: readonly Readonly<{keyId: string; reviewerId: string}>[];
  binding: ResumeBinding; evidence: Pick<ReturnType<typeof openContinuationEvidence>, 'reference' | 'hold'>;
  gate: Gate; now(): number; checkpointTtlMs: number; maxReviewBytes: number;
  installedSource(occurrence: CapturedOccurrence): Readonly<{gate: Gate}>;
  recordHeld(prepareAttemptId: string, requestId: string): Promise<void>;
}>;

export function createHeldCheckpointDeferrals({authorityScopeCid, namespaceId, siteKey,
  realizationKey, journal, authorities, binding, evidence, gate, now,
  checkpointTtlMs, maxReviewBytes, installedSource, recordHeld}: Ports) {
  // The Host-resolved request: this installation scope, the caller's request
  // identity and intent, and the Site and realization it would run on. The
  // caller supplies none of these values directly.
  const requestSubject = (requested: RequestIdentity) => Object.freeze({
    version: 'actql-remote-run-acceptance-request/0.1',
    authority_scope_cid: authorityScopeCid,
    namespace_id: namespaceId,
    logical_request_scope_cid: requested.logicalRequestScopeCid,
    intent_fingerprint_cid: requested.intentFingerprintCid,
    site_key: siteKey,
    realization_key: realizationKey,
  });
  // One prepare attempt per request of this installation scope, found again
  // from the request ID alone (a lookup has no Program).
  const prepareAttemptIdOf = (requestId: string) => `prepare-${hex(canonicalJson({
    authority_scope_cid: authorityScopeCid, namespace_id: namespaceId,
    request_id: requestId})).slice(0, 40)}`;

  function deferralFor({prepareAttemptId, request, requestCid, captured,
    answering}: HeldRequest) {
    return {
      journal,
      authorities,
      binding,
      async describe(view: AuthorizationView) {
        const capturedWire = capturedValueWire(captured);
        const invocation = {
          version: 'actql-remote-prepared-invocation/0.1',
          request_cid: requestCid,
          captured_submission_cid: capturedValueCid(captured),
          site_key: siteKey,
          realization_key: realizationKey,
        };
        const invocationCid = contentCid(invocation);
        const created = now();
        const expiresAt = new Date(created + checkpointTtlMs).toISOString();
        const displayed = {
          request_id: captured.requestId,
          kind: captured.kind,
          format: captured.kind === 'aql' ? captured.input.format : 'json',
          document: captured.kind === 'aql' ? captured.input.text
            : captured.input,
          parameters: captured.parameters,
          site_key: siteKey,
          realization_key: realizationKey,
          operation: 'write',
        };
        const projection: Record<string, unknown> = {
          version: 'actql-run-review-projection/0.1',
          prepared_invocation_cid: invocationCid,
          execution_context_cid: gate.contextCid,
          host_policy_cid: gate.configurationCid,
          approval_claims: ['invocation_scope_approved'],
          authoring_context_cid: contentCid({principal: captured.principalId,
            request_id: captured.requestId}),
          redaction_policy_cid: contentCid({version:
            'actql-remote-review-redaction/0.1', redacted: []}),
          sensitivity: 'restricted',
          retention_class: 'approval-evidence',
          encryption_required: true,
          expires_at: expiresAt,
          displayed_scope: displayed,
          displayed_authoring_context: [{principal: captured.principalId}],
        };
        projection.review_projection_cid = capturedValueCid(projection);
        const reviewWire = capturedValueWire(projection);
        if (Buffer.byteLength(reviewWire, 'utf8') > maxReviewBytes) {
          fail('CheckpointReviewTooLarge');
        }
        const reviewCid = capturedValueCid(JSON.parse(reviewWire));
        const items = [
          {name: 'captured_input', wire: capturedWire},
          {name: 'invocation_request', wire: canonicalJson(request)},
          {name: 'prepared_invocation', wire: canonicalJson(invocation)},
          {name: 'review_projection', wire: reviewWire},
        ];
        const continuation = {
          version: 'actql-remote-continuation/0.1',
          prepare_attempt_id: prepareAttemptId,
          boundary: view.boundary,
          invocation_cid: invocationCid,
          request_subject_cid: request.subject_cid,
          request_id: captured.requestId,
          delegated_subject: JSON.parse(JSON.stringify(view.subject)),
          answering_authorities: [...answering],
          evidence: items.map(({name, wire}) =>
            evidence.reference(prepareAttemptId, name, wire)),
        };
        const continuationCid = contentCid(continuation);
        await evidence.hold(prepareAttemptId, requestCid, [...items,
          {name: 'continuation_record', wire: canonicalJson(continuation)}]);
        return {
          priorStatus: undefined,
          declaredResults: [...captured.resultNames],
          binding,
          body: {
            checkpoint_id: `${prepareAttemptId}-preparation`,
            continuation_state_cid: continuationCid,
            subject: {kind: 'prepare_attempt',
              prepare_attempt_id: prepareAttemptId, continuation: 'start_run'},
            kind: 'run_scope',
            required_artifact: {artifact_type: 'prepared_invocation',
              artifact_cid: invocationCid},
            review_projection_cid: reviewCid,
            human_summary: `Run request ${captured.requestId} on ${siteKey}`,
            created_at: new Date(created).toISOString(),
            expires_at: expiresAt,
          },
        };
      },
    };
  }

  // The pre-acquisition binding of a held read: the request, the exact
  // captured submission, the Host-checked source and the Host-resolved read
  // tuple. It is not a Prepared Invocation: the formal invocation depends on
  // the later source observation and is issued by its owner after it.
  const acquisitionIntent = (requestCid: string, captured: SourceCapture, occurrence: CapturedOccurrence) => ({
    version: pluralCapture(captured)
      ? 'actql-remote-multi-source-acquisition-intent/0.1'
      : 'actql-remote-acquisition-intent/0.1',
    request_cid: requestCid,
    captured_submission_cid: capturedValueCid(captured),
    ...(pluralCapture(captured)
      ? {occurrence: occurrenceIdentity(occurrence)} : {}),
    checked_source: occurrence.checkedSource,
    read_tuple: occurrence.readTuple,
    physical_binding: occurrence.physicalBinding,
    ...(captured.version === BOUND_SOURCE_SUBMISSION
      ? {installation_binding: occurrence.installationBinding} : {}),
  });

  // The durable deferral of a request's source read (`read_access`,
  // `prepare_attempt`). `port` persists the Checkpoint: the journal for a new
  // held request, or the current resume claim for one already resuming.
  // `earlier` names the approvals this attempt already holds (checked again
  // on their own before the start).
  function readDeferralFor<Port extends Pick<Journal, 'persistCheckpoint' | 'submitResolution'>>({prepareAttemptId, request, requestCid, captured,
    occurrence, answering, port, earlier = []}: HeldSourceRequest<Port>) {
    const {gate: readGate} = installedSource(occurrence);
    return {
      journal: port,
      authorities,
      binding,
      async describe(view: AuthorizationView) {
        const intent = acquisitionIntent(requestCid, captured, occurrence);
        const intentCid = capturedValueCid(intent);
        const created = now();
        const expiresAt = new Date(created + checkpointTtlMs).toISOString();
        const projection: Record<string, unknown> = {
          version: 'actql-run-review-projection/0.1',
          prepared_invocation_cid: intentCid,
          execution_context_cid: readGate.contextCid,
          host_policy_cid: readGate.configurationCid,
          approval_claims: ['invocation_scope_approved'],
          authoring_context_cid: contentCid({principal: captured.principalId,
            request_id: captured.requestId}),
          redaction_policy_cid: contentCid({version:
            'actql-remote-review-redaction/0.1', redacted: []}),
          sensitivity: 'restricted',
          retention_class: 'approval-evidence',
          encryption_required: true,
          expires_at: expiresAt,
          displayed_scope: {
            request_id: captured.requestId,
            kind: captured.kind,
            format: captured.kind === 'aql' ? captured.input.format : 'json',
            document: captured.kind === 'aql' ? captured.input.text
              : captured.input,
            parameters: captured.parameters,
            source: occurrence.checkedSource,
            read_tuple: occurrence.readTuple,
            physical_binding: occurrence.physicalBinding,
            ...(pluralCapture(captured)
              ? {occurrence: occurrenceIdentity(occurrence)} : {}),
          },
          displayed_authoring_context: [{principal: captured.principalId}],
        };
        projection.review_projection_cid = capturedValueCid(projection);
        const reviewWire = capturedValueWire(projection);
        if (Buffer.byteLength(reviewWire, 'utf8') > maxReviewBytes) {
          fail('CheckpointReviewTooLarge');
        }
        const reviewCid = capturedValueCid(JSON.parse(reviewWire));
        const items = [
          {name: 'captured_input', wire: capturedValueWire(captured)},
          {name: 'invocation_request', wire: canonicalJson(request)},
          // The Store's prepared-invocation slot holds the acquisition
          // intent (a distinct version), never a fabricated invocation.
          {name: 'prepared_invocation', wire: capturedValueWire(intent)},
          {name: 'review_projection', wire: reviewWire},
        ];
        const continuation = {
          version: 'actql-remote-continuation/0.1',
          prepare_attempt_id: prepareAttemptId,
          boundary: view.boundary,
          invocation_cid: intentCid,
          request_subject_cid: request.subject_cid,
          request_id: captured.requestId,
          delegated_subject: JSON.parse(JSON.stringify(view.subject)),
          answering_authorities: [...answering],
          earlier_approvals: [...earlier],
          ...(pluralCapture(captured)
            ? {acquisition_occurrence: occurrenceIdentity(occurrence)} : {}),
          evidence: items.map(({name, wire}) =>
            evidence.reference(prepareAttemptId, name, wire)),
        };
        const continuationCid = contentCid(continuation);
        await recordHeld(prepareAttemptId, captured.requestId);
        await evidence.hold(prepareAttemptId, requestCid, [...items,
          {name: 'continuation_record', wire: canonicalJson(continuation)}]);
        return {
          priorStatus: undefined,
          declaredResults: [...captured.resultNames],
          binding,
          body: {
            checkpoint_id: `${prepareAttemptId}-acquisition` +
              (pluralCapture(captured)
                ? `-${hex(occurrenceKey(occurrence)).slice(0, 20)}` : ''),
            continuation_state_cid: continuationCid,
            subject: {kind: 'prepare_attempt',
              prepare_attempt_id: prepareAttemptId, continuation: 'start_run'},
            kind: 'read_access',
            required_artifact: {artifact_type: 'read_scope',
              artifact_cid: intentCid},
            review_projection_cid: reviewCid,
            human_summary: `Read ${occurrence.checkedSource.sourceRef}` +
              ` for request ${captured.requestId}`,
            created_at: new Date(created).toISOString(),
            expires_at: expiresAt,
          },
        };
      },
    };
  }

  return {requestSubject, prepareAttemptIdOf, deferralFor, acquisitionIntent, readDeferralFor};
}
