// Physical Host composition for the shared Effect compiler and Run owner.
// The request journal applies MoonBit's atomic start decisions. This adapter
// never schedules Effect apply or interprets a provider's unknown outcome.
import {randomUUID} from 'node:crypto';
import {runtimeCore} from '../host-common/runtime-core.mjs';
export {openClientRequestJournal} from './client-request-journal.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {issuedEffectSetReceiptWires} from
  '../host-common/effect-receipt-custody.mjs';
import {installNodeClientRunStart} from './client-run-start.mjs';
import {originalModelRunWire} from './installed-model-originals.mjs';
import {sampleOriginalQueryTime} from './query-evaluation-clock.mjs';

const limits = Object.freeze({maxWireBytes: 1000000, maxNodes: 100000,
  maxDepth: 100});
const denied = () => Object.assign(new Error('ClientEffectRunDenied'),
  {code: 'ClientEffectRunDenied'});
const expired = ref => Object.assign(new Error('ClientEffectRunExpired'),
  {code: 'ClientEffectRunExpired', ref});
const unsupported = () => Object.assign(new Error('ClientProgramUnsupported'),
  {code: 'ClientProgramUnsupported'});

export function installNodeClientEffectRun({moon,
  publicationControl: control = runtimeCore(moon).publicationControl,
  journal, authorizeRequest, authorizeRunStart, prepareExecution, execute,
  prepareDefinition, assertRequestedStopAvailable, requestIdentityFor,
  inferPlanFor, resultPolicyOriginalFor, validateInstallation, updateTargetOriginals,
  now = () => new Date().toISOString()}) {
  if (typeof moon?.clientProgramEffectCompilationIssueCode !== 'function' ||
      typeof authorizeRequest !== 'function' ||
      (prepareExecution !== undefined &&
        typeof prepareExecution !== 'function') ||
      (prepareDefinition !== undefined && typeof prepareDefinition !== 'function') ||
      (requestIdentityFor !== undefined && typeof requestIdentityFor !== 'function') ||
      (assertRequestedStopAvailable !== undefined &&
        typeof assertRequestedStopAvailable !== 'function') ||
      (inferPlanFor !== undefined && typeof inferPlanFor !== 'function') ||
      (resultPolicyOriginalFor !== undefined &&
        typeof resultPolicyOriginalFor !== 'function') ||
      (validateInstallation !== undefined && typeof validateInstallation !== 'function') ||
      (updateTargetOriginals !== undefined &&
        (typeof moon?.clientProgramEffectTargetSelections !== 'function' ||
         typeof moon?.clientProgramEffectTargetSelectionOriginal !== 'function')) ||
      typeof execute !== 'function' ||
      typeof journal?.reservePhysicalStart !== 'function' ||
      typeof journal?.originalSubmittedIntent !== 'function' ||
      typeof now !== 'function' ||
      typeof moon?.clientProgramEffectRunStartCurrent !== 'function') {
    throw new TypeError('InvalidClientEffectRunInstallation');
  }
  const startRun = installNodeClientRunStart({journal, requestControl: moon,
    publicationControl: control, authorizeRunStart});
  const queryTimeNames = ['clientProgramEffectRequiresQueryTime',
    'clientProgramPrepareEffectQueryTime', 'clientProgramQueryTimeCreatedAt',
    'clientProgramBindEffectQueryTime', 'clientProgramRestoreEffectQueryTimePreparation',
    'clientProgramQueryTimeContext'];
  const queryTimePorts = queryTimeNames.map(name => Object.getOwnPropertyDescriptor(moon, name)?.value);
  const hasQueryTime = queryTimePorts.some(value => value !== undefined);
  if (hasQueryTime && queryTimePorts.some(value => typeof value !== 'function')) {
    throw new TypeError('InvalidClientEffectRunInstallation');
  }
  const queryTimeCall = (index, args) => Reflect.apply(queryTimePorts[index], moon, args);
  const queryTimeRequired = prepared => {
    if (!hasQueryTime) return false;
    const required = checked(queryTimeCall(0, [prepared, limits.maxNodes, limits.maxNodes]));
    if (typeof required !== 'boolean') throw denied();
    return required;
  };
  const restoreQueryTime = (required, prepared, allowed, definition, identity) => {
    if (!required) return {};
    const queryTimePreparation = checked(queryTimeCall(4,
      [prepared, allowed, definition, identity]));
    const queryTime = queryTimeCall(5, [queryTimePreparation]);
    if (queryTime === undefined) throw denied();
    return {queryTimePreparation, queryTime};
  };
  const handles = new WeakMap();
  const compilations = new WeakMap();
  const contentPolicies = new WeakMap();
  const compile = prepared => {
    if (prepared === null || typeof prepared !== 'object') throw denied();
    let compilation = compilations.get(prepared) ?? updateTargetOriginals?.compilationFor(prepared);
    if (compilation !== undefined) {
      validateInstallation?.({prepared, compilation});
      return compilation;
    }
    const infer = inferPlanFor?.(prepared);
    let contentPolicy;
    if (infer === undefined && typeof moon.clientProgramEffectSerializationOccurrences === 'function' &&
        moon.clientProgramEffectAcquisitionCount(prepared) === 0 &&
        moon.clientProgramEffectSerializationOccurrences(prepared).length > 0) {
      contentPolicy = resultPolicyOriginalFor?.(prepared);
    }
    let outcome;
    if (contentPolicy !== undefined) {
      if (contentPolicy?.kind !== 'data_policy' || typeof contentPolicy.cid !== 'string' ||
          typeof contentPolicy.wire !== 'string' ||
          typeof moon.clientProgramCompileLocalEffectsWithSourceFreePolicyBody !== 'function') {
        throw new TypeError('InvalidHostResultDataPolicy');
      }
      outcome = moon.clientProgramCompileLocalEffectsWithSourceFreePolicyBody(prepared,
        contentPolicy.cid, contentPolicy.wire, limits.maxWireBytes, limits.maxNodes, limits.maxDepth);
    } else outcome = infer === undefined
      ? moon.clientProgramCompileLocalEffects(prepared)
      : moon.clientProgramCompileLocalEffectsWithInfer(prepared, infer);
    if (moon.clientProgramEffectCompilationIssueCode(outcome) ===
        'unsupported_program') throw unsupported();
    compilation = checked(outcome);
    if (contentPolicy !== undefined) contentPolicies.set(prepared, contentPolicy);
    validateInstallation?.({prepared, compilation});
    compilations.set(prepared, compilation);
    return compilation;
  };
  const admitEvidence = (name, wire) => checked(
    moon.strategyRunEvidenceAdmit(name, wire, limits.maxWireBytes,
      limits.maxNodes, limits.maxDepth));
  const definitionToken = definition => checked(moon.strategyPublicationAdmit(
    'run_definition', definition.wire, limits.maxWireBytes,
    limits.maxNodes, limits.maxDepth));
  return Object.freeze({
    // A held Run-acceptance Checkpoint must never be opened for a Program
    // this installed Host cannot compile. The exact compiled owner is reused
    // by acceptance; this check neither issues a Run nor starts physical I/O.
    checkSupported(prepared) { compile(prepared); },
    capturePreparedOriginal(prepared) {
      return updateTargetOriginals?.capturePrepared(prepared, compile(prepared));
    },
    // Restore ONLY the existing resource preparation for an already retained
    // Run. No start claim, execution Owner, new Definition, query-time sample
    // or business authorization is issued here. Canceled/unknown Runs still
    // need their same resources for original observation and cleanup.
    async restoreRetainedPreparation({prepared, identity, namespaceId, ref, originalSubmittedIntent}) {
      const retained = journal.resolveDefinition(identity, {namespaceId}, moon, control);
      if (typeof prepareDefinition !== 'function' ||
          retained?.ref.runDefinitionCid !== ref?.runDefinitionCid ||
          retained.runDefinition?.identity !== ref.runDefinitionCid ||
          originalSubmittedIntent?.intent === undefined ||
          typeof originalSubmittedIntent.assertCurrent !== 'function') throw denied();
      const evidence = retained.runAdmissionEvidence;
      if (evidence === undefined || updateTargetOriginals === undefined ||
          !moon.clientSubmittedIntentEffectCompatible(originalSubmittedIntent.intent, prepared)) throw denied();
      originalSubmittedIntent.assertCurrent();
      const compilation = compile(prepared);
      let restored;
      if (evidence.updateTargetRunOriginal !== undefined) {
        restored = updateTargetOriginals.restoreRun(evidence.updateTargetRunOriginal,
          retained.runDefinition, identity, compilation);
      } else {
        if (typeof evidence.effectOriginalRunWire !== 'string') throw denied();
        restored = updateTargetOriginals.restoreEffectMaterials(evidence.effectOriginalRunWire,
          retained.runDefinition, identity, compilation);
      }
      if (restored.prepared !== prepared || restored.compilation !== compilation ||
          moon.strategyRunEvidenceJson(moon.clientProgramAllowedEffectRunPrepared(restored.allowed)) !== evidence.prepared ||
          moon.strategyRunEvidenceJson(moon.clientProgramAllowedEffectRunAuthorization(restored.allowed)) !== evidence.authorization) throw denied();
      const {allowed, definition} = restored;
      const queryTime = restoreQueryTime(queryTimeRequired(prepared), prepared, allowed, definition, identity);
      const modelCompiled = inferPlanFor?.(prepared) === undefined ? undefined :
        control.adoptCheckedClientEffectInferRun(allowed, retained.runDefinition, evidence.resultPolicyOriginal, limits);
      const facts = Object.freeze({ref: retained.ref, prepared, identity, compilation,
        allowed, definition, runDefinition: retained.runDefinition,
        queryTimePreparation: queryTime.queryTimePreparation,
        queryTime: queryTime.queryTime, modelCompiled, resultPolicyOriginal: evidence.resultPolicyOriginal,
        ...restored, originalSubmittedIntent});
      // Reuse the same actual normal constructor/adoption callback, with its
      // original eight-field tuple. Its existing Host bag owns partial failure.
      const selected = prepareDefinition?.(facts);
      const then = selected?.then;
      if (typeof then === 'function') {
        try {await new Promise((resolve, reject) => Reflect.apply(then, selected, [resolve, reject]));}
        catch { /* Join the original invalid borrow before refusing it. */ }
        throw new TypeError('AsyncClientEffectDefinitionPreparation');
      }
      originalSubmittedIntent.assertCurrent();
      restored.assertUpdateSelectionCurrent?.();
      return facts;
    },
    // Record the public state of a started Run whose complete admitted Effect
    // Set has unknown outcomes. The owner names exactly those Effects; the
    // journal keeps the state for status and reconcile in any later process.
    // Nothing is resent, and no answer or Store write relabels the outcome.
    // `issuedSet` must be the exact Set the receipt owner issued for this
    // ledger and Preview, as for publication.
    recordReconciliation(ref, {issuedSet, ledger, preview,
      updatedAt = now()}) {
      const retained = journal.lookupRunDefinition(ref, moon, control);
      if (retained === undefined || retained.resultNames === undefined) {
        throw denied();
      }
      const runId = JSON.parse(retained.runDefinition.wire).run_id;
      const receipts = issuedEffectSetReceiptWires(issuedSet, ledger, preview);
      // The journal owns the first unknown observation. Reissue from current
      // receipt facts at its original time, then retain the strict whole-wire
      // comparison: a new read must not rewrite that observation or Effect set.
      const original = journal.lookupReconciliationState(ref);
      const observedAt = original === undefined
        ? updatedAt : JSON.parse(original).updated_at;
      const wire = control.effectReconciliationRunState(preview, receipts,
        {runId, updatedAt: observedAt, resultNames: retained.resultNames}, limits);
      journal.recordReconciliationState(ref, wire);
      return JSON.parse(wire);
    },
    // The recorded reconciliation state of a Run, or undefined. Reading it
    // performs no provider I/O and never starts or resends work.
    reconciliation(ref) {
      const wire = journal.lookupReconciliationState(ref);
      return wire === undefined ? undefined : Object.freeze(JSON.parse(wire));
    },
    async accept({prepared, authorityScopeCid, requestId, namespaceId,
      principalId, connection, lookupExpiresAt, submission}) {
      // Authentication/current acceptance authority precedes even lookup, so
      // a caller cannot infer the presence of another caller's request.
      const policy = await authorizeRequest(Object.freeze({prepared,
        authorityScopeCid, requestId, namespaceId, principalId, connection}));
      if (policy === null || typeof policy !== 'object') throw denied();
      const identity = requestIdentityFor === undefined
        ? moon.clientProgramEffectRequestIdentity(prepared,
          authorityScopeCid, requestId, moon.clientProgramSourceFreeInputIntentCid())
        : requestIdentityFor(Object.freeze({prepared, authorityScopeCid, requestId}));
      if (identity === undefined) throw denied();
      let requestedStop = false;
      if (submission !== undefined) {
        const original = journal.lookupSubmittedIntent(submission,
          {authorityScopeCid, currentAuthorization: submission.currentAuthorization === true}, moon);
        if (original?.requestId !== requestId || original.intentCid !== submission.intentCid) {
          throw denied();
        }
        // Reuse the existing submitted-intent reader ceilings, not the
        // independent Effect-material limits above.
        const intent = moon.clientSubmittedIntent(original.intentWire,
          1048576, 65536, 64);
        if (intent === undefined) throw denied();
        if (!moon.clientSubmittedIntentEffectCompatible(intent, prepared)) throw denied();
        requestedStop = moon.clientSubmittedIntentRequestsCommitStop(intent);
      }
      const compiled = () => compile(prepared);
      const requiresQueryTime = queryTimeRequired(prepared);
      const accepted = await journal.admitOrLookupDefinition(identity, {
        namespaceId, lookupExpiresAt, submission,
        async issueDefinition() {
          // Only the Journal's new-Run branch needs this optional capability.
          // Saved original Runs keep their lookup/recovery identity when a
          // signer is absent; no new preparation or publication starts here.
          if (requestedStop) assertRequestedStopAvailable?.();
          // This callback runs only after the same Journal lookup selected a
          // new invocation. A policy's old creation time is not a fresh query
          // sample. Keep the one preparation before dependent compilation;
          // a race/lookup later restores the winning saved original instead.
          const queryTimePreparation = requiresQueryTime
            ? checked(queryTimeCall(1, [prepared, identity, sampleOriginalQueryTime()]))
            : undefined;
          const createdAt = queryTimePreparation === undefined ? policy.createdAt
            : queryTimeCall(2, [queryTimePreparation]);
          // The installed Host selects an actual Result policy original before
          // this new Run is recorded. A retained Run reuses its saved original.
          const resultPolicyOriginal = contentPolicies.get(prepared) ?? resultPolicyOriginalFor?.(prepared);
          const allowed = checked(moon.clientProgramIssueAllowedEffectRun(
            compiled(), policy.executionContextCid, policy.hostPolicyCid,
            policy.expiresAt));
          const definition = checked(moon.clientProgramIssueEffectRunDefinition(
            allowed, namespaceId, randomUUID(), createdAt, policy.expiresAt));
          if (queryTimePreparation !== undefined) {
            checked(queryTimeCall(3, [queryTimePreparation, prepared, allowed, definition, identity]));
          }
          if (!moon.clientProgramEffectRunStartCurrent(allowed,
            definition, now())) throw expired();
          const runDefinition = control.admit('run_definition',
            moon.strategyPublicationContractJson(definition), limits);
          const updateTargetRunOriginal = updateTargetOriginals?.captureRun({prepared,
            allowed, definition, identity});
          // Selected UPDATE/STORE custody already contains this exact codec;
          // do not retain a second serialized copy. Other requested stops need
          // the same original materials before acceptance, not current config
          // reconstruction when their first Effect is resumed after restart.
          // Ordinary approval also resumes in another process without an
          // explicit commit stop. Its original must survive that same boundary.
          const effectOriginalRunWire = updateTargetRunOriginal !== undefined
            ? undefined : updateTargetOriginals?.captureEffectMaterials({allowed, definition, identity});
          if (requestedStop && updateTargetRunOriginal === undefined && effectOriginalRunWire === undefined) {
            throw Object.assign(new Error('RequestedEffectStopOriginalUnavailable'),
              {code: 'RequestedEffectStopOriginalUnavailable'});
          }
          const modelCompiled = inferPlanFor?.(prepared) === undefined ? undefined :
            control.adoptCheckedClientEffectInferRun(allowed, runDefinition,
              resultPolicyOriginal, limits);
          // The same Host may retain its actual resource/Scope originals
          // before the Journal publishes this business Run. A failure remains
          // with that original preparation; no second definition or admission
          // is issued by this callback, and it grants no Effect approval.
          const originalPreparation = prepareDefinition?.(Object.freeze({prepared,
            compilation: compiled(), allowed, definition, identity, runDefinition,
            modelCompiled, resultPolicyOriginal, queryTimePreparation}));
          const preparationThen = originalPreparation?.then;
          if (typeof preparationThen === 'function') {
            // The actual Journal already awaits this SAME issuer. Invalid
            // async construction stays joined to its original acceptance
            // before refusal; settlement is not a cleanup acknowledgement.
            try {
              await new Promise((resolve, reject) => Reflect.apply(
                preparationThen, originalPreparation, [() => resolve(), reject]));
            } catch {
              // A rejected async constructor remains invalid at this sync
              // preparation boundary, with the same original refusal below.
            }
            throw new TypeError('AsyncClientEffectDefinitionPreparation');
          }
          return {
            resultNames: moon.clientProgramEffectCompilationResultNames(
              compiled()),
            runDefinition,
            runAdmissionEvidence: {
              prepared: moon.strategyRunEvidenceJson(
                moon.clientProgramAllowedEffectRunPrepared(allowed)),
              authorization: moon.strategyRunEvidenceJson(
                moon.clientProgramAllowedEffectRunAuthorization(allowed)),
              ...(updateTargetRunOriginal === undefined ? {} : {updateTargetRunOriginal}),
              ...(effectOriginalRunWire === undefined ? {} : {effectOriginalRunWire}),
              ...(resultPolicyOriginal === undefined ? {} :
                {resultPolicyOriginal}),
              ...(modelCompiled === undefined ? {} : {
                modelOriginalRunWire: originalModelRunWire(modelCompiled, runDefinition),
              }),
            },
          };
        },
      }, moon, control);
      const handle = Object.freeze({ref: accepted.ref,
        durability: accepted.durability, revision: accepted.revision,
        lookupExpiresAt: accepted.lookupExpiresAt});
      handles.set(handle, {prepared, identity, namespaceId, principalId,
        connection, compile: compiled, requiresQueryTime});
      return handle;
    },
    async start(handle, {beforePhysicalStart, started, signal} = {}) {
      const owned = handles.get(handle);
      if (owned === undefined ||
          beforePhysicalStart !== undefined &&
            typeof beforePhysicalStart !== 'function' ||
          started !== undefined && typeof started !== 'function') {
        throw denied();
      }
      const {prepared, identity, namespaceId, principalId, connection, compile, requiresQueryTime} = owned;
      const start = await startRun({identity, namespaceId, principalId, connection});
      const retained = journal.resolveDefinition(identity, {namespaceId}, moon, control);
      if (retained.physicalStartReserved !== false ||
          retained.preDispatchFailureConfirmed) {
        return Object.freeze({kind: 'reconcile', ref: start.ref});
      }
      const evidence = retained.runAdmissionEvidence;
      if (evidence === undefined) {
        throw Object.assign(new Error('ClientEffectRunEvidenceMissing'),
          {code: 'ClientEffectRunEvidenceMissing', ref: retained.ref});
      }
      const originalSubmittedIntent = journal.originalSubmittedIntent(identity,
        {namespaceId}, moon, control);
      if (originalSubmittedIntent !== undefined &&
          !moon.clientSubmittedIntentEffectCompatible(originalSubmittedIntent.intent, prepared)) {
        throw denied();
      }
      const compilation = compile();
      const original = updateTargetOriginals?.validateRun({prepared, compilation,
        evidence, runDefinition: retained.runDefinition, identity}) ?? {};
      const allowed = checked(moon.clientProgramAdmitAllowedEffectRun(compilation,
        admitEvidence('prepared_invocation', evidence.prepared),
        admitEvidence('run_authorization', evidence.authorization)));
      const definition = definitionToken(retained.runDefinition);
      const queryTime = restoreQueryTime(requiresQueryTime, prepared, allowed, definition, identity);
      const owner = checked(moon.clientProgramBindCompiledEffectRun(
        prepared, allowed, definition));
      // Recheck current start authority immediately before the atomic physical
      // claim. The original authorization remains bound to the saved Run.
      let authorized = false;
      try {
        authorized = await authorizeRunStart(Object.freeze({namespaceId,
          principalId, connection, ref: retained.ref,
          runDefinition: retained.runDefinition}));
      } catch { /* A failed current authority observation fails closed. */ }
      originalSubmittedIntent?.assertCurrent();
      if (authorized === true &&
          !moon.clientProgramEffectRunStartCurrent(allowed,
            definition, now())) {
        // This Run never crossed the physical boundary. A concurrent winner
        // may have claimed it, in which case its unknown outcome is retained.
        try { journal.markPreDispatchFailure(start.ref); }
        catch (cause) {
          const latest = journal.resolveDefinition(identity, {namespaceId},
            moon, control);
          if (latest?.physicalStartReserved !== false) {
            return Object.freeze({kind: 'reconcile', ref: start.ref});
          }
          throw cause;
        }
        throw expired(start.ref);
      }
      signal?.throwIfAborted();
      original.assertUpdateSelectionCurrent?.();
      let preparedExecution;
      if (prepareExecution !== undefined && authorized === true) {
        try {
          preparedExecution = prepareExecution(Object.freeze({ref: start.ref,
            identity, owner, prepared, compilation, allowed, definition,
            ...queryTime,
            runDefinition: retained.runDefinition,
            originalSubmittedIntent,
            ...original,
            resultPolicyOriginal: evidence.resultPolicyOriginal}));
          if (typeof preparedExecution?.then === 'function') {
            // A misinstalled asynchronous preparer is not a physical-start
            // permit. Consume its eventual rejection without accepting it
            // as evidence or retrying this Run.
            void Promise.resolve(preparedExecution).catch(() => {});
            throw new TypeError('AsyncClientEffectPreparation');
          }
        } catch (error) {
          try { journal.markPreDispatchFailure(start.ref); }
          catch (observationFailure) {
            const latest = journal.resolveDefinition(identity, {namespaceId},
              moon, control);
            if (latest?.physicalStartReserved !== false) {
              return Object.freeze({kind: 'reconcile', ref: start.ref});
            }
            throw Object.assign(new Error('ClientEffectPreparationUnknown',
              {cause: error}), {code: 'ClientEffectPreparationUnknown',
              primaryFailure: error, observationFailure, ref: start.ref});
          }
          throw error;
        }
      }
      // A resumed Checkpoint enters its current claim immediately before the
      // durable physical-start reservation. The answer alone is not a send
      // permit; no asynchronous work separates these two admissions.
      beforePhysicalStart?.();
      originalSubmittedIntent?.assertCurrent();
      original.assertUpdateSelectionCurrent?.();
      if (!journal.reservePhysicalStart(identity, {namespaceId, ref: start.ref,
        currentAuthorization: authorized === true}, moon, control)) {
        return Object.freeze({kind: 'reconcile', ref: start.ref});
      }
      started?.();
      // Only the claim winner receives the bound owner. The callback owns all
      // capture/apply/publication and cleanup, including after a thrown error.
      // No catch path resets the durable physical-start claim.
      const value = await execute(Object.freeze({ref: start.ref, identity,
        owner, prepared, compilation, allowed, definition,
        ...queryTime,
        ...original,
        runDefinition: retained.runDefinition, originalSubmittedIntent,
        preparedExecution, signal}));
      return Object.freeze({kind: 'started', ref: start.ref, value});
    },
    // Rebind a previously admitted computation for the existing Checkpoint
    // owner. This grants no physical-start permit and never clears the Run's
    // original start claim. The caller must retain its fenced continuation
    // and restore completed inputs before asking an adapter for new I/O.
    async restoreComputation(handle) {
      const owned = handles.get(handle);
      if (owned === undefined) throw denied();
      const {prepared, identity, namespaceId, principalId, connection, compile, requiresQueryTime} = owned;
      const retained = journal.resolveDefinition(identity, {namespaceId}, moon, control);
      if (retained?.ref.runDefinitionCid !== handle.ref.runDefinitionCid ||
          retained.physicalStartReserved !== true ||
          retained.preDispatchFailureConfirmed || retained.cancellationRequested ||
          retained.observedTerminalOutcome !== null) throw denied();
      const evidence = retained.runAdmissionEvidence;
      if (evidence === undefined) throw denied();
      const originalSubmittedIntent = journal.originalSubmittedIntent(identity,
        {namespaceId}, moon, control);
      if (originalSubmittedIntent !== undefined &&
          !moon.clientSubmittedIntentEffectCompatible(originalSubmittedIntent.intent, prepared)) {
        throw denied();
      }
      const compilation = compile();
      const original = updateTargetOriginals?.validateRun({prepared, compilation,
        evidence, runDefinition: retained.runDefinition, identity}) ?? {};
      const allowed = checked(moon.clientProgramAdmitAllowedEffectRun(compilation,
        admitEvidence('prepared_invocation', evidence.prepared),
        admitEvidence('run_authorization', evidence.authorization)));
      const definition = definitionToken(retained.runDefinition);
      const queryTime = restoreQueryTime(requiresQueryTime, prepared, allowed, definition, identity);
      const owner = checked(moon.clientProgramBindCompiledEffectRun(prepared, allowed, definition));
      const current = await authorizeRunStart(Object.freeze({namespaceId,
        principalId, connection, ref: retained.ref, runDefinition: retained.runDefinition}));
      if (current !== true) throw denied();
      originalSubmittedIntent?.assertCurrent();
      original.assertUpdateSelectionCurrent?.();
      if (!moon.clientProgramEffectRunStartCurrent(allowed, definition, now())) {
        throw expired(retained.ref);
      }
      const modelCompiled = prepareDefinition === undefined || inferPlanFor?.(prepared) === undefined ? undefined :
        control.adoptCheckedClientEffectInferRun(allowed, retained.runDefinition, evidence.resultPolicyOriginal, limits);
      const facts = Object.freeze({ref: retained.ref, identity, owner, prepared, compilation,
        ...queryTime,
        ...original,
        allowed, definition, runDefinition: retained.runDefinition,
        queryTimePreparation: queryTime.queryTimePreparation, modelCompiled,
        originalSubmittedIntent,
        resultPolicyOriginal: evidence.resultPolicyOriginal});
      // A cold lookup did not enter the new-Run issuer above. Restore its
      // SAME normal definition/resource constructor before opening execution;
      // the original Request parent owns partial failure, not a new admission.
      const originalPreparation = prepareDefinition?.(facts);
      const preparationThen = originalPreparation?.then;
      if (typeof preparationThen === 'function') {
        try {
          await new Promise((resolve, reject) => Reflect.apply(
            preparationThen, originalPreparation, [() => resolve(), reject]));
        } catch { /* Join the same invalid borrow before refusing it. */ }
        throw new TypeError('AsyncClientEffectDefinitionPreparation');
      }
      if (prepareDefinition !== undefined) {
        // The synchronous constructor may reenter cancellation/retirement.
        // Re-read this original Journal boundary before any execution opens.
        const current = journal.resolveDefinition(identity, {namespaceId}, moon, control);
        if (current?.ref.runDefinitionCid !== handle.ref.runDefinitionCid ||
            current.runDefinition?.identity !== retained.runDefinition.identity ||
            current.physicalStartReserved !== true || current.preDispatchFailureConfirmed ||
            current.cancellationRequested || current.observedTerminalOutcome !== null) throw denied();
        originalSubmittedIntent?.assertCurrent();
        original.assertUpdateSelectionCurrent?.();
        if (!moon.clientProgramEffectRunStartCurrent(allowed, definition, now())) throw expired(retained.ref);
      }
      const preparedExecution = prepareExecution?.(facts);
      if (typeof preparedExecution?.then === 'function') {
        void Promise.resolve(preparedExecution).catch(() => {});
        throw new TypeError('AsyncClientEffectPreparation');
      }
      return Object.freeze({...facts, preparedExecution});
    },
  });
}
