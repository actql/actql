// Select the bounded checked acquisitions from an inert installation inventory.
// This owns no provider work, authorization or continuation identity.
import {checked} from '../host-common/runtime-result.mjs';
import type {SynchronousRuntimeData} from '../host-common/runtime-result.mjs';
import {runtimeField} from '../host-common/compiler-binding.generated.mjs';
import {installedSourceFor} from './installed-source.mjs';
import {prepareOriginalSourceQuery} from './original-query-preparation.mjs';


type CoreResult = Extract<SynchronousRuntimeData, object>;
type QueryPreparation = Parameters<typeof prepareOriginalSourceQuery>[0];
type Registry = QueryPreparation['registry'];
type Coordinate = readonly [stage: number, input: number, sourceSlot: number, computeTask: number];
type CoordinatesRuntime = Readonly<{
  clientProgramEffectAcquisitionCount(prepared: unknown): number;
  clientProgramInstalledEffectManagedPlanSourceCoordinates?(plan: unknown, prepared: unknown, request: unknown): CoreResult;
  clientProgramEffectDirectSourceCoordinates?(prepared: unknown): CoreResult;
}>;
type InputRuntime = CoordinatesRuntime & Readonly<{
  clientProgramSelectInstalledEffectSourceInput(prepared: unknown, request: unknown, stage: number, input: number): CoreResult;
  clientProgramSelectedSourceInputKind(selection: unknown): string;
  clientProgramSelectedSourceInputRef(selection: unknown): string | undefined;
}>;
type PlanRuntime = InputRuntime & Readonly<{
  clientProgramInstalledEffectRowSourceInputPrepare?(declaration: unknown, provider: unknown, inputLimits?: unknown): CoreResult;
  clientProgramInstalledEffectDuckDBSourceInputPrepare?(sourceRef: string, schema: string, table: string,
    queryContract: string, evidenceContract: string, twoReceiptContract: string): CoreResult;
}>;
type AcquiredRuntime = InputRuntime & QueryPreparation['moon'] & Readonly<{
  clientProgramInstalledEffectManagedPlanSource(plan: unknown, task: number): CoreResult;
  clientProgramQueryRequirementSourceRef(requirement: unknown): string;
  clientProgramInstalledEffectManagedOperationPlan(run: unknown, prepared: unknown, request: unknown): CoreResult;
  clientProgramInstalledEffectManagedPlanWholeSource(plan: unknown, task: number): CoreResult;
  clientProgramInstalledEffectManagedDuckDBCapture(run: unknown, prepared: unknown, request: unknown, task: number): CoreResult;
  clientProgramWholeSourceFacts(acquisition: unknown): readonly [sourceRef: string, ...rest: unknown[]] | undefined;
}>;
type LedgerContributions = [capacities: readonly unknown[], transferBytes: readonly bigint[],
  executionBytes: readonly bigint[], installedContracts: Registry, values: string,
  fragment: string | undefined, ordered: string | undefined];
type LedgerRuntime = CoordinatesRuntime & Readonly<{
  clientProgramInstalledEffectManagedRunPrepareLedger?(run: unknown, prepared: unknown, request: unknown,
    ...contributions: LedgerContributions): CoreResult;
  clientProgramPrepareMultiCapturedEffectInstalledLedger?(prepared: unknown, ...contributions: LedgerContributions): unknown;
}>;
type SourceCapacity = Readonly<{capacity: unknown; transferBytes: bigint; executionBytes: bigint; managedRun?: unknown}>;
type Adapter = Readonly<{
  admitsSource(sourceRef: string): boolean;
  realizationKey: string;
  prepare?: unknown;
  open?: unknown;
  supportsRetainedRelationOutput?: boolean;
  ledgerCapacity?(preparedSource: unknown): SourceCapacity;
}>;
type SourceProfile<Member extends Adapter> = Parameters<typeof installedSourceFor<Member>>[0];
type NativePlanSource = Readonly<{
  sourceRef: string;
  schema: string;
  table: string;
  contracts: readonly [query: string, evidence: string, twoReceipt: string];
}>;
type PlanInput = Readonly<{
  nativeSource?: NativePlanSource;
  declaration?: unknown;
  provider?: unknown;
  inputLimits?: unknown;
  transferBytes: bigint;
  executionBytes: bigint;
}>;
type PlanOptions<Member extends Adapter> = Readonly<{
  moon: PlanRuntime; preparedEffect: unknown; requestIdentity: unknown; sourceProfile: SourceProfile<Member>;
  queryContract: string; evidenceContract: string;
}>;
type Occurrence = Readonly<{stage: number; input: number; task: number; computeTask?: number}>;
type Selection<Member extends Adapter> = Readonly<{
  adapter: Member; sourceKind: 'query' | 'whole-input'; occurrence: Occurrence;
}>;
type UnsupportedSelection<Member extends Adapter> = Readonly<{
  reason: 'unsupported-realization'; count: number; sourceRef: string | undefined; adapter: Member;
  realization: string | undefined; previousRef: string | undefined; previousAdapter: Member | undefined;
}>;
type AcquiredOptions<Member extends Adapter> = Readonly<{
  moon: AcquiredRuntime; preparedEffect: unknown; sourceProfile: SourceProfile<Member>;
  registry?: Registry; values?: string; fragment?: string; ordered?: string; queryTimePreparation?: unknown;
  requestIdentity?: unknown; managedPlan?: unknown; managedRun?: unknown;
  onUnsupportedSelection?(error: TypeError, detail: UnsupportedSelection<Member>): unknown;
}>;
type LedgerOptions = Readonly<{
  moon: LedgerRuntime; preparedEffect: unknown;
  sources: readonly Readonly<{adapter: Adapter; preparedSource: unknown; occurrence: Occurrence}>[];
  registry: Registry; values: string; fragment?: string; ordered?: string; requestIdentity?: unknown;
}>;

function effectSourceInputs(moon: CoordinatesRuntime, preparedEffect: unknown, managedPlan?: unknown, requestIdentity?: unknown): readonly Coordinate[] {
  const planned = managedPlan !== undefined && requestIdentity !== undefined;
  const count = planned ? undefined : moon.clientProgramEffectAcquisitionCount(preparedEffect);
  if (!planned && (!Number.isSafeInteger(count) || count! < 0)) throw new TypeError('UnsupportedEffectSourceCount');
  if (count === 0) return [];
  const select = planned ? moon.clientProgramInstalledEffectManagedPlanSourceCoordinates
    : moon.clientProgramEffectDirectSourceCoordinates;
  if (typeof select !== 'function') throw new TypeError('InstalledEffectSourceCoordinatesUnavailable');
  const coordinates = checked(Reflect.apply(select as Function, moon,
    planned ? [managedPlan, preparedEffect, requestIdentity] : [preparedEffect]));
  if (!Array.isArray(coordinates) || !planned && coordinates.length !== count) {
    throw new TypeError('InvalidInstalledEffectSourceCoordinates');
  }
  const ports = new Set();
  for (const [slot, value] of coordinates.entries()) {
    if (!Array.isArray(value) || value.length !== 4 ||
        value.some(number => !Number.isSafeInteger(number) || number < 0) || value[2] !== slot) {
      throw new TypeError('InvalidInstalledEffectSourceCoordinates');
    }
    const port = `${value[0]}:${value[1]}`;
    if (ports.has(port)) throw new TypeError('InvalidInstalledEffectSourceCoordinates');
    ports.add(port);
  }
  return coordinates as readonly Coordinate[];
}

// Select original installation inputs from the checked Requests before the
// Plan constructs requirements/acquisitions. Repeated occurrences retain
// separate slots even when they borrow the same immutable Source.
export function selectAcquiredEffectPlanInputs<Member extends Adapter>({moon, preparedEffect, requestIdentity,
  sourceProfile, queryContract, evidenceContract}: PlanOptions<Member>) {
  const coordinates = effectSourceInputs(moon, preparedEffect);
  const count = coordinates.length;
  if (count === 0) return undefined;
  const select = moon.clientProgramSelectInstalledEffectSourceInput;
  if (typeof select !== 'function') throw new TypeError('InstalledEffectPlanRuntimeUnavailable');
  const originals: PlanInput[] = [], declarations: unknown[] = [], providers: unknown[] = [],
    transferBytes: bigint[] = [], executionBytes: bigint[] = [];
  let wholeInput = false;
  for (let task = 0; task < count; task++) {
    const [stage, input] = coordinates[task];
    const selected = checked(Reflect.apply(select, moon, [preparedEffect, requestIdentity, stage, input]));
    const kind = moon.clientProgramSelectedSourceInputKind(selected);
    if (kind !== 'query' && kind !== 'whole-input') {
      throw new TypeError('UnsupportedEffectSourceRealization');
    }
    const sourceRef = moon.clientProgramSelectedSourceInputRef(selected);
    const adapter = installedSourceFor(sourceProfile, sourceRef!);
    const prepare = Object.getOwnPropertyDescriptor(adapter, 'managedEffectPlanSelection')?.value;
    if (typeof prepare !== 'function') throw new TypeError('InstalledEffectPlanInputsUnavailable');
    const original = Reflect.apply(prepare, adapter,
      [kind === 'whole-input' ? Object.freeze({preparedEffect}) : undefined, sourceRef]) as PlanInput;
    const native = original?.nativeSource;
    if (kind === 'whole-input' && native !== undefined) throw new TypeError('UnsupportedEffectSourceRealization');
    if (kind === 'whole-input') {
      if (original?.inputLimits === undefined) throw new TypeError('InstalledEffectSourcePolicyUnavailable');
      wholeInput = true;
    }
    if ((original?.declaration === undefined) === (native === undefined) ||
        typeof original.transferBytes !== 'bigint' ||
        typeof original.executionBytes !== 'bigint' || original.transferBytes < 0n || original.executionBytes < 0n) {
      throw new TypeError('InstalledSourceCapacityUnavailable');
    }
    if (native !== undefined && (native === null || !Object.isFrozen(native) ||
        native.sourceRef !== sourceRef || ![native.sourceRef, native.schema, native.table].every(
          value => typeof value === 'string' && value.length > 0) ||
        !Array.isArray(native.contracts) || !Object.isFrozen(native.contracts) || native.contracts.length !== 3 ||
        native.contracts.some(value => typeof value !== 'string' || value.length === 0) ||
        original.provider !== undefined)) throw new TypeError('InstalledSourceCapacityUnavailable');
    originals.push(original);
    declarations.push(original.declaration); providers.push(original.provider);
    transferBytes.push(original.transferBytes); executionBytes.push(original.executionBytes);
  }
  let inputs;
  if (wholeInput || originals.some(value => value.nativeSource !== undefined)) {
    // Nominal inert Source inputs preserve the original occurrence order.
    // Only the SAME Core Plan later prepares each Query/capture once.
    inputs = originals.map(original => {
      const native = original.nativeSource;
      const construct = native === undefined ? moon.clientProgramInstalledEffectRowSourceInputPrepare
        : moon.clientProgramInstalledEffectDuckDBSourceInputPrepare;
      if (typeof construct !== 'function') throw new TypeError('InstalledEffectPlanRuntimeUnavailable');
      return checked(Reflect.apply(construct as Function, moon, native === undefined
        ? [original.declaration, original.provider,
          ...(original.inputLimits === undefined ? [] : [original.inputLimits])]
        : [native.sourceRef, native.schema, native.table, ...native.contracts]));
    });
  } else if (providers.some(value => value === undefined) && providers.some(value => value !== undefined)) {
    throw new TypeError('InstalledSourceCapacityUnavailable');
  }
  return Object.freeze({...(inputs === undefined ? {declarations: Object.freeze(declarations),
    ...(providers[0] === undefined ? {} : {providers: Object.freeze(providers)})}
    : {inputs: Object.freeze(inputs)}),
    queryContract, evidenceContract, transferBytes: Object.freeze(transferBytes),
    executionBytes: Object.freeze(executionBytes)});
}

export function selectAcquiredEffectSources<Member extends Adapter>({moon, preparedEffect, sourceProfile,
  registry, values, fragment, ordered, queryTimePreparation, requestIdentity, managedPlan, managedRun,
  onUnsupportedSelection}: AcquiredOptions<Member>) {
  const coordinates = effectSourceInputs(moon, preparedEffect, managedPlan, requestIdentity);
  const count = coordinates.length;
  const selected: Selection<Member>[] = [];
  let firstRef: string | undefined;
  for (let task = 0; task < count; task++) {
    const [stage, input, sourceSlot, computeTask] = coordinates[task];
    let kind: string = 'query';
    let sourceRef: string | undefined;
    if (requestIdentity !== undefined) {
      // Select the adapter from the original checked Request. Its current
      // native/row getter below verifies the SAME retained Plan requirement.
      const selection = checked(moon.clientProgramSelectInstalledEffectSourceInput(
        preparedEffect, requestIdentity, stage, input));
      kind = moon.clientProgramSelectedSourceInputKind(selection);
      if (kind !== 'query' && kind !== 'whole-input') {
        throw new TypeError('UnsupportedEffectSourceRealization');
      }
      sourceRef = moon.clientProgramSelectedSourceInputRef(selection);
    } else {
      const requirement = managedPlan !== undefined
      ? runtimeField(checked(moon.clientProgramInstalledEffectManagedPlanSource(managedPlan, task)), 1)
      : queryTimePreparation === undefined
      ? checked(moon.clientProgramEffectPrepareLocalQueryRequirement!(
        preparedEffect, stage, input, registry!, values!, fragment, ordered))
      : prepareOriginalSourceQuery({moon, preparedEffect, stage, input,
        registry: registry!, values: values!, fragment, ordered, queryTimePreparation, requestIdentity}).requirement;
      sourceRef = moon.clientProgramQueryRequirementSourceRef(requirement);
    }
    const adapter = installedSourceFor(sourceProfile, sourceRef!);
    if (kind === 'whole-input' && adapter.realizationKey !== 'row-source-acquired') {
      throw new TypeError('UnsupportedEffectSourceRealization');
    }
    if (managedPlan !== undefined && managedRun !== undefined) {
      // Native captures have no RowDeclaration/RowAcquisition. Borrow the
      // original nominal capture from this SAME current parent and Plan.
      const plan = checked(moon.clientProgramInstalledEffectManagedOperationPlan(
        managedRun, preparedEffect, requestIdentity));
      if (plan !== managedPlan) throw new TypeError('ForeignInstalledEffectManagedRun');
      const whole = kind === 'whole-input'
        ? checked(moon.clientProgramInstalledEffectManagedPlanWholeSource(managedPlan, task)) : undefined;
      const requirement = kind === 'whole-input' ? undefined : adapter.realizationKey === 'duckdb-acquired'
        ? runtimeField(checked(moon.clientProgramInstalledEffectManagedDuckDBCapture(
          managedRun, preparedEffect, requestIdentity, task)), 0)
        : runtimeField(checked(moon.clientProgramInstalledEffectManagedPlanSource(managedPlan, task)), 1);
      const actualRef = kind === 'whole-input' ? moon.clientProgramWholeSourceFacts(runtimeField(whole, 1))?.[0]
        : moon.clientProgramQueryRequirementSourceRef(requirement);
      if (actualRef !== sourceRef) {
        throw new TypeError('ForeignInstalledEffectManagedRun');
      }
    }
    if (typeof adapter.prepare !== 'function' || typeof adapter.open !== 'function') {
      throw new TypeError('InvalidAcquiredEffectComputationPort');
    }
    const realization = count > 1 ? adapter.realizationKey : undefined;
    if (count > 1 && !['duckdb-acquired', 'row-source-acquired'].includes(realization!)) {
      const error = new TypeError('UnsupportedEffectSourceRealization');
      onUnsupportedSelection?.(error, Object.freeze({reason: 'unsupported-realization', count,
        sourceRef, adapter, realization, previousRef: firstRef, previousAdapter: selected[0]?.adapter}));
      throw error;
    }
    if (selected.length === 0) firstRef = sourceRef;
    // An installation is a factory, not an acquisition occurrence. The same
    // immutable backing may serve several checked ports; each preparation,
    // capture, capacity and cleanup obligation retains its original slot.
    selected.push(Object.freeze({adapter, sourceKind: kind as Selection<Member>['sourceKind'],
      occurrence: Object.freeze({stage, input, task: sourceSlot,
        ...(computeTask === sourceSlot ? {} : {computeTask})})}));
  }
  return Object.freeze(selected);
}

// Mixed installed Sources contribute their own opaque checked capture budgets.
// No row-backed capacity can be passed to a nominal DuckDB configuration API.
export function prepareInstalledAcquiredEffectLedger({moon, preparedEffect, sources,
  registry, values, fragment, ordered, requestIdentity}: LedgerOptions) {
  if (!Array.isArray(sources) || sources.length < 1) {
    throw new TypeError('InstalledMultiSourceCapacityUnavailable');
  }
  const coordinates = effectSourceInputs(moon, preparedEffect);
  if (coordinates.length !== sources.length) throw new TypeError('InstalledMultiSourceCapacityUnavailable');
  const capacities = sources.map(({adapter, preparedSource, occurrence}: LedgerOptions['sources'][number], index) => {
    if (!['duckdb-acquired', 'row-source-acquired'].includes(adapter?.realizationKey) ||
        adapter.supportsRetainedRelationOutput !== true ||
        typeof adapter.ledgerCapacity !== 'function' ||
        occurrence?.stage !== coordinates[index][0] || occurrence.input !== coordinates[index][1] ||
        occurrence.task !== index || (occurrence.computeTask ?? occurrence.task) !== coordinates[index][3]) {
      throw new TypeError('InstalledMultiSourceCapacityUnavailable');
    }
    const capacity = adapter.ledgerCapacity(preparedSource);
    if (capacity?.capacity === undefined || typeof capacity.transferBytes !== 'bigint' ||
        typeof capacity.executionBytes !== 'bigint' || capacity.transferBytes < 0n ||
        capacity.executionBytes < 0n) {
      throw new TypeError('InstalledSourceCapacityUnavailable');
    }
    return capacity;
  });
  const managedRun = capacities[0].managedRun;
  if (capacities.some(value => value.managedRun !== undefined)) {
    if (managedRun === undefined || capacities.some(value => value.managedRun !== managedRun) ||
        requestIdentity === undefined ||
        typeof moon?.clientProgramInstalledEffectManagedRunPrepareLedger !== 'function') {
      throw new TypeError('InstalledEffectOriginalRunUnavailable');
    }
    // Both Source originals and the generated DAG borrow the same already
    // admitted Effect Run. A missing/foreign original cannot fall back to the
    // legacy scalar constructor, even when the reported byte limits match.
    return checked(moon.clientProgramInstalledEffectManagedRunPrepareLedger(
      managedRun, preparedEffect, requestIdentity,
      capacities.map(value => value.capacity), capacities.map(value => value.transferBytes),
      capacities.map(value => value.executionBytes), registry, values, fragment, ordered));
  }
  if (typeof moon?.clientProgramPrepareMultiCapturedEffectInstalledLedger !== 'function') {
    throw new TypeError('InstalledMultiSourceCapacityUnavailable');
  }
  const ledger = moon.clientProgramPrepareMultiCapturedEffectInstalledLedger(
    preparedEffect, capacities.map(value => value.capacity),
    capacities.map(value => value.transferBytes),
    capacities.map(value => value.executionBytes), registry, values, fragment, ordered);
  if (ledger === undefined) throw new Error('InstalledMultiSourceLedgerUnavailable');
  return ledger;
}
