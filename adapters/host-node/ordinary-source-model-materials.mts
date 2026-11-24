// Preserve the original funded Request through Model material construction.
// Recovery has the same current checks and no new provider or compiler path.
import type {checkedRequestProgramPreparation as checkProgram} from './client-program-preparation.mjs';

type WireAt = (index: number) => string;
type Definition = Readonly<{wire: string}>;
type SavedOriginal = Readonly<{materialsWire: string; resultPolicyOriginal: Readonly<{wire: string}>}>;
type Restored = Readonly<{prepared: object; compiled: object; graph: object; runDefinition: Definition}>;
type Runtime = Parameters<typeof checkProgram>[0] & Readonly<{
  clientProgramPreparationBorrowRead?(holder: unknown): unknown;
  clientProgramRequestProgramModuleIssueCode?: Parameters<typeof checkProgram>[2];
  clientProgramPrepareRequestModelContractMaterials?(parent: unknown, receipt: object,
    count: number, wireAt: WireAt, containers: number): unknown;
  clientProgramPrepareRequestModelProviderBinding?(parent: unknown, receipt: object,
    providerId: string, installation: string, contract: string, configuration: string): unknown;
  clientProgramModelProviderBinding?(providerId: string, installation: string, contract: string, configuration: string): unknown;
}>;
type RecoveryControl = Readonly<{
  reserveCheckedClientRequestModelRecoveryMaterials?(parent: unknown, receipt: object,
    request: object, definition: Definition, count: number, wireAt: WireAt, containers: number): unknown;
}>;
type Recovery = {
  request: object; definition: Definition; restored?: Restored; original?: SavedOriginal;
  assertCurrent(): void; model?: Readonly<{control: RecoveryControl}>;
};
type DomainState = {preparing?: boolean; preparationFailed?: boolean; preparationFailure?: unknown};
export type OrdinaryModelMaterialsState = DomainState & {
  parent?: unknown; context: Readonly<{runtime: Runtime}>; recovery?: Recovery;
  prepared?: object; compilationKind?: string; compilationFamily?: string;
  holder?: unknown; inventoryHolder?: unknown; adopting?: boolean; modelCompilation?: unknown;
  modelProviderBinding?: unknown; modelGraph?: unknown;
  effectBorrowMethods?: Readonly<{clientProgramEffectPreparationInputRead?(holder: unknown): unknown}>;
};
type State = OrdinaryModelMaterialsState;
type Producer = Readonly<{receipt: object; finished?: boolean; preparation?: State}>;
type Ports = Readonly<{
  current(): void; producerForRequest(request: object): Producer | undefined;
  fail(code: string): never; checked(value: unknown): unknown;
  checkedRequestProgramPreparation: typeof checkProgram;
  runtimeCore(runtime: Runtime): Readonly<{publicationControl: RecoveryControl}>;
}>;

export function constructRequestDomain<Value>(state: DomainState, construct: () => Value) {
  state.preparing = true;
  try {return construct();}
  catch (cause) {
    state.preparationFailed = true; state.preparationFailure = cause;
    throw cause;
  } finally {state.preparing = false;}
}

export function createOrdinarySourceModelMaterials({current, producerForRequest, fail, checked, checkedRequestProgramPreparation, runtimeCore}: Ports) {
  function reserveModelRecovery(producer: Producer, state: State, count: number, wireAt: WireAt, containers: number) {
    if (state.recovery === undefined || producer.finished || state.preparing || state.adopting ||
        typeof wireAt !== 'function') fail('ForeignInstalledSourceProducer');
    const moon = state.context.runtime;
    const recovery = state.recovery!;
    const control = recovery.model?.control ?? runtimeCore(moon).publicationControl;
    const reserve = control.reserveCheckedClientRequestModelRecoveryMaterials;
    if (typeof reserve !== 'function') fail('NodeManagedRunRuntimeUnavailable');
    try {
      Reflect.apply(reserve!, control, [state.parent, producer.receipt,
        recovery.request, recovery.definition, count, wireAt, containers]);
      current();
      if (producer.finished || producer!.preparation !== state || state.recovery !== recovery) fail('ForeignInstalledSourceProducer');
      recovery.assertCurrent();
      if (producer.finished || producer!.preparation !== state || state.recovery !== recovery) fail('ForeignInstalledSourceProducer');
    } catch (cause) {
      state.preparationFailed = true; state.preparationFailure = cause;
      throw cause;
    }
  }
  const restoreModelOriginal = {
    restoreModelOriginal(request: object, original: SavedOriginal, definition: Definition, identity: object,
      construct: (parent: unknown, receipt: object) => Restored) {
      current();
      const producer = producerForRequest(request), state = producer?.preparation;
      if (state?.preparationFailed) throw state.preparationFailure;
      if (state?.recovery === undefined || state.recovery.restored !== undefined ||
          state.recovery.definition !== definition || state.recovery.request !== identity ||
          typeof construct !== 'function') fail('ForeignInstalledSourceProducer');
      const recovery = state!.recovery!;
      reserveModelRecovery(producer!, state!, 3, index => index === 0 ? original.materialsWire
        : index === 1 ? original.resultPolicyOriginal.wire : definition.wire, 4);
      // Retain the SAME already-funded material record before the restored
      // owner constructor/current can fail. Later metadata construction uses
      // this immutable original, never a recompiled/current Source surrogate.
      recovery.original = original;
      return constructRequestDomain(state!, () => {
        // The fourth fixed container covers the returned originals pair and
        // its retained authoring alias. It is not another material/Root.
        const restored = construct(state!.parent, producer!.receipt);
        if (restored?.runDefinition !== definition || restored.prepared === undefined ||
            restored.compiled === undefined || restored.graph === undefined) fail('ForeignInstalledSourceProducer');
        recovery.restored = restored;
        state!.prepared = restored.prepared;
        current();
        if (producer!.finished || producer!.preparation !== state || state!.recovery !== recovery) fail('ForeignInstalledSourceProducer');
        recovery.assertCurrent();
        if (producer!.finished || producer!.preparation !== state || state!.recovery !== recovery) fail('ForeignInstalledSourceProducer');
        return restored;
      });
    }
  }.restoreModelOriginal;
  return {reserveModelRecovery, restoreModelOriginal, modelMaterials: {
    prepareModelMaterials(prepared: object, request: object, count: number, wireAt: WireAt, containerCount: number) {
      current();
      const producer = producerForRequest(request), state = producer?.preparation;
      if (state?.preparationFailed) throw state.preparationFailure;
      if (state?.recovery !== undefined) {
        if (state.recovery.restored?.prepared !== prepared || state.prepared !== prepared) fail('ForeignInstalledSourceProducer');
        try {return reserveModelRecovery(producer!, state!, count, wireAt, containerCount);}
        catch (cause) {state.preparationFailed = true; state.preparationFailure = cause; throw cause;}
      }
      const effectful = state?.compilationKind === 'effectful' && state.effectBorrowMethods !== undefined;
      if (state === undefined || state.prepared !== prepared || !effectful && state.compilationFamily !== 'model' ||
          state.holder === undefined || state.inventoryHolder !== undefined || state.adopting ||
          state.preparing || state.modelCompilation !== undefined || typeof wireAt !== 'function') fail('ForeignInstalledSourceProducer');
      const moon = state!.context.runtime;
      const readOriginal = effectful ? state!.effectBorrowMethods!.clientProgramEffectPreparationInputRead
        : moon.clientProgramPreparationBorrowRead;
      if (typeof readOriginal !== 'function' || Reflect.apply(readOriginal!, moon, [state!.holder]) !== prepared) {
        fail('ForeignInstalledSourceProducer');
      }
      const prepare = moon.clientProgramPrepareRequestModelContractMaterials;
      const issue = moon.clientProgramRequestProgramModuleIssueCode;
      if (typeof prepare !== 'function' || typeof issue !== 'function') fail('NodeManagedRunRuntimeUnavailable');
      return constructRequestDomain(state!, () => {
        checkedRequestProgramPreparation(moon, Reflect.apply(prepare!, moon,
          [state!.parent, producer!.receipt, count, wireAt, containerCount]), issue);
        current();
        if (producer!.finished || producer!.preparation !== state || state!.prepared !== prepared ||
            Reflect.apply(readOriginal!, moon, [state!.holder]) !== prepared) fail('ForeignInstalledSourceProducer');
      });
    },
    prepareModelBinding(prepared: object, request: object, providerId: string, installation: string,
      contract: string, configuration: string) {
      current();
      const producer = producerForRequest(request), state = producer?.preparation;
      if (state?.preparationFailed) throw state.preparationFailure;
      if (state?.recovery !== undefined) {
        if (state.recovery.restored?.prepared !== prepared || state.prepared !== prepared) {
          fail('ForeignInstalledSourceProducer');
        }
        // A restored Program can contain several original Model occurrences.
        // Each binding reserves its own materials on this same recovery parent;
        // an earlier occurrence's binding is not a foreign preparation.
        const recovery = state.recovery;
        reserveModelRecovery(producer!, state!, 3,
          index => index === 0 ? installation : index === 1 ? contract : configuration, 3);
        return constructRequestDomain(state!, () => {
          state.modelProviderBinding = checked(state.context.runtime.clientProgramModelProviderBinding!(
            providerId, installation, contract, configuration));
          current();
          if (producer!.finished || producer!.preparation !== state || state.recovery !== recovery) fail('ForeignInstalledSourceProducer');
          recovery.assertCurrent();
          if (producer!.finished || producer!.preparation !== state || state.recovery !== recovery) fail('ForeignInstalledSourceProducer');
          return state!.modelProviderBinding;
        });
      }
      const effectful = state?.compilationKind === 'effectful' && state.effectBorrowMethods !== undefined;
      if (state === undefined || state.prepared !== prepared || !effectful && state.compilationFamily !== 'model' ||
          state.holder === undefined || state.inventoryHolder !== undefined || state.adopting ||
          state.preparing || state.modelCompilation !== undefined ||
          state.modelProviderBinding !== undefined && state.modelGraph === undefined) fail('ForeignInstalledSourceProducer');
      const moon = state!.context.runtime;
      const readOriginal = effectful ? state!.effectBorrowMethods!.clientProgramEffectPreparationInputRead
        : moon.clientProgramPreparationBorrowRead;
      if (typeof readOriginal !== 'function' || Reflect.apply(readOriginal!, moon, [state!.holder]) !== prepared) {
        fail('ForeignInstalledSourceProducer');
      }
      const prepare = moon.clientProgramPrepareRequestModelProviderBinding;
      const issue = moon.clientProgramRequestProgramModuleIssueCode;
      if (typeof prepare !== 'function' || typeof issue !== 'function') fail('NodeManagedRunRuntimeUnavailable');
      return constructRequestDomain(state!, () => {
        state!.modelProviderBinding = checkedRequestProgramPreparation(moon, Reflect.apply(prepare!, moon,
          [state!.parent, producer!.receipt, providerId, installation, contract, configuration]), issue);
        current();
        if (producer!.finished || producer!.preparation !== state || state!.prepared !== prepared ||
            Reflect.apply(readOriginal!, moon, [state!.holder]) !== prepared) fail('ForeignInstalledSourceProducer');
        return state!.modelProviderBinding;
      });
    },
  }};
}
