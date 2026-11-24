// The same funded Request retains compilation and Explanation custody until
// the original admission's children can return. This path never grants a Run.
import {checked} from '../host-common/runtime-result.mjs';
import {assertRequestPreparationControl, beginRequestInput, beginHttpRequestInput, cleanupRequestInput, requestPreparationAvailable}
  from '../local-node/request-preparation-adapter.mjs';
import {checkedRequestProgramPreparation} from './client-program-preparation.mjs';
import {assertOriginalClientRequestJournal, observeOriginalClientRequestJournalCustody} from './client-request-journal.mjs';
import {localContractLimits} from './local-values-plan.mjs';
import resourceRuntime from './ordinary-node-resource-runtime.cjs';

import type {RequestPreparationState} from '../local-node/request-preparation-adapter.mjs';
import type {SourceProducerCustody} from './ordinary-source-producer-custody.mjs';
import type {OrdinarySourceRun} from './ordinary-source-run-custody.mjs';

type Callback = (...args: never[]) => unknown;
type CheckedRuntime = Parameters<typeof checkedRequestProgramPreparation>[0];
type IssueCode = Parameters<typeof checkedRequestProgramPreparation>[2];
type ModuleCompilation = (parent: unknown, receipt: object, admission: unknown, output: boolean) => unknown;
type Runtime = RequestPreparationState['context']['runtime'] & CheckedRuntime & Readonly<{
  clientProgramPrepareRequestProgramCompilation: ModuleCompilation;
  clientProgramRequestProgramModuleIssueCode: IssueCode;
  clientProgramReserveRequestQueryTimeInvocation?: unknown;
  clientProgramRequestProgramCompilationOriginal?: unknown;
  clientProgramPreparationBorrowRead(holder: unknown): unknown;
  clientProgramPrepareRequestOriginalExplanation?: unknown;
  clientProgramAdoptRequestProgramWithExplanation?: unknown;
  clientProgramCaptureRequestOriginalExplanation?: unknown;
  clientProgramOriginalExplanationPlanWire?: unknown;
  clientProgramOriginalExplanationFactsWire?: unknown;
  clientProgramReturnRequestOriginalExplanation?: unknown;
  clientProgramReturnOriginalExplanationCapture?: unknown;
}>;
type OriginalJournal = Readonly<{supportsOriginalExplanation?: () => unknown}>;
type Limits = Readonly<{maxWireBytes: number; maxNodes: number; maxDepth: number}>;
type Contracts = Readonly<{moon: Runtime; admission: unknown}>;
type Explanation = {
  preparation?: unknown; scope?: unknown; definition?: unknown; journal?: OriginalJournal;
  factsWire?: string; contextWire?: string; invocationTemplateWire?: string; plan?: unknown;
  offered: boolean; acknowledged: boolean; returning: boolean; databaseClosed: boolean; dispatchReady: boolean;
  methods: Readonly<{adopt: Callback; returnPreparation: (...args: unknown[]) => unknown;
    returnCapture: (...args: unknown[]) => unknown}>;
};
export type OrdinarySourceRequestState = RequestPreparationState & {
  context: Readonly<{runtime: Runtime; retainedRelationOutput: boolean}> &
    Parameters<typeof assertRequestPreparationControl>[0];
  requiresQueryTime?: boolean; phase?: unknown; originalExplanation?: Explanation; staticExplanationDelivery?: unknown;
  staticPlanRead?: boolean; staticModelOccurrences?: unknown; staticModelExecutions?: unknown; staticModelGraphs?: unknown;
};
type State = OrdinarySourceRequestState;
type Producer = Pick<SourceProducerCustody, 'finished' | 'preparation' | 'receipt'>;
type RequestProducer = SourceProducerCustody & {kind?: string; body?: object; preparation?: State};
type RequestConnection = Parameters<typeof beginRequestInput>[2];
type OpenParent = (state: State, receipt: object,
  assertCurrent: () => undefined, childrenPending: () => boolean) => unknown;

type Ports = Readonly<{
  originals: Readonly<{installation: Readonly<{sequenceContractOriginal?: Contracts}>}>;
  current(): void; fail(code: string): never; closing: boolean; closed: boolean;
  callbacks: Readonly<{
    preparationContext?(originals: unknown): State['context'] | undefined;
    validator(originals: unknown): void;
  }>;
  receipts: WeakMap<object, RequestProducer>; producers: Set<RequestProducer>;
  runs: Pick<WeakMap<object, OrdinarySourceRun>, 'get'>; liveRuns: Set<OrdinarySourceRun>;
  retainSourceInitializationMaterial(producer: RequestProducer): unknown;
  retainedRunCurrent(run: OrdinarySourceRun): void;
  releaseFinishedProducer(producer: RequestProducer): boolean;
  producerFor(receipt: object): RequestProducer;
}>;

export function createOrdinarySourceRequestCustody(ports: Ports) {
  const {originals, current, fail, callbacks, receipts, producers, runs, liveRuns,
    retainSourceInitializationMaterial, retainedRunCurrent, releaseFinishedProducer, producerFor} = ports;
  function originalTimedInvocation<Value>(state: State, producer: Producer, prepared: unknown, construct: (artifact: unknown) => Value, contracts?: Contracts) {
    if (state.requiresQueryTime !== true) return undefined;
    const moon = state.context.runtime, compile = moon.clientProgramPrepareRequestProgramCompilation;
    const issue = moon.clientProgramRequestProgramModuleIssueCode;
    const reserve = moon.clientProgramReserveRequestQueryTimeInvocation;
    if (typeof construct !== 'function' || typeof compile !== 'function' ||
        typeof reserve !== 'function' || typeof issue !== 'function' || contracts === undefined || contracts.moon !== moon) {
      fail('NodeManagedRunRuntimeUnavailable');
    }
    const assertOriginal = () => {
      current();
      if (producer.finished || producer.preparation !== state || state.prepared !== prepared ||
          originals.installation.sequenceContractOriginal !== contracts || state.parent === undefined || state.holder === undefined ||
          moon.clientProgramPreparationBorrowRead(state.holder) !== prepared) {
        fail('ForeignInstalledSourceProducer');
      }
    };
    assertOriginal();
    const readOriginal = moon.clientProgramRequestProgramCompilationOriginal;
    const retained = typeof readOriginal === 'function'
      ? Reflect.apply(readOriginal, moon, [state.parent, producer.receipt]) : undefined;
    const artifact = retained ?? checkedRequestProgramPreparation(moon,
      Reflect.apply(compile as ModuleCompilation, moon, [state.parent, producer.receipt,
        contracts!.admission, state.context.retainedRelationOutput]), issue as IssueCode);
    assertOriginal();
    checkedRequestProgramPreparation(moon,
      Reflect.apply(reserve as Callback, moon, [state.parent, producer.receipt, artifact]), issue as IssueCode);
    assertOriginal();
    // The typed bridge returns its original Option. Forward it unchanged;
    // JavaScript does not construct or inspect a tuple representation.
    const invocation = construct(artifact);
    assertOriginal();
    return invocation;
  }
  function prepareOriginalExplanation(state: State, producer: Producer, contracts: Contracts, journal: OriginalJournal | undefined, staticPlan?: Limits) {
    const moon = state.context.runtime;
    // Old/unsupported installed profiles keep the existing Plan path. This
    // is selected facility support, not a public switch or capacity grant.
    if (staticPlan === undefined) {
      if (journal === undefined || typeof journal.supportsOriginalExplanation !== 'function' ||
          !journal.supportsOriginalExplanation()) return;
      assertOriginalClientRequestJournal(journal);
    }
    const prepare = moon.clientProgramPrepareRequestOriginalExplanation;
    const adopt = moon.clientProgramAdoptRequestProgramWithExplanation;
    const capture = moon.clientProgramCaptureRequestOriginalExplanation;
    const plan = moon.clientProgramOriginalExplanationPlanWire;
    const facts = moon.clientProgramOriginalExplanationFactsWire;
    const returnPreparation = moon.clientProgramReturnRequestOriginalExplanation;
    const returnCapture = moon.clientProgramReturnOriginalExplanationCapture;
    const readOriginal = moon.clientProgramRequestProgramCompilationOriginal;
    if (typeof prepare !== 'function' || typeof adopt !== 'function' ||
        typeof capture !== 'function' || typeof plan !== 'function' ||
        typeof facts !== 'function' || typeof returnPreparation !== 'function' ||
        typeof returnCapture !== 'function' || typeof readOriginal !== 'function') return;
    if (Reflect.apply(readOriginal, moon, [state.parent, producer.receipt]) === undefined) {
      checkedRequestProgramPreparation(moon,
        moon.clientProgramPrepareRequestProgramCompilation(state.parent, producer.receipt,
          contracts.admission, state.context.retainedRelationOutput),
        moon.clientProgramRequestProgramModuleIssueCode);
    }
    const limits = staticPlan ?? localContractLimits;
    const original = checked(Reflect.apply(prepare, moon, [state.parent, producer.receipt,
      limits.maxWireBytes, limits.maxNodes, limits.maxDepth]));
    if (original === undefined) return;
    // All additional retained wrappers follow the actual working admission.
    // The same per-producer holding owns failure before a Plan/ticket returns.
    state.originalExplanation = Object.seal({preparation: original, scope: undefined,
      factsWire: undefined, offered: false, acknowledged: false, returning: false, databaseClosed: false, dispatchReady: false, journal,
      methods: Object.freeze({adopt, returnPreparation, returnCapture}) as Explanation['methods']});
  }
  function disposeOriginalExplanation(state: State | undefined, decline = false) {
    const original = state?.originalExplanation;
    if (original === undefined) return true;
    if (original.returning) return false;
    if (original.scope !== undefined && original.offered && !original.acknowledged && !original.databaseClosed) {
      // Consume only the actual native close observation before dropping the
      // strong Journal alias. This scalar does not settle semantic uncertainty.
      if (!observeOriginalClientRequestJournalCustody(original.journal).databaseClosed) return false;
      original.databaseClosed = true;
    }
    original.factsWire = undefined;
    if (original.definition !== undefined) {
      original.contextWire = original.invocationTemplateWire = original.plan = undefined;
    }
    original.journal = undefined;
    const moon = state!.context.runtime;
    original.returning = true;
    try {
      if (original.scope !== undefined) {
        checked(original.definition === undefined
          ? Reflect.apply(original.methods.returnCapture, moon, [original.scope])
          : original.methods.returnCapture(original.scope, original.definition, decline));
        original.scope = undefined;
      }
      if (original.preparation !== undefined) {
        checked(Reflect.apply(original.methods.returnPreparation, moon, [original.preparation]));
        original.preparation = undefined;
      }
      state!.originalExplanation = undefined;
      return true;
    } finally {original.returning = false;}
  }
  function cleanupOriginalRequestInput(state: State, retire?: Parameters<typeof cleanupRequestInput>[1]) {
    if (state.staticExplanationDelivery !== undefined) fail('InstalledSourceRunCleanupPending');
    if (!disposeOriginalExplanation(state)) fail('InstalledExplanationAdmissionCleanupPending');
    if (state.staticPlanRead && state.compilationKind === 'effectful') {
      // Static projection issued no submitted/preparation alias. Drop all of
      // its local metadata while the SAME holder still backs them; only the
      // existing abort/return below can acknowledge the original capacity.
      state.staticModelOccurrences = state.staticModelExecutions = state.staticModelGraphs = undefined;
      state.modelGraph = state.prepared = undefined;
    }
    return cleanupRequestInput(state, retire);
  }
  function beginProducer(kind: string | undefined, openParent: OpenParent, requiresParent = false) {
    current();
    // A selected funded context cannot fall back to an unfunded snapshot
    // when its typed capability or installed output mode is unavailable.
    // Resolve it before allocating a producer, including a throwing lookup.
    const context = callbacks.preparationContext === undefined
      ? undefined : callbacks.preparationContext(originals);
    if (requiresParent && context === undefined) fail('NodeLocalPreparationAdmissionUnavailable');
    if (context !== undefined && !requestPreparationAvailable(context)) {
      fail('NodeLocalPreparationAdmissionUnavailable');
    }
    if (context !== undefined) assertRequestPreparationControl(context);
    if (producers.size === 32) fail('InstalledSourceProducerLimit');
    const receipt = Object.freeze({});
    const producer: RequestProducer = {receipt, kind, body: undefined, request: undefined, finished: false, liveRuns: 0, snapshotPublication: undefined, preparation: undefined};
    receipts.set(receipt, producer); producers.add(producer);
    const sourceEnvironment = retainSourceInitializationMaterial(producer);
    // The same Request precedes every SDK snapshot, independent of options.
    // Original Program and Parameters continue to their checked compiler
    // module; no shape scan selects a second preparation protocol.
    if (context !== undefined) {
      const state: State = {context, original: undefined, admission: undefined, parent: undefined,
        prepared: undefined, holder: undefined, adopting: false,
        authoringContextOriginal: undefined,
        originalCheckResult: undefined,
        projectOriginalCheck: Object.getOwnPropertyDescriptor(context.runtime,
          'clientProgramProjectRequestCheckOutcome')?.value};
      producer.preparation = state;
      try {
        if (sourceEnvironment !== undefined &&
            Object.getOwnPropertyDescriptor(context, 'preparedEnvironment')?.value !== sourceEnvironment) {
          fail('ForeignInstalledSourceProducer');
        }
        const assertOriginalCurrent = (): undefined => {
          // Cleanup may continue while the manager is closing. Exact
          // membership/current installation, not raw Prepared, is retained.
          if (ports.closed || receipts.get(receipt) !== producer || producer.preparation !== state) {
            fail('ForeignInstalledSourceProducer');
          }
          const adopted = state.prepared === undefined ? undefined : runs.get(state.prepared as object);
          if (adopted?.producer === producer && adopted.original === state.original &&
              adopted.value !== undefined) retainedRunCurrent(adopted);
          else callbacks.validator(originals);
          // The original external current callback may retire this same
          // input before opening returns. Cheap state fences, not another
          // external current call, preserve the exact original after reentry.
          if (ports.closed || receipts.get(receipt) !== producer || producer.preparation !== state) {
            fail('ForeignInstalledSourceProducer');
          }
        };
        // The same initial Root survives Run adoption. Observe physical
        // children on its existing producer/Run inventory, rather than
        // freezing a no-children answer before those children can exist.
        const childrenPending = () => {
          if (state.staticExplanationDelivery !== undefined) return true;
          for (const run of liveRuns) if (run.producer === producer &&
              run.children.some(child => child.flight !== undefined || !child.closed)) return true;
          return false;
        };
        const accepted = openParent(state, receipt, assertOriginalCurrent, childrenPending);
        if (!accepted) fail('NodeLocalPreparationAdmissionUnavailable');
      } catch (cause) {
        producer.finished = true;
        try {
          cleanupOriginalRequestInput(state);
          producer.preparation = undefined;
          releaseFinishedProducer(producer);
        } catch (cleanupCause) {
          throw Object.assign(new Error('NodeLocalPreparationCleanupPending', {cause}),
            {code: 'NodeLocalPreparationCleanupPending', cleanupPending: true,
              cleanupCause});
        }
        throw cause;
      }
    }
    return receipt;
  }
  return {originalTimedInvocation, prepareOriginalExplanation, disposeOriginalExplanation,
    cleanupOriginalRequestInput, beginProducer, requestInput: {
    assertSourceSnapshotCurrent(receipt: object) {
      current();
      const producer = producerFor(receipt), preparation = producer.preparation;
      if (producer.finished || producer.body !== undefined) fail('ForeignInstalledSourceProducer');
      if (preparation !== undefined) {
        const original = preparation.original;
        if (original === undefined || preparation.adopting ||
            preparation.parent === undefined && preparation.phase === undefined) {
          fail('ForeignInstalledSourceProducer');
        }
        resourceRuntime.assertOrdinaryManagedRunCurrent(original!, receipt);
        if (producer.preparation !== preparation || preparation.original !== original) {
          fail('ForeignInstalledSourceProducer');
        }
      }
      // A current callback may synchronously retire this same producer. Its
      // original receipt/Resource tuple must still own this pre-freeze phase.
      if (ports.closing || ports.closed || receipts.get(receipt) !== producer ||
          producer.finished || producer.body !== undefined) fail('ForeignInstalledSourceProducer');
    },
    beforeSourceSnapshot(kind: string, input: unknown, options: unknown, originalConnection: RequestConnection) {
      return beginProducer(kind, (state, receipt, assertCurrent, childrenPending) =>
        beginRequestInput(state, receipt, originalConnection, assertCurrent, childrenPending));
    },
    beforeHttpRequestBody() {
      return beginProducer(undefined, (state, receipt, assertCurrent, childrenPending) =>
        beginHttpRequestInput(state, receipt, assertCurrent, childrenPending), true);
    },
    reserveHttpRequestBody(receipt: object, bytes: number, chunks: number, quantum: number, wireLimit: number) {
      current();
      const producer = producerFor(receipt), state = producer.preparation;
      if (producer.finished || producer.body !== undefined || state?.parent === undefined ||
          state.snapshotting || state.snapshot !== undefined) fail('ForeignInstalledSourceProducer');
      const moon = state!.context.runtime;
      checked(Reflect.apply(moon.clientProgramReserveRequestHttpInput as (...args: unknown[]) => unknown, moon,
        [state!.parent, receipt, bytes, chunks, quantum, wireLimit]));
    },
    prepareHttpRequestJson(receipt: object, wire: string) {
      current();
      const producer = producerFor(receipt), state = producer.preparation;
      if (producer.finished || producer.body !== undefined || state?.parent === undefined ||
          state.snapshotting || state.snapshot !== undefined || typeof wire !== 'string') {
        fail('ForeignInstalledSourceProducer');
      }
      const moon = state!.context.runtime;
      checked(Reflect.apply(moon.clientProgramPrepareRequestHttpJson as (...args: unknown[]) => unknown, moon,
        [state!.parent, receipt, wire]));
    },
    bindHttpRequestKind(receipt: object, kind: string, connection: RequestConnection) {
      current();
      const producer = producerFor(receipt), state = producer.preparation;
      if (producer.finished || producer.kind !== undefined || producer.body !== undefined ||
          state?.parent === undefined || state.snapshotting || state.snapshot !== undefined ||
          !['program', 'aql'].includes(kind) || !Object.isFrozen(connection) ||
          !['local', 'remote'].includes(connection.mode) || connection.owner !== connection.mode ||
          !Array.isArray(connection.consentRefs) || !Array.isArray(connection.runners)) {
        fail('ForeignInstalledSourceProducer');
      }
      producer.kind = kind;
    },
  }};

}
