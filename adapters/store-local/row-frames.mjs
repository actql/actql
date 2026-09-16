// Physical framing only. Typed values, normalization laws and row identity are
// interpreted by the shared MoonBit decoder/admission, never by this splitter.
export class RetainedRowFrameError extends Error {
  constructor(code) { super(code); this.code = code; }
}

export function createRetainedRowFrames(options, accept) {
  const limits = Object.freeze({ ...options });
  for (const key of ['maxBytes', 'maxRows', 'maxRowBytes', 'maxDepth', 'maxFrameBytes']) {
    if (!Number.isSafeInteger(limits[key]) || limits[key] < 0) throw new RetainedRowFrameError('InvalidRowFrameLimits');
  }
  if (!limits.maxRowBytes || limits.maxRowBytes > 16 * 1024 * 1024 ||
      !limits.maxFrameBytes || limits.maxFrameBytes > 16 * 1024 * 1024 ||
      !limits.maxDepth || limits.maxDepth > 64 || typeof accept !== 'function') {
    throw new RetainedRowFrameError('InvalidRowFrameLimits');
  }
  const row = new Uint8Array(limits.maxRowBytes);
  const stack = new Uint8Array(limits.maxDepth);
  const decoder = new TextDecoder('utf-8', { fatal: true });
  let state = 'start', bytes = 0, rows = 0, size = 0, depth = 0;
  let quoted = false, escaped = false, feeding = false, closed = false;
  const fail = code => { closed = true; throw new RetainedRowFrameError(code); };
  return Object.freeze({
    async feed(chunk, signal) {
      if (closed || feeding) fail('RowFramesClosed');
      if (!(chunk instanceof Uint8Array)) fail('InvalidRowFrame');
      if (chunk.length > limits.maxFrameBytes || chunk.length > limits.maxBytes - bytes) fail('RowFrameByteLimit');
      feeding = true;
      bytes += chunk.length;
      try {
        for (const byte of chunk) {
          signal?.throwIfAborted();
          if (state === 'start') {
            if (byte !== 91) fail('InvalidRowArray');
            state = 'first'; continue;
          }
          if (state === 'done') fail('TrailingRowContent');
          if (state === 'after') {
            if (byte === 93) { state = 'done'; continue; }
            if (byte !== 44) fail('InvalidRowSeparator');
            state = 'next'; continue;
          }
          if (state === 'first' && byte === 93) { state = 'done'; continue; }
          if (state === 'first' || state === 'next') {
            if (byte !== 123) fail('InvalidRowObject');
            if (rows === limits.maxRows) fail('RowCountLimit');
            state = 'row'; size = 0; depth = 0; quoted = false; escaped = false;
          }
          if (size === limits.maxRowBytes) fail('RowSizeLimit');
          row[size++] = byte;
          if (quoted) {
            if (escaped) escaped = false;
            else if (byte === 92) escaped = true;
            else if (byte === 34) quoted = false;
            continue;
          }
          if (byte === 34) { quoted = true; continue; }
          if (byte === 123 || byte === 91) {
            if (depth === limits.maxDepth) fail('RowDepthLimit');
            stack[depth++] = byte;
          } else if (byte === 125 || byte === 93) {
            if (!depth || stack[depth - 1] !== (byte === 125 ? 123 : 91)) fail('InvalidRowNesting');
            depth--;
            if (!depth) {
              const text = decoder.decode(row.subarray(0, size));
              await accept(text, rows);
              signal?.throwIfAborted();
              if (closed) fail('RowFramesClosed');
              rows++; state = 'after'; size = 0;
            }
          }
        }
      } catch (error) { closed = true; throw error; }
      finally { feeding = false; }
    },
    finish() {
      if (closed || feeding) fail('RowFramesClosed');
      closed = true;
      if (state !== 'done') fail('IncompleteRowArray');
      return Object.freeze({ bytes, rows });
    },
    cancel() { closed = true; },
  });
}
