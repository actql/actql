import {runtimeField} from '../host-common/compiler-binding.generated.mjs';
import type {storeCompletedResultPublicationPayload} from '../host-common/durable-result-payload.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {setImmediate as yieldEventLoop} from 'node:timers/promises';

type Payload = Parameters<typeof storeCompletedResultPublicationPayload>;
type StoreExport = (host: undefined, index: number, limits: Payload[4]) => ReturnType<NonNullable<Payload[7]>>;
type ResultOriginal = Readonly<{selection: unknown; storeExport: StoreExport}>;
type ResultRuntime = Readonly<{
  clientProgramInferPublicationBegin(binding: unknown, index: number): unknown;
  clientProgramInferPublicationCancel(owner: unknown): boolean;
  clientProgramInferPublicationAdvance(owner: unknown, quantum: number): unknown;
  clientProgramInferPublicationSelection(owner: unknown): unknown;
  clientProgramInferPublicationFinish(owner: unknown): unknown;
  clientProgramInferPublicationStoreExport(owner: unknown): unknown;
  clientProgramInferPublicationRelease(owner: unknown): boolean;
}>;
type RetainedStoreCleanup = Readonly<{
  status?(): Readonly<{pending?: boolean}> | undefined;
  retry?(): unknown;
}>;
type StoreFailure = Readonly<{
  message?: string; code?: string; cleanupPending?: boolean; cleanupHandle?: RetainedStoreCleanup;
}>;
type ResultStep<Result> = Readonly<{
  moon: ResultRuntime; binding: unknown; result: number;
  consume(original: ResultOriginal & Readonly<{exported: unknown; signal: AbortSignal | undefined}>): Result;
  signal?: AbortSignal; quantum?: number;
}>;

export const pending = () => Object.assign(new Error('ClientDispatchCleanupPending'),
  {code: 'ClientDispatchCleanupPending'});

// This is physical stepping of the existing checked Result transformer, not
// another publisher or an adapter-authored publication inventory. The Store
// callback receives the common selection and ordinary opaque output exporter.
export async function withNodeInferResult<Result>({moon, binding, result, consume,
  signal, quantum = 256}: ResultStep<Result>): Promise<Awaited<Result>> {
  if (typeof consume !== 'function' || !Number.isSafeInteger(result) ||
      result < 0 || !Number.isSafeInteger(quantum) || quantum < 1 ||
      quantum > 2147483647) {
    throw new TypeError('InvalidInstalledInferResult');
  }
  signal?.throwIfAborted();
  const owner = checked(moon.clientProgramInferPublicationBegin(binding,
    result));
  const cancel = () => moon.clientProgramInferPublicationCancel(owner);
  signal?.addEventListener('abort', cancel, {once: true});
  let custodyTransferred = false;
  try {
    for (;;) {
      signal?.throwIfAborted();
      const progress = checked(moon.clientProgramInferPublicationAdvance(owner,
        quantum));
      if (runtimeField(progress, 0)) break;
      await yieldEventLoop();
    }
    signal?.throwIfAborted();
    const selection = moon.clientProgramInferPublicationSelection(owner);
    const exported = checked(moon.clientProgramInferPublicationFinish(owner));
    // Do not race this against abort: a rejected/aborted consumer must first
    // settle its physical I/O and retain any unresolved cleanup responsibility.
    return await consume({selection, exported, signal,
      storeExport: () => checked(
        moon.clientProgramInferPublicationStoreExport(owner)) as ReturnType<StoreExport>});
  } catch (failure) {
    if ((failure as StoreFailure | undefined)?.cleanupPending === true) {
      // The existing dispatch supervisor retries this exact Store cleanup
      // handle. Keep the Result pinned until that handle confirms settlement;
      // a rejected consumer Promise alone cannot confirm physical stop.
      const original = (failure as StoreFailure).cleanupHandle;
      custodyTransferred = true;
      const retained = Object.freeze({
        status: () => ({pending: custodyTransferred}),
        async retry() {
          if (!custodyTransferred) return false;
          if (typeof original?.retry !== 'function' ||
              typeof original?.status !== 'function') throw pending();
          if (original.status()?.pending === true) await original.retry();
          if (original.status()?.pending !== false) throw pending();
          moon.clientProgramInferPublicationRelease(owner);
          custodyTransferred = false;
          return true;
        },
      });
      // Preserve the original typed cause even when its Error is immutable.
      const held = new Error((failure as StoreFailure).message, {cause: failure}) as Error & {
        code: string | undefined; cleanupPending: boolean; cleanupHandle: typeof retained;
      };
      held.code = (failure as StoreFailure).code;
      held.cleanupPending = true;
      held.cleanupHandle = retained;
      throw held;
    }
    throw failure;
  } finally {
    signal?.removeEventListener('abort', cancel);
    if (!custodyTransferred) moon.clientProgramInferPublicationRelease(owner);
  }
}
