// Bounded control-response decoding shared by the existing Host operations.
const maxControlResponseBytes = 1024 * 1024;

// Payload bytes and JSON wire bytes are different budgets. A JSON string
// needs at most six wire bytes per UTF-8 byte (escaped ASCII controls).
// Resource metadata has at most 102 bounded names of 256 characters each;
// six bytes per UTF-16 code unit also bounds escaped surrogate pairs.
const resourceEnvelopeBytes = 102 * (256 * 6 + 3) + 1024;

export const reviewEnvelopeBytes = 1024;

export const jsonPayloadWireBytes = bytes => 6 * bytes + resourceEnvelopeBytes;

export async function boundedHostJson(response,
  maxWireBytes = maxControlResponseBytes) {
  const declared = response.headers.get('content-length');
  const reader = response.body?.getReader();
  if (!reader) throw new Error('InvalidHostControlResponse');
  let complete = false;
  try {
    if (declared !== null && Number(declared) > maxWireBytes) {
      throw new Error('HostControlResponseLimit');
    }
    const chunks = [];
    let size = 0;
    while (true) {
      const {done, value} = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > maxWireBytes) {
        throw new Error('HostControlResponseLimit');
      }
      chunks.push(value);
    }
    const bytes = new Uint8Array(size);
    let offset = 0;
    for (const chunk of chunks) {
      bytes.set(chunk, offset);
      offset += chunk.byteLength;
    }
    const parsed = JSON.parse(new TextDecoder('utf-8', {fatal: true})
      .decode(bytes));
    complete = true;
    return parsed;
  } finally {
    if (!complete) {
      try { await reader.cancel(); } catch {}
    }
    reader.releaseLock();
  }
}

export const controlValue = (response, maxWireBytes) => response instanceof Response
  ? boundedHostJson(response, maxWireBytes) : response;
