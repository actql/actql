// Host-private receipt lifecycle. This is transport provenance, not an ActQL
// execution record: the MoonBit issuer must also check semantics and retention.
import { DuckDBTransportError, withSourceDatabase } from './session.mjs';

const attempted = new WeakSet();
const completed = new WeakMap();

// Only trusted acquisition adapters call this with their fixed receipt plan.
// Neither Program data nor a provider's serialized claim chooses the body.
export async function withSourceAcquisition(grant, port, limits, signal, body) {
  if (attempted.has(port)) throw new DuckDBTransportError('AttemptAlreadyStarted');
  attempted.add(port);
  const readView = Object.freeze({});
  let ownedSession;
  try {
    const result = await withSourceDatabase(grant, limits, async session => {
      ownedSession = session;
      return await body(session, readView);
    }, signal);
    // withSourceDatabase returns only after all commands, transaction settlement
    // and connection cleanup succeed. The retained session is already closed;
    // it records the actual lifetime, not a connection available to Compute.
    completed.set(result, { grant, port, readView, session: ownedSession });
    return result;
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
