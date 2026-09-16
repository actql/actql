// Local's asynchronous physical reader. The installed MoonBit operations own
// admission, transfer charging, typed decoding and logical identity verification.
// No filesystem, DuckDB runtime or expression semantics belong in this wrapper.
import {retainedInputContract, consumeRetainedInput} from '../store-local/representations.mjs';
import {createRetainedRowFrames} from '../store-local/row-frames.mjs';

export async function readLocalRetainedInput(operation, checked, signal) {
  // Snapshot the exact attempt/port operations before any asynchronous boundary.
  const {material, input, begin, charge, append, finish} = operation;
  const limits = Object.freeze({...operation.frames});
  signal?.throwIfAborted();
  for (const fn of [checked, begin, charge, append, finish]) {
    if (typeof fn !== 'function') throw new TypeError('InvalidLocalImportOperations');
  }
  const contract = retainedInputContract(material, input);
  if (!Number.isSafeInteger(contract.maxFrameBytes) || contract.maxFrameBytes < 1 ||
      contract.maxFrameBytes > limits.maxFrameBytes) {
    throw new RangeError('LocalImportFrameLimit');
  }
  const frames = createRetainedRowFrames(limits, row => {
    signal?.throwIfAborted();
    checked(append(row));
  });
  try {
    signal?.throwIfAborted();
    checked(begin());
    await consumeRetainedInput(material, input, async chunk => {
      signal?.throwIfAborted();
      if (!(chunk instanceof Uint8Array)) throw new TypeError('InvalidLocalImportFrame');
      // Charge bytes actually received even when the frame/row later fails.
      // The common reservation prevents exceeding the admitted transfer ceiling.
      checked(charge(BigInt(chunk.byteLength)));
      await frames.feed(chunk, signal);
    }, signal);
    signal?.throwIfAborted();
    const usage = frames.finish();
    // Store integrity and complete framing precede common logical verification.
    checked(finish());
    return usage;
  } finally {
    // This is parser disposal, not evidence of Store cleanup or task settlement.
    frames.cancel();
  }
}
