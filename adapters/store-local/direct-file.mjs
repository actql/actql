// Trusted execution-side physical file access. This is not value admission or
// ActQL completion evidence. The callback must settle all native file use before
// returning; its value remains provisional until the final integrity checks.
import {open, lstat} from 'node:fs/promises';
import {constants} from 'node:fs';
import {createHash} from 'node:crypto';
import {RetainedFileError} from './files.mjs';

const fail = code => { throw new RetainedFileError(code); };
const quantity = value => Number.isSafeInteger(value) && value >= 0;

export async function withVerifiedDelegatedFile(supplied, use, signal) {
  const lease = Object.freeze({...supplied});
  if (lease.version !== 'actql-local-file-read/0.1' ||
      typeof lease.session !== 'string' || !lease.session.length || lease.session.length > 256 ||
      typeof lease.token !== 'string' || !/^[a-f0-9-]{36}$/.test(lease.token) ||
      typeof lease.path !== 'string' || !lease.path.length ||
      !quantity(lease.device) || !quantity(lease.inode) || !quantity(lease.bytes) ||
      typeof lease.cid !== 'string' || !/^sha256:[a-f0-9]{64}$/.test(lease.cid) ||
      !quantity(lease.maxFrameBytes) || !lease.maxFrameBytes || lease.maxFrameBytes > 16777216 ||
      typeof use !== 'function') fail('InvalidStoreReadDelegation');
  signal?.throwIfAborted();
  const fd = await open(lease.path, constants.O_RDONLY | constants.O_NOFOLLOW);
  let value;
  try {
    const check = state => {
      if (!state.isFile() || state.dev !== BigInt(lease.device) ||
          state.ino !== BigInt(lease.inode) || state.size !== BigInt(lease.bytes)) fail('ForeignStoreFile');
    };
    const before = await fd.stat({bigint: true});
    check(before);
    const unchanged = async () => {
      signal?.throwIfAborted();
      const [current, path] = await Promise.all([fd.stat({bigint: true}), lstat(lease.path, {bigint: true})]);
      check(current); check(path);
      if (current.mtimeNs !== before.mtimeNs || current.ctimeNs !== before.ctimeNs ||
          path.mtimeNs !== before.mtimeNs || path.ctimeNs !== before.ctimeNs) fail('RetainedBodyChanged');
      signal?.throwIfAborted();
    };
    await unchanged();
    const hash = createHash('sha256');
    const buffer = Buffer.alloc(Math.min(lease.maxFrameBytes, Math.max(1, lease.bytes)));
    let position = 0;
    while (position < lease.bytes) {
      signal?.throwIfAborted();
      const {bytesRead} = await fd.read(buffer, 0, Math.min(buffer.length, lease.bytes - position), position);
      if (!bytesRead) fail('RetainedBodyTruncated');
      hash.update(buffer.subarray(0, bytesRead));
      position += bytesRead;
    }
    if (`sha256:${hash.digest('hex')}` !== lease.cid) fail('RetainedBodyChanged');
    await unchanged();
    value = await use(Object.freeze({path: lease.path, bytes: lease.bytes}));
    await unchanged();
  } finally { await fd.close(); }
  signal?.throwIfAborted();
  return Object.freeze({value, report: Object.freeze({version: lease.version,
    session: lease.session, token: lease.token, bytes: lease.bytes, cid: lease.cid})});
}
