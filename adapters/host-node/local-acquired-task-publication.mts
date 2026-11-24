import {checkedLocalOutputLimits} from './local-publication-limit-projection.mjs';
import {localContractLimits as limits} from './local-publication-limits.mjs';
import {localPublicationPlan, localRetentionTimes, retentionDependencies} from './local-publication-plan.mjs';

import type {acquiredTaskRunAdmission, sourceFreeTaskPlan} from './local-source-free-plan.mjs';

type TaskAdmission = ReturnType<typeof acquiredTaskRunAdmission>;
type SourceFreePorts<Retention> = Parameters<typeof sourceFreeTaskPlan<Retention>>[0];
type PublicationOriginal = SourceFreePorts<unknown>['publicationOriginal'];
type SourceCapture = Readonly<{
  source(): unknown;
  originalWholeInput?: () => unknown;
}>;
type CapturedSource = Readonly<{
  logicalInput?: unknown;
  checkedSource?: unknown;
  identity?: unknown;
  requirement?: unknown;
  inputKind?: string;
  wholeCapacity?: unknown;
  capture: SourceCapture;
}>;
type Occurrence = Readonly<{captured: CapturedSource; sourceEvidence: unknown}>;
type SourceWindow = Readonly<{
  authorityScopeCid: string; captureStartedAt: string; captureCompletedAt: string;
}>;
type SourceBinding = SourceWindow & (
  | {captured: CapturedSource; sourceEvidence: unknown; keyedObservation?: unknown}
  | {sources: readonly Occurrence[]}
);
type PublicationBindings = SourceFreePorts<unknown>['moon'] & {
  clientProgramCapturedSourceMatches(program: unknown, source: unknown): boolean;
  clientProgramCapturedTaskSourceMatches(program: unknown, source: unknown, task: number): boolean;
  clientProgramCapturedSourceLogicalCid(identity: unknown): string;
  clientProgramPublicationDataPolicyCid(program: unknown): string | undefined;
};
type Projection = (moon: PublicationBindings, prepared: unknown,
  original: PublicationOriginal) => ReturnType<typeof checkedLocalOutputLimits>;
type TaskControl<Retention> = Parameters<typeof localPublicationPlan<Retention>>[0]['control'] &
  Pick<SourceFreePorts<Retention>['control'], 'checkClientCompiledRunOwner' | 'issueProgramInitialRetention'> & {
  issueCheckedClientCompiledInvocation(compiled: TaskAdmission['compiled'], definition: TaskAdmission['runDefinition'],
    policy: Readonly<{dataPolicyCid: string; source: SourceBinding}>, bounds: typeof limits,
    owner: unknown, prepared: unknown): Readonly<{observation: unknown; invocation: unknown}>;
};
type TaskOptions<Retention> = SourceWindow & {
  moon: PublicationBindings;
  control: TaskControl<Retention>;
  acquired: TaskAdmission;
  preparedProgram: unknown;
  publicationOriginal?: PublicationOriginal;
  effectiveDataPolicyCid: string;
  namespaceId: string;
  storeAuthorityCid: string;
  now(): string;
};
type DirectOptions<Retention> = TaskOptions<Retention> & Occurrence;
type PluralOptions<Retention> = TaskOptions<Retention> & {sources: readonly Occurrence[]};
type KeyedOptions<Retention> = DirectOptions<Retention> & {
  control: TaskControl<Retention> & {
    keyedLookupPublicationEvidence(observation: unknown): Readonly<{logicalRelationCid: string; source: unknown}>;
  };
  keyedObservation: Readonly<{observation: unknown}>;
};

// The connector/Acquisition owner supplies Source Evidence after completing
// physical capture and current authorization. This Host binds that evidence to
// the checked task Run and the captured relation before publication.
export function acquiredTaskPublicationPlan<Retention>({moon, control, acquired,
  preparedProgram, publicationOriginal, captured, sourceEvidence, authorityScopeCid,
  effectiveDataPolicyCid, captureStartedAt, captureCompletedAt, namespaceId,
  storeAuthorityCid, now}: DirectOptions<Retention>) {
  control.checkClientCompiledRunOwner(acquired.compiled, preparedProgram);
  if (sourceEvidence === undefined ||
      typeof effectiveDataPolicyCid !== 'string' ||
      captured?.logicalInput === undefined ||
      captured?.checkedSource === undefined ||
      captured?.identity === undefined ||
      captured?.capture === undefined ||
      moon.clientProgramCapturedSourceMatches(preparedProgram,
        captured.capture.source()) !== true) {
    throw new TypeError('InvalidAcquiredTaskPublication');
  }
  // The adopted capture constructor retains this SAME Program body. Grow
  // before the existing complete Source/lookup invocation checks so current
  // callbacks cannot invalidate an earlier capture check unnoticed.
  if ((acquired.publicationPreparation !== undefined || publicationOriginal?.kind === 'installed_run') &&
      (publicationOriginal?.kind !== 'installed_run' || acquired.publicationPreparation === undefined ||
        acquired.publicationPreparation !== publicationOriginal.value)) {
    throw new TypeError('OriginalProgramRetentionOwnerRequired');
  }
  const originalRetention = publicationOriginal?.kind !== 'installed_run' ? undefined :
    control.issueProgramInitialRetention(acquired.publicationPreparation, preparedProgram,
      acquired.requestIdentity, effectiveDataPolicyCid, localRetentionTimes(now), retentionDependencies, limits);
  const {observation, invocation} = control.issueCheckedClientCompiledInvocation(
    acquired.compiled, acquired.runDefinition,
    {dataPolicyCid: effectiveDataPolicyCid, source: {captured, sourceEvidence,
      authorityScopeCid, captureStartedAt, captureCompletedAt}}, limits,
    acquired.publicationPreparation, preparedProgram);
  return localPublicationPlan({control, originalRetention, admission: acquired.admission,
    runDefinition: acquired.runDefinition, invocation, observation,
    compiledPlanCid: acquired.compiledPlan.identity,
    programDefinitionCid: moon.clientProgramDefinitionCid(preparedProgram),
    inputRelationCids: [moon.clientProgramCapturedSourceLogicalCid(
      captured.identity)], sourceEvidence: [sourceEvidence],
    authorityScopeCid, namespaceId, storeAuthorityCid,
    dataPolicyCid: effectiveDataPolicyCid, createdAt: acquired.createdAt,
    now, resultCount: moon.clientProgramResultCount(preparedProgram),
    compiled: acquired.compiled, preparedProgram, publicationOriginal,
    authoringContextOriginal: acquired.authoringContextOriginal,
    ...(publicationOriginal === undefined ? {} : {
      outputLimits: (checkedLocalOutputLimits as Projection)(moon, preparedProgram, publicationOriginal),
    })});
}


// The existing checked publication owner receives the complete occurrence
// inventory. Each source evidence retains its own read policy; the final
// publication policy is the checker's join of exact Result contributors.
export function acquiredMultiTaskPublicationPlan<Retention>({moon, control, acquired,
  preparedProgram, publicationOriginal, sources, authorityScopeCid, effectiveDataPolicyCid,
  captureStartedAt, captureCompletedAt, namespaceId, storeAuthorityCid, now}: PluralOptions<Retention>) {
  control.checkClientCompiledRunOwner(acquired.compiled, preparedProgram);
  const whole = Array.isArray(sources) && sources.some(({captured}) => captured?.inputKind === 'whole-input');
  if (!Array.isArray(sources) || sources.length < 1 ||
      moon.clientProgramPublicationDataPolicyCid(preparedProgram) !== effectiveDataPolicyCid ||
      sources.some(({captured, sourceEvidence}, task) =>
        sourceEvidence === undefined || captured?.logicalInput === undefined ||
        captured?.identity === undefined || (whole
          ? captured.inputKind !== 'whole-input' || captured.wholeCapacity === undefined ||
            typeof captured.capture?.originalWholeInput !== 'function' || acquired.publicationPreparation === undefined
          : captured?.requirement === undefined ||
            !moon.clientProgramCapturedTaskSourceMatches(preparedProgram, captured.capture.source(), task)))) {
    throw new TypeError('InvalidAcquiredTaskPublication');
  }
  const observed = sources;
  // The adopted capture constructor retains this SAME Program body. Grow
  // before the existing complete Source/lookup invocation checks so current
  // callbacks cannot invalidate an earlier capture check unnoticed.
  if ((acquired.publicationPreparation !== undefined || publicationOriginal?.kind === 'installed_run') &&
      (publicationOriginal?.kind !== 'installed_run' || acquired.publicationPreparation === undefined ||
        acquired.publicationPreparation !== publicationOriginal.value)) {
    throw new TypeError('OriginalProgramRetentionOwnerRequired');
  }
  const originalRetention = publicationOriginal?.kind !== 'installed_run' ? undefined :
    control.issueProgramInitialRetention(acquired.publicationPreparation, preparedProgram,
      acquired.requestIdentity, effectiveDataPolicyCid, localRetentionTimes(now), retentionDependencies, limits);
  const {observation, invocation} = control.issueCheckedClientCompiledInvocation(
    acquired.compiled, acquired.runDefinition, {source: {sources: observed, authorityScopeCid,
      captureStartedAt, captureCompletedAt}, dataPolicyCid: effectiveDataPolicyCid}, limits,
    acquired.publicationPreparation, preparedProgram);
  return localPublicationPlan({control, originalRetention, admission: acquired.admission,
    runDefinition: acquired.runDefinition, invocation, observation,
    compiledPlanCid: acquired.compiledPlan.identity,
    programDefinitionCid: moon.clientProgramDefinitionCid(preparedProgram),
    // Result derivation records a unique set of logical content dependencies.
    // Equal content does not coalesce the occurrence-owned captures or either
    // Source Evidence entry retained above in the Observation Set.
    inputRelationCids: [...new Set(sources.map(source =>
      moon.clientProgramCapturedSourceLogicalCid(source.captured.identity)))],
    sourceEvidence: observed.map(source => source.sourceEvidence),
    authorityScopeCid, namespaceId, storeAuthorityCid,
    dataPolicyCid: effectiveDataPolicyCid, createdAt: acquired.createdAt,
    now, resultCount: moon.clientProgramResultCount(preparedProgram),
    compiled: acquired.compiled, preparedProgram, publicationOriginal,
    authoringContextOriginal: acquired.authoringContextOriginal,
    ...(publicationOriginal === undefined ? {} : {
      outputLimits: (checkedLocalOutputLimits as Projection)(moon, preparedProgram, publicationOriginal),
    })});
}

// A keyed JOIN completes a second Source, not a second Direct task prefix.
// Retain both Source evidence entries while reusing the admitted compilation
// and the ordinary Result publication/retention plan.
export function acquiredKeyedTaskPublicationPlan<Retention>({moon, control, acquired,
  preparedProgram, publicationOriginal, captured, sourceEvidence, keyedObservation,
  authorityScopeCid, effectiveDataPolicyCid, captureStartedAt, captureCompletedAt,
  namespaceId, storeAuthorityCid, now}: KeyedOptions<Retention>) {
  control.checkClientCompiledRunOwner(acquired.compiled, preparedProgram);
  if (sourceEvidence === undefined ||
      captured?.logicalInput === undefined || captured?.identity === undefined ||
      captured?.requirement === undefined || captured?.capture === undefined ||
      keyedObservation?.observation === undefined ||
      moon.clientProgramPublicationDataPolicyCid(preparedProgram) !== effectiveDataPolicyCid ||
      moon.clientProgramCapturedSourceMatches(preparedProgram, captured.capture.source()) !== true) {
    throw new TypeError('InvalidAcquiredTaskPublication');
  }
  // The adopted capture constructor retains this SAME Program body. Grow
  // before the existing complete Source/lookup invocation checks so current
  // callbacks cannot invalidate an earlier capture check unnoticed.
  if ((acquired.publicationPreparation !== undefined || publicationOriginal?.kind === 'installed_run') &&
      (publicationOriginal?.kind !== 'installed_run' || acquired.publicationPreparation === undefined ||
        acquired.publicationPreparation !== publicationOriginal.value)) {
    throw new TypeError('OriginalProgramRetentionOwnerRequired');
  }
  const originalRetention = publicationOriginal?.kind !== 'installed_run' ? undefined :
    control.issueProgramInitialRetention(acquired.publicationPreparation, preparedProgram,
      acquired.requestIdentity, effectiveDataPolicyCid, localRetentionTimes(now), retentionDependencies, limits);
  const right = control.keyedLookupPublicationEvidence(keyedObservation.observation);
  const left = sourceEvidence;
  const {observation, invocation} = control.issueCheckedClientCompiledInvocation(
    acquired.compiled, acquired.runDefinition, {source: {captured, sourceEvidence: left,
      keyedObservation: keyedObservation.observation, authorityScopeCid,
      captureStartedAt, captureCompletedAt}, dataPolicyCid: effectiveDataPolicyCid}, limits,
    acquired.publicationPreparation, preparedProgram);
  return localPublicationPlan({control, originalRetention, admission: acquired.admission,
    runDefinition: acquired.runDefinition, invocation, observation,
    compiledPlanCid: acquired.compiledPlan.identity,
    programDefinitionCid: moon.clientProgramDefinitionCid(preparedProgram),
    inputRelationCids: [...new Set([
      moon.clientProgramCapturedSourceLogicalCid(captured.identity),
      right.logicalRelationCid,
    ])],
    sourceEvidence: [left, right.source],
    authorityScopeCid, namespaceId, storeAuthorityCid,
    dataPolicyCid: effectiveDataPolicyCid, createdAt: acquired.createdAt,
    now, resultCount: moon.clientProgramResultCount(preparedProgram),
    compiled: acquired.compiled, preparedProgram, publicationOriginal,
    authoringContextOriginal: acquired.authoringContextOriginal,
    ...(publicationOriginal === undefined ? {} : {
      outputLimits: (checkedLocalOutputLimits as Projection)(moon, preparedProgram, publicationOriginal),
    })});
}
