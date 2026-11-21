// Execution-side counterpart. The installed handler is trusted module wiring;
// no request chooses an executable, module URL or arbitrary JavaScript callback.
import { Socket } from 'node:net';
import { createProcessFrameReader, encodeProcessFrame, executionProtocol } from './process-frames.mjs';
import {decodeProcessLimits, encodeProcessUsage} from './process-accounting.mjs';
import type {FrameLimits, ProcessFrameValue, UncheckedProcessEnvelope} from './process-frames.mjs';
import type {decodeProcessUsage} from './process-accounting.mjs';

type ResourceLimits = ReturnType<typeof decodeProcessLimits>;
type ExecutionIdentity = Readonly<{protocol: typeof executionProtocol; session: string; run: string}>;
type ExecutionContext = Readonly<{session: string; run: string; sequence: number;
  resourceLimits: ResourceLimits | undefined; callHost: (request: unknown) => Promise<ProcessFrameValue | undefined>}>;
type ExecutionHandler = (request: ProcessFrameValue, signal: AbortSignal, context: ExecutionContext) => unknown;
type WorkerOptions = Readonly<{finish?: () => unknown;
  accounting?: () => ReturnType<typeof decodeProcessUsage>}>;
type PendingCall = Readonly<{call: number; resolve: (value: ProcessFrameValue | undefined) => void;
  reject: (reason: unknown) => void}>;

export function serveManagedExecution(handler: ExecutionHandler, frames: FrameLimits,
  { finish = async () => {}, accounting }: WorkerOptions = {}) {
  if (accounting !== undefined && typeof accounting !== 'function') throw new TypeError('InvalidProcessAccounting');
  const stream = new Socket({ fd: 3, readable: true, writable: true });
  let identity: ExecutionIdentity | undefined;
  let sequence = 0;
  let active: AbortController | undefined;
  let stopped = false;
  let finishing: Promise<void> | undefined;
  let hostCalls = 0, hostPending: PendingCall | undefined;
  let resourceLimits: ResourceLimits | undefined;
  const send = (kind: string, number: number, body: unknown) => new Promise<void>((resolve, reject) => {
    let frame;
    try { frame = encodeProcessFrame({ ...identity, kind, sequence: number, body }, frames); }
    catch (error) { reject(error); return; }
    stream.write(frame, error => error ? reject(error) : resolve());
  });
  const finishOnce = () => finishing ??= (async () => {
    try {
      await finish();
      if (resourceLimits) await send('usage', sequence, {terminal: true, usage: encodeProcessUsage(accounting!())});
    }
    finally { stream.end(); }
  })();
  const stop = () => {
    stopped = true;
    active?.abort();
    if (hostPending) {
      hostPending.reject(Error('HostServiceCancelled'));
      hostPending = undefined;
    }
    if (!active) finishOnce().catch(() => { process.exitCode = 1; });
  };
  const reader = createProcessFrameReader(frames, ((message: UncheckedProcessEnvelope) => {
    if (!message || message.protocol !== executionProtocol ||
        typeof message.session !== 'string' || typeof message.run !== 'string' ||
        Object.keys(message).sort().join(',') !== 'body,kind,protocol,run,sequence,session') throw Error('InvalidEnvelope');
    if (!identity) {
      if (message.kind !== 'hello' || message.sequence !== 0) throw Error('MissingHandshake');
      if (message.body !== null) {
        if (!accounting || !message.body || Object.keys(message.body).join(',') !== 'resourceLimits') throw Error('MissingAccountingBinding');
        resourceLimits = decodeProcessLimits(message.body.resourceLimits);
      }
      identity = { protocol: executionProtocol, session: message.session, run: message.run };
      send('ready', 0, null).catch(stop);
      return;
    }
    if (message.session !== identity.session || message.run !== identity.run) throw Error('ForeignSession');
    if (message.kind === 'stop' && message.sequence === sequence && message.body === null) { stop(); return; }
    if (message.kind === 'host-reply' || message.kind === 'host-failed') {
      if (stopped || !active || !hostPending || message.sequence !== sequence ||
          message.body?.call !== hostPending.call ||
          Object.keys(message.body).sort().join(',') !==
            (message.kind === 'host-reply' ? 'call,value' : 'call,code')) throw Error('ForeignHostServiceReply');
      const waiting = hostPending;
      hostPending = undefined;
      if (message.kind === 'host-failed') waiting.reject(Error('HostServiceFailed'));
      else waiting.resolve(message.body!.value);
      return;
    }
    if (stopped || active || message.kind !== 'execute' ||
        message.sequence !== sequence + 1 || !Number.isSafeInteger(message.sequence)) throw Error('UnexpectedRequest');
    sequence = message.sequence;
    const controller = new AbortController();
    active = controller;
    (async () => {
      try {
        controller.signal.throwIfAborted();
        const result = await handler(message.body, controller.signal,
          Object.freeze({ session: identity!.session, run: identity!.run, sequence: message.sequence,
            resourceLimits,
            callHost: (payload: unknown) => {
              controller.signal.throwIfAborted();
              if (active !== controller || stopped || hostPending) throw Error('HostServiceNotReady');
              const call = hostCalls + 1;
              // Validate before consuming a call number or changing state.
              encodeProcessFrame({...identity, kind: 'host-request', sequence,
                body: {call, payload}}, frames);
              hostCalls = call;
              const response = new Promise<ProcessFrameValue | undefined>((resolve, reject) => { hostPending = {call, resolve, reject}; });
              response.catch(() => {});
              send('host-request', sequence, {call, payload}).catch(stop);
              return response;
            },
          }));
        if (hostPending) throw Error('UnawaitedHostService');
        controller.signal.throwIfAborted();
        if (resourceLimits) await send('usage', message.sequence, {terminal: false, usage: encodeProcessUsage(accounting!())});
        controller.signal.throwIfAborted();
        await send('reply', message.sequence, result);
      } catch (error) {
        stopped = true;
        // Failure presence is independent of an undefined/null rejection reason.
        await send('failed', message.sequence, {
          code: typeof (error as {code?: unknown} | null | undefined)?.code === 'string' ? (error as {code: string}).code.slice(0, 256) : 'ExecutionFailed',
        }).catch(() => {});
      } finally {
        active = undefined;
        if (stopped) await finishOnce();
      }
    })().catch(() => { process.exitCode = 1; stream.destroy(); });
  }) as Parameters<typeof createProcessFrameReader>[1]);
  stream.on('data', (chunk: Buffer) => { try { reader.feed(chunk); } catch { stop(); } });
  stream.on('error', stop);
  stream.on('end', stop);
  return Object.freeze({ stop });
}
