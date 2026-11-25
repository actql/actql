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

import type {WireConnection, WireRunRef, WireRunState} from '../../packages/client-wire/index.js';
import type {openClientRequestJournal} from './client-request-journal.mjs';
import type {installUpdateTargetOriginals} from './installed-update-originals.mjs';

type Journal = Pick<ReturnType<typeof openClientRequestJournal>, 'admitOrLookupDefinition' | 'resolveDefinition' |
  'lookupDefinition' | 'lookupRunDefinition' | 'lookupSubmittedIntent' | 'reserveDispatch' | 'reservePhysicalStart' |
  'originalSubmittedIntent' | 'recordReconciliationState' | 'lookupReconciliationState' | 'markPreDispatchFailure'>;
type DefinitionOptions = Parameters<Journal['admitOrLookupDefinition']>[1];
type Retained = NonNullable<ReturnType<Journal['resolveDefinition']>>;
type RunDefinition = NonNullable<Retained['runDefinition']>;
type AdmissionMaterial = NonNullable<Retained['runAdmissionEvidence']>;
type OriginalIntent = ReturnType<Journal['originalSubmittedIntent']>;
type Publication = Parameters<Journal['admitOrLookupDefinition']>[3] &
  Pick<ReturnType<typeof runtimeCore>['publicationControl'], 'effectReconciliationRunState' | 'adoptCheckedClientEffectInferRun'>;
type Runtime = Readonly<{
    clientRequestAuthorityScopeCid(identity: unknown): string;
    clientRequestCallerId(identity: unknown): string;
    clientProgramEffectTargetSelections?(prepared: unknown): string | undefined;
    clientProgramEffectTargetSelectionOriginal?(prepared: unknown): readonly unknown[];
    clientProgramEffectCompilationIssueCode(result: unknown): string | undefined;
    clientProgramEffectRunStartCurrent(allowed: unknown, definition: unknown, now: string): boolean;
    clientProgramEffectAcquisitionCount(prepared: unknown): number;
    clientProgramEffectSerializationOccurrences?(prepared: unknown): readonly unknown[];
    clientProgramCompileLocalEffectsWithSourceFreePolicyBody(prepared: unknown, cid: string, wire: string,
      bytes: number, nodes: number, depth: number): unknown;
    clientProgramCompileLocalEffects(prepared: unknown): unknown;
    clientProgramCompileLocalEffectsWithInfer(prepared: unknown, infer: unknown): unknown;
    clientProgramCompileLocalEffectsWithInfers(prepared: unknown, infers: readonly unknown[]): unknown;
    clientProgramEffectRequestIdentity(prepared: unknown, authorityScopeCid: string, requestId: string, intentCid: string): unknown;
    clientProgramSourceFreeInputIntentCid(): string;
    clientSubmittedIntentEffectCompatible(intent: unknown, prepared: unknown): boolean;
    clientSubmittedIntentRequestsCommitStop(intent: unknown): boolean;
    clientProgramIssueAllowedEffectRun(compilation: unknown, executionContextCid: string,
      hostPolicyCid: string, expiresAt: string): unknown;
    clientProgramIssueEffectRunDefinition(allowed: unknown, namespace: string, runId: string,
      createdAt: string, expiresAt: string): unknown;
    clientProgramEffectCompilationResultNames(compilation: unknown): readonly string[];
    clientProgramAllowedEffectRunPrepared(allowed: unknown): unknown;
    clientProgramAllowedEffectRunAuthorization(allowed: unknown): unknown;
    clientProgramAdmitAllowedEffectRun(compilation: unknown, preparedEvidence: unknown, authorization: unknown): unknown;
    clientProgramBindCompiledEffectRun(prepared: unknown, allowed: unknown, definition: unknown): unknown;
    strategyPublicationContractIdentity(contract: unknown): string;
    strategyPublicationContractJson(contract: unknown): string;
    strategyRunEvidenceJson(original: unknown): string;
    strategyRunEvidenceAdmit(name: string, wire: string, bytes: number, nodes: number, depth: number): unknown;
    strategyPublicationAdmit(name: 'run_definition', wire: string, bytes: number, nodes: number, depth: number): unknown;
  }> & Parameters<Journal['admitOrLookupDefinition']>[2] & Parameters<Journal['lookupSubmittedIntent']>[2] &
  Parameters<Journal['originalSubmittedIntent']>[2] & Parameters<Journal['reserveDispatch']>[2] &
  Parameters<Journal['reservePhysicalStart']>[2] & Parameters<Journal['lookupDefinition']>[1];
type MaybePromise<Value> = Value | PromiseLike<Value>;
type ResultPolicy = NonNullable<AdmissionMaterial['resultPolicyOriginal']>;
type UpdateOriginals = ReturnType<typeof installUpdateTargetOriginals>;
type ReserveOriginal = Parameters<UpdateOriginals['captureRun']>[1];
type CapturedPrepared = Parameters<UpdateOriginals['validatePreparedOriginal']>[2];
type UpdateSelection = Partial<Pick<ReturnType<UpdateOriginals['restoreRun']>,
  'updateTargetSelections' | 'assertUpdateSelectionCurrent'>>;
type RetainedUpdateMaterial = Parameters<UpdateOriginals['restoreRun']>[0];
type RunUpdateEvidence = Parameters<UpdateOriginals['validateRun']>[0]['evidence'];
type QueryTime = Readonly<{queryTimePreparation?: unknown; queryTime?: unknown}>;
type Policy = Readonly<{createdAt: string; expiresAt: string; executionContextCid: string; hostPolicyCid: string}>;
type Accept = Readonly<{prepared: unknown; authorityScopeCid: string; requestId: string; namespaceId: string;
  principalId: string; connection: WireConnection; lookupExpiresAt: string; submission?: DefinitionOptions['submission']}>;
type RequestFacts = Pick<Accept, 'prepared' | 'authorityScopeCid' | 'requestId'>;
type AcceptFacts = RequestFacts & Pick<Accept, 'namespaceId' | 'principalId' | 'connection'>;
type StartAuthority = Pick<Accept, 'namespaceId' | 'principalId' | 'connection'> &
  Readonly<{ref: WireRunRef; runDefinition: RunDefinition}>;
type DefinitionFacts = Readonly<{prepared: unknown; identity: unknown; compilation: unknown; allowed: unknown; definition: unknown;
  runDefinition: RunDefinition; queryTimePreparation?: unknown; modelCompiled?: unknown; resultPolicyOriginal?: ResultPolicy}>;
type InitialPreparation = Pick<DefinitionFacts, 'prepared' | 'identity' | 'compilation' | 'allowed' | 'definition' |
  'queryTimePreparation' | 'modelCompiled'>;
type PreparationResponse = (Partial<InitialPreparation> & Readonly<{then?: unknown}>) | null | undefined;
type Compile = (() => unknown) & {initialOriginal?: InitialPreparation};
type Owner = Pick<Accept, 'prepared' | 'namespaceId' | 'principalId' | 'connection'> &
  Readonly<{identity: unknown; compile: Compile; requiresQueryTime: boolean}>;
type Restore = Pick<Owner, 'prepared' | 'identity' | 'namespaceId'> &
  Readonly<{ref: WireRunRef; originalSubmittedIntent?: OriginalIntent}>;
type StartOptions = Readonly<{beforePhysicalStart?(): unknown; started?(): unknown; signal?: AbortSignal}>;
type ReceiptSet = Parameters<typeof issuedEffectSetReceiptWires>[0];
type Reconciliation = Readonly<{issuedSet: ReceiptSet; ledger: unknown; preview: object; updatedAt?: string}>;
type ExecutionFacts = Omit<DefinitionFacts, 'prepared'> & QueryTime & UpdateSelection & Readonly<{
  prepared: object; ref: WireRunRef; owner: unknown; originalSubmittedIntent?: OriginalIntent; preparedExecution?: unknown; signal?: AbortSignal;
}>;
type EvidenceReader = (maxOptionalBytes?: number) => AdmissionMaterial | undefined;
type Installation<Value> = Readonly<{moon: Runtime; publicationControl?: Publication; journal: Journal;
  authorizeRequest(input: AcceptFacts): MaybePromise<Policy | null | undefined>;
  authorizeRunStart(input: StartAuthority): MaybePromise<boolean>;
  prepareExecution?(input: ExecutionFacts): unknown;
  execute(input: ExecutionFacts): MaybePromise<Value>;
  prepareDefinition?(input: DefinitionFacts): PreparationResponse;
  captureDefinitionExplanation?(input: DefinitionFacts, evidence: EvidenceReader, hasIntent: boolean):
    Readonly<{ticket: unknown; evidence?: AdmissionMaterial}> | undefined;
  assertRequestedStopAvailable?(): unknown;
  requestIdentityFor?(input: RequestFacts): unknown;
  inferPlanFor?(prepared: unknown): unknown;
  resultPolicyOriginalFor?(prepared: unknown): ResultPolicy | undefined;
  validateInstallation?(input: Pick<DefinitionFacts, 'prepared' | 'compilation'>): unknown;
  updateTargetOriginals?: UpdateOriginals;
  reserveOriginal?: ReserveOriginal;
  localPolicySigning?: boolean;
  now?: () => string;
}>;

const limits = Object.freeze({maxWireBytes: 1000000, maxNodes: 100000,
  maxDepth: 100});
const denied = (): Error => Object.assign(new Error('ClientEffectRunDenied'),
  {code: 'ClientEffectRunDenied'});
const expired = (ref?: WireRunRef) => Object.assign(new Error('ClientEffectRunExpired'),
  {code: 'ClientEffectRunExpired', ref});
const unsupported = () => Object.assign(new Error('ClientProgramUnsupported'),
  {code: 'ClientProgramUnsupported'});

// Optional checked preparation DATA on this exact per-handle compiler thunk.
// The selected Request already funded its one borrowed slot before returning
// this tuple. It is never an Account decision, current proof or dispatch grant.
function retainInitialEffectPreparation(compiled: Compile, value: PreparationResponse, facts: DefinitionFacts) {
  if (value === undefined || value === null || typeof value !== 'object' || value.prepared === undefined) return;
  if (!Object.isFrozen(value) || value.prepared !== facts.prepared || value.identity !== facts.identity ||
      value.compilation !== facts.compilation || value.allowed !== facts.allowed || value.definition !== facts.definition ||
      value.queryTimePreparation !== facts.queryTimePreparation || value.modelCompiled !== facts.modelCompiled) throw denied();
  if (compiled.initialOriginal !== undefined && compiled.initialOriginal !== value) throw denied();
  compiled.initialOriginal = value as InitialPreparation;
}

function checkInitialEffectPreparation(value: InitialPreparation, prepared: unknown, identity: unknown,
  compilation: unknown, retained: Retained, moon: Runtime) {
  const evidence = retained.runAdmissionEvidence;
  if (!Object.isFrozen(value) || value.prepared !== prepared || value.identity !== identity ||
      value.compilation !== compilation || evidence === undefined ||
      retained.runDefinition.identity !== retained.ref.runDefinitionCid ||
      moon.strategyPublicationContractIdentity(value.definition) !== retained.ref.runDefinitionCid ||
      moon.strategyPublicationContractJson(value.definition) !== retained.runDefinition.wire ||
      moon.strategyRunEvidenceJson(moon.clientProgramAllowedEffectRunPrepared(value.allowed)) !== evidence.prepared ||
      moon.strategyRunEvidenceJson(moon.clientProgramAllowedEffectRunAuthorization(value.allowed)) !== evidence.authorization) throw denied();
}

export function installNodeClientEffectRun<Value>({moon,
  publicationControl: control = runtimeCore(moon).publicationControl,
  journal, authorizeRequest, authorizeRunStart, prepareExecution, execute,
  prepareDefinition, captureDefinitionExplanation, assertRequestedStopAvailable, requestIdentityFor,
  inferPlanFor, resultPolicyOriginalFor, validateInstallation, updateTargetOriginals, reserveOriginal,
  localPolicySigning = false,
  now = () => new Date().toISOString()}: Installation<Value>) {
  if (typeof moon?.clientProgramEffectCompilationIssueCode !== 'function' ||
      typeof authorizeRequest !== 'function' ||
      (prepareExecution !== undefined &&
        typeof prepareExecution !== 'function') ||
      (prepareDefinition !== undefined && typeof prepareDefinition !== 'function') ||
      (captureDefinitionExplanation !== undefined && typeof captureDefinitionExplanation !== 'function') ||
      (requestIdentityFor !== undefined && typeof requestIdentityFor !== 'function') ||
      (assertRequestedStopAvailable !== undefined &&
        typeof assertRequestedStopAvailable !== 'function') ||
      (inferPlanFor !== undefined && typeof inferPlanFor !== 'function') ||
      (resultPolicyOriginalFor !== undefined &&
        typeof resultPolicyOriginalFor !== 'function') ||
      (validateInstallation !== undefined && typeof validateInstallation !== 'function') ||
      typeof localPolicySigning !== 'boolean' ||
      (reserveOriginal !== undefined && typeof reserveOriginal !== 'function') ||
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
  const startRun = installNodeClientRunStart<unknown, WireConnection, Runtime, Publication, RunDefinition>({journal, requestControl: moon,
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
  const queryTimeCall = (index: number, args: readonly unknown[]): unknown => Reflect.apply(queryTimePorts[index], moon, args);
  const queryTimeRequired = (prepared: unknown) => {
    if (!hasQueryTime) return false;
    const required = checked(queryTimeCall(0, [prepared, limits.maxNodes, limits.maxNodes]));
    if (typeof required !== 'boolean') throw denied();
    return required;
  };
  const restoreQueryTime = (required: boolean, prepared: unknown, allowed: unknown, definition: unknown,
    identity: unknown, retainedPreparation?: unknown): QueryTime => {
    if (!required) return {};
    const queryTimePreparation = retainedPreparation ?? checked(queryTimeCall(4,
      [prepared, allowed, definition, identity]));
    const queryTime = retainedPreparation === undefined
      ? queryTimeCall(5, [queryTimePreparation])
      : checked(queryTimeCall(3, [queryTimePreparation, prepared, allowed, definition, identity]));
    if (queryTime === undefined) throw denied();
    return {queryTimePreparation, queryTime};
  };
  const handles = new WeakMap<object, Owner>();
  const compilations = new WeakMap<object, unknown>();
  const contentPolicies = new WeakMap<object, ResultPolicy>();
  const compile = (prepared: unknown) => {
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
      : Array.isArray(infer)
        ? moon.clientProgramCompileLocalEffectsWithInfers(prepared, infer)
        : moon.clientProgramCompileLocalEffectsWithInfer(prepared, infer);
    if (moon.clientProgramEffectCompilationIssueCode(outcome) ===
        'unsupported_program') throw unsupported();
    compilation = checked(outcome);
    if (contentPolicy !== undefined) contentPolicies.set(prepared, contentPolicy);
    validateInstallation?.({prepared, compilation});
    compilations.set(prepared, compilation);
    return compilation;
  };
  const admitEvidence = (name: string, wire: unknown) => checked(
    moon.strategyRunEvidenceAdmit(name, wire as string, limits.maxWireBytes,
      limits.maxNodes, limits.maxDepth));
  const definitionToken = (definition: RunDefinition) => checked(moon.strategyPublicationAdmit(
    'run_definition', definition.wire, limits.maxWireBytes,
    limits.maxNodes, limits.maxDepth));
  return Object.freeze({
    // A held Run-acceptance Checkpoint must never be opened for a Program
    // this installed Host cannot compile. The exact compiled owner is reused
    // by acceptance; this check neither issues a Run nor starts physical I/O.
    checkSupported(prepared: unknown) { compile(prepared); },
    capturePreparedOriginal(prepared: unknown, original?: CapturedPrepared) {
      if (original !== undefined) {
        if (updateTargetOriginals === undefined) throw denied();
        // Held restoration already owns these complete materials. Preserve its
        // existing nominal compiler/current/full-byte validator; a copied DATA
        // flag cannot select this branch without that restored original pair.
        updateTargetOriginals.validatePreparedOriginal(prepared, compile(prepared), original);
        return original;
      }
      return updateTargetOriginals?.capturePrepared(prepared, compile(prepared), reserveOriginal);
    },
    // Restore ONLY the existing resource preparation for an already retained
    // Run. No start claim, execution Owner, new Definition, query-time sample
    // or business authorization is issued here. Canceled/unknown Runs still
    // need their same resources for original observation and cleanup.
    async restoreRetainedPreparation({prepared, identity, namespaceId, ref, originalSubmittedIntent}: Restore) {
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
        restored = updateTargetOriginals.restoreRun(evidence.updateTargetRunOriginal as RetainedUpdateMaterial,
          retained.runDefinition, identity, compilation, prepared);
      } else {
        if (typeof evidence.effectOriginalRunWire !== 'string') throw denied();
        restored = updateTargetOriginals.restoreEffectMaterials(evidence.effectOriginalRunWire,
          retained.runDefinition, identity, compilation, prepared);
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
        ...restored as Partial<typeof restored>, originalSubmittedIntent});
      // Reuse the same actual normal constructor/adoption callback, with its
      // original eight-field tuple. Its existing Host bag owns partial failure.
      const selected = prepareDefinition?.(facts);
      const then = selected?.then;
      if (typeof then === 'function') {
        try {await new Promise<void>((resolve, reject) => Reflect.apply(then, selected, [resolve, reject]));}
        catch { /* Join the original invalid borrow before refusing it. */ }
        throw new TypeError('AsyncClientEffectDefinitionPreparation');
      }
      originalSubmittedIntent.assertCurrent();
      (restored as UpdateSelection).assertUpdateSelectionCurrent?.();
      return facts;
    },
    // Record the public state of a started Run whose complete admitted Effect
    // Set has unknown outcomes. The owner names exactly those Effects; the
    // journal keeps the state for status and reconcile in any later process.
    // Nothing is resent, and no answer or Store write relabels the outcome.
    // `issuedSet` must be the exact Set the receipt owner issued for this
    // ledger and Preview, as for publication.
    recordReconciliation(ref: WireRunRef, {issuedSet, ledger, preview,
      updatedAt = now()}: Reconciliation) {
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
        ? updatedAt : JSON.parse(original as string).updated_at;
      const wire = control.effectReconciliationRunState(preview, receipts,
        {runId, updatedAt: observedAt, resultNames: retained.resultNames}, limits);
      journal.recordReconciliationState(ref, wire);
      return JSON.parse(wire) as WireRunState;
    },
    // The recorded reconciliation state of a Run, or undefined. Reading it
    // performs no provider I/O and never starts or resends work.
    reconciliation(ref: WireRunRef) {
      const wire = journal.lookupReconciliationState(ref);
      return wire === undefined ? undefined : Object.freeze(JSON.parse(wire as string) as WireRunState);
    },
    async accept({prepared, authorityScopeCid, requestId, namespaceId,
      principalId, connection, lookupExpiresAt, submission}: Accept) {
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
        requestedStop = moon.clientSubmittedIntentRequestsCommitStop(intent) as boolean;
      }
      const compiled: Compile = () => compile(prepared);
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
            : queryTimeCall(2, [queryTimePreparation]) as string;
          // The installed Host selects an actual Result policy original before
          // this new Run is recorded. A retained Run reuses its saved original.
          const resultPolicyOriginal = contentPolicies.get(prepared as object) ?? resultPolicyOriginalFor?.(prepared);
          const definitionCompilation = compiled();
          const allowed = checked(moon.clientProgramIssueAllowedEffectRun(
            definitionCompilation, policy.executionContextCid, policy.hostPolicyCid,
            policy.expiresAt));
          const definition = checked(moon.clientProgramIssueEffectRunDefinition(
            allowed, namespaceId, randomUUID(), createdAt, policy.expiresAt));
          if (queryTimePreparation !== undefined) {
            checked(queryTimeCall(3, [queryTimePreparation, prepared, allowed, definition, identity]));
          }
          if (!moon.clientProgramEffectRunStartCurrent(allowed,
            definition, now())) throw expired();
          const runDefinition = control.admit('run_definition',
            moon.strategyPublicationContractJson(definition), limits) as RunDefinition;
          const updateTargetRunOriginal = updateTargetOriginals?.captureRun({prepared,
            allowed, definition, identity, compilation: definitionCompilation, runDefinition}, reserveOriginal);
          // Selected UPDATE/STORE custody already contains this exact codec;
          // do not retain a second serialized copy. Other requested stops need
          // the same original materials before acceptance, not current config
          // reconstruction when their first Effect is resumed after restart.
          // Ordinary approval also resumes in another process without an
          // explicit commit stop. Its original must survive that same boundary.
          const effectOriginalRunWire = updateTargetRunOriginal !== undefined
            ? undefined : updateTargetOriginals?.captureEffectMaterials({prepared, allowed, definition, identity,
              compilation: definitionCompilation, runDefinition,
              retainForReview: requestedStop || (submission !== undefined && localPolicySigning)});
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
          const definitionFacts = Object.freeze({prepared,
            compilation: compiled(), allowed, definition, identity, runDefinition,
            modelCompiled, resultPolicyOriginal, queryTimePreparation});
          const evidence: EvidenceReader = maxOptionalBytes => {
            const modelOriginal = modelCompiled === undefined ? undefined :
              originalModelRunWire(modelCompiled, runDefinition, maxOptionalBytes);
            if (modelCompiled !== undefined && modelOriginal === undefined) return undefined;
            return Object.freeze({
              prepared: moon.strategyRunEvidenceJson(
                moon.clientProgramAllowedEffectRunPrepared(allowed)),
              authorization: moon.strategyRunEvidenceJson(
                moon.clientProgramAllowedEffectRunAuthorization(allowed)),
              ...(updateTargetRunOriginal === undefined ? {} : {updateTargetRunOriginal}),
              ...(effectOriginalRunWire === undefined ? {} : {effectOriginalRunWire}),
              ...(resultPolicyOriginal === undefined ? {} : {resultPolicyOriginal}),
              ...(modelOriginal === undefined ? {} : {modelOriginalRunWire: modelOriginal}),
            });
          };
          const selectedExplanation = captureDefinitionExplanation?.(definitionFacts, evidence,
            submission?.intentCid !== undefined);
          const originalPreparation = prepareDefinition?.(definitionFacts);
          const preparationThen = originalPreparation?.then;
          if (typeof preparationThen === 'function') {
            // The actual Journal already awaits this SAME issuer. Invalid
            // async construction stays joined to its original acceptance
            // before refusal; settlement is not a cleanup acknowledgement.
            try {
              await new Promise<void>((resolve, reject) => Reflect.apply(
                preparationThen, originalPreparation, [() => resolve(), reject]));
            } catch {
              // A rejected async constructor remains invalid at this sync
              // preparation boundary, with the same original refusal below.
            }
            throw new TypeError('AsyncClientEffectDefinitionPreparation');
          }
          retainInitialEffectPreparation(compiled, originalPreparation, definitionFacts);
          return {
            resultNames: moon.clientProgramEffectCompilationResultNames(
              compiled()),
            runDefinition,
            runAdmissionEvidence: selectedExplanation === undefined ? evidence() : selectedExplanation.evidence,
            ...(selectedExplanation === undefined ? {} : {
              originalPlan: selectedExplanation.ticket, originalExplanation: selectedExplanation.ticket,
            }),
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
    async start(handle: object, {beforePhysicalStart, started, signal}: StartOptions = {}) {
      const owned = handles.get(handle);
      if (owned === undefined ||
          beforePhysicalStart !== undefined &&
            typeof beforePhysicalStart !== 'function' ||
          started !== undefined && typeof started !== 'function') {
        throw denied();
      }
      const {prepared, identity, namespaceId, principalId, connection, compile, requiresQueryTime} = owned;
      const start = await startRun({identity, namespaceId, principalId, connection});
      const retained = journal.resolveDefinition(identity, {namespaceId}, moon, control)!;
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
      const original: UpdateSelection = updateTargetOriginals?.validateRun({prepared, compilation,
        evidence: evidence as RunUpdateEvidence, runDefinition: retained.runDefinition, identity}) ?? {};
      if (compile.initialOriginal !== undefined) {
        checkInitialEffectPreparation(compile.initialOriginal, prepared, identity, compilation, retained, moon);
      }
      const allowed = compile.initialOriginal === undefined
        ? checked(moon.clientProgramAdmitAllowedEffectRun(compilation,
          admitEvidence('prepared_invocation', evidence.prepared),
          admitEvidence('run_authorization', evidence.authorization)))
        : compile.initialOriginal.allowed;
      const definition = compile.initialOriginal === undefined
        ? definitionToken(retained.runDefinition) : compile.initialOriginal.definition;
      const queryTime = restoreQueryTime(requiresQueryTime, prepared, allowed, definition, identity,
        compile.initialOriginal?.queryTimePreparation);
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
      let preparedExecution: unknown;
      if (prepareExecution !== undefined && authorized === true) {
        try {
          // compile() has admitted the same prepared object retained by this handle.
          preparedExecution = prepareExecution(Object.freeze({ref: start.ref,
            identity, owner, prepared: prepared as object, compilation, allowed, definition,
            ...queryTime,
            runDefinition: retained.runDefinition,
            originalSubmittedIntent,
            ...original,
            resultPolicyOriginal: evidence.resultPolicyOriginal}));
          if (typeof (preparedExecution as {then?: unknown} | null | undefined)?.then === 'function') {
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
      // The actual winning claim transfers these originals to the existing
      // bound execution facts. A refused/ambiguous claim retains the same slot.
      delete compile.initialOriginal;
      started?.();
      // Only the claim winner receives the bound owner. The callback owns all
      // capture/apply/publication and cleanup, including after a thrown error.
      // No catch path resets the durable physical-start claim.
      const value = await execute(Object.freeze({ref: start.ref, identity,
        owner, prepared: prepared as object, compilation, allowed, definition,
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
    async restoreComputation(handle: Readonly<{ref: WireRunRef}>) {
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
      const original: UpdateSelection = updateTargetOriginals?.validateRun({prepared, compilation,
        evidence: evidence as RunUpdateEvidence, runDefinition: retained.runDefinition, identity}) ?? {};
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
      const facts = Object.freeze({ref: retained.ref, identity, owner, prepared: prepared as object, compilation,
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
          await new Promise<void>((resolve, reject) => Reflect.apply(
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
      if (typeof (preparedExecution as {then?: unknown} | null | undefined)?.then === 'function') {
        void Promise.resolve(preparedExecution).catch(() => {});
        throw new TypeError('AsyncClientEffectPreparation');
      }
      return Object.freeze({...facts, preparedExecution});
    },
  });
}
