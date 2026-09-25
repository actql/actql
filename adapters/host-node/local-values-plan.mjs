// Bind the installed source-free compiler to the common Run and publication
// owner. Physical Local policy CIDs are stable identities of this Host profile.
import {createHash, randomUUID} from 'node:crypto';
import * as run from '../../packages/run-host-core/index.mjs';
import {checked} from '../host-common/runtime-result.mjs';

const limits = Object.freeze({maxWireBytes: 100000, maxNodes: 10000,
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

export function sourceFreeValuesPlan({moon, control, preparedProgram,
  document, format, parameters, environmentWire, environmentCid,
  authorityScopeCid, tenantId, requestId, storeAuthorityCid, now,
  retainedDefinitionWire}) {
  const at = Date.parse(now());
  if (!Number.isFinite(at)) throw new TypeError('InvalidLocalClock');
  const retained = retainedDefinitionWire === undefined ? undefined :
    JSON.parse(retainedDefinitionWire);
  const createdAt = retained?.created_at ?? instant(at);
  const validUntil = retained?.valid_until ??
    instant(at + 24 * 60 * 60 * 1000);
  const availableUntil = instant(at + 60 * 60 * 1000);
  const deleteBy = instant(at + 2 * 60 * 60 * 1000);
  const metadataDeleteBy = instant(at + 7 * 24 * 60 * 60 * 1000);
  const coreEnvironment = run.admitEnvironment(environmentWire,
    environmentCid, {rela: true});
  const prepared = run.prepare(document, format, coreEnvironment,
    parameters === null ? undefined : JSON.stringify(parameters));
  const compilation = run.compileValues(prepared);
  const siteCompilation = checked(moon.clientProgramCompileLocalValues(
    preparedProgram));
  const coreWires = run.privateCompilationWires(compilation);
  const siteWires = {
    boundTemplate: moon.clientProgramCompilationTemplateWire(siteCompilation),
    compiledPlan: moon.clientProgramCompilationCompiledPlanWire(
      siteCompilation),
  };
  if (JSON.parse(coreWires.boundTemplate).bound_invocation_template_cid !==
      JSON.parse(siteWires.boundTemplate).bound_invocation_template_cid ||
      JSON.parse(coreWires.compiledPlan).compiled_plan_cid !==
      JSON.parse(siteWires.compiledPlan).compiled_plan_cid) {
    throw new Error('LocalCompilerOwnerMismatch');
  }
  const contextCid = cid({version: 'actql-installed-local-context/0.1',
    authority_scope_cid: authorityScopeCid});
  const hostPolicyCid = policyCid('source-free-values');
  const issued = run.issueAllowedRun(prepared, compilation, {
    executionContextCid: contextCid, hostPolicyCid,
    expiresAt: validUntil,
  });
  const template = control.admitRunEvidence('bound_invocation_template',
    siteWires.boundTemplate, limits);
  const compiledPlan = control.admit('compiled_plan',
    siteWires.compiledPlan, limits);
  const preparedEvidence = control.admitRunEvidence('prepared_invocation',
    issued.preparedInvocationWire, limits);
  const authorization = control.admitRunEvidence('run_authorization',
    issued.authorizationWire, limits);
  const admission = control.admitCheckedClientRunPublication(preparedProgram,
    template, preparedEvidence, authorization, compiledPlan);
  const sourceDefinition = retainedDefinitionWire === undefined
    ? run.issueSourceFreeRunDefinition(prepared, compilation,
      issued.admission, tenantId, randomUUID(), createdAt, validUntil)
    : run.admitSourceFreeRunDefinition(prepared, compilation,
      issued.admission, retainedDefinitionWire);
  const definitionWire = run.privateRunDefinition(sourceDefinition);
  const runDefinition = control.admit('run_definition',
    definitionWire.wire, limits);
  if (runDefinition.identity !== definitionWire.cid) {
    throw new Error('LocalRunOwnerMismatch');
  }
  control.checkClientRunDefinitionBinding(preparedProgram, admission,
    runDefinition);
  const dataPolicyCid = policyCid('local-result-data');
  const issuedInvocation = run.issueSourceFreeInvocation(prepared,
    compilation, issued.admission, sourceDefinition, dataPolicyCid, limits);
  const observation = control.admitRunEvidence('observation_set',
    issuedInvocation.observation.wire, limits);
  const invocation = control.admit('run_invocation',
    issuedInvocation.invocation.wire, limits);
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
      program_definition_cid: run.requestFields(
        run.prepareSourceFreeRequest(prepared, compilation,
          authorityScopeCid, requestId)).programDefinitionCid,
      annotations: []}), limits);
  return Object.freeze({admission, runDefinition, invocation, observation,
    normalizationJournal, authoringContext,
    results: Object.freeze([Object.freeze({retention,
      evidenceContext: Object.freeze({
        computationContractCid: compiledPlan.identity,
        inputRelationCids: [], scopeCid: runDefinition.identity,
        effectiveDataPolicyCid: dataPolicyCid,
        authorityScopeCid,
      })})]),
    receiptEvidence: Object.freeze({bindings: [], sourceEvidence: [],
      modelEvidence: [], barrierAttemptReceiptCids: []}),
    captureEvidence: Object.freeze({pendingSourceStateAdvances: [],
      modelEvidence: []}),
    request: Object.freeze({tenantId, authorityScopeCid,
      publicationPolicyCid: policyCid('local-publication'),
      publicationTargetCid: storeAuthorityCid, requestedAt: createdAt}),
    attempt: Object.freeze({attemptId: randomUUID(),
      fenceCid: cid({version: 'actql-local-run-fence/0.1',
        run_definition_cid: runDefinition.identity}),
      externalIdempotencyKey: undefined, startedAt: createdAt}),
    outputLimits: localOutputLimits, contractLimits: limits, now,
  });
}
