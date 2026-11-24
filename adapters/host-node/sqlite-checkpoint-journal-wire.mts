import type {WireCheckpointSummary} from '../../packages/client-wire/index.d.ts';
import type {AdmissionRow, CheckpointRow, PreparationRow} from './sqlite-checkpoint-journal-storage.mjs';

type ReviewerIdentity = Readonly<{keyId?: unknown; reviewerId?: unknown}>;
export type ResumeBinding = Readonly<{authorizationContextCid?: unknown; environmentBindingCid?: unknown}>;
type CoreResult<Result extends object> = Readonly<{ok: true}> & Result;
type CoreFailure = Readonly<{ok: false; detail?: unknown; issue: string}>;

// Shape of the wire already admitted by checkpoint_runtime before projection.
// Retain its original snake_case fields until the inspection view is built.
export type CheckpointArtifact = Readonly<{
  checkpoint_id: string; checkpoint_cid: string;
  continuation_state_cid: string; review_projection_cid: string;
  required_artifact: Readonly<{artifact_type: string; artifact_cid: string}>;
  phase: WireCheckpointSummary['phase']; kind: WireCheckpointSummary['kind'];
  requirements: readonly string[]; reason_code: string; human_summary: string;
  created_at: string; expires_at: string;
}> & (Readonly<{
  run_id?: never; run_definition_cid?: never;
  subject: Readonly<{kind: 'prepare_attempt'; prepare_attempt_id: string; continuation: 'start_run'}>;
}> | Readonly<{
  run_id: string; run_definition_cid: string;
  subject: Readonly<{kind: 'run_unit'; run_id: string; unit_id: string;
    continuation: 'resume_unit'; prepare_attempt_id?: never}>;
}>);

export const fail: (code: string, cause?: unknown) => never = (code, cause) => {
  throw Object.assign(new Error(code, {cause}), {code});
};
export const text = (value: unknown): value is string => typeof value === 'string' && value.length > 0;
export const cid = (value: unknown): value is string => typeof value === 'string' &&
  /^sha256:[0-9a-f]{64}$/u.test(value);

export function core<Result extends object>(result: string, code: string): CoreResult<Result> {
  const value = JSON.parse(result) as CoreResult<Result> | CoreFailure;
  if (value.ok !== true) {
    const error = Object.assign(new Error(code, {
      cause: value.detail ?? value.issue,
    }), {code, issueCode: value.issue});
    throw error;
  }
  return value;
}

export function iso(ms: number) {
  if (!Number.isSafeInteger(ms) || ms < 0) fail('InvalidJournalClock');
  return new Date(ms).toISOString();
}

export function authoritiesJson(authorities: unknown) {
  if (!Array.isArray(authorities) || authorities.length === 0) {
    fail('InvalidReviewerAuthorities');
  }
  return JSON.stringify(authorities.map((authority: ReviewerIdentity | null | undefined) => {
    if (!text(authority?.keyId) || !text(authority?.reviewerId)) {
      fail('InvalidReviewerAuthorities');
    }
    return {key_id: authority.keyId, reviewer_id: authority.reviewerId};
  }));
}

export function bindingJson(binding: ResumeBinding | null | undefined) {
  if (!text(binding?.authorizationContextCid) ||
      !text(binding?.environmentBindingCid)) {
    fail('InvalidResumeBinding');
  }
  return JSON.stringify({
    authorization_context_cid: binding.authorizationContextCid,
    environment_binding_cid: binding.environmentBindingCid,
  });
}

export function declaredJson(results: unknown) {
  if (!Array.isArray(results) || !results.every(text) ||
      new Set(results).size !== results.length) {
    fail('InvalidDeclaredResults');
  }
  return JSON.stringify(results);
}

export function effectsJson(effects: unknown) {
  if (!Array.isArray(effects) || !effects.every(text) ||
      new Set(effects).size !== effects.length) {
    fail('InvalidUnknownEffects');
  }
  return JSON.stringify(effects);
}

// Exact decision-subject binding stored next to a Checkpoint (for example
// the gate's digest of the ten-field decision subject). Optional: '' when the
// Checkpoint was persisted without one.
export function subjectBinding(value: unknown) {
  if (value === undefined || value === null) return '';
  if (typeof value !== 'string' || !/^sha256:[0-9a-f]{64}$/.test(value)) {
    fail('InvalidDecisionSubjectBinding');
  }
  return value;
}

// The durable identity of one protected send, recorded with its admission;
// '' when the send has none.
export function admissionIdentity(value: unknown) {
  if (value === undefined || value === null) return '';
  if (!text(value)) fail('InvalidDispatchIdentity');
  return value;
}

export const priorAdmissionView = (row: AdmissionRow) => Object.freeze({
  generation: Number(row.generation),
  claimant: row.claimant,
  admittedAt: row.admitted_at,
  dispatchIdentity: row.dispatch_identity === '' ? null
    : row.dispatch_identity,
});

// Claims the Host required of the decision when it deferred it, bound next to
// the Checkpoint: the decision request's own claims, never claims an answer
// establishes. Sorted and unique; '[]' when none were requested.
export function requestedClaimsJson(value: unknown) {
  if (value === undefined || value === null) return '[]';
  if (!Array.isArray(value) || !value.every(text) ||
      new Set(value).size !== value.length) {
    fail('InvalidRequestedClaims');
  }
  return JSON.stringify([...value].sort());
}

// Account configuration CID the deferring gate evaluated the decision under,
// bound next to the Checkpoint. A resume admits no dispatch under another
// configuration, whatever the current account outcome. '' when the
// Checkpoint was persisted without one (then no resume dispatch is admitted
// by the gate).
export function configurationBinding(value: unknown) {
  if (value === undefined || value === null) return '';
  if (typeof value !== 'string' || !/^sha256:[0-9a-f]{64}$/.test(value)) {
    fail('InvalidConfigurationBinding');
  }
  return value;
}

// Safe inspection view: identities, the review subject reference, and the
// non-restricted metadata sealed in the Checkpoint. No review projection
// contents, evidence, or Host authority configuration are returned.
export function checkpointView(
  wire: string,
  row: Pick<CheckpointRow, 'decision_subject_cid' | 'requested_claims_json' | 'closure' | 'resolution_cid'>,
) {
  const artifact = JSON.parse(wire) as CheckpointArtifact;
  return Object.freeze({
    checkpointCid: artifact.checkpoint_cid,
    checkpointId: artifact.checkpoint_id,
    runId: artifact.run_id ?? null,
    runDefinitionCid: artifact.run_definition_cid ?? null,
    prepareAttemptId: artifact.subject.prepare_attempt_id ?? null,
    subject: Object.freeze({...artifact.subject}),
    phase: artifact.phase,
    kind: artifact.kind,
    requiredArtifact: Object.freeze({
      type: artifact.required_artifact.artifact_type,
      cid: artifact.required_artifact.artifact_cid,
    }),
    reviewProjectionCid: artifact.review_projection_cid,
    continuationStateCid: artifact.continuation_state_cid,
    requirements: Object.freeze([...artifact.requirements]),
    reasonCode: artifact.reason_code,
    humanSummary: artifact.human_summary,
    createdAt: artifact.created_at,
    expiresAt: artifact.expires_at,
    decisionSubjectCid: row.decision_subject_cid === '' ? null :
      row.decision_subject_cid,
    requestedClaims: Object.freeze(JSON.parse(row.requested_claims_json) as string[]),
    closure: row.closure,
    resolutionCid: row.resolution_cid === '' ? null : row.resolution_cid,
  });
}

export function preparationView(row: PreparationRow) {
  return Object.freeze({
    prepareAttemptId: row.prepare_attempt_id,
    status: row.status,
    version: Number(row.version),
    checkpointCid: row.checkpoint_cid === '' ? null : row.checkpoint_cid,
    runId: row.run_id === '' ? null : row.run_id,
    endReason: row.end_reason === '' ? null : row.end_reason,
    terminalErrorCode: row.terminal_error_code === '' ? null :
      row.terminal_error_code,
    cancelRequested: row.cancel_requested === 1,
  });
}
