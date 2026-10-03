// Cooperative local execution only: no installed hook, daemon or OS quota.
import {fork} from 'node:child_process';
import {createHash, randomUUID} from 'node:crypto';
import {closeSync, constants, fstatSync, lstatSync, mkdirSync, openSync,
  readSync, realpathSync, unlinkSync, writeFileSync} from 'node:fs';
import {homedir, hostname} from 'node:os';
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

export function acquireLocalLocks({root, heavy, directory = lockDirectory(), evidence}) {
  const worktree = realpathSync(root);
  const owner = {token: randomUUID(), pid: process.pid, uid: uid(), host: hostname(),
    worktree, startedAt: new Date().toISOString(), evidence};
  const paths = [join(directory.path, `worktree-${digest(worktree)}.lock`)];
  if (heavy) paths.push(join(directory.path, 'heavy.lock'));
  const held = [];
  const release = () => {
    for (const item of [...held].reverse()) {
      directory.check();
      const current = readLock(item.path);
      if (!same(current.stat, item.stat) || !same(lstatSync(item.path), item.stat) ||
          current.owner.token !== owner.token) {
        throw new Error(`Refusing to remove a changed local check lock: ${item.path}`);
      }
      unlinkSync(item.path);
      held.splice(held.indexOf(item), 1);
    }
  };
  try {
    for (const path of paths) {
      directory.check();
      let fd;
      try { fd = openSync(path, constants.O_WRONLY | constants.O_CREAT |
        constants.O_EXCL | constants.O_NOFOLLOW, 0o600); }
      catch (error) {
        if (error.code !== 'EEXIST') throw error;
        let detail = 'unreadable or incomplete owner metadata';
        try {
          const {owner: previous} = readLock(path);
          detail = `token=${previous.token}; pid=${previous.pid}; ${lockOwnerStatus(previous)}; ` +
            `evidence=${previous.evidence ?? 'unavailable'}`;
        } catch { /* Never reclaim unreadable ownership. */ }
        throw new Error(`Local check lock busy: ${path}\n${detail}\n` +
          'No automatic stale-lock removal. Inspect this owner and its processes before manual recovery.');
      }
      try {
        const stat = fstatSync(fd);
        held.push({path, stat});
        writeFileSync(fd, JSON.stringify(owner) + '\n');
      } finally { closeSync(fd); }
      directory.check();
    }
    return {owner, paths, release};
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
