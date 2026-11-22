import {types as nodeTypes} from 'node:util';

type Amounts = {nodes: bigint; text: bigint; wire: bigint};
type CapacityAmounts = readonly [retainedNodes: bigint, retainedText: bigint, retainedWire: bigint,
  workspaceNodes: bigint, workspaceText: bigint, workspaceWire: bigint];
type CleanupObservation = Readonly<{handle: unknown; method: unknown}>;
type Workspace = Amounts & {
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
  methods: Readonly<{ComposeInstalledSourceConstructionCapacity?: unknown}>;
  phase: 'opening' | 'working' | 'failed' | 'ready' | 'retiring' | 'retired';
  workspaces: Set<Workspace>;
  providers: unknown[];
  inputs: unknown[];
  cleanup: CleanupObservation[];
  capacity: unknown;
  input: unknown;
  ioPending: number;
  io?: SourceIo;
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
}>;
type MaterialPorts<Owner> = Readonly<{
  fail(code: string): never;
  sourceCall<Name extends keyof Calls>(original: Owner, material: Material, name: Name, args: Calls[Name]): unknown;
  sourceNativeThen: typeof Promise.prototype.then;
}>;

export function createInstalledSourceMaterialAccounting<Owner>(
  {fail: reject, sourceCall, sourceNativeThen}: MaterialPorts<Owner>) {
  const fail: (code: string) => never = reject;

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

  return {sourceIo, sourceQuote, releaseFinishedSourceWorkspaces, reserveSource, reconcileSource,
    retainSourceFailure, requireSynchronousSourceConstruction};
}
