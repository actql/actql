import {createHash} from 'node:crypto';
import {isAbsolute} from 'node:path';
import {setImmediate as yieldTurn} from 'node:timers/promises';

const fail = (code, cause) => {throw Object.assign(new Error(code, {cause}), {code});};
const positive = value => Number.isSafeInteger(value) && value > 0;
const methods = ['openFileRoot', 'openFileDirectory', 'openRootFile', 'fileRootCurrent',
  'fileRootStat', 'fileRootNext', 'fileRootRead', 'fileRootClose', 'fileRootEntryKind'];
const metadataKeys = ['dev', 'ino', 'size', 'links', 'modifiedSeconds', 'modifiedNanos',
  'changedSeconds', 'changedNanos'];
const equalMetadata = (left, right) => metadataKeys.every(key => left[key] === right[key]);
function readMetadata(value) {
  if (value === null || typeof value !== 'object' ||
      metadataKeys.some(key => typeof value[key] !== 'bigint') || value.size < 0n ||
      value.modifiedNanos < 0n || value.modifiedNanos >= 1000000000n ||
      value.changedNanos < 0n || value.changedNanos >= 1000000000n) fail('InvalidLocalFileMetadata');
  return Object.freeze(Object.fromEntries(metadataKeys.map(key => [key, value[key]])));
}
const version = metadata => 'sha256:' + createHash('sha256').update(JSON.stringify({
  size: String(metadata.size), modifiedSeconds: String(metadata.modifiedSeconds),
  modifiedNanos: String(metadata.modifiedNanos),
})).digest('hex');
const currentResult = value => {
  if (value === undefined) return;
  if (value instanceof Promise) void value.catch(() => {});
  fail('InvalidLocalFileCurrentFence');
};

// Same existing filesystem custody, not a permission or resource factory.
// The Host admits this actual native namespace and its FD lifetime separately;
// each Source child supplies its same current scope before covered I/O.
export function openLocalFileRoot({native, path, assertCurrent}) {
  if (!isAbsolute(path ?? '') || !path.isWellFormed() ||
      Buffer.byteLength(path) > 4096 || typeof assertCurrent !== 'function') fail('InvalidLocalFileRoot');
  const callbacks = Object.freeze(Object.fromEntries(methods.map(name => {
    const method = Object.getOwnPropertyDescriptor(native ?? {}, name)?.value;
    if (typeof method !== 'function') fail('LocalFilesystemUnavailable');
    return [name, method];
  })));
  const call = (name, ...args) => Reflect.apply(callbacks[name], native, args);
  const readers = new Set();
  let root, rootClose, closing = false;
  const current = () => {
    if (closing) fail('LocalFileRootClosing');
    currentResult(assertCurrent());
    if (root !== undefined) currentResult(call('fileRootCurrent', root));
  };
  const closeNative = slot => {
    if (slot.outcome === 'closed' || slot.outcome === 'unknown') return;
    const result = call('fileRootClose', slot.original);
    const outcome = Object.getOwnPropertyDescriptor(result ?? {}, 'outcome')?.value;
    if (!['pending', 'closed', 'unknown'].includes(outcome)) fail('LocalFileCloseUnconfirmed');
    slot.outcome = outcome;
    if (outcome === 'closed') slot.original = undefined;
  };
  function closeRoot() {
    closing = true;
    const errors = [];
    for (const reader of readers) {
      try {reader.close();} catch (cause) {errors.push(cause);}
    }
    if (readers.size === 0 && root !== undefined) {
      rootClose ??= {original: root, outcome: undefined};
      try {closeNative(rootClose);} catch (cause) {errors.push(cause);}
      if (rootClose.outcome === 'closed') root = undefined;
    }
    return Object.freeze({pending: readers.size !== 0 || root !== undefined,
      errors: Object.freeze(errors)});
  }
  let originalMetadata;
  try {current();root = call('openFileRoot', path);current();originalMetadata = readMetadata(call('fileRootStat', root));}
  catch (cause) {
    const observed = closeRoot();
    if (observed.pending) {
      const cleanup = Object.freeze({status: () => Object.freeze({pending: root !== undefined}), retry: closeRoot});
      throw Object.assign(new Error('LocalFileRootCleanupPending', {cause}),
        {code: 'LocalFileRootCleanupPending', cleanupPending: true, cleanupHandle: cleanup});
    }
    throw cause;
  }
  return Object.freeze({
    metadata: originalMetadata,
    assertCurrent: current,
    close: closeRoot,
    openReader({limits, assertCurrent: checkRead, signal}) {
      current();
      const names = ['maxEntries','maxDepth','maxPathBytes','maxFiles','maxFileBytes','maxReadBytes'];
      const fields = limits !== null && typeof limits === 'object' ? Object.getOwnPropertyDescriptors(limits) : {};
      if (typeof checkRead !== 'function' || Reflect.ownKeys(fields).length !== names.length ||
          names.some(name => !Object.hasOwn(fields[name] ?? {}, 'value'))) fail('InvalidLocalFileReadLimits');
      const bounds = Object.freeze(Object.fromEntries(names.map(name => [name, fields[name].value])));
      if (!positive(bounds.maxEntries) || bounds.maxEntries > 100000 ||
          !positive(bounds.maxDepth) || bounds.maxDepth > 128 ||
          !positive(bounds.maxPathBytes) || bounds.maxPathBytes > 4096 ||
          !positive(bounds.maxFiles) || bounds.maxFiles > bounds.maxEntries ||
          !Number.isSafeInteger(bounds.maxFileBytes) || bounds.maxFileBytes < 0 ||
          !Number.isSafeInteger(bounds.maxReadBytes) || bounds.maxReadBytes < bounds.maxFileBytes) {
        fail('InvalidLocalFileReadLimits');
      }
      const slots = [];
      let stopping = false, released = false, flight, failure;
      let examined = 0, files = 0, readBytes = 0;
      const check = () => {
        current();signal?.throwIfAborted();
        if (stopping || released) fail('LocalFileReadClosing');
        currentResult(checkRead());
      };
      function acquire(name, parent, component, maximum) {
        check();
        const original = call(name, parent, component, ...(maximum === undefined ? [] : [maximum]));
        const slot = {original, outcome: undefined};
        // Retain before current/stat/decoder or any later callback can fail.
        slots.push(slot);check();currentResult(call('fileRootCurrent', original));
        return slot;
      }
      function close() {
        stopping = true;
        if (released) return Object.freeze({pending: false});
        if (flight !== undefined) return Object.freeze({pending: true});
        const errors = [];
        for (const slot of slots.slice().reverse()) {
          try {closeNative(slot);} catch (cause) {errors.push(cause);}
        }
        if (slots.every(slot => slot.outcome === 'closed')) {
          released = true;slots.length = 0;readers.delete(reader);
        }
        return Object.freeze({pending: !released, errors: Object.freeze(errors)});
      }
      function finishSlot(slot) {
        closeNative(slot);
        if (slot.outcome !== 'closed') fail('LocalFileCleanupPending');
        slots.splice(slots.indexOf(slot), 1);
      }
      async function content(slot, metadata, collect) {
        if (metadata.size > BigInt(bounds.maxFileBytes) ||
            metadata.size > BigInt(bounds.maxReadBytes - readBytes)) fail('LocalFileBytesLimit');
        readBytes += Number(metadata.size);
        // One bounded original output buffer avoids retaining one Buffer and
        // array slot per possible short read, then duplicating them at concat.
        // The caller retains its actual raw-buffer holding until capture ends.
        const bytes = collect ? Buffer.allocUnsafeSlow(Number(metadata.size)) : undefined;
        const hash = createHash('sha256');
        let offset = 0;
        while (offset < Number(metadata.size)) {
          check();
          const chunk = call('fileRootRead', slot.original, offset,
            Math.min(65536, Number(metadata.size) - offset));
          if (!Buffer.isBuffer(chunk) || chunk.length === 0 ||
              chunk.length > Math.min(65536, Number(metadata.size) - offset)) fail('LocalFileChanged');
          hash.update(chunk);if (collect) chunk.copy(bytes, offset);
          offset += chunk.length;
          await yieldTurn(undefined, {signal});
        }
        check();
        if (!equalMetadata(metadata, readMetadata(call('fileRootStat', slot.original)))) fail('LocalFileChanged');
        return {version: 'sha256:' + hash.digest('hex'),
          ...(collect ? {bytes} : {})};
      }
      function execute(operation) {
        check();if (flight !== undefined || failure !== undefined) fail('LocalFileReadAlreadyAttempted');
        const work = Promise.resolve().then(operation);
        flight = work;
        return work.catch(cause => {failure = cause;throw cause;}).finally(() => {flight = undefined;});
      }
      const reader = Object.freeze({
        close,
        status: () => Object.freeze({pending: !released}),
        list({contentVersion = false, onFile}) {
          if (typeof onFile !== 'function' || typeof contentVersion !== 'boolean') fail('InvalidLocalFileListing');
          return execute(async () => {
            const decoder = new TextDecoder('utf-8', {fatal: true, ignoreBOM: true});
            async function visit(parent, component, prefix, depth) {
              if (depth > bounds.maxDepth) fail('LocalDirectoryDepthLimit');
              const directory = acquire('openFileDirectory', parent, component, bounds.maxEntries);
              for (;;) {
                check();const bytes = call('fileRootNext', directory.original);
                if (bytes === null) break;
                if (!Buffer.isBuffer(bytes) || bytes.length === 0 || ++examined > bounds.maxEntries) fail('LocalDirectoryEntryLimit');
                const name = decoder.decode(bytes), relative = prefix + name;
                if (!name || name === '.' || name === '..' || /[\/\0]/u.test(name) ||
                    Buffer.byteLength(relative) > bounds.maxPathBytes) fail('InvalidLocalFilePath');
                const kind = call('fileRootEntryKind', directory.original, name);
                if (kind === 'directory') await visit(directory.original, name, relative + '/', depth + 1);
                else if (kind === 'file') {
                  if (++files > bounds.maxFiles) fail('LocalFileCountLimit');
                  const slot = acquire('openRootFile', directory.original, name);
                  const metadata = readMetadata(call('fileRootStat', slot.original));
                  const observedVersion = contentVersion ? (await content(slot, metadata, false)).version : version(metadata);
                  check();
                  await onFile(Object.freeze({path: relative, metadata, version: observedVersion}));
                  check();finishSlot(slot);
                } else if (kind !== 'symlink' && kind !== 'other') fail('InvalidLocalFileEntryKind');
                await yieldTurn(undefined, {signal});
              }
              finishSlot(directory);
            }
            await visit(root, '', '', 0);
          });
        },
        read(path, {expectedVersion, contentVersion = false} = {}) {
          if (typeof path !== 'string' || !path.isWellFormed() || !path ||
              Buffer.byteLength(path) > bounds.maxPathBytes || typeof contentVersion !== 'boolean') fail('InvalidLocalFilePath');
          const components = path.split('/');
          if (components.some(name => !name || name === '.' || name === '..' || name.includes('\0')) ||
              components.length - 1 > bounds.maxDepth) fail('InvalidLocalFilePath');
          return execute(async () => {
            let parent = root;
            for (const component of components.slice(0,-1)) parent = acquire('openFileDirectory', parent, component, bounds.maxEntries).original;
            const file = acquire('openRootFile', parent, components.at(-1));
            const metadata = readMetadata(call('fileRootStat', file.original));
            const value = await content(file, metadata, true);
            const observedVersion = contentVersion ? value.version : version(metadata);
            if (expectedVersion !== undefined && expectedVersion !== observedVersion) fail('LocalFileVersionConflict');
            return Object.freeze({path, metadata, version: observedVersion, bytes: value.bytes});
          });
        },
      });
      readers.add(reader);return reader;
    },
  });
}
