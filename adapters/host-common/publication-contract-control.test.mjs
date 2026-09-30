import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {createServer} from 'node:http';
import test from 'node:test';
import {mkdtemp, open, readdir, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from './runtime-core.mjs';
import {checked} from './runtime-result.mjs';
import {publishEffectFreeRun, publishEffectfulRun} from
  './run-publication.mjs';
import {retainIssuedEffectSetReceipt} from
  './effect-receipt-custody.mjs';
import {publishCompletedEffectFreeRun} from
  './completed-run-publication.mjs';
import {prepareCompletedEffectFreeRunPublication} from
  './run-publication-preflight.mjs';
import {deliverPublishedResult} from './result-delivery.mjs';
import {
  deliverAuthorizedResult,
  installResultAccessAuthority,
  installNodeResultAccessService,
} from '../host-node/result-access.mjs';
import {
  inspectAuthorizedRunState,
  installRunStateAuthority,
  installRunStateService,
} from './run-state-access.mjs';
import {
  installManifestAccessAuthority,
  installManifestAccessService,
  readAuthorizedManifest,
} from './manifest-access.mjs';
import {
  extendResultRetention,
  installMetadataRetentionAuthority,
  installMetadataRetentionService,
  installResultRetentionAuthority,
  installResultRetentionExtensionAuthority,
  installResultRetentionExtensionService,
  installResultRetentionService,
  retireExpiredResult,
  retireExpiredPublicationMetadata,
} from './result-retention.mjs';
import {openLocalPublicationStore} from
  '../store-local/publication-store.mjs';
import {createClientHttpHandler} from '../host-node/client-http.mjs';
import {connect as connectClient} from '../../packages/sdk/index.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const limits = Object.freeze({
  maxWireBytes: 64 * 1024,
  maxNodes: 4096,
  maxDepth: 64,
});

test('generated publication owner crosses the JS bridge as named actions', () => {
  const core = runtimeCore(moon);
  const control = core.publicationControl;
  assert.equal(control.publicationSetupAction(false, false, false, false,
    false, false, false), 'check_existing_commit');
  assert.equal(control.publicationAttemptAction(undefined, false, false),
    'append_preparing');
  assert.equal(control.publicationCancellationAction(undefined), 'rethrow');
  assert.equal(control.committedPublicationFinalizationAction(undefined),
    'invalid');
  assert.equal(control.publicationCommitFailureAction(false, false, false,
    false), 'reconcile_commit');
  assert.equal(control.publicationUnknownRetryAction(false, false, false,
    false), 'reconcile');
  assert.equal(control.publicationPreparedReleaseAction(-1, 0, false, false,
    false), 'finished');
  assert.equal(control.publicationCleanupOwnerAction(0, 0, false, false,
    false, false), 'finished');
  assert.equal(core.outputExportControl.payloadFailureAction(false, false,
    false, false, false, false, false, false), 'finished');
});

const publicationOutputLimits = Object.freeze({
  maxResultFields: 10,
  maxResultMappingWork: 100,
  maxResultOrderWork: 100,
  maxResultWorkspaceEntries: 10,
  maxRows: 100,
  maxValueNodes: 1000,
  maxValueTextBytes: 4096,
  maxValueDepth: 10,
  maxValueWork: 8192,
  maxWireBytes: 4096,
  maxWireNodes: 1000,
  maxWireDepth: 10,
  maxColumns: 10,
  maxOrderWork: 1000,
  maxLogicalWireBytes: 8192,
  maxLogicalWireNodes: 1003,
  maxLogicalWireDepth: 12,
  maxSchemaFields: 10,
  maxSchemaBytes: 4096,
  maxSchemaNodes: 100,
  maxSchemaDepth: 10,
  maxBatchBytes: 1024,
});
const canonical = value => Array.isArray(value)
  ? value.map(canonical)
  : value !== null && typeof value === 'object'
    ? Object.fromEntries(Object.keys(value).sort()
      .map(key => [key, canonical(value[key])]))
    : value;
const canonicalCid = value => `sha256:${createHash('sha256')
  .update(JSON.stringify(canonical(value))).digest('hex')}`;

function invocation(control) {
  return control.seal('run_invocation', JSON.stringify({
    version: 'actql-run-invocation/0.1',
    invocation_template_cid: cid('1'),
    observation_set_cid: cid('2'),
  }), limits);
}

function admittedRun(control, programDefinitionCid) {
  const template = control.sealRunEvidence(
    'bound_invocation_template',
    JSON.stringify({
      version: 'actql-bound-invocation-template/0.1',
      program_definition_cid: programDefinitionCid,
      parameter_values_cid: cid('2'),
      invocation_bindings_cid: cid('3'),
      check_environment_cid: cid('4'),
      grammar_manifest_cid: cid('5'),
      required_profile_contracts: [],
      barrier_contract_manifest_cid: cid('6'),
      source_evidence: 'unbound',
    }),
    limits,
  );
  const compiledPlan = control.seal('compiled_plan', JSON.stringify({
    version: 'actql-compiled-plan/0.1',
    compiler_version: 'compiler-0.1',
    aoa_ir_version: 'aoa-ir-0.1',
    executable_plan_cid: cid('0'),
    program_definition_cid: programDefinitionCid,
    program_semantics_cid: cid('a'),
    aoa_contract_cid: cid('b'),
    aoa_logical_cid: cid('c'),
  }), limits);
  const prepared = control.sealRunEvidence(
    'prepared_invocation',
    JSON.stringify({
      version: 'actql-prepared-invocation/0.1',
      invocation_template_cid: template.identity,
      compiled_plan_cid: compiledPlan.identity,
      execution_context_cid: cid('8'),
      host_policy_cid: cid('9'),
      policy_decision: 'allow',
      expires_at: '2026-09-18T03:00:00.000Z',
    }),
    limits,
  );
  const authorization = control.sealRunEvidence(
    'run_authorization',
    JSON.stringify({
      version: 'actql-run-authorization/0.1',
      prepared_invocation_cid: prepared.identity,
      execution_context_cid: cid('8'),
      host_policy_cid: cid('9'),
      decision: 'allowed',
    }),
    limits,
  );
  const admission = control.admitRunPublication(
    template,
    prepared,
    authorization,
    compiledPlan,
  );
  const run = control.issueRunDefinition(admission, {
    scopeId: 'scope',
    runId: 'run',
    inputArtifactSetCid: cid('a'),
    createdAt: '2026-09-18T00:00:00.000Z',
    validUntil: '2026-09-18T02:00:00.000Z',
  }, limits);
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
      data_policy_cid: cid('a'),
    }),
    limits,
  );
  return Object.freeze({
    admission,
    run,
    invoked: control.issueRunInvocation(template, observation, limits),
  });
}

function deliveryRoot(control) {
  const artifact = control.seal('result_artifact', JSON.stringify({
    version: 'actql-result-artifact/0.1',
    result_definition_cid: cid('1'),
    invocation_cid: cid('2'),
    logical_result_cid: cid('3'),
    result_schema_cid: cid('4'),
    ordering_evidence_cid: cid('5'),
    actual_row_count: 1,
    actual_completeness: 'complete',
    effective_data_policy_cid: cid('6'),
    effective_retention_policy_cid: cid('7'),
    provenance_evidence_cids: [cid('8')],
  }), limits);
  const manifest = control.seal('result_manifest', JSON.stringify({
    version: 'actql-result-manifest/0.1',
    run_definition_cid: cid('9'),
    invocation_cid: cid('2'),
    results: {answer: JSON.parse(artifact.wire)},
  }), limits);
  const index = control.seal('public_index_entry', JSON.stringify({
    version: 'actql-public-index-entry/0.1',
    namespace_id: 'namespace',
    authority_scope_cid: cid('a'),
    run_definition_cid: cid('9'),
    invocation_cid: cid('2'),
    result_manifest_cid: manifest.identity,
    run_receipt_cid: cid('b'),
    captured_run_cid: cid('c'),
    durable_result_binding_cids: [cid('d')],
    publication_request_cid: cid('e'),
    publication_attempt_cid: cid('f'),
    committed_at: '2026-09-18T00:00:00.000Z',
  }), limits);
  return {artifact, manifest, index};
}

test('installed publication control uses the portable contract owner', () => {
  const control = runtimeCore(moon).publicationControl;
  const sealed = invocation(control);
  assert.deepEqual(sealed, {
    name: 'run_invocation',
    identityField: 'invocation_cid',
    identity:
      'sha256:49e5afcdeaf57b77db072d5db04ce83fcaf25b6eee8f5d33ae9606fb504ded18',
    wire: '{"invocation_cid":"sha256:' +
      '49e5afcdeaf57b77db072d5db04ce83fcaf25b6eee8f5d33ae9606fb504ded18' +
      '","invocation_template_cid":"' + cid('1') +
      '","observation_set_cid":"' + cid('2') +
      '","version":"actql-run-invocation/0.1"}',
  });
  assert.deepEqual(
    control.admit('run_invocation', sealed.wire, limits),
    sealed,
  );
  assert.throws(
    () => control.recordAllowsCommit(Object.freeze({...sealed})),
    /Foreign publication contract/u,
  );
});

test('portable delivery owner binds grants attempts and receipts', () => {
  const control = runtimeCore(moon).publicationControl;
  const {artifact, manifest, index} = deliveryRoot(control);
  assert.equal(
    control.resultSerializationContractCid('json', limits),
    'sha256:f8a9922a194323d7b0f33733eb29753a6b68b48becee913cedb30a23a97cedf8',
  );
  const grant = control.issueResultReadGrant(index, manifest, {
    resultNames: ['answer'],
    formats: ['json', 'jsonl', 'csv'],
    principalId: 'principal',
    purpose: 'download',
    dataCeilingCid: cid('1'),
    maxBytes: 4096,
    maxUses: 2,
    expiresAt: '2026-09-19T00:00:00.000Z',
    authorizationContextCid: cid('2'),
    egressAdmissionCid: cid('3'),
  }, limits);
  assert.deepEqual(JSON.parse(grant.wire).results, [{
    result_artifact_cid: artifact.identity,
    result_name: 'answer',
  }]);
  const attempt = control.issueDeliveryAttempt(
    index,
    manifest,
    grant,
    {
      resultName: 'answer',
      format: 'json',
      attemptId: 'attempt-1',
      requestedAt: '2026-09-18T01:00:00.000Z',
    },
    limits,
  );
  const streaming = control.issueDeliveryRecord(attempt, undefined, {
    state: 'streaming',
    confirmedByteCount: 0,
    exposure: 'exact',
    possibleUnconfirmedMaxBytes: undefined,
    deliveredSha256: undefined,
    receipt: undefined,
    failureCid: undefined,
    observedAt: '2026-09-18T01:00:00.000Z',
    cleanupOwnerCids: [],
  }, limits);
  const receipt = control.issueResultDeliveryReceipt(
    index,
    manifest,
    grant,
    attempt,
    {byteCount: 2, sha256: '0'.repeat(64)},
    limits,
  );
  const succeeded = control.issueDeliveryRecord(attempt, streaming, {
    state: 'succeeded',
    confirmedByteCount: 2,
    exposure: 'exact',
    possibleUnconfirmedMaxBytes: undefined,
    deliveredSha256: '0'.repeat(64),
    receipt,
    failureCid: undefined,
    observedAt: '2026-09-18T01:00:01.000Z',
    cleanupOwnerCids: [],
  }, limits);
  assert.equal(
    JSON.parse(succeeded.wire).result_delivery_receipt_cid,
    receipt.identity,
  );
});

test('portable delivery serializer owns the three canonical formats', () => {
  const control = runtimeCore(moon).publicationControl;
  const schema = JSON.stringify({
    amount: {nullable: false, precision: 4, scale: 2, type: 'decimal'},
    enabled: {nullable: false, type: 'boolean'},
    meta: {
      additional_properties: false,
      fields: {k: {nullable: false, type: 'string'}},
      nullable: false,
      type: 'object',
    },
    missing: {nullable: true, type: 'number'},
    name: {nullable: false, type: 'string'},
    score: {nullable: false, type: 'number'},
  });
  const fields = ['name', 'score', 'amount', 'enabled', 'missing', 'meta'];
  const row = JSON.stringify({
    amount: '2.30',
    enabled: false,
    meta: {k: 'é'},
    missing: null,
    name: 'x,"y',
    score: 1.5,
  });
  const expected =
    '{"name":"x,\\"y","score":1.5,"amount":"2.30",' +
    '"enabled":false,"missing":null,"meta":{"k":"é"}}';

  const serialize = format => {
    const serializer = control.prepareResultDeliverySerializer(
      format,
      schema,
      fields,
      limits,
    );
    return control.beginResultDelivery(serializer) +
      control.nextResultDeliveryRow(serializer, row) +
      control.finishResultDelivery(serializer);
  };

  assert.equal(serialize('json'), `[${expected}]`);
  assert.equal(serialize('jsonl'), `${expected}\n`);
  assert.equal(
    serialize('csv'),
    '"name","score","amount","enabled","missing","meta"\n' +
      '"x,""y",1.5,2.30,false,\\N,"{""k"":""é""}"\n',
  );
});

test('portable evidence owner issues Invocation after exact capture', () => {
  const control = runtimeCore(moon).publicationControl;
  const template = control.sealRunEvidence(
    'bound_invocation_template',
    JSON.stringify({
      version: 'actql-bound-invocation-template/0.1',
      program_definition_cid: cid('1'),
      parameter_values_cid: cid('2'),
      invocation_bindings_cid: cid('3'),
      check_environment_cid: cid('4'),
      grammar_manifest_cid: cid('5'),
      required_profile_contracts: [],
      barrier_contract_manifest_cid: cid('6'),
      source_evidence: 'unbound',
    }),
    limits,
  );
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
      data_policy_cid: cid('7'),
    }),
    limits,
  );
  assert.deepEqual(
    control.admitRunEvidence(template.name, template.wire, limits),
    template,
  );
  const issued = control.issueRunInvocation(template, observation, limits);
  assert.deepEqual(JSON.parse(issued.wire), {
    invocation_cid: issued.identity,
    invocation_template_cid: template.identity,
    observation_set_cid: observation.identity,
    version: 'actql-run-invocation/0.1',
  });
  const foreign = control.sealRunEvidence(
    'bound_invocation_template',
    JSON.stringify({
      ...JSON.parse(template.wire),
      bound_invocation_template_cid: undefined,
      program_definition_cid: cid('8'),
    }),
    limits,
  );
  assert.throws(
    () => control.issueRunInvocation(foreign, observation, limits),
    {code: 'MoonBitHostFailure'},
  );
});

test('portable admission issues Run Definition from exact authority', () => {
  const control = runtimeCore(moon).publicationControl;
  const template = control.sealRunEvidence(
    'bound_invocation_template',
    JSON.stringify({
      version: 'actql-bound-invocation-template/0.1',
      program_definition_cid: cid('1'),
      parameter_values_cid: cid('2'),
      invocation_bindings_cid: cid('3'),
      check_environment_cid: cid('4'),
      grammar_manifest_cid: cid('5'),
      required_profile_contracts: [],
      barrier_contract_manifest_cid: cid('6'),
      source_evidence: 'unbound',
    }),
    limits,
  );
  const compiledPlan = control.seal('compiled_plan', JSON.stringify({
    version: 'actql-compiled-plan/0.1',
    compiler_version: 'compiler-0.1',
    aoa_ir_version: 'aoa-ir-0.1',
    executable_plan_cid: cid('0'),
    program_definition_cid: cid('1'),
    program_semantics_cid: cid('a'),
    aoa_contract_cid: cid('b'),
    aoa_logical_cid: cid('c'),
  }), limits);
  const prepared = control.sealRunEvidence(
    'prepared_invocation',
    JSON.stringify({
      version: 'actql-prepared-invocation/0.1',
      invocation_template_cid: template.identity,
      compiled_plan_cid: compiledPlan.identity,
      execution_context_cid: cid('8'),
      host_policy_cid: cid('9'),
      policy_decision: 'allow',
      expires_at: '2026-09-18T03:00:00.000Z',
    }),
    limits,
  );
  const authorization = control.sealRunEvidence(
    'run_authorization',
    JSON.stringify({
      version: 'actql-run-authorization/0.1',
      prepared_invocation_cid: prepared.identity,
      execution_context_cid: cid('8'),
      host_policy_cid: cid('9'),
      decision: 'allowed',
    }),
    limits,
  );
  const admission = control.admitRunPublication(
    template,
    prepared,
    authorization,
    compiledPlan,
  );
  const definition = control.issueRunDefinition(admission, {
    scopeId: 'scope',
    runId: 'run',
    inputArtifactSetCid: cid('a'),
    createdAt: '2026-09-18T00:00:00.000Z',
    validUntil: '2026-09-18T02:00:00.000Z',
  }, limits);
  assert.deepEqual(JSON.parse(definition.wire), {
    authorization_context_cid: cid('8'),
    compiled_plan_cid: compiledPlan.identity,
    created_at: '2026-09-18T00:00:00.000Z',
    input_artifact_set_cid: cid('a'),
    invocation_template_cid: template.identity,
    run_definition_cid: definition.identity,
    run_id: 'run',
    scope_id: 'scope',
    valid_until: '2026-09-18T02:00:00.000Z',
    version: 'actql-run-definition/0.1',
  });
  assert.throws(
    () => control.issueRunDefinition(
      Object.freeze({kind: 'run-publication-admission'}),
      {
        scopeId: 'scope',
        runId: 'run',
        inputArtifactSetCid: cid('a'),
        createdAt: '2026-09-18T00:00:00.000Z',
        validUntil: '2026-09-18T02:00:00.000Z',
      },
      limits,
    ),
    /Foreign Run publication admission/u,
  );
});

test('publication preflight rejects immutable or physical incompatibility',
  () => {
    const control = runtimeCore(moon).publicationControl;
    const {admission, run, invoked} = admittedRun(control, cid('6'));
    const definition = control.seal('result_definition', JSON.stringify({
      version: 'actql-result-definition/0.1',
      program_definition_cid: cid('6'),
      result_name: 'answer',
    }), limits);
    const retention = control.seal(
      'result_retention_policy',
      JSON.stringify({
        version: 'actql-result-retention-policy/0.1',
        retention_contract_cid: cid('b'),
        effective_data_policy_cid: cid('a'),
        available_until: '2026-09-18T01:00:00.000Z',
        delete_by: '2026-09-18T02:00:00.000Z',
        extension_ceiling_at: '2026-09-18T03:00:00.000Z',
        metadata_retention_policy_cid: cid('c'),
        metadata_delete_by: '2026-09-18T04:00:00.000Z',
        clock_contract_cid: cid('d'),
      }),
      limits,
    );
    const plan = Object.freeze({
      admission,
      runDefinition: run,
      invocation: invoked,
      observation: Object.freeze({}),
      normalizationJournal: Object.freeze({}),
      authoringContext: Object.freeze({}),
      results: Object.freeze([
        Object.freeze({
          retention,
          evidenceContext: Object.freeze({
            computationContractCid: cid('1'),
            inputRelationCids: Object.freeze([]),
            scopeCid: cid('2'),
            effectiveDataPolicyCid: cid('a'),
            authorityScopeCid: cid('7'),
          }),
        }),
      ]),
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
        authorityScopeCid: cid('7'),
        publicationPolicyCid: cid('8'),
        publicationTargetCid: cid('9'),
        requestedAt: '2026-09-18T00:00:00.000Z',
      }),
      attempt: Object.freeze({
        attemptId: 'attempt-a',
        fenceCid: cid('0'),
        externalIdempotencyKey: undefined,
        startedAt: '2026-09-18T00:00:01.000Z',
      }),
      outputLimits: publicationOutputLimits,
      contractLimits: limits,
      now: () => '2026-09-18T00:00:02.000Z',
    });
    const publicationInventory = Object.freeze({
      programDefinitionCid: cid('6'),
      occurrences: Object.freeze([
        Object.freeze({definitionContract: definition}),
      ]),
    });
    let requirement;
    const admitted = prepareCompletedEffectFreeRunPublication({
      store: {
        publicationCapacitySupports(value) {
          requirement = value;
          return true;
        },
      },
      control,
      publicationInventory,
      plan,
    });
    assert.equal(admitted.request.name, 'publication_request');
    assert.equal(admitted.attempt.name, 'publication_attempt');
    assert.deepEqual(requirement, {
      requiredBytes: 19 * limits.maxWireBytes,
      objectCount: 19,
      maxObjectBytes: limits.maxWireBytes,
    });
    assert(Object.isFrozen(admitted.plan));
    assert.throws(() => prepareCompletedEffectFreeRunPublication({
      store: {publicationCapacitySupports: () => false},
      control,
      publicationInventory,
      plan,
    }), {code: 'RunPublicationCapacityUnsupported'});
    assert.throws(() => prepareCompletedEffectFreeRunPublication({
      store: {publicationCapacitySupports: () => true},
      control,
      publicationInventory: Object.freeze({occurrences: Object.freeze([])}),
      plan,
    }), {code: 'InvalidRunPublicationPreflight'});
    const missingBatchLimit = Object.freeze(Object.fromEntries(
      Object.entries(publicationOutputLimits)
        .filter(([name]) => name !== 'maxBatchBytes'),
    ));
    assert.throws(() => prepareCompletedEffectFreeRunPublication({
      store: {publicationCapacitySupports: () => true},
      control,
      publicationInventory,
      plan: Object.freeze({...plan, outputLimits: missingBatchLimit}),
    }), {code: 'InvalidRunPublicationPreflight'});
    assert.throws(() => prepareCompletedEffectFreeRunPublication({
      store: {publicationCapacitySupports: () => true},
      control,
      publicationInventory,
      plan: Object.freeze({
        ...plan,
        outputLimits: Object.freeze({
          ...publicationOutputLimits,
          maxSchemaBytes: -1,
        }),
      }),
    }), {code: 'InvalidRunPublicationPreflight'});
    assert.throws(() => prepareCompletedEffectFreeRunPublication({
      store: {publicationCapacitySupports: () => true},
      control,
      publicationInventory,
      plan: Object.freeze({
        ...plan,
        outputLimits: Object.freeze({
          ...publicationOutputLimits,
          unboundedBytes: 1,
        }),
      }),
    }), {code: 'InvalidRunPublicationPreflight'});
  });

test('portable control validates the exact Run Result publication chain', () => {
  const control = runtimeCore(moon).publicationControl;
  const run = control.seal('run_definition', JSON.stringify({
    version: 'actql-run-definition/0.1',
    scope_id: 'scope',
    run_id: 'run',
    compiled_plan_cid: cid('3'),
    invocation_template_cid: cid('1'),
    authorization_context_cid: cid('4'),
    input_artifact_set_cid: cid('5'),
    created_at: '2026-09-18T00:00:00.000Z',
    valid_until: '2026-09-18T01:00:00.000Z',
  }), limits);
  const invoked = invocation(control);
  const definition = control.seal('result_definition', JSON.stringify({
    version: 'actql-result-definition/0.1',
    program_definition_cid: cid('6'),
    result_name: 'answer',
  }), limits);
  const retention = control.seal('result_retention_policy', JSON.stringify({
    version: 'actql-result-retention-policy/0.1',
    retention_contract_cid: cid('b'),
    effective_data_policy_cid: cid('a'),
    available_until: '2026-09-18T01:00:00.000Z',
    delete_by: '2026-09-18T02:00:00.000Z',
    extension_ceiling_at: '2026-09-18T03:00:00.000Z',
    metadata_retention_policy_cid: cid('c'),
    metadata_delete_by: '2026-09-18T04:00:00.000Z',
    clock_contract_cid: cid('d'),
  }), limits);
  const resultSchema = Object.freeze({
    value: Object.freeze({nullable: false, type: 'integer'}),
  });
  const resultSchemaWire = JSON.stringify(canonical(resultSchema));
  const resultSchemaCid = canonicalCid(resultSchema);
  const derivation = control.seal('derivation_evidence', JSON.stringify({
    version: 'actql-acquisition-derivation-evidence/0.1',
    producer_contract_cid: definition.identity,
    computation_contract_cid: cid('3'),
    input_relation_cids: [],
    logical_value_cid: canonicalCid({
      sort: 'relation',
      value: [{value: 7}],
    }),
    relation_schema_cid: resultSchemaCid,
    scope_cid: cid('5'),
    effective_data_policy_cid: cid('a'),
    ordering: {kind: 'occurrence', terms: []},
    issuer_id: 'common-host',
    authority_scope_cid: cid('d'),
  }), limits);
  const ordering = control.seal('ordering_evidence', JSON.stringify({
    version: 'actql-acquisition-ordering/0.1',
    producer_contract_cid: definition.identity,
    kind: 'occurrence',
    terms: [],
    witness_evidence: [{kind: 'derivation', cid: derivation.identity}],
  }), limits);
  const resultRows = [{value: 7}];
  const logicalResultCid = canonicalCid({sort: 'relation', value: resultRows});
  const artifact = control.seal('result_artifact', JSON.stringify({
    version: 'actql-result-artifact/0.1',
    result_definition_cid: definition.identity,
    invocation_cid: invoked.identity,
    logical_result_cid: logicalResultCid,
    result_schema_cid: resultSchemaCid,
    ordering_evidence_cid: ordering.identity,
    actual_row_count: 1,
    actual_completeness: 'complete',
    effective_data_policy_cid: cid('a'),
    effective_retention_policy_cid: retention.identity,
    provenance_evidence_cids: [derivation.identity],
  }), limits);
  const manifest = control.issueResultManifest(
    run, invoked, [definition], [artifact], limits,
  );
  assert.equal(control.runChainValid(
    run, invoked, [definition], [artifact], manifest, limits,
  ), true);
  assert.equal(control.runChainValid(
    run, invoked, [definition], [], manifest, limits,
  ), false);
});

test('portable control validates Receipt and Captured Run references',
  async t => {
  const control = runtimeCore(moon).publicationControl;
  const template = control.sealRunEvidence(
    'bound_invocation_template',
    JSON.stringify({
      version: 'actql-bound-invocation-template/0.1',
      program_definition_cid: cid('6'),
      parameter_values_cid: cid('1'),
      invocation_bindings_cid: cid('2'),
      check_environment_cid: cid('4'),
      grammar_manifest_cid: cid('5'),
      required_profile_contracts: [],
      barrier_contract_manifest_cid: cid('7'),
      source_evidence: 'unbound',
    }),
    limits,
  );
  const compiledPlan = control.seal('compiled_plan', JSON.stringify({
    version: 'actql-compiled-plan/0.1',
    compiler_version: 'compiler-0.1',
    aoa_ir_version: 'aoa-ir-0.1',
    executable_plan_cid: cid('0'),
    program_definition_cid: cid('6'),
    program_semantics_cid: cid('e'),
    aoa_contract_cid: cid('d'),
    aoa_logical_cid: cid('f'),
  }), limits);
  const prepared = control.sealRunEvidence(
    'prepared_invocation',
    JSON.stringify({
      version: 'actql-prepared-invocation/0.1',
      invocation_template_cid: template.identity,
      compiled_plan_cid: compiledPlan.identity,
      execution_context_cid: cid('4'),
      host_policy_cid: cid('5'),
      policy_decision: 'allow',
      expires_at: '2026-09-18T03:00:00.000Z',
    }),
    limits,
  );
  const authorization = control.sealRunEvidence(
    'run_authorization',
    JSON.stringify({
      version: 'actql-run-authorization/0.1',
      prepared_invocation_cid: prepared.identity,
      execution_context_cid: cid('4'),
      host_policy_cid: cid('5'),
      decision: 'allowed',
    }),
    limits,
  );
  const admission = control.admitRunPublication(
    template,
    prepared,
    authorization,
    compiledPlan,
  );
  const run = control.issueRunDefinition(admission, {
    scopeId: 'scope',
    runId: 'run',
    inputArtifactSetCid: cid('5'),
    createdAt: '2026-09-18T00:00:00.000Z',
    validUntil: '2026-09-18T01:00:00.000Z',
  }, limits);
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
      data_policy_cid: cid('a'),
    }),
    limits,
  );
  const invoked = control.issueRunInvocation(template, observation, limits);
  const definition = control.seal('result_definition', JSON.stringify({
    version: 'actql-result-definition/0.1',
    program_definition_cid: cid('6'),
    result_name: 'answer',
  }), limits);
  const retention = control.seal('result_retention_policy', JSON.stringify({
    version: 'actql-result-retention-policy/0.1',
    retention_contract_cid: cid('b'),
    effective_data_policy_cid: cid('a'),
    available_until: '2026-09-18T01:00:00.000Z',
    delete_by: '2026-09-18T02:00:00.000Z',
    extension_ceiling_at: '2026-09-18T03:00:00.000Z',
    metadata_retention_policy_cid: cid('c'),
    metadata_delete_by: '2026-09-18T04:00:00.000Z',
    clock_contract_cid: cid('d'),
  }), limits);
  const resultSchema = Object.freeze({
    value: Object.freeze({nullable: false, type: 'integer'}),
  });
  const resultSchemaWire = JSON.stringify(canonical(resultSchema));
  const resultSchemaCid = canonicalCid(resultSchema);
  const derivation = control.seal('derivation_evidence', JSON.stringify({
    version: 'actql-acquisition-derivation-evidence/0.1',
    producer_contract_cid: definition.identity,
    computation_contract_cid: cid('3'),
    input_relation_cids: [],
    logical_value_cid: canonicalCid({
      sort: 'relation',
      value: [{value: 7}],
    }),
    relation_schema_cid: resultSchemaCid,
    scope_cid: cid('5'),
    effective_data_policy_cid: cid('a'),
    ordering: {kind: 'occurrence', terms: []},
    issuer_id: 'common-host',
    authority_scope_cid: cid('d'),
  }), limits);
  const ordering = control.seal('ordering_evidence', JSON.stringify({
    version: 'actql-acquisition-ordering/0.1',
    producer_contract_cid: definition.identity,
    kind: 'occurrence',
    terms: [],
    witness_evidence: [{kind: 'derivation', cid: derivation.identity}],
  }), limits);
  const resultRows = [{value: 7}];
  const logicalResultCid = canonicalCid({sort: 'relation', value: resultRows});
  const artifact = control.seal('result_artifact', JSON.stringify({
    version: 'actql-result-artifact/0.1',
    result_definition_cid: definition.identity,
    invocation_cid: invoked.identity,
    logical_result_cid: logicalResultCid,
    result_schema_cid: resultSchemaCid,
    ordering_evidence_cid: ordering.identity,
    actual_row_count: 1,
    actual_completeness: 'complete',
    effective_data_policy_cid: cid('a'),
    effective_retention_policy_cid: retention.identity,
    provenance_evidence_cids: [derivation.identity],
  }), limits);
  const manifest = control.issueResultManifest(
    run, invoked, [definition], [artifact], limits,
  );
  const normalizationJournal = control.sealRunEvidence(
    'normalization_journal',
    JSON.stringify({
      version: 'actql-normalization-journal/0.1',
      rule_catalog_cid: cid('c'),
      entries: [],
    }),
    limits,
  );
  const receipt = control.issueEffectFreeRunReceipt({
    admission,
    runDefinition: run,
    invocation: invoked,
    observation,
    definitions: [definition],
    artifacts: [artifact],
    manifest,
  }, {
    normalizationJournal,
    bindings: [],
    sourceEvidence: [],
    modelEvidence: [],
    barrierAttemptReceiptCids: [],
  }, limits);
  const authoringContext = control.sealRunEvidence(
    'authoring_context',
    JSON.stringify({
      version: 'actql-authoring-context/0.1',
      program_definition_cid: cid('6'),
      annotations: [],
    }),
    limits,
  );
  const snapshot = control.admitCapturedResultSnapshot(
    definition,
    artifact,
    JSON.stringify(resultRows),
    ['value'],
    limits,
  );
  const captured = control.issueEffectFreeCapturedRun({
    runDefinition: run,
    invocation: invoked,
    definitions: [definition],
    artifacts: [artifact],
    manifest,
    receipt,
  }, {
    snapshots: [snapshot],
    pendingSourceStateAdvances: [],
    authoringContext,
    modelEvidence: [],
  }, limits);
  const receiptBody = JSON.parse(receipt.wire);
  const {result_definition_cid: ignoredDefinition,
    ordering_evidence_cid: ignoredOrdering,
    result_artifact_cid: ignoredIdentity, ...artifactBody} =
    JSON.parse(artifact.wire);
  const sourceArtifact = control.seal('effect_source_artifact',
    JSON.stringify({...artifactBody,
      version: 'actql-effect-source-artifact/0.1',
      source_result: 'rows', source_binding_cid: cid('9'),
      store_authority_cid: cid('a')}), limits);
  const previewBody = {
    version: 'actql-effect-preview/0.1', sensitivity: 'private',
    retention_class: 'authority-evidence', encryption_required: true,
    program_semantics_cid: receiptBody.program_semantics_cid,
    program_definition_cid: receiptBody.program_definition_cid,
    invocation_cid: invoked.identity, run_identity_cid: run.identity,
    compiled_plan_cid: receiptBody.compiled_plan_cid,
    check_environment_cid: receiptBody.check_environment_cid,
    authoring_context: JSON.parse(authoringContext.wire),
    barrier_provenance_cids: [], model_derived: false,
    model_task_contract_cids: [], model_invocation_evidence_cids: [],
    model_response_artifact_cids: [],
    effects: [{
      effect_id: 'WriteOne', effect_kind: 'update', target: 'Object',
      mapping: 'mapping:fixture', resolved_mapping_contract_cid: cid('9'),
      effect_identity_cid: cid('9'), effect_plan_logical_cid: cid('9'),
      source_result: 'rows', result_artifact_cid: sourceArtifact.identity,
      preview_strength: 'full_diff', source_binding_cid: cid('9'),
      capability_evidence_cid: cid('9'), authority_scope_cid: cid('9'),
      write_footprint: {kind: 'exact_targets',
        resource_identity_scheme_cid: cid('9'),
        provider_namespace: 'provider', provider_boundary_cid: cid('9'),
        resource_kind: 'Object', provider_object_identity_cids: [cid('1')]},
      count: 0, max_items: 1, required_permissions: ['write'],
      approval: 'none', on_item_failure: 'halt', changes: [], row_order: [],
      effect_member_preview_cid: cid('1'), executed: false,
    }],
    executed: false, effect_preview_cid: cid('2'),
  };
  const previewWire = () => JSON.stringify(canonical(previewBody));
  previewBody.effects[0].effect_member_preview_cid =
    checked(moon.strategyEffectPreviewIdentities(previewWire(),
      limits.maxWireBytes, limits.maxNodes, limits.maxDepth))[1];
  previewBody.effect_preview_cid =
    checked(moon.strategyEffectPreviewIdentities(previewWire(),
      limits.maxWireBytes, limits.maxNodes, limits.maxDepth))[0];
  assert.equal(previewBody.authoring_context.authoring_context_cid,
    authoringContext.identity);
  assert.equal(previewBody.authoring_context.program_definition_cid,
    previewBody.program_definition_cid);
  assert.equal(previewBody.run_identity_cid, run.identity);
  assert.deepEqual(checked(moon.strategyEffectPreviewIdentities(previewWire(),
    limits.maxWireBytes, limits.maxNodes, limits.maxDepth)),
  [previewBody.effect_preview_cid,
    previewBody.effects[0].effect_member_preview_cid]);
  const preview = control.admitEffectComputationPreview(
    previewWire(), run, authoringContext, limits);
  const privateBinding = control.effectPrivateEvidenceBinding(preview, cid('a'));
  assert.deepEqual(Object.keys(privateBinding),
    ['name', 'semanticCid', 'holdingCid', 'wire']);
  assert.equal(privateBinding.name, 'effect_preview');
  assert.equal(privateBinding.semanticCid, previewBody.effect_preview_cid);
  assert.equal(privateBinding.wire, previewWire());
  assert.match(privateBinding.holdingCid, /^sha256:[0-9a-f]{64}$/u);
  assert.notEqual(control.effectPrivateEvidenceBinding(
    preview, cid('b')).holdingCid, privateBinding.holdingCid);
  assert.throws(() => control.effectPrivateEvidenceBinding(
    Object.freeze({kind: 'effect-computation-preview'}), cid('a')),
  /Foreign Effect computation Preview/u);
  assert.throws(() => control.effectPrivateEvidenceBinding(
    preview, 'foreign'), {code: 'MoonBitHostFailure'});
  const computationChain = {
    runDefinition: run, invocation: invoked, definitions: [definition],
    artifacts: [artifact], manifest, receipt,
  };
  const computationEvidence = {snapshots: [snapshot],
    effectSources: [control.admitCapturedEffectSourceArtifact(
      preview, 0, invoked, sourceArtifact, cid('a'))],
    pendingSourceStateAdvances: [], authoringContext, modelEvidence: []};
  assert.throws(() => control.issueEffectfulCapturedRun(
    computationChain, computationEvidence, preview,
    [{name: 'WriteOne', wire: '{}'}], limits),
  {name: 'TypeError', message: 'Invalid Effectful Captured Run request'});
  const localDefinitionBody = {
    version: 'actql-local-result-definition/0.1',
    unit_definition_cid: cid('1'), result_name: 'rows',
  };
  const localDefinition = canonical({
    ...localDefinitionBody,
    self_cid: canonicalCid(localDefinitionBody),
  });
  const localInvocationBody = {
    version: 'actql-local-computation-semantics/0.1',
    unit_definition_cid: cid('1'), used_values_cid: cid('2'),
    local_contracts_cid: cid('3'), observation_cids: [],
    policy_cid: cid('a'),
  };
  const localInvocation = canonical({
    ...localInvocationBody,
    self_cid: canonicalCid(localInvocationBody),
  });
  const localDerivationBody = {...JSON.parse(derivation.wire),
    producer_contract_cid: localDefinition.self_cid};
  delete localDerivationBody[derivation.identityField];
  const localDerivation = control.seal('derivation_evidence',
    JSON.stringify(localDerivationBody), limits);
  const localOrderingBody = {...JSON.parse(ordering.wire),
    producer_contract_cid: localDefinition.self_cid,
    witness_evidence: [{kind: 'derivation',
      cid: localDerivation.identity}]};
  delete localOrderingBody[ordering.identityField];
  const localOrdering = control.seal('ordering_evidence',
    JSON.stringify(localOrderingBody), limits);
  const localArtifact = control.seal('result_artifact', JSON.stringify({
    ...artifactBody,
    version: 'actql-result-artifact/0.1',
    result_definition_cid: localDefinition.self_cid,
    invocation_cid: localInvocation.self_cid,
    ordering_evidence_cid: localOrdering.identity,
    provenance_evidence_cids: [localDerivation.identity],
  }), limits);
  const localManifestBody = {
    version: 'actql-local-result-manifest/0.1',
    unit_definition_cid: cid('1'),
    local_invocation_cid: localInvocation.self_cid,
    results: {rows: localArtifact.identity},
  };
  const localManifest = canonical({
    ...localManifestBody,
    self_cid: canonicalCid(localManifestBody),
  });
  const rawContract = value => checked(moon.strategyPublicationAdmit(
    value.name, value.wire,
    limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
  const rawPreview = checked(moon.strategyAdmitEffectComputationPreview(
    previewWire(), run.identity, authoringContext.identity,
    limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
  const rawSource = checked(moon.strategyAdmitCapturedEffectSourceArtifact(
    rawPreview, 0, rawContract(invoked), rawContract(sourceArtifact), cid('a')));
  const rawLocal = checked(moon.strategyAdmitCapturedLocalEffectSource(
    rawSource, JSON.stringify(localDefinition),
    JSON.stringify(localInvocation), JSON.stringify(localManifest),
    rawContract(localArtifact), rawContract(localDerivation),
    rawContract(localOrdering), rawContract(retention),
    limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
  const issueDirect = plans => {
    const rawCaptured = checked(moon.strategyIssueEffectfulCapturedRun(
      rawContract(run), rawContract(invoked), [rawContract(definition)],
      [rawContract(artifact)], rawContract(manifest), rawContract(receipt),
      [checked(moon.strategyAdmitCapturedResultSnapshot(
        rawContract(definition), rawContract(artifact),
        JSON.stringify(resultRows), ['value'],
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth))],
      [rawSource], [rawLocal], [],
      checked(moon.strategyRunEvidenceAdmit('authoring_context',
        authoringContext.wire, limits.maxWireBytes, limits.maxNodes,
        limits.maxDepth)), [], rawPreview,
      plans.map(value => value.name), plans.map(value => value.wire),
      limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
    return control.admit('captured_run',
      moon.strategyPublicationContractJson(rawCaptured), limits);
  };
  const effectfulCaptured = issueDirect([{name: 'WriteOne', wire: '{}'}]);
  assert.equal(effectfulCaptured.name, 'captured_run');
  assert.deepEqual(Object.keys(JSON.parse(effectfulCaptured.wire)
    .effect_context.effect_source_local_inventory), ['WriteOne']);
  assert.deepEqual(Object.keys(JSON.parse(effectfulCaptured.wire)
    .effect_context.effects), ['WriteOne']);
  assert.throws(() => issueDirect([]),
  {code: 'MoonBitHostFailure'});
  assert.throws(() => issueDirect([{name: 'Foreign', wire: '{}'}]),
  {code: 'MoonBitHostFailure'});
  const memberReceipt = control.seal('effect_apply_receipt',
    JSON.stringify({
      version: 'actql-effect-apply-receipt/0.1',
      run_identity_cid: previewBody.run_identity_cid,
      effect_preview_cid: previewBody.effect_preview_cid,
      effect_member_preview_cid:
        previewBody.effects[0].effect_member_preview_cid,
      rows: [], status: 'applied',
    }), limits);
  const setReceipt = control.seal('effect_set_apply_receipt',
    JSON.stringify({
      version: 'actql-effect-set-apply-receipt/0.1',
      effect_preview_cid: previewBody.effect_preview_cid,
      apply_policy: 'attempt_all',
      effects: [{
        effect_id: 'WriteOne',
        effect_member_preview_cid:
          previewBody.effects[0].effect_member_preview_cid,
        state: 'applied', replayed: false,
        member_receipt_cid: memberReceipt.identity,
      }],
      status: 'applied',
    }), limits);
  const issuedSet = control.issueEffectSetApplyReceiptFromMembers(
    preview, [memberReceipt], [false], limits);
  assert.equal(issuedSet.identity, setReceipt.identity);
  assert.equal(control.effectSetReceiptRunDisposition(preview, {
    setWire: issuedSet.wire, memberWires: [memberReceipt.wire],
  }, limits), 0);
  assert.throws(() => control.issueEffectSetApplyReceiptFromMembers(
    preview, [memberReceipt], [], limits), {code: 'MoonBitHostFailure'});
  const finalChain = {
    runDefinition: run, invocation: invoked,
    definitions: [definition], artifacts: [artifact], manifest,
    computationReceipt: receipt, capturedRun: effectfulCaptured,
  };
  const finalReceipt = control.issueEffectfulFinalRunReceipt(
    finalChain, preview, {setWire: setReceipt.wire,
      memberWires: [memberReceipt.wire]}, limits);
  assert.equal(JSON.parse(finalReceipt.wire).captured_run_cid,
    effectfulCaptured.identity);
  assert.equal(JSON.parse(finalReceipt.wire).effect_preview_cid,
    previewBody.effect_preview_cid);
  assert.notEqual(finalReceipt.identity, receipt.identity);
  assert.throws(() => control.issueEffectfulFinalRunReceipt(
    finalChain, {}, {setWire: setReceipt.wire,
      memberWires: [memberReceipt.wire]}, limits),
  {name: 'TypeError', message: 'Foreign Effect computation Preview'});
  assert.throws(() => control.issueEffectfulFinalRunReceipt(
    finalChain, preview, {setWire: setReceipt.wire,
      memberWires: []}, limits),
  {code: 'MoonBitHostFailure'});
  assert.throws(() => control.issueEffectfulFinalRunReceipt(
    {...finalChain, capturedRun: captured}, preview,
    {setWire: setReceipt.wire,
      memberWires: [memberReceipt.wire]}, limits),
  {code: 'MoonBitHostFailure'});
  const payloadWire = JSON.stringify(resultRows);
  const payloadBytes = Buffer.byteLength(payloadWire, 'utf8');
  const physicalCid = `sha256:${createHash('sha256')
    .update(payloadWire).digest('hex')}`;
  const binding = control.issueDurableResultBinding({
    runDefinition: run,
    definition,
    invocation: invoked,
    artifact,
    ordering,
    retention,
  }, {
    codecContractCid: cid('b'),
    resultFields: ['value'],
    resultSchemaWire,
    materialGenerationCid: physicalCid,
    storeAuthorityCid: cid('a'),
    rowCount: 1,
    byteCount: payloadBytes,
    physicalSha256: physicalCid.slice(7),
  }, limits);
  const request = control.issuePublicationRequest(run, [definition], {
    namespaceId: 'namespace-a',
    authorityScopeCid: cid('d'),
    publicationPolicyCid: cid('e'),
    publicationTargetCid: cid('f'),
    requestedAt: '2026-09-18T00:00:00.000Z',
  }, limits);
  const attempt = control.issuePublicationAttempt(request, run, {
    attemptId: 'attempt-1',
    fenceCid: cid('0'),
    startedAt: '2026-09-18T00:00:01.000Z',
  }, limits);
  const indexEntry = control.issuePublicIndexEntry({
    runDefinition: run,
    invocation: invoked,
    manifest,
    receipt,
    capturedRun: captured,
    durableBindings: [binding],
    request,
    attempt,
  }, '2026-09-18T00:00:02.000Z', limits);
  const effectfulIndex = control.issuePublicIndexEntry({
    runDefinition: run,
    invocation: invoked,
    manifest,
    receipt: finalReceipt,
    capturedRun: effectfulCaptured,
    durableBindings: [binding],
    request,
    attempt,
  }, '2026-09-18T00:00:02.000Z', limits);
  assert.equal(control.publicIndexSameCommittedContent(
    indexEntry, indexEntry), true);
  assert.equal(control.publicIndexSameCommittedContent(
    indexEntry, effectfulIndex), false);
  const effectfulEvidence = {
    ...finalChain,
    derivations: [derivation],
    orderings: [ordering],
    retentions: [retention],
    durableBindings: [binding],
  };
  const effectfulReceipts = {setWire: setReceipt.wire,
    memberWires: [memberReceipt.wire], finalWire: finalReceipt.wire};
  assert.equal(control.effectfulCommitValid(effectfulEvidence, preview,
    effectfulReceipts, request, attempt, effectfulIndex, limits), true);
  assert.equal(control.effectfulCommitValid(effectfulEvidence, preview,
    effectfulReceipts, request, attempt, indexEntry, limits), false);
  assert.equal(control.effectfulCommitValid({...effectfulEvidence,
    derivations: []}, preview, effectfulReceipts, request, attempt,
  effectfulIndex, limits), false);
  assert.throws(() => control.effectfulCommitValid(effectfulEvidence, {},
    effectfulReceipts, request, attempt, effectfulIndex, limits),
  {name: 'TypeError', message: 'Foreign Effect computation Preview'});
  assert.equal(control.effectFreeChainValid(
    run,
    invoked,
    [definition],
    [artifact],
    manifest,
    receipt,
    captured,
    limits,
  ), true);
  assert.equal(control.effectFreeCommitValid(
    run,
    invoked,
    [definition],
    [artifact],
    [derivation],
    [ordering],
    [retention],
    [binding],
    manifest,
    receipt,
    captured,
    request,
    attempt,
    indexEntry,
    limits,
  ), true);
  const foreignDefinition = control.seal(
    'result_definition',
    JSON.stringify({
      version: 'actql-result-definition/0.1',
      program_definition_cid: cid('f'),
      result_name: 'answer',
    }),
    limits,
  );
  assert.equal(control.effectFreeChainValid(
    run,
    invoked,
    [foreignDefinition],
    [artifact],
    manifest,
    receipt,
    captured,
    limits,
  ), false);
  const wrongReceiptValue = JSON.parse(receipt.wire);
  delete wrongReceiptValue.receipt_identity_cid;
  wrongReceiptValue.compiled_plan_cid = cid('e');
  const wrongReceipt = control.seal(
    'run_receipt', JSON.stringify(wrongReceiptValue), limits,
  );
  const wrongReceiptCaptureValue = JSON.parse(captured.wire);
  delete wrongReceiptCaptureValue.captured_run_cid;
  wrongReceiptCaptureValue.receipt = JSON.parse(wrongReceipt.wire);
  const wrongReceiptCapture = control.seal(
    'captured_run', JSON.stringify(wrongReceiptCaptureValue), limits,
  );
  assert.equal(control.effectFreeChainValid(
    run,
    invoked,
    [definition],
    [artifact],
    manifest,
    wrongReceipt,
    wrongReceiptCapture,
    limits,
  ), false);
  const wrongInventoryValue = JSON.parse(captured.wire);
  delete wrongInventoryValue.captured_run_cid;
  const wrongEffect = wrongInventoryValue.effect_context;
  delete wrongEffect.effect_context_cid;
  wrongEffect.result_values = {foreign: null};
  wrongEffect.effect_context_cid = canonicalCid(wrongEffect);
  const wrongInventoryCapture = control.seal(
    'captured_run', JSON.stringify(wrongInventoryValue), limits,
  );
  assert.equal(control.effectFreeChainValid(
    run,
    invoked,
    [definition],
    [artifact],
    manifest,
    receipt,
    wrongInventoryCapture,
    limits,
  ), false);
  const wrongIndex = control.seal('public_index_entry', JSON.stringify({
    ...JSON.parse(indexEntry.wire),
    public_index_entry_cid: undefined,
    result_manifest_cid: cid('0'),
  }), limits);
  assert.equal(control.effectFreeCommitValid(
    run,
    invoked,
    [definition],
    [artifact],
    [derivation],
    [ordering],
    [retention],
    [binding],
    manifest,
    receipt,
    captured,
    request,
    attempt,
    wrongIndex,
    limits,
  ), false);
  const directory = await mkdtemp(join(
    tmpdir(), 'actql-publication-chain-',
  ));
  t.after(() => rm(directory, {recursive: true, force: true}));
  const store = await openLocalPublicationStore({
    directory,
    storeAuthorityCid: cid('a'),
    capacityBytes: 4 * 1024 * 1024,
    maxObjectBytes: limits.maxWireBytes,
    maxObjects: 100,
    maxContractNodes: limits.maxNodes,
    maxContractDepth: limits.maxDepth,
    privateEvidenceKey: Buffer.alloc(32, 4),
  }, control);
  t.after(async () => { await store.close(); });
  const privatePrepared = await store.preparePrivateEvidence(
    privateBinding.name, privateBinding.wire, privateBinding.semanticCid,
  );
  await store.commitPhysicalHolding({
    version: 'actql-local-physical-holding/0.1',
    namespace: 'publication-private',
    holding_cid: privateBinding.holdingCid,
    manifest_cid: privateBinding.semanticCid,
    objects: [{cid: privatePrepared.physicalCid,
      byte_count: privatePrepared.bytes}],
  }, [privatePrepared.prepared]);
  assert.equal((await store.readPrivateEvidence(
    privateBinding.name,
    privateBinding.semanticCid,
    privateBinding.holdingCid,
  )).toString('utf8'), privateBinding.wire);
  assert.equal((await store.confirmPrivateEvidence(privateBinding))
    .holding_cid, privateBinding.holdingCid);
  for (const contract of [
    run,
    invoked,
    definition,
    artifact,
    derivation,
    ordering,
    retention,
    binding,
    manifest,
    receipt,
    captured,
    request,
    sourceArtifact,
    effectfulCaptured,
    memberReceipt,
    setReceipt,
    finalReceipt,
    foreignDefinition,
  ]) {
    await store.putPublicationContract(contract.name, contract.wire);
  }
  await store.putSemantic(resultSchemaWire, resultSchemaCid);
  await store.putBytes(Buffer.from(payloadWire, 'utf8'), physicalCid);
  await store.createAttempt(attempt.wire);
  const preparing = control.issuePublicationRecord(attempt, undefined, {
    state: 'preparing',
    observedAt: '2026-09-18T00:00:03.000Z',
    cleanupOwnerCids: [],
    uncommittedConfirmed: false,
  }, limits);
  await store.appendRecord(preparing.wire, {
    uncommittedConfirmed: false,
  });
  const committing = control.issuePublicationRecord(attempt, preparing, {
    state: 'committing',
    observedAt: '2026-09-18T00:00:04.000Z',
    cleanupOwnerCids: [],
    uncommittedConfirmed: false,
  }, limits);
  await store.appendRecord(committing.wire, {
    uncommittedConfirmed: false,
  });
  const source = computationEvidence.effectSources[0];
  const sourceWriter = store.createPreparedObjectWriter(payloadBytes);
  await sourceWriter.append(Buffer.from(payloadWire, 'utf8'));
  const sourcePrepared = await sourceWriter.seal(physicalCid);
  const sourceHoldingCid = control.capturedEffectSourceHoldingCid(source);
  await store.commitPhysicalHolding({
    version: 'actql-local-physical-holding/0.1',
    namespace: 'effect-source',
    holding_cid: sourceHoldingCid,
    manifest_cid: sourceArtifact.identity,
    objects: [{cid: sourcePrepared.cid, byte_count: sourcePrepared.bytes}],
  }, [sourcePrepared.prepared]);
  const effectfulPreparation = {
    index: effectfulIndex,
    chain: effectfulEvidence,
    preview,
    receipts: effectfulReceipts,
    privateBinding,
    effectSources: [source],
  };
  const checkedPreparation = await store.inspectEffectfulStoredEvidence(
    effectfulPreparation);
  assert.equal(checkedPreparation.finalReceipt.identity,
    finalReceipt.identity);
  assert.equal(checkedPreparation.privateHoldingCid,
    privateBinding.holdingCid);
  assert.deepEqual(checkedPreparation.effectSourceHoldingCids,
    [sourceHoldingCid]);
  const effectfulDirectory = await mkdtemp(join(
    tmpdir(), 'actql-effectful-publication-commit-',
  ));
  t.after(() => rm(effectfulDirectory, {recursive: true, force: true}));
  const effectfulConfiguration = {
    directory: effectfulDirectory,
    storeAuthorityCid: cid('a'),
    capacityBytes: 4 * 1024 * 1024,
    maxObjectBytes: limits.maxWireBytes,
    maxObjects: 100,
    maxContractNodes: limits.maxNodes,
    maxContractDepth: limits.maxDepth,
    privateEvidenceKey: Buffer.alloc(32, 4),
  };
  const effectfulStore = await openLocalPublicationStore(
    effectfulConfiguration, control,
  );
  t.after(async () => { await effectfulStore.close(); });
  const effectfulPrivate = await effectfulStore.preparePrivateEvidence(
    privateBinding.name, privateBinding.wire, privateBinding.semanticCid,
  );
  await effectfulStore.commitPhysicalHolding({
    version: 'actql-local-physical-holding/0.1',
    namespace: 'publication-private',
    holding_cid: privateBinding.holdingCid,
    manifest_cid: privateBinding.semanticCid,
    objects: [{cid: effectfulPrivate.physicalCid,
      byte_count: effectfulPrivate.bytes}],
  }, [effectfulPrivate.prepared]);
  for (const contract of [
    run, invoked, definition, artifact, derivation, ordering, retention,
    binding, manifest, receipt, sourceArtifact, effectfulCaptured,
    memberReceipt, setReceipt, finalReceipt, request, attempt,
  ]) {
    await effectfulStore.putPublicationContract(
      contract.name, contract.wire,
    );
  }
  await effectfulStore.putSemantic(resultSchemaWire, resultSchemaCid);
  await effectfulStore.putBytes(Buffer.from(payloadWire, 'utf8'), physicalCid);
  await effectfulStore.createAttempt(attempt.wire);
  await effectfulStore.appendRecord(preparing.wire, {
    uncommittedConfirmed: false,
  });
  await effectfulStore.appendRecord(committing.wire, {
    uncommittedConfirmed: false,
  });
  const effectfulSourceWriter = effectfulStore.createPreparedObjectWriter(
    payloadBytes,
  );
  await effectfulSourceWriter.append(Buffer.from(payloadWire, 'utf8'));
  const effectfulSource = await effectfulSourceWriter.seal(physicalCid);
  await effectfulStore.commitPhysicalHolding({
    version: 'actql-local-physical-holding/0.1',
    namespace: 'effect-source',
    holding_cid: sourceHoldingCid,
    manifest_cid: sourceArtifact.identity,
    objects: [{cid: effectfulSource.cid,
      byte_count: effectfulSource.bytes}],
  }, [effectfulSource.prepared]);
  const effectfulRequired = [...new Set([
    run.identity, invoked.identity, definition.identity, artifact.identity,
    derivation.identity, ordering.identity, retention.identity,
    binding.identity, manifest.identity, receipt.identity,
    sourceArtifact.identity, effectfulCaptured.identity,
    memberReceipt.identity, setReceipt.identity, finalReceipt.identity,
    request.identity, attempt.identity, resultSchemaCid,
  ])];
  await assert.rejects(effectfulStore.commitEffectfulIndex(
    effectfulPreparation,
    effectfulRequired.filter(cid => cid !== sourceArtifact.identity),
  ), {code: 'IncompletePublicationCommitInventory'});
  assert.equal(await effectfulStore.inspectCommittedIndex({
    namespaceId: 'namespace-a',
    authorityScopeCid: cid('d'),
    runDefinitionCid: run.identity,
  }), undefined);
  const effectfulFixtureLedger = Object.freeze({});
  const effectfulPublication = {
    store: effectfulStore,
    control,
    chain: effectfulEvidence,
    preview,
    ledger: effectfulFixtureLedger,
    issuedSet: retainIssuedEffectSetReceipt({
      set: setReceipt, members: [memberReceipt],
      ledger: effectfulFixtureLedger, preview,
    }),
    effectSources: [source],
    sourceArtifacts: [sourceArtifact],
    request: {
      namespaceId: 'namespace-a',
      authorityScopeCid: cid('d'),
      publicationPolicyCid: cid('e'),
      publicationTargetCid: cid('f'),
      requestedAt: '2026-09-18T00:00:00.000Z',
    },
    attempt: {
      attemptId: 'attempt-1',
      fenceCid: cid('0'),
      externalIdempotencyKey: undefined,
      startedAt: '2026-09-18T00:00:01.000Z',
    },
    limits,
    now: () => '2026-09-18T00:00:02.000Z',
    signal: undefined,
  };
  await assert.rejects(publishEffectfulRun({
    ...effectfulPublication, sourceArtifacts: [],
  }), {code: 'InvalidEffectfulRunPublicationEvidence'});
  await assert.rejects(publishEffectfulRun({
    ...effectfulPublication,
    issuedSet: {...effectfulPublication.issuedSet},
  }), {code: 'EffectSetReceiptEvidenceNotOwned'});
  await assert.rejects(publishEffectfulRun({
    ...effectfulPublication, ledger: Object.freeze({}),
  }), {code: 'EffectSetReceiptEvidenceNotOwned'});
  assert.equal(await effectfulStore.inspectCommittedIndex({
    namespaceId: 'namespace-a',
    authorityScopeCid: cid('d'),
    runDefinitionCid: run.identity,
  }), undefined);
  let loseEffectfulCommitResponse = true;
  const lostEffectfulStore = Object.freeze({
    ...effectfulStore,
    async commitEffectfulIndex(...args) {
      const committed = await effectfulStore.commitEffectfulIndex(...args);
      if (loseEffectfulCommitResponse) {
        loseEffectfulCommitResponse = false;
        throw new Error('LostEffectfulCommitResponse');
      }
      return committed;
    },
  });
  const effectfulCommitted = await publishEffectfulRun({
    ...effectfulPublication, store: lostEffectfulStore,
  });
  assert.equal(effectfulCommitted.committed, false);
  assert.equal(effectfulCommitted.idempotent, true);
  assert.equal(effectfulCommitted.state, 'succeeded');
  assert.equal(effectfulCommitted.index.identity, effectfulIndex.identity);
  const effectfulReplay = await publishEffectfulRun(effectfulPublication);
  assert.equal(effectfulReplay.idempotent, true);
  const effectfulKey = {
    namespaceId: 'namespace-a',
    authorityScopeCid: cid('d'),
    runDefinitionCid: run.identity,
  };
  assert.deepEqual(await effectfulStore.inspectCommittedIndex(effectfulKey),
    JSON.parse(effectfulIndex.wire));
  await effectfulStore.close();
  const reopenedEffectfulStore = await openLocalPublicationStore(
    {...effectfulConfiguration, privateEvidenceKey: Buffer.alloc(32, 4)},
    control,
  );
  t.after(async () => { await reopenedEffectfulStore.close(); });
  assert.deepEqual(
    await reopenedEffectfulStore.inspectCommittedIndex(effectfulKey),
    JSON.parse(effectfulIndex.wire),
  );
  assert.equal(await reopenedEffectfulStore
    .validateCommittedEffectfulEvidence(effectfulPreparation), true);
  assert.notEqual(await reopenedEffectfulStore.inspectPhysicalHolding(
    privateBinding.holdingCid), undefined);
  assert.notEqual(await reopenedEffectfulStore.inspectPhysicalHolding(
    sourceHoldingCid), undefined);
  const effectfulRetired =
    await reopenedEffectfulStore.retireCommittedPublicationMetadata(
      effectfulKey, '2026-09-18T00:00:08.000Z',
    );
  assert.equal(effectfulRetired.deleted, true);
  assert.equal(await reopenedEffectfulStore.inspectPhysicalHolding(
    privateBinding.holdingCid), undefined);
  assert.equal(await reopenedEffectfulStore.inspectPhysicalHolding(
    sourceHoldingCid), undefined);
  await assert.rejects(store.inspectEffectfulStoredEvidence({
    ...effectfulPreparation, index: indexEntry,
  }), {code: 'InvalidEffectfulCommitChain'});
  await assert.rejects(store.inspectEffectfulStoredEvidence({
    ...effectfulPreparation,
    privateBinding: {...privateBinding, wire: '{}'},
  }), {code: 'EffectfulPrivateEvidenceUnavailable'});
  await assert.rejects(store.inspectEffectfulStoredEvidence({
    ...effectfulPreparation, effectSources: [],
  }), {code: 'InvalidEffectfulSourceInventory'});
  assert.equal((await store.retirePhysicalHolding(
    privateBinding.holdingCid,
  )).deleted, true);
  await assert.rejects(store.inspectEffectfulStoredEvidence(
    effectfulPreparation), {code: 'EffectfulPrivateEvidenceUnavailable'});
  const evidence = Object.freeze({
    runDefinition: run,
    invocation: invoked,
    definitions: Object.freeze([definition]),
    artifacts: Object.freeze([artifact]),
    derivations: Object.freeze([derivation]),
    orderings: Object.freeze([ordering]),
    retentions: Object.freeze([retention]),
    durableBindings: Object.freeze([binding]),
    manifest,
    receipt,
    capturedRun: captured,
  });
  const required = [...new Set([
    run.identity,
    invoked.identity,
    definition.identity,
    artifact.identity,
    derivation.identity,
    ordering.identity,
    retention.identity,
    binding.identity,
    manifest.identity,
    receipt.identity,
    captured.identity,
    request.identity,
    attempt.identity,
  ])];
  const foreignEvidence = Object.freeze({
    ...evidence,
    definitions: Object.freeze([foreignDefinition]),
  });
  await assert.rejects(store.commitIndex(
    indexEntry.wire,
    [...new Set([...required, foreignDefinition.identity])],
    foreignEvidence,
  ), error => error?.code === 'InvalidPublicationCommitChain');
  const times = [
    '2026-09-18T00:00:05.000Z',
    '2026-09-18T00:00:06.000Z',
  ];
  const publicationOptions = {
    store,
    control,
    evidence,
    request: {
      namespaceId: 'namespace-a',
      authorityScopeCid: cid('d'),
      publicationPolicyCid: cid('e'),
      publicationTargetCid: cid('f'),
      requestedAt: '2026-09-18T00:00:00.000Z',
    },
    attempt: {
      attemptId: 'attempt-1',
      fenceCid: cid('0'),
      externalIdempotencyKey: undefined,
      startedAt: '2026-09-18T00:00:01.000Z',
    },
    limits,
    now: () => times.shift() ?? '2026-09-18T00:00:07.000Z',
    signal: undefined,
  };
  let exportedResults = 0;
  const execution = Object.freeze({
    status: 'host-tasks-completed',
    resultInventory: Object.freeze([{name: 'answer', task: 1}]),
    publicationInventory: Object.freeze({
      occurrences: Object.freeze([Object.freeze({
        name: 'answer',
        task: 1,
        definitionContract: definition,
      })]),
    }),
    async storePublicationResult(index, target, supplied) {
      exportedResults++;
      assert.equal(index, 0);
      assert.equal(target, store);
      assert.equal(supplied.runDefinition, run);
      assert.equal(supplied.invocation, invoked);
      assert.equal(supplied.retention, retention);
      return Object.freeze({
        occurrence: Object.freeze({
          name: 'answer', task: 1, definition,
        }),
        physical: Object.freeze({cid: physicalCid, bytes: payloadBytes}),
        orderedRows: Object.freeze({rows: 1}),
        publication: Object.freeze({
          derivation,
          ordering,
          artifact,
          snapshot,
          durableBinding: binding,
        }),
      });
    },
  });
  const completedPublicationOptions = {
    execution,
    store,
    control,
    admission,
    runDefinition: run,
    invocation: invoked,
    observation,
    normalizationJournal,
    authoringContext,
    results: [{retention, evidenceContext: {}}],
    receiptEvidence: {
      bindings: [],
      sourceEvidence: [],
      modelEvidence: [],
      barrierAttemptReceiptCids: [],
    },
    captureEvidence: {
      pendingSourceStateAdvances: [],
      modelEvidence: [],
    },
    request: publicationOptions.request,
    attempt: publicationOptions.attempt,
    outputLimits: {},
    contractLimits: limits,
    now: () => '2026-09-18T00:00:05.000Z',
    signal: undefined,
  };
  await assert.rejects(publishCompletedEffectFreeRun({
    ...completedPublicationOptions,
    results: [],
  }), {code: 'InvalidCompletedRunPublicationOptions'});
  assert.equal(exportedResults, 0);
  const assembled = await publishCompletedEffectFreeRun(
    completedPublicationOptions,
  );
  assert.equal(exportedResults, 1);
  assert.equal(assembled.evidence.manifest.identity, manifest.identity);
  assert.equal(assembled.evidence.receipt.identity, receipt.identity);
  assert.equal(assembled.evidence.capturedRun.identity, captured.identity);
  const committed = assembled.publication;
  assert.equal(committed.state, 'succeeded');
  assert.equal(committed.committed, true);
  assert.equal(committed.idempotent, false);
  assert.deepEqual(await store.inspectCommittedIndex({
    namespaceId: 'namespace-a',
    authorityScopeCid: cid('d'),
    runDefinitionCid: run.identity,
  }), JSON.parse(committed.index.wire));
  const retried = await publishEffectFreeRun(publicationOptions);
  assert.equal(retried.state, 'succeeded');
  assert.equal(retried.committed, false);
  assert.equal(retried.idempotent, true);
  assert.equal(retried.index.identity, committed.index.identity);

  const completedUnknownDirectory = await mkdtemp(join(
    tmpdir(), 'actql-completed-publication-unknown-',
  ));
  t.after(() => rm(
    completedUnknownDirectory, {recursive: true, force: true},
  ));
  let completedUnknownIndexSyncFailures = 3;
  const completedUnknownDurability = Object.freeze({
    async syncDirectory(path) {
      if (path === join(completedUnknownDirectory, 'indexes') &&
          completedUnknownIndexSyncFailures > 0) {
        completedUnknownIndexSyncFailures--;
        const error = new Error('injected index directory sync failure');
        error.code = 'EIO';
        throw error;
      }
      const handle = await open(path, 'r');
      try { await handle.sync(); }
      finally { await handle.close(); }
    },
  });
  const completedUnknownStore = await openLocalPublicationStore({
    directory: completedUnknownDirectory,
    storeAuthorityCid: cid('a'),
    capacityBytes: 4 * 1024 * 1024,
    maxObjectBytes: limits.maxWireBytes,
    maxObjects: 100,
    maxContractNodes: limits.maxNodes,
    maxContractDepth: limits.maxDepth,
  }, control, completedUnknownDurability);
  await completedUnknownStore.putSemantic(resultSchemaWire, resultSchemaCid);
  const completedUnknownWriter =
    completedUnknownStore.createPreparedObjectWriter(payloadBytes);
  await completedUnknownWriter.append(payloadWire);
  const completedUnknownPayload =
    await completedUnknownWriter.seal(physicalCid);
  let completedUnknownExports = 0;
  const completedUnknownExecution = Object.freeze({
    ...execution,
    async storePublicationResult(index, target, supplied) {
      completedUnknownExports++;
      assert.equal(index, 0);
      assert.equal(target, completedUnknownStore);
      assert.equal(supplied.runDefinition, run);
      assert.equal(supplied.invocation, invoked);
      return Object.freeze({
        occurrence: Object.freeze({
          name: 'answer', task: 1, definition,
        }),
        physical: Object.freeze({cid: physicalCid, bytes: payloadBytes}),
        orderedRows: Object.freeze({rows: 1}),
        publication: Object.freeze({
          derivation,
          ordering,
          artifact,
          snapshot,
          durableBinding: binding,
        }),
        prepared: completedUnknownPayload.prepared,
      });
    },
  });
  let completedUnknownFailure;
  await assert.rejects(publishCompletedEffectFreeRun({
    ...completedPublicationOptions,
    execution: completedUnknownExecution,
    store: completedUnknownStore,
    attempt: {
      ...completedPublicationOptions.attempt,
      attemptId: 'unknown-completed-attempt',
    },
  }), error => {
    completedUnknownFailure = error;
    return error?.code === 'RunPublicationUnknown' &&
      error.cleanupHandle?.status().pending === true;
  });
  assert.equal(completedUnknownExports, 1);
  assert.equal(completedUnknownPayload.prepared.status().pending, true);
  assert.equal((await completedUnknownStore.verifyObject(physicalCid)).bytes,
    payloadBytes);
  const reconciledCompletedUnknown =
    await completedUnknownFailure.cleanupHandle.retry();
  assert.equal(reconciledCompletedUnknown.pending, false);
  assert.equal(reconciledCompletedUnknown.outcome, 'committed');
  assert.equal(completedUnknownPayload.prepared.status().pending, false);
  assert.equal(completedUnknownExports, 1);
  assert.equal(
    completedUnknownFailure.primaryFailure.publicationResult.state,
    'succeeded',
  );
  assert.equal(await completedUnknownStore.close(), true);

  await store.close();
  const deliveryStore = await openLocalPublicationStore({
    directory,
    storeAuthorityCid: cid('a'),
    capacityBytes: 4 * 1024 * 1024,
    maxObjectBytes: limits.maxWireBytes,
    maxObjects: 100,
    maxContractNodes: limits.maxNodes,
    maxContractDepth: limits.maxDepth,
  }, control);
  t.after(async () => { await deliveryStore.close(); });
  const deliveryIndexValue = await deliveryStore.confirmCommittedIndex({
    namespaceId: 'namespace-a',
    authorityScopeCid: cid('d'),
    runDefinitionCid: run.identity,
  });
  const deliveryIndex = await deliveryStore.readPublicationContract(
    deliveryIndexValue.public_index_entry_cid,
    'public_index_entry',
  );
  const deliveryManifest = await deliveryStore.readPublicationContract(
    deliveryIndexValue.result_manifest_cid,
    'result_manifest',
  );
  const deliveryGrant = control.issueResultReadGrant(
    deliveryIndex,
    deliveryManifest,
    {
      resultNames: ['answer'],
      formats: ['json', 'jsonl', 'csv'],
      principalId: 'principal-a',
      purpose: 'download',
      dataCeilingCid: cid('1'),
      maxBytes: 1024,
      maxUses: 4,
      expiresAt: '2026-09-19T00:00:00.000Z',
      authorizationContextCid: cid('2'),
      egressAdmissionCid: cid('3'),
    },
    limits,
  );
  const createDigest = () => {
    const hash = createHash('sha256');
    return Object.freeze({
      update: bytes => hash.update(bytes),
      finish: () => hash.digest('hex'),
    });
  };
  let requestAccessAllowed = true;
  let accessAllowed = true;
  let advanceAccessTimeAt;
  let readRequestGate;
  let accessTime = '2026-09-18T01:00:00.000Z';
  const accessChecks = [];
  const accessAuthority = installResultAccessAuthority({
    async authorizeResultReadRequest(facts) {
      accessChecks.push(`authorize:request:${facts.resultName}`);
      if (readRequestGate !== undefined) {
        readRequestGate.started();
        await readRequestGate.wait;
      }
      return requestAccessAllowed;
    },
    async authorizeDeliveryAttemptLookup(facts) {
      accessChecks.push(`authorize:attempt:${facts.resultName}`);
      return accessAllowed;
    },
    async admitResultRead(facts) {
      accessChecks.push(`admit:${facts.resultName}:${facts.format}`);
      return {
        authorizationContextCid: cid('2'),
        dataCeilingCid: cid('1'),
        egressAdmissionCid: cid('3'),
        expiresAt: '2026-09-19T00:00:00.000Z',
        maxBytes: 1024,
        maxUses: 3,
      };
    },
    async authorizeResultRead(facts) {
      accessChecks.push(`authorize:${facts.delivery.stage}`);
      if (advanceAccessTimeAt !== undefined &&
          facts.delivery.stage === 'write') {
        await Promise.resolve();
        accessTime = advanceAccessTimeAt;
      }
      return accessAllowed;
    },
  });
  const accessService = installNodeResultAccessService({
    store: deliveryStore,
    control,
    authority: accessAuthority,
    now: () => accessTime,
    limits,
    frameLimits: {
      maxRowBytes: 4096,
      maxDepth: 32,
      maxFrameBytes: 4096,
    },
  });
  let stateAccessAllowed = true;
  let resultPolicyAvailable = true;
  const stateAuthority = installRunStateAuthority({
    authorizeRunState: () => stateAccessAllowed,
    resultPolicyAvailable: () => resultPolicyAvailable,
  });
  const stateService = installRunStateService({
    store: deliveryStore,
    control,
    authority: stateAuthority,
    now: () => accessTime,
    limits,
  });
  let manifestAccessAllowed = true;
  const manifestAuthority = installManifestAccessAuthority({
    authorizeManifestRead: () => manifestAccessAllowed,
    admitManifestRead: () => ({
      authorizationContextCid: cid('2'),
      clockContractCid: cid('d'),
      dataCeilingCid: cid('1'),
      expiresAt: '2026-09-19T00:00:00.000Z',
      maxBytes: limits.maxWireBytes,
      maxUses: 1,
    }),
  });
  const manifestService = installManifestAccessService({
    store: deliveryStore,
    control,
    authority: manifestAuthority,
    now: () => accessTime,
    limits,
  });
  const stateRequest = {
    indexKey: {
      namespaceId: 'namespace-a',
      authorityScopeCid: cid('d'),
      runDefinitionCid: run.identity,
    },
    principalId: 'principal-a',
    purpose: 'inspect',
  };
  const availableState = await inspectAuthorizedRunState(
    stateService, stateRequest,
  );
  assert.equal(availableState.status, 'succeeded');
  assert.equal(availableState.result_available, true);
  assert.deepEqual(availableState.next_action, {
    kind: 'read_result', results: ['answer'],
  });
  assert.deepEqual(availableState.result_availability.answer, {
    observed_at: accessTime,
    reason: 'confirmed_present',
    state: 'available',
  });
  const contradictoryStateService = installRunStateService({
    store: Object.freeze({
      ...deliveryStore,
      latestRecordContract: () => deliveryStore.readPublicationContract(
        deliveryIndexValue.public_index_entry_cid, 'public_index_entry'),
    }),
    control,
    authority: stateAuthority,
    now: () => accessTime,
    limits,
  });
  await assert.rejects(
    inspectAuthorizedRunState(contradictoryStateService, stateRequest),
    {code: 'InvalidCommittedPublicationState'},
  );
  const clientHost = createServer(createClientHttpHandler({
    authenticate: authorization => authorization === 'Bearer scoped-token'
      ? 'principal-a' : undefined,
    authorizeConnection: facts => facts.connection.mode === 'local' &&
      facts.connection.owner === 'local' &&
      (facts.ref === undefined || facts.ref.namespaceId === 'namespace-a'),
    negotiate: () => ({
      version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
      durability: 'durable', scopeRef: 'principal-a',
      capabilities: ['result-jsonl'],
      limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024,
        maxRowRetainedValueBytes: 1024,
        maxRetainedValueBytes: 4096, maxRows: 100,
        maxBatchRows: 10, maxBatchRetainedValueBytes: 2048},
    }),
    attach: async ({ref, principalId}) => {
      await inspectAuthorizedRunState(stateService, {
        indexKey: ref, principalId, purpose: 'inspect',
      });
      return {ref, durability: 'durable', revision: 0};
    },
    stateService,
    resultService: accessService,
  }));
  await new Promise(resolve => clientHost.listen(0, '127.0.0.1', resolve));
  try {
    const base = `http://127.0.0.1:${clientHost.address().port}`;
    const headers = {authorization: 'Bearer scoped-token',
      'content-type': 'application/json'};
    const connection = {mode: 'local', owner: 'local',
      runners: [], consentRefs: []};
    const statusReply = await fetch(`${base}/actql/client/0.1/status`, {
      method: 'POST', headers,
      body: JSON.stringify({connection, ref: stateRequest.indexKey}),
    });
    assert.equal(statusReply.status, 200);
    assert.deepEqual(await statusReply.json(), availableState);
    const readReply = await fetch(`${base}/actql/client/0.1/read`, {
      method: 'POST', headers,
      body: JSON.stringify({connection, ref: stateRequest.indexKey,
        resultName: 'answer', format: 'json', attemptId: 'http-result-read'}),
    });
    assert.equal(readReply.status, 200);
    assert.equal(await readReply.text(), '[{"value":7}]');
    const streamReply = await fetch(`${base}/actql/client/0.1/read`, {
      method: 'POST', headers,
      body: JSON.stringify({connection, ref: stateRequest.indexKey,
        resultName: 'answer', format: 'jsonl',
        attemptId: 'http-result-stream'}),
    });
    assert.equal(streamReply.status, 200);
    assert.equal(await streamReply.text(), '{"value":7}\n\x1e');
    const client = await connectClient({mode: 'local', owner: 'local',
      endpoint: `${base}/`, token: 'scoped-token'});
    const attached = await client.attach(stateRequest.indexKey);
    assert.deepEqual(await attached.status(), availableState);
    const reader = attached.result('answer').rows();
    assert.deepEqual(await Array.fromAsync(reader), [{value: 7}]);
    assert.equal(reader.state(), 'complete');
    assert.equal((await attached.result('answer')
      .deliveryAttempt(reader.attemptId)).kind, 'found');
    const inspectAttempt = async attemptId => fetch(
      `${base}/actql/client/0.1/delivery-attempt`, {
        method: 'POST', headers,
        body: JSON.stringify({connection, ref: stateRequest.indexKey,
          resultName: 'answer', attemptId}),
      });
    const attemptReply = await inspectAttempt('http-result-stream');
    assert.equal(attemptReply.status, 200);
    let attemptStatus = await attemptReply.json();
    assert.equal(attemptStatus.kind, 'found');
    assert.equal(attemptStatus.attempt.attempt_id, 'http-result-stream');
    for (let tries = 0; tries < 100 &&
        attemptStatus.record?.state !== 'succeeded'; tries++) {
      await new Promise(resolve => setTimeout(resolve, 10));
      attemptStatus = await (await inspectAttempt('http-result-stream')).json();
    }
    assert.equal(attemptStatus.record.state, 'succeeded');
    assert.equal(attemptStatus.hostReleaseReceipt.delivered_byte_count,
      Buffer.byteLength('{"value":7}\n'));
    assert.deepEqual(await (await inspectAttempt('missing')).json(),
      {kind: 'not_found'});
    accessAllowed = false;
    const deniedAttempt = await inspectAttempt('http-result-stream');
    const deniedMissing = await inspectAttempt('missing');
    assert.equal(deniedAttempt.status, 403);
    assert.equal(deniedMissing.status, 403);
    accessAllowed = true;
  } finally {
    await new Promise(resolve => clientHost.close(resolve));
  }
  const uncertainStateService = installRunStateService({
    store: Object.freeze({
      confirmCommittedIndex: key =>
        deliveryStore.confirmCommittedIndex(key),
      readPublicationContract: (identity, name) =>
        deliveryStore.readPublicationContract(identity, name),
      latestRecordContract: identity =>
        deliveryStore.latestRecordContract(identity),
      observeTrustedClock: (identity, at) =>
        deliveryStore.observeTrustedClock(identity, at),
      readCommittedResultRetentionExtension: (key, definition) =>
        deliveryStore.readCommittedResultRetentionExtension(key, definition),
      withCommittedResult: async () => {
        throw new Error('temporary Store query failure');
      },
    }),
    control,
    authority: stateAuthority,
    now: () => accessTime,
    limits,
  });
  const uncertainState = await inspectAuthorizedRunState(
    uncertainStateService, stateRequest,
  );
  assert.equal(uncertainState.result_available, false);
  assert.deepEqual(uncertainState.next_action, {
    kind: 'refresh_availability', results: ['answer'],
  });
  assert.equal(
    uncertainState.result_availability.answer.reason,
    'store_query_failed',
  );
  resultPolicyAvailable = false;
  const policyState = await inspectAuthorizedRunState(
    stateService, stateRequest,
  );
  assert.equal(policyState.result_available, false);
  assert.deepEqual(policyState.next_action, {kind: 'none'});
  assert.equal(
    policyState.result_availability.answer.reason,
    'policy_unavailable',
  );
  resultPolicyAvailable = true;
  stateAccessAllowed = false;
  await assert.rejects(
    inspectAuthorizedRunState(stateService, stateRequest),
    {code: 'RunStateAccessDenied'},
  );
  stateAccessAllowed = true;
  const manifestRequest = {
    indexKey: stateRequest.indexKey,
    principalId: 'principal-a',
    purpose: 'inspect',
    attemptId: 'manifest-read-a',
  };
  const manifestResponse = await readAuthorizedManifest(
    manifestService, manifestRequest,
  );
  assert.equal(manifestResponse.manifestCid, manifest.identity);
  assert.equal(manifestResponse.manifest.results.answer.result_artifact_cid,
    artifact.identity);
  assert.equal(manifestResponse.idempotent, false);
  assert.equal((await readAuthorizedManifest(
    manifestService, manifestRequest,
  )).idempotent, true);
  await assert.rejects(readAuthorizedManifest(manifestService, {
    ...manifestRequest,
    attemptId: 'manifest-read-b',
  }), {code: 'ManifestReadGrantUseLimit'});
  manifestAccessAllowed = false;
  await assert.rejects(
    readAuthorizedManifest(manifestService, manifestRequest),
    {code: 'ManifestAccessDenied'},
  );
  manifestAccessAllowed = true;
  const authorizedChunks = [];
  requestAccessAllowed = false;
  for (const deniedRequest of [
    {
      ...stateRequest,
      purpose: 'download',
      resultName: 'answer',
      format: 'json',
      attemptId: 'denied-existing',
    },
    {
      ...stateRequest,
      indexKey: {...stateRequest.indexKey, runDefinitionCid: cid('0')},
      purpose: 'download',
      resultName: 'answer',
      format: 'json',
      attemptId: 'denied-missing-index',
    },
    {
      ...stateRequest,
      purpose: 'download',
      resultName: 'missing-result',
      format: 'json',
      attemptId: 'denied-missing-result',
    },
  ]) {
    await assert.rejects(deliverAuthorizedResult(
      accessService,
      deniedRequest,
      {
        write: () => assert.fail('denied request exposed bytes'),
        finish: () => assert.fail('denied request completed delivery'),
      },
    ), error => error?.code === 'ResultAccessDenied' &&
      error.cause === undefined && error.primaryFailure === undefined);
  }
  requestAccessAllowed = true;
  const authorizedDelivery = await deliverAuthorizedResult(
    accessService,
    {
      indexKey: {
        namespaceId: 'namespace-a',
        authorityScopeCid: cid('d'),
        runDefinitionCid: run.identity,
      },
      principalId: 'principal-a',
      purpose: 'download',
      resultName: 'answer',
      format: 'json',
      attemptId: 'authorized-json',
    },
    {
      async write(bytes) {
        authorizedChunks.push(Buffer.from(bytes));
        return {confirmedBytes: bytes.byteLength};
      },
      async finish() { return {confirmed: true}; },
    },
  );
  assert.equal(Buffer.concat(authorizedChunks).toString('utf8'),
    '[{"value":7}]');
  assert.equal(authorizedDelivery.idempotent, false);
  assert.ok(accessChecks.includes('authorize:request:answer'));
  assert.ok(accessChecks.includes('authorize:read'));
  assert.ok(accessChecks.includes('authorize:write'));
  assert.ok(accessChecks.includes('authorize:receipt'));
  let releaseReadRequest;
  let readAuthorizationStarted;
  const readStarted = new Promise(resolve => {
    readAuthorizationStarted = resolve;
  });
  const readWait = new Promise(resolve => { releaseReadRequest = resolve; });
  readRequestGate = {started: readAuthorizationStarted, wait: readWait};
  const changedReadRequest = {
    indexKey: {namespaceId: 'namespace-a', authorityScopeCid: cid('d'),
      runDefinitionCid: run.identity},
    principalId: 'principal-a', purpose: 'download', resultName: 'answer',
    format: 'json', attemptId: 'snapshot-json',
  };
  const snapshottedChunks = [];
  const pendingRead = deliverAuthorizedResult(
    accessService, changedReadRequest, {
      async write(bytes) {
        snapshottedChunks.push(Buffer.from(bytes));
        return {confirmedBytes: bytes.byteLength};
      },
      async finish() { return {confirmed: true}; },
    },
  );
  await readStarted;
  changedReadRequest.resultName = 'missing-result';
  changedReadRequest.format = 'csv';
  changedReadRequest.attemptId = 'foreign-attempt';
  changedReadRequest.indexKey.namespaceId = 'namespace-b';
  changedReadRequest.indexKey.runDefinitionCid = cid('0');
  releaseReadRequest();
  readRequestGate = undefined;
  const snapshottedDelivery = await pendingRead;
  assert.equal(snapshottedDelivery.idempotent, false);
  assert.equal(Buffer.concat(snapshottedChunks).toString('utf8'),
    '[{"value":7}]');
  accessAllowed = false;
  await assert.rejects(deliverAuthorizedResult(
    accessService,
    {
      indexKey: {
        namespaceId: 'namespace-a',
        authorityScopeCid: cid('d'),
        runDefinitionCid: run.identity,
      },
      principalId: 'principal-a',
      purpose: 'download',
      resultName: 'answer',
      format: 'json',
      attemptId: 'authorized-revoked',
    },
    {
      write: () => assert.fail('revoked access exposed bytes'),
      finish: () => assert.fail('revoked access finished delivery'),
    },
  ), {code: 'ResultDeliveryDenied'});
  accessAllowed = true;
  accessTime = '2026-09-18T01:00:00.001Z';
  requestAccessAllowed = false;
  await assert.rejects(deliverAuthorizedResult(
    accessService,
    {
      indexKey: stateRequest.indexKey,
      principalId: 'principal-a',
      purpose: 'download',
      resultName: 'answer',
      format: 'json',
      attemptId: 'denied-expired',
    },
    {
      write: () => assert.fail('denied expired Result exposed bytes'),
      finish: () => assert.fail('denied expired Result finished delivery'),
    },
  ), {code: 'ResultAccessDenied'});
  requestAccessAllowed = true;
  await assert.rejects(deliverAuthorizedResult(
    accessService,
    {
      indexKey: {
        namespaceId: 'namespace-a',
        authorityScopeCid: cid('d'),
        runDefinitionCid: run.identity,
      },
      principalId: 'principal-a',
      purpose: 'download',
      resultName: 'answer',
      format: 'json',
      attemptId: 'authorized-expired',
    },
    {
      write: () => assert.fail('expired Result exposed bytes'),
      finish: () => assert.fail('expired Result finished delivery'),
    },
  ), {code: 'ResultUnavailable'});
  const expiredState = await inspectAuthorizedRunState(
    stateService, stateRequest,
  );
  assert.equal(expiredState.result_available, false);
  assert.deepEqual(expiredState.next_action, {kind: 'none'});
  assert.equal(
    expiredState.result_availability.answer.reason,
    'retention_expired',
  );
  accessTime = '2026-09-18T01:00:00.000Z';
  const deliveryBase = {
    store: deliveryStore,
    control,
    indexKey: {
      namespaceId: 'namespace-a',
      authorityScopeCid: cid('d'),
      runDefinitionCid: run.identity,
    },
    grant: deliveryGrant,
    resultName: 'answer',
    limits,
    frameLimits: {
      maxRowBytes: 4096,
      maxDepth: 32,
      maxFrameBytes: 4096,
    },
    now: () => '2026-09-18T01:00:00.000Z',
    createDigest,
    authorize: () => true,
    signal: undefined,
  };
  const expiringGrant = control.issueResultReadGrant(
    deliveryIndex,
    deliveryManifest,
    {
      resultNames: ['answer'],
      formats: ['json'],
      principalId: 'principal-a',
      purpose: 'expiring-download',
      dataCeilingCid: cid('1'),
      maxBytes: 1024,
      maxUses: 1,
      expiresAt: '2026-09-18T01:00:00.000Z',
      authorizationContextCid: cid('2'),
      egressAdmissionCid: cid('3'),
    },
    limits,
  );
  let expiringTime = '2026-09-18T00:59:59.999Z';
  let expiredSinkWrites = 0;
  await assert.rejects(deliverPublishedResult({
    ...deliveryBase,
    grant: expiringGrant,
    format: 'json',
    attemptId: 'delivery-expired-during-authorization',
    now: () => expiringTime,
    async authorize(facts) {
      if (facts.stage === 'write') {
        await Promise.resolve();
        expiringTime = '2026-09-18T01:00:00.001Z';
      }
      return true;
    },
    sink: {
      async write(bytes) {
        expiredSinkWrites++;
        return {confirmedBytes: bytes.byteLength};
      },
      async finish() { return {confirmed: true}; },
    },
  }), {code: 'ResultDeliveryGrantExpired'});
  assert.equal(expiredSinkWrites, 0);

  const cancelledGrant = control.issueResultReadGrant(
    deliveryIndex,
    deliveryManifest,
    {
      resultNames: ['answer'],
      formats: ['json'],
      principalId: 'principal-a',
      purpose: 'cancelled-download',
      dataCeilingCid: cid('1'),
      maxBytes: 1024,
      maxUses: 1,
      expiresAt: '2026-09-19T00:00:00.000Z',
      authorizationContextCid: cid('2'),
      egressAdmissionCid: cid('3'),
    },
    limits,
  );
  const cancelledController = new AbortController();
  let cancelledSinkWrites = 0;
  await assert.rejects(deliverPublishedResult({
    ...deliveryBase,
    grant: cancelledGrant,
    format: 'json',
    attemptId: 'delivery-cancelled-during-authorization',
    signal: cancelledController.signal,
    async authorize(facts) {
      if (facts.stage === 'write') {
        await Promise.resolve();
        cancelledController.abort(new Error('authorization cancelled'));
      }
      return true;
    },
    sink: {
      async write(bytes) {
        cancelledSinkWrites++;
        return {confirmedBytes: bytes.byteLength};
      },
      async finish() { return {confirmed: true}; },
    },
  }), error => error?.message === 'authorization cancelled');
  assert.equal(cancelledSinkWrites, 0);
  const expectedDelivery = Object.freeze({
    json: '[{"value":7}]',
    jsonl: '{"value":7}\n',
    csv: '"value"\n7\n',
  });
  for (const format of ['json', 'jsonl', 'csv']) {
    const chunks = [];
    const delivered = await deliverPublishedResult({
      ...deliveryBase,
      format,
      attemptId: `delivery-${format}`,
      createDigest: format === 'jsonl' ? () => {
        const digest = createDigest();
        return {update: bytes => digest.update(bytes),
          finish: async () => digest.finish()};
      } : createDigest,
      sink: {
        async write(bytes) {
          chunks.push(Buffer.from(bytes));
          return {confirmedBytes: bytes.byteLength};
        },
        async finish() { return {confirmed: true}; },
      },
    });
    const deliveryBytes = Buffer.concat(chunks);
    assert.equal(deliveryBytes.toString('utf8'), expectedDelivery[format]);
    assert.equal(delivered.byteCount, deliveryBytes.byteLength);
    assert.equal(
      delivered.sha256,
      createHash('sha256').update(deliveryBytes).digest('hex'),
    );
  }
  const emptyGrant = control.issueResultReadGrant(
    deliveryIndex,
    deliveryManifest,
    {
      resultNames: ['answer'],
      formats: ['jsonl'],
      principalId: 'principal-a',
      purpose: 'empty-download',
      dataCeilingCid: cid('1'),
      maxBytes: 1024,
      maxUses: 3,
      expiresAt: '2026-09-19T00:00:00.000Z',
      authorizationContextCid: cid('2'),
      egressAdmissionCid: cid('3'),
    },
    limits,
  );
  const emptyStore = Object.freeze({
    ...deliveryStore,
    withCommittedResultRows(
      indexKey,
      resultDefinitionCid,
      authorize,
      suppliedFrameLimits,
      use,
      frameControl,
    ) {
      return deliveryStore.withCommittedResultRows(
        indexKey,
        resultDefinitionCid,
        authorize,
        suppliedFrameLimits,
        (metadata, _readRows) => use(
          Object.freeze({...metadata, rowCount: 0}),
          async _emit => undefined,
        ),
        frameControl,
      );
    },
  });
  let emptyFinishes = 0;
  const emptyDelivery = await deliverPublishedResult({
    ...deliveryBase,
    store: emptyStore,
    grant: emptyGrant,
    format: 'jsonl',
    attemptId: 'delivery-empty-jsonl',
    sink: {
      write: () => assert.fail('empty JSONL wrote bytes'),
      async finish() {
        emptyFinishes++;
        return {confirmed: true};
      },
    },
  });
  assert.equal(emptyFinishes, 1);
  assert.equal(emptyDelivery.byteCount, 0);
  assert.equal(
    emptyDelivery.sha256,
    createHash('sha256').update('').digest('hex'),
  );
  await assert.rejects(deliverPublishedResult({
    ...deliveryBase,
    store: emptyStore,
    grant: emptyGrant,
    format: 'jsonl',
    attemptId: 'delivery-empty-finish-failed',
    sink: {
      write: () => assert.fail('empty JSONL wrote bytes'),
      finish: () => Promise.reject(new Error('sink finish failed')),
    },
  }), {code: 'ResultDeliverySinkCompletionFailed'});
  await assert.rejects(deliverPublishedResult({
    ...deliveryBase,
    store: emptyStore,
    grant: emptyGrant,
    format: 'jsonl',
    attemptId: 'delivery-empty-finish-unknown',
    sink: {
      write: () => assert.fail('empty JSONL wrote bytes'),
      finish: () => ({confirmed: false}),
    },
  }), {code: 'ResultDeliverySinkCompletionUnknown'});
  for (const attemptId of [
    'delivery-empty-finish-failed',
    'delivery-empty-finish-unknown',
  ]) {
    const attempt = control.issueDeliveryAttempt(
      deliveryIndex,
      deliveryManifest,
      emptyGrant,
      {
        resultName: 'answer',
        format: 'jsonl',
        attemptId,
        requestedAt: '2026-09-18T01:00:00.000Z',
      },
      limits,
    );
    const record = await deliveryStore.latestDeliveryRecord(
      attempt.identity,
    );
    assert.equal(record.state, 'failed');
    assert.equal(record.result_delivery_receipt_cid, undefined);
  }
  const idempotentDelivery = await deliverPublishedResult({
    ...deliveryBase,
    format: 'json',
    attemptId: 'delivery-json',
    sink: {
      write: () => assert.fail('idempotent delivery wrote bytes'),
      finish: () => assert.fail('idempotent delivery finished sink'),
    },
  });
  assert.equal(idempotentDelivery.idempotent, true);

  let sinkWrites = 0;
  await assert.rejects(deliverPublishedResult({
    ...deliveryBase,
    format: 'json',
    attemptId: 'delivery-partial',
    sink: {
      async write(bytes) {
        sinkWrites++;
        if (sinkWrites === 1) {
          return {confirmedBytes: bytes.byteLength};
        }
        const failure = new Error('partial sink failure');
        failure.deliveryProgress = {
          confirmedBytes: 1,
          exposure: 'unknown_additional',
          possibleUnconfirmedMaxBytes: bytes.byteLength - 1,
        };
        throw failure;
      },
      async finish() { return {confirmed: true}; },
    },
  }), /ResultDeliverySinkWriteFailed/u);
  const partialAttempt = control.issueDeliveryAttempt(
    deliveryIndex,
    deliveryManifest,
    deliveryGrant,
    {
      resultName: 'answer',
      format: 'json',
      attemptId: 'delivery-partial',
      requestedAt: '2026-09-18T01:00:00.000Z',
    },
    limits,
  );
  const partialRecord = await deliveryStore.latestDeliveryRecord(
    partialAttempt.identity,
  );
  assert.equal(partialRecord.state, 'failed');
  assert.equal(partialRecord.exposure, 'unknown_additional');
  assert.ok(partialRecord.confirmed_byte_count > 1);

  const revocationGrant = control.issueResultReadGrant(
    deliveryIndex,
    deliveryManifest,
    {
      resultNames: ['answer'],
      formats: ['json'],
      principalId: 'principal-a',
      purpose: 'revocation-check',
      dataCeilingCid: cid('1'),
      maxBytes: 1024,
      maxUses: 1,
      expiresAt: '2026-09-19T00:00:00.000Z',
      authorizationContextCid: cid('2'),
      egressAdmissionCid: cid('3'),
    },
    limits,
  );
  let authorizedWrites = 0;
  let exposedWrites = 0;
  await assert.rejects(deliverPublishedResult({
    ...deliveryBase,
    grant: revocationGrant,
    format: 'json',
    attemptId: 'delivery-revoked',
    authorize(facts) {
      return facts.stage !== 'write' || ++authorizedWrites === 1;
    },
    sink: {
      async write(bytes) {
        exposedWrites++;
        return {confirmedBytes: bytes.byteLength};
      },
      async finish() { return {confirmed: true}; },
    },
  }), {code: 'ResultDeliveryDenied'});
  assert.equal(exposedWrites, 1);
  const revokedAttempt = control.issueDeliveryAttempt(
    deliveryIndex,
    deliveryManifest,
    revocationGrant,
    {
      resultName: 'answer',
      format: 'json',
      attemptId: 'delivery-revoked',
      requestedAt: '2026-09-18T01:00:00.000Z',
    },
    limits,
  );
  assert.equal((await deliveryStore.latestDeliveryRecord(
    revokedAttempt.identity,
  )).state, 'failed');

  await assert.rejects(deliverPublishedResult({
    ...deliveryBase,
    format: 'json',
    attemptId: 'delivery-over-limit',
    sink: {
      write: () => assert.fail('exhausted grant wrote bytes'),
      finish: () => assert.fail('exhausted grant finished delivery'),
    },
  }), {code: 'DeliveryGrantUseLimit'});

  const recoveryGrant = control.issueResultReadGrant(
    deliveryIndex,
    deliveryManifest,
    {
      resultNames: ['answer'],
      formats: ['json'],
      principalId: 'principal-a',
      purpose: 'cleanup-recovery',
      dataCeilingCid: cid('1'),
      maxBytes: 1024,
      maxUses: 1,
      expiresAt: '2026-09-19T00:00:00.000Z',
      authorizationContextCid: cid('2'),
      egressAdmissionCid: cid('3'),
    },
    limits,
  );
  let failTerminalRecord = true;
  const recoveryStore = Object.freeze({
    ...deliveryStore,
    async appendDeliveryRecord(recordWire) {
      if (failTerminalRecord &&
          JSON.parse(recordWire).state === 'failed') {
        failTerminalRecord = false;
        const error = new Error('injected terminal record failure');
        error.code = 'EIO';
        throw error;
      }
      return deliveryStore.appendDeliveryRecord(recordWire);
    },
  });
  let recoveryFailure;
  try {
    await deliverPublishedResult({
      ...deliveryBase,
      store: recoveryStore,
      grant: recoveryGrant,
      format: 'json',
      attemptId: 'delivery-cleanup-retry',
      sink: {
        write: () => Promise.reject(new Error('sink unavailable')),
        finish: () => assert.fail('failed delivery finished sink'),
      },
    });
    assert.fail('delivery unexpectedly succeeded');
  } catch (error) {
    recoveryFailure = error;
  }
  assert.equal(recoveryFailure.code, 'ResultDeliveryFailed');
  assert.equal(recoveryFailure.cleanupPending, true);
  assert.equal((await recoveryFailure.cleanupHandle.retry()).pending, false);
  const recoveryAttempt = control.issueDeliveryAttempt(
    deliveryIndex,
    deliveryManifest,
    recoveryGrant,
    {
      resultName: 'answer',
      format: 'json',
      attemptId: 'delivery-cleanup-retry',
      requestedAt: '2026-09-18T01:00:00.000Z',
    },
    limits,
  );
  assert.equal((await deliveryStore.latestDeliveryRecord(
    recoveryAttempt.identity,
  )).state, 'failed');

  const durabilityGrant = control.issueResultReadGrant(
    deliveryIndex,
    deliveryManifest,
    {
      resultNames: ['answer'],
      formats: ['json'],
      principalId: 'principal-a',
      purpose: 'durability-recovery',
      dataCeilingCid: cid('1'),
      maxBytes: 1024,
      maxUses: 1,
      expiresAt: '2026-09-19T00:00:00.000Z',
      authorizationContextCid: cid('2'),
      egressAdmissionCid: cid('3'),
    },
    limits,
  );
  let failSucceededDurability = true;
  const durabilityStore = Object.freeze({
    ...deliveryStore,
    async appendDeliveryRecord(recordWire) {
      const result = await deliveryStore.appendDeliveryRecord(recordWire);
      if (failSucceededDurability &&
          JSON.parse(recordWire).state === 'succeeded') {
        failSucceededDurability = false;
        const error = new Error('injected delivery record sync failure');
        error.code = 'EIO';
        throw error;
      }
      return result;
    },
  });
  let durabilityWrites = 0;
  let durabilityFinishes = 0;
  let durabilityFailure;
  try {
    await deliverPublishedResult({
      ...deliveryBase,
      store: durabilityStore,
      grant: durabilityGrant,
      format: 'json',
      attemptId: 'delivery-durability-retry',
      sink: {
        async write(bytes) {
          durabilityWrites++;
          return {confirmedBytes: bytes.byteLength};
        },
        async finish() {
          durabilityFinishes++;
          return {confirmed: true};
        },
      },
    });
    assert.fail('delivery durability failure was accepted');
  } catch (error) {
    durabilityFailure = error;
  }
  assert.equal(
    durabilityFailure.code,
    'ResultDeliveryDurabilityPending',
  );
  assert.equal(durabilityFailure.cleanupPending, true);
  assert.equal(durabilityWrites > 0, true);
  assert.equal(durabilityFinishes, 1);
  assert.equal(
    (await durabilityFailure.cleanupHandle.retry()).pending,
    false,
  );
  const durabilityRetry = await deliverPublishedResult({
    ...deliveryBase,
    store: durabilityStore,
    grant: durabilityGrant,
    format: 'json',
    attemptId: 'delivery-durability-retry',
    sink: {
      write: () => assert.fail('durability retry repeated delivery'),
      finish: () => assert.fail('durability retry repeated completion'),
    },
  });
  assert.equal(durabilityRetry.idempotent, true);
  assert.equal(durabilityFinishes, 1);

  accessTime = '2026-09-18T01:30:00.000Z';
  const expiredBeforeExtension = await inspectAuthorizedRunState(
    stateService, stateRequest,
  );
  assert.equal(expiredBeforeExtension.result_available, false);
  assert.equal(
    expiredBeforeExtension.result_availability.answer.reason,
    'retention_expired',
  );
  const deniedExtensionService = installResultRetentionExtensionService({
    store: deliveryStore,
    control,
    authority: installResultRetentionExtensionAuthority({
      authorizeResultExtension: () => false,
    }),
    now: () => accessTime,
    limits,
  });
  await assert.rejects(extendResultRetention(deniedExtensionService, {
    indexKey: stateRequest.indexKey,
    resultName: 'answer',
    availableUntil: '2026-09-18T01:45:00.000Z',
    reason: 'authorized_download',
  }), {code: 'ResultRetentionExtensionDenied'});
  const extensionStages = [];
  const extensionService = installResultRetentionExtensionService({
    store: deliveryStore,
    control,
    authority: installResultRetentionExtensionAuthority({
      authorizeResultExtension(facts) {
        extensionStages.push(facts.stage);
        return true;
      },
    }),
    now: () => accessTime,
    limits,
  });
  await assert.rejects(extendResultRetention(extensionService, {
    indexKey: stateRequest.indexKey,
    resultName: 'answer',
    availableUntil: '2026-09-18T02:00:00.001Z',
    reason: 'forbidden_extension',
  }), {code: 'ResultRetentionExtensionNotAllowed'});
  const extended = await extendResultRetention(extensionService, {
    indexKey: stateRequest.indexKey,
    resultName: 'answer',
    availableUntil: '2026-09-18T01:45:00.000Z',
    reason: 'authorized_download',
  });
  assert.equal(extended.idempotent, false);
  assert.deepEqual(extensionStages, ['request', 'request', 'extend']);
  const extensionRetry = await extendResultRetention(extensionService, {
    indexKey: stateRequest.indexKey,
    resultName: 'answer',
    availableUntil: '2026-09-18T01:45:00.000Z',
    reason: 'authorized_download',
  });
  assert.equal(extensionRetry.idempotent, true);
  const availableAfterExtension = await inspectAuthorizedRunState(
    stateService, stateRequest,
  );
  assert.equal(availableAfterExtension.result_available, true);
  assert.equal(
    availableAfterExtension.result_availability.answer.reason,
    'confirmed_present',
  );
  const extendedBytes = [];
  const extendedDelivery = await deliverAuthorizedResult(
    accessService,
    {
      indexKey: stateRequest.indexKey,
      principalId: 'principal-a',
      purpose: 'extended-download',
      resultName: 'answer',
      format: 'json',
      attemptId: 'authorized-after-extension',
    },
    {
      write(bytes) {
        extendedBytes.push(Buffer.from(bytes));
        return {confirmedBytes: bytes.byteLength};
      },
      finish() { return {confirmed: true}; },
    },
  );
  assert.equal(extendedDelivery.idempotent, false);
  assert.ok(Buffer.concat(extendedBytes).byteLength > 0);

  let unavailableSinkWrites = 0;
  advanceAccessTimeAt = '2026-09-18T01:45:00.001Z';
  await assert.rejects(deliverAuthorizedResult(
    accessService,
    {
      indexKey: stateRequest.indexKey,
      principalId: 'principal-a',
      purpose: 'authorization-crosses-retention',
      resultName: 'answer',
      format: 'json',
      attemptId: 'authorization-crosses-retention',
    },
    {
      write(bytes) {
        unavailableSinkWrites++;
        return {confirmedBytes: bytes.byteLength};
      },
      finish() { return {confirmed: true}; },
    },
  ), {code: 'ResultDeliveryDenied'});
  advanceAccessTimeAt = undefined;
  assert.equal(unavailableSinkWrites, 0);

  const retentionAuthority = installResultRetentionAuthority({
    authorizeResultDeletion: () => true,
  });
  const notDueRetentionService = installResultRetentionService({
    store: deliveryStore,
    control,
    authority: retentionAuthority,
    now: () => '2026-09-18T01:45:00.001Z',
    limits,
  });
  await assert.rejects(retireExpiredResult(notDueRetentionService, {
    indexKey: stateRequest.indexKey,
    resultName: 'answer',
    reason: 'retention_deadline',
  }), {code: 'ResultDeletionNotDue'});
  const deniedRetentionService = installResultRetentionService({
    store: deliveryStore,
    control,
    authority: installResultRetentionAuthority({
      authorizeResultDeletion: () => false,
    }),
    now: () => '2026-09-18T02:00:00.000Z',
    limits,
  });
  await assert.rejects(retireExpiredResult(deniedRetentionService, {
    indexKey: stateRequest.indexKey,
    resultName: 'answer',
    reason: 'retention_deadline',
  }), {code: 'ResultRetentionDenied'});
  const retentionService = installResultRetentionService({
    store: deliveryStore,
    control,
    authority: retentionAuthority,
    now: () => '2026-09-18T02:00:00.000Z',
    limits,
  });
  const retired = await retireExpiredResult(retentionService, {
    indexKey: stateRequest.indexKey,
    resultName: 'answer',
    reason: 'retention_deadline',
  });
  assert.equal(retired.cleanupPending, false);
  accessTime = '2026-09-18T02:00:00.000Z';
  await assert.rejects(extendResultRetention(extensionService, {
    indexKey: stateRequest.indexKey,
    resultName: 'answer',
    availableUntil: '2026-09-18T01:50:00.000Z',
    reason: 'too_late',
  }), {code: 'ResultRetentionExtensionUnavailable'});
  requestAccessAllowed = false;
  await assert.rejects(deliverAuthorizedResult(
    accessService,
    {
      indexKey: stateRequest.indexKey,
      principalId: 'principal-a',
      purpose: 'download',
      resultName: 'answer',
      format: 'json',
      attemptId: 'denied-deleted',
    },
    {
      write: () => assert.fail('denied deleted Result exposed bytes'),
      finish: () => assert.fail('denied deleted Result finished delivery'),
    },
  ), {code: 'ResultAccessDenied'});
  requestAccessAllowed = true;
  await assert.rejects(deliverAuthorizedResult(
    accessService,
    {
      indexKey: stateRequest.indexKey,
      principalId: 'principal-a',
      purpose: 'download',
      resultName: 'answer',
      format: 'json',
      attemptId: 'authorized-after-deletion',
    },
    {
      write: () => assert.fail('deleted Result exposed bytes'),
      finish: () => assert.fail('deleted Result finished delivery'),
    },
  ), {code: 'ResultUnavailable'});
  const deletedState = await inspectAuthorizedRunState(
    stateService, stateRequest,
  );
  assert.equal(deletedState.status, 'succeeded');
  assert.equal(deletedState.result_available, false);
  assert.deepEqual(deletedState.next_action, {kind: 'none'});
  assert.equal(
    deletedState.result_availability.answer.reason,
    'deleted',
  );
  const metadataAuthority = installMetadataRetentionAuthority({
    authorizeMetadataDeletion: () => true,
  });
  const earlyMetadataService = installMetadataRetentionService({
    store: deliveryStore,
    control,
    authority: metadataAuthority,
    now: () => '2026-09-18T03:59:59.999Z',
    limits,
  });
  await assert.rejects(retireExpiredPublicationMetadata(
    earlyMetadataService,
    {indexKey: stateRequest.indexKey, reason: 'metadata_deadline'},
  ), {code: 'MetadataDeletionNotDue'});
  const metadataStages = [];
  const metadataService = installMetadataRetentionService({
    store: deliveryStore,
    control,
    authority: installMetadataRetentionAuthority({
      authorizeMetadataDeletion(facts) {
        metadataStages.push(facts.stage);
        return true;
      },
    }),
    now: () => '2026-09-18T04:00:00.000Z',
    limits,
  });
  const retiredMetadata = await retireExpiredPublicationMetadata(
    metadataService,
    {indexKey: stateRequest.indexKey, reason: 'metadata_deadline'},
  );
  assert.equal(retiredMetadata.cleanupPending, false);
  assert.deepEqual(metadataStages, ['request', 'delete']);
  assert.equal(await deliveryStore.confirmCommittedIndex(
    stateRequest.indexKey,
  ), undefined);

  const lostDirectory = await mkdtemp(join(
    tmpdir(), 'actql-publication-lost-response-',
  ));
  t.after(() => rm(lostDirectory, {recursive: true, force: true}));
  const lostBase = await openLocalPublicationStore({
    directory: lostDirectory,
    storeAuthorityCid: cid('a'),
    capacityBytes: 4 * 1024 * 1024,
    maxObjectBytes: limits.maxWireBytes,
    maxObjects: 100,
    maxContractNodes: limits.maxNodes,
    maxContractDepth: limits.maxDepth,
  }, control);
  await lostBase.putSemantic(resultSchemaWire, resultSchemaCid);
  await lostBase.putBytes(Buffer.from(payloadWire, 'utf8'), physicalCid);
  t.after(async () => { await lostBase.close(); });
  let loseCommitResponse = true;
  const lostStore = Object.freeze({
    ...lostBase,
    async commitIndex(...arguments_) {
      const value = await lostBase.commitIndex(...arguments_);
      if (loseCommitResponse) {
        loseCommitResponse = false;
        throw new Error('simulated lost commit response');
      }
      return value;
    },
  });
  const lost = await publishEffectFreeRun({
    ...publicationOptions,
    store: lostStore,
    attempt: {
      ...publicationOptions.attempt,
      attemptId: 'lost-response-attempt',
    },
  });
  assert.equal(lost.state, 'succeeded');
  assert.equal(lost.committed, false);
  assert.equal(lost.idempotent, true);
  assert.equal((await lostBase.latestRecord(lost.attempt.identity)).state,
    'succeeded');

  const raceDirectory = await mkdtemp(join(
    tmpdir(), 'actql-publication-race-',
  ));
  t.after(() => rm(raceDirectory, {recursive: true, force: true}));
  const raceBase = await openLocalPublicationStore({
    directory: raceDirectory,
    storeAuthorityCid: cid('a'),
    capacityBytes: 4 * 1024 * 1024,
    maxObjectBytes: limits.maxWireBytes,
    maxObjects: 100,
    maxContractNodes: limits.maxNodes,
    maxContractDepth: limits.maxDepth,
  }, control);
  await raceBase.putSemantic(resultSchemaWire, resultSchemaCid);
  await raceBase.putBytes(Buffer.from(payloadWire, 'utf8'), physicalCid);
  t.after(async () => { await raceBase.close(); });
  let commitArrivals = 0;
  let releaseCommits;
  const commitsReady = new Promise(resolve => { releaseCommits = resolve; });
  const raceStore = Object.freeze({
    ...raceBase,
    async commitIndex(...arguments_) {
      commitArrivals++;
      if (commitArrivals === 2) releaseCommits();
      await commitsReady;
      return raceBase.commitIndex(...arguments_);
    },
  });
  const raceAttempts = ['race-a', 'race-b'].map(attemptId => ({
    ...publicationOptions.attempt,
    attemptId,
  }));
  const raced = await Promise.all(raceAttempts.map(attempt =>
    publishEffectFreeRun({...publicationOptions, store: raceStore, attempt})));
  assert.equal(raced.filter(value => value.committed).length, 1);
  assert.equal(raced.filter(value => value.idempotent).length, 1);
  assert.equal(raced[0].index.identity, raced[1].index.identity);
  assert.equal(raced[0].attempt.identity, raced[1].attempt.identity);
  const raceContracts = raceAttempts.map(attempt =>
    control.issuePublicationAttempt(request, run, attempt, limits));
  const raceStates = await Promise.all(raceContracts.map(attempt =>
    raceBase.latestRecord(attempt.identity)));
  assert.deepEqual(
    raceStates.map(value => value.state).sort(),
    ['cancelled', 'succeeded'],
  );
  assert.equal((await readdir(
    join(raceDirectory, 'metadata-inventories'),
  )).length, 1);
  const raceIndexes = raceContracts.map(raceAttempt =>
    control.issuePublicIndexEntry({
      runDefinition: run,
      invocation: invoked,
      manifest,
      receipt,
      capturedRun: captured,
      durableBindings: [binding],
      request,
      attempt: raceAttempt,
    }, '2026-09-18T00:00:07.000Z', limits));
  const losingIndex = raceIndexes.find(candidate =>
    JSON.parse(candidate.wire).publication_attempt_cid !==
      raced[0].attempt.identity);
  await assert.rejects(
    raceBase.readPublicationContract(
      losingIndex.identity, 'public_index_entry',
    ),
    error => error?.code === 'PublicationContractMissing',
  );

  const unknownDirectory = await mkdtemp(join(
    tmpdir(), 'actql-publication-unknown-',
  ));
  t.after(() => rm(unknownDirectory, {recursive: true, force: true}));
  const unknownBase = await openLocalPublicationStore({
    directory: unknownDirectory,
    storeAuthorityCid: cid('a'),
    capacityBytes: 4 * 1024 * 1024,
    maxObjectBytes: limits.maxWireBytes,
    maxObjects: 100,
    maxContractNodes: limits.maxNodes,
    maxContractDepth: limits.maxDepth,
  }, control);
  await unknownBase.putSemantic(resultSchemaWire, resultSchemaCid);
  await unknownBase.putBytes(Buffer.from(payloadWire, 'utf8'), physicalCid);
  t.after(async () => { await unknownBase.close(); });
  let indexInspections = 0;
  const unknownStore = Object.freeze({
    ...unknownBase,
    async confirmCommittedIndex(...arguments_) {
      indexInspections++;
      if (indexInspections > 1) throw new Error('index unavailable');
      return unknownBase.confirmCommittedIndex(...arguments_);
    },
    async commitIndex() { throw new Error('commit outcome unavailable'); },
  });
  const unknownAttempt = {
    ...publicationOptions.attempt,
    attemptId: 'unknown-attempt',
  };
  await assert.rejects(publishEffectFreeRun({
    ...publicationOptions,
    store: unknownStore,
    attempt: unknownAttempt,
  }), error => error?.code === 'RunPublicationUnknown' &&
    error.publicationState === 'publication_unknown');
  const unknownContract = control.issuePublicationAttempt(
    request, run, unknownAttempt, limits,
  );
  assert.equal((await unknownBase.latestRecord(unknownContract.identity)).state,
    'publication_unknown');
  const reconciled = await publishEffectFreeRun({
    ...publicationOptions,
    store: unknownBase,
    attempt: {
      ...publicationOptions.attempt,
      attemptId: 'reconciled-attempt',
    },
  });
  assert.equal(reconciled.state, 'succeeded');

  const cancelledDirectory = await mkdtemp(join(
    tmpdir(), 'actql-publication-cancelled-',
  ));
  t.after(() => rm(cancelledDirectory, {recursive: true, force: true}));
  const cancelledBase = await openLocalPublicationStore({
    directory: cancelledDirectory,
    storeAuthorityCid: cid('a'),
    capacityBytes: 4 * 1024 * 1024,
    maxObjectBytes: limits.maxWireBytes,
    maxObjects: 100,
    maxContractNodes: limits.maxNodes,
    maxContractDepth: limits.maxDepth,
  }, control);
  await cancelledBase.putSemantic(resultSchemaWire, resultSchemaCid);
  await cancelledBase.putBytes(Buffer.from(payloadWire, 'utf8'), physicalCid);
  t.after(async () => { await cancelledBase.close(); });
  const cancellation = new AbortController();
  const cancelledStore = Object.freeze({
    ...cancelledBase,
    async appendRecord(wire, options) {
      const value = await cancelledBase.appendRecord(wire, options);
      if (value.state === 'preparing') cancellation.abort();
      return value;
    },
  });
  const cancelledAttempt = {
    ...publicationOptions.attempt,
    attemptId: 'cancelled-attempt',
  };
  await assert.rejects(publishEffectFreeRun({
    ...publicationOptions,
    store: cancelledStore,
    attempt: cancelledAttempt,
    signal: cancellation.signal,
  }), {name: 'AbortError'});
  const cancelledContract = control.issuePublicationAttempt(
    request, run, cancelledAttempt, limits,
  );
  assert.equal((await cancelledBase.latestRecord(
    cancelledContract.identity,
  )).state, 'cancelled');
});

test('local durable Store accepts only MoonBit-admitted contract wire',
  async t => {
    const directory = await mkdtemp(join(
      tmpdir(), 'actql-publication-runtime-',
    ));
    t.after(() => rm(directory, {recursive: true, force: true}));
    const control = runtimeCore(moon).publicationControl;
    const store = await openLocalPublicationStore({
      directory,
      storeAuthorityCid: cid('a'),
      capacityBytes: 1024 * 1024,
      maxObjectBytes: limits.maxWireBytes,
      maxObjects: 100,
      maxContractNodes: limits.maxNodes,
      maxContractDepth: limits.maxDepth,
    }, control);
    t.after(async () => { await store.close(); });
    const sealed = invocation(control);
    const stored = await store.putPublicationContract(
      sealed.name, sealed.wire,
    );
    assert.equal(stored.semanticCid, sealed.identity);
    assert.deepEqual(
      await store.readJsonObject(sealed.identity, sealed.name),
      JSON.parse(sealed.wire),
    );
  });

test('complete publication reclaims prepared payloads after a later export fails',
  async () => {
    const definition = Object.freeze({
      name: 'result_definition', identity: cid('1'), wire: '{}',
    });
    const runDefinition = Object.freeze({
      name: 'run_definition', identity: cid('2'), wire: '{}',
    });
    const invoked = Object.freeze({
      name: 'run_invocation', identity: cid('3'), wire: '{}',
    });
    const retention = Object.freeze({
      name: 'result_retention_policy', identity: cid('4'), wire: '{}',
    });
    let pending = true;
    let releases = 0;
    const prepared = Object.freeze({
      status: () => Object.freeze({pending, errors: Object.freeze([])}),
      async release() { releases++; pending = false; return true; },
      async retry() { pending = false; return this.status(); },
    });
    const publication = Object.freeze({
      artifact: definition,
      derivation: definition,
      ordering: definition,
      durableBinding: definition,
      snapshot: Object.freeze({}),
    });
    const occurrences = Object.freeze([0, 1].map((_, index) =>
      Object.freeze({
        name: `result-${index}`,
        task: index + 1,
        definitionContract: definition,
      })));
    const execution = Object.freeze({
      status: 'host-tasks-completed',
      resultInventory: occurrences,
      publicationInventory: Object.freeze({occurrences}),
      async storePublicationResult(index) {
        if (index === 1) throw new Error('second export failed');
        return Object.freeze({
          occurrence: Object.freeze({
            name: 'result-0', task: 1, definition,
          }),
          publication,
          prepared,
        });
      },
    });
    const progress = runtimeCore(moon).publicationControl;
    const control = Object.freeze({
      publicationPreparedReleaseAction:
        progress.publicationPreparedReleaseAction,
      publicationCleanupOwnerAction:
        progress.publicationCleanupOwnerAction,
      issueResultManifest() { assert.fail('Manifest must not be issued'); },
      issueEffectFreeRunReceipt() { assert.fail('Receipt must not be issued'); },
      issueEffectFreeCapturedRun() {
        assert.fail('Captured Run must not be issued');
      },
    });
    await assert.rejects(publishCompletedEffectFreeRun({
      execution,
      store: Object.freeze({}),
      control,
      admission: Object.freeze({}),
      runDefinition,
      invocation: invoked,
      observation: Object.freeze({}),
      normalizationJournal: Object.freeze({}),
      authoringContext: Object.freeze({}),
      results: [0, 1].map(() => ({
        retention,
        evidenceContext: Object.freeze({}),
      })),
      receiptEvidence: {
        bindings: [], sourceEvidence: [], modelEvidence: [],
        barrierAttemptReceiptCids: [],
      },
      captureEvidence: {
        pendingSourceStateAdvances: [], modelEvidence: [],
      },
      request: Object.freeze({}),
      attempt: Object.freeze({}),
      outputLimits: Object.freeze({}),
      contractLimits: Object.freeze({}),
      now: () => '2026-09-18T00:00:00.000Z',
      signal: undefined,
    }), /second export failed/u);
    assert.equal(releases, 1);
    assert.equal(pending, false);
  });

test('complete publication composes every unresolved cleanup owner',
  async () => {
    const definition = Object.freeze({
      name: 'result_definition', identity: cid('1'), wire: '{}',
    });
    const runDefinition = Object.freeze({
      name: 'run_definition', identity: cid('2'), wire: '{}',
    });
    const invoked = Object.freeze({
      name: 'run_invocation', identity: cid('3'), wire: '{}',
    });
    const retention = Object.freeze({
      name: 'result_retention_policy', identity: cid('4'), wire: '{}',
    });
    let preparedPending = true;
    let primaryPending = true;
    let allowPrepared = false;
    let allowPrimary = false;
    let preparedRetries = 0;
    let primaryRetries = 0;
    const prepared = Object.freeze({
      status: () => Object.freeze({
        pending: preparedPending, errors: Object.freeze([]),
      }),
      async release() { throw new Error('prepared release failed'); },
      async retry() {
        preparedRetries++;
        if (allowPrepared) preparedPending = false;
        return this.status();
      },
    });
    const primaryCleanup = Object.freeze({
      status: () => Object.freeze({
        pending: primaryPending, errors: Object.freeze([]),
      }),
      async retry() {
        primaryRetries++;
        if (allowPrimary) primaryPending = false;
        return this.status();
      },
    });
    const primary = Object.freeze({
      code: 'SecondExportFailed',
      cleanupPending: true,
      cleanupHandle: primaryCleanup,
    });
    const publication = Object.freeze({
      artifact: definition,
      derivation: definition,
      ordering: definition,
      durableBinding: definition,
      snapshot: Object.freeze({}),
    });
    const occurrences = Object.freeze([0, 1].map((_, index) =>
      Object.freeze({
        name: `result-${index}`,
        task: index + 1,
        definitionContract: definition,
      })));
    const execution = Object.freeze({
      status: 'host-tasks-completed',
      resultInventory: occurrences,
      publicationInventory: Object.freeze({occurrences}),
      async storePublicationResult(index) {
        if (index === 1) throw primary;
        return Object.freeze({
          occurrence: Object.freeze({
            name: 'result-0', task: 1, definition,
          }),
          publication,
          prepared,
        });
      },
    });
    const progress = runtimeCore(moon).publicationControl;
    const control = Object.freeze({
      publicationPreparedReleaseAction:
        progress.publicationPreparedReleaseAction,
      publicationCleanupOwnerAction:
        progress.publicationCleanupOwnerAction,
      issueResultManifest() { assert.fail('Manifest must not be issued'); },
      issueEffectFreeRunReceipt() { assert.fail('Receipt must not be issued'); },
      issueEffectFreeCapturedRun() {
        assert.fail('Captured Run must not be issued');
      },
    });
    let failure;
    await assert.rejects(publishCompletedEffectFreeRun({
      execution,
      store: Object.freeze({}),
      control,
      admission: Object.freeze({}),
      runDefinition,
      invocation: invoked,
      observation: Object.freeze({}),
      normalizationJournal: Object.freeze({}),
      authoringContext: Object.freeze({}),
      results: [0, 1].map(() => ({
        retention,
        evidenceContext: Object.freeze({}),
      })),
      receiptEvidence: {
        bindings: [], sourceEvidence: [], modelEvidence: [],
        barrierAttemptReceiptCids: [],
      },
      captureEvidence: {
        pendingSourceStateAdvances: [], modelEvidence: [],
      },
      request: Object.freeze({}),
      attempt: Object.freeze({}),
      outputLimits: Object.freeze({}),
      contractLimits: Object.freeze({}),
      now: () => '2026-09-18T00:00:00.000Z',
      signal: undefined,
    }), error => {
      failure = error;
      return error?.code === 'SecondExportFailed' &&
        error.primaryFailure === primary &&
        error.cleanupHandle?.status().pending === true;
    });
    allowPrepared = true;
    assert.equal((await failure.cleanupHandle.retry()).pending, true);
    assert.equal(preparedPending, false);
    assert.equal(primaryPending, true);
    allowPrimary = true;
    assert.equal((await failure.cleanupHandle.retry()).pending, false);
    assert.equal(preparedRetries, 1);
    assert.equal(primaryRetries, 2);
  });
