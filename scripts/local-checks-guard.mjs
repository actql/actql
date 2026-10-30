// Cooperative local execution only: no installed hook, daemon or OS quota.
import {execFileSync, fork} from 'node:child_process';
import {createHash, randomUUID} from 'node:crypto';
import {closeSync, constants, fstatSync, lstatSync, mkdirSync, openSync,
  readFileSync, readdirSync, readSync, realpathSync, statfsSync, unlinkSync, writeFileSync} from 'node:fs';
import {availableParallelism, homedir, hostname, totalmem} from 'node:os';
import {join} from 'node:path';

const same = (a, b) => a.dev === b.dev && a.ino === b.ino;
const digest = value => createHash('sha256').update(value).digest('hex');
const uid = () => process.getuid();

// A supplied budget is a duration, not a classification or approval. Bound it
// only by Node's timer range, so an overflowing timer cannot fire immediately.
export function durationSeconds(value, name = 'timeout-seconds') {
  const seconds = Number(value);
  if (!/^(?:\d+)(?:\.\d+)?$/u.test(String(value)) || !Number.isFinite(seconds) ||
      seconds <= 0 || seconds * 1000 > 2147483647) {
    throw new Error(`--${name} must be positive and fit Node's timer range`);
  }
  return seconds;
}

export function checkBudget(explicit, minutes) {
  if (explicit !== undefined) return durationSeconds(explicit);
  if (typeof minutes !== 'number' || !Number.isFinite(minutes) || minutes <= 0) {
    throw new Error('No workflow timeout is available; supply --timeout-seconds explicitly');
  }
  return durationSeconds(minutes * 60);
}

export function lockDirectory(home = homedir()) {
  const root = realpathSync(home);
  const paths = [root, join(root, '.cache'), join(root, '.cache', 'actql'),
    join(root, '.cache', 'actql', 'local-checks'),
    join(root, '.cache', 'actql', 'local-checks', digest(hostname()).slice(0, 16))];
  const identities = [];
  for (const [index, path] of paths.entries()) {
    if (index > 0) {
      try { mkdirSync(path); } catch (error) { if (error.code !== 'EEXIST') throw error; }
    }
    const stat = lstatSync(path);
    if (!stat.isDirectory() || stat.isSymbolicLink() || stat.uid !== uid()) {
      throw new Error(`Local check state must be a user-owned directory without symlinks: ${path}`);
    }
    identities.push(stat);
  }
  const check = () => paths.forEach((path, index) => {
    const stat = lstatSync(path);
    if (!stat.isDirectory() || stat.isSymbolicLink() || stat.uid !== uid() ||
        !same(stat, identities[index])) throw new Error(`Local check state ownership changed: ${path}`);
  });
  return {path: paths.at(-1), check};
}

function readLock(path) {
  // O_NOFOLLOW alone still blocks while opening a FIFO, before fstat or the
  // supervisor's execution timer can run. Never wait on an unowned object.
  const fd = openSync(path, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
  try {
    const stat = fstatSync(fd);
    if (!stat.isFile() || stat.uid !== uid() || stat.nlink !== 1 || stat.size > 16384) {
      throw new Error('Lock ownership or metadata is ambiguous');
    }
    // Bound the read itself as well: metadata may grow after fstat.
    const bytes = Buffer.alloc(16385);
    let length = 0, count;
    while (length < bytes.length && (count = readSync(fd, bytes, length, bytes.length - length, null))) length += count;
    if (length > 16384) throw new Error('Lock ownership or metadata is ambiguous');
    return {stat, owner: JSON.parse(bytes.subarray(0, length).toString('utf8'))};
  } finally { closeSync(fd); }
}

export function lockOwnerStatus(owner) {
  if (owner?.host !== hostname() || owner?.uid !== uid() ||
      !Number.isSafeInteger(owner?.pid) || owner.pid <= 0) return 'unknown';
  try { process.kill(owner.pid, 0); return 'PID present (identity may have changed)'; }
  catch (error) { return error.code === 'ESRCH' ? 'PID absent (children may remain)' : 'unknown'; }
}

const poolVersion = 'actql-local-heavy-pool/1';
export const maximumHeavyJobs = 4;
const mib = 1024 * 1024;

export function heavyResourceRequest(value = {}) {
  if (value === null || typeof value !== 'object' || Array.isArray(value) ||
      Object.keys(value).some(key => !['memoryBytes', 'diskBytes', 'cpuThreads'].includes(key))) {
    throw new Error('Invalid heavy verification resource request');
  }
  const request = {memoryBytes: 2048 * mib, diskBytes: 2048 * mib, cpuThreads: 2, ...value};
  if (Object.values(request).some(amount => !Number.isSafeInteger(amount) || amount <= 0)) {
    throw new Error('Heavy verification resources must be positive safe integers');
  }
  return request;
}

// These are cooperative verification reservations, not product limits or OS quotas.
// Current memory availability already reflects running jobs. Check the next
// job against that measurement, and all estimates against physical memory.
export function heavyResourceAdmission(request, members, available) {
  request = heavyResourceRequest(request);
  const reserved = {memoryBytes: 0, diskBytes: 0, cpuThreads: 0};
  for (const member of members) {
    const resources = heavyResourceRequest(member);
    for (const key of Object.keys(reserved)) reserved[key] += resources[key];
  }
  if (Object.keys(reserved).some(key => !Number.isSafeInteger(reserved[key]) ||
      !Number.isSafeInteger(available?.[key]) || available[key] < 0) ||
      !Number.isSafeInteger(available.totalMemoryBytes) || available.totalMemoryBytes < 0) {
    throw new Error('Invalid heavy verification headroom');
  }
  const required = {memoryBytes: request.memoryBytes + 256 * mib,
    diskBytes: reserved.diskBytes + request.diskBytes + 128 * mib,
    cpuThreads: reserved.cpuThreads + request.cpuThreads};
  const memoryPoolRequiredBytes = reserved.memoryBytes + required.memoryBytes;
  return {admitted: members.length < maximumHeavyJobs &&
    memoryPoolRequiredBytes <= available.totalMemoryBytes &&
    Object.keys(required).every(key => required[key] <= available[key]),
  limit: maximumHeavyJobs, request, reserved, required, memoryPoolRequiredBytes, available};
}

export function availableVerificationMemory(platform, text, total) {
  if (platform === 'linux') {
    const match = /^MemAvailable:\s+(\d+) kB$/mu.exec(text);
    const bytes = match && Number(match[1]) * 1024;
    if (Number.isSafeInteger(bytes) && bytes >= 0) return bytes;
  } else if (platform === 'darwin') {
    const match = /^System-wide memory free percentage: (\d+)%$/mu.exec(text);
    const percentage = match && Number(match[1]);
    if (match && percentage <= 100 && Number.isSafeInteger(total) && total > 0) {
      return Math.floor(total * percentage / 100);
    }
  }
  throw new Error('Available verification memory could not be measured');
}

function verificationHeadroom(root) {
  const disk = statfsSync(root, {bigint: true});
  const bytes = disk.bavail * disk.bsize;
  const memory = process.platform === 'darwin'
    ? execFileSync('/usr/bin/memory_pressure', ['-Q'], {encoding: 'utf8',
      timeout: 1000, maxBuffer: 8192, env: {...process.env, LC_ALL: 'C'}})
    : readFileSync('/proc/meminfo', 'utf8');
  const totalMemoryBytes = totalmem();
  return {memoryBytes: availableVerificationMemory(process.platform, memory, totalMemoryBytes),
    totalMemoryBytes,
    cpuThreads: availableParallelism(),
    diskBytes: Number(bytes > BigInt(Number.MAX_SAFE_INTEGER) ? BigInt(Number.MAX_SAFE_INTEGER) : bytes)};
}

function busyLock(path) {
  let detail = 'unreadable or incomplete owner metadata';
  try {
    const {owner} = readLock(path);
    detail = `token=${owner.token}; pid=${owner.pid}; ${lockOwnerStatus(owner)}; ` +
      `evidence=${owner.evidence ?? 'unavailable'}`;
  } catch { /* Never reclaim unreadable ownership. */ }
  return new Error(`Local check lock busy: ${path}\n${detail}\n` +
    'No automatic stale-lock removal. Inspect this owner and its processes before manual recovery.');
}

function newLock(path, owner, directory) {
  directory.check();
  let fd;
  try { fd = openSync(path, constants.O_WRONLY | constants.O_CREAT |
    constants.O_EXCL | constants.O_NOFOLLOW, 0o600); }
  catch (error) { if (error.code === 'EEXIST') throw busyLock(path); throw error; }
  try {
    const stat = fstatSync(fd);
    writeFileSync(fd, JSON.stringify(owner) + '\n');
    return {path, stat};
  } finally { closeSync(fd); }
}

function checkedLock(item, token, directory) {
  directory.check();
  const current = readLock(item.path);
  if (!same(current.stat, item.stat) || !same(lstatSync(item.path), item.stat) ||
      current.owner.token !== token) {
    throw new Error(`Refusing to remove a changed local check lock: ${item.path}`);
  }
  return current;
}

function removeLock(item, token, directory) {
  checkedLock(item, token, directory);
  unlinkSync(item.path);
}

function withPoolAdmission(directory, owner, use) {
  const path = join(directory.path, 'heavy-pool-admission.lock');
  const deadline = process.hrtime.bigint() + 1_000_000_000n;
  let mutex;
  while (!mutex) {
    try { mutex = newLock(path, owner, directory); }
    catch (error) {
      if (error.message.startsWith('Local check lock busy:') && process.hrtime.bigint() < deadline) {
        Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 10);
      } else throw error;
    }
  }
  try { return use(); }
  finally { removeLock(mutex, owner.token, directory); }
}

function poolMembers(directory, poolToken) {
  const members = [];
  const known = new Set([1, 2, 3, 4].map(slot => `heavy-slot-${slot}.lock`));
  for (const name of readdirSync(directory.path)) {
    if (name.startsWith('heavy-slot-') && !known.has(name)) throw busyLock(join(directory.path, name));
  }
  for (let slot = 1; slot <= maximumHeavyJobs; slot++) {
    const path = join(directory.path, `heavy-slot-${slot}.lock`);
    let member;
    try { member = readLock(path); }
    catch (error) { if (error.code === 'ENOENT') continue; throw busyLock(path); }
    const pool = member.owner.heavyPool;
    if (pool?.version !== poolVersion || pool.token !== poolToken || pool.slot !== slot ||
        member.owner.uid !== uid() || member.owner.host !== hostname() ||
        typeof member.owner.token !== 'string' || member.owner.token.length === 0 ||
        typeof member.owner.worktree !== 'string' || member.owner.worktree.length === 0 ||
        !Number.isSafeInteger(member.owner.pid) ||
        member.owner.pid <= 0 || pool.resources === null || typeof pool.resources !== 'object' ||
        Object.keys(pool.resources).sort().join(',') !== 'cpuThreads,diskBytes,memoryBytes') {
      throw busyLock(path);
    }
    heavyResourceRequest(pool.resources);
    // A reservation remains bound to the original exclusive worktree Owner.
    // Missing or replaced custody is not available capacity, even with a valid pool token.
    let worktree;
    try {
      worktree = readLock(join(directory.path, `worktree-${digest(member.owner.worktree)}.lock`));
      if (['token', 'pid', 'uid', 'host', 'worktree'].some(key =>
        worktree.owner?.[key] !== member.owner[key])) throw new Error('Heavy member worktree Owner changed');
    } catch { throw busyLock(path); }
    members.push({...member, path});
  }
  return members;
}

function acquireHeavyReservation(root, owner, directory, resources) {
  return withPoolAdmission(directory, owner, () => {
    const path = join(directory.path, 'heavy.lock');
    let barrier, created = false;
    try { barrier = {...readLock(path), path}; }
    catch (error) {
      if (error.code !== 'ENOENT') throw busyLock(path);
      // Retained slots without their barrier are ambiguous, not free capacity.
      for (let slot = 1; slot <= maximumHeavyJobs; slot++) {
        try { lstatSync(join(directory.path, `heavy-slot-${slot}.lock`)); }
        catch (missing) { if (missing.code === 'ENOENT') continue; throw missing; }
        throw new Error('Heavy reservation exists without its legacy barrier; inspect ownership');
      }
      const token = randomUUID();
      const barrierOwner = {...owner, heavyPool: {version: poolVersion, token}};
      barrier = {...newLock(path, barrierOwner, directory), owner: barrierOwner};
      created = true;
    }
    const pool = barrier.owner.heavyPool;
    if (pool?.version !== poolVersion || typeof pool.token !== 'string' ||
        barrier.owner.uid !== uid() || barrier.owner.host !== hostname() ||
        typeof barrier.owner.token !== 'string' || !Number.isSafeInteger(barrier.owner.pid) ||
        barrier.owner.pid <= 0) throw busyLock(path);
    let reservation;
    try {
      const members = poolMembers(directory, pool.token);
      if (!created && members.length === 0) throw busyLock(path);
      const admission = heavyResourceAdmission(resources,
        members.map(member => member.owner.heavyPool.resources), verificationHeadroom(root));
      if (!admission.admitted) throw new Error('Heavy verification queue/resource pressure: ' +
        JSON.stringify({...admission, members: members.map(member => member.owner.pid)}));
      const occupied = new Set(members.map(member => member.owner.heavyPool.slot));
      const slot = [1, 2, 3, 4].find(value => !occupied.has(value));
      const slotOwner = {...owner, heavyPool: {version: poolVersion,
        token: pool.token, slot, resources: admission.request}};
      reservation = newLock(join(directory.path, `heavy-slot-${slot}.lock`), slotOwner, directory);
      return {reservation, barrier, admission: {...admission, slot,
        barrier: path, members: members.map(member => member.owner.pid)}, release() {
        withPoolAdmission(directory, owner, () => {
          const current = checkedLock(barrier, barrier.owner.token, directory);
          if (current.owner.heavyPool?.version !== poolVersion ||
              current.owner.heavyPool.token !== pool.token) {
            throw new Error('Refusing to remove a changed heavy compatibility barrier');
          }
          checkedLock(reservation, owner.token, directory);
          const members = poolMembers(directory, pool.token);
          if (!members.some(member => same(member.stat, reservation.stat))) {
            throw new Error('Heavy reservation membership changed');
          }
          removeLock(reservation, owner.token, directory);
          if (members.length === 1) removeLock(barrier, barrier.owner.token, directory);
        });
      }};
    } catch (error) {
      if (created && !reservation) removeLock(barrier, barrier.owner.token, directory);
      throw error;
    }
  });
}

export function acquireLocalLocks({root, heavy, heavyResources, directory = lockDirectory(), evidence}) {
  const worktree = realpathSync(root);
  const owner = {token: randomUUID(), pid: process.pid, uid: uid(), host: hostname(),
    worktree, startedAt: new Date().toISOString(), evidence};
  const paths = [join(directory.path, `worktree-${digest(worktree)}.lock`)];
  const held = [];
  let shared;
  const release = () => {
    // Preserve the original worktree identity refusal before changing shared custody.
    for (const item of held) {
      try { checkedLock(item, owner.token, directory); }
      catch (error) { if (error.code === 'ENOENT') throw busyLock(item.path); throw error; }
    }
    if (shared) { shared.release(); shared = undefined; }
    for (const item of [...held].reverse()) {
      removeLock(item, owner.token, directory);
      held.splice(held.indexOf(item), 1);
    }
  };
  try {
    for (const path of paths) {
      held.push(newLock(path, owner, directory));
      directory.check();
    }
    if (heavy) {
      shared = acquireHeavyReservation(worktree, owner, directory, heavyResources);
      paths.push(shared.reservation.path);
    }
    return {owner, paths, release, heavyAdmission: shared?.admission};
  } catch (error) {
    try { release(); } catch (cleanup) { error.message += `\n${cleanup.message}`; }
    throw error;
  }
}

// The supervisor owns the new process group and its locks, including when the
// caller is killed. IPC disconnect requests cancellation; there is no PID poll.
export function runLocalCheck(config, {signal} = {}) {
  if (signal?.aborted) return Promise.resolve(130);
  return new Promise((resolve, reject) => {
    const child = fork(new URL('./local-checks-supervisor.mjs', import.meta.url), [], {
      cwd: config.root, detached: true, execArgv: [], stdio: ['ignore', 'inherit', 'inherit', 'ipc'],
    });
    let terminalStatus;
    child.on('message', message => {
      if (Number.isInteger(message.terminalStatus)) terminalStatus = message.terminalStatus;
    });
    const cancel = () => {
      if (child.connected) child.send({cancel: true});
    };
    const interrupt = () => cancel();
    process.on('SIGINT', interrupt);
    process.on('SIGTERM', interrupt);
    signal?.addEventListener('abort', cancel, {once: true});
    child.on('error', reject);
    child.on('exit', (code, stopped) => {
      process.removeListener('SIGINT', interrupt);
      process.removeListener('SIGTERM', interrupt);
      signal?.removeEventListener('abort', cancel);
      // SIGKILL deliberately retains locks, rather than guessing that all
      // descendants have stopped or deleting a possibly reused owner's lock.
      resolve(code ?? terminalStatus ?? (stopped === 'SIGKILL' ? 137 : 1));
    });
    child.send({config});
  });
}
