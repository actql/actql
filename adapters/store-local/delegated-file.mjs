// Execution-side physical-byte writer. Only installed Host wiring supplies the
// descriptor; it is never a Program path or an ActQL completion certificate.
import { open } from 'node:fs/promises';
import { constants } from 'node:fs';
import { createHash } from 'node:crypto';
import { RetainedFileError } from './files.mjs';

const fail = code => { throw new RetainedFileError(code); };
const quantity = n => Number.isSafeInteger(n) && n >= 0;

export async function openDelegatedFile(supplied, signal) {
  const lease = Object.freeze({ ...supplied });
  if (lease.version !== 'actql-local-file/0.1' ||
      typeof lease.session !== 'string' || !lease.session.length || lease.session.length > 256 ||
      typeof lease.token !== 'string' || !/^[a-f0-9-]{36}$/.test(lease.token) ||
      typeof lease.path !== 'string' || !lease.path.length ||
      !quantity(lease.device) || !quantity(lease.inode) ||
      !quantity(lease.maxBytes) || !quantity(lease.maxFrameBytes) ||
      !lease.maxFrameBytes || lease.maxFrameBytes > 16 * 1024 * 1024) fail('InvalidStoreDelegation');
  signal?.throwIfAborted();
  const fd = await open(lease.path, constants.O_WRONLY | constants.O_NOFOLLOW);
  let closed = false;
  let busy = false;
  let failed = false;
  let bytes = 0;
  const hash = createHash('sha256');
  const close = async () => { if (!closed) { await fd.close(); closed = true; } };
  const active = () => {
    signal?.throwIfAborted();
    if (closed || failed || busy) fail('InvalidStoreWriteState');
  };
  try {
    const state = await fd.stat();
    if (!state.isFile() || state.dev !== lease.device || state.ino !== lease.inode || state.size !== 0) fail('ForeignStoreFile');
    signal?.throwIfAborted();
  } catch (error) { await close(); throw error; }
  const append = async (frame, binary = false) => {
    active();
    if (binary ? !(frame instanceof Uint8Array) : typeof frame !== 'string') fail('InvalidStoreFrame');
    const size = binary ? frame.byteLength : Buffer.byteLength(frame, 'utf8');
    if (size > lease.maxFrameBytes || size > lease.maxBytes - bytes) fail('StoreCapacity');
    const buffer = binary ? Buffer.from(frame) : Buffer.from(frame, 'utf8');
    busy = true;
    try {
      let offset = 0;
      while (offset < size) {
        signal?.throwIfAborted();
        const { bytesWritten } = await fd.write(buffer, offset, size - offset, bytes + offset);
        if (!bytesWritten) fail('IncompleteStoreWrite');
        offset += bytesWritten;
      }
      hash.update(buffer);
      bytes += size;
    } catch (error) { failed = true; throw error; }
    finally { busy = false; }
  };
  return Object.freeze({
    append: text => append(text),
    appendBytes: bytes => append(bytes, true),
    async seal() {
      active();
      busy = true;
      try {
        const state = await fd.stat();
        if (state.size !== bytes || state.dev !== lease.device || state.ino !== lease.inode) fail('StoreIdentityMismatch');
        signal?.throwIfAborted();
        const cid = `sha256:${hash.digest('hex')}`;
        await close();
        signal?.throwIfAborted();
        return Object.freeze({ version: lease.version, session: lease.session,
          token: lease.token, bytes, cid });
      } catch (error) { failed = true; throw error; }
      finally { busy = false; }
    },
    async close() {
      if (busy) fail('StoreWriterBusy');
      failed = true;
      await close();
    },
  });
}
