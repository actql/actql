// Local's asynchronous physical reader. The installed MoonBit operations own
// admission, transfer charging, typed decoding and logical identity verification.
// No filesystem, DuckDB runtime or expression semantics belong in this wrapper.
import {retainedInputContract, retainedStorageBody, consumeRetainedInput} from '../store-local/representations.mjs';
import {createMoonBitRetainedRowFrames} from '../store-local/moonbit-row-frames.mjs';
import type {MoonBitRetainedFrameBindings} from '../store-local/moonbit-row-frames.mjs';
import type {RetainedRowFrameLimits} from '../store-local/row-frames.mjs';

type LocalRetainedFrameBindings = Readonly<{
  strategyPrepareDurableResultRowFrames: MoonBitRetainedFrameBindings['retainedFramesPrepare'];
  strategyFeedDurableResultRowFrames: MoonBitRetainedFrameBindings['retainedFramesFeed'];
  strategyFinishDurableResultRowFrames: MoonBitRetainedFrameBindings['retainedFramesFinish'];
  strategyCancelDurableResultRowFrames: MoonBitRetainedFrameBindings['retainedFramesCancel'];
}>;
type RetainedInputOperation = Readonly<{
  material: object;
  input: unknown;
  frames: RetainedRowFrameLimits;
  begin(): unknown;
  charge(bytes: bigint): unknown;
  append(row: string): unknown;
  finish(): unknown;
}>;

export async function readLocalRetainedInput(moon: LocalRetainedFrameBindings, operation: RetainedInputOperation,
  checked: (result: unknown) => unknown, signal?: AbortSignal) {
  // Snapshot the exact attempt/port operations before any asynchronous boundary.
  const {material, input, begin, charge, append, finish} = operation;
  const limits = {...operation.frames};
  signal?.throwIfAborted();
  for (const fn of [checked, begin, charge, append, finish]) {
    if (typeof fn !== 'function') throw new TypeError('InvalidLocalImportOperations');
  }
  const contract = retainedInputContract(material, input);
  if (!Number.isSafeInteger(contract.maxFrameBytes) || contract.maxFrameBytes < 1 ||
      contract.maxFrameBytes > limits.maxFrameBytes) {
    throw new RangeError('LocalImportFrameLimit');
  }
  // This SAME registered body was sealed from the canonical output batches.
  // Its immutable byte count bounds every row supplied by consumeRetainedInput;
  // a policy ceiling need not become an eagerly allocated row buffer. Keep
  // the original pre-admitted Task floor and all later import/Store checks.
  const body = retainedStorageBody(material);
  const extent = Object.isFrozen(body) ? Object.getOwnPropertyDescriptor(body, 'bytes') : undefined;
  const bodyBytes: unknown = extent && Object.hasOwn(extent, 'value') ? extent.value : undefined;
  if (Number.isSafeInteger(bodyBytes) && (bodyBytes as number) >= 0 && (bodyBytes as number) <= 2147483647) {
    limits.maxBytes = Math.min(limits.maxBytes, bodyBytes as number);
    limits.maxRowBytes = Math.min(limits.maxRowBytes, Math.max(1, bodyBytes as number));
  }
  Object.freeze(limits);
  const frames = createMoonBitRetainedRowFrames(Object.freeze({
    retainedFramesPrepare:
      moon.strategyPrepareDurableResultRowFrames,
    retainedFramesFeed:
      moon.strategyFeedDurableResultRowFrames,
    retainedFramesFinish:
      moon.strategyFinishDurableResultRowFrames,
    retainedFramesCancel:
      moon.strategyCancelDurableResultRowFrames,
  }), limits, row => {
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
