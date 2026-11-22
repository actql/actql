// Host-private receipt lifecycle. This is transport provenance, not an ActQL
// execution record: the MoonBit issuer must also check semantics and retention.
import { DuckDBTransportError, withSourceDatabase } from './session.mjs';
import {AcquisitionOpenError, acquisitionFailure} from '../../../host-common/acquisition-outcome.mjs';
import {ExecutionAuthorizationError} from '../../../host-common/authorization-gate.mjs';

export type SourceLimits = Parameters<typeof withSourceDatabase>[1];
export type SourceSession = Parameters<Parameters<typeof withSourceDatabase>[2]>[0];
export type SourceAccounting = Parameters<typeof withSourceDatabase>[4];
export type SourceFields = Awaited<ReturnType<SourceSession['command']>>;
export type SourceParameters = Parameters<SourceSession['command']>[1];
export type SourceChunk = Parameters<Parameters<SourceSession['command']>[2]>[0];
export type SourceSettlement<Value> = Awaited<ReturnType<typeof withSourceAcquisition<Value>>>;
export type SourceReceiptPort = Readonly<{
  abort(cause: unknown, readView: object): unknown;
  metadataSql(): string;
  metadataParameters(): SourceParameters;
  acceptMetadata(chunk: SourceChunk, readView: object): unknown;
  finishMetadata(fields: SourceFields, readView: object): unknown;
}>;
export type SourceRecovery = Readonly<{
  close(): unknown;
  cleanup(): unknown;
  cleanupPending(): boolean;
}>;

type CleanupStatus = Readonly<{pending: boolean; errors: readonly unknown[]}>;
type CleanupHandle = Readonly<{status(): CleanupStatus | undefined; retry(): unknown}>;
type CleanupState = {
  primaryFailure?: unknown;
  cleanupErrors?: readonly unknown[];
  cleanupPending?: boolean;
  cleanupHandle?: CleanupHandle;
};

const attempted = new WeakSet<object>();
const completed = new WeakMap<object, Readonly<{
  grant: object; port: object; readView: object; session: SourceSession | undefined;
}>>();

// Keep the transport's existing cleanupHandle protocol as well as the Run's
// acquisition recovery handoff. Both describe this same owner, not two jobs.
export function sourceAcquisitionFailure(cause: unknown, outcome: unknown, recovery?: SourceRecovery) {
  const reason = cause instanceof AcquisitionOpenError ? Object.assign(
    new Error(cause.message, {cause}), {code: cause.code},
  ) : cause;
  const failure = acquisitionFailure(reason, outcome, recovery) as AcquisitionOpenError & CleanupState;
  if (recovery !== undefined) {
    const status = () => Object.freeze({pending: recovery.cleanupPending(),
      errors: Object.freeze([...((cause as CleanupState | null | undefined)?.cleanupErrors ?? [])])});
    failure.primaryFailure = (cause as CleanupState | null | undefined)?.primaryFailure ?? cause;
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
export async function withSourceAcquisition<Value>(
  grant: object, port: Pick<SourceReceiptPort, 'abort'>, limits: SourceLimits, signal: AbortSignal | undefined,
  body: (session: SourceSession, readView: object) => Value | Promise<Value>, accounting?: SourceAccounting,
) {
  if (attempted.has(port)) throw new DuckDBTransportError('AttemptAlreadyStarted');
  attempted.add(port);
  const readView = Object.freeze({});
  let ownedSession: SourceSession | undefined;
  let started = false, stopped = false;
  // These are observations from the physical session owner, including later
  // settlement after a cancellation deadline. A rejected Promise is not one.
  const physical = Object.freeze({
    started() { started = true; accounting?.started(); },
    chargeTransfer(bytes: number) { accounting?.chargeTransfer(bytes); },
    settled(confirmed: boolean) { stopped = confirmed; accounting?.settled(confirmed); },
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
    const cleanupErrors: unknown[] = [];
    try { await port.abort(error, readView); }
    catch (cleanup) {
      abortPending = true;
      cleanupErrors.push(cleanup);
    }
    const upstream = (error as CleanupState | null | undefined)?.cleanupHandle;
    const pending = () => abortPending || (started && !stopped) ||
      (upstream?.status()?.pending ?? (error as CleanupState | null | undefined)?.cleanupPending === true);
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
export function matchesSourceAcquisition(result: unknown, grant: unknown, port: unknown, readView: unknown) {
  const owned = completed.get(result as object);
  return owned !== undefined && owned.grant === grant && owned.port === port
    && owned.readView === readView && owned.session !== undefined;
}

// Explicit issuer/observation teardown, not a consumer failure hook. Other
// attempts and successful observations keep their own independent ownership.
export function releaseSourceAcquisition(result: object) {
  completed.delete(result);
}
