// Physical stepping of the existing Core Model outcome identity scan. The
// accepted invocation binding owns the original output/issuer throughout;
// no Source, Model, Result transformer, Ledger or send is started here.
import {setImmediate as yieldEventLoop} from 'node:timers/promises';
import {runtimeField} from '../host-common/compiler-binding.generated.mjs';
import {checked} from '../host-common/runtime-result.mjs';

const extent = value => {
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

export async function withOriginalInferModelObservation({moon, operation, binding,
  consume, signal, quantum = 256}) {
  if (typeof consume !== 'function' ||
      typeof operation?.growOriginalPublicationCapacity !== 'function' ||
      !Number.isSafeInteger(quantum) || quantum < 1 || quantum > 2147483647 ||
      !['clientProgramInferModelIdentityStartCapacity', 'clientProgramInferModelIdentityStart',
        'clientProgramInferModelIdentityNextCapacity', 'clientProgramInferModelIdentityAdvance',
        'clientProgramInferModelIdentityFinish', 'clientProgramInferModelIdentityCancel',
        'clientProgramInferModelIdentityReceiptCancel', 'clientProgramInferModelObservationCapacity']
        .every(name => typeof moon?.[name] === 'function')) {
    throw new TypeError('InferModelObservationUnavailable');
  }
  signal?.throwIfAborted();
  let [retained, execution] = extent(moon.clientProgramInferModelIdentityStartCapacity(binding));
  operation.growOriginalPublicationCapacity(retained, execution);
  const scan = checked(moon.clientProgramInferModelIdentityStart(binding));
  let receipt;
  try {
    for (;;) {
      signal?.throwIfAborted();
      const [nextRetained, nextExecution] = extent(
        moon.clientProgramInferModelIdentityNextCapacity(scan));
      retained = nextRetained > retained ? nextRetained : retained;
      execution = nextExecution > execution ? nextExecution : execution;
      operation.growOriginalPublicationCapacity(retained, execution);
      const progress = checked(moon.clientProgramInferModelIdentityAdvance(
        scan, quantum, nextRetained, nextExecution));
      if (runtimeField(progress, 0)) break;
      await yieldEventLoop();
    }
    signal?.throwIfAborted();
    receipt = checked(moon.clientProgramInferModelIdentityFinish(scan));
    // This is the existing finite Model observation codec, not a row cap.
    const [writerRetained, writerExecution] = extent(
      moon.clientProgramInferModelObservationCapacity(binding, receipt, 16384));
    operation.growOriginalPublicationCapacity(retained + writerRetained, execution + writerExecution);
    return await consume({binding, scan, receipt});
  } finally {
    if (receipt !== undefined) moon.clientProgramInferModelIdentityReceiptCancel(receipt);
    moon.clientProgramInferModelIdentityCancel(scan);
  }
}
