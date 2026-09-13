// One broad row receipt; filter/select are the acquisition's Local residual.
// The trusted MoonBit port owns catalog, value and retention validation.
import { DuckDBTransportError, withSourceDatabase } from './session.mjs';

const attempted = new WeakSet();

export async function runBroadAcquisition(grant, port, limits, signal) {
  if (attempted.has(port)) throw new DuckDBTransportError('AttemptAlreadyStarted');
  attempted.add(port);
  const readView = Object.freeze({});
  try {
    return await withSourceDatabase(grant, limits, async session => {
      const metadata = await session.command(port.metadataSql(), port.metadataParameters(),
        chunk => port.acceptMetadata(chunk, readView));
      await port.finishMetadata(metadata, readView);
      const before = session.usage();
      let begun = false;
      const begin = async fields => { await port.beginReceipt(fields, readView); begun = true; };
      const fields = await session.command(port.scanSql(), [], async chunk => {
        if (!begun) await begin(chunk.fields);
        await port.acceptChunk(chunk, readView);
      });
      if (!begun) await begin(fields);
      const accepted = await port.finishReceipt(readView);
      const after = session.usage();
      const transport = Object.freeze(Object.fromEntries(
        Object.keys(before).map(key => [key, after[key] - before[key]]),
      ));
      return Object.freeze({ readView, accepted, transport });
    }, signal);
  } catch (error) {
    try { await port.abort(error, readView); }
    catch (cleanup) {
      throw new DuckDBTransportError('ReceiverCleanupFailed', {
        cause: new AggregateError([error, cleanup]),
      });
    }
    throw error;
  }
}
