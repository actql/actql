// Trusted Host implementation primitive, invoked after common start/reservation.
// A reply is transport material, never authority to complete an ActQL task.
import { spawn } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import {types as utilTypes} from 'node:util';
import { encodeProcessFrame, createProcessFrameReader, validateFrameLimits, ProcessProtocolError, executionProtocol } from './process-frames.mjs';
import {encodeProcessLimits, decodeProcessUsage} from './process-accounting.mjs';
import type {Duplex} from 'node:stream';
import type {FrameLimits, ProcessFrameValue, UncheckedProcessEnvelope} from './process-frames.mjs';
import type {SynchronousAction} from './installed-host-cleanup.mjs';

type FrameReaderInput = Parameters<typeof createProcessFrameReader>;
type FrameGeometry = Parameters<NonNullable<FrameReaderInput[4]>>[0];
type FrameHook<Value> = (value: Value) => undefined;
type ExitStatus = Readonly<{code: number | null; signal: NodeJS.Signals | null}>;
type HostCall = Readonly<{session: string; run: string; sequence: number; call: number}>;
type ServiceCleanup = Readonly<{status: () => {pending: boolean}; retry: () => unknown}>;
type HostService = Readonly<{
  invoke(request: unknown, signal: AbortSignal, owner: HostCall): unknown;
  cleanupHandle: ServiceCleanup;
}>;
type Budget = Readonly<{
  limits: unknown;
  report(usage: ReturnType<typeof decodeProcessUsage>, terminal: boolean): ReturnType<SynchronousAction>;
}>;
type ExecutionPreparation = Readonly<{
  entry: URL; runtime?: URL; run: string; frames: FrameLimits; maxRequests: number;
  graceMs: number; startupMs: number; hostService?: HostService; maxHostCalls?: number;
  accounting?: Budget; beforeBodyAllocation?: FrameHook<number>;
  bodyReceived?: FrameHook<Buffer>; bodySnapshot?: FrameHook<FrameGeometry>;
}>;
type PreparedConfiguration = Omit<ExecutionPreparation, 'entry' | 'runtime' | 'hostService' | 'accounting' | 'maxHostCalls'> & Readonly<{
  executable: string; runtimePath: string; hello: Buffer; session: string; maxHostCalls: number;
  envelope: (kind: string, sequence: number, body: unknown) => object;
  budget?: Budget;
  service?: ServiceCleanup & Pick<HostService, 'invoke'>;
}>;
declare const executionPreparationBrand: unique symbol;
export type PreparedExecution = Readonly<{[executionPreparationBrand]: true}>;
type PendingRequest = {sequence: number; resolve: (value: ProcessFrameValue) => void;
  reject: (cause: unknown) => void; detach: () => void};

const preparations = new WeakMap<object, PreparedConfiguration>();
const NativePromise = Promise;
const nativeThen = Promise.prototype.then;

// Pure configuration validation precedes admission. The opaque preparation
// snapshots every value used by spawn and the handshake, including the URL.
export function prepareManagedExecution({ entry, runtime, run, frames, maxRequests, graceMs, startupMs,
  hostService, maxHostCalls = 0, accounting, beforeBodyAllocation, bodyReceived, bodySnapshot }: ExecutionPreparation) {
  frames = validateFrameLimits(frames);
  const budget = accounting === undefined ? undefined : Object.freeze({
    limits: encodeProcessLimits(accounting.limits), report: accounting.report,
  });
  if (budget && typeof budget.report !== 'function') throw new ProcessProtocolError('InvalidProcessAccounting');
  const service = hostService === undefined ? undefined : Object.freeze({
    invoke: hostService?.invoke,
    status: hostService?.cleanupHandle?.status,
    retry: hostService?.cleanupHandle?.retry,
  });
  if (!(entry instanceof URL) || entry.protocol !== 'file:' ||
      (runtime !== undefined && (!(runtime instanceof URL) || runtime.protocol !== 'file:')) ||
      typeof run !== 'string' || !run.length || run.length > 256 ||
      !Number.isSafeInteger(maxRequests) || maxRequests < 1 ||
      !Number.isSafeInteger(graceMs) || graceMs < 1 || graceMs > 60000 ||
      !Number.isSafeInteger(startupMs) || startupMs < 1 || startupMs > 60000 ||
      !Number.isSafeInteger(maxHostCalls) || maxHostCalls < 0 ||
      (beforeBodyAllocation !== undefined && (typeof beforeBodyAllocation !== 'function' ||
        utilTypes.isAsyncFunction(beforeBodyAllocation))) ||
      (bodyReceived !== undefined && (typeof bodyReceived !== 'function' ||
        utilTypes.isAsyncFunction(bodyReceived))) ||
      (bodySnapshot !== undefined && (typeof bodySnapshot !== 'function' ||
        utilTypes.isAsyncFunction(bodySnapshot))) ||
      (service === undefined ? maxHostCalls !== 0 :
        maxHostCalls < 1 || typeof service.invoke !== 'function' ||
        typeof service.status !== 'function' || typeof service.retry !== 'function')) {
    throw new ProcessProtocolError('InvalidExecutionConfiguration');
  }
  const session = randomUUID();
  const envelope = (kind: string, sequence: number, body: unknown) => ({ protocol: executionProtocol, session, run, kind, sequence, body });
  // Snapshot the executable and first message before performing any process I/O.
  const executable = fileURLToPath(entry);
  // The optional interpreter is trusted installation configuration, never a
  // Program-supplied command or arbitrary argument list. Preserve the default
  // Node launch and the same process-exit/cleanup owner for other runtimes.
  const runtimePath = runtime === undefined ? process.execPath : fileURLToPath(runtime);
  const hello = encodeProcessFrame(envelope('hello', 0, budget ? {resourceLimits: budget.limits} : null), frames);
  const prepared = Object.freeze({}) as PreparedExecution;
  preparations.set(prepared, { executable, runtimePath, hello, envelope, frames, session, run, maxRequests, graceMs, startupMs,
    service, maxHostCalls, budget, beforeBodyAllocation, bodyReceived, bodySnapshot });
  return prepared;
}

export async function startManagedExecution(configuration: ExecutionPreparation | PreparedExecution,
  signal?: AbortSignal, beforeSpawn?: () => undefined) {
  if (beforeSpawn !== undefined && typeof beforeSpawn !== 'function') {
    throw new TypeError('InvalidExecutionHandoff');
  }
  signal?.throwIfAborted();
  const prepared = preparations.has(configuration) ? configuration : prepareManagedExecution(configuration as ExecutionPreparation);
  const { executable, runtimePath, hello, envelope, frames, session, run, maxRequests, graceMs, startupMs,
    service, maxHostCalls, budget, beforeBodyAllocation, bodyReceived, bodySnapshot } = preparations.get(prepared)!;
  preparations.delete(prepared);
  signal?.throwIfAborted();
  // Installed Host accounting records the attempted physical handoff after
  // pure refusals. A callback-triggered abort keeps that debit but cannot spawn.
  // This trusted hook must finish synchronously and grants no authority.
  if (beforeSpawn !== undefined) {
    const result = beforeSpawn() as unknown;
    if (result !== undefined) {
      // Refuse async handoff without leaking an unobserved rejection.
      if (utilTypes.isPromise(result)) Promise.prototype.then.call(result, () => {}, () => {});
      throw new TypeError('InvalidExecutionHandoff');
    }
  }
  signal?.throwIfAborted();
  const child = spawn(runtimePath, [executable], {
    stdio: ['ignore', 'ignore', 'ignore', 'pipe'],
  });
  const stream = child.stdio[3] as Duplex;
  // Diagnostic wire counts, not logical transfer admission or delivery receipts.
  // Count attempted writes and every received byte, including rejected frames.
  let submittedBytes = 0n, receivedBytes = 0n;
  const writeFrame = (frame: Buffer, callback: (error?: Error | null) => void) => {
    submittedBytes += BigInt(frame.byteLength);
    return stream.write(frame, callback);
  };
  let exited = false;
  let stopped = false;
  let ready = false;
  let sequence = 0;
  let pending: PendingRequest | undefined;
  let hostCalls = 0, hostWork: Promise<void> | undefined, hostController: AbortController | undefined;
  let bodyAdmissionOriginal: unknown, bodyAdmissionJoin: Promise<void> | undefined;
  let lastUsageSequence = 0, terminalUsage = false;
  const servicePending = () => {
    try { return bodyAdmissionOriginal !== undefined || !!hostWork || !!service?.status().pending; }
    catch { return true; }
  };
  let stopTimer: ReturnType<typeof setTimeout> | undefined;
  let startTimer: ReturnType<typeof setTimeout> | undefined;
  let exitValue: ExitStatus | undefined;
  let resolveExit!: (value: ExitStatus) => void;
  const exit = new Promise<ExitStatus>(resolve => { resolveExit = resolve; });
  let resolveReady!: () => void;
  let rejectReady!: (reason: unknown) => void;
  const readyPromise = new Promise<void>((resolve, reject) => { resolveReady = resolve; rejectReady = reject; });
  const cleanupHandle = Object.freeze({
    status: () => Object.freeze({ pending: !exited || servicePending() }),
    // Resolution is exclusively an observed process exit or a no-PID spawn
    // failure. Channel closure and a stop request cannot resolve this promise.
    whenStopped: () => exit,
    retry: async () => {
      stop(); await exit;
      if (hostWork) await hostWork;
      if (bodyAdmissionJoin) await bodyAdmissionJoin;
      if (service) await service.retry();
      return Object.freeze({pending: !exited || servicePending()});
    },
  });
  const failure = (code: string, cause?: unknown) => {
    const error = new ProcessProtocolError(code) as ProcessProtocolError & {cleanupHandle: typeof cleanupHandle};
    error.cleanupHandle = cleanupHandle;
    if (cause !== undefined) error.cause = cause;
    return error;
  };
  const send = (message: unknown) => new Promise<void>((resolve, reject) => {
    let frame;
    try { frame = encodeProcessFrame(message, frames); }
    catch (error) { reject(error); return; }
    writeFrame(frame, error => error ? reject(error) : resolve());
  });
  const stop = () => {
    if (exited || stopped) return;
    stopped = true;
    hostController?.abort();
    // The worker may release cooperatively; only actual process exit settles
    // this process. An IPC disconnect or cancellation acknowledgement does not.
    send(envelope('stop', sequence, null)).catch(() => {});
    stopTimer = setTimeout(() => { if (!exited) child.kill('SIGKILL'); }, graceMs);
  };
  const rejectPending = (error: unknown) => {
    if (pending) { pending.detach(); pending.reject(error); pending = undefined; }
  };
  const broken = (cause: unknown) => {
    const error = cause instanceof Error ? cause : failure('ExecutionChannelFailure', cause);
    (error as Error & {cleanupHandle?: typeof cleanupHandle}).cleanupHandle = cleanupHandle;
    rejectReady(error);
    rejectPending(error);
    stop();
  };
  // Both original synchronous entries share this process's callback custody.
  // A returned task is not backing or received-byte proof; a failure closes
  // the reader, so no second task can overwrite the pending original.
  const bodyEntry = <Value,>(method: FrameHook<Value> | undefined) => method === undefined ? undefined : (value: Value) => {
    try {
      const result = method(value) as unknown;
      if (result !== undefined) {
        if (result !== null && ['object', 'function'].includes(typeof result)) {
          // A mistaken async entry is never accepted as backing. Retain the
          // SAME returned task under this process's existing cleanup custody;
          // process exit alone cannot release its original resource borrower.
          bodyAdmissionOriginal = result;
          if (utilTypes.isPromise(result)) {
            bodyAdmissionJoin = new NativePromise<void>(resolve => {
              const settled = () => {
                bodyAdmissionOriginal = bodyAdmissionJoin = undefined;
                resolve();
              };
              try { Reflect.apply(nativeThen, result, [settled, settled]); }
              catch { resolve(); } // Keep the unjoined original pending.
            });
          }
        }
        throw new TypeError('InvalidFrameCapacityHandoff');
      }
    }
    catch (cause) {
      // This SAME process owner must survive a refused/throwing resource
      // handoff too. Never mutate a frozen original or discard thrown undefined
      // while attaching the existing process-exit cleanup handle.
      const error = failure('ExecutionChannelFailure');
      error.cause = cause;
      throw error;
    }
  };
  const reader = createProcessFrameReader(frames, ((message: UncheckedProcessEnvelope) => {
    if (!message || message.protocol !== executionProtocol || message.session !== session ||
        message.run !== run || !Number.isSafeInteger(message.sequence) ||
        Object.keys(message).sort().join(',') !== 'body,kind,protocol,run,sequence,session') {
      throw failure('ForeignExecutionMessage');
    }
    if (!ready) {
      if (message.kind !== 'ready' || message.sequence !== 0 || message.body !== null || stopped) {
        throw failure('InvalidExecutionHandshake');
      }
      ready = true; clearTimeout(startTimer); resolveReady(); return;
    }
    if (message.kind === 'usage') {
      if (!budget || exited || terminalUsage || !message.body ||
          Object.keys(message.body).sort().join(',') !== 'terminal,usage' ||
          typeof message.body.terminal !== 'boolean' || message.sequence !== sequence ||
          (message.body.terminal ? !stopped : !pending || sequence <= lastUsageSequence)) {
        throw failure('InvalidExecutionAccounting');
      }
      const usage = decodeProcessUsage(message.body.usage);
      budget.report(usage, message.body.terminal);
      terminalUsage = message.body.terminal;
      lastUsageSequence = sequence;
      return;
    }
    if (message.kind === 'host-request') {
      if (!service || stopped || !pending || message.sequence !== pending.sequence || hostWork ||
          !message.body || Object.keys(message.body).sort().join(',') !== 'call,payload' ||
          message.body.call !== hostCalls + 1 || hostCalls >= maxHostCalls) {
        throw failure('InvalidHostServiceRequest');
      }
      const call = ++hostCalls;
      const requestSequence = message.sequence;
      const controller = new AbortController();
      hostController = controller;
      // Defer invocation until hostWork is installed, including synchronous
      // throws. Only one bounded request can be in flight in either direction.
      hostWork = Promise.resolve().then(async () => {
        try {
          controller.signal.throwIfAborted();
          const value = await service.invoke(message.body!.payload, controller.signal,
            Object.freeze({session, run, sequence: requestSequence, call}));
          controller.signal.throwIfAborted();
          if (!exited) await send(envelope('host-reply', requestSequence, {call, value}));
        } catch (error) {
          if (!exited && !stopped) await send(envelope('host-failed', requestSequence,
            {call, code: typeof (error as {code?: unknown} | null | undefined)?.code === 'string' ? (error as {code: string}).code.slice(0, 256) : 'HostServiceFailed'})).catch(broken);
        } finally {
          hostController = undefined;
          hostWork = undefined;
        }
      });
      return;
    }
    if (!pending || hostWork || message.sequence !== pending.sequence ||
        !['reply', 'failed'].includes(message.kind)) throw failure('UnexpectedExecutionMessage');
    if (budget && message.kind === 'reply' && lastUsageSequence !== sequence) {
      throw failure('MissingExecutionAccounting');
    }
    const current = pending;
    pending = undefined; current.detach();
    if (message.kind === 'failed') {
      current.reject(failure('ExecutionFailed', message.body));
      stop();
    } else if (stopped) {
      current.reject(failure('ExecutionCancelled'));
    } else {
      current.resolve(message.body);
    }
  }) as FrameReaderInput[1], bodyEntry(beforeBodyAllocation), bodyEntry(bodyReceived), bodyEntry(bodySnapshot));
  stream.on('data', (chunk: Buffer) => {
    receivedBytes += BigInt(chunk.byteLength);
    try { reader.feed(chunk); } catch (error) { broken(error); }
  });
  stream.on('error', error => broken(failure('ExecutionChannelFailure', error)));
  stream.on('end', () => {
    try { reader.end(); } catch (error) { broken(error); }
    if (!stopped && !exited) broken(failure('ExecutionChannelClosed'));
  });
  const didExit = (code: number | null, terminationSignal: NodeJS.Signals | null) => {
    if (exited) return;
    exited = true; stopped = true;
    hostController?.abort();
    clearTimeout(startTimer); clearTimeout(stopTimer);
    signal?.removeEventListener('abort', abort);
    exitValue = Object.freeze({ code, signal: terminationSignal });
    const error = failure('ExecutionExited', exitValue);
    rejectReady(error); rejectPending(error); resolveExit(exitValue);
  };
  child.once('exit', didExit);
  child.once('error', error => {
    broken(failure('ExecutionSpawnFailure', error));
    // A failed spawn has no PID and no started native process to settle.
    if (child.pid == null) didExit(null, null);
  });
  const abort = () => broken(failure('ExecutionCancelled', signal?.reason));
  signal?.addEventListener('abort', abort, { once: true });
  startTimer = setTimeout(() => broken(failure('ExecutionStartupTimeout')), startupMs);
  if (signal?.aborted) abort();
  else writeFrame(hello, error => { if (error) broken(failure('ExecutionChannelFailure', error)); });
  await readyPromise;
  if (signal?.aborted) {
    abort();
    throw failure('ExecutionCancelled', signal.reason);
  }

  return Object.freeze({
    identity: () => Object.freeze({ session, run }),
    status: () => Object.freeze({ ready, stopped, exited, pending: !exited || servicePending(),
      requests: sequence, hostCalls, exit: exitValue,
      transport: Object.freeze({submittedBytes: submittedBytes.toString(), receivedBytes: receivedBytes.toString()}) }),
    cleanupHandle,
    async request(body: unknown, requestSignal?: AbortSignal) {
      requestSignal?.throwIfAborted();
      if (stopped || exited || pending) throw failure('ExecutionNotReady');
      if (sequence >= maxRequests) throw failure('ExecutionRequestLimit');
      const next = sequence + 1;
      // Invalid/oversized preparation is correctable and consumes no sequence.
      const frame = encodeProcessFrame(envelope('execute', next, body), frames);
      requestSignal?.throwIfAborted();
      const result = new Promise<ProcessFrameValue>((resolve, reject) => {
        const onAbort = () => {
          reject(failure('ExecutionCancelled', requestSignal!.reason));
          stop();
        };
        pending = {
          sequence: next, resolve, reject,
          detach: () => requestSignal?.removeEventListener('abort', onAbort),
        };
        requestSignal?.addEventListener('abort', onAbort, { once: true });
      });
      sequence = next;
      writeFrame(frame, error => { if (error) broken(failure('ExecutionChannelFailure', error)); });
      return result;
    },
    async close() {
      stop(); const result = await exit;
      if (hostWork) await hostWork;
      if (bodyAdmissionJoin) await bodyAdmissionJoin;
      return result;
    },
  });
}
