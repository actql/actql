import {types as nodeTypes} from 'node:util';
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeField, runtimeTag} from '../host-common/compiler-binding.generated.mjs';
import type {sourceJsonWireGeometry} from './installed-source-construction-geometry.mjs';

type Amounts = {nodes: bigint; text: bigint; wire: bigint};
type CapacityAmounts = readonly [retainedNodes: bigint, retainedText: bigint, retainedWire: bigint,
  workspaceNodes: bigint, workspaceText: bigint, workspaceWire: bigint];
type CleanupObservation = Readonly<{handle: unknown; method: unknown}>;
type JsonGeometry = ReturnType<typeof sourceJsonWireGeometry>;
type Workspace = Amounts & {
  keepFailed?: boolean;
  json?: {providerIndex: number; projectionIndex: number; quantity: unknown; projection: JsonGeometry};
  retained?: Partial<Amounts>;
  finished?: boolean;
  cleanup?: CleanupObservation;
};
type SourceIo = Readonly<{
  begin(bytes: bigint): unknown;
  charge(operation: unknown, bytes: bigint): unknown;
  uncertain(operation: unknown): unknown;
  finish(operation: unknown): unknown;
}>;
type Material = Amounts & {
  methods: Readonly<Record<MaterialMethod, unknown>>;
  busy: boolean;
  unit: unknown;
  constructors: number;
  contexts: unknown[];
  environment: unknown;
  sourceOriginal: unknown;
  environmentWire: string | undefined;
  phase: 'opening' | 'working' | 'failed' | 'ready' | 'retiring' | 'retired';
  workspaces: Set<Workspace>;
  providers: unknown[];
  inputs: unknown[];
  cleanup: CleanupObservation[];
  capacity: unknown;
  input: unknown;
  ioPending: number;
  io?: SourceIo;
  modelFailure?: {cause: unknown};
  modelRetained?: object;
  modelProviderIndex?: number;
};
type Calls = Readonly<{
  BeginInstalledSourceIo: readonly [capacity: unknown, input: unknown, bytes: bigint];
  ChargeInstalledSourceIo: readonly [operation: unknown, bytes: bigint];
  MarkInstalledSourceIoTransferUncertain: readonly [operation: unknown];
  FinishInstalledSourceIoAfterCleanup: readonly [operation: unknown];
  InstalledSourceConstructionCapacity: CapacityAmounts;
  ComposeInstalledSourceConstructionCapacity: readonly [capacity: unknown, providers: readonly unknown[]];
  ReserveInstalledSourceConstruction: readonly [capacity: unknown, input: unknown, quote: unknown];
  ReconcileInstalledSourceConstruction: readonly [capacity: unknown, input: unknown, quote: unknown];
  InstalledTableConstructionInventory: readonly [nodes: bigint, wire: bigint, strings: bigint, serializerText: bigint];
  InstalledProfileConstructionCapacities: readonly [nodes: bigint, units: bigint];
  InstalledSourceJsonConstructionCapacity: readonly [wireNodes: bigint, wireUnits: bigint, bufferBytes: bigint,
    returnedNodes: bigint, returnedTextBytes: bigint];
  InstalledSourceRetainedConstructionCapacity: readonly [original: unknown];
  InstalledSourceInspectionConstructionCapacity: readonly [parsed: unknown];
  CompleteInstalledSourceMaterial: readonly [capacity: unknown, input: unknown, sourceOriginal: unknown,
    environment: unknown, quote: unknown];
  BorrowInstalledSourceMaterial: readonly [capacity: unknown];
  BorrowedInstalledSourceEnvironment: readonly [holder: unknown, sourceOriginal: unknown];
  ReturnInstalledSourceMaterial: readonly [holder: unknown];
  RetireInstalledSourceMaterial: readonly [capacity: unknown, input: unknown];
  AbortUncontinuedSourceMaterial: readonly [unit: unknown, input: unknown];
}>;
type CallResults = Readonly<Record<keyof Calls, unknown>> & Readonly<{
  InstalledTableConstructionInventory: readonly [nodes: bigint, text: bigint, wire: bigint];
  InstalledProfileConstructionCapacities: readonly [parsed: unknown, projected: unknown];
  ReturnInstalledSourceMaterial: boolean;
  RetireInstalledSourceMaterial: boolean;
  AbortUncontinuedSourceMaterial: boolean;
}>;
type MaterialMethod = keyof Calls | 'TakeHostInitializationSourceCapacity' | 'ContinueInstalledSourceMaterial';
type CoreMethod = (...args: unknown[]) => unknown;
type Runtime = Readonly<Partial<Record<`clientProgram${MaterialMethod}`, unknown>>> & Readonly<{
  clientProgramSerializationCapacityBytes?: unknown;
  clientProgramAccumulateModelTaskConstructionCapacity?: unknown;
}>;
type Owner = {
  readonly moon: Runtime;
  readonly initialPreparation?: unknown;
  readonly restoreDeclaration?: unknown;
  readonly restoreAuthoredDeclaration?: unknown;
  readonly declarationJson?: unknown;
  material?: Material;
};
type ModelOwner = Owner & Readonly<{current(): void}>;
type MaterialPorts = Readonly<{
  fail(code: string): never;
  sourceNativeThen: typeof Promise.prototype.then;
}>;

export function createInstalledSourceMaterialAccounting(
  {fail: reject, sourceNativeThen}: MaterialPorts) {
  const fail: (code: string) => never = reject;

  // Native initialization uses the SAME initial Resource reservation. These are
  // material quantities for existing shared node/text/byte allowances, not a JS
  // Ledger, a profile limit or a second permission/cleanup decision. Small fixed
  // methods and control frames belong to the trusted Host baseline.
  function sourceMaterial(original: Owner): Material | undefined {
    if (original.material !== undefined) return original.material;
    if (original.initialPreparation === undefined) return undefined;
    if (typeof original.restoreDeclaration !== 'function' && typeof original.restoreAuthoredDeclaration !== 'function' ||
        typeof original.declarationJson !== 'function') {
      fail('InstalledSourceInitializationRuntimeUnavailable');
    }
    const methods = Object.freeze({
      TakeHostInitializationSourceCapacity: original.moon.clientProgramTakeHostInitializationSourceCapacity,
      ContinueInstalledSourceMaterial: original.moon.clientProgramContinueInstalledSourceMaterial,
      InstalledSourceConstructionCapacity: original.moon.clientProgramInstalledSourceConstructionCapacity,
      ComposeInstalledSourceConstructionCapacity: original.moon.clientProgramComposeInstalledSourceConstructionCapacity,
      InstalledSourceRetainedConstructionCapacity: original.moon.clientProgramInstalledSourceRetainedConstructionCapacity,
      InstalledSourceJsonConstructionCapacity: original.moon.clientProgramInstalledSourceJsonConstructionCapacity,
      InstalledProfileConstructionCapacities: original.moon.clientProgramInstalledProfileConstructionCapacities,
      InstalledSourceInspectionConstructionCapacity: original.moon.clientProgramInstalledSourceInspectionConstructionCapacity,
      InstalledTableConstructionInventory: original.moon.clientProgramInstalledTableConstructionInventory,
      ReserveInstalledSourceConstruction: original.moon.clientProgramReserveInstalledSourceConstruction,
      ReconcileInstalledSourceConstruction: original.moon.clientProgramReconcileInstalledSourceConstruction,
      CompleteInstalledSourceMaterial: original.moon.clientProgramCompleteInstalledSourceMaterial,
      BorrowInstalledSourceMaterial: original.moon.clientProgramBorrowInstalledSourceMaterial,
      BorrowedInstalledSourceEnvironment: original.moon.clientProgramBorrowedInstalledSourceEnvironment,
      ReturnInstalledSourceMaterial: original.moon.clientProgramReturnInstalledSourceMaterial,
      RetireInstalledSourceMaterial: original.moon.clientProgramRetireInstalledSourceMaterial,
      AbortUncontinuedSourceMaterial: original.moon.clientProgramAbortUncontinuedSourceMaterial,
      BeginInstalledSourceIo: original.moon.clientProgramBeginInstalledSourceIo,
      ChargeInstalledSourceIo: original.moon.clientProgramChargeInstalledSourceIo,
      MarkInstalledSourceIoTransferUncertain: original.moon.clientProgramMarkInstalledSourceIoTransferUncertain,
      FinishInstalledSourceIoAfterCleanup: original.moon.clientProgramFinishInstalledSourceIoAfterCleanup,
    });
    for (const [name, fn] of Object.entries(methods)) {
      if ((name === 'ComposeInstalledSourceConstructionCapacity' || name === 'InstalledSourceRetainedConstructionCapacity' ||
          name === 'InstalledSourceJsonConstructionCapacity' || name === 'InstalledProfileConstructionCapacities' ||
          name === 'InstalledSourceInspectionConstructionCapacity' || name === 'InstalledTableConstructionInventory') && fn === undefined) continue;
      if (typeof fn !== 'function') fail('InstalledSourceInitializationRuntimeUnavailable');
    }
    const material: Material = {methods, input: undefined, unit: undefined, capacity: undefined,
      phase: 'opening', busy: false, ioPending: 0, constructors: 0,
      nodes: 0n, text: 0n, wire: 0n, inputs: [], providers: [], contexts: [], cleanup: [], workspaces: new Set(),
      environment: undefined, sourceOriginal: undefined, environmentWire: undefined};
    // Retain before the one-shot take or continuation can call the original
    // current fence. A failed continuation still owns the uncontinued pair.
    original.material = material;
    try {
      const pair = checked(Reflect.apply(methods.TakeHostInitializationSourceCapacity as CoreMethod,
        original.moon, [original.initialPreparation]));
      material.input = runtimeField(pair, 0); material.unit = runtimeField(pair, 1);
      material.capacity = checked(Reflect.apply(methods.ContinueInstalledSourceMaterial as CoreMethod,
        original.moon, [material.unit, material.input]));
      material.phase = 'working';
    } catch (cause) {material.phase = 'failed'; throw cause;}
    return material;
  }

  function sourceCall<Name extends keyof Calls>(original: Owner, material: Material, name: Name,
    args: Calls[Name]): CallResults[Name] {
    if (material.busy) fail('InstalledSourceInitializationReentry');
    if (typeof material.methods?.[name] !== 'function') fail('InstalledSourceInitializationRuntimeUnavailable');
    material.busy = true;
    try {return checked(Reflect.apply(material.methods[name], original.moon, args)) as CallResults[Name];}
    catch (cause) {
      // This fixed method name identifies the failed constructor, not its DATA.
      // Preserve the original failure and cleanup carrier even when diagnostics
      // cannot be attached to a frozen/non-Error thrown value.
      try {
        if (cause instanceof Error && !Object.hasOwn(cause, 'installedSourcePhase')) {
          Object.defineProperty(cause, 'installedSourcePhase', {value: name, enumerable: true});
          const issue = Object.getOwnPropertyDescriptor(cause, 'cause')?.value;
          const tag = runtimeTag(issue);
          if (Number.isSafeInteger(tag)) {
            Object.defineProperty(cause, 'installedSourceIssueTag', {value: tag, enumerable: true});
          }
          if (name === 'ReserveInstalledSourceConstruction' && tag === 7) {
            const resource = runtimeField(issue, 0);
            if (Number.isSafeInteger(resource)) {
              Object.defineProperty(cause, 'installedSourceResourceIssue', {value: resource, enumerable: true});
            }
          }
          if (name === 'ReserveInstalledSourceConstruction' &&
              typeof original.moon.clientProgramSerializationCapacityBytes === 'function') {
            const amounts = original.moon.clientProgramSerializationCapacityBytes(args[2]);
            for (const [key, index] of ([['installedSourceRetainedBytes', 0], ['installedSourceExecutionBytes', 1]] as const)) {
              const amount = runtimeField(amounts, index);
              if (typeof amount === 'bigint' && amount >= 0n) {
                Object.defineProperty(cause, key, {value: String(amount), enumerable: true});
              }
            }
          }
        }
      } catch { /* Diagnostics never replace the original failure. */ }
      throw cause;
    }
    finally {material.busy = false;}
  }

  // This is only a bound view of the SAME original Core material. The existing
  // file owner retains its operation tokens and sole physical close/retry duty.
  function sourceIo(original: Owner, material: Material) {
    if (material.io !== undefined) return material.io;
    const io: SourceIo = Object.freeze({
      begin(bytes: bigint) {
        if (this !== io) fail('ForeignInstalledSourceIo');
        if (material.phase !== 'working') fail('InstalledSourceInitializationClosed');
        return sourceCall(original, material, 'BeginInstalledSourceIo', [material.capacity, material.input, bytes]);
      },
      charge(operation: unknown, bytes: bigint) {
        if (this !== io) fail('ForeignInstalledSourceIo');
        return sourceCall(original, material, 'ChargeInstalledSourceIo', [operation, bytes]);
      },
      uncertain(operation: unknown) {
        if (this !== io) fail('ForeignInstalledSourceIo');
        return sourceCall(original, material, 'MarkInstalledSourceIoTransferUncertain', [operation]);
      },
      finish(operation: unknown) {
        if (this !== io) fail('ForeignInstalledSourceIo');
        return sourceCall(original, material, 'FinishInstalledSourceIoAfterCleanup', [operation]);
      },
    });
    material.io = io;
    return io;
  }

  function sourceCapacityQuote(original: Owner, material: Material, values: CapacityAmounts, pendingProvider?: unknown) {
    let base = sourceCall(original, material, 'InstalledSourceConstructionCapacity', values);
    if (material.providers.length === 0 && pendingProvider === undefined) return base;
    if (typeof material.methods.ComposeInstalledSourceConstructionCapacity !== 'function') {
      fail('InstalledSourceInitializationRuntimeUnavailable');
    }
    // A pure pending quote has not entered its native constructor. Fold its
    // fixed singleton before admission without registering ungranted DATA or
    // copying the retained provider population. Failed admitted prefixes stay.
    if (pendingProvider !== undefined) {
      base = sourceCall(original, material, 'ComposeInstalledSourceConstructionCapacity', [base, [pendingProvider]]);
    }
    if (material.providers.length === 0) return base;
    return sourceCall(original, material, 'ComposeInstalledSourceConstructionCapacity', [base, material.providers]);
  }

  function sourceQuote(original: Owner, material: Material, nodes = 0n, text = 0n, wire = 0n) {
    return sourceCapacityQuote(original, material,
      [material.nodes, material.text, material.wire, nodes, text, wire]);
  }

  function releaseFinishedSourceWorkspaces(material: Material) {
    for (const workspace of material.workspaces) {
      if (!workspace.finished || typeof workspace.cleanup?.method !== 'function') continue;
      try {
        const value = Reflect.apply(workspace.cleanup.method, workspace.cleanup.handle, []);
        if (Object.getOwnPropertyDescriptor(value ?? {}, 'pending')?.value === false) {
          material.workspaces.delete(workspace);
        }
      } catch { /* An unknown original cleanup state keeps its full workspace. */ }
    }
  }

  function reserveSource(original: Owner, material: Material, nodes = 0n, text = 0n, wire = 0n,
    workspace?: Workspace, retained?: Partial<Amounts>, pendingProvider?: unknown) {
    if (material.phase !== 'working') fail('InstalledSourceInitializationClosed');
    releaseFinishedSourceWorkspaces(material);
    let activeNodes = nodes, activeText = text, activeWire = wire;
    let retainedNodes = retained?.nodes ?? nodes, retainedText = retained?.text ?? text,
      retainedWire = retained?.wire ?? wire;
    for (const active of material.workspaces) {
      if (active === workspace) continue;
      activeNodes += active.nodes; activeText += active.text; activeWire += active.wire;
      retainedNodes += active.retained?.nodes ?? active.nodes;
      retainedText += active.retained?.text ?? active.text;
      retainedWire += active.retained?.wire ?? active.wire;
    }
    // Every live original constructor overlaps the completed prefix AND all
    // other active/failed native workspaces. Replace only this read's extent,
    // after the same parent has admitted the complete simultaneous quantities.
    const quote = sourceCapacityQuote(original, material,
      [material.nodes + retainedNodes, material.text + retainedText, material.wire + retainedWire,
        activeNodes, activeText, activeWire], pendingProvider);
    sourceCall(original, material, 'ReserveInstalledSourceConstruction',
      [material.capacity, material.input, quote]);
    if (workspace !== undefined) Object.assign(workspace, {nodes, text, wire, retained});
  }

  function reconcileSource(original: Owner, material: Material) {
    releaseFinishedSourceWorkspaces(material);
    if (material.workspaces.size !== 0) {
      // Core reconciliation is retained-only. Until every native child has
      // actually closed, keep the admitted high-water debit instead of shrinking
      // beneath a sibling's buffers or a failed original cleanup.
      reserveSource(original, material);
      return;
    }
    sourceCall(original, material, 'ReconcileInstalledSourceConstruction',
      [material.capacity, material.input, sourceQuote(original, material)]);
  }

  function retainSourceFailure(material: Material, cause: unknown, workspace?: Workspace) {
    // Observe only the existing physical cleanup owner's status. Its original
    // retry remains with installed-host-cleanup; this adds no FD retry engine.
    const handle = Object.getOwnPropertyDescriptor(Object(cause), 'cleanupHandle')?.value;
    let child: CleanupObservation | undefined;
    if (handle !== undefined) {
      const method = Object.getOwnPropertyDescriptor(handle, 'status')?.value;
      child = {handle, method};
    } else if (Object.getOwnPropertyDescriptor(Object(cause), 'cleanupPending')?.value === true) {
      child = {handle: undefined, method: undefined};
    }
    if (child !== undefined) material.cleanup.push(child);
    if (workspace !== undefined) {
      workspace.finished = true;
      workspace.cleanup = child;
      if (child === undefined) material.workspaces.delete(workspace);
    }
  }

  // Invalid asynchronous construction never becomes an admitted projection.
  // Its SAME Source borrow nevertheless remains pending until the actual native
  // computation settles. No later completion repairs the original refusal.
  function requireSynchronousSourceConstruction<Value>(material: Material, value: Value): Value {
    if (!nodeTypes.isPromise(value)) return value;
    material.inputs.push(value);material.ioPending++;
    const settle = (result: unknown, failed: boolean) => {
      try {
        material.inputs.push(result);
        if (failed) retainSourceFailure(material, result);
      } catch {material.cleanup.push({handle: undefined, method: undefined});}
      finally {material.ioPending--;}
    };
    try {
      const joined = Reflect.apply(sourceNativeThen, value,
        [(result: unknown) => settle(result, false), (cause: unknown) => settle(cause, true)]);
      material.inputs.push(joined);
    } catch {
      // Native observation itself failed: retain the pending original borrow.
      material.cleanup.push({handle: undefined, method: undefined});
    }
    fail('InstalledSourceConstructorNotSynchronous');
  }

  function sourceProjectionMethods(projection: object) {
    if (!projection || nodeTypes.isProxy(projection) || !Object.isFrozen(projection)) fail('InvalidInstalledSourceCommandProjection');
    const fields = Object.getOwnPropertyDescriptors(projection);
    if (Reflect.ownKeys(fields).length !== 2 || ['capacity','project'].some(name =>
        !Object.hasOwn(fields[name] ?? {}, 'value') || typeof fields[name].value !== 'function' ||
        nodeTypes.isProxy(fields[name].value) || nodeTypes.isAsyncFunction(fields[name].value))) fail('InvalidInstalledSourceCommandProjection');
    return Object.freeze({capacity: fields.capacity.value as CoreMethod, project: fields.project.value as CoreMethod});
  }

  function freezeSourceProjection<Value>(value: Value): Value {
    // The original JSON graph has already been funded and parsed. Freeze that
    // graph in place; do not emit/reparse or mint a second declaration holder.
    const pending: unknown[] = [value];
    while (pending.length !== 0) {
      const node = pending.pop();
      if (node !== null && typeof node === 'object') {
        for (const child of Object.values(node)) {
          if (child !== null && typeof child === 'object') pending.push(child);
        }
        Object.freeze(node);
      }
    }
    return value;
  }

  // Both existing native entrances complete through this SAME material. Their
  // callers retain every actual output before entering here. Preserve the full
  // admitted prefix through the original current fence; only then select the
  // existing typed retained quantity and detach its spent callback slot.
  function retainCompletedSourceNativeConstruction(original: Owner, material: Material, providerIndex: number,
    projectionIndex: number, quantity: unknown, projection: unknown, validate: () => void) {
    const check = () => {
      validate();
      if (material.phase !== 'working' || material.providers[providerIndex] !== quantity ||
          material.inputs[projectionIndex] !== projection) fail('InstalledSourceInputCapacityUnavailable');
    };
    check();
    // Reconciliation itself is numerical. The existing reserve entrance also
    // checks the SAME physical parent when its admitted debit is sufficient.
    reserveSource(original, material);
    check();
    let retained;
    material.busy = true;
    try {
      retained = checked(Reflect.apply(material.methods.InstalledSourceRetainedConstructionCapacity as CoreMethod,
        original.moon, [quantity]));
      check();
      if (!retained || typeof retained !== 'object' || nodeTypes.isProxy(retained)) {
        fail('InstalledSourceInputCapacityUnavailable');
      }
      material.inputs[projectionIndex] = undefined;
      material.providers[providerIndex] = retained;
    } finally {material.busy = false;}
    try {
      // The full old debit is still held: reserve observes currentness before
      // any shrink. A failed original fence therefore cannot spend that debt.
      reserveSource(original, material);
      validate();
      if (material.phase !== 'working' || material.providers[providerIndex] !== retained ||
          material.inputs[projectionIndex] !== undefined) fail('InstalledSourceInputCapacityUnavailable');
      reconcileSource(original, material);
    } catch (cause) {
      // A failed final fence keeps the SAME original quote and callback debt.
      material.providers[providerIndex] = quantity;
      material.inputs[projectionIndex] = projection;
      throw cause;
    }
  }

  // One pure metadata/native-input constructor under an already existing Source
  // material. Context and metadata-reader entrances supply only private guards;
  // neither can replace the original material or reserve after construction.
  function prepareSourceNativeInput(original: Owner, material: Material, projection: object | undefined,
    attempts: WeakSet<object>, validate: () => void, retain: (value: object) => void) {
    if (material.phase !== 'working' || material.busy || attempts.has(projection!)) {
      fail('ForeignInstalledSourceInitialization');
    }
    validate();
    let {capacity: capacityFor, project}: Partial<ReturnType<typeof sourceProjectionMethods>> =
      sourceProjectionMethods(projection!);
    if (typeof material.methods.InstalledSourceRetainedConstructionCapacity !== 'function') {
      fail('InstalledSourceInitializationRuntimeUnavailable');
    }
    attempts.add(projection!);
    let quantity;
    material.busy = true;
    try {quantity = requireSynchronousSourceConstruction(material, Reflect.apply(capacityFor!, projection, []));}
    finally {material.busy = false;}
    if (!quantity || typeof quantity !== 'object' || nodeTypes.isProxy(quantity)) fail('InstalledSourceInputCapacityUnavailable');
    // Register only after the SAME reservation admits the complete pending
    // quantity. A refused pure quote creates no native holding or cleanup ACK.
    reserveSource(original, material, 0n, 0n, 0n, undefined, undefined, quantity);
    const providerIndex = material.providers.length, projectionIndex = material.inputs.length;
    material.providers.push(quantity); material.inputs.push(projection);
    validate();
    if (material.phase !== 'working') fail('ForeignInstalledSourceInitialization');
    let value;
    material.busy = true;
    try {
      value = requireSynchronousSourceConstruction(material, Reflect.apply(project!, projection, []));
      material.inputs.push(value);
      validate();
      if (!value || typeof value !== 'object' || nodeTypes.isProxy(value) || 'then' in value) {
        fail('InvalidInstalledSourceNativeInput');
      }
      retain(value);
    } finally {material.busy = false;}
    retainCompletedSourceNativeConstruction(original, material, providerIndex,
      projectionIndex, quantity, projection, validate);
    projection = capacityFor = project = quantity = undefined;
    return value;
  }

  // JSON uses the SAME typed constructor recipe and successful-output cut as
  // other native inputs. JS reports its original wire facts and physical return;
  // Core owns peak/retained arithmetic, currentness and the original reservation.
  function reserveSourceJsonConstruction(original: Owner, material: Material, workspace: Workspace,
    geometry: JsonGeometry, bufferBytes: bigint) {
    const quantity = sourceCall(original, material, 'InstalledSourceJsonConstructionCapacity',
      [geometry.nodes, geometry.units, bufferBytes, geometry.retained.nodes, geometry.retained.text]);
    const providerIndex = material.providers.length, projectionIndex = material.inputs.length;
    material.providers.push(quantity); material.inputs.push(geometry);
    workspace.json = {providerIndex, projectionIndex, quantity, projection: geometry};
    // The original recipe now includes this read's complete parser/buffer peak.
    // Keep its physical pending marker, without charging those same buffers twice.
    Object.assign(workspace, {nodes: 0n, text: 0n, wire: 0n, retained: undefined});
    reserveSource(original, material);
  }

  function retainCompletedSourceJson<Value>(original: Owner, material: Material, workspace: Workspace, value: Value): Value {
    const input = material.inputs.length;
    material.inputs.push(value);
    // Reaching here follows the SAME awaited file close (or synchronous parse
    // of retained text). A later current failure keeps the original provider
    // peak, not a fictitious pending FD, until this Source actually retires.
    material.workspaces.delete(workspace); workspace.keepFailed = true;
    const {providerIndex, projectionIndex, quantity, projection} = workspace.json!;
    retainCompletedSourceNativeConstruction(original, material, providerIndex,
      projectionIndex, quantity, projection, () => {
        if (sourceMaterial(original) !== material || material.phase !== 'working' ||
            material.inputs[input] !== value) fail('ForeignInstalledSourceInitialization');
      });
    return value;
  }

  // Model metadata shares this SAME initialization material. One existing provider
  // slot holds its incremental retained total. Each call adds only THIS peak;
  // success replaces that peak with its original actual retained quantity. A
  // failed/current-refused constructor keeps its full debt and original inputs.
  function prepareModelTaskInput(original: ModelOwner, material: Material, projection: object,
    attempts: WeakSet<object>, validate: () => void) {
    if (material.modelFailure !== undefined) throw material.modelFailure.cause;
    if (material.phase !== 'working' || material.busy || attempts.has(projection) ||
        !projection || nodeTypes.isProxy(projection) || !Object.isFrozen(projection)) {
      fail('ForeignInstalledSourceInitialization');
    }
    const fields = Object.getOwnPropertyDescriptors(projection);
    if (Reflect.ownKeys(fields).length !== 3 || ['capacity', 'project', 'retained'].some(name =>
        !Object.hasOwn(fields[name] ?? {}, 'value') || typeof fields[name].value !== 'function' ||
        nodeTypes.isProxy(fields[name].value) || nodeTypes.isAsyncFunction(fields[name].value))) {
      fail('InvalidInstalledModelTaskProjection');
    }
    validate(); original.current();
    attempts.add(projection);
    const accumulate = original.moon.clientProgramAccumulateModelTaskConstructionCapacity;
    if (typeof accumulate !== 'function') fail('InstalledSourceInitializationRuntimeUnavailable');
    const add = (previous: unknown, current: unknown) => {
      const value = checked(Reflect.apply(accumulate, original.moon, [previous, current]));
      if (!value || typeof value !== 'object' || nodeTypes.isProxy(value)) {
        fail('InstalledSourceInputCapacityUnavailable');
      }
      return value;
    };
    const previous = material.modelRetained;
    let index = material.modelProviderIndex;
    const inputIndex = material.inputs.length;
    let peak;
    try {
      material.busy = true;
      try {peak = add(previous, requireSynchronousSourceConstruction(material,
        Reflect.apply(fields.capacity.value, projection, [])));}
      finally {material.busy = false;}
      if (index === undefined) {
        index = material.modelProviderIndex = material.providers.length;
        material.providers.push(peak);
      } else material.providers[index] = peak;
      material.inputs.push(projection);
      reserveSource(original, material);
      validate(); original.current();
      let value, retained;
      material.busy = true;
      try {
        value = requireSynchronousSourceConstruction(material, Reflect.apply(fields.project.value, projection, []));
        material.inputs.push(value);
        if (!value || typeof value !== 'object' || nodeTypes.isProxy(value) || 'then' in value) {
          fail('InvalidInstalledSourceNativeInput');
        }
        validate(); original.current();
        retained = add(previous, requireSynchronousSourceConstruction(material,
          Reflect.apply(fields.retained.value, projection, [value])));
        validate(); original.current();
      } finally {material.busy = false;}
      // Same original current/parent is checked while the full peak remains held.
      reserveSource(original, material);
      validate(); original.current();
      material.providers[index] = retained;
      material.modelRetained = retained;
      material.inputs[inputIndex] = undefined;
      reconcileSource(original, material);
      return value;
    } catch (cause) {
      if (peak !== undefined && index !== undefined) {
        material.providers[index] = peak;
        material.modelRetained = previous;
        material.inputs[inputIndex] = projection;
      }
      material.modelFailure = {cause};
      retainSourceFailure(material, cause);
      throw cause;
    }
  }

  return {sourceMaterial, sourceCall, sourceIo, sourceQuote, releaseFinishedSourceWorkspaces, reserveSource, reconcileSource,
    retainSourceFailure, requireSynchronousSourceConstruction, sourceProjectionMethods, freezeSourceProjection,
    retainCompletedSourceNativeConstruction, prepareSourceNativeInput, reserveSourceJsonConstruction,
    retainCompletedSourceJson, prepareModelTaskInput};
}
