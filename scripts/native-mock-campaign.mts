// One retained original Native Mock fixture process, with one pending iteration.
// This is not a worker pool or a portable preparation/acceptance authority.
import assert from 'node:assert/strict';
import {fork} from 'node:child_process';
import type {Writable} from 'node:stream';

type CloseStatus = {code: number | null; signal: NodeJS.Signals | null};
type CampaignFailure = NodeJS.ErrnoException & {stopIssue?: string; stdout?: string; stderr?: string;
  status?: CloseStatus['code']; signal?: CloseStatus['signal']};
type IterationOutput = {status: CloseStatus['code']; signal: CloseStatus['signal']; stdout: string; stderr: string} &
  ({receiptFile: string; error?: never} | {receiptFile?: never; error: CampaignFailure});
type Pending = {iteration: number; sent: boolean; timer: NodeJS.Timeout; resolve: (result: IterationOutput) => void};
type CampaignOptions = {script: string; directory: string; count: number; cwd: string;
  timeoutMs?: number; killGraceMs?: number; env?: NodeJS.ProcessEnv};
type WorkerMessage = {type: 'ready'} | {type: 'completed'; iteration: number; receiptFile: string};
type ParentMessage = {type: 'iteration'; iteration: number};
type Consume = (iteration: number, run: () => string | Promise<string>) => Promise<void>;
type Waiting = {resolve: () => void; reject: (error: unknown) => void};

const MAX_OUTPUT = 8 * 1024 ** 2;

export function openNativeMockCampaign({script, directory, count, cwd,
  timeoutMs = 240000, killGraceMs = 5000, env = process.env}: CampaignOptions) {
  assert(Number.isSafeInteger(count) && count > 0 && count <= 30);
  assert(Number.isSafeInteger(timeoutMs) && timeoutMs > 0);
  assert(Number.isSafeInteger(killGraceMs) && killGraceMs > 0);
  const child = fork(script, [directory, '--campaign-worker', String(count)], {
    cwd, env: {...env, ACTQL_CI_NATIVE_RELEASE_PHASES: '1'}, execArgv: [],
    detached: true, stdio: ['ignore', 'pipe', 'pipe', 'ipc'],
  });
  let ready = false, next = 0, pending: Pending | undefined, failure: CampaignFailure | undefined,
    stopping = false, closed: CloseStatus | undefined, escalation: NodeJS.Timeout | undefined;
  let stdout: Buffer[] = [], stderr: Buffer[] = [], outputBytes = 0;
  let resolveClosed!: (status: CloseStatus) => void;
  const closure = new Promise<CloseStatus>(resolve => {resolveClosed = resolve;});
  const stop = (error: CampaignFailure) => {
    failure ??= error;
    if (stopping || closed) return;
    stopping = true;
    const signal = (name: NodeJS.Signals) => {
      if (Number.isInteger(child.pid) && child.pid! > 0) {
        try {process.kill(-child.pid!, name);}
        catch (issue) {if ((issue as NodeJS.ErrnoException).code !== 'ESRCH') failure!.stopIssue ??= (issue as NodeJS.ErrnoException).code;}
      }
    };
    // Independent parent timer remains live while synchronous Source checking
    // blocks the fixture. SIGTERM first lets its existing Native command owner
    // stop/join a detached command group; escalation is bounded independently.
    signal('SIGTERM');
    escalation = setTimeout(() => signal('SIGKILL'), killGraceMs);
  };
  const onTerm = () => stop(Object.assign(new Error('Native Mock campaign interrupted'), {code: 'ECANCELED'}));
  process.once('SIGTERM', onTerm); process.once('SIGINT', onTerm);
  const capture = (target: Buffer[], chunk: Buffer) => {
    const remaining = MAX_OUTPUT - outputBytes;
    if (remaining > 0) target.push(chunk.subarray(0, remaining));
    outputBytes += chunk.length;
    if (outputBytes > MAX_OUTPUT) stop(Object.assign(new Error('Native Mock campaign output limit exceeded'),
      {code: 'ERR_CHILD_PROCESS_STDIO_MAXBUFFER'}));
  };
  child.stdout!.on('data', chunk => capture(stdout, chunk));
  child.stderr!.on('data', chunk => capture(stderr, chunk));
  child.stdout!.once('error', stop); child.stderr!.once('error', stop);
  const send = () => {
    if (ready && pending && !pending.sent && !failure) {
      pending.sent = true;
      child.send({type: 'iteration', iteration: pending.iteration}, error => {if (error) stop(error);});
    }
  };
  child.on('message', (message: WorkerMessage) => {
    try {
      assert(message && typeof message === 'object' && !Array.isArray(message));
      if (message.type === 'ready') {
        assert.deepEqual(Object.keys(message), ['type']);
        assert(!ready && next === 0, 'Duplicate Native Mock ready');
        ready = true; send();
      } else {
        assert.deepEqual(Object.keys(message).sort(), ['iteration', 'receiptFile', 'type']);
        assert.equal(message.type, 'completed');
        assert(pending?.sent && !failure, 'Unrequested or late Native Mock completion');
        assert.equal(message.iteration, pending.iteration, 'Foreign Native Mock iteration');
        assert.equal(typeof message.receiptFile, 'string');
        assert(message.receiptFile.length > 0 && message.receiptFile.length <= 4096);
        const original = pending;
        clearTimeout(original.timer); pending = undefined; next++;
        original.resolve({status: 0, signal: null, receiptFile: message.receiptFile,
          stdout: Buffer.concat(stdout).toString('utf8'), stderr: Buffer.concat(stderr).toString('utf8')});
      }
    } catch (error) {stop(error as CampaignFailure);}
  });
  child.once('error', stop);
  child.once('close', (code, signal) => {
    closed = {code, signal};
    clearTimeout(escalation);
    process.removeListener('SIGTERM', onTerm); process.removeListener('SIGINT', onTerm);
    if (code !== 0 || signal || next !== count) failure ??= new Error('Original Native Mock fixture did not complete its campaign');
    if (pending) {
      clearTimeout(pending.timer);
      pending.resolve({status: code, signal, error: failure ?? new Error('Native Mock completion missing'),
        stdout: Buffer.concat(stdout).toString('utf8'), stderr: Buffer.concat(stderr).toString('utf8')});
      pending = undefined;
    }
    resolveClosed(closed);
  });
  return Object.freeze({
    async run(iteration: number) {
      assert(!pending && !closed && !failure && iteration === next && next < count,
        'Closed, overlapping or replayed Native Mock iteration');
      if (next > 0) {stdout = []; stderr = []; outputBytes = 0;}
      return new Promise<IterationOutput>(resolve => {
        pending = {iteration, resolve, sent: false,
          timer: setTimeout(() => stop(Object.assign(new Error('Original Native Mock iteration timed out'),
            {code: 'ETIMEDOUT'})), timeoutMs)};
        send();
      });
    },
    async close() {
      if (!closed && next < count) stop(new Error('Native Mock campaign ended before the original population'));
      // Do not let an unconfirmed final process/IPC close wait forever after
      // the last receipt. The same external bound still applies to retirement.
      const timer = setTimeout(() => stop(new Error('Native Mock fixture close did not confirm')), timeoutMs);
      try {await closure;} finally {clearTimeout(timer);}
      if (failure) {
        // A failure after the final completion still owns its original output;
        // do not reduce it to a generic process-close message in the report.
        failure.stdout ??= Buffer.concat(stdout).toString('utf8');
        failure.stderr ??= Buffer.concat(stderr).toString('utf8');
        failure.status ??= closed!.code; failure.signal ??= closed!.signal;
        throw failure;
      }
      return closed!;
    },
  });
}

// The original fixture alone calls its action and emits completion after the
// same registry and scratch owners have closed. Parent messages select only an
// ordered iteration, never manifests, subjects, verifier results or commands.
export async function serveNativeMockCampaign(count: number, action: (consume: Consume) => void | Promise<void>) {
  assert.equal(typeof process.send, 'function', 'Native Mock campaign requires its original IPC parent');
  let next = 0, waiting: Waiting | undefined, queued: boolean | undefined, busy = false, failure: unknown;
  const fail = (error: unknown) => {
    failure ??= error;
    if (waiting) {waiting.reject(failure); waiting = undefined;}
    if (process.listenerCount('SIGTERM')) process.emit('SIGTERM');
  };
  const onMessage = (message: ParentMessage) => {
    try {
      assert(message && typeof message === 'object' && !Array.isArray(message));
      assert.deepEqual(Object.keys(message).sort(), ['iteration', 'type']);
      assert.equal(message.type, 'iteration');
      assert(!busy && !queued && message.iteration === next && next < count,
        'Unrequested, overlapping or replayed Native Mock iteration');
      if (waiting) {const original = waiting; waiting = undefined; original.resolve();}
      else queued = true;
    } catch (error) {fail(error);}
  };
  const onDisconnect = () => {
    fail(new Error('Original Native Mock campaign parent disconnected'));
    // This fixture was forked as its own group. Stop inherited npm/generator
    // children too, while the existing observer stops detached Native groups.
    try {process.kill(-process.pid, 'SIGTERM');}
    catch (error) {if ((error as NodeJS.ErrnoException).code !== 'ESRCH') throw error;}
  };
  process.on('message', onMessage); process.once('disconnect', onDisconnect);
  const send = (message: WorkerMessage) => new Promise<void>((resolve, reject) => process.send!(message, error => error ? reject(error) : resolve()));
  const drain = (stream: Writable) => new Promise<void>((resolve, reject) => stream.write('', error => error ? reject(error) : resolve()));
  try {
    await send({type: 'ready'});
    await action(async (iteration, run) => {
      assert.equal(iteration, next);
      if (!queued) await new Promise<void>((resolve, reject) => {waiting = {resolve, reject};});
      queued = false;
      if (failure) throw failure;
      busy = true;
      const receiptFile = await run();
      if (failure) throw failure;
      await drain(process.stdout); await drain(process.stderr);
      await send({type: 'completed', iteration, receiptFile});
      busy = false; next++;
    });
    if (failure) throw failure;
    assert.equal(next, count, 'Missing original Native Mock iteration');
  } finally {
    process.removeListener('message', onMessage); process.removeListener('disconnect', onDisconnect);
    if (process.connected) process.disconnect();
  }
}
