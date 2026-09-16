// Physical Store reader for a Host-admitted local process session. Bytes remain
// provisional until whole-body verification; callers admit values/completion
// separately. No pathname or digest here can create ActQL result authority.
import { open } from 'node:fs/promises';
import { constants } from 'node:fs';
import { createHash } from 'node:crypto';
import { RetainedFileError } from './files.mjs';

const fail = code => { throw new RetainedFileError(code); };
const quantity = n => Number.isSafeInteger(n) && n >= 0;

export async function consumeDelegatedFile(supplied, accept, signal) {
  const lease = Object.freeze({ ...supplied });
  if (lease.version !== 'actql-local-file-read/0.1' ||
      typeof lease.session !== 'string' || !lease.session.length || lease.session.length > 256 ||
      typeof lease.token !== 'string' || !/^[a-f0-9-]{36}$/.test(lease.token) ||
      typeof lease.path !== 'string' || !lease.path.length ||
      !quantity(lease.device) || !quantity(lease.inode) || !quantity(lease.bytes) ||
      typeof lease.cid !== 'string' || !/^sha256:[a-f0-9]{64}$/.test(lease.cid) ||
      !quantity(lease.maxFrameBytes) || !lease.maxFrameBytes || lease.maxFrameBytes > 16 * 1024 * 1024 ||
      typeof accept !== 'function') fail('InvalidStoreReadDelegation');
  signal?.throwIfAborted();
  const fd = await open(lease.path, constants.O_RDONLY | constants.O_NOFOLLOW);
  let report;
  try {
    const check = async () => {
      const state = await fd.stat();
      if (!state.isFile() || state.dev !== lease.device || state.ino !== lease.inode ||
          state.size !== lease.bytes) fail('ForeignStoreFile');
      signal?.throwIfAborted();
    };
    await check();
    const hash = createHash('sha256');
    const buffer = Buffer.alloc(Math.min(lease.maxFrameBytes, Math.max(1, lease.bytes)));
    let position = 0;
    while (position < lease.bytes) {
      signal?.throwIfAborted();
      const { bytesRead } = await fd.read(buffer, 0, Math.min(buffer.length, lease.bytes - position), position);
      if (!bytesRead) fail('RetainedBodyTruncated');
      signal?.throwIfAborted();
      hash.update(buffer.subarray(0, bytesRead));
      await accept(buffer.subarray(0, bytesRead));
      signal?.throwIfAborted();
      position += bytesRead;
    }
    await check();
    if (`sha256:${hash.digest('hex')}` !== lease.cid) fail('RetainedBodyChanged');
    report = Object.freeze({ version: lease.version, session: lease.session,
      token: lease.token, bytes: position, cid: lease.cid });
  } finally { await fd.close(); }
  signal?.throwIfAborted();
  return report;
}
