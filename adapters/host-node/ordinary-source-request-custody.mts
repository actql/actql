// The same funded Request retains compilation and Explanation custody until
// the original admission's children can return. This path never grants a Run.
import {checked} from '../host-common/runtime-result.mjs';
import {cleanupRequestInput} from '../local-node/request-preparation-adapter.mjs';
import {checkedRequestProgramPreparation} from './client-program-preparation.mjs';
import {assertOriginalClientRequestJournal, observeOriginalClientRequestJournalCustody} from './client-request-journal.mjs';
import {localContractLimits} from './local-values-plan.mjs';

import type {RequestPreparationState} from '../local-node/request-preparation-adapter.mjs';
import type {SourceProducerCustody} from './ordinary-source-producer-custody.mjs';

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
  context: Readonly<{runtime: Runtime; retainedRelationOutput: boolean}>;
  requiresQueryTime?: boolean; originalExplanation?: Explanation; staticExplanationDelivery?: unknown;
  staticPlanRead?: boolean; staticModelOccurrences?: unknown; staticModelExecutions?: unknown; staticModelGraphs?: unknown;
};
type State = OrdinarySourceRequestState;
type Producer = Pick<SourceProducerCustody, 'finished' | 'preparation' | 'receipt'>;
type Ports = Readonly<{
  originals: Readonly<{installation: Readonly<{sequenceContractOriginal?: Contracts}>}>;
  current(): void; fail(code: string): never;
}>;

export function createOrdinarySourceRequestCustody({originals, current, fail}: Ports) {
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
  return {originalTimedInvocation, prepareOriginalExplanation, disposeOriginalExplanation, cleanupOriginalRequestInput};
}
