// Shared independent publication fixture for real Host and Store acceptance.
import {createHash} from 'node:crypto';

const hash = value => `sha256:${createHash('sha256').update(JSON.stringify(value)).digest('hex')}`;

export const publicationResultExportLimits = Object.freeze({
  maxResultFields: 10,
  maxResultMappingWork: 1000,
  maxResultOrderWork: 10000,
  maxResultWorkspaceEntries: 100,
  maxRows: 100,
  maxValueNodes: 10000,
  maxValueTextBytes: 100000,
  maxValueDepth: 64,
  maxValueWork: 100000,
  maxWireBytes: 100000,
  maxWireNodes: 10000,
  maxWireDepth: 64,
  maxColumns: 10,
  maxOrderWork: 10000,
  maxLogicalWireBytes: 100000,
  maxLogicalWireNodes: 10003,
  maxLogicalWireDepth: 66,
  maxSchemaFields: 10,
  maxSchemaBytes: 100000,
  maxSchemaNodes: 10000,
  maxSchemaDepth: 64,
  maxBatchBytes: 4096,
});

export function standardPublicationPlan(
  runtime,
  programDefinitionCid,
  resultCount,
  attemptId,
) {
  const control = runtime.publicationControl;
  const contractLimits = Object.freeze({
    maxWireBytes: 100000,
    maxNodes: 10000,
    maxDepth: 64,
  });
  const effectiveDataPolicyCid = hash('effective-policy');
  const template = control.sealRunEvidence(
    'bound_invocation_template',
    JSON.stringify({
      version: 'actql-bound-invocation-template/0.1',
      program_definition_cid: programDefinitionCid,
      parameter_values_cid: hash('parameter-values'),
      invocation_bindings_cid: hash('invocation-bindings'),
      check_environment_cid: hash('check-environment'),
      grammar_manifest_cid: hash('grammar-manifest'),
      required_profile_contracts: [],
      barrier_contract_manifest_cid: hash('barrier-contract-manifest'),
      source_evidence: 'unbound',
    }),
    contractLimits,
  );
  const compiledPlan = control.seal('compiled_plan', JSON.stringify({
    version: 'actql-compiled-plan/0.1',
    compiler_version: 'compiler-test-0.1',
    aoa_ir_version: 'aoa-ir-test-0.1',
    executable_plan_cid: hash('executable-plan'),
    program_definition_cid: programDefinitionCid,
    program_semantics_cid: hash('program-semantics'),
    aoa_contract_cid: hash('aoa-contract'),
    aoa_logical_cid: hash('aoa-logical'),
  }), contractLimits);
  const prepared = control.sealRunEvidence(
    'prepared_invocation',
    JSON.stringify({
      version: 'actql-prepared-invocation/0.1',
      invocation_template_cid: template.identity,
      compiled_plan_cid: compiledPlan.identity,
      execution_context_cid: hash('execution-context'),
      host_policy_cid: hash('host-policy'),
      policy_decision: 'allow',
      expires_at: '2026-09-18T03:00:00.000Z',
    }),
    contractLimits,
  );
  const authorization = control.sealRunEvidence(
    'run_authorization',
    JSON.stringify({
      version: 'actql-run-authorization/0.1',
      prepared_invocation_cid: prepared.identity,
      execution_context_cid: hash('execution-context'),
      host_policy_cid: hash('host-policy'),
      decision: 'allowed',
    }),
    contractLimits,
  );
  const admission = control.admitRunPublication(
    template,
    prepared,
    authorization,
    compiledPlan,
  );
  const runDefinition = control.issueRunDefinition(admission, {
    scopeId: 'standard-publication-scope',
    runId: `standard-publication-${attemptId}`,
    inputArtifactSetCid: hash('input-artifact-set'),
    createdAt: '2026-09-18T00:00:00.000Z',
    validUntil: '2026-09-18T02:30:00.000Z',
  }, contractLimits);
  const observation = control.sealRunEvidence(
    'observation_set',
    JSON.stringify({
      version: 'actql-observation-set/0.1',
      invocation_template_cid: template.identity,
      source_evidence_cids: [],
      captured_input_artifact_cids: [],
      consistency: 'no_external_sources',
      capture_started_at: null,
      capture_completed_at: null,
      replayability: {
        materialized: false,
        availability_evidence_cids: [],
      },
      data_policy_cid: effectiveDataPolicyCid,
    }),
    contractLimits,
  );
  const invocation = control.issueRunInvocation(
    template,
    observation,
    contractLimits,
  );
  const retention = control.seal(
    'result_retention_policy',
    JSON.stringify({
      version: 'actql-result-retention-policy/0.1',
      retention_contract_cid: hash('retention-contract'),
      effective_data_policy_cid: effectiveDataPolicyCid,
      available_until: '2026-09-18T01:00:00.000Z',
      delete_by: '2026-09-18T02:00:00.000Z',
      extension_ceiling_at: '2026-09-18T03:00:00.000Z',
      metadata_retention_policy_cid: hash('metadata-retention'),
      metadata_delete_by: '2026-09-18T04:00:00.000Z',
      clock_contract_cid: hash('clock-contract'),
    }),
    contractLimits,
  );
  const normalizationJournal = control.sealRunEvidence(
    'normalization_journal',
    JSON.stringify({
      version: 'actql-normalization-journal/0.1',
      rule_catalog_cid: hash('rule-catalog'),
      entries: [],
    }),
    contractLimits,
  );
  const authoringContext = control.sealRunEvidence(
    'authoring_context',
    JSON.stringify({
      version: 'actql-authoring-context/0.1',
      program_definition_cid: programDefinitionCid,
      annotations: [],
    }),
    contractLimits,
  );
  return Object.freeze({
    admission,
    runDefinition,
    invocation,
    observation,
    normalizationJournal,
    authoringContext,
    results: Object.freeze(Array.from({length: resultCount}, (_, index) =>
      Object.freeze({
        retention,
        evidenceContext: Object.freeze({
          computationContractCid: hash(`checked-computation-${index}`),
          inputRelationCids: Object.freeze([]),
          scopeCid: hash(`result-scope-${index}`),
          effectiveDataPolicyCid,
          authorityScopeCid: hash('authority-scope'),
        }),
      }))),
    receiptEvidence: Object.freeze({
      bindings: Object.freeze([]),
      sourceEvidence: Object.freeze([]),
      modelEvidence: Object.freeze([]),
      barrierAttemptReceiptCids: Object.freeze([]),
    }),
    captureEvidence: Object.freeze({
      pendingSourceStateAdvances: Object.freeze([]),
      modelEvidence: Object.freeze([]),
    }),
    request: Object.freeze({
      namespaceId: 'namespace-a',
      authorityScopeCid: hash('authority-scope'),
      publicationPolicyCid: hash('publication-policy'),
      publicationTargetCid: hash('publication-target'),
      requestedAt: '2026-09-18T00:00:00.000Z',
    }),
    attempt: Object.freeze({
      attemptId,
      fenceCid: hash('publication-fence'),
      externalIdempotencyKey: undefined,
      startedAt: '2026-09-18T00:00:01.000Z',
    }),
    outputLimits: publicationResultExportLimits,
    contractLimits,
    now: () => '2026-09-18T00:00:02.000Z',
  });
}
