// Private shared settlement/cleanup mechanics, not a Connector registration API.
import { matchesSourceAcquisition, releaseSourceAcquisition } from './source-acquisition.mjs';
import { DuckDBTransportError } from './session.mjs';

export async function runSettledQuery(grant, prepare, limits, signal, acquire, accepts, accounting) {
  let bridge;
  let settled;
  let closed = false;
  const verify = attempt => !closed && bridge !== undefined && settled !== undefined
    && attempt === bridge.attempt && accepts(settled.value, attempt)
    && matchesSourceAcquisition(settled, grant, bridge.port, settled.value.readView);
  const close = () => {
    if (closed) return;
    closed = true;
    try { bridge?.close(); }
    finally {
      if (settled !== undefined) releaseSourceAcquisition(settled);
      settled = undefined;
    }
  };
  try {
    // A synchronous trusted factory installs verify on the MoonBit issuer.
    bridge = prepare(verify);
    signal?.throwIfAborted();
    settled = await acquire(grant, bridge.port, limits, signal, accounting);
    signal?.throwIfAborted();
    if (!verify(bridge.attempt)) throw new DuckDBTransportError('ForeignAcceptedAttempt');
    // These are synchronous MoonBit state transitions: settlement, guarded
    // demand/guards, retention, evidence and capture. No new source access is allowed.
    const observation = bridge.complete();
    if (observation === undefined || observation === null || typeof observation.then === 'function') {
      throw new DuckDBTransportError('InvalidCaptureCompletion');
    }
    return Object.freeze({
      observation,
      bindInput(...args) {
        if (closed) throw new DuckDBTransportError('IssuerClosed');
        // Consumer failures do not release a successful acquisition or reread.
        return bridge.bindInput(observation, ...args);
      },
      close,
    });
  } catch (error) {
    const failures = [error];
    try { bridge?.abort(); } catch (cleanup) { failures.push(cleanup); }
    try { close(); } catch (cleanup) { failures.push(cleanup); }
    if (failures.length > 1) {
      throw new DuckDBTransportError('QueryCleanupFailed', { cause: new AggregateError(failures) });
    }
    throw error;
  }
}
