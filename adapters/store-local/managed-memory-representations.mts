// Portable registry and scoped access for managed row representations. File
// providers install their own grouped reader; memory-only consumers never load
// Node filesystem or crypto modules.
export type ManagedTransferEstimate = Readonly<{
  transferBytes: bigint;
  retainedBytes: bigint;
  executionBytes: bigint;
}>;
type Readable = (input: unknown) => boolean;
type RowAuthorization = (input: unknown, index: number) => boolean;
type EmitRow = (row: string) => unknown;
type AppendRow = (index: number, row: string) => unknown;
type BeforeRead = (indices: readonly number[], bytes: number) => unknown;
type RowProvider = Readonly<{read(file: unknown, emit: EmitRow, signal?: AbortSignal): unknown}>;
type Occurrence = Readonly<{material: object; input: unknown; codecContractCid?: string}>;
type RowUse = <Value, Committed>(occurrences: readonly Occurrence[], authorize: RowAuthorization,
  append: AppendRow, use: () => Value, signal?: AbortSignal, beforeRead?: BeforeRead,
  commit?: (provisional: Awaited<Value>) => Committed) => Promise<Awaited<Value> | Awaited<Committed>>;
type UsePin = Readonly<{acquire(): void; releaseUse(): void; sourceAvailable(): boolean; available(): boolean}>;
type Representation = Readonly<{
  readable: Readable;
  codecContractCid?: string;
  physicalManifest?: {cid: string};
  rowProvider?: RowProvider;
  transferEstimate?: ManagedTransferEstimate;
  transferAvailable?(): boolean;
}> & ((UsePin & {memory: true; rowProvider: RowProvider}) | {memory?: false; rowUse?: RowUse});
type MemoryRepresentation = Extract<Representation, {memory: true}>;
type ProviderGroup = Readonly<{kind: 'provider'; rowUse: RowUse; indices: readonly number[]}>;
type RowGroup = Readonly<{kind: 'memory'; indices: readonly number[]}> | ProviderGroup;
type RowPlan = Readonly<{
  materials: readonly object[];
  owners: readonly Representation[];
  groups: readonly RowGroup[];
}>;
type CleanupHandle = Readonly<{status(): unknown; retry(): unknown}>;
type ManagedInputFailure = Error & {
  code: string;
  primaryFailure: unknown;
  cleanupPending: boolean;
  cleanupErrors: readonly unknown[];
  cleanupHandle?: CleanupHandle;
};

const representations = new WeakMap<object, Representation>();
const rowPlans = new WeakSet<RowPlan>();
const managedInputOwners = new WeakMap<object, CleanupHandle>();
const managedInputReleaseFailures = new WeakMap<object, {handle: CleanupHandle; primary: unknown}>();
// A copied wrapper or replaced recovery callback cannot borrow a registered
// memory owner's completed-output cleanup authority.
export function managedMemoryReleaseFailureMatches(owner: object, failure: object) {
  const original = managedInputReleaseFailures.get(failure);
  return original !== undefined && managedInputOwners.get(owner) === original.handle &&
    Object.getOwnPropertyDescriptor(failure, 'cleanupHandle')?.value === original.handle &&
    Object.getOwnPropertyDescriptor(failure, 'primaryFailure')?.value === original.primary;
}
const issue = (code: string) => Object.assign(new Error(code), {code});
const member = (value: unknown, name: string): unknown => {
  try {
    return value !== null &&
      (typeof value === 'object' || typeof value === 'function')
      ? (value as Record<string, unknown>)[name] : undefined;
  } catch { return undefined; }
};
const cleanupState = (handle: unknown) => {
  if (!handle || typeof member(handle, 'status') !== 'function') {
    return Object.freeze({pending: true, errors: Object.freeze([])});
  }
  try {
    const state = (handle as CleanupHandle).status() as {pending?: unknown; errors?: unknown} | undefined;
    if (!state || typeof state.pending !== 'boolean') {
      return Object.freeze({pending: true, errors: Object.freeze([])});
    }
    return Object.freeze({
      pending: state.pending,
      errors: Object.freeze(Array.isArray(state.errors) ? [...state.errors] : []),
    });
  } catch (error) {
    return Object.freeze({pending: true, errors: Object.freeze([error])});
  }
};

function memoryUseFailure(reason: unknown, acquired: readonly UsePin[]) {
  const native = member(reason, 'cleanupHandle');
  if (member(reason, 'cleanupPending') !== true) return undefined;
  let usesReleased = false;
  const diagnostics: unknown[] = [];
  const releaseFailures: unknown[] = [];
  const releaseAll = () => {
    if (usesReleased) return;
    usesReleased = true;
    for (let index = acquired.length - 1; index >= 0; index--) {
      try { acquired[index].releaseUse(); }
      catch (error) { releaseFailures.push(error); }
    }
  };
  const initial = cleanupState(native);
  if (!initial.pending) {
    releaseAll();
    if (releaseFailures.length === 0) return undefined;
  }
  const failure = issue(typeof member(reason, 'code') === 'string'
    ? member(reason, 'code') as string : 'ManagedInputUseFailed') as ManagedInputFailure;
  failure.cause = reason;
  failure.primaryFailure = reason;
  failure.cleanupPending = true;
  diagnostics.push(...initial.errors);
  const status = () => {
    const state = usesReleased
      ? Object.freeze({pending: false, errors: Object.freeze([])})
      : cleanupState(native);
    const releaseStates = releaseFailures.map(error =>
      cleanupState(member(error, 'cleanupHandle')));
    return Object.freeze({
      pending: !usesReleased || releaseStates.some(value => value.pending),
      errors: Object.freeze([
        ...diagnostics,
        ...state.errors,
        ...releaseFailures,
        ...releaseStates.flatMap(value => value.errors),
      ]),
    });
  };
  failure.cleanupErrors = status().errors;
  failure.cleanupHandle = Object.freeze({
    status,
    async retry() {
      if (!usesReleased && typeof member(native, 'retry') === 'function') {
        try { await (native as CleanupHandle).retry(); }
        catch (error) { diagnostics.push(error); }
      }
      if (!usesReleased && !cleanupState(native).pending) releaseAll();
      for (const error of releaseFailures) {
        const handle = member(error, 'cleanupHandle');
        if (cleanupState(handle).pending &&
            typeof member(handle, 'retry') === 'function') {
          try { await (handle as CleanupHandle).retry(); }
          catch (retryError) { diagnostics.push(retryError); }
        }
      }
      failure.cleanupErrors = status().errors;
      failure.cleanupPending = status().pending;
      return status();
    },
  });
  return failure;
}

function releaseMemoryUses(acquired: readonly UsePin[], primary?: unknown) {
  const primaryProvided = arguments.length >= 2;
  const errors: unknown[] = [];
  for (let index = acquired.length - 1; index >= 0; index--) {
    try { acquired[index].releaseUse(); }
    catch (error) { errors.push(error); }
  }
  if (errors.length === 0) return;
  const failure = issue('ManagedInputReleaseFailed') as ManagedInputFailure;
  const hasReleaseCause = errors[0] !== null &&
    (typeof errors[0] === 'object' || typeof errors[0] === 'function') &&
    Object.hasOwn(errors[0], 'primaryFailure');
  const releaseCause = hasReleaseCause
    ? (errors[0] as {primaryFailure: unknown}).primaryFailure
    : errors[0];
  failure.cause = primaryProvided ? primary : releaseCause;
  failure.primaryFailure = primaryProvided ? primary : releaseCause;
  failure.cleanupErrors = Object.freeze([...errors]);
  const handles = errors.map(error =>
    member(error, 'cleanupPending') === true
      ? member(error, 'cleanupHandle')
      : undefined);
  const status = () => Object.freeze({
    pending: handles.some(handle => cleanupState(handle).pending),
    errors: Object.freeze([
      ...errors,
      ...handles.flatMap(handle => cleanupState(handle).errors),
    ]),
  });
  failure.cleanupPending = status().pending;
  if (failure.cleanupPending) {
    failure.cleanupHandle = Object.freeze({
      status,
      async retry() {
        for (const handle of handles) {
          if (cleanupState(handle).pending &&
              typeof member(handle, 'retry') === 'function') {
            try { await (handle as CleanupHandle).retry(); }
            catch (error) { failure.cleanupErrors = Object.freeze([
              ...failure.cleanupErrors, error,
            ]); }
          }
        }
        failure.cleanupPending = status().pending;
        return status();
      },
    });
  }
  throw failure;
}

export function managedRepresentation(material: object) {
  return representations.get(material);
}

export function installManagedRepresentation(material: object, representation: Representation) {
  if (!material || typeof material !== 'object' ||
      representations.has(material)) {
    throw issue('InvalidManagedInputRegistration');
  }
  representations.set(material, Object.freeze(representation));
}

export function managedInputCodecContractCid(material: object) {
  return representations.get(material)?.codecContractCid;
}

export function managedInputPhysicalManifestCid(material: object) {
  return representations.get(material)?.physicalManifest?.cid;
}

// Pure capacity advertisement for an explicit representation Transfer. These
// are safe upper bounds fixed by the representation owner, not observed usage
// and not permission to acquire the generation.
export function managedInputTransferEstimate(material: object) {
  const representation = representations.get(material);
  if (!representation) return undefined;
  try {
    if (typeof representation.transferAvailable === 'function' &&
        representation.transferAvailable() !== true) {
      return undefined;
    }
  } catch { return undefined; }
  const estimate = representation.transferEstimate;
  return estimate === undefined ? undefined : Object.freeze({...estimate});
}

// Pure support lookup used during candidate preparation. It grants no Store
// access, pins no generation and starts no provider work.
export function managedInputSupportsRows(material: object) {
  return typeof representations.get(material)?.rowProvider?.read === 'function';
}

// Pure full-set compatibility planning. A plan fixes the exact representation
// owners and the scopes that must overlap, but acquires no generation and
// starts no provider work. Different physical providers compose by nesting
// their scoped uses; publication remains outside every final provider check.
export function planManagedInputRows(materials: readonly object[]): RowPlan | undefined {
  if (!Array.isArray(materials)) return undefined;
  const held = materials.map(material => representations.get(material));
  if (held.some(value =>
      typeof value?.rowProvider?.read !== 'function')) return undefined;
  const grouped = new Map<RowUse, number[]>();
  const memory: number[] = [];
  for (let index = 0; index < held.length; index++) {
    const value = held[index]!;
    if (value.memory === true) {
      memory.push(index);
      continue;
    }
    if (typeof value.rowUse !== 'function') return undefined;
    const indices = grouped.get(value.rowUse) ?? [];
    indices.push(index);
    grouped.set(value.rowUse, indices);
  }
  if (grouped.size > 1) return undefined;
  const groups: RowGroup[] = [];
  if (memory.length > 0) {
    groups.push(Object.freeze({kind: 'memory', indices: Object.freeze(memory)}));
  }
  for (const [rowUse, indices] of grouped) {
    groups.push(Object.freeze({
      kind: 'provider',
      rowUse,
      indices: Object.freeze(indices),
    }));
  }
  const plan = Object.freeze({
    materials: Object.freeze([...materials]),
    owners: Object.freeze([...held]) as readonly Representation[],
    groups: Object.freeze(groups),
  });
  rowPlans.add(plan);
  return plan;
}

// Managed in-memory representation registration. Its physical lifetime stays
// with the installed implementation; this registry only acquires a scoped
// use count and never turns the opaque material into a portable handle.
export function registerManagedMemoryInput(
  material: object, readable: Readable, available: () => boolean,
  rowProvider: RowProvider, release: () => void, transferEstimate?: ManagedTransferEstimate,
) {
  const estimateValid = transferEstimate === undefined ||
    (transferEstimate !== null && typeof transferEstimate === 'object' &&
      [transferEstimate.transferBytes, transferEstimate.retainedBytes,
        transferEstimate.executionBytes].every(value =>
        typeof value === 'bigint' && value >= 0n));
  if (!material || typeof material !== 'object' ||
      representations.has(material) || typeof readable !== 'function' ||
      typeof available !== 'function' || rowProvider === null ||
      typeof rowProvider !== 'object' ||
      typeof rowProvider.read !== 'function' ||
      typeof release !== 'function' || available() !== true ||
      !estimateValid) {
    throw issue('InvalidManagedInputRegistration');
  }
  let open = true, readers = 0, released = false;
  let releaseAttempted = false, releaseFailed = false, releaseFailure: unknown;
  let originalReleaseError: ManagedInputFailure | undefined;
  const closeWaiters: {resolve(): void; reject(error: unknown): void}[] = [];
  const settleCloseWaiters = () => {
    if (!released && !releaseFailed) return;
    while (closeWaiters.length > 0) {
      const waiter = closeWaiters.shift()!;
      if (released) waiter.resolve();
      else waiter.reject(releaseError());
    }
  };
  const finishRelease = () => {
    if (released || releaseAttempted || open || readers !== 0) return;
    releaseAttempted = true;
    try {
      release();
      released = true;
    } catch (error) {
      releaseFailed = true;
      releaseFailure = error;
    }
    settleCloseWaiters();
  };
  const releaseCleanup = Object.freeze({
    status() {
      if (released) return Object.freeze({pending: false, errors: Object.freeze([])});
      const state = cleanupState(member(releaseFailure, 'cleanupHandle'));
      return Object.freeze({
        pending: true,
        errors: Object.freeze([
          ...(releaseFailed ? [releaseFailure] : []),
          ...state.errors,
        ]),
      });
    },
    async retry() {
      const handle = member(releaseFailure, 'cleanupHandle');
      if (!released && member(releaseFailure, 'cleanupPending') === true &&
          typeof member(handle, 'retry') === 'function') {
        await (handle as CleanupHandle).retry();
        const state = cleanupState(handle);
        if (!state.pending && state.errors.length === 0) {
          released = true;
          settleCloseWaiters();
        }
      }
      return releaseCleanup.status();
    },
  });
  const releaseError = () => {
    // releaseAttempted fixes the original failure. Concurrent waiters and
    // later retries share this one wrapper, not a growing failure inventory.
    if (originalReleaseError !== undefined) return originalReleaseError;
    const failure = issue('ManagedInputReleaseFailed') as ManagedInputFailure;
    failure.cause = releaseFailure;
    failure.primaryFailure = releaseFailure;
    failure.cleanupErrors = releaseCleanup.status().errors;
    failure.cleanupPending = true;
    failure.cleanupHandle = releaseCleanup;
    managedInputReleaseFailures.set(failure, {handle: releaseCleanup, primary: releaseFailure});
    originalReleaseError = failure;
    return failure;
  };
  const held: MemoryRepresentation = {
    readable,
    available: () => open && available() === true,
    sourceAvailable: () => available() === true,
    rowProvider,
    memory: true,
    transferAvailable: () => open && available() === true,
    transferEstimate: transferEstimate === undefined
      ? undefined
      : Object.freeze({...transferEstimate}),
    acquire() {
      if (!open || available() !== true) {
        throw issue('ManagedInputUnavailable');
      }
      readers++;
    },
    releaseUse() {
      if (readers < 1) throw issue('InvalidManagedInputUse');
      readers--;
      finishRelease();
      if (releaseFailed && !released) throw releaseError();
    },
  };
  installManagedRepresentation(material, held);
  const owner = Object.freeze({
    async close() {
      open = false;
      finishRelease();
      if (releaseFailed && !released) throw releaseError();
      if (!released) {
        // An admitted reader still owns the generation. Its releaseUse()
        // settles these waiters without polling or granting a new use.
        await new Promise<void>((resolve, reject) => {
          closeWaiters.push({resolve, reject});
          settleCloseWaiters();
        });
      }
    },
    status: () => Object.freeze({
      open,
      readers,
      released,
      releaseRequested: !open,
      releaseAttempted,
      releaseFailed: releaseFailed && !released,
    }),
  });
  managedInputOwners.set(owner, releaseCleanup);
  return owner;
}

// Publication-only scoped read of one exact managed material generation.
// Semantic admission remains in MoonBit; this function owns only the physical
// use pin while the installed representation emits its retained rows.
export async function withManagedOutputRows<Value>(
  material: object, emit: EmitRow, signal: AbortSignal | undefined, commit: () => Value,
) {
  const held = representations.get(material) as MemoryRepresentation | undefined;
  if (!held || typeof held.rowProvider?.read !== 'function' ||
      typeof emit !== 'function' || typeof commit !== 'function') {
    throw issue('UnsupportedManagedRowRepresentation');
  }
  const acquired: UsePin[] = [];
  let failed = false;
  try {
    held.acquire();
    acquired.push(held);
    if (held.sourceAvailable() !== true) {
      throw issue('ManagedInputUnavailable');
    }
    signal?.throwIfAborted();
    await held.rowProvider.read(undefined, emit, signal);
    signal?.throwIfAborted();
    if (held.sourceAvailable() !== true) {
      throw issue('ManagedInputUnavailable');
    }
    return await commit();
  } catch (error) {
    failed = true;
    if (member(error, 'cleanupPending') === true) {
      const retained = memoryUseFailure(error, acquired);
      if (retained !== undefined) throw retained;
      throw error;
    }
    releaseMemoryUses(acquired, error);
    throw error;
  } finally {
    if (!failed) releaseMemoryUses(acquired);
  }
}

async function withManagedMemoryRows<Value, Committed>(
  occurrences: readonly Occurrence[], held: readonly MemoryRepresentation[], providers: readonly RowProvider[],
  authorize: RowAuthorization, append: AppendRow, use: (recheck: () => void) => Value,
  signal: AbortSignal | undefined, commit?: (provisional: Awaited<Value>) => Committed,
) {
    const admit = (index: number, acquired = false) => {
      signal?.throwIfAborted();
      const occurrence = occurrences[index];
      const value = held[index]!;
      const isAvailable = acquired
        ? value.sourceAvailable() === true
        : value.available() === true;
      if (!isAvailable || occurrence.input == null ||
          value.readable(occurrence.input) !== true ||
          authorize(occurrence.input, index) !== true) {
        throw issue('ManagedInputUnavailable');
      }
    };
    const unique = [...new Set(held)];
    const acquired: UsePin[] = [];
    let failed = false;
    try {
      for (const value of unique) {
        value.acquire();
        acquired.push(value);
      }
      for (let index = 0; index < occurrences.length; index++) {
        admit(index, true);
      }
      for (let index = 0; index < providers.length; index++) {
        admit(index, true);
        await providers[index].read(
          undefined,
          row => append(index, row),
          signal,
        );
      }
      for (let index = 0; index < occurrences.length; index++) {
        admit(index, true);
      }
      const recheck = () => {
        for (let index = 0; index < occurrences.length; index++) {
          admit(index, true);
        }
        signal?.throwIfAborted();
      };
      const provisional = await use(recheck);
      recheck();
      return typeof commit === 'function'
        ? await commit(provisional)
        : provisional;
    } catch (error) {
      failed = true;
      if (member(error, 'cleanupPending') === true) {
        const retained = memoryUseFailure(error, acquired);
        if (retained !== undefined) throw retained;
        throw error;
      }
      releaseMemoryUses(acquired, error);
      throw error;
    } finally {
      if (!failed) releaseMemoryUses(acquired);
    }
}

// Representation-neutral managed row use. Memory generations are pinned in
// this portable module. Installed physical providers retain their own grouped
// read operation so importing the Local connector does not import Node I/O.
export function withManagedInputRows<Value, Committed>(
  occurrences: readonly Occurrence[], authorize: RowAuthorization, append: AppendRow, use: () => Value,
  signal: AbortSignal | undefined, beforeRead: BeforeRead | undefined,
  commit: (provisional: Awaited<Value>) => Committed, planned?: RowPlan,
): Promise<Awaited<Committed>>;
export function withManagedInputRows<Value>(
  occurrences: readonly Occurrence[], authorize: RowAuthorization, append: AppendRow, use: () => Value,
  signal?: AbortSignal, beforeRead?: BeforeRead, commit?: undefined, planned?: RowPlan,
): Promise<Awaited<Value>>;
export async function withManagedInputRows<Value, Committed>(
  occurrences: readonly Occurrence[], authorize: RowAuthorization, append: AppendRow, use: () => Value,
  signal?: AbortSignal, beforeRead?: BeforeRead, commit?: (provisional: Awaited<Value>) => Committed, planned?: RowPlan,
) {
  if (!Array.isArray(occurrences) ||
      typeof authorize !== 'function' || typeof append !== 'function' ||
      typeof use !== 'function' ||
      (commit !== undefined && typeof commit !== 'function')) {
    throw issue('InvalidManagedInputUse');
  }
  const materials = occurrences.map((occurrence: Occurrence) => occurrence?.material);
  const plan = planned ?? planManagedInputRows(materials);
  if (!plan || !rowPlans.has(plan) ||
      plan.materials.length !== materials.length ||
      plan.materials.some((material, index) => material !== materials[index]) ||
      plan.owners.some((owner, index) =>
        owner !== representations.get(materials[index]))) {
    throw issue('UnsupportedManagedRowRepresentation');
  }
  const groupArguments = (group: RowGroup) => {
    const subset = group.indices.map(index => occurrences[index]);
    const held = group.indices.map(index => plan.owners[index]);
    const providers = held.map(value => value.rowProvider!);
    const authorizeSubset = (input: unknown, index: number) =>
      authorize(input, group.indices[index]);
    const appendSubset = (index: number, row: string) =>
      append(group.indices[index], row);
    return {subset, held, providers, authorizeSubset, appendSubset};
  };
  if (plan.groups.length === 0) {
    signal?.throwIfAborted();
    const provisional = await use();
    signal?.throwIfAborted();
    return typeof commit === 'function'
      ? await commit(provisional)
      : provisional;
  }
  if (plan.groups.length === 1) {
    const group = plan.groups[0];
    const args = groupArguments(group);
    if (group.kind === 'memory') {
      return withManagedMemoryRows(
        args.subset, args.held as readonly MemoryRepresentation[], args.providers, args.authorizeSubset,
        args.appendSubset, () => use(), signal, commit,
      );
    }
    return group.rowUse(
      args.subset, args.authorizeSubset, args.appendSubset, use, signal,
      beforeRead, commit,
    );
  }
  const memory = plan.groups[0];
  const provider = plan.groups[1] as ProviderGroup;
  const memoryArgs = groupArguments(memory);
  const providerArgs = groupArguments(provider);
  return withManagedMemoryRows(
    memoryArgs.subset,
    memoryArgs.held as readonly MemoryRepresentation[],
    memoryArgs.providers,
    memoryArgs.authorizeSubset,
    memoryArgs.appendSubset,
    recheckMemory => provider.rowUse(
      providerArgs.subset,
      providerArgs.authorizeSubset,
      providerArgs.appendSubset,
      use,
      signal,
      beforeRead,
      typeof commit === 'function'
        ? provisional => {
          recheckMemory();
          return commit(provisional);
        }
        : undefined,
    ),
    signal,
    undefined,
  );
}
