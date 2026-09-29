// Bind the installed source-free compiler to the common Run and publication
// owner. Physical Local policy CIDs are stable identities of this Host profile.
import {createHash, randomUUID} from 'node:crypto';
import {checked} from '../host-common/runtime-result.mjs';

// Contract and evidence issuance bounds. A captured Run's Named Result
// snapshot is admitted under them too, so they hold what one captured Run can
// output: the Local import wire (1 MB, 100k nodes).
const limits = Object.freeze({maxWireBytes: 1000000, maxNodes: 100000,
  maxDepth: 64});
export const localOutputLimits = Object.freeze({
  maxResultFields: 10, maxResultMappingWork: 1000,
  maxResultOrderWork: 10000, maxResultWorkspaceEntries: 100,
  maxRows: 10000, maxValueNodes: 1000000, maxValueTextBytes: 10000000,
  maxValueDepth: 64, maxValueWork: 1000000, maxWireBytes: 10000000,
  maxWireNodes: 1000000, maxWireDepth: 64, maxColumns: 100,
  maxOrderWork: 1000000, maxLogicalWireBytes: 10000000,
  maxLogicalWireNodes: 1000003, maxLogicalWireDepth: 66,
  maxSchemaFields: 100, maxSchemaBytes: 100000,
  maxSchemaNodes: 10000, maxSchemaDepth: 64, maxBatchBytes: 65536,
});
export const localContractLimits = limits;

const cid = value => `sha256:${createHash('sha256')
  .update(JSON.stringify(value)).digest('hex')}`;
const policyCid = name => cid({version: 'actql-installed-local-policy/0.1',
  name});
const instant = value => new Date(value).toISOString();

function localPublicationPlan({control, admission, runDefinition, invocation,
  observation, compiledPlanCid, programDefinitionCid, inputRelationCids,
  sourceEvidence, authorityScopeCid, namespaceId, storeAuthorityCid,
  dataPolicyCid, createdAt, now, resultCount, retainUntil}) {
  const at = Date.parse(now());
  const availableAt = retainUntil === undefined ? at + 60 * 60 * 1000
    : Math.max(at + 60 * 60 * 1000, Date.parse(retainUntil));
  const availableUntil = instant(availableAt);
  const deleteBy = instant(availableAt + 60 * 60 * 1000);
  const metadataDeleteBy = instant(Math.max(at + 7 * 24 * 60 * 60 * 1000,
    availableAt + 2 * 60 * 60 * 1000));
  const retention = control.seal('result_retention_policy', JSON.stringify({
    version: 'actql-result-retention-policy/0.1',
    retention_contract_cid: policyCid('local-result-retention'),
    effective_data_policy_cid: dataPolicyCid,
    available_until: availableUntil, delete_by: deleteBy,
    extension_ceiling_at: metadataDeleteBy,
    metadata_retention_policy_cid: policyCid('local-result-metadata'),
    metadata_delete_by: metadataDeleteBy,
    clock_contract_cid: policyCid('local-clock'),
  }), limits);
  const normalizationJournal = control.sealRunEvidence(
    'normalization_journal', JSON.stringify({
      version: 'actql-normalization-journal/0.1',
      rule_catalog_cid: policyCid('local-normalization'), entries: [],
    }), limits);
  const authoringContext = control.sealRunEvidence('authoring_context',
    JSON.stringify({version: 'actql-authoring-context/0.1',
      program_definition_cid: programDefinitionCid,
      annotations: []}), limits);
  return Object.freeze({admission, runDefinition, invocation, observation,
    normalizationJournal, authoringContext,
    results: Object.freeze(Array.from({length: resultCount}, () =>
      Object.freeze({retention, evidenceContext: Object.freeze({
        computationContractCid: compiledPlanCid,
        inputRelationCids, scopeCid: runDefinition.identity,
        effectiveDataPolicyCid: dataPolicyCid, authorityScopeCid,
      })}))),
    receiptEvidence: Object.freeze({bindings: [], sourceEvidence,
      modelEvidence: [], barrierAttemptReceiptCids: []}),
    captureEvidence: Object.freeze({pendingSourceStateAdvances: [],
      modelEvidence: []}),
    request: Object.freeze({namespaceId, authorityScopeCid,
      publicationPolicyCid: policyCid('local-publication'),
      publicationTargetCid: storeAuthorityCid, requestedAt: createdAt}),
    attempt: Object.freeze({attemptId: randomUUID(),
      fenceCid: cid({version: 'actql-local-run-fence/0.1',
        run_definition_cid: runDefinition.identity}),
      externalIdempotencyKey: undefined, startedAt: createdAt}),
    outputLimits: localOutputLimits, contractLimits: limits, now,
  });
}

// The Effect Run acceptance owner already compiled and admitted this Run.
// Reuse its exact compiler outputs; do not prepare or compile another Program
// to reconstruct publication evidence. Captured inputs must outlive approval
// waiting, so retention covers the admitted Run's validity window.
function effectPublicationAdmission({moon, control, prepared,
  compilation, allowed, definition, authorityScopeCid, namespaceId,
  storeAuthorityCid, now}) {
  const template = control.admitRunEvidence('bound_invocation_template',
    moon.clientProgramEffectCompilationTemplateWire(compilation), limits);
  const preparedEvidence = control.admitRunEvidence('prepared_invocation',
    moon.strategyRunEvidenceJson(
      moon.clientProgramAllowedEffectRunPrepared(allowed)), limits);
  const authorization = control.admitRunEvidence('run_authorization',
    moon.strategyRunEvidenceJson(
      moon.clientProgramAllowedEffectRunAuthorization(allowed)), limits);
  const compiledPlan = control.admit('compiled_plan',
    moon.clientProgramEffectCompilationCompiledPlanWire(compilation), limits);
  const admission = control.admitCheckedClientEffectRunPublication(prepared,
    template, preparedEvidence, authorization, compiledPlan);
  const runDefinition = control.admit('run_definition',
    moon.strategyPublicationContractJson(definition), limits);
  const dataPolicyCid = policyCid('local-result-data');
  return Object.freeze({moon, control, prepared, compilation, allowed,
    definition, authorityScopeCid, namespaceId, storeAuthorityCid, now,
    admission, runDefinition, compiledPlan, dataPolicyCid});
}

export function sourceFreeEffectPublicationPlan(options) {
  const acquired = effectPublicationAdmission(options);
  const {moon, control, prepared, compilation, admission, runDefinition,
    compiledPlan, dataPolicyCid, authorityScopeCid, namespaceId,
    storeAuthorityCid, now} = acquired;
  const sourceFree = checked(moon.clientProgramIssueEffectSourceFreeInvocation(
    compilation, dataPolicyCid, limits.maxWireBytes, limits.maxNodes,
    limits.maxDepth));
  const observation = control.admitRunEvidence('observation_set',
    moon.strategyRunEvidenceJson(sourceFree._0), limits);
  const invocation = control.admit('run_invocation',
    moon.strategyPublicationContractJson(sourceFree._1), limits);
  const run = JSON.parse(runDefinition.wire);
  const resultCount = moon.clientProgramEffectCompilationResultNames(
    compilation).length;
  const plan = localPublicationPlan({control, admission, runDefinition,
    invocation, observation, compiledPlanCid: compiledPlan.identity,
    programDefinitionCid: moon.clientProgramEffectDefinitionCid(prepared),
    inputRelationCids: [], sourceEvidence: [], authorityScopeCid, namespaceId,
    storeAuthorityCid, dataPolicyCid, createdAt: run.created_at, now,
    resultCount, retainUntil: run.valid_until});
  return Object.freeze({...plan, invocationOwner: sourceFree._1,
    localEvidenceContext: Object.freeze({admission, runDefinition,
      runInvocation: invocation, observation})});
}

// The accepted Effect Run can be admitted before provider I/O, but its
// Observation Set cannot be issued until the exact acquired source exists.
export function acquiredEffectPublicationAdmission(options) {
  return effectPublicationAdmission(options);
}

export function acquiredEffectPublicationPlan({acquired, captured,
  sourceEvidenceWire, captureStartedAt, captureCompletedAt}) {
  const {moon, control, prepared, compilation, definition, admission,
    runDefinition, compiledPlan, authorityScopeCid,
    namespaceId, storeAuthorityCid, now} = acquired;
  if (typeof sourceEvidenceWire !== 'string' ||
      typeof captureStartedAt !== 'string' ||
      typeof captureCompletedAt !== 'string' ||
      captured?.logicalInput === undefined ||
      captured?.checkedSource === undefined ||
      captured?.identity === undefined ||
      captured?.capture === undefined ||
      moon.clientProgramEffectCapturedSourceMatches(prepared,
        captured.capture.source()) !== true) {
    throw new TypeError('InvalidAcquiredEffectPublication');
  }
  const source = captured.checkedSource;
  const {observation, invocation, owner: invocationOwner} =
    control.issueCheckedClientEffectCapturedInvocation(
      prepared, compilation, admission, definition,
      captured.capture.source(), {sourceEvidenceWire,
        inputLogicalWire: moon.strategyRunEvidenceJson(captured.logicalInput),
        sourceRef: source.sourceRef,
        sourceContractCid: source.sourceContractCid,
        authorityScopeCid, dataPolicyCid: source.sourceDataPolicyCid,
        captureStartedAt, captureCompletedAt}, limits);
  const sourceEvidence = control.admitRunEvidence('source_evidence',
    sourceEvidenceWire, limits);
  const run = JSON.parse(runDefinition.wire);
  const resultCount = moon.clientProgramEffectCompilationResultNames(
    compilation).length;
  const plan = localPublicationPlan({control, admission, runDefinition,
    invocation, observation, compiledPlanCid: compiledPlan.identity,
    programDefinitionCid: moon.clientProgramEffectDefinitionCid(prepared),
    inputRelationCids: [moon.clientProgramCapturedSourceLogicalCid(
      captured.identity)], sourceEvidence: [sourceEvidence],
    authorityScopeCid, namespaceId, storeAuthorityCid,
    dataPolicyCid: source.sourceDataPolicyCid, createdAt: run.created_at,
    now, resultCount, retainUntil: run.valid_until});
  return Object.freeze({...plan, invocationOwner,
    localEvidenceContext: Object.freeze({admission, runDefinition,
      runInvocation: invocation, observation})});
}

export function sourceFreeValuesPlan({moon, control, preparedProgram,
  authorityScopeCid, namespaceId, storeAuthorityCid, now,
  retainedDefinitionWire}) {
  const at = Date.parse(now());
  if (!Number.isFinite(at)) throw new TypeError('InvalidLocalClock');
  const retained = retainedDefinitionWire === undefined ? undefined :
    JSON.parse(retainedDefinitionWire);
  const createdAt = retained?.created_at ?? instant(at);
  const validUntil = retained?.valid_until ??
    instant(at + 24 * 60 * 60 * 1000);
  const contextCid = cid({version: 'actql-installed-local-context/0.1',
    authority_scope_cid: authorityScopeCid});
  const compiled = control.prepareCheckedClientCompiledRun(preparedProgram,
    'values', {executionContextCid: contextCid,
      hostPolicyCid: policyCid('source-free-values'), expiresAt: validUntil});
  const {admission, compiledPlan} = compiled;
  const runDefinition = control.defineCheckedClientCompiledRun(compiled, {
    namespaceId, runId: randomUUID(), createdAt, validUntil,
    retainedDefinitionWire,
  });
  const dataPolicyCid = policyCid('local-result-data');
  const {observation, invocation} = control.issueCheckedClientCompiledInvocation(
    compiled, runDefinition, {dataPolicyCid}, limits);
  return localPublicationPlan({control, admission, runDefinition, invocation,
    observation, compiledPlanCid: compiledPlan.identity,
    programDefinitionCid: moon.clientProgramDefinitionCid(preparedProgram),
    inputRelationCids: [], sourceEvidence: [], authorityScopeCid,
    namespaceId, storeAuthorityCid, dataPolicyCid, createdAt,
    now, resultCount: 1});
}

// Admit the complete checked task graph, including acquired sources, to the
// same portable Run owner used by the installed source-free profile. Physical
// acquisition and Source Evidence must still be established before this Run
// can be published; this admission alone never authorizes provider I/O.
export function acquiredTaskRunAdmission({moon, control, preparedProgram,
  authorityScopeCid, namespaceId, now, retainedDefinitionWire}) {
  const at = Date.parse(now());
  if (!Number.isFinite(at)) throw new TypeError('InvalidLocalClock');
  const retained = retainedDefinitionWire === undefined ? undefined :
    JSON.parse(retainedDefinitionWire);
  const createdAt = retained?.created_at ?? instant(at);
  const validUntil = retained?.valid_until ??
    instant(at + 24 * 60 * 60 * 1000);
  const contextCid = cid({version: 'actql-installed-local-context/0.1',
    authority_scope_cid: authorityScopeCid});
  const compiled = control.prepareCheckedClientCompiledRun(preparedProgram,
    'tasks', {executionContextCid: contextCid,
      hostPolicyCid: policyCid('checked-tasks'), expiresAt: validUntil});
  const {admission, compiledPlan} = compiled;
  const runDefinition = control.defineCheckedClientCompiledRun(compiled, {
    namespaceId, runId: randomUUID(), createdAt, validUntil,
    retainedDefinitionWire,
  });
  return Object.freeze({...compiled, compiled, runDefinition, createdAt});
}

// Multi-task source-free Programs use the common task compiler and the same
// empty initial input set. No source observation is invented for Values roots.
export function sourceFreeTaskPlan(options) {
  const acquired = acquiredTaskRunAdmission(options);
  const {moon, control, preparedProgram, authorityScopeCid, namespaceId,
    storeAuthorityCid, now} = options;
  const dataPolicyCid = policyCid('local-result-data');
  const {observation, invocation} = control.issueCheckedClientCompiledInvocation(
    acquired.compiled, acquired.runDefinition, {dataPolicyCid}, limits);
  return localPublicationPlan({control, admission: acquired.admission,
    runDefinition: acquired.runDefinition, invocation, observation,
    compiledPlanCid: acquired.compiledPlan.identity,
    programDefinitionCid: moon.clientProgramDefinitionCid(preparedProgram),
    inputRelationCids: [], sourceEvidence: [], authorityScopeCid, namespaceId,
    storeAuthorityCid, dataPolicyCid, createdAt: acquired.createdAt, now,
    resultCount: moon.clientProgramResultCount(preparedProgram)});
}

// The connector/Acquisition owner supplies Source Evidence after completing
// physical capture and current authorization. This Host binds that evidence to
// the checked task Run and the captured relation before publication.
export function acquiredTaskPublicationPlan({moon, control, acquired,
  preparedProgram, captured, sourceEvidenceWire, authorityScopeCid,
  effectiveDataPolicyCid, captureStartedAt, captureCompletedAt, namespaceId,
  storeAuthorityCid, now}) {
  control.checkClientCompiledRunOwner(acquired.compiled, preparedProgram);
  if (typeof sourceEvidenceWire !== 'string' ||
      typeof effectiveDataPolicyCid !== 'string' ||
      captured?.logicalInput === undefined ||
      captured?.checkedSource === undefined ||
      captured?.identity === undefined ||
      captured?.capture === undefined ||
      moon.clientProgramCapturedSourceMatches(preparedProgram,
        captured.capture.source()) !== true) {
    throw new TypeError('InvalidAcquiredTaskPublication');
  }
  const inputLogicalWire = moon.strategyRunEvidenceJson(
    captured.logicalInput);
  const source = captured.checkedSource;
  const {observation, invocation} = control.issueCheckedClientCompiledInvocation(
    acquired.compiled, acquired.runDefinition,
    {dataPolicyCid: effectiveDataPolicyCid, source: {
      sourceEvidenceWire, inputLogicalWire,
      sourceRef: source.sourceRef,
      sourceContractCid: source.sourceContractCid,
      authorityScopeCid, captureStartedAt, captureCompletedAt,
    }}, limits);
  const sourceEvidence = control.admitRunEvidence('source_evidence',
    sourceEvidenceWire, limits);
  return localPublicationPlan({control, admission: acquired.admission,
    runDefinition: acquired.runDefinition, invocation, observation,
    compiledPlanCid: acquired.compiledPlan.identity,
    programDefinitionCid: moon.clientProgramDefinitionCid(preparedProgram),
    inputRelationCids: [moon.clientProgramCapturedSourceLogicalCid(
      captured.identity)], sourceEvidence: [sourceEvidence],
    authorityScopeCid, namespaceId, storeAuthorityCid,
    dataPolicyCid: effectiveDataPolicyCid, createdAt: acquired.createdAt,
    now, resultCount: moon.clientProgramResultCount(preparedProgram)});
}
