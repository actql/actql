// One invocation, one live process-group leader. Never signal a stored PID.
import {spawn, spawnSync} from 'node:child_process';
import {closeSync, constants, fstatSync, ftruncateSync, lstatSync, mkdirSync,
  mkdtempSync, openSync, realpathSync, writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {acquireLocalLocks, durationSeconds} from './local-checks-guard.mjs';
import {COMMAND_OUTPUT_LIMIT, redactCommandArguments, redactCommandEvidence} from './packed-query-evidence.mjs';

let config, locks, directory, evidence, timer, escalation, child, primaryStatus;
let childClosed = true;
let cancelling = false, finished = false, groupOwned = false, retainLocks = false;
let output = [], outputBytes = 0, outputComplete = true;
let summary = {startedAt: new Date().toISOString(), status: 'starting', complete: false, steps: []};
const env = process.env;
// Caller pipes can reject early diagnostics, or stop draining after the command
// exits. Keep their faults separate from captured command evidence and never
// report a stream error by writing recursively to that same stream.
const callerStreams = ['stdout', 'stderr'].map(name => {
  const stream = process[name], state = {name, stream};
  stream.on('error', error => { state.error ??= error; });
  stream.on('close', () => { state.error ??= new Error('CallerOutputClosed'); });
  return state;
});
function writeCaller(name, text) {
  const state = callerStreams.find(item => item.name === name);
  if (state.error) return;
  try { state.stream.write(text, error => { if (error) state.error ??= error; }); }
  catch (error) { state.error ??= error; }
}
const diagnostic = message => writeCaller('stderr', `${message}\n`);
const same = (a, b) => a.dev === b.dev && a.ino === b.ino;

async function flushCallerOutput(deadline) {
  await Promise.all(callerStreams.map(state => new Promise(resolve => {
    if (state.error) { resolve(); return; }
    const {stream} = state;
    const done = error => {
      if (error) state.error ??= error;
      clearTimeout(timeout);
      stream.removeListener('error', done);
      stream.removeListener('close', closed);
      resolve();
    };
    const closed = () => done(new Error('CallerOutputClosed'));
    const timeout = setTimeout(() => done(new Error('CallerOutputFlushTimeout')),
      Math.max(0, deadline - performance.now()));
    stream.once('error', done);
    stream.once('close', closed);
    // A callback on the last queued write also waits for earlier diagnostics.
    // A true return from write() alone would not prove delivery to the pipe.
    try { stream.write('', done); } catch (error) { done(error); }
  })));
}

function recordCallerFailures() {
  for (const state of callerStreams) {
    if (!state.error || state.reported) continue;
    state.reported = true;
    (summary.errors ??= []).push({stage: `${state.name} forwarding`,
      code: state.error.code ?? state.error.message});
  }
  summary.callerOutputComplete = !callerStreams.some(state => state.error);
  return !summary.callerOutputComplete;
}

// The same ownership checks as packed-query-evidence: a unique canonical
// directory, exclusive initial files, and truncation only through a checked
// no-follow descriptor. Check ancestors too, including a replaced _build.
function createEvidence(root) {
  const paths = [realpathSync(root)];
  for (const name of ['_build', 'local-checks', 'attempts']) paths.push(join(paths.at(-1), name));
  const identities = [];
  const ownedDirectory = path => {
    const stat = lstatSync(path);
    if (!stat.isDirectory() || stat.isSymbolicLink() || stat.uid !== process.getuid()) {
      throw new Error('EvidenceDirectoryOwnershipChanged');
    }
    return stat;
  };
  for (const [index, path] of paths.entries()) {
    if (index > 0) {
      try { mkdirSync(path); } catch (error) { if (error.code !== 'EEXIST') throw error; }
    }
    identities.push(ownedDirectory(path));
  }
  const directory = mkdtempSync(join(paths.at(-1), 'run-'));
  paths.push(directory);
  identities.push(ownedDirectory(directory));
  const files = new Map();
  function checkDirectory() {
    paths.forEach((path, index) => {
      if (!same(ownedDirectory(path), identities[index]) || realpathSync(path) !== path) {
        throw new Error('EvidenceDirectoryOwnershipChanged');
      }
    });
  }
  function write(name, value) {
    checkDirectory();
    const path = join(directory, name), previous = files.get(name);
    // Nonblocking also refuses a substituted FIFO without waiting for a reader.
    const fd = openSync(path, constants.O_WRONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK |
      (previous ? 0 : constants.O_CREAT | constants.O_EXCL), 0o600);
    try {
      const current = fstatSync(fd);
      if (!current.isFile() || current.uid !== process.getuid() || current.nlink !== 1 ||
          (previous && !same(previous, current)) || !same(lstatSync(path), current)) {
        throw new Error('EvidenceFileOwnershipChanged');
      }
      checkDirectory();
      files.set(name, current);
      ftruncateSync(fd, 0);
      writeFileSync(fd, value);
      checkDirectory();
      if (!same(lstatSync(path), current)) throw new Error('EvidenceFileOwnershipChanged');
    } finally { closeSync(fd); }
  }
  return {directory, write};
}

function noteError(error, stage) {
  summary.complete = false;
  (summary.errors ??= []).push({stage, code: error.code ?? error.message});
  if (['starting', 'running', 'passed'].includes(summary.status)) summary.status = 'guard failed';
  diagnostic(error.message);
}

function persist() {
  if (!evidence) return;
  let failure;
  try {
    const redacted = Buffer.from(redactCommandEvidence(Buffer.concat(output).toString('utf8'), env));
    if (redacted.length > COMMAND_OUTPUT_LIMIT) summary.outputComplete = outputComplete = false;
    evidence.write('output.log', redacted.subarray(0, COMMAND_OUTPUT_LIMIT));
  } catch (error) { failure = error; noteError(error, 'output'); }
  // Even if output storage failed, retain an incomplete summary when safe.
  try { evidence.write('summary.json', JSON.stringify(summary, null, 2) + '\n'); }
  catch (error) { failure ??= error; noteError(error, 'summary'); }
  if (failure) throw failure;
}

function capture(data) {
  const bytes = Buffer.from(data);
  const remaining = COMMAND_OUTPUT_LIMIT - outputBytes;
  if (remaining > 0) {
    output.push(bytes.subarray(0, remaining));
    outputBytes += Math.min(bytes.length, remaining);
  }
  if (bytes.length > remaining) {
    outputComplete = false;
    cancel('output-limit', 1);
  }
}

// macOS and Linux both expose these ps fields. A parse/visibility error never
// certifies the group empty. Zombies no longer execute or hold build handles.
function groupMembers() {
  try {
  const result = spawnSync('ps', ['-A', '-o', 'pid=', '-o', 'pgid=', '-o', 'stat='],
    {encoding: 'utf8', timeout: 2000, maxBuffer: 4 * 1024 * 1024});
  if (result.status !== 0 || result.error || result.stderr) throw new Error('Cannot inspect owned process group with ps');
  const rows = result.stdout.trim().split('\n').filter(Boolean).map(line => {
    const match = /^\s*(\d+)\s+(\d+)\s+(\S+)\s*$/u.exec(line);
    if (!match) throw new Error('Cannot parse owned process group from ps');
    return {pid: Number(match[1]), group: Number(match[2]), state: match[3]};
  });
  if (!rows.some(row => row.pid === process.pid && row.group === process.pid)) {
    throw new Error('Supervisor is not its own process-group leader');
  }
  return rows.filter(row => row.group === process.pid && row.pid !== process.pid &&
    row.pid !== result.pid && !row.state.startsWith('Z'));
  } catch (error) { retainLocks = true; throw error; }
}

async function finish(status, release) {
  if (finished) return;
  finished = true;
  status = primaryStatus || status;
  release &&= !retainLocks;
  clearTimeout(timer);
  clearTimeout(escalation);
  summary.endedAt = new Date().toISOString();
  summary.outputComplete = outputComplete;
  summary.complete = false;
  summary.exitCode = status;
  summary.locksReleased = false;
  // Do not publish completion until both evidence and required lock cleanup
  // succeeded. Cleanup failures must not replace an earlier command failure.
  try { persist(); } catch { status ||= 1; }
  try {
    if (release) {
      locks?.release();
      summary.locksReleased = true;
    }
  } catch (error) {
    noteError(error, 'lock release');
    release = false;
    status ||= 1;
  }
  if (!release || !outputComplete) status ||= 1;
  // One separate five-second delivery budget covers both streams and any
  // final evidence-error diagnostics. A stalled caller must not hold us alive.
  const flushDeadline = performance.now() + 5000;
  if (output.length) writeCaller('stdout', redactCommandEvidence(Buffer.concat(output).toString('utf8'), env));
  if (directory) diagnostic(`Local check evidence: ${directory}`);
  if (!release && locks) diagnostic('Local check locks retained; process termination or ownership is unconfirmed. Inspect the reported owner before manual recovery.');
  await flushCallerOutput(flushDeadline);
  if (recordCallerFailures()) status ||= 1;
  if (status !== 0 && summary.status === 'passed') summary.status = 'guard failed';
  summary.exitCode = status;
  summary.complete = status === 0 && release && !summary.errors?.length;
  try { persist(); } catch {
    status ||= 1;
    summary.exitCode = status;
    summary.complete = false;
    try { evidence?.write('summary.json', JSON.stringify(summary, null, 2) + '\n'); }
    catch (error) { diagnostic(error.message); }
  }
  await flushCallerOutput(flushDeadline);
  if (recordCallerFailures()) {
    status ||= 1;
    summary.exitCode = status;
    summary.complete = false;
    if (summary.status === 'passed') summary.status = 'guard failed';
    // Do not create more caller writes after the delivery budget is spent.
    try { evidence?.write('summary.json', JSON.stringify(summary, null, 2) + '\n'); }
    catch { /* Earlier evidence diagnostics are already queued or delivered. */ }
  }
  process.exit(status);
}

function cancel(reason, status = 130) {
  if (cancelling || finished) return;
  cancelling = true;
  summary.status = reason;
  clearTimeout(timer);
  diagnostic(`Local check stopped: ${reason}`);
  try { persist(); } catch (error) { diagnostic(error.message); }
  if (!groupOwned) { finish(status, true); return; }
  // Self is still the live group leader, preventing process-group PID reuse.
  process.kill(-process.pid, 'SIGTERM');
  escalation = setTimeout(() => {
    summary.status = `${reason}: SIGKILL escalation; locks retained`;
    summary.outputComplete = false;
    summary.exitCode = primaryStatus || status;
    summary.locksReleased = false;
    try { persist(); } catch (error) { diagnostic(error.message); }
    if (directory) diagnostic(`Local check evidence: ${directory}`);
    diagnostic('Killing only the owned process group; locks retained for inspection.');
    if (process.connected) process.send({terminalStatus: primaryStatus || status});
    process.kill(-process.pid, 'SIGKILL');
  }, (config?.graceSeconds ?? 5) * 1000);
  const inspect = () => {
    if (finished) return;
    try {
      if (groupMembers().length === 0 && childClosed) { finish(status, true); return; }
    } catch (error) {
      diagnostic(error.message);
      // Do not turn unknown liveness into a successful release. The bounded
      // escalation still addresses only our live, owned group.
      return;
    }
    setTimeout(inspect, 25);
  };
  inspect();
}

process.on('SIGTERM', () => cancel('interrupted'));
process.on('SIGINT', () => cancel('interrupted'));
process.on('disconnect', () => cancel('parent disconnected'));
process.on('message', async message => {
  if (message.cancel) { cancel('interrupted'); return; }
  if (config || finished || !message.config) return;
  config = message.config;
  try {
    if (!['linux', 'darwin'].includes(process.platform)) throw new Error('Local guard supports macOS and Linux only');
    durationSeconds(config.timeoutSeconds);
    durationSeconds(config.graceSeconds ?? 5, 'kill-grace-seconds');
    groupMembers();
    groupOwned = true;
    evidence = createEvidence(config.root);
    directory = evidence.directory;
    summary = {...summary, worktree: config.root, heavy: config.heavy,
      timeoutSeconds: config.timeoutSeconds, graceSeconds: config.graceSeconds ?? 5};
    locks = acquireLocalLocks({root: config.root, heavy: config.heavy, evidence: directory});
    summary.owner = locks.owner;
    summary.locks = locks.paths;
    summary.status = 'running';
    persist();
    diagnostic(`Local check budget: ${config.timeoutSeconds}s; TERM grace: ${config.graceSeconds ?? 5}s`);
    diagnostic(`Local check evidence: ${directory}`);
    timer = setTimeout(() => cancel('timeout', 124), config.timeoutSeconds * 1000);
    for (const step of config.steps) {
      if (cancelling) return;
      if (step.scratch) mkdirSync(step.scratch, {recursive: true});
      const record = {name: step.name, command: redactCommandArguments([step.command, ...step.args], env),
        startedAt: new Date().toISOString(), status: 'running', streamsComplete: false};
      summary.steps.push(record);
      persist();
      diagnostic(`== ${step.name}`);
      const result = await new Promise(resolve => {
        childClosed = false;
        child = spawn(step.command, step.args, {cwd: config.root,
          env: {...env, ...step.env}, stdio: ['ignore', 'pipe', 'pipe']});
        child.stdout.on('data', capture);
        child.stderr.on('data', capture);
        let error;
        child.on('error', problem => { error = problem.code ?? problem.message; });
        for (const [name, stream] of [['stdout', child.stdout], ['stderr', child.stderr]]) {
          stream.on('error', problem => {
            outputComplete = false;
            (record.streamErrors ??= []).push({stream: name, code: problem.code ?? problem.message});
            noteError(problem, `${name} drain`);
            cancel('output drain failed', 1);
          });
        }
        child.on('exit', (code, signal) => {
          // Descendants can keep these pipes open after the direct command
          // exits. Retain its outcome now, without claiming drained streams
          // or releasing custody of its still-live process group.
          Object.assign(record, {code, signal, exitedAt: new Date().toISOString()});
          record.status = code === 0 ? 'draining' : 'failed';
          // A later TERM-handler exit is evidence, not a replacement for an
          // already-established timeout or caller cancellation.
          if (!cancelling) {
            if (code) primaryStatus ||= code;
            else if (signal) primaryStatus ||= 1;
            if (primaryStatus) summary.status = 'failed';
          }
          try { persist(); } catch { cancel('guard failed', primaryStatus || 1); }
        });
        child.on('close', (code, signal) => {
          childClosed = true;
          record.streamsComplete = !record.streamErrors?.length &&
            child.stdout.readableEnded && child.stderr.readableEnded;
          if (!record.streamsComplete) outputComplete = false;
          resolve({code, signal, error});
        });
      });
      record.endedAt = new Date().toISOString();
      Object.assign(record, result);
      record.status = result.code === 0 && !result.error && record.streamsComplete ? 'passed' : 'failed';
      if (record.status === 'failed' && !cancelling) {
        primaryStatus ||= result.code || 1;
        summary.status = 'failed';
      }
      persist();
      if (cancelling) return;
      if (groupMembers().length > 0) { cancel('command left running descendants', primaryStatus || 1); return; }
      if (record.status === 'failed') {
        summary.status = 'failed';
        finish(result.code || 1, true);
        return;
      }
    }
    summary.status = 'passed';
    finish(0, true);
  } catch (error) {
    diagnostic(error.message);
    if (!primaryStatus) summary.status = 'guard failed';
    if (child && groupOwned) cancel(primaryStatus ? 'failed' : 'guard failed', primaryStatus || 1);
    else finish(primaryStatus || 1, true);
  }
});
