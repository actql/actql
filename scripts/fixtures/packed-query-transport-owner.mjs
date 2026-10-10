// Fixture process ownership only. Product Hosts retain their normal policies.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {resolve} from 'node:path';

export const acceptanceTimeoutMs = 900_000;
export const acceptanceOutputBytes = 8 * 1024 * 1024;
export const transportModes = Object.freeze(['local', 'remote']);
let currentWorker;
export function sourceFixturePaths(mode, profile, directory = process.cwd()) {
  assert.ok(mode === undefined || ['local', 'remote', 'tail'].includes(mode));
  const profileSuffix = profile === 'standard' ? '' : `-${profile}`;
  const transportSuffix = mode === 'remote' || mode === 'tail' ? `-${mode}` : '';
  return Object.freeze({
    database: resolve(directory, `records${profileSuffix}${transportSuffix}.duckdb`),
    sourceProfilePath: resolve(directory, `source-profile${profileSuffix}${transportSuffix}.json`),
  });
}

export function requireCompleteInventory(expected, completed) {
  assert.ok(Array.isArray(expected) && Array.isArray(completed));
  assert.ok(expected.every(value => typeof value === 'string'));
  assert.equal(new Set(expected).size, expected.length, 'duplicate authored case');
  assert.equal(new Set(completed).size, completed.length, 'duplicate completed case');
  assert.deepEqual(completed, expected, 'missing, extra or reordered case');
}

// Parent death must not leave a live fixture Host behind. Cancellation otherwise
// stops before the next case; the original case finally blocks retain cleanup.
export function ownTransportWorker() {
  assert.equal(typeof process.send, 'function', 'worker requires an owned IPC parent');
  assert.equal(process.connected, true, 'worker parent must still be connected');
  assert.equal(currentWorker, undefined, 'one fixture cleanup authority per worker');
  let cancelled = false;
  const cancel = message => {
    if (message?.type === 'cancel-packed-query') cancelled = true;
  };
  const disconnected = () => process.exit(1);
  process.on('message', cancel);
  process.on('disconnect', disconnected);
  currentWorker = Object.freeze({
    check() { if (cancelled) throw new Error('PackedQuerySiblingCancelled'); },
    release() {
      process.removeListener('message', cancel);
      process.removeListener('disconnect', disconnected);
      if (process.connected) process.disconnect();
    },
  });
  return currentWorker;
}
export function transportWorker() {
  assert.ok(currentWorker, 'transport entry must install parent-death ownership before product imports');
  return currentWorker;
}

// Both transports and the serial tail use this one absolute deadline and one
// output allowance. No child creates a fresh acceptance budget or process group.
export function createTransportOwner({deadline, env = process.env, timeoutMs = acceptanceTimeoutMs,
  outputLimit = acceptanceOutputBytes, forward = (name, bytes) => process[name].write(bytes)}) {
  assert.ok(Number.isSafeInteger(deadline) && deadline > Date.now());
  assert.ok(Number.isSafeInteger(timeoutMs) && timeoutMs > 0 && timeoutMs <= acceptanceTimeoutMs);
  assert.ok(deadline - Date.now() <= timeoutMs);
  assert.ok(Number.isSafeInteger(outputLimit) && outputLimit > 0 &&
    outputLimit <= acceptanceOutputBytes);
  let outputBytes = 0, primary, closed = false;
  const live = new Set(), receipts = [];
  let escalation;
  const fail = error => {
    primary ??= error;
    for (const owned of live) {
      if (owned.child.connected) {
        try { owned.child.send({type: 'cancel-packed-query'}, () => {}); }
        catch { /* The same owned handle is still joined and has a bounded kill. */ }
      }
    }
    escalation ??= setTimeout(() => {
      for (const owned of live) owned.child.kill('SIGKILL');
    }, Math.max(0, Math.min(5000, deadline - Date.now())));
  };
  const expired = setTimeout(() => {
    primary ??= new Error('PackedQueryAcceptanceDeadline');
    for (const owned of live) owned.child.kill('SIGKILL');
  }, Math.max(0, deadline - Date.now()));
  const interrupted = signal => fail(new Error(`PackedQueryInterrupted:${signal}`));
  const sigint = () => interrupted('SIGINT'), sigterm = () => interrupted('SIGTERM');
  process.on('SIGINT', sigint);
  process.on('SIGTERM', sigterm);
  async function run(commands) {
    assert.ok(!closed && !primary);
    assert.ok(Array.isArray(commands) && commands.length >= 1 && commands.length <= 2);
    assert.equal(live.size, 0, 'one transport batch at a time');
    if (Date.now() >= deadline) throw new Error('PackedQueryAcceptanceDeadline');
    const flights = commands.map(({name, command = process.execPath, args, cwd,
      environment = {}}) => new Promise(resolve => {
      if (primary) { resolve(); return; }
      let child;
      const receipt = {name, startedAt: new Date().toISOString(), endedAt: null,
        pid: null, status: null, signal: null, error: null, terminal: false};
      receipts.push(receipt);
      try {
        child = spawn(command, args, {cwd, env: {...env, ...environment},
          detached: false, stdio: ['ignore', 'pipe', 'pipe', 'ipc']});
      } catch (error) {
        receipt.error = error.code ?? error.message;
        receipt.terminal = true;
        receipt.endedAt = new Date().toISOString();
        fail(error); resolve(); return;
      }
      const owned = {child, receipt};
      receipt.pid = child.pid ?? null;
      live.add(owned);
      for (const name of ['stdout', 'stderr']) child[name].on('data', bytes => {
        outputBytes += bytes.length;
        if (outputBytes > outputLimit) {
          fail(new Error('PackedQueryAggregateOutputLimit')); return;
        }
        try { forward(name, bytes); } catch (error) { fail(error); }
      });
      child.once('error', error => {
        receipt.error = error.code ?? error.message;
        fail(error);
      });
      child.once('exit', (code, signal) => {
        if (code !== 0 || signal !== null) fail(new Error(`PackedQueryWorkerFailed:${name}`));
      });
      child.once('close', (status, signal) => {
        Object.assign(receipt, {status, signal, endedAt: new Date().toISOString(), terminal: true});
        live.delete(owned);
        resolve();
      });
    }));
    await Promise.all(flights);
    if (primary) throw primary;
    assert.ok(receipts.every(receipt => receipt.terminal));
  }
  return Object.freeze({run,
    check() {
      if (primary) throw primary;
      if (Date.now() >= deadline) throw new Error('PackedQueryAcceptanceDeadline');
    },
    report: () => ({deadline, timeoutMs, workerOutputBytes: outputBytes, outputLimit,
      primaryError: primary?.message ?? null, liveChildren: live.size,
      children: receipts.map(receipt => ({...receipt}))}),
    close() {
      assert.equal(live.size, 0, 'all owned workers must settle before release');
      closed = true;
      clearTimeout(expired); clearTimeout(escalation);
      process.removeListener('SIGINT', sigint); process.removeListener('SIGTERM', sigterm);
    },
  });
}
