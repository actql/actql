import {installedEffectDependencyOriginal} from './installed-effect-dependency-original.mjs';
import {runtimeField, runtimeOptionalField, runtimeIsBoxedSome} from './compiler-binding.generated.mjs';
import {checked} from './runtime-result.mjs';
import {outputExportControl} from './output-export-control.mjs';
import {contentGenerationControl} from './content-generation-control.mjs';
import {contentCaptureControl} from './content-capture-control.mjs';
import {siteControl} from './site-control.mjs';
import {remoteStandardSourceControl} from './remote-standard-source-control.mjs';
import {remoteCredentialControl} from './remote-credential-control.mjs';
import {remoteBundleControl} from './remote-bundle-control.mjs';
import {remoteTransferControl} from './remote-transfer-control.mjs';
import {remoteSiteControl} from './remote-site-control.mjs';
import {effectApplicationControl} from './effect-application-control.mjs';
import {createRuntimeExecutionControls} from './runtime-execution-control.mjs';
import {createLocalSigningMetadata} from './local-signing-metadata.mjs';
import {createInstallationPreparationMetadata} from './installation-preparation-metadata.mjs';
import {publicationProgressControl} from './publication-progress-control.mjs';
import {createResultDeliveryControls} from './runtime-result-delivery-control.mjs';
import {createRunStateControls} from './runtime-run-state-control.mjs';
import {createPublicationContractControls} from './runtime-publication-contract-control.mjs';
import {createQueryTimeControls} from './runtime-query-time-control.mjs';
import {createContentPublicationControls} from './runtime-content-publication-control.mjs';
import {createContentInferenceControls} from './runtime-content-inference-control.mjs';
import {createEffectCaptureControls} from './runtime-effect-capture-control.mjs';
import {createPublicationValidationControls} from './runtime-publication-validation-control.mjs';
import {createCapturedPublicationControls} from './runtime-captured-publication-control.mjs';
import {createInferOriginalReadControls} from './runtime-infer-original-read-control.mjs';
import {createModelPreparationControls} from './runtime-model-preparation-control.mjs';
import {createEffectPreparationControls} from './runtime-effect-preparation-control.mjs';
import {createEffectUnitResultControls} from './runtime-effect-unit-result-control.mjs';
import {createEffectArtifactControls} from './runtime-effect-artifact-control.mjs';
import {createEffectRecoveryControls} from './runtime-effect-recovery-control.mjs';
import {createEffectPreviewControls} from './runtime-effect-preview-control.mjs';
import {validWirePlanViewShape} from '../../packages/client-wire/index.mjs';
import {ledgerUsageSnapshot, ledgerUsageDiagnostic,
  ledgerUsageHasPendingResources, ledgerUsageSnapshotHasPendingResources} from './ledger-usage.mjs';
import {
  resultOutputLimitFields,
  validResultOutputLimits,
} from './result-output-limits.mjs';

export {contentCaptureControl, contentGenerationControl};
export {ledgerUsageSnapshot, ledgerUsageDiagnostic,
  ledgerUsageHasPendingResources, ledgerUsageSnapshotHasPendingResources};
const publicationControls = new WeakMap();

function publicationControl(moon) {
  let control = publicationControls.get(moon);
  if (control !== undefined) return control;
  const tokens = new WeakMap();
  const recoveredEffectCaptures = new WeakMap();
  const capturedComputationPreparations = new WeakMap();
  const contractBounds = new WeakMap();
  const issuedDeliveryGrants = new WeakMap();
  const issuedDeliveryAttempts = new WeakMap();
  const originalDeliveryAttempts = new WeakMap();
  const evidenceTokens = new WeakMap();
  const modelOriginalDocumentTokens = new WeakMap();
  const admissionTokens = new WeakMap();
  const compiledRunTokens = new WeakMap();
  const originalRunPlanTokens = new WeakMap();
  // The installed namespace supplies these fixed methods before a first
  // admission can await. Later property replacement cannot return another
  // owner's loan or change the original projection selected by this control.
  const captureRequestExplanation = moon.clientProgramCaptureRequestOriginalExplanation;
  const originalExplanationPlanWire = moon.clientProgramOriginalExplanationPlanWire;
  const originalExplanationFactsWire = moon.clientProgramOriginalExplanationFactsWire;
  const returnExplanationCapture = moon.clientProgramReturnOriginalExplanationCapture;
  const acknowledgeExplanationCapture = moon.clientProgramAcknowledgeOriginalExplanationCapture;
  const observeOriginalDispatchFailure = moon.clientProgramObserveOriginalDispatchFailure;
  const describeExecutionFailure = moon.strategyModule_local_ManagedFailureExplanation;
  const prepareLogicalObservation = moon.clientProgramPrepareLogicalObservation;
  const originalInferRunTokens = new WeakMap();
  const restoredInferRuns = new WeakSet();
  const serializationPlanTokens = new WeakMap();
  const serializationGenerationTokens = new WeakMap();
  const serializationInputEvidenceTokens = new WeakMap();
  const compiledSourceFreeResultPolicy = compiled => {
    const value = compiledRunTokens.get(compiled);
    if (value === undefined) throw new TypeError('Foreign Client compiled Run');
    const original = moon.clientProgramCompiledRunSourceFreeResultPolicy(value);
    return original === undefined ? undefined : Object.freeze({
      kind: runtimeField(original, 0), cid: runtimeField(original, 1), wire: runtimeField(original, 2),
    });
  };
  const inferInvocationTokens = new WeakMap();
  const inferModelObservationTokens = new WeakMap();
  const compiledRunResult = (result, code) => {
    try {
      return checked(result);
    } catch (error) {
      if (error.code !== 'MoonBitHostFailure') throw error;
      throw Object.assign(new Error(code, {cause: error.cause}), {code});
    }
  };
  const compiledContent = compiled => {
    const value = compiledRunTokens.get(compiled);
    if (value === undefined || !moon.clientProgramCompiledRunHasSerialization(value)) {
      throw new TypeError('Foreign Client compiled Content Run');
    }
    return value;
  };
  const contentCaptures = values => {
    if (values === undefined) return [];
    if (!Array.isArray(values)) throw new TypeError('Invalid Content capture inventory');
    return values.map(value => {
      const generation = serializationGenerationTokens.get(value);
      if (generation === undefined) throw new TypeError('Foreign Client Content generation');
      return compiledRunResult(moon.clientProgramSerializationCapture(generation),
        'Client Content capture unavailable');
    });
  };
  const snapshotTokens = new WeakMap();
  const effectSourceTokens = new WeakMap();
  const localEffectSourceTokens = new WeakMap();
  const localEffectArtifactTokens = new WeakMap();
  const localEffectIdentityTokens = new WeakMap();
  const tableInputTokens = new WeakMap();
  const tablePreviewTokens = new WeakMap();
  const recoveredTablePreviewTokens = new WeakMap();
  const localEffectManifestTokens = new WeakMap();
  const localEffectArtifactSources = new WeakMap();
  const localEffectImportSources = new WeakMap();
  const localEffectDependencyTokens = new WeakMap();
  const localEffectImportTokens = new WeakMap();
  const inspectLocalEffectArtifact = issued => {
    const value = Object.freeze({
      identity: moon.clientProgramLocalEffectResultArtifactCid(issued),
      wire: moon.clientProgramLocalEffectResultArtifactJson(issued),
      derivationWire: moon.clientProgramLocalEffectResultDerivationJson(issued),
      orderingWire: moon.clientProgramLocalEffectResultOrderingJson(issued),
    });
    localEffectArtifactTokens.set(value, issued);
    return value;
  };
  // The actual Core-issued Source metadata is projected once. Only callers
  // with an admitted whole Unit register an Artifact dependency token below;
  // Model contributions remain inside their complete Model context.
  const inspectAcquiredEffectEvidence = (issued, publicationRetention, limits, deferCatalogs = false) => {
    return Object.freeze({
      invocation: moon.clientProgramAcquiredEffectInvocation(issued),
      bodies: Object.freeze([
        ...moon.clientProgramAcquiredEffectDependencyBodies(issued)
          .map(pair => Object.freeze({kind: runtimeField(pair, 0), wire: runtimeField(pair, 1),
            ...(runtimeField(pair, 0) === 'request_values' ? {
              cid: moon.clientProgramAcquiredEffectRequestCid(issued),
            } : {})})),
        Object.freeze({kind: 'result_retention_policy',
          wire: inspect(token(publicationRetention)).wire}),
      ]),
      ...(deferCatalogs ? {catalogDeferred: true, catalogBodies: Object.freeze([])} : {catalogBodies: Object.freeze(checked(
        moon.clientProgramAcquiredEffectCatalogBodies(issued,
          limits.maxWireBytes, limits.maxNodes, limits.maxDepth))
        .map(body => Object.freeze({kind: runtimeField(body, 0), cid: runtimeField(body, 1),
          wire: runtimeField(body, 2)})))}),
    });
  };
  const localEffectContext = context => {
    if (context === null || typeof context !== 'object' ||
        !['admission', 'runDefinition', 'runInvocation', 'observation']
          .every(key => context[key] !== undefined)) {
      throw new TypeError('Invalid local Effect Result context');
    }
    return [admissionToken(context.admission), token(context.runDefinition),
      token(context.runInvocation), evidenceToken(context.observation)];
  };
  const sourceAdvanceTokens = new WeakMap();
  const computationPreviewTokens = new WeakMap();
  const computationPreviewWires = new WeakMap();
  const inspect = (contract, limits) => {
    const value = Object.freeze({
      name: moon.strategyPublicationContractName(contract),
      identityField: moon.strategyPublicationContractIdentityField(contract),
      identity: moon.strategyPublicationContractIdentity(contract),
      wire: moon.strategyPublicationContractJson(contract),
    });
    tokens.set(value, contract);
    if (limits !== undefined) {
      // The actual issuer checked this complete immutable wire under these
      // bounds. Each JSON node needs at least one UTF-16 code unit; at most
      // three UTF-8 bytes encode one code unit. These conservative bounds
      // can prove a later looser limit without parsing or hashing again.
      contractBounds.set(value, Object.freeze({
        maxWireBytes: Math.min(limits.maxWireBytes, value.wire.length * 3),
        maxNodes: Math.min(limits.maxNodes, value.wire.length),
        maxDepth: limits.maxDepth,
      }));
    }
    return value;
  };
  // Complete immutable DATA only; callers retain their original Read/Run
  // reservation and all current/physical duties. Shared by fresh and recovery.
  const inspectPreparedEffectCapturedRun = prepared => {
    const existing = recoveredEffectCaptures.get(prepared);
    if (existing !== undefined) return existing;
    const actual = moon.clientProgramRecoveredEffectCapturedRunLimits(prepared);
    const limits = Object.freeze({maxWireBytes:runtimeField(actual,0), maxNodes:runtimeField(actual,1), maxDepth:runtimeField(actual,2)});
    issuanceLimits(limits, 'original Effect captured Run');
    const captured = inspect(moon.clientProgramRecoveredEffectCapturedRunContract(prepared), limits);
    recoveredEffectCaptures.set(captured, prepared); recoveredEffectCaptures.set(prepared, captured);
    return captured;
  };
  const token = value => {
    const result = tokens.get(value);
    if (result === undefined) {
      throw new TypeError('Foreign publication contract');
    }
    return result;
  };
  const inspectEvidence = evidence => {
    const value = Object.freeze({
      name: moon.strategyRunEvidenceName(evidence),
      identity: moon.strategyRunEvidenceIdentity(evidence),
      wire: moon.strategyRunEvidenceJson(evidence),
    });
    evidenceTokens.set(value, evidence);
    return value;
  };
  const evidenceToken = value => {
    const result = evidenceTokens.get(value);
    if (result === undefined) throw new TypeError('Foreign Run evidence');
    return result;
  };
  const inspectAdmission = admission => {
    const value = Object.freeze({kind: 'run-publication-admission'});
    admissionTokens.set(value, admission);
    return value;
  };
  const admissionToken = value => {
    const result = admissionTokens.get(value);
    if (result === undefined) {
      throw new TypeError('Foreign Run publication admission');
    }
    return result;
  };
  const inspectSnapshot = snapshot => {
    const value = Object.freeze({kind: 'captured-result-snapshot'});
    snapshotTokens.set(value, snapshot);
    return value;
  };
  const snapshotToken = value => {
    const result = snapshotTokens.get(value);
    if (result === undefined) {
      throw new TypeError('Foreign captured Result snapshot');
    }
    return result;
  };
  const inspectEffectSource = source => {
    const value = Object.freeze({kind: 'captured-effect-source-artifact'});
    effectSourceTokens.set(value, source);
    return value;
  };
  const effectSourceToken = value => {
    const result = effectSourceTokens.get(value);
    if (result === undefined) {
      throw new TypeError('Foreign captured Effect source artifact');
    }
    return result;
  };
  const localEffectSourceToken = value => {
    const result = localEffectSourceTokens.get(value);
    if (result === undefined) {
      throw new TypeError('Foreign local Effect source evidence');
    }
    return result;
  };
  const inspectSourceAdvance = advance => {
    const value = Object.freeze({kind: 'pending-source-state-advance'});
    sourceAdvanceTokens.set(value, advance);
    return value;
  };
  const sourceAdvanceToken = value => {
    const result = sourceAdvanceTokens.get(value);
    if (result === undefined) {
      throw new TypeError('Foreign pending source-state advance');
    }
    return result;
  };
  const issuanceLimits = (limits, label) => {
    if (limits === null || typeof limits !== 'object' ||
        !Number.isSafeInteger(limits.maxWireBytes) ||
        !Number.isSafeInteger(limits.maxNodes) ||
        !Number.isSafeInteger(limits.maxDepth) ||
        limits.maxWireBytes < 0 || limits.maxNodes < 0 ||
        limits.maxDepth < 0) {
      throw new TypeError(`Invalid ${label} issuance limits`);
    }
    return limits;
  };
  const captureContractLimits = (limits, label) => issuanceLimits(Object.freeze({
    maxWireBytes: limits?.maxWireBytes,
    maxNodes: limits?.maxNodes,
    maxDepth: limits?.maxDepth,
  }), label);
  const {resultReadControls, resultRetentionControls, resultDeliveryControls} =
    createResultDeliveryControls(moon, {token, inspect, issuanceLimits, captureContractLimits,
      issuedDeliveryGrants, issuedDeliveryAttempts, originalDeliveryAttempts});
  const {effectRunStateControls, runIdentityControls, publicationStateControls} =
    createRunStateControls(moon, {token, issuanceLimits,
      computationPreviewTokens, modelOriginalDocumentTokens});
  const {transitionControls, contractControls} = createPublicationContractControls(moon, {
    token, admissionToken, evidenceToken, inspect, captureContractLimits,
  });
  const contentPublicationControls = createContentPublicationControls(moon, {
    compiledRunTokens, serializationGenerationTokens, compiledContent, compiledRunResult, token,
    inspectEvidence, inspect, captureContractLimits,
    serializationPlanTokens, serializationInputEvidenceTokens, inspectAdmission, evidenceToken, issuanceLimits,
  });
  const queryTimeControls = createQueryTimeControls(moon, {
    compiledRunTokens, token, currentControl: () => control,
  });
  const contentInferenceControls = createContentInferenceControls(moon, {
    serializationPlanTokens, serializationGenerationTokens, compiledContent, compiledRunResult, token,
  });
  const {captureControls, sourceControls, inventoryControls} = createEffectCaptureControls(moon, {
    computationPreviewTokens, recoveredEffectCaptures, localEffectArtifactTokens,
    token, inspect, inspectSnapshot, inspectEffectSource, inspectPreparedEffectCapturedRun,
    effectSourceToken, localEffectSourceToken, issuanceLimits,
  });
  const {capturedPreparationLimits, snapshotControls, effectFreeCaptureControls, effectfulCaptureControls} =
    createCapturedPublicationControls(moon, {
      capturedComputationPreparations, computationPreviewTokens, token, evidenceToken, snapshotToken,
      sourceAdvanceToken, contentCaptures, effectSourceToken, localEffectSourceToken,
      inspect, inspectSnapshot, inspectPreparedEffectCapturedRun, captureContractLimits,
    });
  const publicationValidationControls = createPublicationValidationControls(moon, {
    capturedComputationPreparations, recoveredEffectCaptures, computationPreviewTokens,
    token, issuanceLimits, capturedPreparationLimits,
  });
  const inferOriginalReadControls = createInferOriginalReadControls(moon, {
    compiledRunTokens, modelOriginalDocumentTokens, token, evidenceToken, inspectEvidence, issuanceLimits,
  });
  const modelPreparationControls = createModelPreparationControls(moon, {
    compiledRunTokens, serializationPlanTokens, token, compiledRunResult, currentControl: () => control,
  });
  const effectPreparationControls = createEffectPreparationControls(moon, {
    admissionToken, token, evidenceToken, inspectAdmission, inspect, inspectEvidence,
    issuanceLimits, captureContractLimits, localEffectDependencyTokens, inferInvocationTokens,
    compiledRunTokens, serializationGenerationTokens, inspectAcquiredEffectEvidence,
  });
  const effectUnitResultControls = createEffectUnitResultControls(moon, {
    compiledRunTokens, localEffectDependencyTokens, localEffectArtifactTokens, localEffectManifestTokens,
    issuanceLimits, token, admissionToken, inspectLocalEffectArtifact, localEffectContext,
  });
  const {effectDependencyControls, effectArtifactControls} =
    createEffectArtifactControls(moon, {
      localEffectDependencyTokens, localEffectManifestTokens, localEffectArtifactTokens, localEffectArtifactSources,
      localEffectImportTokens, localEffectImportSources, localEffectSourceTokens, localEffectIdentityTokens,
      issuanceLimits, token, admissionToken, evidenceToken, effectSourceToken, inspectLocalEffectArtifact,
      localEffectContext, currentControl: () => control,
    });
  const effectRecoveryControls = createEffectRecoveryControls(moon, {
    computationPreviewTokens, localEffectArtifactTokens, localEffectIdentityTokens,
    tableInputTokens, tablePreviewTokens, recoveredTablePreviewTokens,
    compiledContent, issuanceLimits, token, effectSourceToken, currentControl: () => control,
  });
  const {pendingSourceAdvanceControls, effectPreviewControls} =
    createEffectPreviewControls(moon, {
      computationPreviewTokens, computationPreviewWires, issuanceLimits, token,
      evidenceToken, inspectEvidence, inspectSourceAdvance,
    });
  control = Object.freeze({
    executionFailureExplanation(cause) {
      if (typeof cause !== 'string' || cause.length > 96 ||
          typeof describeExecutionFailure !== 'function') return undefined;
      // Reuse the original Common export captured with this control. This is
      // inert catalogue DATA, never an original failure or read permission.
      const value = Reflect.apply(describeExecutionFailure, moon, [cause]);
      return typeof value === 'string' ? value : undefined;
    },
    seal(name, bodyWire, limits) {
      limits = captureContractLimits(limits, 'publication contract');
      return inspect(checked(moon.strategyPublicationSeal(
        name,
        bodyWire,
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      )), limits);
    },
    // Data-only private retention parser; no resource/custody/current grant.
    privateContinuationRetentionShape: moon.clientProgramPrivateContinuationRetentionShape,
    admit(name, completeWire, limits) {
      limits = captureContractLimits(limits, 'publication contract');
      return inspect(checked(moon.strategyPublicationAdmit(
        name,
        completeWire,
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      )), limits);
    },
    // SAME private opaque contract and original READ capacity. These are
    // representation observations, not copied DATA admission or authority.
    retainResultReadMetadata(parent, input, slot, original, mode) {
      const value = tokens.get(original);
      if (value === undefined) throw new TypeError('Foreign publication contract');
      return checked(moon.clientProgramRetainRequestResultMetadataContract(parent, input, slot, value, mode));
    },
    admitOriginal(original, limits) {
      const retained = contractBounds.get(original);
      if (retained === undefined || !tokens.has(original)) return undefined;
      const required = captureContractLimits(limits, 'publication contract');
      return retained.maxWireBytes <= required.maxWireBytes &&
        retained.maxNodes <= required.maxNodes &&
        retained.maxDepth <= required.maxDepth ? original : undefined;
    },
    preparedClientNormalizationEvidence(prepared, limits) {
      issuanceLimits(limits, 'Run evidence');
      // The same original already owns its measured journal. No Source read,
      // wire admission or fresh normalization occurs at publication time.
      return inspectEvidence(checked(moon.clientProgramPreparedLocalNormalizationEvidence(
        prepared, limits.maxWireBytes, limits.maxNodes, limits.maxDepth)));
    },
    preparedClientAuthoringContextEvidence(prepared, original, limits) {
      issuanceLimits(limits, 'Run evidence');
      if (original === undefined) throw new TypeError('OriginalClientAuthoringContextRequired');
      return inspectEvidence(checked(moon.clientProgramPreparedAuthoringContextEvidence(
        prepared, original, limits.maxWireBytes, limits.maxNodes, limits.maxDepth)));
    },
    sealRunEvidence(name, bodyWire, limits) {
      issuanceLimits(limits, 'Run evidence');
      return inspectEvidence(checked(moon.strategyRunEvidenceSeal(
        name,
        bodyWire,
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      )));
    },
    admitRunEvidence(name, completeWire, limits) {
      issuanceLimits(limits, 'Run evidence');
      return inspectEvidence(checked(moon.strategyRunEvidenceAdmit(
        name,
        completeWire,
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      )));
    },
    issueRunInvocation(template, observation, limits) {
      limits = captureContractLimits(limits, 'Run Invocation');
      return inspect(checked(moon.strategyIssueRunInvocation(
        evidenceToken(template),
        evidenceToken(observation),
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      )), limits);
    },
    admitRunPublication(template, prepared, authorization, compiledPlan) {
      return inspectAdmission(checked(moon.strategyRunPublicationAdmit(
        evidenceToken(template),
        evidenceToken(prepared),
        evidenceToken(authorization),
        token(compiledPlan),
      )));
    },
    admitCheckedClientRunPublication(
      checkedProgram, template, prepared, authorization, compiledPlan,
    ) {
      if (typeof moon.clientProgramAdmitPublication !== 'function') {
        throw new TypeError('Client Program admission is unavailable');
      }
      const admission = moon.clientProgramAdmitPublication(
        checkedProgram,
        evidenceToken(template),
        evidenceToken(prepared),
        evidenceToken(authorization),
        token(compiledPlan),
      );
      if (admission === undefined) {
        throw new TypeError('Publication evidence differs from checked Program');
      }
      return inspectAdmission(admission);
    },
    ...contentInferenceControls,
    readCurrentClientRunView(runDefinition, prepared, authorization, ref, state, snapshotCid, limits) {
      if (typeof moon.clientProgramCurrentRunView !== 'function') {
        throw Object.assign(new Error('ClientOperationUnavailable'),
          {code: 'ClientOperationUnavailable'});
      }
      return compiledRunResult(moon.clientProgramCurrentRunView(
        token(runDefinition), evidenceToken(prepared), evidenceToken(authorization),
        JSON.stringify(ref), JSON.stringify(state), snapshotCid,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth),
      'RunHostInspectRejected');
    },
    readCheckedClientStaticPlan(checkedProgram, kind, limits) {
      if (!['values', 'tasks', 'effects'].includes(kind) ||
          !Number.isSafeInteger(limits?.maxWireBytes) || limits.maxWireBytes < 1 ||
          !Number.isSafeInteger(limits?.maxNodes) || limits.maxNodes < 1 ||
          !Number.isSafeInteger(limits?.maxDepth) || limits.maxDepth < 1) {
        throw new TypeError('InvalidClientStaticPlanRequest');
      }
      const compile = kind === 'effects' ? moon.clientProgramCompileLocalEffects
        : kind === 'values' ? moon.clientProgramCompileLocalValues
          : moon.clientProgramCompileLocalTasks;
      const project = kind === 'effects' ? moon.clientProgramEffectfulStaticPlanView
        : kind === 'values' ? moon.clientProgramValuesStaticPlanView
          : moon.clientProgramTaskStaticPlanView;
      if (typeof compile !== 'function' || typeof project !== 'function') {
        throw Object.assign(new Error('ClientOperationUnavailable'),
          {code: 'ClientOperationUnavailable'});
      }
      // Compile the original checked owner only. In particular, do not issue
      // an allowed Run, allocate a request identity or open an execution.
      const compiled = compiledRunResult(compile(checkedProgram),
        'RunHostCompilationRejected');
      return compiledRunResult(project(checkedProgram, compiled,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth),
      'RunHostStaticPlanRejected');
    },
    prepareClientLogicalObservation(run, executionOwner, definition, limits) {
      issuanceLimits(limits, 'Original logical boundary');
      const compiled = compiledRunTokens.get(executionOwner?.compiled);
      const prepared = executionOwner?.program;
      if (compiled === undefined || prepared === undefined ||
          !moon.clientProgramCompiledRunMatches(compiled, prepared) ||
          !moon.clientProgramCheckCompiledRunDefinition(compiled, token(definition))) {
        throw new TypeError('Foreign Client logical boundary original');
      }
      if (typeof prepareLogicalObservation !== 'function') {
        throw new TypeError('ClientLogicalObservationUnavailable');
      }
      // Keep this actual typed Result intact so the receiving owner can take
      // its original failed-constructor cleanup token without parsing Errors.
      return Reflect.apply(prepareLogicalObservation, moon,
        [run, prepared, compiled, token(definition), limits.maxWireBytes,
          limits.maxNodes, limits.maxDepth]);
    },
    captureOriginalClientRunPlan(compiled, original, definition, limits, explanation) {
      issuanceLimits(limits, 'Original Run plan');
      if (limits.maxWireBytes < 1 || limits.maxNodes < 1 || limits.maxDepth < 1) {
        throw new TypeError('Invalid Original Run plan issuance limits');
      }
      const value = compiledRunTokens.get(compiled);
      if (value === undefined ||
          !moon.clientProgramCompiledRunMatches(value, original) ||
          !moon.clientProgramCheckCompiledRunDefinition(value, token(definition))) {
        throw new TypeError('Foreign Client original plan compilation');
      }
      if (typeof moon.clientProgramCompiledRunStaticPlanView !== 'function') {
        throw Object.assign(new Error('ClientOperationUnavailable'), {code: 'ClientOperationUnavailable'});
      }
      let wire;
      if (explanation === undefined) {
        wire = compiledRunResult(moon.clientProgramCompiledRunStaticPlanView(
          value, original, limits.maxWireBytes, limits.maxNodes, limits.maxDepth),
        'RunHostOriginalPlanRejected');
      } else {
        if (explanation.preparation === undefined || explanation.scope !== undefined ||
            typeof captureRequestExplanation !== 'function' ||
            typeof originalExplanationPlanWire !== 'function' ||
            typeof originalExplanationFactsWire !== 'function' ||
            typeof returnExplanationCapture !== 'function') {
          throw new TypeError('Foreign Client original explanation preparation');
        }
        // Retain in the SAME managed Run before another current getter can
        // fail. The Core issuer validates the actual Request/Run/compiler;
        // neither this record nor equal wires supplies admission authority.
        explanation.scope = compiledRunResult(Reflect.apply(captureRequestExplanation, moon, [
          explanation.preparation, value, token(definition)]), 'RunHostOriginalExplanationRejected');
        explanation.preparation = undefined;
        wire = compiledRunResult(Reflect.apply(originalExplanationPlanWire, moon, [
          explanation.scope]), 'RunHostOriginalExplanationRejected');
        explanation.factsWire = compiledRunResult(Reflect.apply(originalExplanationFactsWire, moon, [
          explanation.scope]), 'RunHostOriginalExplanationRejected');
        if (typeof explanation.factsWire !== 'string' ||
            Buffer.byteLength(explanation.factsWire) > limits.maxWireBytes) {
          throw new TypeError('Invalid Client original explanation evidence');
        }
      }
      if (typeof compiled.compiledPlan.wire !== 'string' || typeof wire !== 'string' ||
          Buffer.byteLength(compiled.compiledPlan.wire) > limits.maxWireBytes ||
          Buffer.byteLength(wire) > limits.maxWireBytes) {
        throw new TypeError('Invalid Client original plan evidence');
      }
      const originalBytes = Object.freeze({compiledPlanWire: compiled.compiledPlan.wire,
        planViewWire: wire});
      const programCid = moon.clientProgramDefinitionCid(original);
      // The nominal compiler projection already bound its map to this Plan
      // and Program. Capture those immutable outputs, not a second stored-input
      // admission. Independent durable reads still use the full reader below.
      const selected = Object.freeze({});
      const retained = {original: originalBytes,
        runDefinitionCid: definition.identity, programCid,
        prepared: compiled.preparedEvidence.wire, authorization: compiled.authorization.wire};
      if (explanation !== undefined) retained.explanation = explanation;
      originalRunPlanTokens.set(selected, Object.freeze(retained));
      return selected;
    },
    captureOriginalEffectRunPlan(explanation, definition, prepared, evidence) {
      token(definition);
      if (explanation.scope === undefined || explanation.plan === undefined ||
          moon.strategyPublicationContractIdentity(explanation.definition) !== definition.identity ||
          moon.strategyPublicationContractJson(explanation.definition) !== definition.wire) {
        throw new TypeError('Foreign Client original Effect plan admission');
      }
      const selected = Object.freeze({});
      originalRunPlanTokens.set(selected, Object.freeze({explanation,
        runDefinitionCid: definition.identity, programCid: moon.clientProgramEffectDefinitionCid(prepared),
        prepared: evidence.prepared, authorization: evidence.authorization}));
      return selected;
    },
    originalRunPlanAdmissionEvidence(selected, definition, programCid, evidence) {
      const retained = originalRunPlanTokens.get(selected);
      // Exact first-admission provenance is independent of current read or
      // control permission. A copied wire/CID cannot create this selection.
      token(definition);
      if (retained === undefined || retained.runDefinitionCid !== definition.identity ||
          retained.programCid !== programCid || retained.prepared !== evidence?.prepared ||
          retained.authorization !== evidence?.authorization) {
        throw new TypeError('Foreign Client original plan admission');
      }
      return retained.original ?? retained.explanation?.plan;
    },
    originalRunExplanationAdmissionEvidence(selected, definition, programCid, evidence) {
      // Reuse the existing nominal original-Plan selection, not another
      // identity registry or a caller's structural wire/CID.
      control.originalRunPlanAdmissionEvidence(selected, definition, programCid, evidence);
      const explanation = originalRunPlanTokens.get(selected).explanation;
      if (explanation === undefined || explanation.acknowledged ||
          typeof explanation.factsWire !== 'string' || explanation.scope === undefined) {
        throw new TypeError('Foreign Client original explanation admission');
      }
      explanation.offered = true;
      return Object.freeze(explanation.definition === undefined ? {factsWire: explanation.factsWire} : {
        factsWire: explanation.factsWire, contextWire: explanation.contextWire,
        invocationTemplateWire: explanation.invocationTemplateWire,
      });
    },
    originalRunExplanationAdmissionAcknowledged(selected, definition, programCid, evidence) {
      control.originalRunPlanAdmissionEvidence(selected, definition, programCid, evidence);
      const explanation = originalRunPlanTokens.get(selected).explanation;
      if (explanation === undefined || !explanation.offered) {
        throw new TypeError('Foreign Client original explanation acknowledgement');
      }
      if (explanation.acknowledged && (explanation.scope === undefined || explanation.dispatchReady)) return;
      if (explanation.returning) throw new TypeError('RunHostOriginalExplanationCleanupPending');
      // The Journal has already dropped its transient Facts aliases after
      // actual COMMIT. Cut the last new managed payload BEFORE lower return
      // can settle/refund; retain the exact cleanup token on a declined return.
      explanation.factsWire = undefined;
      explanation.journal = undefined;
      explanation.acknowledged = true;
      explanation.returning = true;
      try {
        if (explanation.definition !== undefined) {
          explanation.contextWire = explanation.invocationTemplateWire = explanation.plan = undefined;
          compiledRunResult(explanation.methods.returnCapture(explanation.scope, explanation.definition, false),
            'RunHostOriginalExplanationCleanupPending');
          explanation.scope = undefined;
        } else if (typeof acknowledgeExplanationCapture === 'function') {
          // The existing manager owns this SAME borrow through execution.
          // Journal ACK drops only committed payload aliases, not that owner.
          compiledRunResult(Reflect.apply(acknowledgeExplanationCapture, moon, [
            explanation.scope]), 'RunHostOriginalExplanationCleanupPending');
          explanation.dispatchReady = true;
        } else {
          // Old namespaces cannot supply a post-ACK original observation.
          compiledRunResult(Reflect.apply(returnExplanationCapture, moon, [
            explanation.scope]), 'RunHostOriginalExplanationCleanupPending');
          explanation.scope = undefined;
        }
      } finally {explanation.returning = false;}
    },
    originalClientDispatchFailureAvailable(selected) {
      // Facility DATA only: the actual read still checks current and the SAME
      // Core owners. Unselected/old profiles allocate no observation callback.
      const explanation = originalRunPlanTokens.get(selected)?.explanation;
      return explanation?.dispatchReady === true && !explanation.returning &&
        explanation.scope !== undefined && typeof observeOriginalDispatchFailure === 'function';
    },
    observeOriginalClientDispatchFailure(selected, host) {
      const explanation = originalRunPlanTokens.get(selected)?.explanation;
      if (explanation?.dispatchReady !== true || explanation.returning ||
          explanation.scope === undefined || typeof observeOriginalDispatchFailure !== 'function') return undefined;
      return checked(Reflect.apply(observeOriginalDispatchFailure, moon, [explanation.scope, host]));
    },
    readStoredRunPlanOriginal(original, definition, programCid, limits) {
      token(definition);
      issuanceLimits(limits, 'Original Run plan');
      if (original === null || typeof original !== 'object' || Array.isArray(original) ||
          Object.keys(original).sort().join(',') !== 'compiledPlanWire,planViewWire' ||
          limits.maxWireBytes < 1 || limits.maxNodes < 1 || limits.maxDepth < 1 ||
          ['compiledPlanWire', 'planViewWire'].some(field =>
            typeof original[field] !== 'string' || Buffer.byteLength(original[field]) > limits.maxWireBytes)) {
        throw new TypeError('Invalid Client original plan evidence');
      }
      const plan = control.admit('compiled_plan', original.compiledPlanWire, limits);
      const view = JSON.parse(original.planViewWire);
      if (!validWirePlanViewShape(view) ||
          plan.identity !== JSON.parse(definition.wire).compiled_plan_cid ||
          view.compiled_plan_cid !== plan.identity ||
          JSON.parse(plan.wire).program_definition_cid !== programCid) {
        throw new TypeError('Foreign Client original plan evidence');
      }
      if (typeof moon.clientProgramCheckLogicalMapBinding !== 'function') {
        throw Object.assign(new Error('ClientOperationUnavailable'), {code: 'ClientOperationUnavailable'});
      }
      const map = control.admitRunEvidence('logical_map', JSON.stringify(view.logical_map), limits);
      compiledRunResult(moon.clientProgramCheckLogicalMapBinding(evidenceToken(map), token(plan),
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth), 'RunHostOriginalMapRejected');
      return original.planViewWire;
    },
    // First admission retains only the actual compiler owner and its original
    // Result policy. A copied wire cannot supply the journal's original ticket.
    captureOriginalClientInferRun(compiled, checkedProgram, definition, request, environment, parameters, funded) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer' ||
          !moon.clientProgramCompiledRunMatches(value, checkedProgram) ||
          !moon.clientProgramMatchesRequestIdentity(checkedProgram, request) ||
          !moon.clientProgramCheckCompiledRunDefinition(value, token(definition))) {
        throw new TypeError('Foreign Client original Infer Run');
      }
      const resultPolicyOriginal = control.compiledInferEvaluationPolicy(compiled);
      if (resultPolicyOriginal === undefined) throw new TypeError('Missing Client original Infer Result policy');
      // Installed capture has a required same-Request constructor. A missing
      // funded port must never fall back to the standalone wire projection.
      let materialsWire;
      if (funded === undefined) {
        materialsWire = compiledRunResult(moon.clientProgramIssueInferRunMaterials(
          value, token(definition), environment, parameters), 'RunHostInferMaterialsRejected');
      } else {
        if (funded?.parent === undefined || funded.input === undefined ||
            typeof moon.clientProgramIssueRequestInferRunMaterials !== 'function') {
          throw new TypeError('Missing Client original Infer material reservation');
        }
        materialsWire = compiledRunResult(moon.clientProgramIssueRequestInferRunMaterials(
          funded.parent, funded.input, value, token(definition)), 'RunHostInferMaterialsRejected');
      }
      const selected = Object.freeze({});
      originalInferRunTokens.set(selected, Object.freeze({
        original: Object.freeze({materialsWire, resultPolicyOriginal}),
        runDefinitionCid: definition.identity,
        request,
        prepared: compiled.preparedEvidence.wire, authorization: compiled.authorization.wire,
      }));
      return selected;
    },
    originalInferRunAdmissionEvidence(selected, definition, request, evidence) {
      const retained = originalInferRunTokens.get(selected);
      token(definition);
      if (retained === undefined || retained.runDefinitionCid !== definition.identity ||
          retained.request !== request || retained.prepared !== evidence?.prepared ||
          retained.authorization !== evidence?.authorization) {
        throw new TypeError('Foreign Client original Infer admission');
      }
      return retained.original;
    },
    // The same journal's already selected Run supplies the expected original.
    // Current installation, authority and physical input custody are not read or
    // issued here. The returned preparation and graph must stay together.
    admitStoredClientInferRunOriginal(original, definition, request, evidence, profiles, limits, recovery) {
      token(definition);
      issuanceLimits(limits, 'Original Infer Run');
      const keys = original === null || typeof original !== 'object' || Array.isArray(original)
        ? [] : Object.keys(original);
      if (keys.length !== 2 || !keys.includes('materialsWire') || !keys.includes('resultPolicyOriginal') ||
          typeof original.materialsWire !== 'string' || original.materialsWire.length === 0 ||
          Buffer.byteLength(original.materialsWire) > limits.maxWireBytes ||
          !Array.isArray(profiles) || profiles.length !== 7 || profiles.some(value => typeof value !== 'boolean')) {
        throw new TypeError('Invalid Client original Infer materials');
      }
      // A Source-backed Run retains its checked publication policy, not the
      // source-free unknown policy. This copy is evidence only: after restoring
      // the original compiler Owner, compare its complete policy below.
      const savedPolicy = original.resultPolicyOriginal;
      if (savedPolicy === null || typeof savedPolicy !== 'object' || Array.isArray(savedPolicy) ||
          Object.keys(savedPolicy).sort().join(',') !== 'cid,kind,wire' ||
          savedPolicy.kind !== 'data_policy' || typeof savedPolicy.cid !== 'string' ||
          typeof savedPolicy.wire !== 'string' || savedPolicy.wire.length === 0 ||
          Buffer.byteLength(savedPolicy.cid) > limits.maxWireBytes ||
          Buffer.byteLength(savedPolicy.wire) > limits.maxWireBytes) {
        throw new TypeError('Invalid Client original Infer Result policy');
      }
      const policy = Object.freeze({kind: savedPolicy.kind, cid: savedPolicy.cid, wire: savedPolicy.wire});
      let materials, authoringContextOriginal;
      if (recovery === undefined) {
        // Existing explicit standalone consumers retain their separate path.
        materials = compiledRunResult(moon.clientProgramAdmitInferRunMaterials(
          original.materialsWire, definition.identity, ...profiles), 'RunHostInferMaterialsRejected');
      } else {
        const admit = moon.clientProgramAdmitRequestInferRunMaterials;
        if (typeof admit !== 'function' || recovery.parent === undefined || recovery.input === undefined) {
          throw new TypeError('Installed Model recovery material constructor unavailable');
        }
        const originals = compiledRunResult(Reflect.apply(admit, moon, [
          recovery.parent, recovery.input, request, token(definition), original.materialsWire, ...profiles,
        ]), 'RunHostInferMaterialsRejected');
        materials = runtimeField(originals, 0);
        authoringContextOriginal = runtimeField(originals, 1);
        if (materials === undefined || authoringContextOriginal === undefined) {
          throw new TypeError('Missing Client original Infer material custody');
        }
      }
      let value = compiledRunResult(moon.clientProgramInferRunMaterialsCompiled(materials),
        'RunHostInferMaterialsRejected');
      const prepared = moon.clientProgramInferRunMaterialsPrepared(materials);
      const graphs = typeof moon.clientProgramInferRunMaterialsGraphs === 'function'
        ? moon.clientProgramInferRunMaterialsGraphs(materials)
        : [moon.clientProgramInferRunMaterialsGraph(materials)];
      if (!Array.isArray(graphs) || graphs.length < 1 || graphs.length > 128 ||
          graphs.some(graph => graph === undefined || graph === null) ||
          !moon.clientProgramMatchesRequestIdentity(prepared, request) ||
          !moon.clientProgramCheckCompiledRunDefinition(value, token(definition)) ||
          inspectEvidence(moon.clientProgramCompiledRunPrepared(value)).wire !== evidence?.prepared ||
          inspectEvidence(moon.clientProgramCompiledRunAuthorization(value)).wire !== evidence?.authorization) {
        throw new TypeError('Foreign Client original Infer materials');
      }
      value = compiledRunResult(moon.clientProgramBindCompiledInferResultPolicy(value,
        policy.cid, policy.wire, limits.maxWireBytes, limits.maxNodes, limits.maxDepth),
      'RunHostResultPolicyRejected');
      const actualPolicy = moon.clientProgramCompiledRunEvaluationPolicy(value);
      if (actualPolicy === undefined || runtimeField(actualPolicy, 0) !== policy.kind ||
          runtimeField(actualPolicy, 1) !== policy.cid || runtimeField(actualPolicy, 2) !== policy.wire) {
        throw new TypeError('Foreign Client original Infer Result policy');
      }
      const compiled = Object.freeze({kind: 'infer',
        template: inspectEvidence(moon.clientProgramCompiledRunTemplate(value)),
        compiledPlan: inspect(moon.clientProgramCompiledRunPlan(value)),
        preparedEvidence: inspectEvidence(moon.clientProgramCompiledRunPrepared(value)),
        authorization: inspectEvidence(moon.clientProgramCompiledRunAuthorization(value)),
        admission: inspectAdmission(moon.clientProgramCompiledRunAdmission(value))});
      compiledRunTokens.set(compiled, value);
      // The copied outer inventory is metadata for these same opaque members.
      // It grants no new preparation, current authority, budget or execution.
      const graph = graphs.length === 1 ? graphs[0] : Object.freeze([...graphs]);
      const restored = Object.freeze({compiled, prepared, graph, runDefinition: definition,
        ...(authoringContextOriginal === undefined ? {} : {authoringContextOriginal})});
      restoredInferRuns.add(restored);
      return restored;
    },
    checkRestoredClientInferRunOwner(restored, checkedProgram) {
      if (!restoredInferRuns.has(restored) || restored.prepared !== checkedProgram) {
        throw new TypeError('Foreign Client restored Infer Run');
      }
      control.checkClientCompiledRunOwner(restored.compiled, checkedProgram);
      return restored;
    },
    checkedClientCompiledInferOriginal(compiled, checkedProgram, definition) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer' ||
          !moon.clientProgramCheckCompiledRunDefinition(value, token(definition))) {
        throw new TypeError('Foreign Client original Infer compilation');
      }
      const original = moon.clientProgramCompiledInferOriginal(value, checkedProgram);
      if (original === undefined) throw new TypeError('Foreign Client original Infer preparation');
      return Object.freeze({graph: runtimeField(original, 0), execution: runtimeField(original, 1)});
    },
    checkedClientCompiledInferOriginals(compiled, checkedProgram, definition) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer' ||
          !moon.clientProgramCheckCompiledRunDefinition(value, token(definition)) ||
          typeof moon.clientProgramCompiledInferOriginals !== 'function') {
        throw new TypeError('Foreign Client original Infer compilation');
      }
      const originalOption = moon.clientProgramCompiledInferOriginals(value, checkedProgram);
      // This exact export specializes Option<Array<Tuple>> as a boxed Option.
      // The singular tuple export above has a different, unboxed layout.
      const originals = runtimeIsBoxedSome(originalOption)
        ? runtimeField(originalOption, 0) : undefined;
      if (!Array.isArray(originals) || originals.length < 1 || originals.length > 128 ||
          originals.some(original => runtimeField(original, 0) === undefined ||
            runtimeField(original, 1) === undefined)) {
        throw new TypeError('Foreign Client original Infer preparation');
      }
      return Object.freeze(originals.map(original => Object.freeze({
        graph: runtimeField(original, 0), execution: runtimeField(original, 1)})));
    },
    prepareCheckedClientCompiledRun(checkedProgram, kind, policy, inferGraph, compilationOriginal) {
      if (!['values', 'tasks', 'infer', 'serialization'].includes(kind)) {
        throw new TypeError('Invalid Client compilation profile');
      }
      if ((kind === 'infer' || kind === 'serialization') !== (inferGraph !== undefined)) {
        throw new TypeError(kind === 'serialization'
          ? 'Content compilation requires its checked graph'
          : 'Infer compilation requires its checked graph');
      }
      const serializationGraph = kind === 'serialization'
        ? serializationPlanTokens.get(inferGraph) : undefined;
      if (kind === 'serialization' && serializationGraph === undefined) {
        throw new TypeError('Foreign Content compilation graph');
      }
      // The existing typed issuer below binds this artifact to the SAME
      // checked Program. A refused original never falls back to compilation.
      const compilation = compilationOriginal !== undefined ? compilationOriginal : compiledRunResult(kind === 'values'
        ? moon.clientProgramCompileLocalValues(checkedProgram)
        : kind === 'serialization'
          ? moon.clientProgramCompileLocalSerialization(checkedProgram, serializationGraph)
        : kind === 'infer'
          ? Array.isArray(inferGraph)
            ? moon.clientProgramCompileLocalInfers(checkedProgram, inferGraph)
            : moon.clientProgramCompileLocalInfer(checkedProgram, inferGraph)
          : moon.clientProgramCompileLocalTasks(checkedProgram),
      kind === 'values' ? 'RunHostCompilationRejected'
        : 'RunHostTaskCompilationRejected');
      // Pure staged originals use the existing Values/Tasks sum. The Request
      // Model compiler instead returns the original raw TaskCompilation;
      // its existing typed issuer validates that original and owner directly.
      // Unmigrated explicit compilation keeps its separate raw artifact entry.
      let value = compiledRunResult(compilationOriginal !== undefined
        ? kind === 'values'
          ? moon.clientProgramIssueOriginalValuesCompiledRun(checkedProgram,
            compilation, policy.executionContextCid, policy.hostPolicyCid,
            policy.expiresAt)
          : kind === 'infer' || kind === 'serialization'
            ? moon.clientProgramIssueTaskCompiledRun(checkedProgram,
              compilation, policy.executionContextCid, policy.hostPolicyCid,
              policy.expiresAt)
          : moon.clientProgramIssueOriginalTaskCompiledRun(checkedProgram,
            compilation, policy.executionContextCid, policy.hostPolicyCid,
            policy.expiresAt)
        : kind === 'values'
          ? moon.clientProgramIssueValuesCompiledRun(checkedProgram,
            compilation, policy.executionContextCid, policy.hostPolicyCid,
            policy.expiresAt)
          : moon.clientProgramIssueTaskCompiledRun(checkedProgram,
            compilation, policy.executionContextCid, policy.hostPolicyCid,
            policy.expiresAt), 'RunHostAdmissionRejected');
      if (kind === 'serialization' && compilationOriginal !== undefined &&
          moon.clientProgramCompiledRunSerializationGraph(value) !== serializationGraph) {
        throw new TypeError('Foreign Content compilation graph');
      }
      if (kind === 'infer') {
        const original = policy.resultDataPolicy;
        if (original?.kind !== 'data_policy' || typeof original.cid !== 'string' ||
            typeof original.wire !== 'string') throw new TypeError('InvalidHostResultDataPolicy');
        value = compiledRunResult(moon.clientProgramBindCompiledInferResultPolicy(
          value, original.cid, original.wire, 1000000, 100000, 64),
        'RunHostResultPolicyRejected');
      }
      const result = Object.freeze({
        kind,
        template: inspectEvidence(moon.clientProgramCompiledRunTemplate(value)),
        compiledPlan: inspect(moon.clientProgramCompiledRunPlan(value)),
        preparedEvidence: inspectEvidence(
          moon.clientProgramCompiledRunPrepared(value)),
        authorization: inspectEvidence(
          moon.clientProgramCompiledRunAuthorization(value)),
        admission: inspectAdmission(
          moon.clientProgramCompiledRunAdmission(value)),
      });
      compiledRunTokens.set(result, value);
      return result;
    },
    admitSourceFreeResultPolicy(resultPolicy, limits) {
      if (resultPolicy?.kind !== 'data_policy' ||
          typeof resultPolicy.cid !== 'string' ||
          typeof resultPolicy.wire !== 'string' ||
          !Number.isSafeInteger(limits?.maxWireBytes) ||
          !Number.isSafeInteger(limits?.maxNodes) ||
          !Number.isSafeInteger(limits?.maxDepth)) {
        throw new TypeError('InvalidHostResultDataPolicy');
      }
      const original = checked(moon.clientProgramAdmitSourceFreeResultPolicyBody(
        resultPolicy.cid, resultPolicy.wire,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      return Object.freeze({kind: runtimeField(original, 0), cid: runtimeField(original, 1),
        wire: runtimeField(original, 2)});
    },
    adoptCheckedClientEffectInferRun(allowed, definition, resultPolicy, limits) {
      if (resultPolicy !== undefined &&
          (resultPolicy?.kind !== 'data_policy' ||
           typeof resultPolicy.cid !== 'string' ||
           typeof resultPolicy.wire !== 'string' ||
           !Number.isSafeInteger(limits?.maxWireBytes) ||
           !Number.isSafeInteger(limits?.maxNodes) ||
           !Number.isSafeInteger(limits?.maxDepth))) {
        throw new TypeError('InvalidHostResultDataPolicy');
      }
      const value = checked(resultPolicy === undefined
        ? moon.clientProgramEffectAllowedInferRun(allowed)
        : moon.clientProgramEffectAllowedInferRunWithPolicyBody(
          allowed, resultPolicy.cid, resultPolicy.wire,
          limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      if (!moon.clientProgramCheckCompiledRunDefinition(value, token(definition))) {
        throw new TypeError('Effect Infer Run Definition differs from admission');
      }
      const result = Object.freeze({kind: 'infer',
        template: inspectEvidence(moon.clientProgramCompiledRunTemplate(value)),
        compiledPlan: inspect(moon.clientProgramCompiledRunPlan(value)),
        preparedEvidence: inspectEvidence(moon.clientProgramCompiledRunPrepared(value)),
        authorization: inspectEvidence(moon.clientProgramCompiledRunAuthorization(value)),
        admission: inspectAdmission(moon.clientProgramCompiledRunAdmission(value))});
      compiledRunTokens.set(result, value);
      return result;
    },
    compiledSourceFreeResultPolicy,
    // Borrow the checked Source-only Effect component from this exact keyed
    // plan and admitted Definition. A Model graph or an equal wire cannot
    // supply this nominal association, and this projection issues no Run.
    adoptCheckedClientEffectKeyedRun(allowed, definition, keyedPlan) {
      const value = compiledRunResult(moon.clientProgramEffectAllowedKeyedRun(
        allowed, keyedPlan, token(definition)), 'RunHostEffectKeyedAdmissionRejected');
      if (!moon.clientProgramCheckCompiledRunDefinition(value, token(definition))) {
        throw new TypeError('Effect keyed Run Definition differs from admission');
      }
      // The original acquired tuple already retains all publication bodies.
      // This private adapter token only borrows the nominal component; avoid
      // decoding those same immutable bodies to manufacture another tuple.
      const result = Object.freeze({kind: 'effect-keyed'});
      compiledRunTokens.set(result, value);
      return result;
    },
    bindCheckedClientRequestEffectKeyedOriginal(parent, input, operationPlan, compilation,
      compiled, definition, keyedPlan, keyed, construct) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'effect-keyed' || typeof construct !== 'function') {
        throw new TypeError('Foreign Client compiled keyed Effect preparation');
      }
      return checked(construct(parent, input, operationPlan, compilation,
        value, token(definition), keyedPlan, keyed));
    },
    startInstalledEffectKeyedCaptureInput(managedRun, prepared, request, compiled,
      definition, keyedPlan, keyed, captures, limits) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'effect-keyed' ||
          !Array.isArray(captures) || captures.some(value =>
            typeof (value.inputKind === 'whole-input'
              ? value.capture?.originalWholeInput : value.capture?.originalRowCapture) !== 'function')) {
        throw new TypeError('Foreign original keyed Effect capture');
      }
      return checked(moon.clientProgramStartInstalledEffectKeyedCaptureInput(
        managedRun, prepared, request, value, token(definition), keyedPlan, keyed,
        captures.map(value => value.inputKind === 'whole-input'
          ? value.capture.originalWholeInput() : value.capture.originalRowCapture()),
        limits.maxEntries, limits.maxNameBytes, limits.maxBytes, limits.maxWork));
    },
    // Borrow the original admitted Effect compilation. No fresh Program,
    // authorization, Source observation or Command approval is issued here.
    ...contentPublicationControls,
    compiledInferSourceFreeResultPolicy: compiledSourceFreeResultPolicy,
    compiledInferEvaluationPolicy(compiled) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined) throw new TypeError('Foreign Client compiled Run');
      const original = moon.clientProgramCompiledRunEvaluationPolicy(value);
      return original === undefined ? undefined : Object.freeze({
        kind: runtimeField(original, 0), cid: runtimeField(original, 1), wire: runtimeField(original, 2),
      });
    },
    checkClientCompiledRunOwner(compiled, checkedProgram) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined ||
          !moon.clientProgramCompiledRunMatches(value, checkedProgram)) {
        throw new TypeError('Foreign Client compiled Run');
      }
    },
    checkClientCompiledEffectRunOwner(compiled, prepared, compilation) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined ||
          moon.clientProgramCompiledRunEffectMatches(value, prepared, compilation) !== true) {
        throw new TypeError('Foreign Client compiled Run');
      }
    },
    checkClientCompiledRunDefinition(compiled, definition) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || !moon.clientProgramCheckCompiledRunDefinition(value, token(definition))) {
        throw new TypeError('Foreign Client compiled Run Definition');
      }
    },
    checkClientCompiledLocalExecutionOwner(compiled, definition) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined ||
          moon.clientProgramCheckCompiledLocalExecutionOwner(value, token(definition)) !== true) {
        throw new TypeError('Foreign Client local execution owner');
      }
    },
    checkedClientRunCapturedContentCandidate(compiled, definition, acquisition, request,
      bindingWire, mediaType, contentCid, sizeBytes, limits) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined) throw new TypeError('Foreign Client compiled Run');
      return checked(moon.clientProgramRunCapturedContentCandidate(value, token(definition),
        acquisition, request, bindingWire, mediaType, contentCid, sizeBytes, ...limits));
    },
    checkedClientStoredRunCapturedContentCandidate(compiled, definition, acquisition,
      originalWire, bindingWire, limits) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined) throw new TypeError('Foreign Client compiled Run');
      return checked(moon.clientProgramStoredRunCapturedContentCandidate(value,
        token(definition), acquisition, originalWire, bindingWire, ...limits));
    },
    recoveredContentIssuerKind(wire, limits) {
      if (typeof wire !== 'string' || !['maxBytes', 'maxNodes', 'maxDepth', 'maxTextUnits']
        .every(key => Number.isInteger(limits?.[key]) && limits[key] > 0 && limits[key] <= 2147483647)) {
        throw new TypeError('Invalid recovered Content reference limits');
      }
      return checked(moon.clientProgramRecoveredContentIssuerKind(wire,
        limits.maxBytes, limits.maxNodes, limits.maxDepth, limits.maxTextUnits));
    },
    recoveredSourceContentConstructionCapacity(wire, bindingWire, limits, role = 'metadata') {
      if (typeof wire !== 'string' || typeof bindingWire !== 'string' ||
          typeof role !== 'string' ||
          !['maxBytes', 'maxNodes', 'maxDepth', 'maxTextUnits'].every(key =>
            Number.isInteger(limits?.[key]) && limits[key] > 0 && limits[key] <= 2147483647)) {
        throw new TypeError('Invalid recovered Source Content construction limits');
      }
      const capacity = moon.clientProgramRecoveredSourceContentConstructionCapacity(
        wire, bindingWire, limits.maxBytes, limits.maxNodes, limits.maxDepth, limits.maxTextUnits, role);
      if (capacity === undefined) throw new TypeError('Recovered Source Content construction unavailable');
      return capacity;
    },
    installedEffectKeyedOriginal(managedContext, prepared) {
      if (managedContext?.runtime !== moon || managedContext.closed ||
          managedContext.prepared !== prepared || managedContext.value === undefined ||
          managedContext.request === undefined) {
        throw new TypeError('Foreign recovered Effect Source original');
      }
      return checked(moon.clientProgramInstalledEffectKeyedOriginal(
        managedContext.value, prepared, managedContext.request));
    },
    effectKeyedOriginalSourceEvidenceFacts(original, prepared, request) {
      const facts = checked(moon.clientProgramEffectKeyedOriginalSourceEvidenceFacts(
        original, prepared, request));
      if (!Array.isArray(facts) || facts.length !== 6 ||
          !facts.every(value => typeof value === 'string')) {
        throw new TypeError('Invalid recovered Effect Source facts');
      }
      return facts;
    },
    checkedRecoveredSourceContentCandidate(original, prepared, request,
      referenceWire, bindingWire, limits) {
      return checked(moon.clientProgramRecoveredSourceContentCandidate(original,
        prepared, request, referenceWire, bindingWire, ...limits));
    },
    compiledRunResultTransformation(compiled, checkedProgram, result) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || !Number.isSafeInteger(result) || result < 0) {
        throw new TypeError('Foreign Client compiled Result');
      }
      return compiledRunResult(
        moon.clientProgramCompiledRunResultTransformation(
          value, checkedProgram, result), 'RunHostResultSelectionRejected');
    },
    ...queryTimeControls,
    defineCheckedClientCompiledRun(compiled, {namespaceId, runId,
      createdAt, validUntil, retainedDefinitionWire}) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined) {
        throw new TypeError('Foreign Client compiled Run');
      }
      return inspect(compiledRunResult(retainedDefinitionWire === undefined
        ? moon.clientProgramIssueCompiledRunDefinition(value,
          namespaceId, runId, createdAt, validUntil)
        : moon.clientProgramAdmitCompiledRunDefinition(value,
          retainedDefinitionWire), compiled.kind !== 'values'
        ? 'RunHostTaskDefinitionRejected'
        : retainedDefinitionWire === undefined
          ? 'RunHostSourceFreeDefinitionRejected'
          : 'RunHostSourceFreeAdmissionRejected'));
    },
    issueCheckedClientCompiledInvocation(compiled, definition,
      {dataPolicyCid, source}, limits, publicationPreparation, preparedProgram) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined) {
        throw new TypeError('Foreign Client compiled Run');
      }
      limits = captureContractLimits(limits, 'Client Run Invocation');
      if (source !== undefined) {
        const sources = source.sources ?? [{captured: source.captured, sourceEvidence: source.sourceEvidence}];
        if (publicationPreparation === undefined || preparedProgram === undefined || compiled.kind !== 'tasks' ||
            !Array.isArray(sources) || sources.length < 1 ||
            sources.some(({captured}) => captured?.capture === undefined || captured?.identity === undefined ||
              captured?.logicalInput === undefined)) {
          throw new TypeError('Invalid original publication invocation profile');
        }
        // The adopted original Plan selects the semantic input boundary.
        // A missing/copy/foreign capture cannot fall back to a Query ABI.
        const kind = checked(moon.clientProgramInstalledManagedPublicationSourceKind(
          publicationPreparation, preparedProgram));
        if (kind === 'whole-input') {
          if (source.keyedObservation !== undefined) throw new TypeError('Invalid original publication invocation profile');
          const originals = sources.map(({captured}) => {
            if (captured.inputKind !== 'whole-input') throw new TypeError('Invalid original whole Source capture');
            const capture = captured.capture;
            const original = Object.getOwnPropertyDescriptor(capture, 'originalWholeInput');
            if (original === undefined || !Object.hasOwn(original, 'value') || typeof original.value !== 'function') {
              throw new TypeError('Invalid original whole Source capture');
            }
            return Reflect.apply(original.value, capture, []);
          });
          const originalArguments = sources.length === 1
            ? [originals[0], sources[0].captured.identity, evidenceToken(sources[0].sourceEvidence), sources[0].captured.logicalInput]
            : [originals, sources.map(({captured}) => captured.identity), sources.map(({sourceEvidence}) => evidenceToken(sourceEvidence)),
              sources.map(({captured}) => captured.logicalInput)];
          const issue = moon[sources.length === 1 ? 'clientProgramIssueWholeSourcePublicationInvocation'
            : 'clientProgramIssueWholeSourcesPublicationInvocation'];
          const issued = compiledRunResult(Reflect.apply(issue, moon, [
            publicationPreparation, preparedProgram, value, token(definition), ...originalArguments,
            source.authorityScopeCid, dataPolicyCid, source.captureStartedAt, source.captureCompletedAt,
            limits.maxWireBytes, limits.maxNodes, limits.maxDepth]), 'RunHostTaskInvocationRejected');
          return Object.freeze({observation: inspectEvidence(runtimeField(issued, 0)),
            invocation: inspect(runtimeField(issued, 1), limits), owner: runtimeField(issued, 1)});
        }
        if (kind !== 'query' || sources.some(({captured}) => captured.requirement === undefined)) {
          throw new TypeError('Invalid original publication invocation profile');
        }
        const issued = compiledRunResult(moon.clientProgramIssueCapturedPublicationInvocation(
          publicationPreparation, preparedProgram, value, token(definition),
          sources.map(({captured}) => captured.capture.source()), sources.map(({captured}) => captured.identity),
          sources.map(({captured}) => captured.requirement), sources.map(({sourceEvidence}) => evidenceToken(sourceEvidence)),
          sources.map(({captured}) => captured.logicalInput), source.keyedObservation,
          source.authorityScopeCid, dataPolicyCid, source.captureStartedAt, source.captureCompletedAt,
          limits.maxWireBytes, limits.maxNodes, limits.maxDepth), 'RunHostTaskInvocationRejected');
        return Object.freeze({observation: inspectEvidence(runtimeField(issued, 0)),
          invocation: inspect(runtimeField(issued, 1), limits), owner: runtimeField(issued, 1)});
      }
      if (publicationPreparation !== undefined && compiled.kind !== 'values' && compiled.kind !== 'tasks') {
        throw new TypeError('Invalid original publication invocation profile');
      }
      const issued = compiledRunResult(publicationPreparation !== undefined
        ? moon.clientProgramIssuePublicationInvocation(publicationPreparation,
          preparedProgram, value, token(definition), dataPolicyCid,
          limits.maxWireBytes, limits.maxNodes, limits.maxDepth)
        : (compiled.kind !== 'values'
          ? moon.clientProgramIssueCompiledSourceFreeTaskInvocation(value,
            token(definition), dataPolicyCid,
            limits.maxWireBytes, limits.maxNodes, limits.maxDepth)
          : moon.clientProgramIssueCompiledValuesInvocation(value,
            token(definition), dataPolicyCid,
            limits.maxWireBytes, limits.maxNodes, limits.maxDepth))
      , 'RunHostInvocationRejected');
      return Object.freeze({observation: inspectEvidence(runtimeField(issued, 0)),
        invocation: inspect(runtimeField(issued, 1), limits), owner: runtimeField(issued, 1)});
    },
    admitInferCapturedInput(prepared, captured, sourceEvidence, authorityScopeCid,
      dataPolicyCid, startedAt, completedAt) {
      return checked(moon.clientProgramAdmitInferCapturedInput(prepared,
        captured.inferStep, captured.capturedSource, captured.identity, captured.requirement,
        captured.logicalInput, evidenceToken(sourceEvidence), authorityScopeCid,
        dataPolicyCid, startedAt, completedAt));
    },
    admitComposedInferSources(occurrence, captures, sourceEvidence, authorityScopeCid,
      startedAt, completedAt, keyed) {
      if (captures.some(value => value.inputKind === 'whole-input')) {
        if (captures.some(value => value.inputKind !== 'whole-input' || value.wholeCapacity === undefined)) {
          throw new TypeError('Unsupported mixed original Model Source inputs');
        }
        return checked(moon.clientProgramAdmitComposedInferWholeSources(occurrence,
          captures.map(value => value.capture.source()), captures.map(value => value.identity),
          captures.map(value => value.wholeCapacity), captures.map(value => value.logicalInput),
          sourceEvidence.map(evidenceToken), authorityScopeCid, startedAt, completedAt, keyed));
      }
      return checked(moon.clientProgramAdmitComposedInferSources(occurrence,
        captures.map(value => value.capture.source()), captures.map(value => value.identity),
        captures.map(value => value.requirement), captures.map(value => value.logicalInput),
        sourceEvidence.map(evidenceToken), authorityScopeCid, startedAt, completedAt, keyed));
    },
    composedInferSourcesFor(occurrence, original) {
      return moon.clientProgramComposedInferSourcesMatch(original, occurrence) === true ? original : undefined;
    },
    startOriginalComposedKeyedPrefix(compiled, definition, graph, scope, keyed, captures, prefix) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      return checked(moon.clientProgramStartOriginalComposedKeyedPrefix(scope,
        value, token(definition), graph, keyed,
        captures.map(value => value.capture.originalRowCapture()), prefix));
    },
    startInstalledOriginalComposedKeyedPrefix(managedRun, compiled, definition, graph, scope, keyed, captures) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      if (captures.some(value => value.inputKind === 'whole-input')) {
        if (captures.some(value => value.inputKind !== 'whole-input' ||
            typeof value.capture.originalCapturedInput !== 'function')) {
          throw new TypeError('Unsupported mixed original keyed Source inputs');
        }
        return checked(moon.clientProgramStartInstalledOriginalComposedKeyedInputPrefix(managedRun,
          scope, value, token(definition), graph, keyed,
          captures.map(value => value.capture.originalCapturedInput())));
      }
      return checked(moon.clientProgramStartInstalledOriginalComposedKeyedPrefix(managedRun,
        scope, value, token(definition), graph, keyed,
        captures.map(value => value.capture.originalRowCapture())));
    },
    prepareInstalledOriginalComposedKeyedHostInput(managedRun, compiled, definition, graph, scope, keyed, captures, host) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer' || host === undefined ||
          captures.some(value => value.inputKind !== 'whole-input' ||
            typeof value.capture.originalCapturedInput !== 'function')) {
        throw new TypeError('Foreign original keyed Host prefix');
      }
      const originals = captures.map(value => value.capture.originalCapturedInput());
      const originalDefinition = token(definition);
      const left = checked(moon.clientProgramInstalledOriginalComposedKeyedHostInputLeft(
        managedRun, scope, value, originalDefinition, graph, keyed, originals, host));
      if (left !== undefined) return Object.freeze({left});
      return Object.freeze({prefix: checked(moon.clientProgramStartInstalledOriginalComposedKeyedHostPrefix(
        managedRun, scope, value, originalDefinition, graph, keyed, originals, host))});
    },
    prepareGenericEffectKeyedLookupSourceMetadata(parent, lookup, captures, sources, selection, limits) {
      limits = captureContractLimits(limits, 'generic keyed Source metadata');
      if (parent === undefined || !Array.isArray(captures) || captures.length !== 1 ||
          !Array.isArray(sources) || sources.length !== 1 || sources[0]?.captured !== captures[0] ||
          captures[0].identity === undefined || captures[0].logicalInput === undefined ||
          sources[0].sourceEvidence === undefined) {
        throw new TypeError('ForeignOriginalGenericKeyedSourceMetadata');
      }
      // Borrow these SAME typed capture/observation originals. The generic
      // Owner checks their complete retained bodies before dispatch starts.
      return checked(moon.clientProgramEffectKeyedGenericSourceMetadata(parent, lookup,
        captures[0].identity, captures[0].logicalInput, evidenceToken(sources[0].sourceEvidence),
        selection.retentionContractCid, selection.availableUntil, selection.deleteBy,
        selection.metadataDeleteBy, selection.metadataRetentionPolicyCid,
        selection.clockContractCid, limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
    },
    finishGenericEffectKeyedLookupPublicationInput(parent, lookup, observedAt, limits) {
      limits = captureContractLimits(limits, 'generic keyed Source completion');
      return checked(moon.clientProgramEffectKeyedGenericPublicationInput(parent, lookup, observedAt,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
    },
    prepareKeyedLookupSourceMetadata(lookup, request, captures, sources,
      retentionSelection, outputLimits, maxWork, limits, fileReadDeclarations) {
      limits = captureContractLimits(limits, 'keyed Source metadata');
      if (!Array.isArray(captures) || !Array.isArray(sources) || !Array.isArray(fileReadDeclarations) ||
          !Object.isFrozen(fileReadDeclarations) || captures.length < 1 ||
          captures.length !== sources.length || !validResultOutputLimits(outputLimits) ||
          !Number.isSafeInteger(maxWork) || maxWork < 1 ||
          captures.some((captured, index) => sources[index]?.captured !== captured ||
            sources[index]?.sourceEvidence === undefined)) {
        throw new TypeError('ForeignOriginalKeyedSourceMetadata');
      }
      const exported = moon.clientProgramEffectInputExportLimits(
        ...resultOutputLimitFields.map(name => outputLimits[name]));
      if (exported === undefined) throw new TypeError('Invalid original keyed input limits');
      const selected = retentionSelection;
      const retention = checked(moon.clientProgramKeyedLookupPrepareRetention(lookup,
        request, selected.retentionContractCid, selected.availableUntil, selected.deleteBy,
        selected.metadataDeleteBy, selected.metadataRetentionPolicyCid,
        selected.clockContractCid, limits.maxWireBytes));
      checked(moon.clientProgramKeyedLookupPrepareLeftIdentity(lookup, exported, maxWork));
      for (let index = 0; index < captures.length; index++) {
        const captured = captures[index], observation = evidenceToken(sources[index].sourceEvidence);
        if (captured.inputKind === 'whole-input') {
          checked(moon.clientProgramKeyedLookupBindWholeSourceMetadata(lookup, index,
            captured.identity, captured.logicalInput, observation, request, retention,
            limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
        } else {
          checked(moon.clientProgramKeyedLookupBindQuerySourceMetadata(lookup, index,
            captured.requirement, captured.identity, captured.logicalInput, observation,
            request, retention, limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
        }
      }
      checked(moon.clientProgramKeyedLookupPrepareLeftRelation(lookup, request, retention,
        moon.clientRequestAuthorityScopeCid(request),
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      checked(moon.clientProgramKeyedLookupBindDeclaredFilePhysicalSource(lookup, fileReadDeclarations));
      return inspect(retention, limits);
    },
    keyedLookupActivationJournalRecord(original, request, compiled, definition, graph, limits, sourceOriginal) {
      limits = captureContractLimits(limits, 'keyed lookup activation');
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || (compiled.kind !== 'infer' &&
          (compiled.kind !== 'effect-keyed' || sourceOriginal === undefined))) {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      const wire = checked(compiled.kind === 'effect-keyed'
        ? moon.clientProgramEffectKeyedDeclaredFileActivationRecord(
          original, request, sourceOriginal, limits.maxWireBytes)
        : moon.clientProgramKeyedLookupDeclaredFileActivationRecord(
          original, request, value, token(definition), graph, limits.maxWireBytes));
      const fields = moon.clientProgramKeyedLookupActivationFields(original);
      return Object.freeze({wire, batchCid: runtimeField(fields, 0),
        slotCid: runtimeField(fields, 1), batchIndex: runtimeField(fields, 2),
        batchCount: runtimeField(fields, 3)});
    },
    keyedLookupActivationJournalCurrent(original, request, compiled, definition, graph, sourceOriginal) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined) return false;
      return compiled.kind === 'effect-keyed'
        ? sourceOriginal !== undefined && moon.clientProgramEffectKeyedNativeActivationMatches(
          original, request, sourceOriginal) === true
        : compiled.kind === 'infer' && moon.clientProgramKeyedLookupActivationMatches(
          original, request, value, token(definition), graph) === true;
    },
    prepareKeyedLookupRawCapture(keyedRequest, compiled, definition, retention,
      storage, contentCid, bytes, at, nowMs, limits) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || (compiled.kind !== 'infer' && compiled.kind !== 'effect-keyed')) {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      const raw = checked(moon.clientProgramKeyedLookupPrepareDeclaredFileRawCapture(
        value, token(definition), keyedRequest, token(retention), storage.namespaceId,
        storage.storeAuthorityCid, storage.availabilityEvidenceCid, storage.issuerContractCid,
        contentCid, bytes, at, nowMs, limits.maxBytes, limits.maxNodes,
        limits.maxDepth, limits.maxTextUnits));
      const fields = checked(moon.clientProgramKeyedLookupRawStoreBinding(raw));
      return Object.freeze({original:raw, binding:Object.freeze({name:'lookup_raw_response',
        semanticCid:runtimeField(fields,0), holdingCid:runtimeField(fields,1),
        wire:runtimeField(fields,2), contentCid:runtimeField(fields,3),
        byteCount:Number(runtimeField(fields,4))})});
    },
    prepareKeyedLookupCapturedPage(keyedRequest, capture, raw, at, outputLimits, maxWork, limits) {
      limits = captureContractLimits(limits, 'keyed captured page');
      if (!validResultOutputLimits(outputLimits)) throw new TypeError('Invalid keyed page limits');
      const exported = moon.clientProgramEffectInputExportLimits(
        ...resultOutputLimitFields.map(name => outputLimits[name]));
      if (exported === undefined) throw new TypeError('Invalid keyed page limits');
      return checked(moon.clientProgramKeyedLookupPrepareCapturedPage(keyedRequest, capture,
        raw, at, exported, maxWork, limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
    },
    keyedLookupPageJournalRecord(page, keyedRequest, request, compiled, definition, graph, limits, sourceOriginal) {
      limits = captureContractLimits(limits, 'keyed lookup page');
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || (compiled.kind !== 'infer' &&
          (compiled.kind !== 'effect-keyed' || sourceOriginal === undefined))) {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      const wire = checked(compiled.kind === 'effect-keyed'
        ? moon.clientProgramEffectKeyedDeclaredFilePageRecord(
          page, keyedRequest, request, sourceOriginal, limits.maxWireBytes)
        : moon.clientProgramKeyedLookupDeclaredFilePageRecord(
          page, keyedRequest, request, value, token(definition), graph, limits.maxWireBytes));
      const fields = moon.clientProgramKeyedLookupCapturedPageFields(page);
      return Object.freeze({wire, batchCid: runtimeField(fields, 0),
        slotCid: runtimeField(fields, 1), activationCid: runtimeField(fields, 2),
        batchIndex: runtimeField(fields, 3)});
    },
    keyedLookupPageJournalCurrent(page, keyedRequest, request, compiled, definition, graph, sourceOriginal) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined) return false;
      return compiled.kind === 'effect-keyed'
        ? sourceOriginal !== undefined && moon.clientProgramEffectKeyedNativeCapturedPageMatches(
          page, keyedRequest, request, sourceOriginal) === true
        : compiled.kind === 'infer' && moon.clientProgramKeyedLookupCapturedPageMatches(
          page, keyedRequest, request, value, token(definition), graph) === true;
    },
    takeSourceEvidenceOriginal(capture) {
      const take = Object.getOwnPropertyDescriptor(capture ?? {}, 'takeSourceEvidenceOriginal')?.value;
      if (typeof take !== 'function') throw new TypeError('InstalledSourceEvidenceUnavailable');
      const evidence = inspectEvidence(Reflect.apply(take, capture, []));
      if (evidence.name !== 'source_evidence') throw new TypeError('InvalidInstalledSourceEvidence');
      return evidence;
    },
    keyedLookupPublicationEvidence(original) {
      const value = moon.clientProgramKeyedLookupObservationOriginals(original);
      if (value === undefined) throw new TypeError('Foreign keyed lookup observation');
      return Object.freeze({source: inspectEvidence(runtimeField(value, 1)),
        logicalRelationCid: runtimeField(value, 2)});
    },
    // Reuse the compiled owner retained at Run admission. The physical
    // adapter supplies its opaque execution and bounded verification owner;
    // this does not adopt external attempts or grant publication authority.
    modelPrivateHoldingCid(definition, storeAuthorityCid, role, slot) {
      const identity = moon.clientProgramModelPrivateHoldingCid(
        token(definition), storeAuthorityCid, role, slot);
      if (identity === undefined) throw new TypeError('InvalidModelPrivateHolding');
      return identity;
    },
    modelScopedPrivateHoldingCid(definition, storeAuthorityCid, entry, role, phase = 'settled') {
      const identity = moon.clientProgramModelScopedPrivateHoldingCid(token(definition),
        storeAuthorityCid, entry.scopeCid, entry.slotCid, entry.attemptCid,
        entry.attemptIndex, phase, role);
      if (identity === undefined) throw new TypeError('InvalidModelScopedPrivateHolding');
      return identity;
    },
    bindCheckedClientInferRun(compiled, execution, definition) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer Run');
      }
      return checked(moon.clientProgramBindInferRun(execution,
        value, token(definition)));
    },
    // Inspect only the original Core execution's issued value. Wire admission
    // remains a separate path; this view does not issue Store or send authority.
    inspectInferInvocationEvidence(originalMoon, execution, slot) {
      if (originalMoon !== moon || !Number.isSafeInteger(slot) || slot < 0 ||
          slot > 2147483647 ||
          typeof moon.clientProgramInferInvocationEvidence !== 'function') {
        throw new TypeError('Foreign Infer invocation evidence');
      }
      const evidence = moon.clientProgramInferInvocationEvidence(execution, slot);
      if (evidence === undefined) return undefined;
      if (moon.strategyRunEvidenceName(evidence) !== 'model_invocation_evidence') {
        throw new TypeError('Foreign Infer invocation evidence');
      }
      return inspectEvidence(evidence);
    },
    bindCheckedClientInferDispatch(compiled, execution, definition,
      {account, principalId, at, delegated, observeAccount, observeAt}) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer Run');
      }
      if (typeof observeAccount !== 'function' ||
          typeof observeAt !== 'function') {
        throw new TypeError('Missing current Infer dispatch observations');
      }
      const admitted = checked(moon.clientProgramIssueInferDispatchAdmission(
        value, token(definition), account, principalId, at, delegated,
        observeAccount, observeAt));
      return checked(moon.clientProgramBindInferDispatchAdmission(execution,
        admitted));
    },
    readCheckedClientComposedInferSavedInputScope(compiled, definition, occurrence,
      graph, snapshotWire, authorityScopeCid, custodyAvailable) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer' || typeof custodyAvailable !== 'function') {
        throw new TypeError('Foreign Client compiled Infer Run');
      }
      return checked(moon.clientProgramReadSavedComposedInferInputScope(value, token(definition),
        occurrence, graph, snapshotWire, authorityScopeCid, custodyAvailable));
    },
    readCheckedClientInferSavedInputScope(compiled, definition, preparedProgram,
      step, graph, snapshotWire, authorityScopeCid, custodyAvailable) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer' || typeof custodyAvailable !== 'function') {
        throw new TypeError('Foreign Client compiled Infer Run');
      }
      return checked(moon.clientProgramReadSavedInferInputScope(value, token(definition),
        preparedProgram, step, graph, snapshotWire, authorityScopeCid, custodyAvailable));
    },
    bindCheckedClientInferModelScope(compiled, execution, definition,
      preparedCallSet, {scope, provider, expectedBoundary}) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer Run');
      }
      // bindInferRun already retained this exact compilation in the active
      // owner. The portable binder compares actual input and every fixed call.
      checked(moon.clientProgramBindInferRun(execution, value, token(definition)));
      return checked(moon.clientProgramBindInferModelScope(execution,
        preparedCallSet, evidenceToken(scope), evidenceToken(provider), {...expectedBoundary,
          task_index: BigInt(expectedBoundary.task_index),
          strategy_revision: BigInt(expectedBoundary.strategy_revision)}));
    },
    bindCheckedClientInferModelDispatch(compiled, execution, definition,
      preparedCallSet, scope, {account, principalId, at, delegated,
        observeAccount, observeAt, enterCall}) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer' ||
          typeof observeAccount !== 'function' || typeof observeAt !== 'function' ||
          typeof enterCall !== 'function') {
        throw new TypeError('Foreign Client compiled Infer dispatch');
      }
      const admitted = checked(moon.clientProgramIssueScopedInferDispatchAdmission(
        value, token(definition), scope, account, principalId, at, delegated,
        observeAccount, observeAt));
      checked(moon.clientProgramBindInferModelDispatch(execution, preparedCallSet,
        admitted, enterCall));
      return admitted;
    },
    // Installation-only async port. It uses the same original scoped
    // admission issuer; a persistence observation is never a fresh permit.
    bindCheckedClientInferModelEntryPersistence(compiled, execution, definition,
      preparedCallSet, scope, {account, principalId, at, delegated,
        observeAccount, observeAt, beginEntry}) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer' ||
          typeof observeAccount !== 'function' || typeof observeAt !== 'function' ||
          typeof beginEntry !== 'function') {
        throw new TypeError('Foreign Client compiled Infer dispatch');
      }
      const admitted = checked(moon.clientProgramIssueScopedInferDispatchAdmission(
        value, token(definition), scope, account, principalId, at, delegated,
        observeAccount, observeAt));
      checked(moon.clientProgramBindInferModelEntryPersistence(execution,
        preparedCallSet, admitted, beginEntry));
      return admitted;
    },
    ...modelPreparationControls,
    ...inferOriginalReadControls,
    // Private installed Node inputs only. Canonical/body admission does not
    // issue capture authority, funded capacity or public async support.
    selectInstalledInitialJevDecisionProfile() {
      // Preserve the original Common value from THIS installed runtime. This
      // is the already registered physical precision selection, not a JS
      // reconstruction, provider capability, numerical loan or dispatch grant.
      if (typeof moon.clientProgramInitialJevDecisionProfile !== 'function') {
        throw new TypeError('Installed native Decision probability profile unavailable');
      }
      const profile = moon.clientProgramInitialJevDecisionProfile();
      if (profile === undefined || profile === null) {
        throw new TypeError('Installed native Decision probability profile unavailable');
      }
      return profile;
    },
    readInstalledModelResponseProfile(wire, expectedCid, limits) {
      issuanceLimits(limits, 'Model response profile');
      if (['maxWireBytes', 'maxNodes', 'maxDepth', 'maxMembers', 'maxWork']
          .some(key => !Number.isSafeInteger(limits[key]) || limits[key] < 0 ||
            limits[key] > 2147483647) ||
          typeof wire !== 'string' || wire.length > limits.maxWireBytes) {
        throw new TypeError('Invalid Model response profile limits');
      }
      return checked(moon.clientProgramReadModelResponseProfile(wire, expectedCid,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth,
        limits.maxMembers, limits.maxWork));
    },
    bindInstalledModelRawCapturePolicy(policy, retention, metadata, clock, data) {
      return checked(moon.clientProgramBindModelRawCapturePolicy(
        evidenceToken(policy), retention, metadata, clock, data));
    },
    installedModelRawSelectionOriginals({retention, metadata, clock, data}) {
      // Existing Common bodies remain the authority for exact kind/CID/wire.
      // This projection cannot issue policy adoption, raw custody or sending.
      return moon.clientProgramModelRawSelectionOriginals(retention, metadata,
        clock, data).map(value => Object.freeze({kind: runtimeField(value, 0),
          cid: runtimeField(value, 1), wire: runtimeField(value, 2)}));
    },
    issueCheckedClientInferRawCapturePolicy(compiled, definition, dispatch, scope,
      {profile, installation, probability, storeAuthorityCid, retention, metadata,
        clock, data, selectedAt, availableUntil, deleteBy, extensionCeilingAt,
        metadataDeleteBy}) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer raw policy');
      }
      return checked(moon.clientProgramIssueInferRawCapturePolicy(value,
        token(definition), dispatch, scope, profile, installation, probability,
        storeAuthorityCid, retention, metadata, clock, data, selectedAt,
        availableUntil, deleteBy, extensionCeilingAt, metadataDeleteBy));
    },
    registerCheckedClientInferRawCapture(compiled, definition, dispatch, scope,
      {policy, profile, installation, probability, account, at, storeAuthorityCid,
        selectionAvailable, observeAccount, observeAt, delegated}) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer' ||
          typeof selectionAvailable !== 'function' ||
          typeof observeAccount !== 'function' || typeof observeAt !== 'function') {
        throw new TypeError('Foreign Client compiled Infer raw capture');
      }
      return checked(moon.clientProgramRegisterInferRawCapture(value,
        token(definition), dispatch, scope, policy, profile, installation,
        probability, account, at, storeAuthorityCid, selectionAvailable,
        observeAccount, observeAt, delegated));
    },
    bindCheckedClientInferInvocation(compiled, execution, definition,
      verified, invocation, dataPolicyCid) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer Run');
      }
      return checked(moon.clientProgramBindInferInvocation(execution,
        value, token(definition), verified, token(invocation), dataPolicyCid));
    },
    bindIssuedClientInferInvocation(compiled, execution, definition, issued) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer Run');
      }
      const binding = checked(moon.clientProgramBindIssuedInferInvocation(
        execution, value, token(definition), issued));
      const result = Object.freeze({binding,
        observation: inspectEvidence(
          moon.clientProgramInferInvocationBindingObservation(binding)),
        invocation: inspect(
          moon.clientProgramInferInvocationBindingInvocation(binding))});
      inferInvocationTokens.set(result, {compiled: value, definition});
      return result;
    },
    checkedClientEffectInferInvocation(checkedEffect, compilation, definition, issued) {
      const retained = inferInvocationTokens.get(issued);
      if (retained === undefined || retained.definition.identity !== definition.identity ||
          !moon.clientProgramCompiledRunEffectMatches(retained.compiled, checkedEffect, compilation) ||
          !moon.clientProgramCheckCompiledRunDefinition(retained.compiled, token(definition)) ||
          moon.clientProgramInferInvocationBindingObservation(issued.binding) === undefined) {
        throw new TypeError('Foreign Effect Infer Invocation');
      }
      return Object.freeze({observation: issued.observation, invocation: issued.invocation,
        owner: token(issued.invocation)});
    },
    captureCheckedClientInferModelObservation(issued, scan, receipt, limits, preconsumer) {
      issuanceLimits(limits, 'Original Model observation');
      if (!inferInvocationTokens.has(issued)) {
        throw new TypeError('Foreign Model observation Invocation');
      }
      const prior = preconsumer === undefined ? undefined : localEffectDependencyTokens.get(preconsumer);
      if (preconsumer !== undefined && prior?.kind !== 'preconsumer_model') {
        throw new TypeError('ForeignPreconsumerModelOriginal');
      }
      const original = prior === undefined
        ? moon.clientProgramIssueInferInvocationBindingOriginalModelObservation(
          issued.binding, receipt, limits.maxWireBytes, limits.maxNodes, limits.maxDepth)
        : checked(moon.clientProgramBindPreconsumerModelUnitObservation(issued.binding, prior.original));
      if (original === undefined) throw new TypeError('Foreign Model outcome receipt');
      const body = moon.clientProgramOriginalModelObservationBody(original);
      const coordinates = moon.clientProgramOriginalModelObservationCoordinates(original);
      // This exported Array Option is boxed by the pinned compiler. The
      // adjacent tuple/String projections retain their own unboxed layouts.
      const inputBodies = moon.clientProgramOriginalModelObservationInputBodies(original);
      const inputs = runtimeIsBoxedSome(inputBodies) ? runtimeField(inputBodies, 0) : undefined;
      const outcomes = moon.clientProgramInferModelIdentityBody(scan, receipt);
      if (typeof runtimeOptionalField(body, 0) !== 'string' ||
          typeof runtimeOptionalField(body, 1) !== 'string' || coordinates === undefined ||
          !Array.isArray(inputs) || typeof outcomes !== 'string') {
        throw new TypeError('Original Model dependency bodies unavailable');
      }
      const task = runtimeField(coordinates, 0), unit = runtimeField(coordinates, 1),
        step = runtimeField(coordinates, 2);
      if (!Number.isSafeInteger(task) || task < 0 ||
          !Number.isSafeInteger(unit) || unit < 0 ||
          !Number.isSafeInteger(step) || step < 0) {
        throw new TypeError('Foreign Model Unit coordinate');
      }
      const value = Object.freeze({task, unit, step,
        bodies: Object.freeze([
          Object.freeze({kind: 'local_model_observation', cid: runtimeField(body, 0),
            wire: runtimeField(body, 1)}),
          ...inputs.map(entry => Object.freeze({kind: runtimeField(entry, 0),
            cid: runtimeField(entry, 1), wire: runtimeField(entry, 2)})),
          Object.freeze({kind: 'relation_value',
            cid: moon.clientProgramEffectInputExportLogicalCid(receipt), wire: outcomes}),
          Object.freeze({kind: 'relation_schema',
            cid: moon.clientProgramEffectInputExportSchemaCid(receipt),
            wire: moon.clientProgramEffectInputExportSchemaWire(receipt)}),
        ])});
      inferModelObservationTokens.set(value, {original, issued});
      return value;
    },
    issueOriginalModelEffectEvidence(model, retention, imports, limits, deferCatalogs = false) {
      issuanceLimits(limits, 'Original Model Effect dependency');
      const retained = inferModelObservationTokens.get(model);
      const imported = imports === undefined ? undefined : localEffectDependencyTokens.get(imports);
      if (retained === undefined || !inferInvocationTokens.has(retained.issued) ||
          imports !== undefined && imported?.kind !== 'imported') {
        throw new TypeError('Foreign Model Effect originals');
      }
      const result = moon.clientProgramOriginalModelAcquiredEffectEvidence(
        retained.original, token(retention), limits.maxWireBytes, limits.maxNodes,
        limits.maxDepth, imported?.issued, imported?.originalSources ?? []);
      let acquired;
      try { acquired = checked(result); }
      catch (cause) {
        try {
          const kind = moon.clientProgramOriginalModelAcquiredEffectEvidenceIssueKind?.(result);
          if (typeof kind === 'string') Object.defineProperty(cause, 'primaryDiagnostic', {
            value: Object.freeze({code: 'MoonBitHostFailure',
              phase: 'original_model_acquired_effect_evidence', kind,
              task: model.task, unit: model.unit, step: model.step}),
          });
        } catch { /* Optional DATA projection cannot replace the original failure. */ }
        throw cause;
      }
      const direct = moon.clientProgramOriginalModelAcquiredEffectSources(acquired)
        .map(source => inspectAcquiredEffectEvidence(source, retention, limits, deferCatalogs));
      const barrier = moon.clientProgramOriginalModelAcquiredEffectLookupBarrier(acquired);
      const lookupBodies = checked(moon.clientProgramOriginalModelAcquiredLookupDependencyBodies(acquired))
        .map(body => Object.freeze({kind:runtimeField(body,0), cid:runtimeField(body,1),
          wire:runtimeField(body,2)}));
      const value = Object.freeze({
        invocation: moon.clientProgramOriginalModelAcquiredEffectInvocation(acquired),
        bodies: Object.freeze([
          ...model.bodies,
          ...direct.flatMap(source => source.bodies),
          ...lookupBodies,
          ...moon.clientProgramOriginalModelAcquiredScopeImportBodies(acquired)
            .map(body => Object.freeze({kind: runtimeField(body, 0), cid: runtimeField(body, 1),
              wire: runtimeField(body, 2)})),
          ...(imports?.bodies ?? []),
          Object.freeze({kind: 'acquisition_scope',
            wire: moon.clientProgramOriginalModelAcquiredEffectScope(acquired)}),
          ...(barrier === undefined || lookupBodies.length !== 0 ? [] : [Object.freeze({kind: 'lookup_barrier',
            cid: runtimeField(barrier, 0), wire: runtimeField(barrier, 1)})]),
        ]),
        ...(deferCatalogs ? {catalogDeferred: true} : {}),
        catalogBodies: Object.freeze([...direct.flatMap(source => source.catalogBodies),
          ...lookupBodies.filter(body => ['source_contract', 'source_view_contract', 'data_policy',
            'request_schema', 'carrier_schema', 'schema_evidence', 'capability_evidence'].includes(body.kind))]),
      });
      localEffectDependencyTokens.set(value, {kind: 'model', issued: acquired,
        original: retained.original});
      return value;
    },
    readCheckedClientInferSlotReplay(compiled, definition, observation,
      records, bundle, proofs, {maxSlots, maxSlotWireUnits}) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer Run');
      }
      return checked(moon.clientProgramReadVerifiedInferSlotReplay(
        evidenceToken(observation), records, bundle, proofs, value, token(definition),
        maxSlots, maxSlotWireUnits));
    },
    ...effectPreparationControls,
    ...effectUnitResultControls,
    ...effectDependencyControls,
    bindCheckedClientEffectRun(checkedEffect, admission, runDefinition) {
      if (typeof moon.clientProgramBindEffectRun !== 'function') {
        throw new TypeError('Client Effect Run binding is unavailable');
      }
      const bound = moon.clientProgramBindEffectRun(
        checkedEffect, admissionToken(admission), token(runDefinition));
      if (bound === undefined) {
        throw new TypeError('Run Definition differs from checked Effect');
      }
      return bound;
    },
    issueRunDefinition(admission, definition, limits) {
      limits = captureContractLimits(limits, 'Run Definition');
      if (definition === null || typeof definition !== 'object') {
        throw new TypeError('Invalid Run Definition request');
      }
      return inspect(checked(moon.strategyIssueRunDefinition(
        admissionToken(admission),
        definition.scopeId,
        definition.runId,
        definition.inputArtifactSetCid,
        definition.createdAt,
        definition.validUntil,
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      )), limits);
    },
    issueEffectFreeRunReceipt(chain, provenance, limits) {
      limits = captureContractLimits(limits, 'Run Receipt');
      if (chain === null || typeof chain !== 'object' ||
          provenance === null || typeof provenance !== 'object' ||
          !Array.isArray(chain.definitions) ||
          !Array.isArray(chain.artifacts) ||
          !Array.isArray(provenance.bindings) ||
          !Array.isArray(provenance.sourceEvidence) ||
          !Array.isArray(provenance.modelEvidence) ||
          !Array.isArray(provenance.barrierAttemptReceiptCids)) {
        throw new TypeError('Invalid Run Receipt request');
      }
      return inspect(checked(moon.strategyIssueEffectFreeRunReceipt(
        admissionToken(chain.admission),
        token(chain.runDefinition),
        token(chain.invocation),
        evidenceToken(chain.observation),
        chain.definitions.map(token),
        chain.artifacts.map(token),
        token(chain.manifest),
        evidenceToken(provenance.normalizationJournal),
        provenance.bindings.map(binding => binding.name),
        provenance.bindings.map(binding => binding.sha256),
        provenance.sourceEvidence.map(evidenceToken),
        provenance.modelEvidence.map(evidenceToken),
        provenance.barrierAttemptReceiptCids,
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
        contentCaptures(provenance.contentGenerations),
      )), limits);
    },
    ...captureControls,
    ...effectArtifactControls,
    ...effectRecoveryControls,
    ...sourceControls,
    ...snapshotControls,
    ...pendingSourceAdvanceControls,
    ...effectFreeCaptureControls,
    ...effectPreviewControls,
    ...inventoryControls,
    ...effectfulCaptureControls,
    prepareLocalEffectDependencyInventory(artifacts, bodies, limits, construction, originalArtifacts = []) {
      issuanceLimits(limits, 'Effect dependency inventory');
      if (!Array.isArray(artifacts) || construction === undefined && artifacts.length > 4096 ||
          !Array.isArray(bodies) || construction === undefined && bodies.length > 4096) {
        throw new TypeError('Invalid Effect dependency inventory');
      }
      if (construction !== undefined) {
        const original=installedEffectDependencyOriginal(construction,moon);
        const kinds=[], identities=[], wires=[], roots=[], originals=[];
        for (const artifact of artifacts) {
          const owned=localEffectArtifactTokens.get(artifact);
          if(owned===undefined)throw new TypeError('Foreign Effect dependency root');
          roots.push(owned);
        }
        if (!Array.isArray(originalArtifacts)) throw new TypeError('Invalid Effect dependency originals');
        for (const artifact of originalArtifacts) {
          const owned=localEffectArtifactTokens.get(artifact);
          if(owned===undefined)throw new TypeError('Foreign Effect dependency original');
          originals.push(owned);
        }
        for(const body of bodies){
          if(body===null||typeof body!=='object')throw new TypeError('Invalid Effect dependency body');
          const kind=Object.getOwnPropertyDescriptor(body,'kind'),
            wire=Object.getOwnPropertyDescriptor(body,'wire'),cid=Object.getOwnPropertyDescriptor(body,'cid');
          if(!kind||!wire||!Object.hasOwn(kind,'value')||!Object.hasOwn(wire,'value')||
              cid!==undefined&&!Object.hasOwn(cid,'value')||typeof kind.value!=='string'||
              typeof wire.value!=='string'||cid!==undefined&&typeof cid.value!=='string')
            throw new TypeError('Invalid Effect dependency body');
          kinds.push(kind.value);identities.push(cid?.value);wires.push(wire.value);
        }
        const value=checked(moon.clientProgramInstalledEffectDependencyInventoryPrepare(
          original.parent,original.prepared,original.request,original.plan,kinds,identities,wires,roots,
          limits.maxWireBytes,limits.maxNodes,limits.maxDepth,originals));
        original.current();
        return value;
      }
      const roots = new Map();
      for (const artifact of artifacts) {
        const owned = localEffectArtifactTokens.get(artifact);
        if (owned === undefined) {
          throw new TypeError('Foreign Effect dependency root');
        }
        roots.set(artifact.identity, owned);
      }
      let remaining = Math.min(limits.maxWireBytes, 16 * 1024 * 1024);
      const entries = new Map();
      const encoder = new TextEncoder();
      for (const body of bodies) {
        const {kind, wire, cid} = body ?? {};
        if (typeof kind !== 'string' || typeof wire !== 'string' ||
            (cid !== undefined && typeof cid !== 'string')) {
          throw new TypeError('Invalid Effect dependency body');
        }
        // Check the aggregate input before parsing or retaining another
        // admitted body. Encoding/envelope limits are checked again by MoonBit.
        if (wire.length > remaining) {
          throw new RangeError('EffectDependencyBodyByteLimit');
        }
        const bytes = encoder.encode(wire).byteLength;
        if (bytes > remaining) {
          throw new RangeError('EffectDependencyBodyByteLimit');
        }
        remaining -= bytes;
        const admitted = checked(moon.clientProgramAdmitEffectDependencyBody(
          kind, cid, wire, limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
        const identity = moon.clientProgramEffectDependencyBodyCid(admitted);
        const key = `${kind}\0${identity}`;
        const previous = entries.get(key);
        if (previous !== undefined && previous.wire !== wire) {
          throw new TypeError('Conflicting Effect dependency body');
        }
        if (previous === undefined) entries.set(key, {wire, admitted});
      }
      return checked(moon.clientProgramIssueEffectDependencyInventory(
        [...entries.values()].map(value => value.admitted), [...roots.values()],
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
    },
    beginEffectfulPublicationConstruction(owner, issue, args, additionalContracts) {
      if (typeof issue !== 'boolean' || !Array.isArray(args) ||
          args.length !== (issue ? 4 : 7)) {
        throw new TypeError('Invalid Effectful publication construction');
      }
      const chain = args[0], receipts = args[2];
      const limits = captureContractLimits(args[args.length - 1], 'Effectful publication construction');
      // This bound belongs to the original completed Read's prepaid metadata.
      // Inspect lengths before allocating flattened token or receipt arrays.
      const inputLimit = checked(moon.clientProgramInstalledEffectCapturePublicationInputLimit(owner));
      if (!Number.isSafeInteger(inputLimit) || inputLimit < 5 ||
          chain === null || typeof chain !== 'object' ||
          receipts === null || typeof receipts !== 'object' ||
          typeof receipts.setWire !== 'string' || !Array.isArray(receipts.memberWires) ||
          issue && !Array.isArray(additionalContracts) ||
          !issue && typeof receipts.finalWire !== 'string') {
        throw new TypeError('Invalid Effectful publication construction');
      }
      let contractCount = 5;
      for (const name of ['definitions', 'artifacts', 'derivations', 'orderings', 'retentions', 'durableBindings']) {
        const values = chain[name];
        if (!Array.isArray(values) || values.length > inputLimit - contractCount) {
          throw new RangeError('EffectfulPublicationMetadataLimit');
        }
        contractCount += values.length;
      }
      const extraCount = issue ? additionalContracts.length : 3;
      if (extraCount > inputLimit - contractCount ||
          receipts.memberWires.length > inputLimit - contractCount - extraCount - (issue ? 1 : 2)) {
        throw new RangeError('EffectfulPublicationMetadataLimit');
      }
      const contracts = [token(chain.capturedRun), token(chain.computationReceipt),
        token(chain.runDefinition), token(chain.invocation), token(chain.manifest)];
      for (const name of ['definitions', 'artifacts', 'derivations', 'orderings', 'retentions', 'durableBindings']) {
        for (const contract of chain[name]) contracts.push(token(contract));
      }
      if (issue) {
        for (const contract of additionalContracts) contracts.push(token(contract));
      } else {
        for (let index = 3; index < 6; index++) contracts.push(token(args[index]));
      }
      const wires = [receipts.setWire];
      for (const wire of receipts.memberWires) {
        if (typeof wire !== 'string') throw new TypeError('Invalid Effectful publication Receipt');
        wires.push(wire);
      }
      if (!issue) wires.push(receipts.finalWire);
      return checked(moon.clientProgramBeginInstalledEffectCapturePublication(owner, issue,
        contracts, wires, limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
    },
    issueEffectfulFinalRunReceipt(chain, preview, receipts, limits) {
      limits = captureContractLimits(limits, 'final Effectful Run Receipt');
      if (chain === null || typeof chain !== 'object' ||
          !Array.isArray(chain.definitions) ||
          !Array.isArray(chain.artifacts) ||
          receipts === null || typeof receipts !== 'object' ||
          typeof receipts.setWire !== 'string' ||
          !Array.isArray(receipts.memberWires) ||
          receipts.memberWires.some(wire => typeof wire !== 'string')) {
        throw new TypeError('Invalid final Effectful Run Receipt');
      }
      const ownedPreview = computationPreviewTokens.get(preview);
      if (ownedPreview === undefined) {
        throw new TypeError('Foreign Effect computation Preview');
      }
      const prepared = recoveredEffectCaptures.get(chain.capturedRun);
      return inspect(checked(prepared === undefined ? moon.strategyIssueEffectfulFinalRunReceipt(
        token(chain.runDefinition), token(chain.invocation),
        chain.definitions.map(token), chain.artifacts.map(token),
        token(chain.manifest), token(chain.computationReceipt),
        token(chain.capturedRun), ownedPreview, receipts.setWire,
        receipts.memberWires, limits.maxWireBytes, limits.maxNodes,
        limits.maxDepth,
      ) : moon.clientProgramIssuePreparedEffectfulFinalRunReceipt(
        token(chain.runDefinition), token(chain.invocation),
        chain.definitions.map(token), chain.artifacts.map(token),
        token(chain.manifest), token(chain.computationReceipt),
        token(chain.capturedRun), prepared, ownedPreview, receipts.setWire,
        receipts.memberWires, limits.maxWireBytes, limits.maxNodes,
        limits.maxDepth,
      )), limits);
    },
    issueEffectSetApplyReceiptFromMembers(preview, members, replayed, limits) {
      limits = captureContractLimits(limits, 'Effect Set Apply Receipt');
      if (!Array.isArray(members) ||
          members.some(member => typeof member?.wire !== 'string') ||
          !Array.isArray(replayed) ||
          replayed.some(value => typeof value !== 'boolean')) {
        throw new TypeError('Invalid Effect Set Apply Receipt request');
      }
      const ownedPreview = computationPreviewTokens.get(preview);
      if (ownedPreview === undefined) {
        throw new TypeError('Foreign Effect computation Preview');
      }
      return inspect(checked(
        moon.strategyIssueEffectSetApplyReceiptFromMembers(
          ownedPreview, members.map(member => member.wire), replayed,
          limits.maxWireBytes, limits.maxNodes, limits.maxDepth,
        ),
      ), limits);
    },
    ...effectRunStateControls,
    ...transitionControls,
    ...publicationProgressControl(moon, token),
    ...contractControls,
    ...publicationValidationControls,
    issueResultArtifact(exportHandle, invocation, retention, limits) {
      limits = captureContractLimits(limits, 'Result Artifact');
      return inspect(checked(
        moon.strategyHostOutputExportIssueResultArtifact(
          exportHandle,
          token(invocation),
          token(retention),
          limits.maxWireBytes,
          limits.maxNodes,
          limits.maxDepth,
        ),
      ), limits);
    },
    ...resultReadControls,
    ...runIdentityControls,
    ...resultRetentionControls,
    ...publicationStateControls,
    ...resultDeliveryControls,
  });
  publicationControls.set(moon, control);
  return control;
}

export function runtimeCore(moon) {
  const publications = publicationControl(moon);
  return Object.freeze({
    siteControl: siteControl(moon),
    managedExecutionProfileCid: moon.strategyHostManagedExecutionProfileCid,
    remoteSiteControl: remoteSiteControl(moon),
    remoteTransferControl: remoteTransferControl(moon),
    remoteStandardSourceControl: remoteStandardSourceControl(moon),
    remoteCredentialControl: remoteCredentialControl(moon),
    // Explicit private DATA view, not an installed issuer or signing permit.
    // Keep older unused runtime routes lazy; actual callers require this ABI.
    localSigningMetadata: () => createLocalSigningMetadata(moon),
    installationPreparationMetadata: () => createInstallationPreparationMetadata(moon),
    effectApplicationControl: effectApplicationControl(moon),
    remoteBundleControl: remoteBundleControl(moon),
    publicationControl: publications,
    outputExportControl: outputExportControl(moon, publications),
    contentGenerationControl: contentGenerationControl(moon, publications),
    contentCaptureControl: contentCaptureControl(moon, publications),
    ...createRuntimeExecutionControls(moon, publications),
  });
}
