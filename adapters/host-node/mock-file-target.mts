// Physical file custody for the installed Mock Row Effect. Common owns the
// declaration, complete document/row admission, version and exact replacement
// bytes. Account/Checkpoint/claim owners authorize calls into this private
// helper; a pathname, callback result or matching hash cannot issue a grant.
import {open, lstat, unlink, rename} from 'node:fs/promises';
import {constants, type BigIntStats} from 'node:fs';
import {dirname, isAbsolute} from 'node:path';
import {randomUUID} from 'node:crypto';

type FileIdentity = Pick<BigIntStats, 'dev' | 'ino'>;
type FileExtent = Pick<BigIntStats, keyof FileIdentity | 'size' | 'mtimeNs' | 'ctimeNs'>;
type BigIntStat = Readonly<{bigint: true}>;
type Handle = {
  close(): unknown;
  stat(options: BigIntStat): BigIntStats | PromiseLike<BigIntStats>;
  read(bytes: Buffer, offset: number, length: number, position: number):
    {bytesRead: number} | PromiseLike<{bytesRead: number}>;
  writeFile(bytes: Buffer): unknown;
  sync(): unknown;
};
type Io = {
  open(path: string, flags: number, mode?: number): Handle | PromiseLike<Handle>;
  lstat(path: string, options: BigIntStat): BigIntStats | PromiseLike<BigIntStats>;
  unlink(path: string): unknown;
  rename(from: string, to: string): unknown;
};
type Current = () => unknown;
type FundRead = (size: number) => unknown;
type TargetOptions = Readonly<{
  dataPath: string;
  maxBytes: number;
  assertCurrent: Current;
  observeWrite?: (runOriginal: object | undefined) => unknown;
  io?: Io;
}>;
type ChildOptions = Readonly<{
  authorize(): unknown;
  signal?: AbortSignal;
  assertCurrent?: Current;
  runOriginal?: object;
}>;
type Slot = {
  path: string;
  handle: Handle;
  methods: Map<keyof Handle, Handle[keyof Handle]>;
  closed: boolean;
  pathPending: boolean;
  identity?: FileIdentity;
};
type CloseStatus = Readonly<{pending: boolean; errors: readonly unknown[]}>;
type TargetStatus = Readonly<{pending: boolean; children: number; closing: boolean}>;
type Releasable = Readonly<{release(): Promise<CloseStatus>}>;
type RunScope = {closing: boolean; flight?: Promise<TargetStatus>};
type ChildOperations = Readonly<{
  acquire(path: string, flags: number, mode?: number, ownsPath?: boolean): Promise<Slot>;
  call<Name extends keyof Handle>(slot: Slot, name: Name, ...args: Parameters<Handle[Name]>): ReturnType<Handle[Name]>;
  read(fundRead?: FundRead): Promise<{bytes: Buffer; file: Slot; before: BigIntStats}>;
  unchanged(slot: Slot, before: BigIntStats): Promise<void>;
  originalPath(slot: Slot): Promise<void>;
  current(): void;
}>;

const fail: (code: string, cause?: unknown) => never = (code, cause) => {throw Object.assign(new Error(code, {cause}), {code});};
const identity = (info: FileIdentity) => ({dev: info.dev, ino: info.ino});
const sameIdentity = (a: FileIdentity | undefined, b: FileIdentity | undefined) => a?.dev === b?.dev && a?.ino === b?.ino;
const sameFile = (a: FileExtent, b: FileExtent) => sameIdentity(a, b) &&
  a.size === b.size && a.mtimeNs === b.mtimeNs && a.ctimeNs === b.ctimeNs;
const apply = Reflect.apply;
const synchronous = (value: unknown) => {
  if (value === undefined) return;
  if (value instanceof Promise) void value.catch(() => {});
  fail('InvalidMockFileCurrentFence');
};

export function createMockFileTarget({dataPath, maxBytes, assertCurrent, observeWrite,
  io = {open, lstat, unlink, rename}}: TargetOptions) {
  if (!isAbsolute(dataPath ?? '') || !Number.isSafeInteger(maxBytes) || maxBytes < 1 ||
      typeof assertCurrent !== 'function' ||
      observeWrite !== undefined && typeof observeWrite !== 'function' ||
      !(['open', 'lstat', 'unlink', 'rename'] as const).every(name => typeof io[name] === 'function')) {
    fail('InvalidMockFileTarget');
  }
  const physical = Object.freeze(Object.fromEntries(
    (['open', 'lstat', 'unlink', 'rename'] as const).map(name => [name, io[name].bind(io)]))) as Readonly<Io>;
  const children = new Set<Releasable>(), childOriginals = new WeakMap<Releasable, object>(),
    runScopes = new WeakMap<object, RunScope>();
  let closing = false, closeFlight: Promise<TargetStatus> | undefined;
  function scope(original: object) {
    if (original === null || typeof original !== 'object') fail('InvalidMockFileRunOriginal');
    let retained = runScopes.get(original);
    if (retained === undefined) {
      retained = {closing: false, flight: undefined};
      runScopes.set(original, retained);
    }
    return retained;
  }
  function current(signal?: AbortSignal) {
    if (closing) fail('MockFileTargetClosing');
    signal?.throwIfAborted();
    synchronous(assertCurrent());
  }
  function makeChild<T>(perform: (operations: ChildOperations) => Promise<T>,
    signal: AbortSignal | undefined, checkCurrent: Current | undefined, runOriginal: object | undefined) {
    const retained = runOriginal === undefined ? undefined : scope(runOriginal);
    const childCurrent = () => {
      current(signal);
      if (retained?.closing) fail('MockFileRunClosing');
      synchronous(checkCurrent?.());
    };
    if (retained?.closing) fail('MockFileRunClosing');
    const slots: Slot[] = [];
    let flight: Promise<T> | undefined, cleanupFlight: Promise<CloseStatus> | undefined, released = false, stopping = false;
    let firstFailure: unknown, latestFailure: unknown, failureSeen = false;
    const remember = (cause: unknown) => {
      if (!failureSeen) {firstFailure = cause; failureSeen = true;}
      latestFailure = cause;
    };
    function method<Name extends keyof Handle>(slot: Slot, name: Name): Handle[Name] {
      if (!slot.methods.has(name)) {
        const value = slot.handle[name];
        if (typeof value !== 'function') fail('MockFileMethodUnavailable');
        slot.methods.set(name, value);
      }
      return slot.methods.get(name) as Handle[Name];
    }
    const call = <Name extends keyof Handle>(slot: Slot, name: Name, ...args: Parameters<Handle[Name]>):
      ReturnType<Handle[Name]> => apply(method(slot, name), slot.handle, args) as ReturnType<Handle[Name]>;
    async function acquire(path: string, flags: number, mode?: number, ownsPath = false) {
      childCurrent();
      const handle = await physical.open(path, flags, mode);
      // Retain before observing close/stat/current or any further await.
      const slot: Slot = {path, handle, methods: new Map(), closed: false,
        pathPending: ownsPath, identity: undefined};
      slots.push(slot);
      method(slot, 'close');
      slot.identity = identity(await call(slot, 'stat', {bigint: true}));
      childCurrent();
      return slot;
    }
    async function unchanged(slot: Slot, before: BigIntStats) {
      childCurrent();
      const now = await call(slot, 'stat', {bigint: true});
      const named = await physical.lstat(slot.path, {bigint: true});
      if (!now.isFile() || !named.isFile() ||
          !sameFile(before, now) || !sameFile(before, named)) fail('MockFileTargetChanged');
      childCurrent();
    }
    async function read(fundRead?: FundRead) {
      const file = await acquire(dataPath, constants.O_RDONLY | constants.O_NOFOLLOW);
      const before = await call(file, 'stat', {bigint: true});
      if (!before.isFile() || before.nlink !== 1n || before.size > BigInt(maxBytes)) {
        fail('InvalidMockTargetFile');
      }
      const size = Number(before.size);
      // The selected writer may grow its same physical reservation from
      // this locked FD's checked size, before allocating or reading the body.
      if (fundRead !== undefined) {
        synchronous(fundRead(size));
        childCurrent();
      }
      const bytes = Buffer.alloc(size);
      let offset = 0;
      while (offset < size) {
        childCurrent();
        const result = await call(file, 'read', bytes, offset, size - offset, offset);
        if (!Number.isSafeInteger(result.bytesRead) || result.bytesRead <= 0 ||
            result.bytesRead > size - offset) fail('MockFileTargetChanged');
        offset += result.bytesRead;
      }
      await unchanged(file, before);
      return {bytes, file, before};
    }
    async function originalPath(slot: Slot) {
      const named = await physical.lstat(slot.path, {bigint: true});
      if (!named.isFile() || !sameIdentity(slot.identity, named)) {
        fail('MockFileTargetPathChanged');
      }
    }
    async function cleanup() {
      stopping = true;
      if (flight !== undefined) {
        try {await flight;} catch { /* Preserve the original operation failure. */ }
      }
      // A failed first stat still owns its acquired FD/path. Observe only that
      // same FD on cleanup; never acquire a replacement or clear an unknown path.
      for (const slot of slots.slice().reverse()) {
        if (slot.closed) continue;
        try {
          if (slot.pathPending && slot.identity === undefined) {
            slot.identity = identity(await call(slot, 'stat', {bigint: true}));
          }
          if (await call(slot, 'close') === false) fail('MockFileCleanupPending');
          slot.closed = true;
        } catch (cause) {remember(cause);}
      }
      // Keep writer exclusion while ANY original FD has not acknowledged close.
      if (slots.some(slot => !slot.closed)) return false;
      for (const slot of slots.slice().reverse()) {
        if (!slot.pathPending) continue;
        if (slot.path === dataPath + '.actql-write.lock' &&
            slots.some(other => other !== slot && other.pathPending)) continue;
        try {
          await originalPath(slot);
          await physical.unlink(slot.path);
          slot.pathPending = false;
        } catch (cause) {
          if ((cause as NodeJS.ErrnoException | undefined)?.code === 'ENOENT') slot.pathPending = false;
          else remember(cause);
        }
      }
      if (slots.some(slot => slot.pathPending)) return false;
      released = true;
      children.delete(child);
      return true;
    }
    const status = () => Object.freeze({pending: !released,
      errors: Object.freeze(!failureSeen ? [] : firstFailure === latestFailure
        ? [firstFailure] : [firstFailure, latestFailure])});
    const drain = () => {
      if (released) return Promise.resolve(status());
      if (cleanupFlight !== undefined) return cleanupFlight;
      cleanupFlight = cleanup().then(() => status()).finally(() => {cleanupFlight = undefined;});
      return cleanupFlight;
    };
    const child = Object.freeze({status, release: drain, retry: drain,
      prepare() {
        if (stopping || released) return Promise.reject(Object.assign(
          new Error('MockFileChildRetired'), {code: 'MockFileChildRetired'}));
        if (flight === undefined) flight = Promise.resolve().then(() => {
          childCurrent();
          return perform({acquire, call, read, unchanged, originalPath, current: childCurrent});
        });
        return flight;
      }});
    children.add(child);
    if (runOriginal !== undefined) childOriginals.set(child, runOriginal);
    return child;
  }
  function readChild<T>({authorize, consume, signal, assertCurrent: checkCurrent, runOriginal}:
    ChildOptions & Readonly<{consume(bytes: Buffer): T}>) {
    if (typeof authorize !== 'function' || typeof consume !== 'function' ||
        (checkCurrent !== undefined && typeof checkCurrent !== 'function')) fail('InvalidMockFileRead');
    current(signal);
    return makeChild(async ({read, current}) => {
      // The installed Site validates its original current Account/read decision.
      // This helper never interprets a permission Bool or copied grant fields.
      await authorize();
      current();
      const {bytes} = await read();
      current();
      const value = consume(bytes);
      if (value instanceof Promise) fail('InvalidMockTargetProjection');
      current();
      return value;
    }, signal, checkCurrent, runOriginal);
  }
  function updateChild({authorize, replace, signal, assertCurrent: checkCurrent, runOriginal, fundRead}:
    ChildOptions & Readonly<{replace(bytes: Buffer): unknown; fundRead?: FundRead}>) {
    if (typeof authorize !== 'function' || typeof replace !== 'function' ||
        (checkCurrent !== undefined && typeof checkCurrent !== 'function') ||
        (fundRead !== undefined && typeof fundRead !== 'function')) fail('InvalidMockFileUpdate');
    current(signal);
    return makeChild(async ({acquire, call, read, unchanged, originalPath, current}) => {
      // This is entered only by the Row Effect's original durable dispatch claim.
      // The same-path exclusion coordinates writers across Host installations.
      await authorize();
      current();
      const lock = await acquire(dataPath + '.actql-write.lock',
        constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL | constants.O_NOFOLLOW,
        0o600, true);
      const {bytes, file, before} = await read(fundRead);
      if (before.uid !== BigInt(process.getuid!()) || (before.mode & 0o200n) === 0n) {
        fail('MockFileTargetNotWritable');
      }
      // Common re-admits the WHOLE latest document, checks the same original
      // row version and emits only the checked Mapping's replacement spans.
      const projected = replace(bytes);
      if (!(projected instanceof Uint8Array) || projected.length > maxBytes) {
        fail('InvalidMockTargetReplacement');
      }
      const output = Buffer.from(projected);
      current();
      const temporary = await acquire(dataPath + '.actql-' + randomUUID() + '.tmp',
        constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL | constants.O_NOFOLLOW,
        Number(before.mode & 0o777n), true);
      await call(temporary, 'writeFile', output);
      await call(temporary, 'sync');
      current();
      await unchanged(file, before);
      await originalPath(lock);
      current();
      // Any throw at/after replacement remains with the same durable claim;
      // cleanup never retries this operation or manufactures a successful ACK.
      await physical.rename(temporary.path, dataPath);
      temporary.pathPending = false;
      // The original replacement returned. This says nothing about the later
      // directory sync/current/cleanup, and diagnostics cannot alter its fate.
      if (observeWrite !== undefined) try {void Promise.resolve(observeWrite(runOriginal)).catch(() => {});} catch {}
      current();
      const directory = await acquire(dirname(dataPath), constants.O_RDONLY);
      await call(directory, 'sync');
      current();
      return Object.freeze({bytes: output.length});
    }, signal, checkCurrent, runOriginal);
  }
  const status = () => Object.freeze({pending: children.size !== 0,
    children: children.size, closing});
  const statusFor = (original: object) => {
    const retained = scope(original);
    const count = [...children].filter(child => childOriginals.get(child) === original).length;
    return Object.freeze({pending: count !== 0, children: count, closing: retained.closing});
  };
  function closeFor(original: object) {
    const retained = scope(original);
    retained.closing = true;
    if (retained.flight !== undefined) return retained.flight;
    retained.flight = (async () => {
      // A Run cannot acknowledge, stop or retire another Run's actual children.
      for (const child of [...children]) {
        if (childOriginals.get(child) === original) await child.release();
      }
      const observed = statusFor(original);
      if (observed.pending) fail('MockFileCleanupPending');
      return observed;
    })().finally(() => {retained.flight = undefined;});
    return retained.flight;
  }
  return Object.freeze({readChild, updateChild, status, statusFor, closeFor,
    close() {
      closing = true;
      if (closeFlight !== undefined) return closeFlight;
      closeFlight = (async () => {
        for (const child of [...children]) await child.release();
        const observed = status();
        if (observed.pending) fail('MockFileCleanupPending');
        return observed;
      })().finally(() => {closeFlight = undefined;});
      return closeFlight;
    }});
}
