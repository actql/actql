import {request as httpRequest} from 'node:http';
import {request as httpsRequest} from 'node:https';

// One sender per signal. Capacity is held until physical close, including
// errors/timeout. There are no retries or response bodies retained beyond cap.
export function createBoundedOtlpSender(endpoint, limits, headers = {}) {
  let closed = false, active, records = 0, bytes = 0, window = performance.now();
  const counters = {sent: 0, failed: 0, limited: 0};
  return Object.freeze({
    async send(payload, serializer) {
      if (closed || active !== undefined) throw new Error('ObservationSenderUnavailable');
      if (performance.now() - window >= limits.windowMs) {
        window = performance.now(); records = 0; bytes = 0;
      }
      if (!(payload instanceof Uint8Array) || payload.byteLength > limits.payloadBytes ||
          records >= limits.windowRecords || payload.byteLength > limits.windowBytes - bytes) {
        counters.limited++; throw new Error('ObservationSenderLimited');
      }
      records++; bytes += payload.byteLength;
      let req, timer;
      const settled = new Promise((resolve, reject) => {
        let failure, completed = false;
        const fail = () => {
          failure ??= new Error('ObservationExportFailed');
          req.destroy();
        };
        try {
          const url = new URL(endpoint);
          req = (url.protocol === 'https:' ? httpsRequest : httpRequest)(url, {
            method: 'POST', agent: false, headers: {
              ...headers,
              'content-type': 'application/x-protobuf',
              'content-length': payload.byteLength,
            },
          }, response => {
            let received = 0;
            const chunks = [];
            response.on('data', data => {
              received += data.byteLength;
              if (received > limits.responseBytes) fail();
              else chunks.push(data);
            });
            response.on('error', fail);
            response.on('end', () => {
              completed = response.statusCode >= 200 && response.statusCode < 300;
              if (completed && serializer !== undefined) {
                try {
                  const answer = serializer.deserializeResponse(Buffer.concat(chunks));
                  const partial = answer?.partialSuccess;
                  if (partial && Object.entries(partial).some(([key, value]) =>
                    key !== 'errorMessage' && value > 0)) completed = false;
                } catch { completed = false; }
              }
              if (!completed) fail();
            });
          });
          req.on('error', () => { failure ??= new Error('ObservationExportFailed'); });
          req.on('close', () => {
            clearTimeout(timer);
            if (!completed || failure !== undefined) { counters.failed++; reject(failure ??
              new Error('ObservationExportFailed')); }
            else { counters.sent++; resolve(); }
          });
          timer = setTimeout(fail, limits.exportTimeoutMs);
          req.end(payload);
        } catch {
          if (req) fail();
          else { counters.failed++; reject(new Error('ObservationExportFailed')); }
        }
      });
      active = {req, settled};
      try { await settled; } finally { active = undefined; }
    },
    status: () => Object.freeze({...counters, active: active === undefined ? 0 : 1,
      windowRecords: records, windowBytes: bytes, closed}),
    async close() {
      closed = true;
      active?.req?.destroy();
      if (active) await active.settled.catch(() => {});
    },
  });
}
