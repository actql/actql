// Descriptor custody for one already authorized Local file write. The caller
// retains the original Effect claim, Content read/availability and resource
// child; this module creates none of those capabilities or a success receipt.
import {isAbsolute} from 'node:path';

const fail = code => {throw Object.assign(new Error(code), {code});};
const text = (value, max) => typeof value === 'string' && value.length > 0 &&
  value.isWellFormed() && !value.includes('\0') && Buffer.byteLength(value) <= max;
const bufferBacking = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(Uint8Array.prototype), 'buffer').get;
const ordinaryBacking = Object.getOwnPropertyDescriptor(ArrayBuffer.prototype, 'byteLength').get;
export const localFileWriteMaxComponents = 128;
const operations = ['openFileRoot','openFileDirectory','openRootFileWriter',
  'fileRootCurrent','fileRootWrite','fileRootPublish','fileRootClose'];

export function prepareLocalFileWrite({native, rootPath, path, temporaryName,
  maxBytes, overwrite = false, assertCurrent, signal, writeQuantumBytes = 65536, observeWriteBytes}) {
  if (!text(rootPath,4096) || !isAbsolute(rootPath) || !text(path,4096) || isAbsolute(path) ||
      !text(temporaryName,1024) || temporaryName.includes('/') ||
      ['.','..'].includes(temporaryName) || typeof overwrite !== 'boolean' ||
      !Number.isSafeInteger(maxBytes) || maxBytes < 0 || maxBytes > 2147483647 ||
      typeof assertCurrent !== 'function' || !Number.isSafeInteger(writeQuantumBytes) ||
      writeQuantumBytes < 1 || writeQuantumBytes > 65536 ||
      observeWriteBytes !== undefined && typeof observeWriteBytes !== 'function') fail('InvalidLocalFileWrite');
  const components = path.split('/');
  if (components.length > localFileWriteMaxComponents || components.some(name =>
    !text(name,1024) || name === '.' || name === '..') ||
    components.at(-1) === temporaryName) fail('InvalidLocalFileWrite');
  const methods = Object.freeze(Object.fromEntries(operations.map(name => {
    const original = Object.getOwnPropertyDescriptor(native ?? {},name)?.value;
    if (typeof original !== 'function') fail('LocalFileWriterUnavailable');
    return [name,original];
  })));
  const call = (name,...args) => Reflect.apply(methods[name],native,args);
  const slots = [];
  let attempted = false, stopping = false, released = false, failure;
  let writer, written = 0, publishAttempted = false;
  const current = () => {
    if (stopping || released) fail('LocalFileWriteClosing');
    if (failure !== undefined) throw failure;
    signal?.throwIfAborted();
    const result = assertCurrent();
    if (result !== undefined) {
      if (result instanceof Promise) void result.catch(()=>{});
      fail('InvalidLocalFileCurrentFence');
    }
    // An original authority callback can start teardown synchronously.
    if (stopping || released) fail('LocalFileWriteClosing');
    signal?.throwIfAborted();
  };
  const perform = operation => {
    try {current();return operation();}
    catch (cause) {failure ??= cause;throw cause;}
  };
  const acquire = (name,...args) => {
    current();
    const original = call(name,...args);
    const slot = {original,outcome:undefined};
    slots.push(slot); // Same cleanup owner before post-factory current/stat.
    current();call('fileRootCurrent',original);
    return original;
  };
  const close = () => {
    stopping = true;
    const errors = [];
    for (const slot of slots.slice().reverse()) {
      if (slot.outcome === 'closed' || slot.outcome === 'unknown') continue;
      try {
        const observation = call('fileRootClose',slot.original);
        const outcome = Object.getOwnPropertyDescriptor(observation ?? {},'outcome')?.value;
        if (!['closed','pending','unknown'].includes(outcome)) fail('LocalFileCloseUnconfirmed');
        slot.outcome = outcome;
        if (outcome === 'closed') slot.original = undefined;
      } catch (cause) {errors.push(cause);}
    }
    if (slots.every(slot=>slot.outcome==='closed')) {
      released = true;writer = undefined;slots.length = 0;
    }
    return Object.freeze({pending:!released,errors:Object.freeze(errors)});
  };
  return Object.freeze({
    start() {
      if (attempted) fail('LocalFileWriteAlreadyAttempted');
      attempted = true;
      return perform(()=>{
        let parent = acquire('openFileRoot',rootPath);
        for (const component of components.slice(0,-1))
          parent = acquire('openFileDirectory',parent,component,1);
        writer = acquire('openRootFileWriter',parent,temporaryName,components.at(-1),Math.max(1,maxBytes));
      });
    },
    write(bytes) {
      return perform(()=>{
        if (writer === undefined || publishAttempted || !Buffer.isBuffer(bytes))
          fail('LocalFileWriteUnavailable');
        // No concurrent SharedArrayBuffer writer may mutate bytes during the
        // same original Store callback. No conversion or lossy text path.
        try {ordinaryBacking.call(bufferBacking.call(bytes));}
        catch {fail('InvalidLocalFileWriteBytes');}
        if (bytes.length > maxBytes-written) fail('LocalFileBytesLimit');
        for (let offset=0;offset<bytes.length;offset+=writeQuantumBytes) {
          current();
          const end = Math.min(bytes.length, offset + writeQuantumBytes);
          const observed = observeWriteBytes?.(BigInt(end - offset));
          if (observed !== undefined) fail('InvalidLocalFileWriteObservation');
          current();call('fileRootWrite',writer,Buffer.prototype.subarray.call(bytes,offset,end));
        }
        written += bytes.length;
      });
    },
    publish() {
      return perform(()=>{
        if (writer === undefined || publishAttempted) fail('LocalFileWriteUnavailable');
        publishAttempted = true; // A thrown post-rename durability is Unknown, not resend.
        call('fileRootPublish',writer,overwrite);
        current();
        return Object.freeze({path,bytes:written}); // Physical facts only, not an Effect ACK.
      });
    },
    close, release:close, retry:close,
    status:()=>Object.freeze({pending:!released}),
  });
}
