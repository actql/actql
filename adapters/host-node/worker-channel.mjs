// Execution-side counterpart. The installed handler is trusted module wiring;
// no request chooses an executable, module URL or arbitrary JavaScript callback.
import { Socket } from 'node:net';
import { createProcessFrameReader, encodeProcessFrame, executionProtocol } from './process-frames.mjs';
import {decodeProcessLimits, encodeProcessUsage} from './process-accounting.mjs';

export function serveManagedExecution(handler, frames, { finish = async () => {}, accounting } = {}) {
  if (accounting !== undefined && typeof accounting !== 'function') throw new TypeError('InvalidProcessAccounting');
  const stream = new Socket({ fd: 3, readable: true, writable: true });
  let identity;
  let sequence = 0;
  let active;
  let stopped = false;
  let finishing;
  let hostCalls = 0, hostPending;
  let resourceLimits;
  const send = (kind, number, body) => new Promise((resolve, reject) => {
    let frame;
    try { frame = encodeProcessFrame({ ...identity, kind, sequence: number, body }, frames); }
    catch (error) { reject(error); return; }
    stream.write(frame, error => error ? reject(error) : resolve());
  });
  const finishOnce = () => finishing ??= (async () => {
    try {
      await finish();
      if (resourceLimits) await send('usage', sequence, {terminal: true, usage: encodeProcessUsage(accounting())});
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
  const reader = createProcessFrameReader(frames, message => {
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
      else waiting.resolve(message.body.value);
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
          Object.freeze({ session: identity.session, run: identity.run, sequence: message.sequence,
            resourceLimits,
            callHost: payload => {
              controller.signal.throwIfAborted();
              if (active !== controller || stopped || hostPending) throw Error('HostServiceNotReady');
              const call = hostCalls + 1;
              // Validate before consuming a call number or changing state.
              encodeProcessFrame({...identity, kind: 'host-request', sequence,
                body: {call, payload}}, frames);
              hostCalls = call;
              const response = new Promise((resolve, reject) => { hostPending = {call, resolve, reject}; });
              response.catch(() => {});
              send('host-request', sequence, {call, payload}).catch(stop);
              return response;
            },
          }));
        if (hostPending) throw Error('UnawaitedHostService');
        controller.signal.throwIfAborted();
        if (resourceLimits) await send('usage', message.sequence, {terminal: false, usage: encodeProcessUsage(accounting())});
        controller.signal.throwIfAborted();
        await send('reply', message.sequence, result);
      } catch (error) {
        stopped = true;
        // Failure presence is independent of an undefined/null rejection reason.
        await send('failed', message.sequence, {
          code: typeof error?.code === 'string' ? error.code.slice(0, 256) : 'ExecutionFailed',
        }).catch(() => {});
      } finally {
        active = undefined;
        if (stopped) await finishOnce();
      }
    })().catch(() => { process.exitCode = 1; stream.destroy(); });
  });
  stream.on('data', chunk => { try { reader.feed(chunk); } catch { stop(); } });
  stream.on('error', stop);
  stream.on('end', stop);
  return Object.freeze({ stop });
}
