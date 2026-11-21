// Private bounded local IPC framing, not ActQL wire/identity or execution proof.
import { Buffer } from 'node:buffer';
import type {SynchronousAction} from './installed-host-cleanup.mjs';

export type FrameLimits = Readonly<{maxBytes: number; maxNodes: number; maxDepth: number}>;
type FrameObject = {[key: string]: ProcessFrameValue};
export type ProcessFrameValue = null | boolean | number | string | FrameObject | ProcessFrameValue[];
type BodyGeometry = Readonly<{nodes: number; fields: number; objects: number; arrays: number; utf16Units: number}>;
type SynchronousObserver<T> = (value: T) => ReturnType<SynchronousAction>;

export const executionProtocol = 'actql-local-execution/0.1';

export class ProcessProtocolError extends Error {
  declare code: string;
  constructor(code: string) { super(code); this.code = code; }
}
const fail: (code: string) => never = code => { throw new ProcessProtocolError(code); };

export function validateFrameLimits(limits: unknown) {
  const copy = { ...limits as FrameLimits };
  for (const key of ['maxBytes', 'maxNodes', 'maxDepth'] as const) {
    if (!Number.isSafeInteger(copy[key]) || copy[key] < 1) fail('InvalidFrameLimits');
  }
  if (copy.maxBytes > 16 * 1024 * 1024 || copy.maxDepth > 64) fail('InvalidFrameLimits');
  return Object.freeze(copy);
}

function snapshot(value: unknown, limits: FrameLimits, plainObjects = false, observed?: SynchronousObserver<BodyGeometry>) {
  let nodes = 0;
  let bytes = 0, fields = 0, objects = 0, arrays = 0, utf16Units = 0;
  const parents = new Set<object>();
  const charge = (count: number) => {
    if (count > limits.maxBytes - bytes) fail('FrameByteLimit');
    bytes += count;
  };
  const textSize = (text: string) => {
    utf16Units += text.length;
    if (text.length > limits.maxBytes - bytes) fail('FrameByteLimit');
    return Buffer.byteLength(JSON.stringify(text));
  };
  const read = (item: unknown, depth: number): ProcessFrameValue => {
    if (++nodes > limits.maxNodes || depth > limits.maxDepth) fail('FrameShapeLimit');
    if (item === null) { charge(4); return item; }
    if (typeof item === 'boolean') { charge(item ? 4 : 5); return item; }
    if (typeof item === 'string') { charge(textSize(item)); return item; }
    if (typeof item === 'number' && Number.isFinite(item)) {
      charge(JSON.stringify(item).length); return plainObjects && item === 0 ? 0 : item;
    }
    if (typeof item !== 'object' || parents.has(item)) fail('InvalidFrameValue');
    const array = Array.isArray(item);
    if (array) arrays++; else objects++;
    const proto = Object.getPrototypeOf(item);
    if (!array && proto !== Object.prototype && proto !== null) fail('InvalidFrameValue');
    parents.add(item);
    charge(2);
    const result: ProcessFrameValue[] | FrameObject = array ? [] : plainObjects ? {} : Object.create(null) as FrameObject;
    if (array) {
      if (item.length > limits.maxNodes - nodes) fail('FrameShapeLimit');
      for (let index = 0; index < item.length; index++) {
        if (index) charge(1);
        const property = Object.getOwnPropertyDescriptor(item, String(index));
        if (!property || !Object.hasOwn(property, 'value')) fail('InvalidFrameValue');
        (result as ProcessFrameValue[]).push(read(property.value, depth + 1));
      }
    } else {
      let count = 0;
      for (const key in item) {
        if (!Object.hasOwn(item, key)) fail('InvalidFrameValue');
        fields++;
        if (count++) charge(1);
        charge(textSize(key) + 1);
        const property = Object.getOwnPropertyDescriptor(item, key);
        if (!property || !Object.hasOwn(property, 'value')) fail('InvalidFrameValue');
        const child = read(property.value, depth + 1);
        if (plainObjects) Object.defineProperty(result, key,
          {value: child, enumerable: true, writable: true, configurable: true});
        else (result as FrameObject)[key] = child;
      }
    }
    parents.delete(item);
    return result;
  };
  const result = read(value, 0);
  if (observed !== undefined) observed({nodes, fields, objects, arrays, utf16Units});
  return result;
}

// Pure configuration validation can retain the same bounded JSON snapshot
// without manufacturing a transport frame that will never be sent.
export function snapshotProcessValue(value: unknown, inputLimits: unknown) {
  return snapshot(value, validateFrameLimits(inputLimits), true);
}

export function encodeProcessFrame(value: unknown, inputLimits: unknown) {
  const limits = validateFrameLimits(inputLimits);
  const body = Buffer.from(JSON.stringify(snapshot(value, limits)));
  if (body.length > limits.maxBytes) fail('FrameByteLimit');
  const frame = Buffer.allocUnsafe(4 + body.length);
  frame.writeUInt32BE(body.length, 0);
  body.copy(frame, 4);
  return frame;
}

export function createProcessFrameReader(inputLimits: unknown, accept: SynchronousObserver<ProcessFrameValue>,
  beforeBodyAllocation?: SynchronousObserver<number>, bodyReceived?: SynchronousObserver<Buffer>,
  bodySnapshot?: SynchronousObserver<BodyGeometry>) {
  const limits = validateFrameLimits(inputLimits);
  if (beforeBodyAllocation !== undefined && typeof beforeBodyAllocation !== 'function' ||
      bodyReceived !== undefined && typeof bodyReceived !== 'function' ||
      bodySnapshot !== undefined && typeof bodySnapshot !== 'function') {
    fail('InvalidFrameCapacityHandoff');
  }
  const header = Buffer.alloc(4);
  let headerBytes = 0;
  let body: Buffer | undefined;
  let bodyBytes = 0;
  let closed = false;
  let feeding = false;
  const feed = (chunk: unknown) => {
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
          // An installed consumer can enter its SAME original backing here,
          // before the raw body, UTF8 String or JSON tree exists. This trusted
          // private entry is synchronous; its return is not an admission proof.
          if (beforeBodyAllocation !== undefined) {
            beforeBodyAllocation(length);
            // Its original Resource/current callback may close this reader.
            if (closed) fail('FrameReaderClosed');
          }
          body = Buffer.allocUnsafe(length);
        }
        const size = Math.min(body.length - bodyBytes, chunk.length - offset);
        chunk.copy(body, bodyBytes, offset, offset + size);
        bodyBytes += size; offset += size;
        if (bodyBytes !== body.length) continue;
        // Observe ONLY the fully received original Buffer, before even a
        // refused UTF8/JSON decode. Announced length never supplies this fact.
        if (bodyReceived !== undefined) {
          bodyReceived(body);
          if (closed) fail('FrameReaderClosed');
        }
        const text = new TextDecoder('utf-8', { fatal: true }).decode(body);
        const value = snapshot(JSON.parse(text), limits, false, bodySnapshot);
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
