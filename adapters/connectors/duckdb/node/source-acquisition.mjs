// Host-private receipt lifecycle. This is transport provenance, not an ActQL
// execution record: the MoonBit issuer must also check semantics and retention.
import { DuckDBTransportError, withSourceDatabase } from './session.mjs';
import {AcquisitionOpenError, acquisitionFailure} from '../../../host-common/acquisition-outcome.mjs';
import {ExecutionAuthorizationError} from '../../../host-common/authorization-gate.mjs';

const attempted = new WeakSet();
const completed = new WeakMap();

// Keep the transport's existing cleanupHandle protocol as well as the Run's
// acquisition recovery handoff. Both describe this same owner, not two jobs.
export function sourceAcquisitionFailure(cause, outcome, recovery) {
  const reason = cause instanceof AcquisitionOpenError ? Object.assign(
    new Error(cause.message, {cause}), {code: cause.code},
  ) : cause;
  const failure = acquisitionFailure(reason, outcome, recovery);
  if (recovery !== undefined) {
    const status = () => Object.freeze({pending: recovery.cleanupPending(),
      errors: Object.freeze([...(cause?.cleanupErrors ?? [])])});
    failure.primaryFailure = cause?.primaryFailure ?? cause;
    failure.cleanupErrors = status().errors;
    failure.cleanupPending = status().pending;
    failure.cleanupHandle = Object.freeze({status,
      async retry() {
        await recovery.cleanup();
        const observed = status();
        failure.cleanupPending = observed.pending;
        return observed;
      },
    });
  }
  return failure;
}

// Only trusted acquisition adapters call this with their fixed receipt plan.
// Neither Program data nor a provider's serialized claim chooses the body.
export async function withSourceAcquisition(grant, port, limits, signal, body, accounting) {
  if (attempted.has(port)) throw new DuckDBTransportError('AttemptAlreadyStarted');
  attempted.add(port);
  const readView = Object.freeze({});
  let ownedSession;
  let started = false, stopped = false;
  // These are observations from the physical session owner, including later
  // settlement after a cancellation deadline. A rejected Promise is not one.
  const physical = Object.freeze({
    started() { started = true; accounting?.started(); },
    chargeTransfer(bytes) { accounting?.chargeTransfer(bytes); },
    settled(confirmed) { stopped = confirmed; accounting?.settled(confirmed); },
  });
  try {
    const result = await withSourceDatabase(grant, limits, async session => {
      ownedSession = session;
      return await body(session, readView);
    }, signal, physical);
    // withSourceDatabase returns only after all commands, transaction settlement
    // and connection cleanup succeed. The retained session is already closed;
    // it records the actual lifetime, not a connection available to Compute.
    completed.set(result, { grant, port, readView, session: ownedSession });
    return result;
  } catch (error) {
    let abortPending = false;
    const cleanupErrors = [];
    try { await port.abort(error, readView); }
    catch (cleanup) {
      abortPending = true;
      cleanupErrors.push(cleanup);
    }
    const upstream = error?.cleanupHandle;
    const pending = () => abortPending || (started && !stopped) ||
      (upstream?.status()?.pending ?? error?.cleanupPending === true);
    const recovery = Object.freeze({
      close() {}, // the failed acquisition already requested abort/settlement
      async cleanup() {
        if (upstream?.status()?.pending) await upstream.retry();
        if (abortPending) {
          await port.abort(error, readView);
          abortPending = false;
        }
        return !pending();
      },
      cleanupPending: pending,
    });
    const cause = cleanupErrors.length ? Object.assign(
      new DuckDBTransportError('ReceiverCleanupFailed', {
        cause: new AggregateError([error, ...cleanupErrors]),
      }), {primaryFailure: error, cleanupErrors: Object.freeze(cleanupErrors)},
    ) : error;
    // Authorization decisions are already typed and never open a physical
    // session. Preserve their public denial/defer evidence when cleanup ended.
    if (!pending() && !started && error instanceof ExecutionAuthorizationError) {
      throw error;
    }
    throw sourceAcquisitionFailure(cause, pending() ? 'unknown' :
      started ? 'stopped' : 'not_started', pending() ? recovery : undefined);
  }
}

// Exact live handles only. Same path, SQL, rows, counters or copied JSON do not
// establish the required relationship. This does not validate MoonBit output.
export function matchesSourceAcquisition(result, grant, port, readView) {
  const owned = completed.get(result);
  return owned !== undefined && owned.grant === grant && owned.port === port
    && owned.readView === readView && owned.session !== undefined;
}

// Explicit issuer/observation teardown, not a consumer failure hook. Other
// attempts and successful observations keep their own independent ownership.
export function releaseSourceAcquisition(result) {
  completed.delete(result);
}
