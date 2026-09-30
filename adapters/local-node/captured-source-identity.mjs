// On-demand identity for an already captured file representation. This adapter
// supplies I/O and real event-loop yields; exact admission and identity belong
// to the existing MoonBit storage verifier and acquisition owner.
import {setImmediate as yieldEventLoop} from 'node:timers/promises';
import {checked} from '../host-common/runtime-result.mjs';
import {retainedStorageBody, retainedStorageContract} from
  '../store-local/representations.mjs';
import {createMoonBitRetainedRowFrames} from
  '../store-local/moonbit-row-frames.mjs';

export async function identifyRetainedCapturedSource(moon, source, signal) {
  signal?.throwIfAborted();
  const scan = checked(moon.clientProgramPrepareCapturedSourceIdentityScan(source));
  let frames;
  try {
    const material = moon.clientProgramCapturedSourceIdentityScanMaterial(scan);
    if (material == null) throw new Error('CapturedSourceStorageUnavailable');
    const contract = retainedStorageContract(material);
    if (!Number.isSafeInteger(contract.maxFrameBytes) ||
        contract.maxFrameBytes < 1 || contract.maxFrameBytes > 65536) {
      throw new RangeError('CapturedSourceIdentityFrameLimit');
    }
    frames = createMoonBitRetainedRowFrames({
      retainedFramesPrepare: moon.strategyPrepareDurableResultRowFrames,
      retainedFramesFeed: moon.strategyFeedDurableResultRowFrames,
      retainedFramesFinish: moon.strategyFinishDurableResultRowFrames,
      retainedFramesCancel: moon.strategyCancelDurableResultRowFrames,
    }, {maxBytes: 10000000, maxRows: 10000, maxRowBytes: 65536,
      maxDepth: 64, maxFrameBytes: contract.maxFrameBytes}, async row => {
      signal?.throwIfAborted();
      checked(moon.clientProgramAppendCapturedSourceIdentityScan(scan, row));
      await yieldEventLoop(undefined, {signal});
      signal?.throwIfAborted();
    });
    await retainedStorageBody(material).consume(
      chunk => frames.feed(chunk, signal), signal);
    signal?.throwIfAborted();
    frames.finish();
    return checked(moon.clientProgramFinishCapturedSourceIdentityScan(scan));
  } finally {
    frames?.cancel();
    // Dispose only this pass, not the captured source or its Store custody.
    moon.clientProgramCancelCapturedSourceIdentityScan(scan);
  }
}
