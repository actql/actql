// Private shared settlement/cleanup mechanics, not a Connector registration API.
import { matchesSourceAcquisition, releaseSourceAcquisition,
  sourceAcquisitionFailure } from './source-acquisition.mjs';
import { DuckDBTransportError } from './session.mjs';
import {acquisitionOutcome} from
  '../../../host-common/acquisition-outcome.mjs';
import {ExecutionAuthorizationError} from '../../../host-common/authorization-gate.mjs';

export async function runSettledQuery(grant, prepare, limits, signal, acquire, accepts, accounting) {
  let bridge;
  let settled;
  let closed = false;
  let released = false;
  let acquiring = false;
  const verify = attempt => !closed && bridge !== undefined && settled !== undefined
    && attempt === bridge.attempt && accepts(settled.value, attempt)
    && matchesSourceAcquisition(settled, grant, bridge.port, settled.value.readView);
  const close = () => {
    if (released) return;
    closed = true;
    bridge?.close();
    if (settled !== undefined) releaseSourceAcquisition(settled);
    settled = undefined;
    bridge = undefined;
    released = true;
  };
  try {
    // A synchronous trusted factory installs verify on the MoonBit issuer.
    bridge = prepare(verify);
    signal?.throwIfAborted();
    acquiring = true;
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
      usage: settled.usage,
      diagnostics: settled.value.diagnostics,
      bindInput(...args) {
        if (closed) throw new DuckDBTransportError('IssuerClosed');
        // Consumer failures do not release a successful acquisition or reread.
        return bridge.bindInput(observation, ...args);
      },
      close,
    });
  } catch (error) {
    const ended = settled !== undefined ? {outcome: 'stopped'} :
      !acquiring || error instanceof ExecutionAuthorizationError
        ? {outcome: 'not_started'} : acquisitionOutcome(error);
    const failures = [error];
    try { bridge?.abort(); } catch (cleanup) { failures.push(cleanup); }
    try { close(); } catch (cleanup) { failures.push(cleanup); }
    const recovery = Object.freeze({
      close() {},
      async cleanup() {
        if (ended.recovery !== undefined) {
          await ended.recovery.close();
          await ended.recovery.cleanup();
        }
        close();
        return !recovery.cleanupPending();
      },
      cleanupPending: () => !released ||
        ended.recovery?.cleanupPending() === true ||
        (ended.outcome === 'unknown' && ended.recovery === undefined),
    });
    const pending = recovery.cleanupPending();
    if (!pending && failures.length === 1 &&
        error instanceof ExecutionAuthorizationError) throw error;
    // Wrapping is required only when issuer cleanup adds a failure or an
    // unknown session owner must be retained; never replace its primary cause.
    const cause = failures.length > 1 ? Object.assign(
      new DuckDBTransportError('QueryCleanupFailed', {cause: new AggregateError(failures)}),
      {primaryFailure: error, cleanupErrors: Object.freeze(failures.slice(1))},
    ) : error;
    throw sourceAcquisitionFailure(cause, pending ? 'unknown' : ended.outcome,
      pending ? recovery : undefined);
  }
}
