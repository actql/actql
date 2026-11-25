import {checked} from '../host-common/runtime-result.mjs';
import type {SynchronousRuntimeData} from '../host-common/runtime-result.mjs';
import {rejectInstalledEffectPlan as fail} from './installed-effect-recipe.mjs';

type CoreResult = Extract<SynchronousRuntimeData, object>;
type Constructor<Arguments extends unknown[]> = (...args: Arguments) => CoreResult;
type OperationDemand = [prepared: unknown, stageIndex: number, effectId: string,
  memberExtents: readonly unknown[], rowExtents: readonly unknown[]];
type SourceArguments = [queryContract: string, evidenceContract: string,
  transferBytes: readonly bigint[], executionBytes: readonly bigint[]];
type ContractArguments = [installedContracts: unknown, values: string, fragment: string | undefined,
  ordered: string | undefined, demands: readonly unknown[]];
type PlanOriginal = [prepared: unknown, identity: unknown];
type DeclaredSource = [declarations: readonly unknown[]];
type ProviderSource = [declarations: readonly unknown[], providers: readonly unknown[]];
type PlanInputs = [...SourceArguments, ...ContractArguments];
type ModelInputs = [model: unknown, components: readonly unknown[], queryTime: unknown];

type Runtime = Readonly<{
  clientProgramEffectAcquisitionCount(prepared: unknown): number;
  clientProgramInstalledEffectOperationDemandPrepare?: Constructor<OperationDemand>;
  clientProgramInstalledEffectOperationDemandWithControlsPrepare?: Constructor<[...OperationDemand, controlsPerRow: unknown]>;
  clientProgramInstalledEffectManagedSourcePlanPrepare?: Constructor<[...PlanOriginal, inputs: readonly unknown[],
    ...PlanInputs, queryTime: unknown, model: unknown, components: readonly unknown[], content: unknown]>;
  clientProgramInstalledEffectManagedPlanPrepare?: Constructor<[...PlanOriginal, ...DeclaredSource, ...PlanInputs]>;
  clientProgramInstalledEffectManagedPlanPrepareAtQueryTime?: Constructor<[...PlanOriginal, queryTime: unknown,
    ...DeclaredSource, ...PlanInputs]>;
  clientProgramInstalledEffectManagedProviderPlanPrepare?: Constructor<[...PlanOriginal, ...ProviderSource, ...PlanInputs]>;
  clientProgramInstalledEffectManagedProviderPlanPrepareAtQueryTime?: Constructor<[...PlanOriginal, queryTime: unknown,
    ...ProviderSource, ...PlanInputs]>;
  clientProgramInstalledEffectModelManagedPlanPrepare?: Constructor<[...PlanOriginal, ...DeclaredSource, ...PlanInputs, ...ModelInputs]>;
  clientProgramInstalledEffectModelManagedProviderPlanPrepare?: Constructor<[...PlanOriginal, ...ProviderSource,
    ...PlanInputs, ...ModelInputs]>;
  clientProgramInstalledEffectContentManagedPlanPrepare?: Constructor<[...PlanOriginal, ...ProviderSource,
    ...PlanInputs, content: unknown, queryTime: unknown]>;
  clientProgramInstalledEffectContentModelManagedPlanPrepare?: Constructor<[...PlanOriginal, ...ProviderSource,
    ...PlanInputs, ...ModelInputs, content: unknown]>;
}>;
type SourceInputs = Readonly<{
  queryContract: string;
  evidenceContract: string;
  transferBytes: readonly bigint[];
  executionBytes: readonly bigint[];
}> & (
  Readonly<{inputs: readonly unknown[]; declarations?: never; providers?: never}> |
  Readonly<{inputs?: never; declarations: readonly unknown[]; providers?: readonly unknown[]}>
);
type DemandRecipe = Readonly<{
  memberOperations: readonly Readonly<{extent: unknown}>[];
  rowOperations: readonly Readonly<{extent: unknown}>[];
  controlsPerRow?: unknown;
}>;
type ManagedPlanOptions<Member extends Readonly<{effectId: string}>> = Readonly<{
  moon: Runtime;
  facts: Readonly<{prepared: unknown; identity: unknown; queryTimePreparation?: unknown}>;
  inputs: Readonly<{
    installedContracts: unknown; values: string; fragment?: string; ordered?: string;
    sourceInputs?: SourceInputs; modelDemand?: unknown; modelComponents?: readonly unknown[];
    contentPreparation?: unknown;
  }>;
  unit: Readonly<{stageIndex: number}>;
  members: readonly Member[];
  recipeFor(member: Member): DemandRecipe | undefined;
}>;

export function prepareInstalledEffectManagedPlan<Member extends Readonly<{effectId: string}>>(
  {moon, facts, inputs, unit, members, recipeFor}: ManagedPlanOptions<Member>): unknown {
  if (facts?.prepared === undefined || facts.identity === undefined ||
      inputs?.installedContracts === undefined ||
      typeof inputs.values !== 'string') {
    fail('InstalledEffectOperationDemandUnavailable');
  }
  // The installing Source supplies its original declaration/reader bounds;
  // Core constructs the acquisition once on this same checked Plan. Missing
  // inputs cannot select a zero-Source or ordinary-purpose replacement.
  const count = moon.clientProgramEffectAcquisitionCount(facts.prepared);
  const sources = inputs.sourceInputs;
  const nativeInputs = sources?.inputs;
  if (!Number.isSafeInteger(count) || count < 0 ||
      count !== 0 && sources === undefined || sources !== undefined &&
      (sources === null || typeof sources !== 'object' || !Object.isFrozen(sources) ||
       !(['transferBytes', 'executionBytes'] as const).every(name =>
         Array.isArray(sources[name]) && Object.isFrozen(sources[name]) && sources[name].length === count) ||
       (nativeInputs === undefined
         ? !Array.isArray(sources.declarations) || !Object.isFrozen(sources.declarations) || sources.declarations.length !== count
         : !Array.isArray(nativeInputs) || !Object.isFrozen(nativeInputs) || nativeInputs.length !== count ||
           sources.declarations !== undefined || sources.providers !== undefined) ||
       sources.providers !== undefined && (!Array.isArray(sources.providers) ||
         !Object.isFrozen(sources.providers) || sources.providers.length !== count) ||
       typeof sources.queryContract !== 'string' || typeof sources.evidenceContract !== 'string' ||
       count !== 0 && (!sources.queryContract || !sources.evidenceContract) ||
       [...sources.transferBytes, ...sources.executionBytes].some(value => typeof value !== 'bigint' || value < 0n))) {
    fail('InstalledEffectPlanInputsUnavailable');
  }
  if (inputs.modelDemand !== undefined && (!Array.isArray(inputs.modelComponents) ||
      !Object.isFrozen(inputs.modelComponents) || inputs.modelComponents.length === 0)) {
    fail('InstalledEffectPlanInputsUnavailable');
  }
  const demands = members.map(member => {
    const recipe = recipeFor(member);
    if (recipe === undefined) fail('InstalledEffectOperationDemandUnavailable');
    const construct = recipe.controlsPerRow === undefined
      ? moon.clientProgramInstalledEffectOperationDemandPrepare
      : moon.clientProgramInstalledEffectOperationDemandWithControlsPrepare;
    if (typeof construct !== 'function') fail('InstalledEffectOperationDemandUnavailable');
    return checked(Reflect.apply(construct, moon, [facts.prepared, unit.stageIndex, member.effectId,
      recipe.memberOperations.map(entry => entry.extent), recipe.rowOperations.map(entry => entry.extent),
      ...(recipe.controlsPerRow === undefined ? [] : [recipe.controlsPerRow])]));
  });
  const model = inputs.modelDemand !== undefined, providers = sources?.providers;
  const content = inputs.contentPreparation;
  if (nativeInputs !== undefined) {
    const construct = moon.clientProgramInstalledEffectManagedSourcePlanPrepare;
    if (typeof construct !== 'function') fail('InstalledEffectPlanRuntimeUnavailable');
    return checked(Reflect.apply(construct, moon, [facts.prepared, facts.identity, nativeInputs,
      sources!.queryContract, sources!.evidenceContract, sources!.transferBytes, sources!.executionBytes,
      inputs.installedContracts, inputs.values, inputs.fragment, inputs.ordered, demands,
      facts.queryTimePreparation, inputs.modelDemand, inputs.modelComponents ?? [], content]));
  }
  const construct = content !== undefined && model ? moon.clientProgramInstalledEffectContentModelManagedPlanPrepare
    : content !== undefined ? moon.clientProgramInstalledEffectContentManagedPlanPrepare : model ? providers === undefined
    ? moon.clientProgramInstalledEffectModelManagedPlanPrepare
    : moon.clientProgramInstalledEffectModelManagedProviderPlanPrepare
    : providers !== undefined ? facts.queryTimePreparation === undefined
      ? moon.clientProgramInstalledEffectManagedProviderPlanPrepare
      : moon.clientProgramInstalledEffectManagedProviderPlanPrepareAtQueryTime
    : facts.queryTimePreparation === undefined
      ? moon.clientProgramInstalledEffectManagedPlanPrepare
      : moon.clientProgramInstalledEffectManagedPlanPrepareAtQueryTime;
  if (typeof construct !== 'function') fail('InstalledEffectPlanRuntimeUnavailable');
  const original = [facts.prepared, facts.identity,
    ...(content !== undefined || model || facts.queryTimePreparation === undefined ? [] : [facts.queryTimePreparation]),
    sources?.declarations ?? [], ...(content !== undefined ? [providers ?? []] : providers !== undefined ? [providers] : []),
    sources?.queryContract ?? '', sources?.evidenceContract ?? '',
    sources?.transferBytes ?? [], sources?.executionBytes ?? [], inputs.installedContracts,
    inputs.values, inputs.fragment, inputs.ordered, demands,
    ...(model ? [inputs.modelDemand, inputs.modelComponents, facts.queryTimePreparation] : []),
    ...(content === undefined ? [] : model ? [content] : [content, facts.queryTimePreparation])];
  // Empty query/evidence strings are unused arguments only for zero Sources;
  // they issue no query contract. Existing Core validates the checked graph.
  return checked(Reflect.apply(construct, moon, original));
}
