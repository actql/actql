import {setImmediate as yieldEventLoop} from 'node:timers/promises';
import {types} from 'node:util';
import {runtimeField} from '../host-common/compiler-binding.generated.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import type {withManagedOutputRows} from '../store-local/managed-memory-representations.mjs';

type Awaitable<Value> = Value | PromiseLike<Value>;
type Runtime = Readonly<{
  clientProgramEffectInputAt(inputs: unknown, memberIndex: number): unknown;
  clientProgramEffectInputTask(input: unknown): number;
  clientProgramEffectTableInputAt?(inputs: unknown, memberIndex: number): unknown;
  clientProgramEffectTableInputTask(input: unknown): number;
  clientProgramEffectLocalResultAt(inputs: unknown, resultIndex: number): unknown;
  clientProgramEffectLocalResultTask(input: unknown): number;
  clientProgramEffectLocalResultExportStart(inputs: unknown, resultIndex: number, limits: unknown): unknown;
  clientProgramEffectLocalResultExportPreparation(owner: unknown): unknown;
  clientProgramEffectLocalResultExportMatchesReceipt(inputs: unknown, owner: unknown, receipt: unknown): boolean;
  clientProgramBeginEffectLocalCommandKeyWorkspace?(workspace: unknown, inputs: unknown, memberIndex: number,
    resultIndex: number, limits: unknown, completed: unknown, material: unknown): unknown;
  clientProgramBeginEffectCommandKeyWorkspace?(workspace: unknown, inputs: unknown, memberIndex: number,
    limits: unknown, completed: unknown, material: unknown): unknown;
  clientProgramEffectCommandKeyWorkspaceSynchronousEnd?(workspace: unknown): void;
  clientProgramEffectLocalManagedInputBegin(inputs: unknown, resultIndex: number,
    completed: unknown, material: unknown, limits: unknown): unknown;
  clientProgramEffectManagedInputBegin(input: unknown, completed: unknown, material: unknown, limits: unknown): unknown;
  clientProgramEffectTableManagedInputBegin(input: unknown, completed: unknown, material: unknown, limits: unknown): unknown;
  clientProgramEffectManagedInputAppend(importing: unknown, row: string): unknown;
  clientProgramEffectManagedInputFinish(importing: unknown): unknown;
  clientProgramEffectTableManagedInputFinish(importing: unknown): unknown;
  clientProgramEffectLocalManagedExportOwner(inputs: unknown, resultIndex: number, importing: unknown): unknown;
  clientProgramEffectInputExportAdvance(preparation: unknown, quantum: number): unknown;
  clientProgramEffectTableInputExportAdvance(preparation: unknown, quantum: number): unknown;
  clientProgramEffectInputExportReady(preparation: unknown): unknown;
  clientProgramEffectTableInputExportReady(preparation: unknown): unknown;
  clientProgramEffectInputExportNext(stream: unknown): unknown;
  clientProgramEffectInputExportNextCanonicalRow(stream: unknown, nodes: number, depth: number, units: number): unknown;
  clientProgramEffectInputExportFinish(stream: unknown): unknown;
  clientProgramEffectInputExportFields(receipt: unknown): readonly string[];
  clientProgramEffectInputExportLogicalCid(receipt: unknown): string;
  clientProgramEffectInputExportSchemaCid(receipt: unknown): string;
  clientProgramEffectInputExportRowCount(receipt: unknown): number;
  clientProgramEffectInputExportReleaseReceipt(receipt: unknown): void;
  clientProgramEffectInputExportCancel(stream: unknown): void;
  clientProgramEffectTableInputExportCancelPreparation(preparation: unknown): boolean;
  clientProgramEffectInputExportCancelPreparation(preparation: unknown): boolean;
  clientProgramEffectManagedInputCancel(importing: unknown): void;
}>;
type OriginalRowPorts = Readonly<{
  clientProgramEffectInputExportNextOriginalRow(stream: unknown, nodes: number, depth: number, units: number): unknown;
  clientProgramEffectOriginalRowAvailable(inputs: unknown, owner: unknown, original: unknown): boolean;
  clientProgramEffectOriginalRowRetire(original: unknown): void;
}>;
type PhysicalSource = Readonly<{
  completed: unknown; material: unknown;
  withRows<Value>(emit: (row: string) => unknown, signal: AbortSignal | undefined,
    commit: () => Value): ReturnType<typeof withManagedOutputRows<Value>>;
}>;
type RowLimits = Readonly<{maxNodes: number; maxDepth: number; maxUtf16Units: number}>;
type Options<Artifact> = Readonly<{
  moon: Runtime & Partial<OriginalRowPorts>;
  execution: Readonly<{effectPhysicalSource(task: number): PhysicalSource | undefined}>;
  inputs: unknown; memberIndex?: number; limits: unknown;
  onChunk(chunk: string): Awaitable<unknown>;
  onReceipt?(input: unknown, receipt: unknown, owner: unknown): Awaitable<Artifact>;
  onCanonicalRow?(rowIndex: number, row: unknown): Awaitable<unknown>;
  onOriginalRow?(rowIndex: number, original: unknown, exportOwner: unknown): Awaitable<unknown>;
  canonicalRowLimits?: RowLimits; originalRowLimits?: RowLimits;
  prepareProposal?(exportOwner: unknown, importing: unknown): Awaitable<unknown>;
  commandWorkspace?: unknown; signal?: AbortSignal; advanceQuantum?: number;
}>;

/**
 * Stream one pinned Effect source through the shared checked Result view.
 * The installed Site owns physical reading; MoonBit owns generation matching,
 * row admission, projection, ordering, and logical identity. This is not an
 * Effect Preview or a mutation permit. The caller retains the input pin.
 */
export async function exportPinnedEffectInput<Artifact>(options: Options<Artifact> & Readonly<{memberIndex: number}>) {
  return exportPinnedResult({...options, localResultIndex: undefined});
}

// Upstream dependency Results use the same bounded exporter and physical
// import bridge. They are not fictitious Effect members or public Results.
export async function exportPinnedEffectLocalResult<Artifact>({resultIndex, ...options}: Options<Artifact> & Readonly<{resultIndex: number}>) {
  if (!Number.isSafeInteger(resultIndex) || resultIndex < 0) {
    throw new TypeError('InvalidEffectLocalResult');
  }
  return exportPinnedResult({...options,
    memberIndex: options.commandWorkspace === undefined ? undefined : options.memberIndex,
    localResultIndex: resultIndex});
}

export async function exportPinnedResult<Artifact>({
  moon, execution, inputs, memberIndex, limits, onChunk,
  onReceipt, onCanonicalRow, canonicalRowLimits, onOriginalRow, originalRowLimits,
  prepareProposal, commandWorkspace,
  signal, advanceQuantum = 256, localResultIndex,
}: Options<Artifact> & Readonly<{localResultIndex: number | undefined}>) {
  const originalRows = onOriginalRow !== undefined;
  const selectedRowLimits = originalRows ? originalRowLimits : canonicalRowLimits;
  if (typeof onChunk !== 'function' ||
      (prepareProposal !== undefined && typeof prepareProposal !== 'function') ||
      (onReceipt !== undefined && typeof onReceipt !== 'function') ||
      (originalRows && (typeof onOriginalRow !== 'function' ||
        onCanonicalRow !== undefined || localResultIndex === undefined)) ||
      (onCanonicalRow !== undefined && typeof onCanonicalRow !== 'function') ||
      ((originalRows || onCanonicalRow !== undefined) &&
        (!Number.isSafeInteger(selectedRowLimits?.maxNodes) ||
          selectedRowLimits!.maxNodes < 1 ||
          !Number.isSafeInteger(selectedRowLimits?.maxDepth) ||
          selectedRowLimits!.maxDepth < 1 ||
          !Number.isSafeInteger(selectedRowLimits?.maxUtf16Units) ||
          selectedRowLimits!.maxUtf16Units < 0)) ||
      !Number.isSafeInteger(advanceQuantum) || advanceQuantum <= 0) {
    throw new TypeError('InvalidEffectInputExport');
  }
  const rowLimits = !originalRows && onCanonicalRow === undefined ? undefined :
    Object.freeze({maxNodes: selectedRowLimits!.maxNodes,
      maxDepth: selectedRowLimits!.maxDepth,
      maxUtf16Units: selectedRowLimits!.maxUtf16Units});
  let originalPorts: OriginalRowPorts | undefined;
  if (originalRows) {
    if (moon === null || typeof moon !== 'object' || types.isProxy(moon)) {
      throw new TypeError('OriginalEffectRowRuntimeUnavailable');
    }
    originalPorts = Object.freeze(Object.fromEntries([
      'clientProgramEffectInputExportNextOriginalRow',
      'clientProgramEffectOriginalRowAvailable',
      'clientProgramEffectOriginalRowRetire',
    ].map(name => {
      const descriptor = Object.getOwnPropertyDescriptor(moon, name);
      if (descriptor === undefined || !Object.hasOwn(descriptor, 'value') ||
          typeof descriptor.value !== 'function') {
        throw new TypeError('OriginalEffectRowRuntimeUnavailable');
      }
      return [name, descriptor.value];
    }))) as OriginalRowPorts;
  }
  signal?.throwIfAborted();
  const local = localResultIndex !== undefined;
  const tableInput = local ? undefined :
    moon.clientProgramEffectTableInputAt?.(inputs, memberIndex!);
  const table = tableInput !== undefined;
  const input = local
    ? moon.clientProgramEffectLocalResultAt(inputs, localResultIndex)
    : table ? tableInput : moon.clientProgramEffectInputAt(inputs, memberIndex!);
  if (input === undefined) {
    throw new TypeError('MissingEffectInput');
  }
  const task = local ? moon.clientProgramEffectLocalResultTask(input)
    : table ? moon.clientProgramEffectTableInputTask(input)
    : moon.clientProgramEffectInputTask(input);
  const physical = execution.effectPhysicalSource(task);
  if (physical === undefined && !local) {
    throw new TypeError('MissingEffectPhysicalSource');
  }
  if (commandWorkspace !== undefined &&
      (table || physical === undefined ||
        local && !Number.isSafeInteger(memberIndex) ||
        typeof (local ? moon.clientProgramBeginEffectLocalCommandKeyWorkspace
          : moon.clientProgramBeginEffectCommandKeyWorkspace) !== 'function' ||
        typeof moon.clientProgramEffectCommandKeyWorkspaceSynchronousEnd !== 'function')) {
    throw new TypeError('EffectCommandWorkspaceUnavailable');
  }
  let importing: unknown, preparation: unknown, stream: unknown, receipt: unknown, exportOwner: unknown;
  try {
    if (physical === undefined) {
      exportOwner = checked(moon.clientProgramEffectLocalResultExportStart(
        inputs, localResultIndex!, limits));
      preparation = moon.clientProgramEffectLocalResultExportPreparation(
        exportOwner);
    } else {
      if (commandWorkspace !== undefined) {
        // The original capture retains this same phase view before calling
        // the exporter. Reserve/allocate before withRows can materialize its
        // managed import; no structural count or caller bytes issue capacity.
        try {
          importing = checked(local
            ? moon.clientProgramBeginEffectLocalCommandKeyWorkspace!(
              commandWorkspace, inputs, memberIndex!, localResultIndex, limits,
              physical.completed, physical.material)
            : moon.clientProgramBeginEffectCommandKeyWorkspace!(
              commandWorkspace, inputs, memberIndex!, limits,
              physical.completed, physical.material));
        } finally {
          // A synchronous return/throw is not a resource/physical ACK.
          moon.clientProgramEffectCommandKeyWorkspaceSynchronousEnd!(commandWorkspace);
        }
      } else importing = checked(local
        ? moon.clientProgramEffectLocalManagedInputBegin(inputs,
          localResultIndex, physical.completed, physical.material, limits)
        : table ? moon.clientProgramEffectTableManagedInputBegin(input,
          physical.completed, physical.material, limits)
        : moon.clientProgramEffectManagedInputBegin(input,
          physical.completed, physical.material, limits));
      preparation = await physical.withRows(
        row => checked(moon.clientProgramEffectManagedInputAppend(
          importing, row)), signal,
        () => checked(table ? moon.clientProgramEffectTableManagedInputFinish(importing)
          : moon.clientProgramEffectManagedInputFinish(importing)),
      );
      if (local) {
        exportOwner = checked(moon.clientProgramEffectLocalManagedExportOwner(
          inputs, localResultIndex, importing));
      }
    }
    for (;;) {
      signal?.throwIfAborted();
      const progress = checked(table
        ? moon.clientProgramEffectTableInputExportAdvance(preparation, advanceQuantum)
        : moon.clientProgramEffectInputExportAdvance(preparation, advanceQuantum));
      if (runtimeField(progress, 0)) break;
      if ((runtimeField(progress, 1) as number) <= 0) {
        throw new Error('EffectInputExportDidNotAdvance');
      }
      await yieldEventLoop(undefined, {signal});
    }
    if (prepareProposal !== undefined) {
      await prepareProposal(exportOwner, importing);
    }
    stream = checked(table ? moon.clientProgramEffectTableInputExportReady(preparation)
      : moon.clientProgramEffectInputExportReady(preparation));
    for (;;) {
      signal?.throwIfAborted();
      if (originalRows) {
        const row = checked(Reflect.apply(
          originalPorts!.clientProgramEffectInputExportNextOriginalRow, moon,
          [stream, rowLimits!.maxNodes, rowLimits!.maxDepth, rowLimits!.maxUtf16Units]));
        if (row === undefined) break;
        const original = runtimeField(row, 2);
        const assertOriginal = () => {
          signal?.throwIfAborted();
          if (Reflect.apply(originalPorts!.clientProgramEffectOriginalRowAvailable,
            moon, [inputs, exportOwner, original]) !== true) {
            throw new TypeError('UnavailableEffectOriginalRow');
          }
        };
        try {
          assertOriginal();
          await onOriginalRow(runtimeField(row, 0) as number, original, exportOwner);
          // The callback can await or revoke the original preparation. Do not
          // publish its row bytes after that original is no longer current.
          assertOriginal();
          await onChunk(runtimeField(row, 1) as string);
        } finally {
          Reflect.apply(originalPorts!.clientProgramEffectOriginalRowRetire,
            moon, [original]);
        }
      } else if (onCanonicalRow === undefined) {
        const chunk = checked(moon.clientProgramEffectInputExportNext(stream));
        if (chunk === undefined) break;
        await onChunk(chunk as string);
      } else {
        const row = checked(moon.clientProgramEffectInputExportNextCanonicalRow(
          stream, rowLimits!.maxNodes, rowLimits!.maxDepth,
          rowLimits!.maxUtf16Units));
        if (row === undefined) break;
        await onCanonicalRow(runtimeField(row, 0) as number, runtimeField(row, 2));
        await onChunk(runtimeField(row, 1) as string);
      }
    }
    signal?.throwIfAborted();
    const finished = checked(moon.clientProgramEffectInputExportFinish(stream));
    receipt = runtimeField(finished, 0);
    await onChunk(runtimeField(finished, 1) as string);
    if (local && moon.clientProgramEffectLocalResultExportMatchesReceipt(
      inputs, exportOwner, receipt) !== true) {
      throw new TypeError('ForeignEffectLocalResultReceipt');
    }
    const artifact = onReceipt === undefined
      ? undefined : await onReceipt(input, receipt,
        local ? exportOwner : importing);
    return Object.freeze({
      fields: moon.clientProgramEffectInputExportFields(receipt),
      logicalCid: moon.clientProgramEffectInputExportLogicalCid(receipt),
      schemaCid: moon.clientProgramEffectInputExportSchemaCid(receipt),
      rowCount: moon.clientProgramEffectInputExportRowCount(receipt),
      ...(artifact === undefined ? {} : {artifact}),
    });
  } finally {
    if (receipt !== undefined) {
      moon.clientProgramEffectInputExportReleaseReceipt(receipt);
    }
    if (stream !== undefined) {
      moon.clientProgramEffectInputExportCancel(stream);
    } else if (preparation !== undefined) {
      if (table) moon.clientProgramEffectTableInputExportCancelPreparation(preparation);
      else moon.clientProgramEffectInputExportCancelPreparation(preparation);
    }
    if (importing !== undefined) {
      moon.clientProgramEffectManagedInputCancel(importing);
    }
  }
}
