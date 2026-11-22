// Physical stepping of the existing Core Model outcome identity scan. The
// accepted invocation binding owns the original output/issuer throughout;
// no Source, Model, Result transformer, Ledger or send is started here.
import {setImmediate as yieldEventLoop} from 'node:timers/promises';
import {runtimeField} from '../host-common/compiler-binding.generated.mjs';
import {checked} from '../host-common/runtime-result.mjs';

type Runtime = Readonly<{
  clientProgramInferModelIdentityStartCapacity?(binding: unknown): unknown;
  clientProgramInferModelIdentityStart?(binding: unknown): unknown;
  clientProgramInferModelIdentityNextCapacity?(scan: unknown): unknown;
  clientProgramInferModelIdentityAdvance?(scan: unknown, quantum: number, retained: bigint, execution: bigint): unknown;
  clientProgramInferModelIdentityFinish?(scan: unknown): unknown;
  clientProgramInferModelIdentityCancel?(scan: unknown): boolean;
  clientProgramInferModelIdentityReceiptCancel?(receipt: unknown): void;
  clientProgramInferModelObservationCapacity?(binding: unknown, receipt: unknown, bytes: number): unknown;
}>;
type OriginalObservation<Binding> = Readonly<{
  binding: Binding; scan: unknown; receipt: unknown; retainedBytes: bigint; executionBytes: bigint;
}>;
type ObservationOptions<Binding, Result> = Readonly<{
  moon: Runtime; operation: Readonly<{growOriginalPublicationCapacity(retained: bigint, execution: bigint): unknown}>;
  binding: Binding; consume(original: OriginalObservation<Binding>): Result | PromiseLike<Result>;
  signal?: AbortSignal; quantum?: number; retainedBase?: bigint; executionBase?: bigint;
}>;

const extent = (value: unknown): [bigint, bigint] => {
  if (value === null || typeof value !== 'object') {
    throw new TypeError('InferModelObservationCapacityUnavailable');
  }
  const retained = runtimeField(value, 0), execution = runtimeField(value, 1);
  if (typeof retained !== 'bigint' || typeof execution !== 'bigint' ||
      retained < 0n || execution < 0n) {
    throw new TypeError('InferModelObservationCapacityUnavailable');
  }
  return [retained, execution];
};

export async function withOriginalInferModelObservation<Binding, Result>({moon, operation, binding,
  consume, signal, quantum = 256, retainedBase = 0n, executionBase = 0n}: ObservationOptions<Binding, Result>) {
  if (typeof retainedBase !== 'bigint' || retainedBase < 0n ||
      typeof executionBase !== 'bigint' || executionBase < 0n ||
      typeof consume !== 'function' ||
      typeof operation?.growOriginalPublicationCapacity !== 'function' ||
      !Number.isSafeInteger(quantum) || quantum < 1 || quantum > 2147483647 ||
      !['clientProgramInferModelIdentityStartCapacity', 'clientProgramInferModelIdentityStart',
        'clientProgramInferModelIdentityNextCapacity', 'clientProgramInferModelIdentityAdvance',
        'clientProgramInferModelIdentityFinish', 'clientProgramInferModelIdentityCancel',
        'clientProgramInferModelIdentityReceiptCancel', 'clientProgramInferModelObservationCapacity']
        .every(name => typeof moon?.[name as keyof Runtime] === 'function')) {
    throw new TypeError('InferModelObservationUnavailable');
  }
  signal?.throwIfAborted();
  let [retained, execution] = extent(moon.clientProgramInferModelIdentityStartCapacity!(binding));
  operation.growOriginalPublicationCapacity(retainedBase + retained, executionBase + execution);
  const scan = checked(moon.clientProgramInferModelIdentityStart!(binding));
  let receipt: unknown;
  try {
    for (;;) {
      signal?.throwIfAborted();
      const [nextRetained, nextExecution] = extent(
        moon.clientProgramInferModelIdentityNextCapacity!(scan));
      retained = nextRetained > retained ? nextRetained : retained;
      execution = nextExecution > execution ? nextExecution : execution;
      operation.growOriginalPublicationCapacity(retainedBase + retained, executionBase + execution);
      const progress = checked(moon.clientProgramInferModelIdentityAdvance!(
        scan, quantum, nextRetained, nextExecution));
      if (runtimeField(progress, 0)) break;
      await yieldEventLoop();
    }
    signal?.throwIfAborted();
    receipt = checked(moon.clientProgramInferModelIdentityFinish!(scan));
    // This is the existing finite Model observation codec, not a row cap.
    const [writerRetained, writerExecution] = extent(
      moon.clientProgramInferModelObservationCapacity!(binding, receipt, 16384));
    const retainedBytes = retained + writerRetained, executionBytes = execution + writerExecution;
    operation.growOriginalPublicationCapacity(retainedBase + retainedBytes, executionBase + executionBytes);
    return await consume({binding, scan, receipt, retainedBytes, executionBytes});
  } finally {
    if (receipt !== undefined) moon.clientProgramInferModelIdentityReceiptCancel!(receipt);
    moon.clientProgramInferModelIdentityCancel!(scan);
  }
}
