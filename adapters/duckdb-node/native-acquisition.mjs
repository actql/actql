// Host-private orchestration of the two distinct row receipts. The port owns
// MoonBit schema/value/guard checks; this module never substitutes SQL typing
// or row-count equality for those checks and does not issue capture evidence.
import { DuckDBTransportError, withSourceDatabase } from './session.mjs';

const attempted = new WeakSet();

export async function runNativeAcquisition(grant, port, limits, signal) {
  if (attempted.has(port)) throw new DuckDBTransportError('AttemptAlreadyStarted');
  attempted.add(port);
  // A fresh private discriminator, not a path/mtime-derived snapshot token.
  // It contains no connection and cannot be used by a fixed-input Compute.
  const readView = Object.freeze({});
  try {
    return await withSourceDatabase(grant, limits, async session => {
      // The trusted adapter supplies catalog-only SQL, not a source-row query.
      // Metadata transport remains in the session ledger, outside both receipts.
      const metadataFields = await session.command(port.metadataSql(),
        port.metadataParameters(), chunk => port.acceptMetadata(chunk, readView));
      await port.finishMetadata(metadataFields, readView);
      const receive = async (role, sql, parameters) => {
        let begun = false;
        const begin = async fields => {
          await port.beginReceipt(role, fields, readView);
          begun = true;
        };
        const before = session.usage();
        const fields = await session.command(sql, parameters, async chunk => {
          if (!begun) await begin(chunk.fields);
          await port.acceptChunk(role, chunk, readView);
        });
        // Empty result metadata still undergoes MoonBit type compatibility.
        if (!begun) await begin(fields);
        const accepted = await port.finishReceipt(role, readView);
        const after = session.usage();
        const transport = Object.freeze(Object.fromEntries(
          Object.keys(before).map(key => [key, after[key] - before[key]]),
        ));
        return Object.freeze({ accepted, transport });
      };
      const validation = await receive('validation_scan', port.validationSql(), []);
      // Await complete pinned validation before starting native filtering.
      if (signal?.aborted) throw new DuckDBTransportError('Cancelled');
      const native = await receive('native_result', port.nativeSql(), port.nativeParameters());
      return Object.freeze({ readView, validation, native });
    }, signal);
  } catch (error) {
    // Includes native settlement/rollback/close failures, not just row callbacks.
    // Provisional receivers and retained chunks must be made unusable for capture.
    try { await port.abort(error, readView); }
    catch (cleanup) {
      throw new DuckDBTransportError('ReceiverCleanupFailed', {
        cause: new AggregateError([error, cleanup]),
      });
    }
    throw error;
  }
}
