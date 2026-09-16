// Host-private orchestration of the two distinct row receipts. The port owns
// MoonBit schema/value/guard checks; this module never substitutes SQL typing
// or row-count equality for those checks and does not issue capture evidence.
import { DuckDBTransportError } from './session.mjs';
import { withSourceAcquisition } from './source-acquisition.mjs';

export async function runNativeAcquisition(grant, port, limits, signal, accounting) {
  return await withSourceAcquisition(grant, port, limits, signal, async (session, readView) => {
    const started = performance.now();
    // The trusted adapter supplies catalog-only SQL, not a source-row query.
    // Metadata transport remains in the session ledger, outside both receipts.
    const metadataFields = await session.command(port.metadataSql(),
      port.metadataParameters(), chunk => port.acceptMetadata(chunk, readView));
    await port.finishMetadata(metadataFields, readView);
    const metadataMilliseconds = performance.now() - started;
    const receive = async (role, sql, parameters) => {
      const receiptStarted = performance.now();
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
      return Object.freeze({ accepted, transport,
        milliseconds: performance.now() - receiptStarted });
    };
    const validation = await receive('validation_scan', port.validationSql(), []);
    // Await complete pinned validation before starting native filtering.
    if (signal?.aborted) throw new DuckDBTransportError('Cancelled');
    const native = await receive('native_result', port.nativeSql(), port.nativeParameters());
    // These wall-clock phases include receiver work (validation, encoding and
    // storage where installed), not just SQL execution. Session command/callback
    // timers are nested within them and must not be added to these totals.
    // Opening/settling/closing the source session is outside this body timer.
    return Object.freeze({ readView, validation, native,
      diagnostics: Object.freeze({
        metadataMilliseconds,
        validationMilliseconds: validation.milliseconds,
        nativeResultMilliseconds: native.milliseconds,
        bodyMilliseconds: performance.now() - started,
      }) });
  }, accounting);
}
