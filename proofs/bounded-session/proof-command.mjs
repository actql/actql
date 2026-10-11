import {spawn} from 'node:child_process';

// Proof tooling custody only: this does not establish a public Run terminal.
// Each POSIX child owns a separate process group. Keep custody through output
// close, including when a synchronous caller times out and signals this runner.
export async function runProofCommand(command, args, {
  cwd, input, env, maxBuffer = 4 * 1024 * 1024, timeout = 0,
} = {}) {
  const grouped = process.platform !== 'win32';
  let child, error, interrupted = null, timer, killTimer, groupClosed = null;
  let stdout = [], stderr = [], bytes = 0;
  const fail = (message, code) => {
    error ??= Object.assign(new Error(message), {code});
  };
  const signal = value => {
    if (!child?.pid) return;
    try {
      if (grouped) process.kill(-child.pid, value);
      else child.kill(value);
    } catch (cause) {
      if (cause.code !== 'ESRCH') error ??= cause;
    }
  };
  const stop = value => {
    signal(value);
    // This bounds physical shutdown, not proof execution or its caller's limit.
    killTimer ??= setTimeout(() => signal('SIGKILL'), 1000);
  };
  const onTerm = () => {
    interrupted ??= 'SIGTERM';
    fail('Proof runner interrupted by SIGTERM', 'EINTR');
    stop('SIGTERM');
  };
  const onInt = () => {
    interrupted ??= 'SIGINT';
    fail('Proof runner interrupted by SIGINT', 'EINTR');
    stop('SIGINT');
  };
  process.on('SIGTERM', onTerm);
  process.on('SIGINT', onInt);
  try {
    child = spawn(command, args, {cwd, env, detached: grouped, stdio: 'pipe'});
    const collect = chunks => chunk => {
      bytes += chunk.length;
      if (bytes <= maxBuffer) chunks.push(chunk);
      else {
        fail('Proof command output exceeds maxBuffer', 'ENOBUFS');
        stop('SIGTERM');
      }
    };
    child.stdout.on('data', collect(stdout));
    child.stderr.on('data', collect(stderr));
    child.stdin.on('error', cause => {
      // A nonzero/terminated child may close stdin before accepting all input.
      if (cause.code !== 'EPIPE') { error ??= cause; stop('SIGTERM'); }
    });
    if (timeout) timer = setTimeout(() => {
      fail('Proof command timed out', 'ETIMEDOUT');
      stop('SIGTERM');
    }, timeout);
    const result = await new Promise(resolve => {
      child.on('error', cause => { error ??= cause; });
      child.on('exit', () => {
        if (!grouped) return;
        try {
          process.kill(-child.pid, 0);
          fail('Proof child exited with surviving group members', 'ECHILDCUSTODY');
          stop('SIGTERM');
        } catch (cause) {
          if (cause.code !== 'ESRCH') { error ??= cause; stop('SIGTERM'); }
        }
      });
      child.on('close', (status, signal) => resolve({status, signal}));
      child.stdin.end(input);
    });
    // A detached descendant may have closed its output before physically
    // stopping. Do not equate pipe close with group shutdown.
    if (grouped && child.pid) {
      groupClosed = false;
      for (let i = 0; i < 200; i++) {
        try { process.kill(-child.pid, 0); }
        catch (cause) {
          if (cause.code === 'ESRCH') { groupClosed = true; break; }
          error ??= cause;
          break;
        }
        fail('Proof command retains group custody after output close', 'ECHILDCUSTODY');
        stop('SIGTERM');
        if (i === 199) fail('Proof group did not close after shutdown', 'ECHILDCUSTODY');
        await new Promise(resolve => setTimeout(resolve, 10));
      }
    }
    return {...result, error, interrupted, outputClosed: true, groupClosed,
      stdout: Buffer.concat(stdout).toString('utf8'),
      stderr: Buffer.concat(stderr).toString('utf8')};
  } finally {
    clearTimeout(timer);
    clearTimeout(killTimer);
    process.off('SIGTERM', onTerm);
    process.off('SIGINT', onInt);
  }
}
