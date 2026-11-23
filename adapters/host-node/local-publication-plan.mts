import {randomUUID} from 'node:crypto';
import {checked} from '../host-common/runtime-result.mjs';
import {localContractLimits as limits, localOutputLimits} from './local-publication-limits.mjs';
import {cid, policyCid, instant} from './local-query-invocation.mjs';

type ContractLimits = typeof limits;
type RetentionTimes = Readonly<{availableUntil: string; deleteBy: string; metadataDeleteBy: string}>;
type EffectRetentionTimes = RetentionTimes & Readonly<{
  expiresAt: string | undefined;
  retentionContractCid: string;
  metadataRetentionPolicyCid: string;
  clockContractCid: string;
}>;
type PublicationContract = Readonly<{identity: string; wire: string}>;
type CurrentAdmission = Readonly<{requestIdentity?: unknown}>;
type ManagedPublication = Readonly<{
  value: unknown;
  request: unknown;
  runtime: unknown;
  prepared: unknown;
  failure?: unknown;
  closed?: boolean;
  retiringContent?: boolean;
  retiringModel?: boolean;
}>;
type RetentionIssuer<Retention> = {
  seal(kind: 'result_retention_policy', wire: string, bounds: ContractLimits): Retention;
};
type ProgramRetentionIssuer<Retention> = {
  issueProgramInitialRetention(owner: unknown, prepared: unknown, request: unknown,
    policy: string, selection: RetentionTimes, contracts: typeof retentionDependencies,
    bounds: ContractLimits): Retention;
};
type PublicationIssuer<Retention> = RetentionIssuer<Retention> & {
  sealRunEvidence(kind: 'normalization_journal' | 'authoring_context', wire: string,
    bounds: ContractLimits): unknown;
  preparedClientNormalizationEvidence(prepared: unknown, bounds: ContractLimits): unknown;
  preparedClientAuthoringContextEvidence(prepared: unknown, original: unknown,
    bounds: ContractLimits): unknown;
  compiledRunResultTransformation(compiled: unknown, prepared: unknown, index: number): unknown;
};
type EffectResultBindings = {
  clientProgramEffectCompilationResultTransformation(compilation: object, prepared: unknown,
    index: number): unknown;
};
type PublicationPlanOptions<Retention> = {
  control: PublicationIssuer<Retention>;
  admission: unknown;
  runDefinition: PublicationContract;
  invocation: unknown;
  observation: unknown;
  compiledPlanCid: string;
  programDefinitionCid: string;
  inputRelationCids: readonly string[];
  sourceEvidence: readonly unknown[];
  authorityScopeCid: string;
  namespaceId: string;
  storeAuthorityCid: string;
  dataPolicyCid: string;
  createdAt: string;
  now(): string;
  resultCount: number;
  retainUntil?: string;
  compiled?: unknown;
  preparedProgram?: unknown;
  publicationOriginal?: Readonly<{authoringContext?: unknown}>;
  authoringContextOriginal?: unknown;
  modelEvidence?: readonly unknown[];
  outputLimits?: Readonly<Record<keyof typeof localOutputLimits, number | undefined>>;
  retentionSelection?: RetentionTimes;
  originalRetention?: Retention | null;
} & (
  | {effectCompilation: object; preparedEffect: unknown; moon: EffectResultBindings}
  | {effectCompilation?: undefined; preparedEffect?: undefined; moon?: EffectResultBindings}
);
type EffectAdmissionBindings = {
  clientProgramEffectCompilationCompiledPlanWire(compilation: unknown): string;
  clientProgramEffectCompilationTemplateWire(compilation: unknown): string;
  strategyRunEvidenceJson(evidence: unknown): string;
  clientProgramAllowedEffectRunPrepared(allowed: unknown): unknown;
  clientProgramAllowedEffectRunAuthorization(allowed: unknown): unknown;
  strategyPublicationContractJson(contract: unknown): string;
};
type EffectAdmissionControl = {
  admit(kind: 'compiled_plan' | 'run_definition', wire: string, bounds: ContractLimits): PublicationContract;
  originalCheckedClientEffectPublication?(allowed: unknown, definition: unknown,
    bounds: ContractLimits): {admission: unknown; runDefinition: PublicationContract};
  admitRunEvidence(kind: 'bound_invocation_template' | 'prepared_invocation' | 'run_authorization',
    wire: string, bounds: ContractLimits): unknown;
  admitCheckedClientEffectRunPublication(prepared: unknown, template: unknown,
    preparedEvidence: unknown, authorization: unknown, compiledPlan: PublicationContract): unknown;
};
type EffectAdmissionOptions<Moon extends EffectAdmissionBindings, Control extends EffectAdmissionControl, Compilation> = {
  moon: Moon;
  control: Control;
  prepared: unknown;
  compilation: Compilation;
  allowed: unknown;
  definition: unknown;
  authorityScopeCid: string;
  namespaceId: string;
  storeAuthorityCid: string;
  now(): string;
  resultDataPolicy: unknown;
  queryTimePreparation?: unknown;
  queryTime?: unknown;
  identity: unknown;
};

// These retained contract bodies use canonical key order. Previously only
// opaque profile IDs were emitted; durable dependency recovery needs the
// exact canonical body as well. This is a coordinated 0.1 identity change,
// not a decoder for the former noncanonical profile hash.
export const retentionDependencies = Object.freeze([
  ['retention_contract', 'local-result-retention'],
  ['metadata_retention_policy', 'local-result-metadata'],
  ['clock_contract', 'local-clock'],
].map(([kind, name]) => {
  const body = {name, version: 'actql-installed-local-policy/0.1'};
  return Object.freeze({kind, cid: cid(body), wire: JSON.stringify(body)});
}));

export function localPublicationPlan<Retention>(options: PublicationPlanOptions<Retention>) {
  return buildLocalPublicationPlan(options).plan;
}

// The same installed Host retention clocks feed early input custody and
// final publication. This DATA resolves no permission or additional lifetime.
export function localRetentionTimes(now: () => string, retainUntil?: string): RetentionTimes {
  const at = Date.parse(now());
  const availableAt = retainUntil === undefined ? at + 60 * 60 * 1000
    : Math.max(at + 60 * 60 * 1000, Date.parse(retainUntil));
  return Object.freeze({availableUntil: instant(availableAt),
    deleteBy: instant(availableAt + 60 * 60 * 1000),
    metadataDeleteBy: instant(Math.max(at + 7 * 24 * 60 * 60 * 1000,
      availableAt + 2 * 60 * 60 * 1000))});
}

export function keyedInputRetentionSelection<Selection>(acquired: {selectRetention(): Selection}): Selection {
  return acquired.selectRetention();
}

function issueLocalResultRetention<Retention>(control: RetentionIssuer<Retention>,
  dataPolicyCid: string, selection: RetentionTimes): Retention {
  const {availableUntil, deleteBy, metadataDeleteBy} = selection;
  return control.seal('result_retention_policy', JSON.stringify({
    version: 'actql-result-retention-policy/0.1',
    retention_contract_cid: retentionDependencies[0].cid,
    effective_data_policy_cid: dataPolicyCid,
    available_until: availableUntil, delete_by: deleteBy,
    extension_ceiling_at: metadataDeleteBy,
    metadata_retention_policy_cid: retentionDependencies[1].cid,
    metadata_delete_by: metadataDeleteBy,
    clock_contract_cid: retentionDependencies[2].cid,
  }), limits);
}

// The Host already owns this mutable managed record. Borrow its current
// original fields only at the terminal publication call, so retirement can
// sever heavy aliases in the existing record. This is not another registry,
// Model publication purpose, preparation or retained owner.
export function managedProgramPublicationCurrent(moon: unknown, prepared: unknown,
  admitted: CurrentAdmission, managed: ManagedPublication | null | undefined,
  owner: unknown, request: unknown): asserts managed is ManagedPublication {
  if (managed === null || typeof managed !== 'object') throw new TypeError('OriginalProgramRetentionOwnerRequired');
  if (Object.hasOwn(managed, 'failure')) throw managed.failure;
  if (owner === undefined || request === undefined || managed.value !== owner || managed.request !== request ||
      managed.runtime !== moon || managed.prepared !== prepared || managed.closed ||
      managed.retiringContent || managed.retiringModel ||
      admitted.requestIdentity !== undefined && admitted.requestIdentity !== request) {
    throw new TypeError('OriginalProgramRetentionOwnerRequired');
  }
}

export function managedProgramInitialRetention<Retention>(moon: unknown, control: ProgramRetentionIssuer<Retention>,
  prepared: unknown, admitted: CurrentAdmission, managed: ManagedPublication,
  policy: string, now: () => string, current: (() => undefined) | undefined): Retention {
  const owner = managed?.value, request = managed?.request;
  managedProgramPublicationCurrent(moon, prepared, admitted, managed, owner, request);
  if (typeof current !== 'function') throw new TypeError('OriginalProgramRetentionCurrentRequired');
  current();
  managedProgramPublicationCurrent(moon, prepared, admitted, managed, owner, request);
  const retention = control.issueProgramInitialRetention(owner, prepared, request, policy,
    localRetentionTimes(now), retentionDependencies, limits);
  // Callback-free failure/retirement guards precede any further current hook.
  // A retired record must not touch its old runtime or hide a primary cause.
  managedProgramPublicationCurrent(moon, prepared, admitted, managed, owner, request);
  current();
  managedProgramPublicationCurrent(moon, prepared, admitted, managed, owner, request);
  return retention;
}

// Keep the retained input policy available to Effect evidence issuance
// without extending the closed publication-plan JS bridge used by ordinary Runs.
export function buildLocalPublicationPlan<Retention>({control, admission, runDefinition, invocation,
  observation, compiledPlanCid, programDefinitionCid, inputRelationCids,
  sourceEvidence, authorityScopeCid, namespaceId, storeAuthorityCid,
  dataPolicyCid, createdAt, now, resultCount, retainUntil,
  compiled, preparedProgram, publicationOriginal, authoringContextOriginal, effectCompilation, preparedEffect, moon,
  modelEvidence = [], outputLimits = localOutputLimits, retentionSelection, originalRetention}: PublicationPlanOptions<Retention>) {
  const retention = originalRetention ?? issueLocalResultRetention(control, dataPolicyCid,
    retentionSelection ?? localRetentionTimes(now, retainUntil));
  const normalizationJournal = preparedProgram === undefined
    // Unselected Effect/legacy material retains its existing separate profile.
    ? control.sealRunEvidence('normalization_journal', JSON.stringify({
      version: 'actql-normalization-journal/0.1',
      rule_catalog_cid: policyCid('local-normalization'), entries: [],
    }), limits)
    : control.preparedClientNormalizationEvidence(preparedProgram, limits);
  const authoringContext = preparedProgram === undefined
    ? control.sealRunEvidence('authoring_context',
    JSON.stringify({version: 'actql-authoring-context/0.1',
      program_definition_cid: programDefinitionCid,
      annotations: []}), limits)
    : control.preparedClientAuthoringContextEvidence(preparedProgram,
      publicationOriginal?.authoringContext ?? authoringContextOriginal, limits);
  const plan = Object.freeze({admission, runDefinition, invocation, observation,
    normalizationJournal, authoringContext,
    results: Object.freeze(Array.from({length: resultCount}, (_, index) => {
      const transformation = effectCompilation !== undefined ? checked(
        moon.clientProgramEffectCompilationResultTransformation(
          effectCompilation, preparedEffect, index)) :
        compiled === undefined ? undefined :
          control.compiledRunResultTransformation(compiled, preparedProgram, index);
      return Object.freeze({retention,
        ...(transformation == null ? {} : {transformation}),
        evidenceContext: Object.freeze({
        computationContractCid: compiledPlanCid,
        inputRelationCids, scopeCid: runDefinition.identity,
        effectiveDataPolicyCid: dataPolicyCid, authorityScopeCid,
      })});
    })),
    receiptEvidence: Object.freeze({bindings: [], sourceEvidence,
      modelEvidence: Object.freeze([...modelEvidence]), barrierAttemptReceiptCids: []}),
    captureEvidence: Object.freeze({pendingSourceStateAdvances: [],
      modelEvidence: Object.freeze([...modelEvidence])}),
    request: Object.freeze({namespaceId, authorityScopeCid,
      publicationPolicyCid: policyCid('local-publication'),
      publicationTargetCid: storeAuthorityCid, requestedAt: createdAt}),
    attempt: Object.freeze({attemptId: randomUUID(),
      fenceCid: cid({version: 'actql-local-run-fence/0.1',
        run_definition_cid: runDefinition.identity}),
      externalIdempotencyKey: undefined, startedAt: createdAt}),
    outputLimits, contractLimits: limits, now,
  });
  return {plan, retention, retentionDependencies};
}

// The Effect Run acceptance owner already compiled and admitted this Run.
// Reuse its exact compiler outputs; do not prepare or compile another Program
// to reconstruct publication evidence. Captured inputs must outlive approval
// waiting, so retention covers the admitted Run's validity window.
export function effectPublicationAdmission<Moon extends EffectAdmissionBindings, Control extends EffectAdmissionControl, Compilation>({moon, control, prepared,
  compilation, allowed, definition, authorityScopeCid, namespaceId,
  storeAuthorityCid, now, resultDataPolicy, queryTimePreparation, queryTime, identity}: EffectAdmissionOptions<Moon, Control, Compilation>) {
  const compiledPlan = control.admit('compiled_plan',
    moon.clientProgramEffectCompilationCompiledPlanWire(compilation), limits);
  let admission, runDefinition;
  if (typeof control.originalCheckedClientEffectPublication === 'function') {
    ({admission, runDefinition} = control.originalCheckedClientEffectPublication(allowed, definition, limits));
  } else {
    const template = control.admitRunEvidence('bound_invocation_template',
      moon.clientProgramEffectCompilationTemplateWire(compilation), limits);
    const preparedEvidence = control.admitRunEvidence('prepared_invocation',
      moon.strategyRunEvidenceJson(moon.clientProgramAllowedEffectRunPrepared(allowed)), limits);
    const authorization = control.admitRunEvidence('run_authorization',
      moon.strategyRunEvidenceJson(moon.clientProgramAllowedEffectRunAuthorization(allowed)), limits);
    admission = control.admitCheckedClientEffectRunPublication(prepared,
      template, preparedEvidence, authorization, compiledPlan);
    runDefinition = control.admit('run_definition', moon.strategyPublicationContractJson(definition), limits);
  }
  const dataPolicyCid = policyCid('local-result-data');
  // Retention is immutable Run DATA, selected at its original first-use
  // boundary and reused after Model awaits. Keep the live permission/current
  // clock below unchanged; this selection never grants or extends access.
  let retentionSelection: EffectRetentionTimes | undefined, retentionFailure: unknown,
    retentionFailed = false;
  const selectRetention = () => {
    if (retentionFailed) throw retentionFailure;
    if (retentionSelection !== undefined) return retentionSelection;
    try {
      const run = JSON.parse(runDefinition.wire) as {valid_until?: string};
      retentionSelection = Object.freeze({...localRetentionTimes(now, run.valid_until),
        expiresAt: run.valid_until,
        retentionContractCid: retentionDependencies[0].cid,
        metadataRetentionPolicyCid: retentionDependencies[1].cid,
        clockContractCid: retentionDependencies[2].cid});
      return retentionSelection;
    } catch (cause) {
      retentionFailed = true; retentionFailure = cause; throw cause;
    }
  };
  return Object.freeze({moon, control, prepared, compilation, allowed,
    definition, authorityScopeCid, namespaceId, storeAuthorityCid, now, selectRetention,
    admission, runDefinition, compiledPlan, dataPolicyCid, resultDataPolicy,
    queryTimePreparation, queryTime, requestIdentity: identity,
    resultDataPolicyLimits: limits});
}
