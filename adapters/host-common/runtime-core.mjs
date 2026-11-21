import {installedEffectDependencyOriginal} from './installed-effect-dependency-original.mjs';
import {runtimeField, runtimeOptionalField, runtimeIsError, runtimeIsBoxedSome, runtimeUnboxedReferenceOption} from './compiler-binding.generated.mjs';
import {checked} from './runtime-result.mjs';
import {tuplePair} from './runtime-tuple.mjs';
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
import {rememberOriginalDispatchFailure} from './dispatch-failure-observation.mjs';
import {createLocalSigningMetadata} from './local-signing-metadata.mjs';
import {createInstallationPreparationMetadata} from './installation-preparation-metadata.mjs';
import {publicationAction} from './publication-action.mjs';
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

// Translate the installed Node envelope only; Common owns contract ceilings.
function inferQuantityCapacity(value) {
  if (value === undefined) return undefined;
  if (value === null || typeof value !== 'object' || Array.isArray(value) ||
      Object.keys(value).sort().join(',') !== 'limits,perAttempt' ||
      ['limits', 'perAttempt'].some(scope => {
        const amount = value[scope];
        return amount === null || typeof amount !== 'object' || Array.isArray(amount) ||
          Object.keys(amount).sort().join(',') !== 'costUnits,durationMs,tokens' ||
          Object.values(amount).some(quantity => typeof quantity !== 'bigint' ||
            quantity < 0n || quantity > BigInt(Number.MAX_SAFE_INTEGER));
      })) {
    throw new TypeError('InvalidInstalledInferQuantityCapacity');
  }
  return {
    limits: {tokens: value.limits.tokens, cost_units: value.limits.costUnits,
      duration_ms: value.limits.durationMs},
    per_attempt: {tokens: value.perAttempt.tokens, cost_units: value.perAttempt.costUnits,
      duration_ms: value.perAttempt.durationMs},
  };
}

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
  const prepareSerializationGraph = (checkedProgram, options, intermediate, request) => {
    const original = options?.resultDataPolicy;
    if (original?.kind !== 'data_policy' || typeof original.cid !== 'string' ||
        typeof original.wire !== 'string' ||
        !['task', 'step', 'maxRows', 'maxBytes'].every(key =>
          Number.isInteger(options[key]) && options[key] >= 0 &&
          options[key] <= 2147483647)) {
      throw new TypeError('Invalid Content compilation options');
    }
    let graph;
    if (request === undefined) {
      const issue = intermediate ? moon.clientProgramSerializationPlanComponent
        : moon.clientProgramSerializationPlanGraph;
      graph = compiledRunResult(issue(checkedProgram, options.task, options.step,
        original.cid, original.wire, options.maxRows, options.maxBytes), 'RunHostContentPlanRejected');
    } else {
      const issue = request.modelOccurrence === undefined ? moon.clientProgramPrepareRequestSerializationGraph
        : moon.clientProgramPrepareRequestModelSerializationGraph;
      if (typeof issue !== 'function') throw new TypeError('Request Content Graph constructor unavailable');
      graph = compiledRunResult(Reflect.apply(issue, moon, [request.parent, request.input,
        ...(request.modelOccurrence === undefined ? [] : [request.modelOccurrence]),
        options.task, options.step, original.cid, original.wire, options.maxRows,
        options.maxBytes, !intermediate, request.contracts]), 'RunHostContentPlanRejected');
    }
    const selected = Object.freeze({task: options.task, step: options.step,
      wire: moon.clientProgramSerializationPlanGraphWire(graph)});
    serializationPlanTokens.set(selected, graph);
    return selected;
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
  const prepareAcquiredSerializationGraph = (checkedProgram, options, intermediate, request) => {
    if (!['task', 'step', 'maxRows', 'maxBytes'].every(key =>
      Number.isInteger(options?.[key]) && options[key] >= 0 && options[key] <= 2147483647)) {
      throw new TypeError('Invalid acquired Content compilation options');
    }
    let graph;
    if (request === undefined) {
      const issue = intermediate ? moon.clientProgramAcquiredSerializationPlanComponent
        : moon.clientProgramAcquiredSerializationPlanGraph;
      graph = compiledRunResult(issue(checkedProgram, options.task, options.step,
        options.maxRows, options.maxBytes), 'RunHostContentPlanRejected');
    } else {
      const issue = request.modelOccurrence === undefined ? moon.clientProgramPrepareRequestAcquiredSerializationGraph
        : moon.clientProgramPrepareRequestModelAcquiredSerializationGraph;
      if (typeof issue !== 'function') throw new TypeError('Request acquired Content Graph constructor unavailable');
      graph = compiledRunResult(Reflect.apply(issue, moon, [request.parent, request.input,
        ...(request.modelOccurrence === undefined ? [] : [request.modelOccurrence]),
        options.task, options.step, options.maxRows, options.maxBytes,
        !intermediate, request.contracts]), 'RunHostContentPlanRejected');
    }
    const selected = Object.freeze({task: options.task, step: options.step,
      wire: moon.clientProgramSerializationPlanGraphWire(graph)});
    serializationPlanTokens.set(selected, graph);
    return selected;
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
  const capturedPreparationLimits = preparation => {
      // The same preparation owns the complete context envelope. Metadata
      // contract bounds cannot price embedded Result rows or their wrapper.
      const originalOption = moon.strategyCapturedRunPreparationLimits(preparation);
      const originalLimits = runtimeIsBoxedSome(originalOption)
        ? runtimeField(originalOption, 0) : undefined;
      if (!Array.isArray(originalLimits) || originalLimits.length !== 3 ||
          !Number.isSafeInteger(originalLimits[0]) ||
          !Number.isSafeInteger(originalLimits[1]) ||
          !Number.isSafeInteger(originalLimits[2]) ||
          originalLimits[0] < 0 || originalLimits[0] > 2147483647 ||
          originalLimits[1] < 0 || originalLimits[1] > 2147483647 ||
          originalLimits[2] < 0 || originalLimits[2] > 2147483647) {
        throw new TypeError('Invalid original Captured Run preparation limits');
      }
      return Object.freeze({maxWireBytes: originalLimits[0],
        maxNodes: originalLimits[1], maxDepth: originalLimits[2]});
  };
  const finishCapturedPreparation = async (preparation, signal,
    retainComputation = false, dependencyOriginal) => {
    let finished = false;
    try {
      const limits = capturedPreparationLimits(preparation);
      while (true) {
        signal?.throwIfAborted();
        const done = dependencyOriginal === undefined
          ? checked(moon.strategyCapturedRunAdvance(preparation, 256))
          : checked(moon.clientProgramInstalledEffectDependencyCaptureAdvance(
            dependencyOriginal.parent, dependencyOriginal.prepared, dependencyOriginal.request,
            dependencyOriginal.plan, preparation, 256));
        dependencyOriginal?.current();
        if (done) break;
        await new Promise(resolve => typeof setImmediate === 'function'
          ? setImmediate(resolve) : setTimeout(resolve, 0));
      }
      signal?.throwIfAborted();
      const captured = dependencyOriginal === undefined ? inspect(checked(retainComputation
        ? moon.strategyCapturedRunFinishRetained(preparation)
        : moon.strategyCapturedRunFinish(preparation)), limits)
        : inspectPreparedEffectCapturedRun(checked(moon.clientProgramFinishInstalledEffectDependencyCapture(
          dependencyOriginal.parent, dependencyOriginal.prepared, dependencyOriginal.request,
          dependencyOriginal.plan, preparation)));
      dependencyOriginal?.current();
      if (retainComputation) {
        capturedComputationPreparations.set(captured, preparation);
      }
      finished = true;
      return captured;
    } finally {
      if (!finished) moon.strategyCapturedRunCancel(preparation);
    }
  };
  const finishProgramSnapshot = async (publication, output, signal) => {
    signal?.throwIfAborted();
    const snapshot = checked(moon.clientProgramBeginSnapshot(publication, output));
    let finished = false;
    try {
      while (true) {
        signal?.throwIfAborted();
        const progress = tuplePair(checked(
          moon.clientProgramAdvanceSnapshot(snapshot, 256)));
        if (!Array.isArray(progress) || progress.length !== 2 ||
            typeof progress[0] !== 'boolean' ||
            !Number.isSafeInteger(progress[1]) || progress[1] < 0) {
          throw new TypeError('Invalid original snapshot progress');
        }
        if (progress[0]) break;
        await new Promise(resolve => typeof setImmediate === 'function'
          ? setImmediate(resolve) : setTimeout(resolve, 0));
      }
      signal?.throwIfAborted();
      const captured = inspectSnapshot(checked(moon.clientProgramFinishSnapshot(snapshot)));
      finished = true;
      return captured;
    } finally {
      if (!finished) moon.clientProgramCancelSnapshot(snapshot);
    }
  };
  const programCaptureLimits = capture => {
    const extent = checked(moon.clientProgramCaptureLimits(capture));
    const maxWireBytes = runtimeField(extent, 0);
    const maxNodes = runtimeField(extent, 1);
    const maxDepth = runtimeField(extent, 2);
    if (!Number.isSafeInteger(maxWireBytes) || maxWireBytes < 0 ||
        maxWireBytes > 2147483647 ||
        !Number.isSafeInteger(maxNodes) || maxNodes < 0 || maxNodes > 2147483647 ||
        !Number.isSafeInteger(maxDepth) || maxDepth < 0 || maxDepth > 2147483647 ||
        runtimeField(extent, 3) !== undefined) {
      throw new TypeError('Invalid original capture extent');
    }
    return Object.freeze({maxWireBytes, maxNodes, maxDepth});
  };
  // Typed ordinary capture never exposes its inner issuer. The same Host
  // continuation owns cancellation throughout every await and publication.
  const finishProgramCapture = async (capture, signal) => {
    let finished = false;
    try {
      checked(moon.clientProgramStartCapture(capture));
      const limits = programCaptureLimits(capture);
      while (true) {
        signal?.throwIfAborted();
        const progress = tuplePair(checked(
          moon.clientProgramAdvanceCapture(capture, 256)));
        if (!Array.isArray(progress) || progress.length !== 2 ||
            typeof progress[0] !== 'boolean' ||
            !Number.isSafeInteger(progress[1]) || progress[1] < 0) {
          throw new TypeError('Invalid original capture progress');
        }
        if (progress[0]) break;
        await new Promise(resolve => typeof setImmediate === 'function'
          ? setImmediate(resolve) : setTimeout(resolve, 0));
      }
      signal?.throwIfAborted();
      const captured = inspect(checked(
        moon.clientProgramFinishCapture(capture)), limits);
      // The existing publication owner keeps this one typed continuation.
      // Its private issuer remains on the same preparation resource owner.
      capturedComputationPreparations.set(captured, {program: capture});
      finished = true;
      return captured;
    } finally {
      if (!finished) moon.clientProgramCancelCapture(capture);
    }
  };
  const finishProgramValidation = async (validation, signal, requireCurrent) => {
    try {
      requireCurrent?.();
      checked(moon.clientProgramStartValidation(validation));
      while (true) {
        signal?.throwIfAborted();
        requireCurrent?.();
        const progress = tuplePair(checked(
          moon.clientProgramAdvanceValidation(validation, 256)));
        if (!Array.isArray(progress) || progress.length !== 2 ||
            typeof progress[0] !== 'boolean' ||
            !Number.isSafeInteger(progress[1]) || progress[1] < 0) {
          throw new TypeError('Invalid original publication validation progress');
        }
        if (progress[0]) {
          signal?.throwIfAborted();
          requireCurrent?.();
          checked(moon.clientProgramFinishValidation(validation));
          return true;
        }
        await new Promise(resolve => typeof setImmediate === 'function'
          ? setImmediate(resolve) : setTimeout(resolve, 0));
      }
    } finally {
      moon.clientProgramCancelValidation(validation);
    }
  };
  const finishStoreValidation = async (validation, requireCurrent) => {
    try {
      while (true) {
        requireCurrent();
        const progress = tuplePair(checked(
          moon.clientStoreAdvanceOriginalValidation(validation, 256)));
        if (!Array.isArray(progress) || progress.length !== 2 ||
            typeof progress[0] !== 'boolean' ||
            !Number.isSafeInteger(progress[1]) || progress[1] < 0) {
          throw new TypeError('Invalid original Store validation progress');
        }
        if (progress[0]) {
          requireCurrent();
          checked(moon.clientStoreFinishOriginalValidation(validation));
          return true;
        }
        await new Promise(resolve => typeof setImmediate === 'function'
          ? setImmediate(resolve) : setTimeout(resolve, 0));
      }
    } finally {
      moon.clientStoreCancelOriginalValidation(validation);
    }
  };
  const finishPublicationValidation = async (
    preparation, advance, finish, cancel, signal,
  ) => {
    try {
      while (true) {
        signal?.throwIfAborted();
        const progress = advance(preparation, 256);
        if (progress === -1) return false;
        if (progress === 1) {
          signal?.throwIfAborted();
          return finish(preparation);
        }
        if (progress !== 0) {
          throw new TypeError('Invalid publication validation progress');
        }
        await new Promise(resolve => typeof setImmediate === 'function'
          ? setImmediate(resolve) : setTimeout(resolve, 0));
      }
    } finally {
      cancel(preparation);
    }
  };
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
    prepareCheckedClientSerializationGraph(checkedProgram, options) {
      return prepareSerializationGraph(checkedProgram, options, false);
    },
    prepareCheckedClientSerializationComponent(checkedProgram, options) {
      return prepareSerializationGraph(checkedProgram, options, true);
    },
    prepareCheckedClientRequestSerializationGraph(parent, input, contracts, checkedProgram, options, intermediate, modelOccurrence) {
      return prepareSerializationGraph(checkedProgram, options, intermediate, {parent, input, contracts, modelOccurrence});
    },
    // Keep the selected facade outside Core. Only this existing private map
    // supplies the SAME opaque Content original to the Request constructor.
    // Return its original Result to the manager's existing error projection.
    prepareClientRequestSerializedInferGraph(parent, input, occurrence, selected, execution, contracts) {
      const graph = serializationPlanTokens.get(selected);
      if (graph === undefined) throw new TypeError('Foreign Content compilation graph');
      const prepare = moon.clientProgramPrepareRequestSerializedModelGraph;
      if (typeof prepare !== 'function') throw new TypeError('Request serialized Model Graph constructor unavailable');
      return Reflect.apply(prepare, moon, [parent, input, occurrence, graph, execution, contracts]);
    },
    prepareCheckedClientSerializedInferGraph(occurrence, selected, execution) {
      const graph = serializationPlanTokens.get(selected);
      if (graph === undefined) throw new TypeError('Foreign Content compilation graph');
      return compiledRunResult(moon.clientProgramSerializedInferPlanGraph(
        occurrence, graph, execution), 'RunHostContentInferPlanRejected');
    },
    startCheckedClientGeneratedInferExecution(compiled, generation, prepared, graph, provider) {
      const run = compiledContent(compiled);
      const original = serializationGenerationTokens.get(generation);
      if (original === undefined) throw new TypeError('Foreign Client Content generation');
      return compiledRunResult(moon.clientProgramStartGeneratedInferExecution(
        prepared, run, original, graph, provider), 'RunHostContentInferInputRejected');
    },
    startCheckedClientGeneratedInferInputs(compiled, generation, graph, inputs, provider) {
      const run = compiledContent(compiled);
      const original = serializationGenerationTokens.get(generation);
      if (original === undefined) throw new TypeError('Foreign Client Content generation');
      return compiledRunResult(moon.clientProgramStartGeneratedInferInputs(
        run, original, graph, inputs, provider), 'RunHostContentInferInputRejected');
    },
    startCheckedClientOriginalGeneratedInferExecution(compiled, generation, prepared, graph, provider,
      definition, consumer, readRetainedBytes, readExecutionBytes, modelRetainedBytes, modelExecutionBytes) {
      const run = compiledContent(compiled);
      const original = serializationGenerationTokens.get(generation);
      if (original === undefined) throw new TypeError('Foreign Client Content generation');
      return compiledRunResult(moon.clientProgramStartOriginalGeneratedInferExecution(
        prepared, run, original, graph, provider, token(definition), consumer,
        readRetainedBytes, readExecutionBytes, modelRetainedBytes, modelExecutionBytes),
      'RunHostContentInferInputRejected');
    },
    startCheckedClientOriginalGeneratedInferInputs(compiled, generation, graph, inputs, provider,
      definition, consumer, readRetainedBytes, readExecutionBytes, modelRetainedBytes, modelExecutionBytes) {
      const run = compiledContent(compiled);
      const original = serializationGenerationTokens.get(generation);
      if (original === undefined) throw new TypeError('Foreign Client Content generation');
      return compiledRunResult(moon.clientProgramStartOriginalGeneratedInferInputs(
        run, original, graph, inputs, provider, token(definition), consumer,
        readRetainedBytes, readExecutionBytes, modelRetainedBytes, modelExecutionBytes),
      'RunHostContentInferInputRejected');
    },
    startCheckedClientRestoredGeneratedInferExecution(compiled, definition, generation,
      prepared, graph, provider, bodies, snapshot, available) {
      const run = compiledContent(compiled);
      const original = serializationGenerationTokens.get(generation);
      if (original === undefined || typeof available !== 'function') {
        throw new TypeError('Foreign Client Content generation');
      }
      return compiledRunResult(moon.clientProgramStartRestoredGeneratedInferInput(
        prepared, run, token(definition), original, graph, bodies.registry, bodies.values,
        provider, snapshot.binding, snapshot.descriptorWire, snapshot.rows, available,
        bodies.fragment, bodies.ordered), 'RunHostContentInferInputRejected');
    },
    startCheckedClientRestoredGeneratedInferInputs(compiled, definition, generation,
      graph, inputs, provider, snapshot, available) {
      const run = compiledContent(compiled);
      const original = serializationGenerationTokens.get(generation);
      if (original === undefined || typeof available !== 'function') {
        throw new TypeError('Foreign Client Content generation');
      }
      return compiledRunResult(moon.clientProgramStartRestoredGeneratedInferInputs(
        run, token(definition), original, graph, inputs, provider, snapshot.binding,
        snapshot.descriptorWire, available), 'RunHostContentInferInputRejected');
    },
    startCheckedClientOriginalContentInferObservation(executions, generations, capacity, limits) {
      if (!Array.isArray(generations)) throw new TypeError('Invalid Content capture inventory');
      const originals = generations.map(generation => {
        const original = serializationGenerationTokens.get(generation);
        if (original === undefined) throw new TypeError('Foreign Client Content generation');
        return original;
      });
      // Project the SAME private generation tokens as the input constructor.
      // The existing typed issuer alone checks Run/Scope/current/complete
      // inventory; this projection adds no callbackful evidence recheck.
      return compiledRunResult(executions.length === 1
        ? moon.clientProgramStartOriginalInferObservationIssuance(executions[0],
          capacity, limits.maxSlots, limits.maxWireBytes, limits.maxWork, originals)
        : moon.clientProgramStartCompleteOriginalInferObservationIssuance(executions,
          capacity, limits.maxSlots, limits.maxWireBytes, limits.maxWork, originals),
      'RunHostContentInferObservationRejected');
    },
    startCheckedClientContentInferObservation(compiled, executions, generations, ledger, limits) {
      const run = compiledContent(compiled);
      if (!Array.isArray(generations)) throw new TypeError('Invalid Content capture inventory');
      const originals = generations.map(generation => {
        const original = serializationGenerationTokens.get(generation);
        if (original === undefined ||
            moon.clientProgramSerializationGenerationEvidence(original, run) === undefined) {
          throw new TypeError('Foreign Client Content generation');
        }
        return original;
      });
      return compiledRunResult(moon.clientProgramStartContentInferObservationIssuance(
        executions, originals, ledger, limits.maxSlots, limits.maxWireBytes, limits.maxWork),
      'RunHostContentInferObservationRejected');
    },
    prepareCheckedClientAcquiredSerializationGraph(checkedProgram, options) {
      return prepareAcquiredSerializationGraph(checkedProgram, options, false);
    },
    prepareCheckedClientAcquiredSerializationComponent(checkedProgram, options) {
      return prepareAcquiredSerializationGraph(checkedProgram, options, true);
    },
    prepareCheckedClientRequestAcquiredSerializationGraph(parent, input, contracts, checkedProgram, options, intermediate, modelOccurrence) {
      return prepareAcquiredSerializationGraph(checkedProgram, options, intermediate, {parent, input, contracts, modelOccurrence});
    },
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
      return retained.original;
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
      return Object.freeze({factsWire: explanation.factsWire});
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
        if (typeof acknowledgeExplanationCapture === 'function') {
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
    adoptCheckedClientEffectSerializationRun(allowed, definition) {
      const value = compiledRunResult(moon.clientProgramEffectAllowedSerializationRun(allowed),
        'RunHostEffectContentAdmissionRejected');
      if (!moon.clientProgramCheckCompiledRunDefinition(value, token(definition))) {
        throw new TypeError('Effect Content Run Definition differs from admission');
      }
      const result = Object.freeze({kind: 'serialization',
        template: inspectEvidence(moon.clientProgramCompiledRunTemplate(value)),
        compiledPlan: inspect(moon.clientProgramCompiledRunPlan(value)),
        preparedEvidence: inspectEvidence(moon.clientProgramCompiledRunPrepared(value)),
        authorization: inspectEvidence(moon.clientProgramCompiledRunAuthorization(value)),
        admission: inspectAdmission(moon.clientProgramCompiledRunAdmission(value))});
      compiledRunTokens.set(result, value);
      return result;
    },
    prepareCheckedClientEffectContentOriginal(prepared, compiled, compilation, definition, graph,
      bodies, workspace, physical, retain) {
      const value = compiledContent(compiled), component = serializationPlanTokens.get(graph);
      if (component === undefined || moon.clientProgramCompiledRunSerializationGraph(value) !== component) {
        throw new TypeError('Foreign Content compilation graph');
      }
      return checked(moon.clientProgramInstalledEffectContentPreparationPrepare(prepared,
        value, compilation, token(definition), component, bodies.registry, bodies.values,
        bodies.fragment, bodies.ordered, workspace, physical.cancel, physical.stopped, physical.cleanup, retain));
    },
    compiledSerializationGraph(compiled) {
      const value = compiledContent(compiled);
      const graph = moon.clientProgramCompiledRunSerializationGraph(value);
      if (graph === undefined) throw new TypeError('Content compilation graph unavailable');
      const coordinates = moon.clientProgramSerializationPlanGraphCoordinates(graph);
      const selected = Object.freeze({task: runtimeField(coordinates, 0), step: runtimeField(coordinates, 1),
        wire: moon.clientProgramSerializationPlanGraphWire(graph)});
      serializationPlanTokens.set(selected, graph);
      return selected;
    },
    prepareRequestSerializationOutputDemand(parent, input, compiled, selection, fields, output) {
      const graph = serializationPlanTokens.get(selection);
      if (graph === undefined) throw new TypeError('Foreign Content compilation graph');
      // Nominal map lookup only; actual same-Graph/Task and current checks are
      // performed after the original Request funds its Common constructor.
      return checked(moon.clientProgramPrepareRequestSerializationOutputDemand(
        parent, input, compiledContent(compiled), graph, ...fields,
        ...resultOutputLimitFields.map(name => output[name])));
    },
    checkedClientSerializationInputRows(compiled, selection) {
      const value = compiledContent(compiled), graph = serializationPlanTokens.get(selection);
      if (graph === undefined || moon.clientProgramCompiledRunSerializationGraph(value) !== graph) {
        throw new TypeError('Foreign Content compilation graph');
      }
      const rows = moon.clientProgramSerializationInputRowBound(graph);
      if (!Number.isSafeInteger(rows) || rows < -1) throw new TypeError('Invalid Content input row bound');
      return rows < 0 ? undefined : rows;
    },
    checkedClientSerializationGenerationLimits(compiled, selection) {
      const value = compiledContent(compiled);
      const graph = serializationPlanTokens.get(selection);
      if (graph === undefined || moon.clientProgramCompiledRunSerializationGraph(value) !== graph) {
        throw new TypeError('Foreign Content compilation graph');
      }
      // Read only the same nominal compiler output, not the caller-visible
      // wire/coordinates. These quantities constrain generation; they supply
      // neither current permission nor physical capacity or cleanup evidence.
      const coordinates = moon.clientProgramSerializationPlanGraphCoordinates(graph);
      const id = `task_${runtimeField(coordinates, 0)}_serialize_${runtimeField(coordinates, 1)}`;
      const body = JSON.parse(moon.clientProgramSerializationPlanGraphWire(graph));
      const nodes = body.nodes?.filter(node => node.kind === 'content_barrier' && node.node_id === id);
      const bounds = nodes?.length === 1 ? nodes[0].barrier?.serialization?.bounds : undefined;
      if (bounds === undefined || !['max_rows', 'max_bytes'].every(name =>
        Number.isInteger(bounds[name]) && bounds[name] >= 0 && bounds[name] <= 2147483647)) {
        throw new TypeError('Content compilation generation bounds unavailable');
      }
      const fieldCount = moon.clientProgramSerializationJsonLeafFieldCount(graph);
      if (!Number.isSafeInteger(fieldCount) || fieldCount < -1) {
        throw new TypeError('Content compilation input shape unavailable');
      }
      return Object.freeze({maxRows: bounds.max_rows, maxBytes: bounds.max_bytes,
        jsonLeafFields: fieldCount < 0 ? undefined : fieldCount});
    },
    inferSerializationGraph(inferGraph) {
      const graph = moon.clientProgramInferPlanSerializationGraph(inferGraph);
      if (graph === undefined) return undefined;
      const coordinates = moon.clientProgramSerializationPlanGraphCoordinates(graph);
      const selected = Object.freeze({task: runtimeField(coordinates, 0), step: runtimeField(coordinates, 1),
        wire: moon.clientProgramSerializationPlanGraphWire(graph)});
      serializationPlanTokens.set(selected, graph);
      return selected;
    },
    compiledSerializationPolicy(compiled) {
      const value = compiledContent(compiled);
      const body = moon.clientProgramSerializationPolicyBody(value);
      return body === undefined ? undefined : Object.freeze({kind: runtimeField(body, 0), cid: runtimeField(body, 1), wire: runtimeField(body, 2)});
    },
    bindCheckedClientSerializationCapture(checkedProgram, graph, captured, observation) {
      const selection = serializationPlanTokens.get(graph);
      if (selection === undefined) throw new TypeError('Foreign Content compilation graph');
      if (typeof captured?.capture?.source !== 'function' || captured.logicalInput === undefined) {
        throw new TypeError('Invalid Content Source capture');
      }
      if (captured.inputKind === 'whole-input') {
        if (captured.wholeCapacity === undefined || observation.keyedObservation !== undefined) {
          throw new TypeError('Invalid Whole Content Source capture');
        }
        return compiledRunResult(moon.clientProgramAdmitSerializationWholeCapturedInput(
          checkedProgram, selection, captured.capture.source(), captured.identity,
          captured.wholeCapacity, captured.logicalInput, observation.sourceEvidenceWire,
          observation.authorityScopeCid, observation.captureStartedAt, observation.captureCompletedAt),
        'RunHostContentCaptureRejected');
      }
      return compiledRunResult(moon.clientProgramAdmitSerializationCapturedInput(
        checkedProgram, selection, captured.capture.source(), captured.identity,
        captured.requirement, captured.logicalInput, observation.sourceEvidenceWire,
        observation.authorityScopeCid, observation.captureStartedAt, observation.captureCompletedAt,
        observation.keyedObservation?.observation),
      'RunHostContentCaptureRejected');
    },
    bindCheckedClientSerializationInputIdentity(compiled, input, receipt, limits, captured) {
      const value = compiledContent(compiled);
      issuanceLimits(limits, 'Content input Artifact');
      const evidence = compiledRunResult(moon.clientProgramSerializationInputIdentityBind(
        value, input, receipt, limits.maxWireBytes, limits.maxNodes, limits.maxDepth, captured),
      'RunHostContentInputIdentityRejected');
      const result = inspectEvidence(moon.clientProgramSerializationInputArtifact(evidence));
      serializationInputEvidenceTokens.set(result, evidence);
      return result;
    },
    bindCheckedClientEffectSerializationCapture(compiled, checkedEffect, captured, observation) {
      const value = compiledContent(compiled);
      if (typeof captured?.capture?.source !== 'function' || captured.logicalInput === undefined) {
        throw new TypeError('Invalid Effect Content Source capture');
      }
      const whole = captured.inputKind === 'whole-input';
      const original = whole ? captured.wholeCapacity : captured.requirement;
      if (original === undefined) throw new TypeError('Invalid Effect Content Source original');
      const admit = whole ? moon.clientProgramAdmitEffectSerializationWholeCapturedInput
        : moon.clientProgramAdmitEffectSerializationCapturedInput;
      return compiledRunResult(admit(
        value, checkedEffect, captured.capture.source(), captured.identity,
        original, captured.logicalInput, observation.sourceEvidenceWire,
        observation.authorityScopeCid, observation.captureStartedAt, observation.captureCompletedAt),
      'RunHostEffectContentCaptureRejected');
    },
    completeCheckedClientContentStep(compiled, definition, step, inputEvidence, candidate,
      content, available, limits) {
      const value = compiledContent(compiled);
      const identity = serializationInputEvidenceTokens.get(inputEvidence);
      if (identity === undefined) throw new TypeError('Foreign Content input identity');
      const generation = compiledRunResult(moon.clientProgramCompleteContentStep(
        step, value, token(definition), identity, candidate, content, available,
        limits.maxNodes, limits.maxTextBytes, limits.maxDepth, limits.maxWork, limits.maxNameBytes),
      'RunHostContentGenerationRejected');
      const result = Object.freeze({});
      serializationGenerationTokens.set(result, generation);
      return result;
    },
    completeCheckedClientSerializationGeneration(compiled, definition, input, inputEvidence, candidate,
      content, available, limits) {
      const value = compiledContent(compiled);
      const identity = serializationInputEvidenceTokens.get(inputEvidence);
      if (identity === undefined) throw new TypeError('Foreign Content input identity');
      const generation = compiledRunResult(moon.clientProgramSerializationGeneration(
        value, token(definition), input, identity, candidate, content, available, limits.maxNodes,
        limits.maxTextBytes, limits.maxDepth, limits.maxWork, limits.maxNameBytes),
      'RunHostContentGenerationRejected');
      const result = Object.freeze({});
      serializationGenerationTokens.set(result, generation);
      return result;
    },
    readmitCheckedClientSerializationGeneration(compiled, definition, graph, scope,
      expectedGenerationCid, evidence, candidate, content) {
      const run = compiledContent(compiled);
      const generation = compiledRunResult(moon.clientProgramReadmitSerializationGeneration(
        run, token(definition), graph, scope, expectedGenerationCid,
        evidenceToken(evidence.input), evidenceToken(evidence.derivation),
        evidenceToken(evidence.generation), candidate, content),
      'RunHostContentGenerationRecoveryRejected');
      const result = Object.freeze({});
      serializationGenerationTokens.set(result, generation);
      return result;
    },
    checkedClientSerializationByteHoldingCid(compiled, definition, storeAuthorityCid) {
      const value = compiledContent(compiled);
      return compiledRunResult(moon.clientProgramSerializationByteHoldingCid(
        value, token(definition), storeAuthorityCid), 'Client Content byte binding unavailable');
    },
    capturedContentGenerationCount(captured) {
      return compiledRunResult(moon.clientCapturedContentGenerationCount(token(captured)),
        'Captured Content inventory unavailable');
    },
    capturedContentGenerationStorage(captured, definition, storeAuthorityCid, index) {
      if (!Number.isSafeInteger(index) || index < 0) {
        throw new TypeError('Invalid Captured Content occurrence');
      }
      const value = compiledRunResult(moon.clientCapturedContentGenerationStorage(
        token(captured), token(definition), storeAuthorityCid, index),
      'Captured Content storage binding unavailable');
      return Object.freeze({holdingCid: runtimeField(value, 0), manifestCid: runtimeField(value, 1),
        contentCid: runtimeField(value, 2), byteCount: runtimeField(value, 3),
        bindings: Object.freeze(runtimeField(value, 4).map(binding => Object.freeze({
          name: runtimeField(binding, 0), semanticCid: runtimeField(binding, 1), wire: runtimeField(binding, 2), holdingCid: runtimeField(binding, 3),
        })))});
    },
    checkedClientSerializationRecoveryBindings(compiled, generation, storeAuthorityCid) {
      const value = compiledRunTokens.get(compiled);
      const completion = serializationGenerationTokens.get(generation);
      if (value === undefined || completion === undefined) {
        throw new TypeError('Foreign Client Content generation');
      }
      const bindings = compiledRunResult(moon.clientProgramSerializationRecoveryBindings(completion,
        value, storeAuthorityCid), 'Client Content recovery binding unavailable');
      return Object.freeze(bindings.map(binding => Object.freeze({
        name: runtimeField(binding, 0), semanticCid: runtimeField(binding, 1), wire: runtimeField(binding, 2), holdingCid: runtimeField(binding, 3),
      })));
    },
    checkedClientSerializationGenerationOutput(compiled, generation) {
      const value = compiledRunTokens.get(compiled);
      const completion = serializationGenerationTokens.get(generation);
      if (value === undefined || completion === undefined) {
        throw new TypeError('Foreign Client Content generation');
      }
      const output = moon.clientProgramSerializationGenerationOutput(completion, value);
      if (output === undefined) throw new TypeError('Client Content generation unavailable');
      return output;
    },
    exportCheckedClientContentGenerationOutput(compiled, definition, generation, storeAuthorityCid) {
      const value = compiledRunTokens.get(compiled);
      const completion = serializationGenerationTokens.get(generation);
      if (value === undefined || completion === undefined) {
        throw new TypeError('Foreign Client Content generation');
      }
      const exported = compiledRunResult(moon.clientProgramExportContentGenerationOutput(
        completion, value, token(definition), storeAuthorityCid),
      'Client Content completion export unavailable');
      return Object.freeze({binding: runtimeField(exported, 0), descriptorWire: runtimeField(exported, 1),
        rows: Object.freeze(runtimeField(exported, 2).slice())});
    },
    checkedClientSerializationGenerationEvidence(compiled, generation) {
      const value = compiledRunTokens.get(compiled);
      const completion = serializationGenerationTokens.get(generation);
      if (value === undefined || completion === undefined) {
        throw new TypeError('Foreign Client Content generation');
      }
      const evidence = moon.clientProgramSerializationGenerationEvidence(completion, value);
      if (evidence === undefined) throw new TypeError('Client Content generation unavailable');
      return inspectEvidence(evidence);
    },
    prepareCheckedClientRetainedContentOutput(compiled, definition, generation,
      storeAuthorityCid, completion, available) {
      const run = compiledRunTokens.get(compiled);
      const original = serializationGenerationTokens.get(generation);
      if (run === undefined || original === undefined || typeof available !== 'function') {
        throw new TypeError('Foreign Client retained Content output');
      }
      return compiledRunResult(moon.clientProgramPrepareRetainedContentOutput(
        original, run, token(definition), storeAuthorityCid, completion.binding,
        completion.descriptorWire, completion.rows, available),
      'Client Content completion recovery unavailable');
    },
    checkedClientCompiledEffectProgram(compiled, checkedEffect) {
      const value = compiledRunTokens.get(compiled);
      const original = value === undefined ? undefined
        : moon.clientProgramCompiledEffectProgram(value, checkedEffect);
      if (original === undefined) throw new TypeError('Foreign Client compiled Effect Run');
      return original;
    },
    checkedClientSerializationGenerationDerivation(compiled, generation) {
      const value = compiledRunTokens.get(compiled);
      const completion = serializationGenerationTokens.get(generation);
      if (value === undefined || completion === undefined) {
        throw new TypeError('Foreign Client Content generation');
      }
      const evidence = moon.clientProgramSerializationGenerationDerivation(completion, value);
      if (evidence === undefined) throw new TypeError('Client Content generation unavailable');
      return inspectEvidence(evidence);
    },
    issueCheckedClientSerializationInvocation(compiled, definition, generation, limits) {
      const value = compiledRunTokens.get(compiled);
      const completion = serializationGenerationTokens.get(generation);
      if (value === undefined || completion === undefined) {
        throw new TypeError('Foreign Client Content generation');
      }
      limits = captureContractLimits(limits, 'Content Invocation');
      const issued = compiledRunResult(moon.clientProgramIssueSerializationInvocation(
        value, token(definition), completion,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth), 'RunHostContentInvocationRejected');
      return Object.freeze({observation: inspectEvidence(runtimeField(issued, 0)),
        invocation: inspect(runtimeField(issued, 1), limits), owner: runtimeField(issued, 1)});
    },
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
    clientRequiresQueryTime(prepared) {
      if (typeof moon.clientProgramRequiresQueryTime !== 'function') return false;
      const value = checked(moon.clientProgramRequiresQueryTime(prepared, 100000, 100000));
      if (typeof value !== 'boolean') throw new TypeError('Invalid Client query-time requirement');
      return value;
    },
    prepareClientQueryTime(prepared, request, createdAt) {
      if (typeof moon.clientProgramPrepareQueryTime !== 'function') {
        throw new TypeError('Client query-time preparation unavailable');
      }
      return checked(moon.clientProgramPrepareQueryTime(prepared, request, createdAt));
    },
    bindClientQueryTime(original, prepared, compiled, definition, request) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || typeof moon.clientProgramBindQueryTime !== 'function') {
        throw new TypeError('Foreign Client query-time compilation');
      }
      return checked(moon.clientProgramBindQueryTime(original, prepared, value, token(definition), request));
    },
    clientQueryTimeInvocationOriginal(original, prepared) {
      const project = moon.clientProgramQueryTimeInvocationOriginal;
      if (typeof project !== 'function') throw new TypeError('Client query-time original unavailable');
      // Opaque Option from the matching Core; never synthesize a JS tuple.
      return Reflect.apply(project, moon, [original, prepared]);
    },
    checkedClientManagedQueryInvocationOriginal(run, prepared, original) {
      const project = moon.clientProgramInstalledManagedRunInvocationOriginal;
      if (typeof project !== 'function') throw new TypeError('Client query-time original unavailable');
      const retained = Reflect.apply(project, moon, [run, prepared]);
      const compiled = compiledRunTokens.get(original.compiled);
      if (compiled === undefined || original.preparedProgram !== prepared ||
          runtimeOptionalField(retained, 0) !== original.queryTimePreparation ||
          runtimeOptionalField(retained, 1) !== original.requestIdentity ||
          runtimeOptionalField(retained, 2) !== compiled ||
          runtimeOptionalField(retained, 3) !== token(original.runDefinition) ||
          moon.clientProgramQueryTimeContext(original.queryTimePreparation) !== original.queryTime) {
        throw new TypeError('Foreign Client original query-time invocation');
      }
      control.checkClientCompiledRunOwner(original.compiled, prepared);
      return original;
    },
    restoreClientQueryTime(prepared, compiled, definition, request) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || typeof moon.clientProgramRestoreQueryTimePreparation !== 'function') {
        throw new TypeError('Foreign Client query-time compilation');
      }
      const preparation = checked(moon.clientProgramRestoreQueryTimePreparation(prepared, value, token(definition), request));
      const context = moon.clientProgramQueryTimeContext(preparation);
      if (context === undefined) throw new TypeError('Client query-time context unavailable');
      return Object.freeze({queryTimePreparation:preparation,queryTime:context});
    },
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
    prepareCheckedClientRequestSerializationCompilation(parent, input, graph, contracts) {
      const original = serializationPlanTokens.get(graph);
      if (original === undefined) throw new TypeError('Foreign Content compilation graph');
      const compile = moon.clientProgramPrepareRequestSerializationCompilation;
      if (typeof compile !== 'function') throw new TypeError('Request Content compiler unavailable');
      // The actual typed constructor checks this SAME parent/input, checked
      // graph and contracts. No graph token or rebuilt compilation escapes.
      return compiledRunResult(Reflect.apply(compile, moon, [parent, input, original, contracts]),
        'RunHostTaskCompilationRejected');
    },
    prepareCheckedClientRequestKeyedSerializationCompilation(parent, input, selected, graph) {
      const original = serializationPlanTokens.get(graph);
      if (original === undefined) throw new TypeError('Foreign Content compilation graph');
      const compile = moon.clientProgramPrepareRequestKeyedSerializationCompilation;
      if (typeof compile !== 'function') throw new TypeError('Request keyed Content compiler unavailable');
      return compiledRunResult(Reflect.apply(compile, moon, [parent, input, selected, original]),
        'RunHostTaskCompilationRejected');
    },
    prepareCheckedClientRequestSerializationPlan(parent, input, request, compiled, definition,
      limits, workspace) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'serialization') {
        throw new TypeError('Foreign Client compiled Content preparation');
      }
      const prepare = moon.clientProgramPrepareRequestSerializationPlan;
      if (typeof prepare !== 'function') throw new TypeError('Request Content Plan unavailable');
      return checked(Reflect.apply(prepare, moon, [parent, input, request, value, token(definition),
        limits.maxRows, limits.maxWork, limits.maxEntries, limits.maxValueBytes,
        limits.maxValueNodes, limits.maxValueDepth, limits.maxFrames, workspace]));
    },
    prepareCheckedClientRequestModelSerializationPlan(parent, input, request, compiled, definition,
      limits, workspace, queryTime) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      const prepare = moon.clientProgramPrepareRequestModelSerializationPlan;
      if (typeof prepare !== 'function') throw new TypeError('Request Model Content Plan unavailable');
      return checked(Reflect.apply(prepare, moon, [parent, input, request, value, token(definition),
        limits.maxRows, limits.maxWork, limits.maxEntries, limits.maxValueBytes,
        limits.maxValueNodes, limits.maxValueDepth, limits.maxFrames, workspace, queryTime]));
    },
    prepareCheckedClientEffectModelDemand(prepared, compiled, compilation, definition, occurrence, graph) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      // The nominal JS holder is not the native compiled Run. Unwrap only
      // its existing private association; Core binds the complete original
      // Effect/compilation/definition/occurrence tuple without another issuer.
      return checked(moon.clientProgramInstalledEffectModelDemandPrepare(
        prepared, value, compilation, token(definition), occurrence, graph));
    },
    prepareCheckedClientNodeEffectModelDemand(prepared, compiled, compilation, definition,
      occurrence, graph, selected, installation) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      const node = installation.nodeInstallation, census = installation.bootstrap;
      return checked(moon.clientProgramInstalledNodeEffectModelDemandPrepare(
        prepared, value, compilation, token(definition), occurrence, graph, selected,
        node.layout, node.installation, node.runtimeArtifactCid, node.layoutArtifactCid, node.probability,
        installation.modelRetainedBytes, installation.modelExecutionBytes,
        census.maxReservations, census.maxHoldings, census.maxDelegations,
        census.bootstrapRetainedBytes, census.bootstrapExecutionBytes));
    },
    prepareCheckedClientRequestModelSourceFreeModule(parent, input, request, compiled, definition, compilation, contracts, retainedOutput, queryTime) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      const prepare = moon.clientProgramPrepareRequestModelSourceFreeModule;
      if (typeof prepare !== 'function') throw new TypeError('Request Model module constructor unavailable');
      // Same existing private originals, never the wire/identity facade.
      return checked(Reflect.apply(prepare, moon, [parent, input, request, value, token(definition), compilation, contracts, retainedOutput, queryTime]));
    },
    prepareCheckedClientRequestModelSourceFreeComponentModule(parent, input, request, compiled, definition,
      compilation, contracts, retainedOutput, queryTime, construct) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      const prepare = moon.clientProgramPrepareRequestModelSourceFreeComponentModule;
      if (typeof prepare !== 'function' || typeof construct !== 'function') {
        throw new TypeError('Request Model component constructor unavailable');
      }
      return checked(Reflect.apply(prepare, moon, [parent, input, request, value,
        token(definition), compilation, contracts, retainedOutput, queryTime, construct]));
    },
    prepareCheckedClientRequestModelsSourceFreeComponentModule(parent, input, request, compiled, definition,
      compilation, contracts, retainedOutput, queryTime, construct) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      const prepare = moon.clientProgramPrepareRequestModelsSourceFreeComponentModule;
      if (typeof prepare !== 'function' || typeof construct !== 'function') {
        throw new TypeError('Request Model components constructor unavailable');
      }
      return checked(Reflect.apply(prepare, moon, [parent, input, request, value,
        token(definition), compilation, contracts, retainedOutput, queryTime, construct]));
    },
    prepareCheckedClientRequestModelsProviderComponentCaptureModule(parent, input, request, compiled, definition,
      compilation, declarations, providers, query, evidence, transport, scratch, contracts, retainedOutput, queryTime, construct) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      const prepare = moon.clientProgramPrepareRequestModelsProviderComponentCaptureModule;
      if (typeof prepare !== 'function' || typeof construct !== 'function') {
        throw new TypeError('Request Model components constructor unavailable');
      }
      return checked(Reflect.apply(prepare, moon, [parent, input, request, value,
        token(definition), compilation, declarations, providers, query, evidence, transport, scratch, contracts, retainedOutput, queryTime, construct]));
    },
    prepareCheckedClientRequestModelCaptureModule(parent, input, request, compiled, definition, compilation,
      declarations, query, evidence, transport, scratch, contracts, retainedOutput, queryTime) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      const prepare = moon.clientProgramPrepareRequestModelCaptureModule;
      if (typeof prepare !== 'function') throw new TypeError('Request Model module constructor unavailable');
      // Same existing private originals, never the wire/identity facade.
      return checked(Reflect.apply(prepare, moon, [parent, input, request, value, token(definition), compilation, declarations, query, evidence,
        transport, scratch, contracts, retainedOutput, queryTime]));
    },
    prepareCheckedClientRequestModelComponentCaptureModule(parent, input, request, compiled, definition, compilation,
      declarations, query, evidence, transport, scratch, contracts, retainedOutput, queryTime, construct) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      const prepare = moon.clientProgramPrepareRequestModelComponentCaptureModule;
      if (typeof prepare !== 'function' || typeof construct !== 'function') {
        throw new TypeError('Request Model component constructor unavailable');
      }
      return checked(Reflect.apply(prepare, moon, [parent, input, request, value, token(definition), compilation,
        declarations, query, evidence, transport, scratch, contracts, retainedOutput, queryTime, construct]));
    },
    prepareCheckedClientRequestModelWholeInputsComponentCaptureModule(parent, input, request, compiled, definition, compilation,
      wholeSources, query, evidence, transport, scratch, contracts, retainedOutput, queryTime, construct) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      const prepare = moon.clientProgramPrepareRequestModelWholeInputsComponentCaptureModule;
      if (typeof prepare !== 'function' || typeof construct !== 'function') {
        throw new TypeError('Request Model component constructor unavailable');
      }
      return checked(Reflect.apply(prepare, moon, [parent, input, request, value, token(definition), compilation,
        wholeSources, query, evidence, transport, scratch, contracts, retainedOutput, queryTime, construct]));
    },
    prepareCheckedClientRequestModelProviderCaptureModule(parent, input, request, compiled, definition, compilation,
      declaration, provider, query, evidence, transport, scratch, contracts, retainedOutput, queryTime) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      const prepare = moon.clientProgramPrepareRequestModelProviderCaptureModule;
      if (typeof prepare !== 'function') throw new TypeError('Request Model module constructor unavailable');
      // Same existing private originals, never the wire/identity facade.
      return checked(Reflect.apply(prepare, moon, [parent, input, request, value, token(definition), compilation, declaration, provider, query, evidence,
        transport, scratch, contracts, retainedOutput, queryTime]));
    },
    prepareCheckedClientRequestModelProviderComponentCaptureModule(parent, input, request, compiled, definition, compilation,
      declaration, provider, query, evidence, transport, scratch, contracts, retainedOutput, queryTime, bindOriginal) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      const prepare = moon.clientProgramPrepareRequestModelProviderComponentCaptureModule;
      if (typeof prepare !== 'function') throw new TypeError('Request Model module constructor unavailable');
      // Same existing private originals, never the wire/identity facade.
      return checked(Reflect.apply(prepare, moon, [parent, input, request, value, token(definition), compilation, declaration, provider, query, evidence,
        transport, scratch, contracts, retainedOutput, queryTime, bindOriginal]));
    },
    prepareCheckedClientRequestModelDuckDBComponentCaptureModule(parent, input, request, compiled, definition, compilation,
      sourceRef, schema, table, query, evidence, receipts, transport, scratch, contracts, retainedOutput, queryTime, bindOriginal) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      const prepare = moon.clientProgramPrepareRequestModelDuckDBComponentCaptureModule;
      if (typeof prepare !== 'function') throw new TypeError('Request Model module constructor unavailable');
      // Same existing private originals, never the wire/identity facade.
      return checked(Reflect.apply(prepare, moon, [parent, input, request, value, token(definition), compilation, sourceRef, schema, table, query, evidence, receipts,
        transport, scratch, contracts, retainedOutput, queryTime, bindOriginal]));
    },
    prepareCheckedClientRequestModelsDuckDBComponentCaptureModule(parent, input, request, compiled, definition, compilation,
      sourceRef, schema, table, query, evidence, receipts, transport, scratch, contracts, retainedOutput, queryTime, bindOriginal) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      const prepare = moon.clientProgramPrepareRequestModelsDuckDBComponentCaptureModule;
      if (typeof prepare !== 'function') throw new TypeError('Request Model module constructor unavailable');
      // Same existing private originals, never the wire/identity facade.
      return checked(Reflect.apply(prepare, moon, [parent, input, request, value, token(definition), compilation, sourceRef, schema, table, query, evidence, receipts,
        transport, scratch, contracts, retainedOutput, queryTime, bindOriginal]));
    },
    reserveCheckedClientRequestModelRecoveryMaterials(parent, input, request, definition, count, wireAt, containers) {
      const reserve = moon.clientProgramReserveRequestModelRecoveryMaterials;
      if (typeof reserve !== 'function') throw new TypeError('Installed Model recovery material reservation unavailable');
      return checked(Reflect.apply(reserve, moon, [parent, input, request, token(definition), count, wireAt, containers]));
    },
    checkedClientRequestModelRecoverySourceCoordinates(parent, input, request, definition, prepared) {
      const select = moon.clientProgramRequestModelRecoverySourceCoordinates;
      if (typeof select !== 'function') throw new TypeError('Installed Model recovery Source unavailable');
      return checked(Reflect.apply(select, moon, [parent, input, request, token(definition), prepared]));
    },
    checkedClientRequestModelRecoveryLedger(parent, input, request, definition) {
      const borrow = moon.clientProgramRequestModelRecoveryLedger;
      if (typeof borrow !== 'function') throw new TypeError('Installed Model recovery Ledger unavailable');
      return checked(Reflect.apply(borrow, moon, [parent, input, request, token(definition)]));
    },
    checkedClientRequestModelRecoveryUsageIsolated(parent, input, request, definition, dag) {
      const inspect = moon.clientProgramRequestModelRecoveryUsageIsolated;
      if (typeof inspect !== 'function') throw new TypeError('Installed Model recovery usage unavailable');
      return Reflect.apply(inspect, moon, [parent, input, request, token(definition), dag]);
    },
    openCheckedClientRequestModelRecoveryHost(parent, input, request, definition, prepared,
      sources, contracts, values, fragment, ordered, providers) {
      const open = moon.clientProgramOpenRequestModelRecoveryHost;
      if (typeof open !== 'function') throw new TypeError('Installed Model recovery Host unavailable');
      return checked(Reflect.apply(open, moon, [parent, input, request, token(definition), prepared,
        sources, contracts, values, fragment, ordered, providers]));
    },
    prepareCheckedClientRequestModelRecoveryReadScopes(parent, input, request, definition, prepared, compiled,
      graphs, bounds, modelRetained, modelExecution, readRetained, readExecution,
      maxReservations, maxHoldings, maxDelegations, quantityLimits) {
      control.checkClientCompiledRunOwner(compiled, prepared);
      control.checkClientCompiledRunDefinition(compiled, definition);
      if (compiled.kind !== 'infer') throw new TypeError('Foreign Client compiled Infer preparation');
      const value = compiledRunTokens.get(compiled);
      const prepare = moon[quantityLimits === undefined ? 'clientProgramPrepareRequestModelRecoveryReadScopes'
        : 'clientProgramPrepareRequestModelRecoveryReadScopesWithQuantities'];
      if (typeof prepare !== 'function') throw new TypeError('Installed Model recovery Scope unavailable');
      return checked(Reflect.apply(prepare, moon, [parent, input, request, token(definition), prepared, value,
        graphs, bounds, modelRetained, modelExecution, readRetained, readExecution,
        maxReservations, maxHoldings, maxDelegations,
        ...(quantityLimits === undefined ? [] : [quantityLimits.tokens, quantityLimits.costUnits, quantityLimits.durationMs])]));
    },
    prepareCheckedClientRequestModelsSourceFreePlan(parent, input, original, request, compiled, definition,
      occurrences, graphs, selected) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      const prepare = moon.clientProgramPrepareRequestModelsSourceFreePlan;
      if (typeof prepare !== 'function') throw new TypeError('Installed Model Plan unavailable');
      return checked(Reflect.apply(prepare, moon, [parent, input, original, request, value,
        token(definition), occurrences, graphs, selected]));
    },
    prepareCheckedClientRequestModelsCapturePlan(parent, input, original, request, compiled, definition,
      occurrences, graphs, selected) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      const prepare = moon.clientProgramPrepareRequestModelsCapturePlan;
      if (typeof prepare !== 'function') throw new TypeError('Installed Model Plan unavailable');
      return checked(Reflect.apply(prepare, moon, [parent, input, original, request, value,
        token(definition), occurrences, graphs, selected]));
    },
    prepareCheckedClientRequestModelSourceFreePlan(parent, input, original, request, compiled, definition,
      occurrence, graph, selected) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      const prepare = moon.clientProgramPrepareRequestModelSourceFreePlan;
      if (typeof prepare !== 'function') throw new TypeError('Installed Model Plan unavailable');
      // These are the original module, selected Limits and Run tokens. The
      // existing typed constructor checks their complete tuple; this binding
      // issues no Scope/Run and does not select bounds or compile again.
      return checked(Reflect.apply(prepare, moon, [parent, input, original, request, value,
        token(definition), occurrence, graph, selected]));
    },
    prepareCheckedClientRequestModelCapturePlan(parent, input, original, request, compiled, definition,
      occurrence, graph, selected) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      const prepare = moon.clientProgramPrepareRequestModelCapturePlan;
      if (typeof prepare !== 'function') throw new TypeError('Installed Model Plan unavailable');
      return checked(Reflect.apply(prepare, moon, [parent, input, original, request, value,
        token(definition), occurrence, graph, selected]));
    },
    prepareCheckedClientRequestNodeModelSourceFreePlan(parent, input, original, request, compiled, definition,
      occurrence, graph, selected, installation) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      const prepare = moon.clientProgramPrepareRequestNodeModelSourceFreePlan;
      if (typeof prepare !== 'function') throw new TypeError('Installed Node Model Plan unavailable');
      const node = installation.nodeInstallation, census = installation.bootstrap;
      // SAME immutable installed declaration and opaque selected bounds. The
      // typed constructor validates layout/originals and the Request admits
      // these actual extents before Scope/read; no JS Ledger is constructed.
      return checked(Reflect.apply(prepare, moon, [parent, input, original, request, value,
        token(definition), occurrence, graph, selected, node.layout, node.installation,
        node.runtimeArtifactCid, node.layoutArtifactCid, node.probability,
        installation.modelRetainedBytes, installation.modelExecutionBytes,
        census.maxReservations, census.maxHoldings, census.maxDelegations,
        census.bootstrapRetainedBytes, census.bootstrapExecutionBytes]));
    },
    prepareCheckedClientRequestNodeModelCapturePlan(parent, input, original, request, compiled, definition,
      occurrence, graph, selected, installation) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      const prepare = moon.clientProgramPrepareRequestNodeModelCapturePlan;
      if (typeof prepare !== 'function') throw new TypeError('Installed Node Model Plan unavailable');
      const node = installation.nodeInstallation, census = installation.bootstrap;
      // SAME immutable installed declaration and opaque selected bounds. The
      // typed constructor validates layout/originals and the Request admits
      // these actual extents before Scope/read; no JS Ledger is constructed.
      return checked(Reflect.apply(prepare, moon, [parent, input, original, request, value,
        token(definition), occurrence, graph, selected, node.layout, node.installation,
        node.runtimeArtifactCid, node.layoutArtifactCid, node.probability,
        installation.modelRetainedBytes, installation.modelExecutionBytes,
        census.maxReservations, census.maxHoldings, census.maxDelegations,
        census.bootstrapRetainedBytes, census.bootstrapExecutionBytes]));
    },
    bindCheckedClientMockModelCapturePlan(original, compiled, definition,
      occurrence, graph, selected) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      const bind = moon.clientProgramInstalledMockModelCapturePlanBind;
      if (typeof bind !== 'function') throw new TypeError('Installed Model Plan unavailable');
      return checked(Reflect.apply(bind, moon, [original, value, token(definition),
        occurrence, graph, selected]));
    },
    checkedClientMockModelRunRequirements(prepared, compiled, definition, occurrence, graph,
      declarations, query, evidence, transport, scratch, registry, values, fragment, ordered) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      return checked(moon.clientProgramInstalledMockModelManagedRunRequirements(
        prepared, value, token(definition), occurrence, graph, declarations,
        query, evidence, transport, scratch, registry, values, fragment, ordered));
    },
    prepareCheckedClientInferOriginalRead(compiled, definition, graph, scope, budget) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      return checked(moon.clientProgramPrepareInferOriginalRead(scope, value, token(definition),
        graph, budget.readRetainedBytes, budget.readExecutionBytes));
    },
    // Installation-only original bootstrap: caller custody must keep this
    // same scope on failure/recovery, never issue a replacement Ledger.
    // Initial allocation and the full preset projection require pre-funding
    // by the trusted installation; supplied numbers do not prove a layout.
    beginCheckedClientInferOriginalReadScope(compiled, definition, graph,
      {quantityCapacity, bootstrapRetainedBytes, bootstrapExecutionBytes,
        maxReservations, maxHoldings, maxDelegations}) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      return checked(moon.clientProgramBeginInferOriginalReadScope(value,
        token(definition), graph, inferQuantityCapacity(quantityCapacity), bootstrapRetainedBytes,
        bootstrapExecutionBytes, maxReservations, maxHoldings, maxDelegations));
    },
    checkedClientInferOriginalReadScopeLive(compiled, definition, graph, scope) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer' ||
          typeof moon.clientProgramInferOriginalReadScopeLive !== 'function') {
        throw new TypeError('InferTrustedRuntimeScopeUnavailable');
      }
      // This lifetime observation neither exposes a Ledger nor substitutes
      // for allocation/current authority/egress or confirmed park invalidation.
      return moon.clientProgramInferOriginalReadScopeLive(scope, value,
        token(definition), graph) === true;
    },
    prepareCheckedClientInferNodeReadLayout(compiled, definition, graph, scope,
      {layout, installation, runtimeArtifactCid, layoutArtifactCid, probability}) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      return checked(moon.clientProgramPrepareInferNodeReadLayout(scope, value,
        token(definition), graph, layout, installation,
        runtimeArtifactCid, layoutArtifactCid, probability));
    },
    // Data-only origin selection from the original checked Owner, before
    // park. Storage must be the same actual port's rechecked binding evidence;
    // matching strings/configuration cannot substitute for its opaque custody.
    checkedClientInferOriginalResourceOriginField(compiled, definition, graph, scope,
      {layout, installation, runtimeArtifactCid, layoutArtifactCid, probability}, storage, field) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      return checked(moon.clientProgramInferOriginalResourceOriginField(scope,
        value, token(definition), graph, layout, installation,
        runtimeArtifactCid, layoutArtifactCid, probability, evidenceToken(storage), field));
    },
    checkCheckedClientInferOriginalParkedStorageOrigin(compiled, definition, graph, scope,
      park, document, {layout, installation, runtimeArtifactCid, layoutArtifactCid, probability}, storage) {
      const value = compiledRunTokens.get(compiled);
      const original = modelOriginalDocumentTokens.get(document);
      if (value === undefined || compiled.kind !== 'infer' || original === undefined) {
        throw new TypeError('Foreign Client original Model document');
      }
      return checked(moon.clientProgramCheckInferOriginalParkedStorageOrigin(scope,
        value, token(definition), graph, park, original, layout, installation,
        runtimeArtifactCid, layoutArtifactCid, probability, evidenceToken(storage)));
    },
    // DATA-only comparison before a Scope exists. The existing Common Owner
    // reads expected origins from the checked Run/Plan, not this document.
    // Storage custody, funding and atomic original admission remain separate.
    checkCheckedClientInferOriginalPreRestoreOrigin(compiled, definition, graph, document, selected) {
      const value = compiledRunTokens.get(compiled);
      const original = modelOriginalDocumentTokens.get(document);
      if (value === undefined || compiled.kind !== 'infer' || original === undefined) {
        throw new TypeError('Foreign Client original Model document');
      }
      const originalDefinition = token(definition);
      if (typeof moon.clientProgramCheckInferOriginalPreRestoreOrigin !== 'function') {
        throw Object.assign(new Error('ClientOperationUnavailable'), {code: 'ClientOperationUnavailable'});
      }
      const {layout, installation, runtimeArtifactCid, layoutArtifactCid, probability} = selected;
      return checked(moon.clientProgramCheckInferOriginalPreRestoreOrigin(value,
        originalDefinition, graph, original, layout, installation,
        runtimeArtifactCid, layoutArtifactCid, probability));
    },
    // Explicit alternative to the normal descriptor issuer, not a fallback.
    // Bootstrap must already cover the dedicated Writer and finish-text borrow.
    prepareCheckedClientInferNodeReadState(compiled, definition, graph, scope,
      {layout, installation, runtimeArtifactCid, layoutArtifactCid, probability}, limits) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      issuanceLimits(limits, 'Original Model state Writer');
      if (['maxWireBytes', 'maxNodes', 'maxDepth'].some(key =>
        !Number.isSafeInteger(limits[key]) || limits[key] < 0 || limits[key] > 2147483647) ||
        limits.maxNodes === 0) {
        throw new TypeError('Invalid original Model state Writer limits');
      }
      return checked(moon.clientProgramPrepareInferNodeReadState(scope, value,
        token(definition), graph, layout, installation, runtimeArtifactCid,
        layoutArtifactCid, probability, limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
    },
    originalClientInferNodeReadStateRead(writer) {
      return checked(moon.clientProgramInferNodeReadStateRead(writer));
    },
    advanceCheckedClientInferNodeReadState(compiled, definition, graph, writer, quantum) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      if (!Number.isSafeInteger(quantum) || quantum < 1 || quantum > 2147483647) {
        throw new TypeError('Invalid original Model state Writer quantum');
      }
      const poll = moon.clientProgramInferNodeReadStatePoll(
        moon.clientProgramAdvanceInferNodeReadState(writer, value, token(definition), graph, quantum));
      return Object.freeze({kind: runtimeField(poll, 0), work: runtimeField(poll, 1), issue: runtimeField(poll, 2)});
    },
    finishCheckedClientInferNodeReadState(compiled, definition, graph, writer) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      return checked(moon.clientProgramFinishInferNodeReadState(writer, value, token(definition), graph));
    },
    stopCheckedClientInferNodeReadState(compiled, definition, graph, scope, writer) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      return checked(moon.clientProgramStopInferNodeReadState(writer, scope, value, token(definition), graph));
    },
    settleCheckedClientInferNodeReadState(compiled, definition, graph, writer, physicalCleanupComplete) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      if (typeof physicalCleanupComplete !== 'boolean') {
        throw new TypeError('Invalid original read cleanup observation');
      }
      return checked(moon.clientProgramSettleInferNodeReadState(writer, value,
        token(definition), graph, physicalCleanupComplete));
    },
    // Do not derive whole-Run cleanup from read refusal, AbortSignal or a
    // saved response. The original census also checks every live child.
    finishCheckedClientInferOriginalReadScope(compiled, definition, graph,
      scope, originalRunCleanupComplete) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      if (typeof originalRunCleanupComplete !== 'boolean') {
        throw new TypeError('Invalid original Run cleanup observation');
      }
      return checked(moon.clientProgramFinishInferOriginalReadScope(scope,
        value, token(definition), graph, originalRunCleanupComplete));
    },
    settleCheckedClientInferOriginalReadPreparation(compiled, definition, graph,
      read, physicalCleanupComplete) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      if (typeof physicalCleanupComplete !== 'boolean') {
        throw new TypeError('Invalid original read cleanup observation');
      }
      return checked(moon.clientProgramSettleInferOriginalReadPreparation(read,
        value, token(definition), graph, physicalCleanupComplete));
    },
    stopCheckedClientInferOriginalReadPreparation(compiled, definition, graph,
      scope, read) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      return checked(moon.clientProgramStopInferOriginalReadPreparation(scope,
        read, value, token(definition), graph));
    },
    claimCheckedClientInferOriginalComposedPreparation(compiled, definition, graph,
      read, readRetainedBytes, readExecutionBytes) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      return checked(moon.clientProgramClaimInferOriginalPreparation(read,
        value, token(definition), graph, readRetainedBytes, readExecutionBytes));
    },
    startCheckedClientOriginalComposedInferExecution(compiled, definition,
      occurrence, graph, prefix, inputs, provider, consumer, readRetainedBytes,
      readExecutionBytes, modelRetainedBytes, modelExecutionBytes, sources, inputBodyRead) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      return checked(moon.clientProgramStartOriginalComposedInferExecution(
        occurrence, graph, prefix, inputs, provider, value, token(definition),
        consumer, readRetainedBytes, readExecutionBytes, modelRetainedBytes,
        modelExecutionBytes, sources, inputBodyRead));
    },
    startCheckedClientOriginalRestoredComposedInferExecution(compiled, definition,
      occurrence, graph, prefix, provider, snapshot, custodyAvailable, savedScope,
      consumer, readRetainedBytes, readExecutionBytes, modelRetainedBytes,
      modelExecutionBytes, referenceIssuer, inputBodyRead) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      return checked(moon.clientProgramStartOriginalRestoredComposedInferExecution(
        occurrence, graph, prefix, provider, snapshot.binding, snapshot.descriptorWire,
        snapshot.rows, custodyAvailable, savedScope, value, token(definition), consumer,
        readRetainedBytes, readExecutionBytes, modelRetainedBytes, modelExecutionBytes,
        referenceIssuer, inputBodyRead));
    },
    openCheckedClientInstalledRestoredModelEffectHost(compiled, definition,
      managedRun, bound, sources, heldOutput, graph) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      return checked(moon.clientProgramInstalledEffectManagedRestoredModelHostOpen(
        managedRun, bound, sources, heldOutput, value, token(definition), graph));
    },
    openCheckedClientInstalledRestoredModelsEffectHost(compiled, definition,
      managedRun, bound, sources, heldOutputs, graphs) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      return checked(moon.clientProgramInstalledEffectManagedRestoredModelsHostOpen(
        managedRun, bound, sources, heldOutputs, value, token(definition), graphs));
    },
    restoredInferSourceOriginals(compiled, definition, scope, occurrence, graph) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      return Object.freeze(checked(moon.clientProgramRestoredInferSourceOriginals(
        scope, value, token(definition), occurrence, graph)).map(original =>
        Object.freeze({source: inspectEvidence(runtimeField(original, 0)),
          logicalRelationCid: moon.strategyRunEvidenceIdentity(runtimeField(original, 1))})));
    },
    // Reuse the original compiled/definition token domains. A public wrapper
    // object cannot be passed as a nominal MoonBit compiled Run or contract.
    claimCheckedClientInferNodePreparationLayout(compiled, definition, graph, read,
      {layout, installation, runtimeArtifactCid, layoutArtifactCid, probability}) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      return checked(moon.clientProgramClaimInferNodePreparationLayout(read,
        value, token(definition), graph, layout, installation,
        runtimeArtifactCid, layoutArtifactCid, probability));
    },
    startCheckedClientInferOriginalPreparation(compiled, definition, prepared,
      step, graph, registry, values, provider, consumer, readRetainedBytes,
      readExecutionBytes, modelRetainedBytes, modelExecutionBytes, fragment, ordered) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      return checked(moon.clientProgramStartOriginalInferExecution(prepared,
        step, graph, registry, values, provider, value, token(definition), consumer,
        readRetainedBytes, readExecutionBytes, modelRetainedBytes,
        modelExecutionBytes, fragment, ordered));
    },
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
    checkClientRunDefinitionBinding(checkedProgram, admission, definition) {
      if (typeof moon.clientProgramCheckRunBinding !== 'function' ||
          !moon.clientProgramCheckRunBinding(checkedProgram,
            admissionToken(admission), token(definition))) {
        throw new TypeError('Run Definition differs from checked Program');
      }
    },
    admitCheckedClientEffectRunPublication(
      checkedEffect, template, prepared, authorization, compiledPlan,
    ) {
      if (typeof moon.clientProgramAdmitEffectPublication !== 'function') {
        throw new TypeError('Client Effect admission is unavailable');
      }
      const admission = moon.clientProgramAdmitEffectPublication(
        checkedEffect,
        evidenceToken(template),
        evidenceToken(prepared),
        evidenceToken(authorization),
        token(compiledPlan),
      );
      if (admission === undefined) {
        throw new TypeError('Publication evidence differs from checked Effect');
      }
      return inspectAdmission(admission);
    },
    // Inspect originals already admitted by this exact Allow/Definition owner.
    // No second evidence admission or byte/CID replacement supplies custody.
    originalCheckedClientEffectPublication(allowed, definition, limits) {
      issuanceLimits(limits, 'Original Effect publication');
      return Object.freeze({
        admission: inspectAdmission(moon.clientProgramAllowedEffectRunAdmission(allowed)),
        runDefinition: inspect(definition, limits),
      });
    },
    issueCheckedClientEffectSourceFreeInvocationOriginal(compilation, policy, limits) {
      issuanceLimits(limits, 'Original source-free Effect Invocation');
      const original = checked(moon.clientProgramIssueEffectSourceFreeInvocationOriginal(
        compilation, policy, limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      const owner = moon.clientProgramEffectSourceFreeInvocationOriginalInvocation(original);
      return Object.freeze({original, owner,
        observation: inspectEvidence(moon.clientProgramEffectSourceFreeInvocationOriginalObservation(original)),
        invocation: inspect(owner, limits)});
    },
    bindCheckedInstalledEffectSourceFreeInvocation(parent, prepared, request, plan, host,
      admission, definition, original) {
      checked(moon.clientProgramBindInstalledEffectSourceFreeInvocation(
        parent, prepared, request, plan, host, admissionToken(admission), token(definition), original));
    },
    issueCheckedInstalledEffectKeyedInvocation(parent, prepared, request, plan, host,
      compilation, admission, definition, lookup, started, completed, limits) {
      issuanceLimits(limits, 'Original installed keyed Source Invocation');
      const issued = checked(moon.clientProgramIssueInstalledEffectKeyedInvocation(
        parent, prepared, request, plan, host, compilation, admissionToken(admission), token(definition),
        lookup, started, completed, limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      return Object.freeze({observation: inspectEvidence(runtimeField(issued, 0)),
        invocation: inspect(runtimeField(issued, 1), limits), owner: runtimeField(issued, 1)});
    },
    prepareInstalledEffectKeyedSourceUnit(parent, prepared, request, plan, host,
      original, lookup, retention, limits, deferCatalogs = false) {
      issuanceLimits(limits, 'Original installed keyed Source Unit');
      const issued = checked(moon.clientProgramPrepareInstalledEffectKeyedSourceUnit(
        parent, prepared, request, plan, host, lookup, token(retention),
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      // Borrow exactly the completed inventory. Core performs current and
      // retention-bound checks; this never exports or admits lookup DATA again.
      let cached = moon.clientProgramEffectKeyedCachedDependencyBodies(original, lookup, token(retention));
      // This actual compiled export returns boxed Option<Array<Body>>. Borrow
      // its SAME payload through the pinned binding; None never means empty.
      cached = runtimeIsBoxedSome(cached) ? runtimeField(cached, 0) : undefined;
      if (!Array.isArray(cached)) throw new TypeError('OriginalEffectKeyedInventoryUnavailable');
      const bodies = cached.map(body => Object.freeze({
        kind: moon.clientProgramEffectDependencyBodyKind(body),
        cid: moon.clientProgramEffectDependencyBodyCid(body),
        wire: moon.clientProgramEffectDependencyBodyJson(body)}));
      for (const body of moon.clientProgramEffectKeyedSourceUnitMetadataBodies(issued)) {
        bodies.push(Object.freeze({kind: runtimeField(body, 0),
          cid: runtimeField(body, 1), wire: runtimeField(body, 2)}));
      }
      const value = Object.freeze({invocation: moon.clientProgramEffectKeyedSourceUnitInvocation(issued),
        ...(deferCatalogs ? {catalogDeferred: true} : {}), bodies: Object.freeze(bodies),
        catalogBodies: Object.freeze(bodies.filter(body => {
          switch (body.kind) {
            case 'source_contract': case 'source_view_contract': case 'data_policy':
            case 'request_schema': case 'carrier_schema': case 'schema_evidence':
            case 'capability_evidence': return true;
            default: return false;
          }
        }))});
      localEffectDependencyTokens.set(value, {kind: 'keyed_source', issued, parent, plan, request});
      return value;
    },
    issueCheckedInstalledEffectCapturedInvocation(parent, prepared, request, plan, host,
      compilation, admission, definition, capturedSource, source, limits) {
      issuanceLimits(limits, 'Original installed Effect Invocation');
      const issued = checked(moon.clientProgramIssueInstalledEffectCapturedInvocation(
        parent, prepared, request, plan, host, compilation, admissionToken(admission), definition,
        capturedSource, source.sourceEvidenceWire, source.inputLogicalWire,
        source.sourceRef, source.sourceContractCid, source.authorityScopeCid, source.dataPolicyCid,
        source.captureStartedAt, source.captureCompletedAt,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      return Object.freeze({observation: inspectEvidence(runtimeField(issued, 0)),
        invocation: inspect(runtimeField(issued, 1), limits), owner: runtimeField(issued, 1)});
    },
    issueCheckedInstalledEffectMultiCapturedInvocation(parent, prepared, request, plan, host,
      compilation, admission, definition, sources, context, limits) {
      issuanceLimits(limits, 'Original installed plural Effect Invocation');
      const issued = checked(moon.clientProgramIssueInstalledEffectMultiCapturedInvocation(
        parent, prepared, request, plan, host, compilation, admissionToken(admission), definition,
        sources.map(value => value.captured.capture.source()),
        sources.map(value => value.captured.identity), sources.map(value => value.captured.requirement),
        sources.map(value => value.sourceEvidenceWire),
        sources.map(value => moon.strategyRunEvidenceJson(value.captured.logicalInput)),
        context.authorityScopeCid, context.dataPolicyCid, context.captureStartedAt, context.captureCompletedAt,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      return Object.freeze({observation: inspectEvidence(runtimeField(issued, 0)),
        invocation: inspect(runtimeField(issued, 1), limits), owner: runtimeField(issued, 1)});
    },
    issueCheckedOriginalEffectDirectSourcesInvocation(parent, prepared, request, plan, host,
      compilation, admission, definition, sources, sourceEvidence, context, limits) {
      issuanceLimits(limits, 'Original installed Direct Effect Invocation');
      const issued = checked(moon.clientProgramIssueOriginalEffectDirectSourcesInvocation(
        parent, prepared, request, plan, host, compilation, admissionToken(admission), definition,
        sources.map(({captured}) => captured.capture.source()), sources.map(({captured}) => captured.identity),
        sourceEvidence.map(evidenceToken), sources.map(({captured}) => captured.logicalInput),
        context.authorityScopeCid, context.dataPolicyCid, context.captureStartedAt, context.captureCompletedAt,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      const invocation = moon.clientProgramEffectDirectSourcesPublicationInvocation(issued);
      return Object.freeze({observation: inspectEvidence(moon.clientProgramEffectDirectSourcesPublicationObservation(issued)),
        invocation: inspect(invocation, limits), owner: invocation, sourcePublication: issued});
    },
    bindCheckedInstalledEffectModelInvocation(parent, prepared, request, plan, host,
      compilation, admission, definition, issued) {
      const retained = inferInvocationTokens.get(issued);
      if (retained === undefined) throw new TypeError('Foreign Effect Infer Invocation');
      const value = checked(moon.clientProgramBindInstalledEffectModelInvocation(
        parent, prepared, request, plan, host, compilation, admissionToken(admission), definition,
        retained.compiled, issued.binding));
      return Object.freeze({observation: inspectEvidence(runtimeField(value, 0)),
        invocation: inspect(runtimeField(value, 1)), owner: runtimeField(value, 1)});
    },
    issueCheckedInstalledEffectContentInvocation(parent, prepared, request, plan, host,
      compilation, admission, definition, compiled, generation, limits) {
      const value = compiledRunTokens.get(compiled), completion = serializationGenerationTokens.get(generation);
      if (value === undefined || completion === undefined) throw new TypeError('Foreign Client Content generation');
      limits = captureContractLimits(limits, 'Original installed Content Invocation');
      const issued = checked(moon.clientProgramIssueInstalledEffectContentInvocation(
        parent, prepared, request, plan, host, compilation, admissionToken(admission), definition,
        value, completion, limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      return Object.freeze({observation: inspectEvidence(runtimeField(issued, 0)),
        invocation: inspect(runtimeField(issued, 1), limits), owner: runtimeField(issued, 1)});
    },
    issueCheckedClientEffectCapturedInvocation(checkedEffect, compilation,
      admission, definition, capturedSource, source, limits) {
      issuanceLimits(limits, 'Client Effect Invocation');
      const issued = checked(moon.clientProgramIssueEffectCapturedInvocation(
        checkedEffect, compilation, admissionToken(admission), definition,
        capturedSource, source.sourceEvidenceWire, source.inputLogicalWire,
        source.sourceRef, source.sourceContractCid,
        source.authorityScopeCid, source.dataPolicyCid,
        source.captureStartedAt, source.captureCompletedAt,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      return Object.freeze({observation: inspectEvidence(runtimeField(issued, 0)),
        invocation: inspect(runtimeField(issued, 1)), owner: runtimeField(issued, 1)});
    },
    issueCheckedInstalledEffectDirectSourcesInvocation(plan, checkedEffect, request,
      compilation, admission, definition, sources, sourceEvidence, context, limits) {
      issuanceLimits(limits, 'Client original Effect Sources Invocation');
      if (!Array.isArray(sources) || sources.length < 1 ||
          !Array.isArray(sourceEvidence) || sourceEvidence.length !== sources.length) {
        throw new TypeError('Incomplete Effect Source coverage');
      }
      const issued = checked(moon.clientProgramPrepareInstalledEffectDirectSourcesPublication(
        plan, checkedEffect, request, compilation, admissionToken(admission), definition,
        sources.map(({captured}) => captured.capture.source()),
        sources.map(({captured}) => captured.identity),
        sourceEvidence.map(evidenceToken),
        sources.map(({captured}) => captured.logicalInput),
        context.authorityScopeCid, context.dataPolicyCid,
        context.captureStartedAt, context.captureCompletedAt,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      const invocation = moon.clientProgramEffectDirectSourcesPublicationInvocation(issued);
      const observation = moon.clientProgramEffectDirectSourcesPublicationObservation(issued);
      return Object.freeze({observation: inspectEvidence(observation),
        invocation: inspect(invocation), owner: invocation, sourcePublication: issued});
    },
    prepareCheckedInstalledEffectSourceUnits(plan, checkedEffect, request,
      compilation, admission, definition, sources, sourceEvidence, context, limits) {
      issuanceLimits(limits, 'Client original Effect Source Units');
      if (!Array.isArray(sources) || sources.length < 1 ||
          !Array.isArray(sourceEvidence) || sourceEvidence.length !== sources.length) {
        throw new TypeError('Incomplete Effect Source coverage');
      }
      return checked(moon.clientProgramPrepareInstalledEffectSourceUnitInputs(
        plan, checkedEffect, request, compilation, admissionToken(admission), definition,
        sources.map(({captured}) => captured.capture.source()),
        sources.map(({captured}) => captured.identity), sourceEvidence.map(evidenceToken),
        sources.map(({captured}) => captured.logicalInput),
        context.authorityScopeCid, context.dataPolicyCid,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
    },
    issueCheckedClientEffectMultiCapturedInvocation(checkedEffect, compilation,
      admission, definition, sources, context, limits) {
      issuanceLimits(limits, 'Client plural Effect Invocation');
      if (!Array.isArray(sources) || sources.length < 1) {
        throw new TypeError('Incomplete Effect Source coverage');
      }
      const issued = checked(moon.clientProgramIssueEffectMultiCapturedInvocation(
        checkedEffect, compilation, admissionToken(admission), definition,
        sources.map(value => value.captured.capture.source()),
        sources.map(value => value.captured.identity),
        sources.map(value => value.captured.requirement),
        sources.map(value => value.sourceEvidenceWire),
        sources.map(value => moon.strategyRunEvidenceJson(value.captured.logicalInput)),
        context.authorityScopeCid, context.dataPolicyCid,
        context.captureStartedAt, context.captureCompletedAt,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      return Object.freeze({observation: inspectEvidence(runtimeField(issued, 0)),
        invocation: inspect(runtimeField(issued, 1)), owner: runtimeField(issued, 1)});
    },
    issueCheckedAcquiredLocalEffectInvocation(checkedEffect, capturedSource,
      identity, requirement, input, observation, authorityScopeCid,
      dataPolicyCid, limits) {
      issuanceLimits(limits, 'Acquired local Effect Invocation');
      return checked(moon.clientProgramIssueAcquiredLocalEffectInvocation(
        checkedEffect, capturedSource, identity, requirement, input,
        evidenceToken(observation), authorityScopeCid, dataPolicyCid,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
    },
    issueProgramInitialRetention(owner, prepared, request, policy, selection, contracts, limits) {
      if (owner === undefined || prepared === undefined || request === undefined) {
        throw new TypeError('OriginalProgramRetentionOwnerRequired');
      }
      limits = captureContractLimits(limits, 'Initial Program retention');
      return inspect(checked(moon.clientProgramIssueProgramInitialRetention(owner, prepared, request,
        contracts[0].cid, policy, selection.availableUntil, selection.deleteBy, selection.metadataDeleteBy,
        contracts[1].cid, selection.metadataDeleteBy, contracts[2].cid,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth)), limits);
    },
    issueInstalledEffectInitialRetention(owner, prepared, request, plan, policy, selection, limits) {
      if (owner === undefined || prepared === undefined || request === undefined || plan === undefined) {
        throw new TypeError('OriginalEffectRetentionOwnerRequired');
      }
      limits = captureContractLimits(limits, 'Initial Effect retention');
      return inspect(checked(moon.clientProgramIssueInstalledEffectInitialRetention(owner, prepared, request, plan,
        selection.retentionContractCid, policy, selection.availableUntil, selection.deleteBy, selection.metadataDeleteBy,
        selection.metadataRetentionPolicyCid, selection.metadataDeleteBy, selection.clockContractCid,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth)), limits);
    },
    rebindInstalledEffectResultRetention(managedRun, prepared, request, plan, retention, policy, limits) {
      if (managedRun == null || prepared == null || request == null || plan == null) {
        throw new TypeError('OriginalEffectRetentionPreparationRequired');
      }
      limits = captureContractLimits(limits, 'Original Effect retention policy');
      const original = token(retention);
      const value = checked(moon.clientProgramRebindInstalledEffectResultRetention(
        managedRun, prepared, request, plan, original, policy,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      return value === original ? retention : inspect(value, limits);
    },
    issueCheckedAcquiredEffectEvidence(checkedEffect, capturedSource,
      identity, requirement, input, observation, authorityScopeCid,
      dataPolicyCid, retention, limits, unit = 0, publicationRetention = retention, deferCatalogs = false) {
      issuanceLimits(limits, 'Acquired Effect evidence');
      if (!Number.isSafeInteger(unit) || unit < 0) {
        throw new TypeError('Invalid acquired Effect Unit');
      }
      const issued = checked(unit === 0 && publicationRetention === retention
        ? moon.clientProgramIssueAcquiredEffectEvidence(
          checkedEffect, capturedSource, identity, requirement, input,
          evidenceToken(observation), authorityScopeCid, dataPolicyCid,
          token(retention), limits.maxWireBytes, limits.maxNodes, limits.maxDepth)
        : moon.clientProgramIssueAcquiredEffectEvidenceAt(
          checkedEffect, unit, capturedSource, identity, requirement, input,
          evidenceToken(observation), authorityScopeCid, dataPolicyCid,
          token(retention), token(publicationRetention),
          limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      const value = inspectAcquiredEffectEvidence(issued, publicationRetention, limits, deferCatalogs);
      localEffectDependencyTokens.set(value, {kind: 'acquired', issued});
      return value;
    },
    issueCheckedWholeEffectSourceUnit(plan, prepared, request, slot, captured,
      identity, capacity, input, observation, authorityScopeCid, retention, limits, deferCatalogs = false) {
      issuanceLimits(limits, 'Whole Effect Source Unit');
      if (!Number.isSafeInteger(slot) || slot < 0) {
        throw new TypeError('Invalid acquired Effect Source slot');
      }
      const issued = checked(moon.clientProgramIssueInstalledWholeEffectSourceUnit(
        plan, prepared, request, slot, captured, identity, capacity, input,
        evidenceToken(observation), authorityScopeCid, token(retention),
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      const value = inspectAcquiredEffectEvidence(issued, retention, limits, deferCatalogs);
      localEffectDependencyTokens.set(value, {kind: 'acquired', issued});
      return value;
    },
    prepareCombinedEffectSourceUnit(publication, unit, retention, limits, deferCatalogs = false) {
      issuanceLimits(limits, 'Combined Effect Source Unit');
      if (!Number.isSafeInteger(unit) || unit < 0) {
        throw new TypeError('Invalid acquired Effect Unit');
      }
      const prepared = checked(moon.clientProgramPrepareCombinedEffectSourceUnit(
        publication, unit, token(retention), limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      const value = Object.freeze({
        invocation: moon.clientProgramCombinedEffectSourceUnitInvocation(prepared),
        bodies: Object.freeze(moon.clientProgramCombinedEffectSourceUnitDependencyBodies(prepared)
          .map(body => Object.freeze({kind: runtimeField(body, 0), cid: runtimeField(body, 1), wire: runtimeField(body, 2)}))),
        ...(deferCatalogs ? {catalogDeferred: true, catalogBodies: Object.freeze([])} : {catalogBodies: Object.freeze(checked(moon.clientProgramCombinedEffectSourceUnitCatalogBodies(
          prepared, limits.maxWireBytes, limits.maxNodes, limits.maxDepth))
          .map(body => Object.freeze({kind: runtimeField(body, 0), cid: runtimeField(body, 1), wire: runtimeField(body, 2)})))}),
      });
      // This is semantic preparation, not a completed producer. Only the
      // actual Result export/receipt issuer below can mint its Artifact.
      localEffectDependencyTokens.set(value, {kind: 'combined_source', issued: prepared, unit});
      return value;
    },
    prepareInstalledEffectModelSourceUnit(managedRun, plan, request, inputs, unit, retention, limits, deferCatalogs = false) {
      issuanceLimits(limits, 'Installed preconsumer Effect Source Unit');
      if (!Number.isSafeInteger(unit) || unit < 0) {
        throw new TypeError('Invalid acquired Effect Unit');
      }
      const prepared = checked(moon.clientProgramPrepareInstalledEffectModelSourceUnit(
        managedRun, plan, request, inputs, unit, token(retention),
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      const value = Object.freeze({
        invocation: moon.clientProgramCombinedEffectSourceUnitInvocation(prepared),
        bodies: Object.freeze(moon.clientProgramCombinedEffectSourceUnitDependencyBodies(prepared)
          .map(body => Object.freeze({kind: runtimeField(body, 0), cid: runtimeField(body, 1), wire: runtimeField(body, 2)}))),
        ...(deferCatalogs ? {catalogDeferred: true, catalogBodies: Object.freeze([])} : {catalogBodies: Object.freeze(checked(moon.clientProgramPrepareInstalledEffectModelSourceUnitCatalog(
          managedRun, plan, request, inputs, prepared,
          limits.maxWireBytes, limits.maxNodes, limits.maxDepth))
          .map(body => Object.freeze({kind: runtimeField(body, 0), cid: runtimeField(body, 1), wire: runtimeField(body, 2)})))}),
      });
      localEffectDependencyTokens.set(value, {kind: 'combined_source', issued: prepared, unit});
      return value;
    },
    prepareOriginalEffectModelUnitEvidence(managedRun, plan, request, held, compiled, definition,
      graph, unit, retention, catalogBodies, operation, limits, retained, current, retainedBase, executionBase, deferCatalogs = false) {
      issuanceLimits(limits, 'Original completed Model Unit');
      const originalCompiled = compiledRunTokens.get(compiled);
      if (originalCompiled === undefined || compiled.kind !== 'infer' || retained.modelScan !== undefined ||
          typeof current !== 'function' || typeof operation?.growOriginalPublicationCapacity !== 'function' ||
          !Number.isSafeInteger(unit) || unit < 0 || !Array.isArray(catalogBodies)) {
        throw new TypeError('ForeignPreconsumerModelOriginal');
      }
      const extent = quote => {
        const r = runtimeOptionalField(quote, 0), e = runtimeOptionalField(quote, 1);
        if (typeof r !== 'bigint' || typeof e !== 'bigint' || r < 0n || e < 0n) {
          throw new TypeError('PreconsumerModelConstructionCapacityUnavailable');
        }
        return [r, e];
      };
      const rawDefinition = token(definition);
      let [r, e] = extent(moon.clientProgramPreconsumerModelUnitIdentityStartCapacity(
        held, originalCompiled, rawDefinition, graph));
      operation.growOriginalPublicationCapacity(retainedBase + r, executionBase + e);
      current();
      retained.modelScan = checked(moon.clientProgramPreconsumerModelUnitIdentityStart(
        held, originalCompiled, rawDefinition, graph));
      current();
      for (;;) {
        const [nextR, nextE] = extent(moon.clientProgramInferModelIdentityNextCapacity(retained.modelScan));
        r = nextR > r ? nextR : r; e = nextE > e ? nextE : e;
        operation.growOriginalPublicationCapacity(retainedBase + r, executionBase + e);
        current();
        const progress = checked(moon.clientProgramInferModelIdentityAdvance(retained.modelScan, 256, nextR, nextE));
        current();
        if (runtimeField(progress, 0)) break;
      }
      retained.modelReceipt = checked(moon.clientProgramInferModelIdentityFinish(retained.modelScan));
      current();
      const [writerR, writerE] = extent(moon.clientProgramPreconsumerModelUnitObservationCapacity(
        held, originalCompiled, rawDefinition, graph, retained.modelReceipt, limits.maxWireBytes));
      retained.identityRetainedBytes = r + writerR;
      retained.identityExecutionBytes = e + writerE;
      operation.growOriginalPublicationCapacity(retainedBase + retained.identityRetainedBytes,
        executionBase + retained.identityExecutionBytes);
      current();
      retained.modelOriginal = checked(moon.clientProgramPrepareInstalledEffectModelUnitEvidence(
        managedRun, plan, request, held, originalCompiled, rawDefinition, graph, retained.modelReceipt,
        token(retention), limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      current();
      const acquired = checked(moon.clientProgramPreconsumerModelUnitAcquiredEvidence(retained.modelOriginal));
      const originals = checked(moon.clientProgramPreconsumerModelUnitDependencyBodies(retained.modelOriginal))
        .map(body => Object.freeze({kind: runtimeField(body, 0), cid: runtimeField(body, 1), wire: runtimeField(body, 2)}));
      const direct = moon.clientProgramOriginalModelAcquiredEffectSources(acquired);
      const lookupBodies = checked(moon.clientProgramOriginalModelAcquiredLookupDependencyBodies(acquired))
        .map(body => Object.freeze({kind: runtimeField(body, 0), cid: runtimeField(body, 1), wire: runtimeField(body, 2)}));
      const bodies = [
        ...originals,
        ...direct.flatMap(source => moon.clientProgramAcquiredEffectDependencyBodies(source)
          .map(pair => Object.freeze({kind: runtimeField(pair, 0), wire: runtimeField(pair, 1),
            ...(runtimeField(pair, 0) === 'request_values' ? {cid: moon.clientProgramAcquiredEffectRequestCid(source)} : {})}))),
        ...lookupBodies,
        ...moon.clientProgramOriginalModelAcquiredScopeImportBodies(acquired)
          .map(body => Object.freeze({kind: runtimeField(body, 0), cid: runtimeField(body, 1), wire: runtimeField(body, 2)})),
        Object.freeze({kind: 'acquisition_scope', wire: moon.clientProgramOriginalModelAcquiredEffectScope(acquired)}),
        Object.freeze({kind: 'relation_value', cid: moon.clientProgramEffectInputExportLogicalCid(retained.modelReceipt),
          wire: moon.clientProgramInferModelIdentityBody(retained.modelScan, retained.modelReceipt)}),
        Object.freeze({kind: 'relation_schema', cid: moon.clientProgramEffectInputExportSchemaCid(retained.modelReceipt),
          wire: moon.clientProgramEffectInputExportSchemaWire(retained.modelReceipt)}),
      ];
      const value = Object.freeze({invocation: moon.clientProgramOriginalModelAcquiredEffectInvocation(acquired),
        ...(deferCatalogs ? {catalogDeferred: true} : {}),
        bodies: Object.freeze(bodies), catalogBodies: Object.freeze([...catalogBodies,
          ...lookupBodies.filter(body => ['source_contract', 'source_view_contract', 'data_policy',
            'request_schema', 'carrier_schema', 'schema_evidence', 'capability_evidence'].includes(body.kind))])});
      localEffectDependencyTokens.set(value, {kind: 'preconsumer_model', issued: acquired,
        original: retained.modelOriginal, unit});
      current();
      return value;
    },
    async prepareOriginalEffectSourceUnitResults(managedRun, plan, request, captured, dependency,
      admission, definition, limits, retained, current, prepared, consumerOccurrence, physicalSource, signal, retainedCurrent) {
      issuanceLimits(limits, 'Original preconsumer Effect Unit Results');
      const owned = localEffectDependencyTokens.get(dependency);
      if (!['combined_source', 'preconsumer_model'].includes(owned?.kind) || retained === null || typeof retained !== 'object' ||
          retained.pins !== undefined || !Array.isArray(retained.exports) || retained.exports.length !== 0 ||
          !Array.isArray(retained.receipts) || retained.receipts.length !== 0 ||
          !Array.isArray(retained.artifacts) || retained.artifacts.length !== 0 || typeof current !== 'function') {
        throw new TypeError('ForeignEffectSourceUnitOriginal');
      }
      current();
      retained.pins = checked(moon.clientProgramPinInstalledEffectModelUnitResults(
        managedRun, plan, request, captured,
        owned.unit));
      current();
      const count = moon.clientProgramEffectModelUnitResultCount(retained.pins);
      for (let index = 0; index < count; index++) {
        let result;
        if (moon.clientProgramEffectModelUnitResultRequiresManagedExport(retained.pins, index)) {
          const task = moon.clientProgramEffectModelUnitResultTask(retained.pins, index);
          const physical = physicalSource?.(task);
          if (physical === undefined) throw new Error('OriginalEffectUnitPhysicalSourceUnavailable');
          const importing = checked(moon.clientProgramBeginInstalledEffectModelUnitManagedExport(
            managedRun, plan, request, captured, retained.pins, index, physical.completed, physical.material));
          // Retain the SAME bridge before current/withRows can reenter or await.
          (retained.imports ??= []).push(importing); current();
          if (typeof retainedCurrent !== 'function') throw new TypeError('OriginalEffectUnitRetainedFenceUnavailable');
          await physical.withRows(row => {
            // The physical reader owns its same-material use and signal. A
            // row checks only local retention; full Journal/selection current
            // stays at the existing read/finish and Model dispatch boundaries.
            retainedCurrent();
            checked(moon.clientProgramEffectManagedInputAppend(importing, row));
            retainedCurrent();
          }, signal, () => {
            current();
            const preparation = checked(moon.clientProgramEffectManagedInputFinish(importing));
            current();
            return preparation;
          });
          current();
          result = moon.clientProgramEffectModelUnitManagedExportOwner(retained.pins, index, importing);
        } else result = moon.clientProgramPrepareInstalledEffectModelUnitResultExport(
          managedRun, plan, request, captured, retained.pins, index);
        let exported;
        try { exported = checked(result); }
        catch (cause) {
          try {
            const kind = moon.clientProgramEffectModelUnitResultExportIssueKind?.(result);
            const coordinates = consumerOccurrence === undefined ? undefined
              : moon.clientProgramInferOccurrenceCoordinates(consumerOccurrence);
            const task = runtimeField(coordinates, 0), unit = runtimeField(coordinates, 1),
              step = runtimeField(coordinates, 2);
            if (typeof kind === 'string' && [task, unit, step].every(value =>
                Number.isSafeInteger(value) && value >= 0 && value <= 2147483647)) {
              Object.defineProperty(cause, 'primaryDiagnostic', {
                value: Object.freeze({code: 'MoonBitHostFailure',
                  phase: 'original_effect_source_unit_result_export', kind, task, unit, step}),
              });
            }
          } catch { /* Optional DATA cannot replace the original export failure. */ }
          throw cause;
        }
        retained.exports.push(exported); current();
        const receipt = checked(moon.clientProgramEffectModelUnitExportReceipt(exported));
        retained.receipts.push(receipt); current();
        // The Plan retained this original public holder/token. A separate
        // Journal wire admission has the same CID but is not that original.
        const artifactResult = owned.kind === 'combined_source'
          ? moon.clientProgramPrepareInstalledEffectModelSourceUnitArtifact(
            managedRun, plan, request, retained.pins, exported, owned.issued, receipt,
            admissionToken(admission), token(definition), limits.maxWireBytes, limits.maxNodes, limits.maxDepth)
          : moon.clientProgramPrepareInstalledEffectModelUnitArtifact(
            managedRun, plan, request, prepared,
            owned.original, retained.pins, exported, receipt, admissionToken(admission),
            limits.maxWireBytes, limits.maxNodes, limits.maxDepth);
        let issued;
        try {issued = checked(artifactResult);}
        catch (cause) {
          try {
            const kind = moon.clientProgramEffectModelUnitResultArtifactIssueKind?.(artifactResult);
            const coordinates = consumerOccurrence === undefined ? undefined
              : moon.clientProgramInferOccurrenceCoordinates(consumerOccurrence);
            const task = runtimeField(coordinates, 0), unit = runtimeField(coordinates, 1),
              step = runtimeField(coordinates, 2);
            if (typeof kind === 'string' && [task, unit, step].every(value =>
                Number.isSafeInteger(value) && value >= 0 && value <= 2147483647)) {
              Object.defineProperty(cause, 'primaryDiagnostic', {
                value: Object.freeze({code: 'MoonBitHostFailure',
                  phase: 'original_effect_source_unit_artifact', kind, task, unit, step}),
              });
            }
          } catch { /* Optional DATA cannot replace the original artifact failure. */ }
          throw cause;
        }
        const artifact = inspectLocalEffectArtifact(issued);
        const name = moon.clientProgramEffectModelUnitResultName(retained.pins, index);
        if (typeof name !== 'string') throw new TypeError('OriginalEffectUnitResultUnavailable');
        retained.artifacts.push(Object.freeze({name, artifact})); current();
      }
      const issued = checked(moon.clientProgramPrepareInstalledEffectModelUnitManifest(
        managedRun, plan, request, dependency.invocation,
        retained.artifacts.map(value => localEffectArtifactTokens.get(value.artifact)),
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      const manifest = Object.freeze({identity: moon.clientProgramLocalEffectResultManifestCid(issued),
        wire: moon.clientProgramLocalEffectResultManifestJson(issued)});
      localEffectManifestTokens.set(manifest, issued);
      retained.manifest = manifest; current();
      return retained;
    },
    bindOriginalEffectUnitArtifact(owner, inputs, artifact, context) {
      const original = localEffectArtifactTokens.get(artifact);
      if (original === undefined) throw new TypeError('ForeignOriginalEffectUnitArtifact');
      checked(moon.clientProgramBindOriginalEffectUnitArtifactRunContext(
        owner, inputs, original, ...localEffectContext(context)));
    },
    originalEffectUnitArtifactDefinition(artifact) {
      const original = localEffectArtifactTokens.get(artifact);
      if (original === undefined) throw new TypeError('ForeignOriginalEffectUnitArtifact');
      return checked(moon.clientProgramOriginalEffectUnitArtifactDefinition(original));
    },
    reuseOriginalEffectUnitArtifact(owner, inputs, artifact, exported, receipt) {
      const original = localEffectArtifactTokens.get(artifact);
      if (original === undefined) throw new TypeError('ForeignOriginalEffectUnitArtifact');
      checked(moon.clientProgramCheckOriginalEffectUnitArtifactExport(owner, inputs, original, exported, receipt));
      return artifact;
    },
    reuseOriginalEffectUnitManifest(owner, invocation, artifacts, manifest) {
      const original = localEffectManifestTokens.get(manifest);
      const retained = artifacts.map(artifact => {
        const value = localEffectArtifactTokens.get(artifact);
        if (value === undefined) throw new TypeError('ForeignOriginalEffectUnitArtifact');
        return value;
      });
      if (original === undefined || !moon.clientProgramOriginalEffectUnitManifestMatches(
          original, owner, invocation, retained)) throw new TypeError('ForeignOriginalEffectUnitManifest');
      return manifest;
    },
    bindInferOriginalResultArtifact(active, index, artifact, manifest) {
      const result = localEffectArtifactTokens.get(artifact), complete = localEffectManifestTokens.get(manifest);
      if (result === undefined || complete === undefined) throw new TypeError('ForeignInferResultArtifact');
      checked(moon.clientProgramBindInferResultArtifactInput(active, index, result, complete));
    },
    retireOriginalEffectUnitResults(retained) {
      // The enclosing original Host/consumer must be stopped first. These
      // calls sever only original export/receipt aliases and Unit pins; no
      // physical stop/Store ACK or consumed-work refund is inferred here.
      for (const exported of retained.exports) moon.clientProgramEffectInputExportCancelPreparation(
        moon.clientProgramEffectLocalResultExportPreparation(exported));
      for (const importing of retained.imports ?? []) moon.clientProgramEffectManagedInputCancel(importing);
      if (retained.imports !== undefined) retained.imports.length = 0;
      for (const receipt of retained.receipts) moon.clientProgramEffectInputExportReleaseReceipt(receipt);
      if (retained.modelReceipt !== undefined) moon.clientProgramInferModelIdentityReceiptCancel(retained.modelReceipt);
      if (retained.modelScan !== undefined) moon.clientProgramInferModelIdentityCancel(retained.modelScan);
      if (retained.pins !== undefined) {
        if (moon.clientProgramReleaseEffectModelUnitResults(retained.pins) !== true) return false;
        retained.pins = undefined;
      }
      retained.exports.length = 0; retained.receipts.length = 0;
      retained.artifacts.length = 0; retained.manifest = undefined;
      retained.modelScan = retained.modelReceipt = retained.modelOriginal = undefined;
      return true;
    },
    issueSourceFreeEffectEvidence(owner, unit, limits) {
      issuanceLimits(limits, 'Source-free Effect dependency');
      const invocation = checked(moon.clientProgramIssueSourceFreeLocalEffectInvocation(
        owner, unit, limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      const scope = control.seal('acquisition_scope',
        '{"sources":[],"version":"actql-acquisition-scope/0.1"}', limits);
      const value = Object.freeze({invocation, bodies: Object.freeze([
        Object.freeze({kind: 'acquisition_scope', wire: scope.wire}),
      ])});
      localEffectDependencyTokens.set(value, {kind: 'source_free', issued: invocation});
      return value;
    },
    issueEffectResultImportObservation(owner, inputs, captured, manifest,
      artifact, limits) {
      issuanceLimits(limits, 'Effect Result import observation');
      const ownedManifest = localEffectManifestTokens.get(manifest);
      const ownedArtifact = localEffectArtifactTokens.get(artifact);
      if (ownedManifest === undefined || ownedArtifact === undefined) {
        throw new TypeError('Foreign Effect Result import evidence');
      }
      const issued = checked(moon.clientProgramIssueEffectResultImportObservation(
        owner, inputs, captured, ownedManifest, ownedArtifact,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      const value = Object.freeze({
        wire: moon.clientProgramEffectResultImportObservationJson(issued),
      });
      localEffectImportTokens.set(value, issued);
      const source = localEffectArtifactSources.get(artifact);
      if (source !== undefined) localEffectImportSources.set(value, source);
      return value;
    },
    issueImportedEffectEvidence(owner, inputs, unit, observations, limits) {
      issuanceLimits(limits, 'Imported Effect evidence');
      if (!Array.isArray(observations)) {
        throw new TypeError('Invalid Effect Result import observations');
      }
      const owned = observations.map(value => {
        const issued = localEffectImportTokens.get(value);
        if (issued === undefined) {
          throw new TypeError('Foreign Effect Result import observation');
        }
        return issued;
      });
      const issued = checked(moon.clientProgramIssueImportedEffectEvidence(
        owner, inputs, unit, owned, limits.maxWireBytes, limits.maxNodes,
        limits.maxDepth));
      const value = Object.freeze({
        invocation: moon.clientProgramImportedEffectInvocation(issued),
        bodies: Object.freeze([
          Object.freeze({kind: 'acquisition_scope',
            wire: moon.clientProgramImportedEffectScopeJson(issued)}),
          ...observations.map(value => Object.freeze({
            kind: 'result_import_observation', wire: value.wire})),
          ...moon.clientProgramImportedEffectRelationBodies(issued).map(wire =>
            Object.freeze({kind: 'acquisition_relation', wire})),
        ]),
      });
      const sources = observations.map(value => localEffectImportSources.get(value));
      localEffectDependencyTokens.set(value, {kind: 'imported', issued,
        originalSources: sources.every(source => source !== undefined)
          ? Object.freeze(sources) : undefined});
      return value;
    },
    issueDependentLocalEffectResultArtifact(owner, inputs, exported,
      dependency, definition, receipt, retention, context, limits) {
      issuanceLimits(limits, 'Dependent local Effect Result Artifact');
      const owned = localEffectDependencyTokens.get(dependency);
      if (owned === undefined) {
        throw new TypeError('Foreign local Effect dependency evidence');
      }
      const exactContext = localEffectContext(context);
      const result = owned.kind === 'keyed_source'
        ? moon.clientProgramIssueInstalledKeyedSourceEffectLocalResultArtifact(
          owned.parent, owned.plan, owned.request, inputs, exported, owned.issued, definition, receipt,
          ...exactContext, limits.maxWireBytes, limits.maxNodes, limits.maxDepth)
        : owned.kind === 'combined_source'
        ? moon.clientProgramIssueCombinedSourceEffectLocalResultArtifact(
          owner, inputs, exported, owned.issued, definition, receipt,
          ...exactContext, limits.maxWireBytes, limits.maxNodes, limits.maxDepth)
        : owned.kind === 'model'
        ? moon.clientProgramOriginalModelEffectResultArtifact(
          owned.original, owner, inputs, exported, owned.issued, definition, receipt,
          ...exactContext, limits.maxWireBytes, limits.maxNodes, limits.maxDepth)
        : owned.kind === 'source_free'
        ? moon.clientProgramIssueSourceFreeExportedLocalEffectResultArtifact(
          owner, inputs, exported, owned.issued, definition, receipt,
          token(retention), ...exactContext,
          limits.maxWireBytes, limits.maxNodes, limits.maxDepth)
        : owned.kind === 'acquired'
        ? moon.clientProgramIssueAcquiredEffectLocalResultArtifact(
          owner, inputs, exported, owned.issued, definition, receipt,
          ...exactContext, limits.maxWireBytes, limits.maxNodes, limits.maxDepth)
        : moon.clientProgramIssueImportedEffectLocalResultArtifact(
          owner, inputs, exported, owned.issued, definition, receipt,
          token(retention), ...exactContext,
          limits.maxWireBytes, limits.maxNodes, limits.maxDepth);
      const value = inspectLocalEffectArtifact(checked(result));
      // Retain the same producer's nominal provenance with its existing
      // Artifact. This is an alias, not a new Source read or cleanup owner.
      if (owned.kind === 'acquired') localEffectArtifactSources.set(value, owned.issued);
      return value;
    },
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
    admitCapturedResultSnapshot(definition, artifact, rowsWire, fields,
      limits) {
      issuanceLimits(limits, 'Captured Result snapshot');
      if (typeof rowsWire !== 'string' || !Array.isArray(fields) ||
          fields.some(field => typeof field !== 'string')) {
        throw new TypeError('Invalid Captured Result snapshot');
      }
      return inspectSnapshot(checked(
        moon.strategyAdmitCapturedResultSnapshot(
          token(definition),
          token(artifact),
          rowsWire,
          fields,
          limits.maxWireBytes,
          limits.maxNodes,
          limits.maxDepth,
        ),
      ));
    },
    admitCapturedEffectSourceArtifact(preview, memberIndex, invocation,
      artifact, storeAuthorityCid) {
      const ownedPreview = computationPreviewTokens.get(preview);
      if (ownedPreview === undefined ||
          !Number.isSafeInteger(memberIndex) || memberIndex < 0 ||
          typeof storeAuthorityCid !== 'string') {
        throw new TypeError('Invalid captured Effect source artifact');
      }
      return inspectEffectSource(checked(
        moon.strategyAdmitCapturedEffectSourceArtifact(
          ownedPreview, memberIndex, token(invocation), token(artifact),
          storeAuthorityCid,
        ),
      ));
    },
    capturedEffectSourceMatchesPreview(preview, memberIndex, invocation,
      source, localEvidence, storeAuthorityCid, limits) {
      issuanceLimits(limits, 'captured Effect source Preview');
      const ownedPreview = computationPreviewTokens.get(preview);
      if (ownedPreview === undefined || !Number.isSafeInteger(memberIndex) ||
          memberIndex < 0 || typeof storeAuthorityCid !== 'string') {
        throw new TypeError('Invalid captured Effect source Preview');
      }
      return checked(moon.strategyCapturedEffectSourceMatchesPreview(ownedPreview,
        memberIndex, token(invocation), effectSourceToken(source),
        localEffectSourceToken(localEvidence), storeAuthorityCid,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
    },
    reserveEffectCaptureRecovery(parent, input, request, runDefinition, encryptedBytes, limits) {
      issuanceLimits(limits, 'Effect capture recovery');
      if (!Number.isSafeInteger(encryptedBytes) || encryptedBytes < 0 || encryptedBytes > 2147483647 ||
          typeof moon.clientProgramReserveRequestEffectCaptureRecovery !== 'function') {
        throw new TypeError('Invalid Effect capture recovery Resource');
      }
      return checked(moon.clientProgramReserveRequestEffectCaptureRecovery(
        parent, input, request, token(runDefinition), encryptedBytes,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
    },
    reserveEffectCaptureEncrypted(parent, input, request, runDefinition, encryptedBytes, limits) {
      issuanceLimits(limits, 'Effect capture encrypted recovery');
      if (!Number.isSafeInteger(encryptedBytes) || encryptedBytes < 0 || encryptedBytes > 2147483647) throw new TypeError('Invalid Effect capture encrypted Resource');
      return checked(moon.clientProgramReserveRequestEffectCaptureEncrypted(parent, input, request, token(runDefinition), encryptedBytes,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
    },
    reserveEffectCaptureEnvelope(parent, input, request, runDefinition, wire, limits) {
      issuanceLimits(limits, 'Effect capture envelope recovery');
      if (typeof wire !== 'string') throw new TypeError('Invalid Effect capture envelope Resource');
      return checked(moon.clientProgramReserveRequestEffectCaptureEnvelope(parent, input, request, token(runDefinition), wire));
    },
    reserveEffectCaptureDecoded(parent, input, request, runDefinition, wire, limits) {
      issuanceLimits(limits, 'Effect capture decoded recovery');
      if (typeof wire !== 'string') throw new TypeError('Invalid Effect capture decoded Resource');
      return checked(moon.clientProgramReserveRequestEffectCaptureDecoded(parent, input, request, token(runDefinition), wire));
    },
    admitRecoveredEffectCapturedRun(parent, input, request, runDefinition, wire, limits) {
      issuanceLimits(limits, 'Effect captured Run recovery');
      if (typeof wire !== 'string') throw new TypeError('Invalid Effect captured Run recovery');
      const prepared = checked(moon.clientProgramAdmitRequestEffectCapturedRun(parent, input, request, token(runDefinition), wire));
      return inspectPreparedEffectCapturedRun(prepared);
    },
    admitLiveEffectCapturedRun(owner, wire) {
      if (typeof wire !== 'string') throw new TypeError('Invalid live Effect captured Run recovery');
      return inspectPreparedEffectCapturedRun(checked(moon.clientProgramAdmitInstalledEffectCapturedRun(owner, wire)));
    },
    retireRecoveredEffectCapturedRun(captured) {
      const prepared = recoveredEffectCaptures.get(captured);
      if (prepared === undefined) throw new TypeError('Foreign recovered Effect captured Run');
      recoveredEffectCaptures.delete(captured); recoveredEffectCaptures.delete(prepared);
    },
    admitCapturedEffectSourceFromCapture(preview, memberIndex, invocation,
      artifact, capturedRun, storeAuthorityCid, limits) {
      issuanceLimits(limits, 'recovered Effect source');
      const ownedPreview = computationPreviewTokens.get(preview);
      if (ownedPreview === undefined || !Number.isSafeInteger(memberIndex) ||
          memberIndex < 0 || typeof storeAuthorityCid !== 'string') {
        throw new TypeError('Invalid recovered Effect source');
      }
      return inspectEffectSource(checked(moon.strategyAdmitCapturedEffectSourceFromCapture(
        ownedPreview, memberIndex, token(invocation), token(artifact),
        token(capturedRun), storeAuthorityCid, limits.maxWireBytes,
        limits.maxNodes, limits.maxDepth)));
    },
    issueEffectSourceArtifactFromExport(input, receipt, invocation,
      retention, sourceBindingCid, storeAuthorityCid, limits) {
      issuanceLimits(limits, 'Effect source Artifact');
      if (typeof moon.clientProgramIssueEffectSourceArtifact !== 'function' ||
          typeof sourceBindingCid !== 'string' ||
          typeof storeAuthorityCid !== 'string') {
        throw new TypeError('Invalid Effect source Artifact export');
      }
      return inspect(checked(moon.clientProgramIssueEffectSourceArtifact(
        input, receipt, token(invocation), token(retention),
        sourceBindingCid, storeAuthorityCid, limits.maxWireBytes,
        limits.maxNodes, limits.maxDepth,
      )));
    },
    issueEffectTableSourceArtifactFromExport(input, receipt, invocation,
      retention, sourceBindingCid, storeAuthorityCid, limits) {
      issuanceLimits(limits, 'private Table source Artifact');
      if (typeof moon.clientProgramIssueEffectTableSourceArtifact !== 'function' ||
          typeof sourceBindingCid !== 'string' || typeof storeAuthorityCid !== 'string') {
        throw new TypeError('Invalid private Table source export');
      }
      return inspect(checked(moon.clientProgramIssueEffectTableSourceArtifact(
        input, receipt, token(invocation), token(retention), sourceBindingCid,
        storeAuthorityCid, limits.maxWireBytes, limits.maxNodes, limits.maxDepth)));
    },
    admitCapturedEffectSourceFromTableInput(preview, memberIndex, invocation,
      artifact, input, storeAuthorityCid, limits) {
      issuanceLimits(limits, 'captured private Table source');
      const ownedPreview = computationPreviewTokens.get(preview);
      const ownedInput = localEffectArtifactTokens.get(input);
      if (ownedPreview === undefined || ownedInput === undefined ||
          !Number.isSafeInteger(memberIndex) || memberIndex < 0) {
        throw new TypeError('Invalid captured private Table source owner');
      }
      const relation = checked(moon.strategyPublicationAdmit('result_artifact',
        moon.clientProgramLocalEffectResultArtifactJson(ownedInput),
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      return inspectEffectSource(checked(moon.strategyAdmitCapturedEffectSourceFromTableInput(
        ownedPreview, memberIndex, token(invocation), token(artifact), relation,
        storeAuthorityCid)));
    },
    admitCapturedEffectSourceFromResult(preview, memberIndex, invocation,
      artifact, result, storeAuthorityCid, limits) {
      issuanceLimits(limits, 'captured Table source');
      const ownedPreview = computationPreviewTokens.get(preview);
      const ownedResult = localEffectArtifactTokens.get(result);
      if (ownedPreview === undefined || ownedResult === undefined ||
          !Number.isSafeInteger(memberIndex) || memberIndex < 0) {
        throw new TypeError('Invalid captured Table source owner');
      }
      const publicationResult = checked(moon.strategyPublicationAdmit('result_artifact',
        moon.clientProgramLocalEffectResultArtifactJson(ownedResult),
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      return inspectEffectSource(checked(moon.strategyAdmitCapturedEffectSourceFromResult(
        ownedPreview, memberIndex, token(invocation), token(artifact),
        publicationResult, storeAuthorityCid)));
    },
    issueSourceFreeLocalEffectResultArtifact(owner, inputs, memberIndex,
      importing, definition, localInvocation, receipt, retention, context,
      limits) {
      issuanceLimits(limits, 'local Effect Result Artifact');
      if (!Number.isSafeInteger(memberIndex) || memberIndex < 0 ||
          context === null || typeof context !== 'object' ||
          !['admission', 'runDefinition', 'runInvocation', 'observation']
            .every(key => context[key] !== undefined)) {
        throw new TypeError('Invalid local Effect Result Artifact');
      }
      const issued = checked(
        moon.clientProgramIssueSourceFreeLocalEffectResultArtifact(
          owner, inputs, memberIndex, importing, definition, localInvocation,
          receipt, token(retention), admissionToken(context.admission),
          token(context.runDefinition), token(context.runInvocation),
          evidenceToken(context.observation),
          limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      return inspectLocalEffectArtifact(issued);
    },
    issueSourceFreeExportedLocalEffectResultArtifact(owner, inputs, exported,
      definition, invocation, receipt, retention, context, limits) {
      issuanceLimits(limits, 'source-free local Manifest Result');
      return inspectLocalEffectArtifact(checked(
        moon.clientProgramIssueSourceFreeExportedLocalEffectResultArtifact(
          owner, inputs, exported, invocation, definition, receipt,
          token(retention), ...localEffectContext(context),
          limits.maxWireBytes, limits.maxNodes, limits.maxDepth)));
    },
    issueSourceFreeLocalEffectTableArtifact(owner, inputs, memberIndex,
      importing, definition, localInvocation, receipt, retention, context, limits) {
      issuanceLimits(limits, 'private Table semantic Artifact');
      if (!Number.isSafeInteger(memberIndex) || memberIndex < 0) {
        throw new TypeError('Invalid private Table member');
      }
      return inspectLocalEffectArtifact(checked(
        moon.clientProgramIssueSourceFreeLocalEffectTableArtifact(
          owner, inputs, memberIndex, importing, definition, localInvocation,
          receipt, token(retention), ...localEffectContext(context),
          limits.maxWireBytes, limits.maxNodes, limits.maxDepth)));
    },
    issueDependentLocalEffectTableArtifact(owner, inputs, memberIndex,
      importing, dependency, definition, receipt, retention, context, limits) {
      issuanceLimits(limits, 'dependent private Table semantic Artifact');
      const owned = localEffectDependencyTokens.get(dependency);
      if (owned === undefined || !Number.isSafeInteger(memberIndex) || memberIndex < 0) {
        throw new TypeError('Foreign private Table dependency evidence');
      }
      const exactContext = localEffectContext(context);
      const result = owned.kind === 'source_free'
        ? moon.clientProgramIssueSourceFreeLocalEffectTableArtifact(
          owner, inputs, memberIndex, importing, definition, owned.issued,
          receipt, token(retention), ...exactContext,
          limits.maxWireBytes, limits.maxNodes, limits.maxDepth)
        : owned.kind === 'imported'
        ? moon.clientProgramIssueImportedLocalEffectTableArtifact(
          owner, inputs, memberIndex, importing, definition, owned.issued,
          receipt, token(retention), ...exactContext,
          limits.maxWireBytes, limits.maxNodes, limits.maxDepth)
        : undefined;
      if (result === undefined) {
        throw new TypeError('UnavailableAcquiredPrivateTableEvidence');
      }
      return inspectLocalEffectArtifact(checked(result));
    },
    issueLocalEffectResultManifest(owner, invocation, artifacts, limits) {
      issuanceLimits(limits, 'local Effect Result Manifest');
      if (!Array.isArray(artifacts) || artifacts.length === 0) {
        throw new TypeError('Invalid local Effect Result Manifest');
      }
      const owned = artifacts.map(artifact => {
        const token = localEffectArtifactTokens.get(artifact);
        if (token === undefined) {
          throw new TypeError('Foreign local Effect Result Artifact');
        }
        return token;
      });
      const issued = checked(moon.clientProgramIssueLocalEffectResultManifest(
        owner, invocation, owned, limits.maxWireBytes, limits.maxNodes,
        limits.maxDepth));
      const value = Object.freeze({
        identity: moon.clientProgramLocalEffectResultManifestCid(issued),
        wire: moon.clientProgramLocalEffectResultManifestJson(issued),
      });
      localEffectManifestTokens.set(value, issued);
      return value;
    },
    localEffectSourceMatches(owner, inputs, memberIndex, manifest,
      invocation, artifact, source) {
      const ownedManifest = localEffectManifestTokens.get(manifest);
      const ownedArtifact = localEffectArtifactTokens.get(artifact);
      if (ownedManifest === undefined || ownedArtifact === undefined ||
          !Number.isSafeInteger(memberIndex) || memberIndex < 0) {
        throw new TypeError('Foreign local Effect source evidence');
      }
      return moon.clientProgramLocalEffectSourceMatches(
        owner, inputs, memberIndex, ownedManifest, invocation,
        ownedArtifact, effectSourceToken(source));
    },
    admitLocalEffectSourceEvidence(owner, inputs, memberIndex, manifest,
      invocation, artifact, source, limits) {
      issuanceLimits(limits, 'local Effect source evidence');
      const ownedManifest = localEffectManifestTokens.get(manifest);
      const ownedArtifact = localEffectArtifactTokens.get(artifact);
      if (ownedManifest === undefined || ownedArtifact === undefined ||
          !Number.isSafeInteger(memberIndex) || memberIndex < 0) {
        throw new TypeError('Foreign local Effect source evidence');
      }
      const issued = checked(moon.clientProgramAdmitLocalEffectSourceEvidence(
        owner, inputs, memberIndex, ownedManifest, invocation,
        ownedArtifact, effectSourceToken(source), limits.maxWireBytes,
        limits.maxNodes, limits.maxDepth));
      const value = Object.freeze({kind: 'captured-local-effect-source'});
      localEffectSourceTokens.set(value, issued);
      return value;
    },
    issueSourceFreeLocalEffectIdentity(owner, inputs, memberIndex, artifact,
      limits) {
      issuanceLimits(limits, 'local Effect identity');
      const ownedArtifact = localEffectArtifactTokens.get(artifact);
      if (ownedArtifact === undefined ||
          !Number.isSafeInteger(memberIndex) || memberIndex < 0 ||
          !Number.isSafeInteger(limits.maxWork) || limits.maxWork < 1) {
        throw new TypeError('Invalid local Effect identity owner');
      }
      const issued = checked(
        moon.clientProgramIssueSourceFreeLocalEffectIdentity(
          owner, inputs, memberIndex, ownedArtifact, limits.maxWork,
          limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      const value = Object.freeze({
        identity: moon.clientProgramLocalEffectIdentityCid(issued),
        wire: moon.clientProgramLocalEffectIdentityJson(issued),
      });
      localEffectIdentityTokens.set(value, issued);
      return value;
    },
    prepareEffectCommandContentArtifact(owner, inputs, memberIndex, artifact, limits) {
      const owned = localEffectArtifactTokens.get(artifact);
      if (owned === undefined || ![memberIndex, limits?.maxFields, limits?.maxWork]
        .every(value => Number.isSafeInteger(value) && value >= 0)) {
        throw new TypeError('Invalid original Effect Content Artifact');
      }
      checked(moon.clientProgramEffectCommandContentPrepareArtifact(
        owner, inputs, memberIndex, owned, limits.maxFields, limits.maxWork));
    },
    releaseEffectCommandContentArtifact(artifact, quantum) {
      const owned = localEffectArtifactTokens.get(artifact);
      if (owned === undefined || !Number.isSafeInteger(quantum) || quantum <= 0) {
        throw new TypeError('Invalid original Effect Content retirement');
      }
      return moon.clientProgramEffectCommandContentReleaseArtifact(owned, quantum);
    },
    borrowEffectCommandContent(owner, inputs, memberIndex, artifact, row,
      inputName, limits) {
      const ownedArtifact = localEffectArtifactTokens.get(artifact);
      if (ownedArtifact === undefined || typeof inputName !== 'string' ||
          ![memberIndex, row, limits?.maxFields, limits?.maxWork].every(
            value => Number.isSafeInteger(value) && value >= 0)) {
        throw new TypeError('Invalid original Effect Content input');
      }
      const view = checked(moon.clientProgramEffectCommandContentBorrow(
        owner, inputs, memberIndex, ownedArtifact, row, inputName,
        limits.maxFields, limits.maxWork));
      let original = {view, owner, inputs, memberIndex,
        artifact: ownedArtifact, row, inputName};
      const current = () => original !== undefined &&
        moon.clientProgramEffectCommandContentMatches(original.view,
          original.owner, original.inputs, original.memberIndex,
          original.artifact, original.row, original.inputName);
      // A physical preparation retains this view before awaiting. Its wire is
      // observed DATA, not byte custody, a capacity loan or a read/send grant.
      return Object.freeze({binding: view, current,
        matchesIssued(issued) {
          const retained = original;
          return retained !== undefined &&
            moon.clientProgramEffectCommandContentMatchesIssued(retained.view, issued) &&
            original === retained;
        },
        wire() {
          if (!current()) throw new TypeError('Original Effect Content unavailable');
          return checked(moon.clientProgramEffectCommandContentWire(original.view));
        },
        release() {
          if (original === undefined) return;
          moon.clientProgramEffectCommandContentRelease(original.view);
          original = undefined;
        }});
    },
    recoverEffectCommandContent({compiled, prepared, definition, captured, preview,
      invocation, source, storeAuthorityCid, generationIndex, memberIndex, row,
      inputName, candidate, issued, limits}) {
      issuanceLimits(limits, 'Recovered Effect Content');
      const run = compiledContent(compiled);
      const admittedPreview = computationPreviewTokens.get(preview);
      if (admittedPreview === undefined || typeof inputName !== 'string' ||
          ![generationIndex, memberIndex, row, limits.maxFields, limits.maxWork]
            .every(value => Number.isSafeInteger(value) && value >= 0)) {
        throw new TypeError('Invalid recovered Effect Content input');
      }
      const original = {run, prepared, definition: token(definition), captured: token(captured),
        preview: admittedPreview, memberIndex, row, inputName};
      const view = checked(moon.clientProgramRecoverEffectCommandContent(run, prepared,
        original.definition, original.captured, admittedPreview, token(invocation), effectSourceToken(source),
        storeAuthorityCid, generationIndex, memberIndex, row, inputName, candidate, issued,
        limits.maxFields, limits.maxWork, limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      let retained = original;
      const current = () => retained !== undefined &&
        moon.clientProgramRecoveredEffectCommandContentMatches(view, original.run,
          original.prepared, original.definition, original.captured, original.preview,
          original.memberIndex, original.row, original.inputName) && retained === original;
      return Object.freeze({binding: view, current,
        matchesIssued(value) {
          return retained !== undefined &&
            moon.clientProgramRecoveredEffectCommandContentMatchesIssued(view, value) &&
            retained === original;
        },
        wire() {
          if (!current()) throw new TypeError('Recovered Effect Content unavailable');
          return checked(moon.clientProgramRecoveredEffectCommandContentWire(view));
        },
        release() {
          if (retained === undefined) return;
          moon.clientProgramRecoveredEffectCommandContentRelease(view);
          retained = undefined;
        }});
    },
    recoverSourceEffectCommandContent({sourceOriginal, prepared, request, definition,
      captured, preview, invocation, source, storeAuthorityCid, memberIndex, row,
      inputName, candidate, issued, limits}) {
      issuanceLimits(limits, 'Recovered Source Effect Content');
      const admittedPreview = computationPreviewTokens.get(preview);
      if (admittedPreview === undefined || typeof inputName !== 'string' ||
          ![memberIndex, row, limits.maxFields, limits.maxWork]
            .every(value => Number.isSafeInteger(value) && value >= 0)) {
        throw new TypeError('Invalid recovered Source Effect Content input');
      }
      const original = {sourceOriginal, prepared, request, definition: token(definition),
        captured: token(captured), preview: admittedPreview, memberIndex, row, inputName};
      const view = checked(moon.clientProgramRecoverSourceEffectCommandContent(sourceOriginal,
        prepared, request, original.definition, original.captured, admittedPreview,
        token(invocation), effectSourceToken(source), storeAuthorityCid, memberIndex,
        row, inputName, candidate, issued, limits.maxFields, limits.maxWork,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      let retained = original;
      const current = () => retained !== undefined &&
        moon.clientProgramRecoveredSourceEffectCommandContentMatches(view,
          original.sourceOriginal, original.prepared, original.request, original.definition,
          original.captured, original.preview, original.memberIndex, original.row,
          original.inputName) && retained === original;
      return Object.freeze({binding: view, current,
        matchesIssued(value) {
          return retained !== undefined &&
            moon.clientProgramRecoveredSourceEffectCommandContentMatchesIssued(view, value) &&
            retained === original;
        },
        wire() {
          if (!current()) throw new TypeError('Recovered Source Effect Content unavailable');
          return checked(moon.clientProgramRecoveredSourceEffectCommandContentWire(view));
        },
        release() {
          if (retained === undefined) return;
          moon.clientProgramRecoveredSourceEffectCommandContentRelease(view);
          retained = undefined;
        }});
    },
    localEffectTableStorageMapping(artifact, limits) {
      issuanceLimits(limits, 'Table storage mapping');
      const owned = localEffectArtifactTokens.get(artifact);
      if (owned === undefined) throw new TypeError('Foreign Table input Artifact');
      const issued = checked(moon.clientProgramLocalEffectTableStorageMapping(
        owned, limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      return Object.freeze({
        identity: moon.clientProgramLocalTableStorageMappingCid(issued),
        wire: moon.clientProgramLocalTableStorageMappingJson(issued),
      });
    },
    admitLocalTableStorageMapping(wire, limits) {
      issuanceLimits(limits, 'Local Table storage mapping');
      if (typeof wire !== 'string') throw new TypeError('Invalid Local Table mapping');
      const admitted = checked(moon.clientProgramAdmitLocalTableStorageMapping(
        wire, limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      return Object.freeze({
        identity: moon.clientProgramLocalTableStorageMappingCid(admitted),
        wire: moon.clientProgramLocalTableStorageMappingJson(admitted),
      });
    },
    bindTableInput(owner, inputs, memberIndex, artifact, identity, scope,
      operationWire, mappingWire, limits) {
      issuanceLimits(limits, 'Table input');
      const ownedArtifact = localEffectArtifactTokens.get(artifact);
      const ownedIdentity = localEffectIdentityTokens.get(identity);
      if (ownedArtifact === undefined || ownedIdentity === undefined ||
          !Number.isSafeInteger(memberIndex) || memberIndex < 0 ||
          typeof operationWire !== 'string' || typeof mappingWire !== 'string') {
        throw new TypeError('Invalid Table input owner');
      }
      const issued = checked(moon.clientProgramBindTableInput(
        owner, inputs, memberIndex, ownedArtifact, ownedIdentity, scope,
        operationWire, mappingWire, limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      // Content/owner binding only. Nothing stages or dispatches a Table write.
      const value = Object.freeze({
        wire: moon.clientProgramTableInputOperationJson(issued),
      });
      tableInputTokens.set(value, issued);
      return value;
    },
    tableInputMatchesSource(input, artifact, identity) {
      const ownedInput = tableInputTokens.get(input);
      const ownedArtifact = localEffectArtifactTokens.get(artifact);
      const ownedIdentity = localEffectIdentityTokens.get(identity);
      if (ownedInput === undefined || ownedArtifact === undefined ||
          ownedIdentity === undefined) {
        throw new TypeError('Foreign Table input source');
      }
      return moon.clientProgramTableInputMatchesSource(ownedInput,
        ownedArtifact, ownedIdentity);
    },
    tableInputStorageMappingWire(input) {
      const owned = tableInputTokens.get(input);
      if (owned === undefined) throw new TypeError('Foreign Table input');
      return moon.clientProgramTableInputStorageMappingJson(owned);
    },
    tableInputSchemaWire(input) {
      const owned = tableInputTokens.get(input);
      if (owned === undefined) throw new TypeError('Foreign Table input');
      return moon.clientProgramTableInputSchemaWire(owned);
    },
    checkRecoveredTableSchemaWire(preview, wire, limits) {
      issuanceLimits(limits, 'recovered Table schema');
      const owned = recoveredTablePreviewTokens.get(preview);
      if (owned === undefined || typeof wire !== 'string') {
        throw new TypeError('Foreign recovered Table schema');
      }
      checked(moon.clientProgramCheckRecoveredTableSchemaWire(owned, wire,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      return wire;
    },
    bindRecoveredTablePreview(preview, memberIndex, invocation, source,
      capturedRun, scope, mappingWire, storeAuthorityCid, limits, tableLimits) {
      issuanceLimits(limits, 'recovered Table Preview');
      issuanceLimits(tableLimits, 'recovered Table material');
      const ownedPreview = computationPreviewTokens.get(preview);
      if (ownedPreview === undefined || !Number.isSafeInteger(memberIndex) ||
          memberIndex < 0 || typeof mappingWire !== 'string' ||
          typeof storeAuthorityCid !== 'string') {
        throw new TypeError('Invalid recovered Table Preview');
      }
      const issued = checked(moon.clientProgramBindRecoveredTablePreview(
        ownedPreview, memberIndex, token(invocation), effectSourceToken(source),
        token(capturedRun), scope, mappingWire, storeAuthorityCid,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth,
        tableLimits.maxWireBytes, tableLimits.maxNodes, tableLimits.maxDepth));
      const value = Object.freeze({
        subjectCid: moon.clientProgramRecoveredTablePreviewSubjectCid(issued),
        operationWire: moon.clientProgramRecoveredTablePreviewOperationJson(issued),
        mappingWire: moon.clientProgramRecoveredTablePreviewMappingJson(issued),
      });
      recoveredTablePreviewTokens.set(value, issued);
      return value;
    },
    recoveredTablePreviewMatchesSource(preview, source) {
      const owned = recoveredTablePreviewTokens.get(preview);
      if (owned === undefined) throw new TypeError('Foreign recovered Table Preview');
      return moon.clientProgramRecoveredTablePreviewMatchesSource(owned,
        effectSourceToken(source));
    },
    bindTablePreview(input, capturedPreview, memberIndex) {
      const ownedInput = tableInputTokens.get(input);
      if (ownedInput === undefined || !Number.isSafeInteger(memberIndex) ||
          memberIndex < 0) throw new TypeError('Invalid Table Preview input');
      const issued = checked(moon.clientProgramBindTablePreview(ownedInput,
        capturedPreview, memberIndex));
      const value = Object.freeze({
        subjectCid: moon.clientProgramTablePreviewSubjectCid(issued),
        operationWire: moon.clientProgramTablePreviewOperationJson(issued),
      });
      tablePreviewTokens.set(value, issued);
      return value;
    },
    tablePreviewInputAvailable(preview) {
      const owned = tablePreviewTokens.get(preview);
      if (owned === undefined) throw new TypeError('Foreign Table Preview');
      return moon.clientProgramTablePreviewInputAvailable(owned);
    },
    localTableCommitResponse(responseWire, statusCode, limits) {
      issuanceLimits(limits, 'Local Table physical response');
      if (typeof responseWire !== 'string' || !Number.isSafeInteger(statusCode)) {
        throw new TypeError('Invalid Local Table physical response');
      }
      return checked(moon.clientProgramLocalTableCommitResponse(responseWire,
        statusCode, limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
    },
    tablePreviewCommitOutcome(preview, responseWire, statusCode, limits) {
      issuanceLimits(limits, 'Table commit outcome');
      const owned = tablePreviewTokens.get(preview);
      const recovered = recoveredTablePreviewTokens.get(preview);
      if (recovered !== undefined && typeof responseWire === 'string' &&
          Number.isSafeInteger(statusCode)) {
        return checked(moon.clientProgramRecoveredTablePreviewCommitOutcome(
          recovered, responseWire, statusCode, limits.maxWireBytes,
          limits.maxNodes, limits.maxDepth));
      }
      if (owned === undefined || typeof responseWire !== 'string' ||
          !Number.isSafeInteger(statusCode)) {
        throw new TypeError('Invalid Table commit response owner');
      }
      return checked(moon.clientProgramTablePreviewCommitOutcome(owned,
        responseWire, statusCode, limits.maxWireBytes, limits.maxNodes,
        limits.maxDepth));
    },
    tablePreviewLedgerBinding(preview) {
      const owned = tablePreviewTokens.get(preview);
      const recovered = recoveredTablePreviewTokens.get(preview);
      if (recovered !== undefined) {
        const identity = moon.clientProgramRecoveredTablePreviewLedgerIdentity(recovered);
        const memberIndex = moon.clientProgramRecoveredTablePreviewMemberIndex(recovered);
        return Object.freeze({preview: identity, memberIndex,
          rowPreviewCid: moon.strategyEffectPreviewOrderedRowCid(identity, memberIndex, 0),
          operationWire: moon.clientProgramRecoveredTablePreviewOperationJson(recovered)});
      }
      if (owned === undefined) throw new TypeError('Foreign Table Preview');
      const identity = moon.clientProgramTablePreviewLedgerIdentity(owned);
      const memberIndex = moon.clientProgramTablePreviewMemberIndex(owned);
      return Object.freeze({
        preview: identity, memberIndex,
        rowPreviewCid: moon.strategyEffectPreviewOrderedRowCid(identity, memberIndex, 0),
        operationWire: moon.clientProgramTablePreviewOperationJson(owned),
      });
    },
    admitTablePreviewClaim(preview, claim) {
      const binding = control.tablePreviewLedgerBinding(preview);
      return checked(moon.strategyEffectMemberRowAdmit(binding.preview,
        binding.memberIndex, 0, 'store', claim.scope, binding.rowPreviewCid,
        claim.locator, claim.key));
    },
    checkSourceFreeLocalEffectPreviewIdentities(owner, inputs, wire,
      runIdentityCid, authoringContextCid, identities, limits) {
      issuanceLimits(limits, 'local Effect Preview identities');
      if (typeof wire !== 'string' ||
          typeof runIdentityCid !== 'string' ||
          typeof authoringContextCid !== 'string' ||
          !Array.isArray(identities)) {
        throw new TypeError('Invalid local Effect Preview identities');
      }
      const owned = identities.map(identity => {
        const token = localEffectIdentityTokens.get(identity);
        if (token === undefined) {
          throw new TypeError('Foreign local Effect identity');
        }
        return token;
      });
      return checked(
        moon.clientProgramCheckSourceFreeLocalEffectPreviewIdentities(
          owner, inputs, wire, runIdentityCid, authoringContextCid, owned,
          limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
    },
    effectSourceArtifactPreviewBinding(artifact, invocationCid, sourceResult,
      storeAuthorityCid) {
      return checked(moon.clientProgramEffectSourceArtifactPreviewBinding(
        token(artifact), invocationCid, sourceResult, storeAuthorityCid));
    },
    effectTableSourceArtifactPreviewBinding(artifact, invocationCid, sourceTableInput,
      storeAuthorityCid) {
      return checked(moon.clientProgramEffectTableSourceArtifactPreviewBinding(
        token(artifact), invocationCid, sourceTableInput, storeAuthorityCid));
    },
    capturedEffectSourceHoldingCid(source) {
      return moon.strategyCapturedEffectSourceHoldingCid(
        effectSourceToken(source));
    },
    capturedEffectSourceArtifactCid(source) {
      return moon.strategyCapturedEffectSourceArtifactCid(
        effectSourceToken(source));
    },
    capturedEffectSourceStoreAuthorityCid(source) {
      return moon.strategyCapturedEffectSourceStoreAuthorityCid(
        effectSourceToken(source));
    },
    async admitCompletedResultSnapshot(exportHandle, outputLimits, signal, publicationResource) {
      if (publicationResource !== undefined) {
        return finishProgramSnapshot(publicationResource, exportHandle, signal);
      }
      // Bare row emission and captured admission share this bound; the latter
      // includes the canonical relation wrapper. Borrow the existing checked
      // output policy without constructing a second quota or projection cache.
      if (outputLimits === null || typeof outputLimits !== 'object' ||
          !Number.isSafeInteger(outputLimits.maxLogicalWireBytes) ||
          !Number.isSafeInteger(outputLimits.maxLogicalWireNodes) ||
          !Number.isSafeInteger(outputLimits.maxLogicalWireDepth) ||
          outputLimits.maxLogicalWireBytes < 0 || outputLimits.maxLogicalWireBytes > 2147483647 ||
          outputLimits.maxLogicalWireNodes < 0 || outputLimits.maxLogicalWireNodes > 2147483647 ||
          outputLimits.maxLogicalWireDepth < 0 || outputLimits.maxLogicalWireDepth > 2147483647) {
        throw new TypeError('Invalid completed Result snapshot output limits');
      }
      signal?.throwIfAborted();
      const preparation = checked(moon.strategyHostOutputSnapshotBegin(
        exportHandle, outputLimits.maxLogicalWireBytes,
        outputLimits.maxLogicalWireNodes, outputLimits.maxLogicalWireDepth));
      let finished = false;
      try {
        while (true) {
          signal?.throwIfAborted();
          if (checked(moon.strategyHostOutputSnapshotAdvance(
            preparation, 256))) break;
          await new Promise(resolve => setTimeout(resolve, 0));
        }
        signal?.throwIfAborted();
        const snapshot = inspectSnapshot(checked(
          moon.strategyHostOutputSnapshotFinish(preparation)));
        finished = true;
        return snapshot;
      } finally {
        if (!finished) moon.strategyHostOutputSnapshotCancel(preparation);
      }
    },
    admitPendingSourceStateAdvance(completeWire, observation, limits) {
      issuanceLimits(limits, 'pending source-state advance');
      if (typeof completeWire !== 'string') {
        throw new TypeError('Invalid pending source-state advance');
      }
      return inspectSourceAdvance(checked(
        moon.strategyAdmitPendingSourceStateAdvance(
          completeWire,
          evidenceToken(observation),
          limits.maxWireBytes,
          limits.maxNodes,
          limits.maxDepth,
        ),
      ));
    },
    async issueEffectFreeCapturedRun(chain, evidence, limits, signal, publicationResource) {
      limits = captureContractLimits(limits, 'Captured Run');
      if (chain === null || typeof chain !== 'object' ||
          evidence === null || typeof evidence !== 'object' ||
          !Array.isArray(chain.definitions) ||
          !Array.isArray(chain.artifacts) ||
          !Array.isArray(evidence.snapshots) ||
          !Array.isArray(evidence.pendingSourceStateAdvances) ||
          !Array.isArray(evidence.modelEvidence)) {
        throw new TypeError('Invalid Captured Run request');
      }
      signal?.throwIfAborted();
      if (publicationResource !== undefined) {
        if (evidence.pendingSourceStateAdvances.length !== 0 ||
            evidence.modelEvidence.length !== 0 ||
            (evidence.contentGenerations !== undefined &&
              (!Array.isArray(evidence.contentGenerations) ||
                evidence.contentGenerations.length !== 0))) {
          throw new TypeError('Invalid original program capture profile');
        }
        const capture = checked(moon.clientProgramPrepareCapture(
          publicationResource, token(chain.runDefinition), token(chain.invocation),
          chain.definitions.map(token), chain.artifacts.map(token),
          token(chain.manifest), token(chain.receipt),
          evidence.snapshots.map(snapshotToken),
          evidenceToken(evidence.authoringContext),
          evidence.modelEvidence.map(evidenceToken),
        ));
        return finishProgramCapture(capture, signal);
      }
      const preparation = moon.strategyBeginOriginalEffectFreeCapturedRun(
        token(chain.runDefinition),
        token(chain.invocation),
        chain.definitions.map(token),
        chain.artifacts.map(token),
        token(chain.manifest),
        token(chain.receipt),
        evidence.snapshots.map(snapshotToken),
        evidence.pendingSourceStateAdvances.map(sourceAdvanceToken),
        evidenceToken(evidence.authoringContext),
        evidence.modelEvidence.map(evidenceToken),
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
        moon.strategyPublicationEvidenceWorkspace(limits.maxNodes),
        contentCaptures(evidence.contentGenerations),
      );
      return finishCapturedPreparation(preparation, signal, true);
    },
    retireCapturedComputation(capturedRun) {
      token(capturedRun);
      const original = capturedComputationPreparations.get(capturedRun);
      if (original === undefined) return;
      // The publication operation owns this alias through reconciliation.
      // Cancel releases managed facts, not physical children or an ACK.
      if (original.program !== undefined) moon.clientProgramCancelCapture(original.program);
      else moon.strategyCapturedRunCancel(original);
      capturedComputationPreparations.delete(capturedRun);
    },
    admitEffectComputationPreview(wire, runDefinition, authoring, limits) {
      issuanceLimits(limits, 'Effect computation Preview');
      if (typeof wire !== 'string' ||
          typeof authoring?.identity !== 'string') {
        throw new TypeError('Invalid Effect computation Preview');
      }
      token(runDefinition);
      evidenceToken(authoring);
      const preview = checked(moon.strategyAdmitEffectComputationPreview(
        wire, runDefinition.identity,
        authoring.identity,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth,
      ));
      const owned = Object.freeze({kind: 'effect-computation-preview'});
      computationPreviewTokens.set(owned, preview);
      computationPreviewWires.set(owned, wire);
      return owned;
    },
    effectComputationPreviewLedgerIdentity(preview) {
      const admitted = computationPreviewTokens.get(preview);
      if (admitted === undefined) {
        throw new TypeError('Foreign Effect computation Preview');
      }
      return admitted;
    },
    retainInstalledEffectRecoveredInputInventory(run, prepared, request, plan,
      allowed, definition, invocation, preview) {
      const admitted = computationPreviewTokens.get(preview);
      if (admitted === undefined) throw new TypeError('Foreign Effect computation Preview');
      return checked(moon.clientProgramInstalledEffectRecoveredInputInventoryRetain(
        run, prepared, request, plan, allowed, definition, token(invocation), admitted));
    },
    recoverInstalledEffectPreviewKeys(run, prepared, request, plan,
      allowed, definition, invocation, preview, scope, maxMembers, maxRows, maxWork,
      maxKeyBytes, maxKeyNodes, maxKeyDepth, construction) {
      const admitted = computationPreviewTokens.get(preview);
      if (admitted === undefined) throw new TypeError('Foreign Effect computation Preview');
      if (typeof construction !== 'function') throw new TypeError('Missing original Effect construction');
      return checked(construction(moon, moon.clientProgramInstalledEffectRecoveredPreviewKeys, [
        run, prepared, request, plan, allowed, definition, token(invocation), admitted, scope,
        maxMembers, maxRows, maxWork, maxKeyBytes, maxKeyNodes, maxKeyDepth]));
    },
    effectComputationPreviewSemanticCid(preview) {
      const admitted = computationPreviewTokens.get(preview);
      if (admitted === undefined) {
        throw new TypeError('Foreign Effect computation Preview');
      }
      return moon.strategyEffectPreviewSemanticCid(admitted);
    },
    effectComputationPreviewWire(preview) {
      const wire = computationPreviewWires.get(preview);
      if (wire === undefined) {
        throw new TypeError('Foreign Effect computation Preview');
      }
      return wire;
    },
    effectComputationReviewConstructionCapacity(preview, limits, previewLimits = limits) {
      issuanceLimits(limits, 'Effect review projection');
      issuanceLimits(previewLimits, 'Effect review Preview');
      // SAME private admission key: the identity and immutable wire cannot be
      // supplied independently or replaced by a copied/equal-CID Preview.
      const original = computationPreviewTokens.get(preview);
      const wire = computationPreviewWires.get(preview);
      if (original === undefined || wire === undefined) {
        throw new TypeError('Foreign Effect computation Preview');
      }
      return moon.clientProgramEffectReviewOriginalConstructionCapacity(original,
        wire, previewLimits.maxWireBytes, previewLimits.maxNodes,
        previewLimits.maxDepth, limits.maxWireBytes, limits.maxNodes,
        limits.maxDepth);
    },
    projectEffectComputationReview(preview, policy, limits, previewLimits = limits) {
      issuanceLimits(limits, 'Effect review projection');
      issuanceLimits(previewLimits, 'Effect review Preview');
      const original = computationPreviewTokens.get(preview);
      const wire = computationPreviewWires.get(preview);
      if (original === undefined || wire === undefined) {
        throw new TypeError('Foreign Effect computation Preview');
      }
      return inspectEvidence(checked(moon.clientProgramProjectEffectReview(
        original, wire, policy.authorityScopeCid, policy.approvalClaims,
        policy.redactionPolicyCid, limits.maxWireBytes, limits.maxNodes,
        limits.maxDepth, previewLimits.maxWireBytes, previewLimits.maxNodes,
        previewLimits.maxDepth)));
    },
    // Private original Client/Checkpoint binding. These operations accept the
    // Common-issued opaque view, never a wire/CID reconstructed substitute.
    requestedEffectStopLifetime(original) {
      const lifetime = checked(moon.clientProgramRequestedEffectStopLifetime(original));
      return Object.freeze({createdAt: runtimeField(lifetime, 0),
        validUntil: runtimeField(lifetime, 1)});
    },
    requestedEffectStopIntentCid(original) {
      return moon.clientProgramRequestedEffectStopIntentCid(original);
    },
    restoreRequestedEffectStop(original, identity, materials, invocation, preview, limits) {
      const admitted = computationPreviewTokens.get(preview);
      if (admitted === undefined) throw new TypeError('Foreign Effect computation Preview');
      return runtimeUnboxedReferenceOption(checked(moon.clientProgramRestoreRequestedEffectStop(
        original.intent, original.referenceWire, identity, materials,
        token(invocation), admitted, limits)));
    },
    sealRequestedEffectStop(original, bodyWire, continuationWire, limits) {
      issuanceLimits(limits, 'Requested Effect stop');
      return checked(moon.clientProgramRequestedEffectStopCheckpoint(original,
        bodyWire, continuationWire, limits.maxWireBytes, limits.maxNodes,
        limits.maxDepth));
    },
    effectPrivateEvidenceBinding(preview, storeAuthorityCid) {
      const ownedPreview = computationPreviewTokens.get(preview);
      if (ownedPreview === undefined) {
        throw new TypeError('Foreign Effect computation Preview');
      }
      return Object.freeze({
        name: 'effect_preview',
        semanticCid: moon.strategyEffectPreviewSemanticCid(ownedPreview),
        holdingCid: checked(moon.strategyEffectPreviewPrivateHoldingCid(
          ownedPreview, storeAuthorityCid,
        )),
        wire: computationPreviewWires.get(preview),
      });
    },
    effectComputationCaptureHoldingCid(runDefinition, storeAuthorityCid) {
      if (typeof storeAuthorityCid !== 'string') {
        throw new TypeError('Invalid Effect computation capture holding');
      }
      return checked(moon.strategyEffectComputationCaptureHoldingCid(
        token(runDefinition), storeAuthorityCid,
      ));
    },
    effectComputationRecordHoldingCid(runDefinition, storeAuthorityCid) {
      if (typeof storeAuthorityCid !== 'string') {
        throw new TypeError('Invalid Effect computation record holding');
      }
      return checked(moon.strategyEffectComputationRecordHoldingCid(
        token(runDefinition), storeAuthorityCid,
      ));
    },
    effectfulComputationEvidenceChainValid(chain, preview, limits) {
      issuanceLimits(limits, 'Effectful computation evidence chain');
      const ownedPreview = computationPreviewTokens.get(preview);
      if (ownedPreview === undefined || !Array.isArray(chain?.definitions) ||
          !Array.isArray(chain.artifacts)) {
        throw new TypeError('Invalid Effectful computation evidence chain');
      }
      const prepared = recoveredEffectCaptures.get(chain.capturedRun);
      if (prepared !== undefined) return moon.clientProgramRecoveredEffectCapturedRunChainValid(
        token(chain.runDefinition), token(chain.invocation), chain.definitions.map(token), chain.artifacts.map(token),
        token(chain.manifest), token(chain.computationReceipt), token(chain.capturedRun), prepared, ownedPreview,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth);
      return moon.strategyEffectfulComputationEvidenceChainValid(
        token(chain.runDefinition), token(chain.invocation),
        chain.definitions.map(token), chain.artifacts.map(token),
        token(chain.manifest), token(chain.computationReceipt),
        token(chain.capturedRun), ownedPreview,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth,
      );
    },
    capturedEffectSourceRecoveryInventoryValid(preview, sources) {
      const ownedPreview = computationPreviewTokens.get(preview);
      if (ownedPreview === undefined || !Array.isArray(sources) ||
          sources.some(value => !Number.isSafeInteger(value?.memberIndex))) {
        throw new TypeError('Invalid recovered Effect source inventory');
      }
      return moon.strategyCapturedEffectSourceRecoveryInventoryValid(
        ownedPreview, sources.map(value => value.memberIndex),
        sources.map(value => token(value.artifact)),
      );
    },
    hasPreparedCapturedEffectRun(capturedRun) {
      token(capturedRun);
      return recoveredEffectCaptures.has(capturedRun);
    },
    prepareCapturedEffectSourceInventory(chain, preview, sources, storeAuthorityCid, limits) {
      token(chain.capturedRun);
      const prepared = recoveredEffectCaptures.get(chain.capturedRun);
      if (prepared === undefined) return undefined;
      issuanceLimits(limits, 'prepared recovered Effect source inventory');
      const ownedPreview = computationPreviewTokens.get(preview);
      if (ownedPreview === undefined || !Array.isArray(sources) ||
          sources.some(value => !Number.isSafeInteger(value?.memberIndex)) ||
          typeof storeAuthorityCid !== 'string') {
        throw new TypeError('Invalid prepared Effect source inventory');
      }
      // Existing decoded Read backing precedes these transient index vectors
      // and returned original Source handles. No second persistent cache or
      // replacement owner is created; the complete checked context is reused.
      const originals = checked(moon.clientProgramRecoveredEffectCapturedRunSources(
        token(chain.runDefinition), token(chain.invocation), chain.definitions.map(token),
        chain.artifacts.map(token), token(chain.manifest), token(chain.computationReceipt),
        token(chain.capturedRun), prepared, ownedPreview,
        sources.map(value => value.memberIndex), sources.map(value => token(value.artifact)),
        storeAuthorityCid, limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      return Object.freeze(originals.map(inspectEffectSource));
    },
    capturedEffectSourceInventoryFromCaptureValid(preview, sources,
      invocation, capturedRun, storeAuthorityCid, limits) {
      issuanceLimits(limits, 'recovered Effect source inventory');
      const ownedPreview = computationPreviewTokens.get(preview);
      if (ownedPreview === undefined || !Array.isArray(sources) ||
          sources.some(value => !Number.isSafeInteger(value?.memberIndex)) ||
          typeof storeAuthorityCid !== 'string') {
        throw new TypeError('Invalid recovered Effect source inventory');
      }
      return moon.strategyCapturedEffectSourceInventoryFromCaptureValid(
        ownedPreview, sources.map(value => value.memberIndex),
        sources.map(value => token(value.artifact)), token(invocation),
        token(capturedRun), storeAuthorityCid, limits.maxWireBytes,
        limits.maxNodes, limits.maxDepth);
    },
    capturedEffectSourceInventoryFromResultsValid(preview, sources, limits) {
      issuanceLimits(limits, 'captured Table source inventory');
      const ownedPreview = computationPreviewTokens.get(preview);
      if (ownedPreview === undefined || !Array.isArray(sources)) {
        throw new TypeError('Invalid captured Table source inventory');
      }
      const results = sources.map(value => {
        const owned = localEffectArtifactTokens.get(value.result);
        if (owned === undefined || !Number.isSafeInteger(value.memberIndex)) {
          throw new TypeError('Foreign captured Table source Result');
        }
        return checked(moon.strategyPublicationAdmit('result_artifact',
          moon.clientProgramLocalEffectResultArtifactJson(owned),
          limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      });
      return moon.strategyCapturedEffectSourceInventoryFromResultsValid(ownedPreview,
        sources.map(value => value.memberIndex),
        sources.map(value => token(value.artifact)), results);
    },
    capturedEffectSourceInventoryFromArtifactsValid(preview, sources, limits) {
      issuanceLimits(limits, 'captured Relation source inventory');
      const ownedPreview = computationPreviewTokens.get(preview);
      if (ownedPreview === undefined || !Array.isArray(sources)) {
        throw new TypeError('Invalid captured Relation source inventory');
      }
      const relations = sources.map(value => {
        const owned = localEffectArtifactTokens.get(value.result);
        if (owned === undefined || !Number.isSafeInteger(value.memberIndex)) {
          throw new TypeError('Foreign captured Relation source Artifact');
        }
        return checked(moon.strategyPublicationAdmit('result_artifact',
          moon.clientProgramLocalEffectResultArtifactJson(owned),
          limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      });
      return moon.strategyCapturedEffectSourceInventoryFromArtifactsValid(ownedPreview,
        sources.map(value => value.memberIndex),
        sources.map(value => token(value.artifact)), relations);
    },
    localEffectResultPayloadBinding(artifact, runDefinition) {
      const owned = localEffectArtifactTokens.get(artifact);
      if (owned === undefined) {
        throw new TypeError('Foreign local Effect Result artifact');
      }
      const binding = checked(moon.clientProgramLocalEffectResultPayloadBinding(
        owned, token(runDefinition)));
      return Object.freeze({artifactCid: artifact.identity,
        physicalCid: runtimeField(binding, 0), byteCount: runtimeField(binding, 1)});
    },
    // Schema material from the authenticated capture, not current configuration.
    capturedEffectDependencySchemas(capturedRun) {
      const prepared = recoveredEffectCaptures.get(capturedRun);
      if (prepared !== undefined) return Object.freeze(moon.clientProgramRecoveredEffectCapturedRunSchemas(prepared)
        .map(pair => Object.freeze({cid:runtimeField(pair,0), wire:runtimeField(pair,1)})));
      const captured = inspect(token(capturedRun));
      const inventory = JSON.parse(captured.wire).effect_context?.effect_dependency_inventory;
      if (captured.name !== 'captured_run' || !Array.isArray(inventory) || inventory.length > 4096) {
        throw new TypeError('InvalidEffectDependencySchemas');
      }
      // Original canonical bodies admitted by the CapturedRun/dependency Owner,
      // never reconstructed from current Catalogs or observed row values.
      return Object.freeze(inventory.filter(entry => entry.kind === 'relation_schema').map(entry => {
        if (typeof entry.cid !== 'string' || !/^sha256:[0-9a-f]{64}$/u.test(entry.cid) ||
            entry.body === null || typeof entry.body !== 'object' || Array.isArray(entry.body)) {
          throw new TypeError('InvalidEffectDependencySchemas');
        }
        return Object.freeze({cid: entry.cid, wire: JSON.stringify(entry.body)});
      }));
    },
    // Physical custody metadata is not semantic identity or permission.
    // Callers first validate the Captured Run chain; issuance binds receipts.
    capturedEffectDependencyPayloadBindings(capturedRun, bindings) {
      const captured = inspect(token(capturedRun));
      const prepared = recoveredEffectCaptures.get(capturedRun);
      const inventory = prepared === undefined ? JSON.parse(captured.wire).effect_context?.effect_dependency_inventory : undefined;
      if (captured.name !== 'captured_run' || (prepared === undefined && !Array.isArray(inventory)) ||
          !Array.isArray(bindings) || (prepared === undefined && bindings.length > 4096)) {
        throw new TypeError('InvalidEffectDependencyPayloadBindings');
      }
      const required = new Set(prepared === undefined ? inventory.filter(entry =>
        entry.kind === 'result_artifact' || entry.kind === 'table_input_artifact').map(entry => entry.cid)
        : moon.clientProgramRecoveredEffectCapturedRunPayloads(prepared));
      const seen = new Set();
      const owned = bindings.map(binding => {
        if (binding === null || typeof binding !== 'object' ||
            Object.keys(binding).sort().join(',') !==
              'artifact_cid,byte_count,physical_cid' ||
            !required.has(binding.artifact_cid) ||
            seen.has(binding.artifact_cid) ||
            typeof binding.physical_cid !== 'string' ||
            !/^sha256:[0-9a-f]{64}$/u.test(binding.physical_cid) ||
            !Number.isSafeInteger(binding.byte_count) || binding.byte_count < 0) {
          throw new TypeError('InvalidEffectDependencyPayloadBindings');
        }
        seen.add(binding.artifact_cid);
        return Object.freeze({...binding});
      });
      if (seen.size !== required.size) {
        throw new TypeError('IncompleteEffectDependencyPayloadBindings');
      }
      return Object.freeze(owned);
    },
    async issueEffectfulCapturedRun(chain, evidence, preview, plans, limits, signal) {
      limits = captureContractLimits(limits, 'Effectful Captured Run');
      if (chain === null || typeof chain !== 'object' ||
          evidence === null || typeof evidence !== 'object' ||
          !Array.isArray(chain.definitions) ||
          !Array.isArray(chain.artifacts) ||
          !Array.isArray(evidence.snapshots) ||
          !Array.isArray(evidence.effectSources) ||
          !Array.isArray(evidence.localEffectSources) ||
          !Array.isArray(evidence.pendingSourceStateAdvances) ||
          !Array.isArray(evidence.modelEvidence) ||
          (evidence.dependencyInventoryWire !== undefined &&
            typeof evidence.dependencyInventoryWire !== 'string') ||
          !Array.isArray(plans) ||
          plans.some(value => !value || typeof value.name !== 'string' ||
            typeof value.wire !== 'string')) {
        throw new TypeError('Invalid Effectful Captured Run request');
      }
      const ownedPreview = computationPreviewTokens.get(preview);
      if (ownedPreview === undefined) {
        throw new TypeError('Foreign Effect computation Preview');
      }
      signal?.throwIfAborted();
      const original = evidence.dependencyConstruction === undefined ? undefined
        : installedEffectDependencyOriginal(evidence.dependencyConstruction, moon);
      if (original !== undefined) {
        const slots = chain.definitions.length + chain.artifacts.length + evidence.snapshots.length +
          evidence.effectSources.length + evidence.localEffectSources.length +
          evidence.pendingSourceStateAdvances.length + evidence.modelEvidence.length +
          (evidence.contentGenerations?.length ?? 0) + 2 * plans.length;
        if (!Number.isSafeInteger(slots) || slots > 2147483647) throw new RangeError('EffectCaptureInventoryLimit');
        checked(moon.clientProgramInstalledEffectDependencyCaptureReserve(original.parent, original.prepared,
          original.request, original.plan, token(chain.runDefinition), token(chain.invocation), slots));
        original.current();
      }
      const preparation = original === undefined ? checked(moon.strategyBeginEffectfulCapturedRun(
        token(chain.runDefinition), token(chain.invocation),
        chain.definitions.map(token), chain.artifacts.map(token),
        token(chain.manifest), token(chain.receipt),
        evidence.snapshots.map(snapshotToken),
        evidence.effectSources.map(effectSourceToken),
        evidence.localEffectSources.map(localEffectSourceToken),
        evidence.pendingSourceStateAdvances.map(sourceAdvanceToken),
        evidenceToken(evidence.authoringContext),
        evidence.modelEvidence.map(evidenceToken), ownedPreview,
        plans.map(value => value.name), plans.map(value => value.wire),
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth,
        evidence.dependencyInventoryWire,
        moon.strategyPublicationEvidenceWorkspace(limits.maxNodes),
        contentCaptures(evidence.contentGenerations),
      )) : checked(moon.clientProgramInstalledEffectDependencyCaptureBegin(
        original.parent, original.prepared, original.request, original.plan,
        token(chain.runDefinition), token(chain.invocation), chain.definitions.map(token),
        chain.artifacts.map(token), token(chain.manifest), token(chain.receipt),
        evidence.snapshots.map(snapshotToken), evidence.effectSources.map(effectSourceToken),
        evidence.localEffectSources.map(localEffectSourceToken),
        evidence.pendingSourceStateAdvances.map(sourceAdvanceToken), evidenceToken(evidence.authoringContext),
        evidence.modelEvidence.map(evidenceToken), ownedPreview,
        plans.map(value => value.name), plans.map(value => value.wire), evidence.dependencyInventoryWire,
        contentCaptures(evidence.contentGenerations), limits.maxWireBytes, limits.maxNodes, limits.maxDepth,
      ));
      original?.current();
      const value = await finishCapturedPreparation(preparation, signal, false, original);
      original?.current();
      return value;
    },
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
    effectSetReceiptRunDisposition(preview, receipts, limits) {
      issuanceLimits(limits, 'Effect Set Run disposition');
      const ownedPreview = computationPreviewTokens.get(preview);
      if (ownedPreview === undefined ||
          typeof receipts?.setWire !== 'string' ||
          !Array.isArray(receipts.memberWires) ||
          receipts.memberWires.some(wire => typeof wire !== 'string')) {
        throw new TypeError('Invalid Effect Set Run disposition');
      }
      return checked(moon.strategyEffectSetReceiptRunDisposition(
        ownedPreview, receipts.setWire, receipts.memberWires,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth,
      ));
    },
    // The public state of a Run whose complete admitted Effect Set has
    // unknown outcomes: `needs_reconciliation` naming exactly those Effects.
    effectReconciliationRunState(preview, receipts, {runId, updatedAt,
      resultNames}, limits) {
      issuanceLimits(limits, 'Effect reconciliation Run state');
      const ownedPreview = computationPreviewTokens.get(preview);
      if (ownedPreview === undefined ||
          typeof receipts?.setWire !== 'string' ||
          !Array.isArray(receipts.memberWires) ||
          receipts.memberWires.some(wire => typeof wire !== 'string') ||
          !Array.isArray(resultNames) ||
          resultNames.some(name => typeof name !== 'string')) {
        throw new TypeError('Invalid Effect reconciliation Run state');
      }
      return checked(moon.strategyEffectReconciliationRunState(
        ownedPreview, receipts.setWire, receipts.memberWires, runId,
        updatedAt, resultNames, limits.maxWireBytes, limits.maxNodes,
        limits.maxDepth,
      ));
    },
    recordTransition(previous, next, uncommittedConfirmed) {
      return moon.strategyPublicationRecordTransition(
        previous === undefined ? undefined : token(previous),
        token(next),
        uncommittedConfirmed,
      );
    },
    recordAllowsCommit(record) {
      return moon.strategyPublicationRecordAllowsCommit(token(record));
    },
    publicationAttemptAction(record, activeChecked, indexIssued) {
      return publicationAction('attempt', moon.strategyPublicationAttemptAction(
        record === undefined ? undefined : token(record),
        activeChecked,
        indexIssued,
      ));
    },
    publicationSetupAction(
      existingChecked,
      existingFound,
      existingEvidenceValidated,
      existingFinalized,
      initialActiveChecked,
      contractsPersisted,
      attemptCreated,
    ) {
      return publicationAction('setup', moon.strategyPublicationSetupAction(
        existingChecked,
        existingFound,
        existingEvidenceValidated,
        existingFinalized,
        initialActiveChecked,
        contractsPersisted,
        attemptCreated,
      ));
    },
    publicationCancellationAction(record) {
      return publicationAction('cancellation',
        moon.strategyPublicationCancellationAction(
          record === undefined ? undefined : token(record),
        ));
    },
    committedPublicationFinalizationAction(record) {
      return publicationAction('finalization',
        moon.strategyCommittedPublicationFinalizationAction(
          record === undefined ? undefined : token(record),
        ));
    },
    supersededPublicationFinalizationAction(record) {
      return publicationAction('finalization',
        moon.strategySupersededPublicationFinalizationAction(
          record === undefined ? undefined : token(record),
        ));
    },
    publicationCommitFailureAction(
      reconciliationAttempted,
      reconciliationFailed,
      committedFound,
      unknownAppendAttempted,
    ) {
      return publicationAction('commitFailure',
        moon.strategyPublicationCommitFailureAction(
          reconciliationAttempted,
          reconciliationFailed,
          committedFound,
          unknownAppendAttempted,
        ));
    },
    publicationUnknownRetryAction(
      reconciliationResolved,
      upstreamPending,
      upstreamRetryAvailable,
      upstreamRetryAttempted,
    ) {
      return publicationAction('unknownRetry',
        moon.strategyPublicationUnknownRetryAction(
          reconciliationResolved,
          upstreamPending,
          upstreamRetryAvailable,
          upstreamRetryAttempted,
        ));
    },
    existingDeliveryAttemptAction(record) {
      return publicationAction('existingDelivery',
        moon.strategyExistingDeliveryAttemptAction(
          record === undefined ? undefined : token(record),
        ));
    },
    beginResultAccessProgress() {
      return moon.strategyBeginResultAccessProgress();
    },
    resultAccessProgressAction(progress) {
      return publicationAction('resultAccess',
        moon.strategyResultAccessProgressAction(progress));
    },
    recordResultAccessRequestAuthorization(progress, authorized) {
      if (!moon.strategyRecordResultAccessRequestAuthorization(
        progress, authorized,
      )) throw new TypeError('Invalid Result access progression');
    },
    recordResultAccessResolution(progress, resolved) {
      if (!moon.strategyRecordResultAccessResolution(progress, resolved)) {
        throw new TypeError('Invalid Result access progression');
      }
    },
    recordResultAccessInitialAvailability(progress, available) {
      if (!moon.strategyRecordResultAccessInitialAvailability(
        progress, available,
      )) throw new TypeError('Invalid Result access progression');
    },
    recordResultAccessReadAdmission(progress, admitted) {
      if (!moon.strategyRecordResultAccessReadAdmission(progress, admitted)) {
        throw new TypeError('Invalid Result access progression');
      }
    },
    recordResultAccessGrant(progress, issued) {
      if (!moon.strategyRecordResultAccessGrant(progress, issued)) {
        throw new TypeError('Invalid Result access progression');
      }
    },
    deliveryFailureTerminalAction(cancellationObserved) {
      return publicationAction('failureTerminal',
        moon.strategyDeliveryFailureTerminalAction(cancellationObserved));
    },
    deliveryRecordRetryAction(nextRecord, recordCount) {
      return publicationAction('recordRetry',
        moon.strategyDeliveryRecordRetryAction(nextRecord, recordCount));
    },
    publicationPreparedReleaseAction(
      currentIndex,
      ownerCount,
      statusChecked,
      pending,
      releaseAttempted,
    ) {
      return publicationAction('preparedRelease',
        moon.strategyPublicationPreparedReleaseAction(
          currentIndex,
          ownerCount,
          statusChecked,
          pending,
          releaseAttempted,
        ));
    },
    publicationCleanupOwnerAction(
      currentIndex,
      ownerCount,
      statusChecked,
      pending,
      retryAvailable,
      retryAttempted,
    ) {
      return publicationAction('cleanupOwner',
        moon.strategyPublicationCleanupOwnerAction(
          currentIndex,
          ownerCount,
          statusChecked,
          pending,
          retryAvailable,
          retryAttempted,
        ));
    },
    runChainValid(runDefinition, invocation, definitions, artifacts,
      manifest, limits) {
      return moon.strategyRunPublicationChainValid(
        token(runDefinition),
        token(invocation),
        definitions.map(token),
        artifacts.map(token),
        token(manifest),
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      );
    },
    issueResultManifest(runDefinition, invocation, definitions, artifacts,
      limits) {
      limits = captureContractLimits(limits, 'Result Manifest');
      return inspect(checked(moon.strategyIssueResultManifest(
        token(runDefinition),
        token(invocation),
        definitions.map(token),
        artifacts.map(token),
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      )), limits);
    },
    issueDurableResultBinding(chain, physical, limits) {
      limits = captureContractLimits(limits, 'durable Result binding');
      if (chain === null || typeof chain !== 'object' ||
          physical === null || typeof physical !== 'object') {
        throw new TypeError('Invalid durable Result binding request');
      }
      return inspect(checked(moon.strategyIssueDurableResultBinding(
        token(chain.runDefinition),
        token(chain.definition),
        token(chain.invocation),
        token(chain.artifact),
        token(chain.ordering),
        token(chain.retention),
        physical.codecContractCid,
        physical.resultFields,
        physical.resultSchemaWire,
        physical.materialGenerationCid,
        physical.storeAuthorityCid,
        physical.rowCount,
        physical.byteCount,
        physical.physicalSha256,
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      )), limits);
    },
    resultPublicationContractByteBounds(inputRelationCids, maxSchemaBytes, limits) {
      limits = captureContractLimits(limits, 'Result publication capacity');
      if (!Array.isArray(inputRelationCids) ||
          !inputRelationCids.every(value => typeof value === 'string' &&
            /^sha256:[0-9a-f]{64}$/u.test(value)) ||
          !Number.isSafeInteger(maxSchemaBytes) || maxSchemaBytes < 0) {
        throw new TypeError('Invalid Result publication capacity');
      }
      const values = moon.strategyResultPublicationContractByteBounds(
        inputRelationCids, maxSchemaBytes, limits.maxWireBytes,
        limits.maxNodes, limits.maxDepth,
      );
      if (!Array.isArray(values) || values.length !== 4 ||
          !values.every(value => Number.isSafeInteger(value) && value >= 0 &&
            value <= limits.maxWireBytes)) {
        throw new TypeError('Invalid Result publication capacity projection');
      }
      return Object.freeze([...values]);
    },
    ordinaryPublicationReceiptByteBound(plan, request, limits) {
      limits = captureContractLimits(limits, 'Publication receipt capacity');
      const provenance = plan.receiptEvidence;
      const value = moon.strategyOrdinaryPublicationReceiptByteBound(
        admissionToken(plan.admission), token(request), token(plan.invocation),
        evidenceToken(plan.observation), evidenceToken(plan.normalizationJournal),
        provenance.bindings.map(binding => binding.name),
        provenance.bindings.map(binding => binding.sha256),
        provenance.sourceEvidence.map(evidenceToken),
        provenance.modelEvidence.map(evidenceToken), provenance.barrierAttemptReceiptCids,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth,
      );
      if (!Number.isSafeInteger(value) || value < 0 || value > limits.maxWireBytes) {
        throw new TypeError('Invalid publication receipt capacity projection');
      }
      return value;
    },
    ordinaryPublicationFrontierByteBounds(request, resultCount, limits) {
      limits = captureContractLimits(limits, 'Publication frontier capacity');
      if (!Number.isSafeInteger(resultCount) || resultCount < 0 || resultCount > 2147483647) {
        throw new TypeError('Invalid publication frontier inventory');
      }
      const values = moon.strategyOrdinaryPublicationFrontierByteBounds(
        token(request), resultCount, limits.maxWireBytes, limits.maxNodes, limits.maxDepth,
      );
      if (!Array.isArray(values) || values.length !== 6 ||
          !values.every(value => Number.isSafeInteger(value) && value >= 0 &&
            value <= limits.maxWireBytes)) {
        throw new TypeError('Invalid publication frontier capacity projection');
      }
      const manifest = moon.strategyOrdinaryPublicationManifestByteBound(
        token(request), limits.maxWireBytes, limits.maxNodes, limits.maxDepth,
      );
      if (!Number.isSafeInteger(manifest) || manifest < 0 || manifest > limits.maxWireBytes) {
        throw new TypeError('Invalid publication manifest capacity projection');
      }
      return Object.freeze({
        manifest,
        index: values[0],
        current: Object.freeze({preparing: values[1], committing: values[2],
          publicationUnknown: values[3], terminal: values[4]}),
        possibleForeignWinnerTerminal: values[5],
      });
    },
    issuePublicationRequest(runDefinition, definitions, intent, limits) {
      limits = captureContractLimits(limits, 'Publication Request');
      if (intent === null || typeof intent !== 'object') {
        throw new TypeError('Invalid Publication Request intent');
      }
      return inspect(checked(moon.strategyIssuePublicationRequest(
        token(runDefinition),
        definitions.map(token),
        intent.namespaceId,
        intent.authorityScopeCid,
        intent.publicationPolicyCid,
        intent.publicationTargetCid,
        intent.requestedAt,
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      )), limits);
    },
    issuePublicationAttempt(request, runDefinition, attempt, limits) {
      limits = captureContractLimits(limits, 'Publication Attempt');
      if (attempt === null || typeof attempt !== 'object') {
        throw new TypeError('Invalid Publication Attempt');
      }
      return inspect(checked(moon.strategyIssuePublicationAttempt(
        token(request),
        token(runDefinition),
        attempt.attemptId,
        attempt.fenceCid,
        attempt.externalIdempotencyKey,
        attempt.startedAt,
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      )), limits);
    },
    publicationPreflightValid(
      admission,
      runDefinition,
      invocation,
      definitions,
      retentions,
      evidenceContexts,
      request,
      attempt,
      programDefinitionCid,
    ) {
      return moon.strategyPublicationPreflightValid(
        admissionToken(admission),
        token(runDefinition),
        token(invocation),
        definitions.map(token),
        retentions.map(token),
        evidenceContexts.map(value => value.computationContractCid),
        evidenceContexts.map(value => value.inputRelationCids),
        evidenceContexts.map(value => value.scopeCid),
        evidenceContexts.map(value => value.effectiveDataPolicyCid),
        evidenceContexts.map(value => value.authorityScopeCid),
        token(request),
        token(attempt),
        programDefinitionCid,
      );
    },
    issuePublicIndexEntry(chain, committedAt, limits) {
      limits = captureContractLimits(limits, 'Public Index Entry');
      if (chain === null || typeof chain !== 'object' ||
          !Array.isArray(chain.durableBindings)) {
        throw new TypeError('Invalid publication chain');
      }
      return inspect(checked(moon.strategyIssuePublicIndexEntry(
        token(chain.runDefinition),
        token(chain.invocation),
        token(chain.manifest),
        token(chain.receipt),
        token(chain.capturedRun),
        chain.durableBindings.map(token),
        token(chain.request),
        token(chain.attempt),
        committedAt,
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      )), limits);
    },
    publicIndexSameCommittedContent(committed, candidate) {
      return moon.strategyPublicIndexSameCommittedContent(
        token(committed), token(candidate));
    },
    issuePublicationRecord(attempt, previous, update, limits) {
      limits = captureContractLimits(limits, 'Publication Record');
      if (update === null || typeof update !== 'object') {
        throw new TypeError('Invalid Publication Record update');
      }
      return inspect(checked(moon.strategyIssuePublicationRecord(
        token(attempt),
        previous === undefined ? undefined : token(previous),
        update.state,
        update.observedAt,
        update.publicIndexEntry === undefined
          ? undefined : token(update.publicIndexEntry),
        update.failureCid,
        update.cleanupOwnerCids,
        update.uncommittedConfirmed,
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      )), limits);
    },
    async effectFreeChainValid(runDefinition, invocation, definitions, artifacts,
      manifest, receipt, capturedRun, limits, signal) {
      issuanceLimits(limits, 'Effect-free chain validation');
      signal?.throwIfAborted();
      const original = capturedComputationPreparations.get(capturedRun);
      if (original?.program !== undefined) {
        const validation = checked(moon.clientProgramPrepareChainValidation(
          original.program, token(runDefinition), token(invocation),
          definitions.map(token), artifacts.map(token), token(manifest),
          token(receipt), token(capturedRun),
        ));
        return finishProgramValidation(validation, signal);
      }
      if (original !== undefined) limits = capturedPreparationLimits(original);
      const args = [
        token(runDefinition),
        token(invocation),
        definitions.map(token),
        artifacts.map(token),
        token(manifest),
        token(receipt),
        token(capturedRun),
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
        moon.strategyPublicationEvidenceWorkspace(limits.maxNodes),
      ];
      const preparation = original === undefined
        ? moon.strategyBeginEffectFreeChainCheck(...args)
        : moon.strategyBeginEffectFreeChainCheckRetained(original, ...args);
      return finishPublicationValidation(preparation,
        moon.strategyEffectFreeChainCheckAdvance,
        moon.strategyEffectFreeChainCheckFinish,
        moon.strategyEffectFreeChainCheckCancel, signal);
    },
    // The selected Store read owns this full-original validation operation.
    // No preparation owner is reconstructed after reopen and no metadata
    // ceiling is reused for a larger independently admitted contract.
    async effectFreeStoredCommitValid(runDefinition, invocation, definitions, artifacts,
      derivations, orderings, retentions, durableBindings, manifest, receipt,
      capturedRun, request, attempt, indexEntry, requireCurrent) {
      if (typeof requireCurrent !== 'function') {
        throw new TypeError('Store publication validation owner unavailable');
      }
      requireCurrent();
      const retained = capturedComputationPreparations.get(capturedRun);
      if (retained?.program !== undefined) {
        const validation = checked(moon.clientProgramPrepareCommitValidation(
          retained.program, token(runDefinition), token(invocation),
          definitions.map(token), artifacts.map(token), derivations.map(token),
          orderings.map(token), retentions.map(token), durableBindings.map(token),
          token(manifest), token(receipt), token(capturedRun), token(request),
          token(attempt), token(indexEntry),
        ));
        return finishProgramValidation(validation, undefined, requireCurrent);
      }
      const validation = checked(moon.clientStoreBeginOriginalCommitValidation(
        token(runDefinition), token(invocation), definitions.map(token),
        artifacts.map(token), derivations.map(token), orderings.map(token),
        retentions.map(token), durableBindings.map(token), token(manifest),
        token(receipt), token(capturedRun), token(request), token(attempt),
        token(indexEntry),
      ));
      return finishStoreValidation(validation, requireCurrent);
    },
    async effectFreeCommitValid(runDefinition, invocation, definitions, artifacts,
      derivations, orderings, retentions, durableBindings, manifest, receipt,
      capturedRun, request, attempt, indexEntry, limits) {
      issuanceLimits(limits, 'Effect-free commit validation');
      const original = capturedComputationPreparations.get(capturedRun);
      if (original?.program !== undefined) {
        const validation = checked(moon.clientProgramPrepareCommitValidation(
          original.program, token(runDefinition), token(invocation),
          definitions.map(token), artifacts.map(token), derivations.map(token),
          orderings.map(token), retentions.map(token), durableBindings.map(token),
          token(manifest), token(receipt), token(capturedRun), token(request),
          token(attempt), token(indexEntry),
        ));
        // Commit reconciliation remains authoritative after cancellation.
        return finishProgramValidation(validation);
      }
      if (original !== undefined) limits = capturedPreparationLimits(original);
      const args = [
        token(runDefinition),
        token(invocation),
        definitions.map(token),
        artifacts.map(token),
        derivations.map(token),
        orderings.map(token),
        retentions.map(token),
        durableBindings.map(token),
        token(manifest),
        token(receipt),
        token(capturedRun),
        token(request),
        token(attempt),
        token(indexEntry),
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
        moon.strategyPublicationEvidenceWorkspace(limits.maxNodes),
      ];
      const preparation = original === undefined
        ? moon.strategyBeginEffectFreeCommitCheck(...args)
        : moon.strategyBeginEffectFreeCommitCheckRetained(original, ...args);
      // A committed outcome is authoritative even after request cancellation.
      return finishPublicationValidation(preparation,
        moon.strategyEffectFreeCommitCheckAdvance,
        moon.strategyEffectFreeCommitCheckFinish,
        moon.strategyEffectFreeCommitCheckCancel);
    },
    effectfulCommitValid(chain, preview, receipts, request, attempt,
      indexEntry, limits) {
      issuanceLimits(limits, 'Effectful publication commit');
      if (chain === null || typeof chain !== 'object' ||
          !['definitions', 'artifacts', 'derivations', 'orderings',
            'retentions', 'durableBindings'].every(name =>
            Array.isArray(chain[name])) ||
          receipts === null || typeof receipts !== 'object' ||
          typeof receipts.setWire !== 'string' ||
          typeof receipts.finalWire !== 'string' ||
          !Array.isArray(receipts.memberWires) ||
          receipts.memberWires.some(wire => typeof wire !== 'string')) {
        throw new TypeError('Invalid Effectful publication commit');
      }
      const ownedPreview = computationPreviewTokens.get(preview);
      if (ownedPreview === undefined) {
        throw new TypeError('Foreign Effect computation Preview');
      }
      const prepared = recoveredEffectCaptures.get(chain.capturedRun);
      return prepared === undefined ? moon.strategyEffectfulPublicationCommitValid(
        token(chain.runDefinition), token(chain.invocation),
        chain.definitions.map(token), chain.artifacts.map(token),
        chain.derivations.map(token), chain.orderings.map(token),
        chain.retentions.map(token), chain.durableBindings.map(token),
        token(chain.manifest), token(chain.computationReceipt),
        token(chain.capturedRun), ownedPreview, receipts.setWire,
        receipts.memberWires, receipts.finalWire, token(request),
        token(attempt), token(indexEntry), limits.maxWireBytes,
        limits.maxNodes, limits.maxDepth,
      ) : moon.clientProgramPreparedEffectfulPublicationCommitValid(
        token(chain.runDefinition), token(chain.invocation),
        chain.definitions.map(token), chain.artifacts.map(token),
        chain.derivations.map(token), chain.orderings.map(token),
        chain.retentions.map(token), chain.durableBindings.map(token),
        token(chain.manifest), token(chain.computationReceipt),
        token(chain.capturedRun), prepared, ownedPreview, receipts.setWire,
        receipts.memberWires, receipts.finalWire, token(request),
        token(attempt), token(indexEntry), limits.maxWireBytes,
        limits.maxNodes, limits.maxDepth,
      );
    },
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
    deliveryTransition(previous, next) {
      return moon.strategyDeliveryRecordTransition(
        previous === undefined ? undefined : token(previous),
        token(next),
      );
    },
    deliverySuccessValid(attempt, receipt, record) {
      return moon.strategyDeliverySuccessValid(
        token(attempt), token(receipt), token(record),
      );
    },
    resultSerializationContractCid(format, limits) {
      issuanceLimits(limits, 'Result serialization');
      return checked(moon.strategyResultSerializationContractCid(
        format,
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      ));
    },
    describeCommittedResult(index, manifest, resultName, bindings,
      definition, schemaWire, format, limits) {
      issuanceLimits(limits, 'Result description');
      return JSON.parse(checked(moon.strategyDescribeCommittedResult(
        token(index), token(manifest), resultName, bindings.map(token),
        token(definition), schemaWire, format, limits.maxWireBytes,
        limits.maxNodes, limits.maxDepth)));
    },
    issueManifestReadGrant(index, manifest, grant, limits) {
      limits = captureContractLimits(limits, 'Manifest read grant');
      if (grant === null || typeof grant !== 'object') {
        throw new TypeError('Invalid Manifest read grant');
      }
      return inspect(checked(moon.strategyIssueManifestReadGrant(
        token(index),
        token(manifest),
        grant.principalId,
        grant.purpose,
        grant.dataCeilingCid,
        grant.maxBytes,
        grant.maxUses,
        grant.expiresAt,
        grant.authorizationContextCid,
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      )), limits);
    },
    issueResultReadGrant(index, manifest, grant, limits) {
      limits = captureContractLimits(limits, 'Result read grant');
      const bounds = Object.freeze({maxWireBytes: limits.maxWireBytes,
        maxNodes: limits.maxNodes, maxDepth: limits.maxDepth});
      if (grant === null || typeof grant !== 'object' ||
          !Array.isArray(grant.resultNames) ||
          !Array.isArray(grant.formats)) {
        throw new TypeError('Invalid Result read grant');
      }
      const result = inspect(checked(moon.strategyIssueResultReadGrant(
        token(index),
        token(manifest),
        grant.resultNames,
        grant.formats,
        grant.principalId,
        grant.purpose,
        grant.dataCeilingCid,
        grant.maxBytes,
        grant.maxUses,
        grant.expiresAt,
        grant.authorizationContextCid,
        grant.egressAdmissionCid,
        bounds.maxWireBytes,
        bounds.maxNodes,
        bounds.maxDepth,
      )), limits);
      issuedDeliveryGrants.set(result, bounds);
      return result;
    },
    issueDeliveryAttempt(index, manifest, grant, attempt, limits) {
      limits = captureContractLimits(limits, 'Delivery Attempt');
      const bounds = Object.freeze({maxWireBytes: limits.maxWireBytes,
        maxNodes: limits.maxNodes, maxDepth: limits.maxDepth});
      if (attempt === null || typeof attempt !== 'object') {
        throw new TypeError('Invalid Delivery Attempt');
      }
      const result = inspect(checked(moon.strategyIssueDeliveryAttempt(
        token(index),
        token(manifest),
        token(grant),
        attempt.resultName,
        attempt.format,
        attempt.attemptId,
        attempt.requestedAt,
        bounds.maxWireBytes,
        bounds.maxNodes,
        bounds.maxDepth,
      )), limits);
      const original = Object.freeze({kind: 'issued-delivery-attempt'});
      const facts = Object.freeze({index, manifest, grant, attempt: result,
        request: Object.freeze({resultName: attempt.resultName, format: attempt.format,
          attemptId: attempt.attemptId, requestedAt: attempt.requestedAt}),
        limits: bounds});
      issuedDeliveryAttempts.set(result, {original,
        index: token(index), manifest: token(manifest), grant: token(grant)});
      originalDeliveryAttempts.set(original, facts);
      return result;
    },
    captureIssuedDeliveryAttempt(attempt, index, manifest, grant, limits) {
      token(attempt);
      const actualIndex = token(index), actualManifest = token(manifest), actualGrant = token(grant);
      const issued = issuedDeliveryAttempts.get(attempt);
      if (issued === undefined) return undefined;
      if (issued.index !== actualIndex || issued.manifest !== actualManifest || issued.grant !== actualGrant) {
        throw new TypeError('PublicationDeliveryOriginalMismatch');
      }
      issuanceLimits(limits, 'Delivery Attempt');
      const grantLimits = issuedDeliveryGrants.get(grant);
      const facts = originalDeliveryAttempts.get(issued.original);
      if (grantLimits === undefined || ['maxWireBytes', 'maxNodes', 'maxDepth'].some(
        key => limits[key] !== grantLimits[key] || limits[key] !== facts.limits[key])) return undefined;
      return issued.original;
    },
    readIssuedDeliveryAttempt(original) {
      const facts = originalDeliveryAttempts.get(original);
      if (facts === undefined) throw new TypeError('ForeignPublicationDeliveryOriginal');
      return facts;
    },
    deliveryResultDefinitionCid(manifest, attempt) {
      return checked(moon.strategyDeliveryResultDefinitionCid(
        token(manifest),
        token(attempt),
      ));
    },
    resultReadRetentionPolicyCid(manifest, resultName) {
      if (typeof resultName !== 'string') {
        throw new TypeError('Invalid Result retention request');
      }
      return checked(moon.strategyResultReadRetentionPolicyCid(
        token(manifest), resultName,
      ));
    },
    manifestResultNames(manifest, limits) {
      issuanceLimits(limits, 'Manifest Result inventory');
      const wire = checked(moon.strategyManifestResultNames(
        token(manifest),
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      ));
      let names;
      try { names = JSON.parse(wire); }
      catch (error) {
        throw new TypeError('Invalid Manifest Result inventory', {cause: error});
      }
      if (!Array.isArray(names)) {
        throw new TypeError('Invalid Manifest Result inventory');
      }
      return Object.freeze([...names]);
    },
    resultReadDefinitionCid(manifest, resultName) {
      if (typeof resultName !== 'string') {
        throw new TypeError('Invalid Result definition request');
      }
      return checked(moon.strategyResultReadDefinitionCid(
        token(manifest), resultName,
      ));
    },
    runDefinitionRunId(runDefinition) {
      return checked(moon.strategyRunDefinitionRunId(token(runDefinition)));
    },
    runDefinitionLifetime(runDefinition, expectedCid) {
      const lifetime = checked(moon.clientLocalCheckpointRunLifetime(
        token(runDefinition), expectedCid));
      return Object.freeze({createdAt: runtimeField(lifetime, 0),
        validUntil: runtimeField(lifetime, 1)});
    },
    // The Common reader checks the exact canonical document and embedded
    // resource CID. This private handle carries data, never restored custody.
    encodeModelOriginalResourceDocument(originWire, stateWire, cutWire, phase, limits) {
      if (![originWire, stateWire, cutWire, phase].every(value => typeof value === 'string')) {
        throw new TypeError('Invalid original Model document inputs');
      }
      issuanceLimits(limits, 'Original Model document');
      const {maxWireBytes, maxNodes, maxDepth} = limits;
      return checked(moon.clientProgramEncodeModelOriginalResourceDocument(
        originWire, stateWire, cutWire, phase, maxWireBytes, maxNodes, maxDepth));
    },
    readModelOriginalResourceDocument(wire, limits) {
      if (typeof wire !== 'string') throw new TypeError('Invalid original Model document');
      issuanceLimits(limits, 'Original Model document');
      const {maxWireBytes, maxNodes, maxDepth} = limits;
      const document = checked(moon.clientProgramReadModelOriginalResourceDocument(
        wire, maxWireBytes, maxNodes, maxDepth));
      const view = Object.freeze({kind: 'model-original-resource-document', wire});
      modelOriginalDocumentTokens.set(view, document);
      return view;
    },
    modelOriginalResourceOriginField(document, field) {
      const original = modelOriginalDocumentTokens.get(document);
      if (original === undefined) throw new TypeError('Foreign original Model document');
      if (typeof field !== 'string') throw new TypeError('Invalid original Model origin field');
      return moon.clientProgramModelOriginalResourceOriginField(original, field);
    },
    runCancellationConfirmed(facts) {
      const names = ['cancellationRequested', 'modelFenceRequired', 'modelFenced',
        'unresolvedModelCalls', 'unresolvedEffects', 'reconciliationRequired',
        'publicationCommitted', 'physicalStopConfirmed', 'cleanupConfirmed',
        'revisionUnchanged'];
      if (names.some(name => typeof facts?.[name] !== 'boolean')) {
        throw new TypeError('Invalid Run cancellation observations');
      }
      return moon.clientRunCancellationConfirmed(...names.map(name => facts[name]));
    },
    resultReadAvailability(manifest, resultName, retention, observedAt) {
      if (typeof resultName !== 'string' || typeof observedAt !== 'string') {
        throw new TypeError('Invalid Result availability request');
      }
      return checked(moon.strategyResultReadAvailability(
        token(manifest), resultName, token(retention), observedAt,
      ));
    },
    resultMetadataRetentionState(retention, observedAt) {
      if (typeof observedAt !== 'string') {
        throw new TypeError('Invalid Result metadata retention request');
      }
      return checked(moon.strategyResultMetadataRetentionState(
        token(retention), observedAt,
      ));
    },
    issueResultRetentionExtension(
      base, availableUntil, admittedAt, limits,
    ) {
      limits = captureContractLimits(limits, 'Result retention extension');
      if (typeof availableUntil !== 'string' ||
          typeof admittedAt !== 'string') {
        throw new TypeError('Invalid Result retention extension');
      }
      return inspect(checked(moon.strategyIssueResultRetentionExtension(
        token(base),
        availableUntil,
        admittedAt,
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      )), limits);
    },
    resultReadExtendedAvailability(
      manifest, resultName, base, extension, observedAt,
    ) {
      if (typeof resultName !== 'string' || typeof observedAt !== 'string') {
        throw new TypeError('Invalid extended Result availability request');
      }
      return checked(moon.strategyResultReadExtendedAvailability(
        token(manifest),
        resultName,
        token(base),
        token(extension),
        observedAt,
      ));
    },
    resultRetentionClockContractCid(retention) {
      return checked(moon.strategyResultRetentionClockContractCid(
        token(retention),
      ));
    },
    trustedClockNotBefore(previous, observedAt) {
      if (previous !== undefined && typeof previous !== 'string' ||
          typeof observedAt !== 'string') {
        return false;
      }
      return moon.strategyTrustedClockNotBefore(previous, observedAt);
    },
    projectCommittedPublicationState(record, index) {
      return checked(moon.strategyPublicationSnapshotState(
        record === undefined ? undefined : token(record),
        token(index),
      ));
    },
    issueSucceededRunState(request, limits) {
      issuanceLimits(limits, 'Succeeded Run state');
      if (request === null || typeof request !== 'object' ||
          typeof request.runId !== 'string' ||
          typeof request.updatedAt !== 'string' ||
          !Array.isArray(request.declaredResults) ||
          !Array.isArray(request.observations)) {
        throw new TypeError('Invalid succeeded Run state');
      }
      const names = [];
      const states = [];
      const reasons = [];
      const observedAt = [];
      for (const observation of request.observations) {
        if (observation === null || typeof observation !== 'object' ||
            typeof observation.name !== 'string' ||
            typeof observation.state !== 'string' ||
            typeof observation.reason !== 'string' ||
            typeof observation.observedAt !== 'string') {
          throw new TypeError('Invalid Result availability observation');
        }
        names.push(observation.name);
        states.push(observation.state);
        reasons.push(observation.reason);
        observedAt.push(observation.observedAt);
      }
      return checked(moon.strategyIssueSucceededRunState(
        request.runId,
        request.updatedAt,
        request.declaredResults,
        names,
        states,
        reasons,
        observedAt,
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      ));
    },
    resultReadGrantAllowsBytes(grant, byteCount) {
      if (!Number.isSafeInteger(byteCount) || byteCount < 0) return false;
      return moon.strategyResultReadGrantAllowsBytes(
        token(grant), byteCount,
      );
    },
    manifestReadGrantAllowsBytes(grant, byteCount) {
      if (!Number.isSafeInteger(byteCount) || byteCount < 0) return false;
      return moon.strategyManifestReadGrantAllowsBytes(
        token(grant), byteCount,
      );
    },
    manifestReadGrantValidAt(grant, observedAt) {
      if (typeof observedAt !== 'string') return false;
      return moon.strategyManifestReadGrantValidAt(
        token(grant), observedAt,
      );
    },
    resultReadGrantValidAt(grant, observedAt) {
      if (typeof observedAt !== 'string') return false;
      return moon.strategyResultReadGrantValidAt(
        token(grant), observedAt,
      );
    },
    issueResultDeliveryReceipt(index, manifest, grant, attempt, delivered,
      limits) {
      limits = captureContractLimits(limits, 'Result delivery receipt');
      if (delivered === null || typeof delivered !== 'object') {
        throw new TypeError('Invalid Result delivery receipt');
      }
      return inspect(checked(moon.strategyIssueResultDeliveryReceipt(
        token(index),
        token(manifest),
        token(grant),
        token(attempt),
        delivered.byteCount,
        delivered.sha256,
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      )), limits);
    },
    issueDeliveryRecord(attempt, previous, update, limits) {
      limits = captureContractLimits(limits, 'Delivery Record');
      if (update === null || typeof update !== 'object' ||
          !Array.isArray(update.cleanupOwnerCids)) {
        throw new TypeError('Invalid Delivery Record');
      }
      return inspect(checked(moon.strategyIssueDeliveryRecord(
        token(attempt),
        previous === undefined ? undefined : token(previous),
        update.state,
        update.confirmedByteCount,
        update.exposure,
        update.possibleUnconfirmedMaxBytes,
        update.deliveredSha256,
        update.receipt === undefined ? undefined : token(update.receipt),
        update.failureCid,
        update.observedAt,
        update.cleanupOwnerCids,
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      )), limits);
    },
    prepareResultDeliverySerializer(format, schemaWire, fields, limits) {
      issuanceLimits(limits, 'Result delivery serializer');
      if (typeof schemaWire !== 'string' || !Array.isArray(fields)) {
        throw new TypeError('Invalid Result delivery serializer');
      }
      return checked(moon.strategyPrepareResultDeliverySerializer(
        format,
        schemaWire,
        fields,
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      ));
    },
    beginResultDelivery(serializer) {
      return checked(moon.strategyBeginResultDelivery(serializer));
    },
    nextResultDeliveryRow(serializer, rowWire) {
      if (typeof rowWire !== 'string') {
        throw new TypeError('Invalid Result delivery row');
      }
      return checked(moon.strategyNextResultDeliveryRow(serializer, rowWire));
    },
    finishResultDelivery(serializer) {
      return checked(moon.strategyFinishResultDelivery(serializer));
    },
    prepareDurableResultRowFrames(limits) {
      if (limits === null || typeof limits !== 'object' ||
          !Number.isSafeInteger(limits.maxBytes) || limits.maxBytes < 0 ||
          !Number.isSafeInteger(limits.maxRows) || limits.maxRows < 0 ||
          !Number.isSafeInteger(limits.maxRowBytes) ||
          limits.maxRowBytes < 1 ||
          !Number.isSafeInteger(limits.maxDepth) || limits.maxDepth < 1 ||
          !Number.isSafeInteger(limits.maxFrameBytes) ||
          limits.maxFrameBytes < 1) {
        throw new TypeError('Invalid durable Result row-frame limits');
      }
      return checked(moon.strategyPrepareDurableResultRowFrames(
        limits.maxBytes,
        limits.maxRows,
        limits.maxRowBytes,
        limits.maxDepth,
        limits.maxFrameBytes,
      ));
    },
    prepareGrowingDurableResultRowFrames(limits) {
      for (const name of ['maxBytes', 'maxRows', 'maxRowBytes', 'maxDepth', 'maxFrameBytes']) {
        if (!Number.isSafeInteger(limits?.[name]) || limits[name] < 0 || limits[name] > 2147483647) {
          throw new TypeError('Invalid growing durable Result row-frame limits');
        }
      }
      return checked(moon.strategyPrepareGrowingDurableResultRowFrames(
        limits.maxBytes, limits.maxRows, limits.maxRowBytes, limits.maxDepth, limits.maxFrameBytes));
    },
    durableResultRowFrameGrowth(frames, bytes) {
      if (!Number.isSafeInteger(bytes) || bytes < 0 || bytes > 2147483647) {
        throw new TypeError('Invalid durable Result row-frame chunk');
      }
      return checked(moon.strategyDurableResultRowFrameGrowth(frames, bytes));
    },
    growDurableResultRowFrameBuffer(frames, bytes) {
      if (!Number.isSafeInteger(bytes) || bytes < 0 || bytes > 2147483647) {
        throw new TypeError('Invalid durable Result row-frame capacity');
      }
      return checked(moon.strategyGrowDurableResultRowFrameBuffer(frames, bytes));
    },
    feedDurableResultRowFrames(frames, chunk) {
      if (!(chunk instanceof Uint8Array)) {
        throw new TypeError('Invalid durable Result row-frame chunk');
      }
      return checked(moon.strategyFeedDurableResultRowFrames(frames, chunk));
    },
    finishDurableResultRowFrames(frames) {
      const summary = checked(
        moon.strategyFinishDurableResultRowFrames(frames),
      );
      if (!Array.isArray(summary) || summary.length !== 2 ||
          summary.some(value => !Number.isSafeInteger(value) || value < 0)) {
        throw new TypeError('Invalid durable Result row-frame summary');
      }
      return Object.freeze({bytes: summary[0], rows: summary[1]});
    },
    cancelDurableResultRowFrames(frames) {
      moon.strategyCancelDurableResultRowFrames(frames);
    },
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
    count: moon.strategyHostCount,
    programDefinitionCid: moon.strategyHostProgramDefinitionCid,
    programHasEffects: moon.strategyHostHasEffects,
    resultInventory(value) {
      const names = moon.strategyHostResultNames(value);
      if (!Array.isArray(names)) throw new TypeError('Invalid Result inventory');
      if (names.length === 0) return Object.freeze([]);
      const inventory = checked(moon.strategyHostPublicationInventory(value));
      const count = moon.strategyHostPublicationInventoryCount(inventory);
      if (count !== names.length) {
        throw new TypeError('Invalid Result inventory projection');
      }
      return Object.freeze(Array.from({length: count}, (_, index) => {
        const definitionContract = publications.admit(
          'result_definition',
          checked(moon.strategyHostPublicationInventoryDefinitionJson(
            inventory, index,
          )),
          {maxWireBytes: 65536, maxNodes: 4096, maxDepth: 64},
        );
        const definition = JSON.parse(definitionContract.wire);
        return Object.freeze({
          name: checked(
            moon.strategyHostPublicationInventoryName(inventory, index),
          ),
          task: checked(
            moon.strategyHostPublicationInventoryTask(inventory, index),
          ),
          definition: Object.freeze(definition),
          definitionContract,
        });
      }));
    },
    next: (value, observeFailure) => {
      const result = moon.strategyHostNext(value);
      try { return checked(result); }
      catch (original) {
        if (runtimeIsError(result) && typeof observeFailure === 'function') {
          try { rememberOriginalDispatchFailure(original, observeFailure(value)); }
          catch { /* Optional observation cannot replace this original failure. */ }
        }
        throw original;
      }
    },
    nextTask: moon.strategyHostNextTask,
    managedProducer: moon.strategyHostManagedProducer,
    managedProducers: moon.strategyHostManagedProducers,
    managedMatches: moon.strategyHostManagedOutputMatches,
    managedCarrierMatches: moon.strategyHostCarrierManagedOutputMatches,
    managedInputMatches: moon.strategyHostManagedInputMatchesMaterial,
    selectManaged: moon.strategyHostSelectManagedRegistration,
    task: moon.strategyHostTask,
    taskCapacity: (value, task) => tuplePair(checked(
      moon.strategyHostTaskCapacity(value, task),
    )),
    registration: moon.strategyHostRegistration,
    completed: moon.strategyHostTaskCompleted,
    finished: moon.strategyHostFinished,
    stop: moon.strategyHostStop,
    requireActivation: moon.strategyHostRequireActivation,
    coverActivation: moon.strategyHostCoverActivation,
    authorizeActivation: moon.strategyHostAuthorizeActivation,
    closeOutputs: moon.strategyHostCloseOutputs,
    output: moon.strategyHostOutput,
    transferBegin: (value, source, transfer, retained, execution) => checked(
      moon.strategyHostTransferBegin(
        value, source, transfer, retained, execution,
      ),
    ),
    transferCharge: (value, transfer, bytes) => checked(
      moon.strategyHostTransferCharge(value, transfer, bytes),
    ),
    transferSettle: (value, transfer, confirmed) => checked(
      moon.strategyHostTransferSettle(value, transfer, confirmed),
    ),
    transferComplete: (value, transfer, retained) => checked(
      moon.strategyHostTransferComplete(value, transfer, retained),
    ),
    transferAbort: (value, transfer, confirmed) => checked(
      moon.strategyHostTransferAbort(value, transfer, confirmed),
    ),
    transferRelease: (value, receipt) => checked(
      moon.strategyHostTransferRelease(value, receipt),
    ),
    transferReceiptMatches: (receipt, transfer, source, bytes, retained) =>
      moon.strategyHostTransferReceiptMatches(
        receipt, transfer, source, bytes, retained,
      ),
    transferPending: moon.strategyHostTransferPending,
    transferProgressBegin: transfer =>
      moon.strategyHostBeginTransferProgress(transfer),
    transferRecordSourceStop: progress =>
      moon.strategyHostRecordTransferSourceStop(progress),
    transferRecordSourceSiteSettlement: progress =>
      moon.strategyHostRecordTransferSourceSiteSettlement(progress),
    transferRecordDestinationCreated: progress =>
      moon.strategyHostRecordTransferDestinationCreated(progress),
    transferRecordDestinationAdmission: (progress, value) =>
      moon.strategyHostRecordTransferDestinationAdmission(
        progress,
        value.distinctMaterial,
        value.distinctGeneration,
        value.rows,
        value.batches,
        value.maxBatchRows,
        value.maxBatchBytes,
        value.transferredBytes,
        value.retainedBytes,
        value.transferLimit,
        value.retentionLimit,
      ),
    transferRecordDestinationHolding: progress =>
      moon.strategyHostRecordTransferDestinationHolding(progress),
    transferRecordDestinationReclaimed: progress =>
      moon.strategyHostRecordTransferDestinationReclaimed(progress),
    transferRecordDestinationSiteSettlement: progress =>
      moon.strategyHostRecordTransferDestinationSiteSettlement(progress),
    transferRecordDestinationCleanupRelease: progress =>
      moon.strategyHostRecordTransferDestinationCleanupRelease(progress),
    transferRecordSiteHoldingRelease: progress =>
      moon.strategyHostRecordTransferSiteHoldingRelease(progress),
    transferCommitAction: progress => checked(
      moon.strategyHostTransferCommitAction(progress),
    ),
    transferCleanupAction: progress => checked(
      moon.strategyHostTransferCleanupAction(progress),
    ),
    transferReceipt: moon.strategyHostTransferReceipt,
    explain: (value, bytes, nodes) => JSON.parse(checked(moon.strategyHostExplain(value, bytes, nodes))),
    preparationUsageIsolated: (value, holder) =>
      typeof moon.clientProgramPreparationBorrowUsageIsolated === 'function' &&
      moon.clientProgramPreparationBorrowUsageIsolated(holder, moon.strategyHostRun(value)) === true,
    usage: value => ledgerUsageSnapshot(moon.strategyHostUsage(value)),
  });
}
