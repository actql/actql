// Observe the same live child after its close handshake, before acknowledging
// the completed observation or judging that child's exit.
import assert from 'node:assert/strict';
import {spawn, spawnSync} from 'node:child_process';
import {lstat, readdir, readlink} from 'node:fs/promises';
import {join, sep} from 'node:path';
import type {ChildProcess} from 'node:child_process';

type RunningChild = Pick<ChildProcess, 'pid' | 'exitCode' | 'signalCode'>;
type Completion = {code: number | null; signal: NodeJS.Signals | null; endedAt: string};
type NativeInstallRecord = {
  command: string; args: readonly string[]; pid: number | null; startedAt: string;
  stdout: string; stderr: string; terminationReason?: 'original-child-timeout' | 'output-limit';
  stdinFailure?: string; spawnFailure?: string; closeObservationFailure?: string;
  closeObservationAcknowledged?: boolean; close?: Awaited<ReturnType<typeof observeChildFds>>;
};
type CloseMessage = {stage?: string; pid?: number; clientCloseReturned?: boolean; hostCloseReturned?: boolean};

export async function observeChildFds(child: RunningChild, state: string) {
  assert.equal(child.exitCode, null); assert.equal(child.signalCode, null);
  const original = await lstat(state); assert(original.isDirectory() && !original.isSymbolicLink());
  if (process.platform === 'darwin') {
    const args = ['-nP', '-a', '-p', String(child.pid), '+D', state, '-F', 'pfn'];
    const result = spawnSync('/usr/sbin/lsof', args, {encoding: 'utf8', timeout: 10_000, maxBuffer: 1024 * 1024});
    assert(result.status === 1 && result.stdout === '' && result.stderr === '' && !result.error,
      'Original still-live Python child has unavailable/nonempty scoped descriptor observation');
    assert.equal(child.exitCode, null); assert.equal(child.signalCode, null);
    return {pid: child.pid, aliveAfterClose: true, scopedStateFd0: true, command: ['/usr/sbin/lsof', ...args],
      exitCode: result.status, stdout: result.stdout, stderr: result.stderr};
  }
  // A future genuine Linux supplier still uses this own-child observation;
  // this branch cannot make the current macOS-only runtime accepted on Linux.
  assert.equal(process.platform, 'linux');
  const fdRoot = `/proc/${child.pid}/fd`, descriptors = await readdir(fdRoot); assert(descriptors.length <= 4096);
  const scoped = [];
  for (const fd of descriptors) {
    let target;
    try {target = await readlink(join(fdRoot, fd));}
    catch (failure) {if ((failure as NodeJS.ErrnoException).code === 'ENOENT') continue; throw failure;}
    const path = target.replace(/ \(deleted\)$/u, '');
    if (path === state || path.startsWith(`${state}${sep}`)) scoped.push({fd, target});
  }
  assert.deepEqual(scoped, []); assert.equal(child.exitCode, null); assert.equal(child.signalCode, null);
  return {pid: child.pid, aliveAfterClose: true, scopedStateFd0: true, descriptorCount: descriptors.length};
}

export async function runNativeInstallCommand(command: string, args: readonly string[],
  {cwd, env, state, expectedCode = 0, expectedError}: {
    cwd?: string; env?: NodeJS.ProcessEnv; state?: string; expectedCode?: number; expectedError?: string;
  } = {}) {
  let observation = Promise.resolve(), childRecord!: NativeInstallRecord;
  await new Promise<void>((resolveRun, rejectRun) => {
    const child = spawn(command, args, {cwd, env, stdio: ['pipe', 'pipe', 'pipe']});
    childRecord = {command, args, pid: child.pid ?? null, startedAt: new Date().toISOString(), stdout: '', stderr: ''};
    let bytes = 0, lines = '', observing = false;
    const timer = setTimeout(() => {childRecord.terminationReason = 'original-child-timeout'; child.kill('SIGTERM');}, 180_000);
    child.stdin.on('error', failure => {childRecord.stdinFailure = (failure as NodeJS.ErrnoException).code;});
    child.on('error', failure => {childRecord.spawnFailure = (failure as NodeJS.ErrnoException).code;});
    const output = (chunk: Buffer, error: boolean) => {
      bytes += chunk.length;
      if (bytes > 8 * 1024 * 1024) {childRecord.terminationReason = 'output-limit'; child.kill('SIGTERM'); return;}
      if (error) {childRecord.stderr += chunk; return;}
      childRecord.stdout += chunk; lines += chunk;
      let end;
      while ((end = lines.indexOf('\n')) !== -1) {
        const line = lines.slice(0, end); lines = lines.slice(end + 1);
        if (!state) continue;
        let body: CloseMessage; try {body = JSON.parse(line) as CloseMessage;} catch {continue;}
        if (body.stage === 'close-observation-ack') {childRecord.closeObservationAcknowledged = body.pid === child.pid; continue;}
        if (body.stage !== 'closed' || observing) continue;
        observing = true;
        observation = (async () => {
          assert.equal(body.pid, child.pid); assert.equal(body.clientCloseReturned, true); assert.equal(body.hostCloseReturned, true);
          childRecord.close = await observeChildFds(child, state); child.stdin.end('observed\n');
        })().catch((failure: unknown) => {childRecord.closeObservationFailure = (failure as Error).message; child.stdin.end('unobserved\n');});
      }
    };
    child.stdout.on('data', chunk => output(chunk, false)); child.stderr.on('data', chunk => output(chunk, true));
    child.once('close', async (code, signal) => {
      clearTimeout(timer); await observation;
      Object.assign(childRecord, {code, signal, endedAt: new Date().toISOString()});
      try {
        if (expectedError !== undefined) {assert.equal(childRecord.spawnFailure, expectedError); assert.notEqual(code, 0); assert.equal(signal, null);}
        else {assert.equal(code, expectedCode, childRecord.stderr); assert.equal(signal, null); assert(!childRecord.spawnFailure);}
        assert(!childRecord.terminationReason);
        if (state) {
          assert.equal(childRecord.close?.scopedStateFd0, true); assert.equal(childRecord.closeObservationAcknowledged, true);
          assert(!childRecord.closeObservationFailure && !childRecord.stdinFailure);
        }
        resolveRun();
      } catch (failure) {(failure as {commandRecord: NativeInstallRecord}).commandRecord = childRecord; rejectRun(failure);}
    });
    if (!state) child.stdin.end();
  });
  return childRecord as NativeInstallRecord & Completion;
}
