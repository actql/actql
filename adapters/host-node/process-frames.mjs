// Private bounded local IPC framing, not ActQL wire/identity or execution proof.
import { Buffer } from 'node:buffer';

export const executionProtocol = 'actql-local-execution/0.1';

export class ProcessProtocolError extends Error {
  constructor(code) { super(code); this.code = code; }
}
const fail = code => { throw new ProcessProtocolError(code); };

export function validateFrameLimits(limits) {
  const copy = { ...limits };
  for (const key of ['maxBytes', 'maxNodes', 'maxDepth']) {
    if (!Number.isSafeInteger(copy[key]) || copy[key] < 1) fail('InvalidFrameLimits');
  }
  if (copy.maxBytes > 16 * 1024 * 1024 || copy.maxDepth > 64) fail('InvalidFrameLimits');
  return Object.freeze(copy);
}

function snapshot(value, limits) {
  let nodes = 0;
  let bytes = 0;
  const parents = new Set();
  const charge = count => {
    if (count > limits.maxBytes - bytes) fail('FrameByteLimit');
    bytes += count;
  };
  const textSize = text => {
    if (text.length > limits.maxBytes - bytes) fail('FrameByteLimit');
    return Buffer.byteLength(JSON.stringify(text));
  };
  const read = (item, depth) => {
    if (++nodes > limits.maxNodes || depth > limits.maxDepth) fail('FrameShapeLimit');
    if (item === null) { charge(4); return item; }
    if (typeof item === 'boolean') { charge(item ? 4 : 5); return item; }
    if (typeof item === 'string') { charge(textSize(item)); return item; }
    if (typeof item === 'number' && Number.isFinite(item)) {
      charge(JSON.stringify(item).length); return item;
    }
    if (typeof item !== 'object' || parents.has(item)) fail('InvalidFrameValue');
    const array = Array.isArray(item);
    const proto = Object.getPrototypeOf(item);
    if (!array && proto !== Object.prototype && proto !== null) fail('InvalidFrameValue');
    parents.add(item);
    charge(2);
    const result = array ? [] : Object.create(null);
    if (array) {
      if (item.length > limits.maxNodes - nodes) fail('FrameShapeLimit');
      for (let index = 0; index < item.length; index++) {
        if (index) charge(1);
        const property = Object.getOwnPropertyDescriptor(item, String(index));
        if (!property || !Object.hasOwn(property, 'value')) fail('InvalidFrameValue');
        result.push(read(property.value, depth + 1));
      }
    } else {
      let count = 0;
      for (const key in item) {
        if (!Object.hasOwn(item, key)) fail('InvalidFrameValue');
        if (count++) charge(1);
        charge(textSize(key) + 1);
        const property = Object.getOwnPropertyDescriptor(item, key);
        if (!property || !Object.hasOwn(property, 'value')) fail('InvalidFrameValue');
        result[key] = read(property.value, depth + 1);
      }
    }
    parents.delete(item);
    return result;
  };
  return read(value, 0);
}

export function encodeProcessFrame(value, inputLimits) {
  const limits = validateFrameLimits(inputLimits);
  const body = Buffer.from(JSON.stringify(snapshot(value, limits)));
  if (body.length > limits.maxBytes) fail('FrameByteLimit');
  const frame = Buffer.allocUnsafe(4 + body.length);
  frame.writeUInt32BE(body.length, 0);
  body.copy(frame, 4);
  return frame;
}

export function createProcessFrameReader(inputLimits, accept) {
  const limits = validateFrameLimits(inputLimits);
  const header = Buffer.alloc(4);
  let headerBytes = 0;
  let body;
  let bodyBytes = 0;
  let closed = false;
  let feeding = false;
  const feed = chunk => {
    if (closed || feeding) fail('FrameReaderClosed');
    if (!Buffer.isBuffer(chunk)) fail('InvalidFrameBytes');
    feeding = true;
    try {
      let offset = 0;
      while (offset < chunk.length) {
        if (!body) {
          const size = Math.min(4 - headerBytes, chunk.length - offset);
          chunk.copy(header, headerBytes, offset, offset + size);
          headerBytes += size; offset += size;
          if (headerBytes !== 4) continue;
          const length = header.readUInt32BE(0);
          if (length < 1 || length > limits.maxBytes) fail('FrameByteLimit');
          // Length is checked before allocating a payload, including a peer
          // which announces a huge message and never sends its body.
          body = Buffer.allocUnsafe(length);
        }
        const size = Math.min(body.length - bodyBytes, chunk.length - offset);
        chunk.copy(body, bodyBytes, offset, offset + size);
        bodyBytes += size; offset += size;
        if (bodyBytes !== body.length) continue;
        const text = new TextDecoder('utf-8', { fatal: true }).decode(body);
        const value = snapshot(JSON.parse(text), limits);
        body = undefined; bodyBytes = 0; headerBytes = 0;
        accept(value);
      }
    } catch (error) {
      closed = true; body = undefined;
      throw error;
    } finally { feeding = false; }
  };
  return Object.freeze({
    feed,
    end() {
      if (closed) fail('FrameReaderClosed');
      closed = true;
      if (headerBytes || body) { body = undefined; fail('TruncatedFrame'); }
    },
  });
}
