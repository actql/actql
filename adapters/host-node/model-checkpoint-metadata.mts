// Public metadata is a projection of the journal's checked retained originals.
// It is neither a caller-supplied approval alias nor permission to read inputs.
const cid = (value: unknown): value is string => typeof value === 'string' && /^sha256:[0-9a-f]{64}$/u.test(value);
const fail: () => never = () => {
  throw Object.assign(new TypeError('InvalidModelCheckpointMetadata'),
    {code: 'InvalidModelCheckpointMetadata'});
};

type CheckpointView = Readonly<{
  kind: string;
  prepareAttemptId: string | null;
  phase: string;
  checkpointCid: string;
  runId: string | null;
  runDefinitionCid: string | null;
  reviewProjectionCid: string;
  requiredArtifact?: Readonly<{type: string; cid: string}> | null;
}>;
type CheckpointJournal = Readonly<{modelCheckpointSummary?(checkpointCid: string): unknown}>;

export function modelCheckpointMetadata(journal: CheckpointJournal, view: CheckpointView) {
  if (view.kind !== 'model_invocation') return Object.freeze({});
  if (view.prepareAttemptId !== null || view.phase !== 'preflight' ||
      view.requiredArtifact?.type !== 'model_invocation_scope' ||
      typeof journal.modelCheckpointSummary !== 'function') fail();
  const checked = journal.modelCheckpointSummary(view.checkpointCid) as Record<string, unknown> | null | undefined;
  if (checked === null || typeof checked !== 'object' ||
      checked.checkpointCid !== view.checkpointCid ||
      checked.runId !== view.runId ||
      checked.runDefinitionCid !== view.runDefinitionCid ||
      checked.scopeCid !== view.requiredArtifact.cid ||
      checked.reviewProjectionCid !== view.reviewProjectionCid ||
      !cid(checked.preparedInvocationCid)) fail();
  return Object.freeze({preparedInvocationCid: checked.preparedInvocationCid});
}
