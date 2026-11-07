// Fixture process ownership only. Product Hosts retain their normal policies.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createHash} from 'node:crypto';
import {readFile, realpath, stat} from 'node:fs/promises';
import {resolve} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {Worker, isMainThread, parentPort, workerData} from 'node:worker_threads';

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

// This is a test-only observer of the already installed original ingress. It
// starts immediately before one named refusal; no runtime bytes are changed.
// Missing diagnostic evidence never replaces the original acceptance result.
export async function observePackedSubmissionCause({sourceURL, report = value => {
  process.stderr.write(`Packed submission original cause: ${JSON.stringify(value)}\n`);
}}) {
  const observations = [];
  let worker, exited, closing, ready, loaded = false, observationFailed = false;
  const emit = value => {try {report(value);} catch { /* Preserve the original test outcome. */ }};
  const unavailable = () => Object.freeze({close: async () => {
    if (!closing) closing = Promise.resolve().then(() => emit({available: false}));
    await closing;
  }});
  try {
    assert.equal(sourceURL.protocol, 'file:');
    assert.equal(sourceURL.search + sourceURL.hash, '');
    const path = await realpath(fileURLToPath(sourceURL)), metadata = await stat(path);
    assert.ok(metadata.isFile() && metadata.size > 0 && metadata.size <= 128 * 1024);
    const bytes = await readFile(path), source = bytes.toString('utf8');
    assert.equal(bytes.length, metadata.size);
    const catches = source.split('\n').flatMap((line, index) =>
      line.trim() === 'throw publicFailure(error);' ? [index] : []);
    assert.equal(catches.length, 2, 'separate Result and generic ingress catches');
    const sha256 = createHash('sha256').update(bytes).digest('hex');
    worker = new Worker(new URL(import.meta.url), {execArgv: [], workerData: {
      kind: 'packed-submission-cause', url: pathToFileURL(path).href,
      sha256, lineNumber: catches[1]}});
    exited = new Promise(resolve => worker.once('exit', resolve));
    ready = new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('DiagnosticStartupUnavailable')), 3000);
      worker.on('error', error => {observationFailed = true; reject(error);});
      worker.on('message', value => {
        if (value.kind === 'loaded') loaded = true;
        if (value.kind === 'primary') observations.push(value.types);
        if (value.kind === 'ready') {clearTimeout(timer); resolve();}
        if (value.kind === 'unavailable') {
          observationFailed = true; clearTimeout(timer); reject(new Error('DiagnosticUnavailable'));
        }
      });
      exited.then(() => {clearTimeout(timer); reject(new Error('DiagnosticExited'));});
    });
    await ready;
    return Object.freeze({close() {
      closing ??= (async () => {
        let stopped = false;
        try {
          worker.postMessage({kind: 'close'});
          await Promise.race([exited, new Promise((_, reject) => {
            const timer = setTimeout(() => reject(new Error('DiagnosticCleanupUnavailable')), 3000);
            exited.then(() => clearTimeout(timer));
          })]);
          stopped = true;
        } catch { /* Terminate only this observer, never the original Host. */ }
        finally {await worker.terminate().catch(() => {});}
        emit({available: loaded && stopped && !observationFailed, sourceSha256: sha256,
          zeroBasedLine: catches[1], originalCauseTypes: observations});
      })();
      return closing;
    }});
  } catch {
    await worker?.terminate().catch(() => {});
    return unavailable();
  }
}

async function runSubmissionCauseObserver() {
  const {Session} = await import('node:inspector');
  const session = new Session();
  session.connectToMainThread();
  const post = (method, params = {}) => new Promise((resolve, reject) =>
    session.post(method, params, (error, value) => error ? reject(error) : resolve(value)));
  // Inspector callbacks alone do not keep a Worker alive during startup.
  const alive = setInterval(() => {}, 1000);
  const originals = new Set();
  let breakpoint, captured = false;
  // Emit only fixed categories and explicitly listed codes. Even a plausible
  // private code prefix or forged compiled constructor name is not evidence.
  const expression = `(()=>{const out=[],queue=[['original',error,0]],seen=new Set();
while(queue.length&&out.length<32){const [edge,value,depth]=queue.shift();
if(value===null||typeof value!=='object'||seen.has(value))continue;seen.add(value);
const proto=Object.getPrototypeOf(value);
const ctor=proto&&Object.getOwnPropertyDescriptor(proto,'constructor')?.value;
const name=typeof ctor==='function'?Object.getOwnPropertyDescriptor(ctor,'name')?.value:'';
const type=['Object','Array','Error','TypeError','RangeError','SyntaxError','ClientError','DOMException'].includes(name)?name:typeof name==='string'&&/^_M[A-Za-z0-9_]{1,157}$/.test(name)?'MoonBit':'Other';
const safeCodes=[
'ENOENT','EACCES','EPERM','EIO','EBUSY','ENOMEM','ENOSPC','EMFILE','EEXIST','ENOTDIR','EISDIR','EBADF',
'ERR_SQLITE_ERROR','ERR_INVALID_STATE','ERR_BUFFER_TOO_LARGE','ERR_OUT_OF_RANGE','ERR_INVALID_ARG_TYPE',
'ClientOperationUnavailable','ClientPreparedSubmissionUnavailable','ClientProgramPreparationFailure',
'ClientProgramRejected','ClientProgramUnsupported','ClientProgramInvalidInput','ClientProgramImplementationLimit',
'ClientProgramAnalysisLimit','ClientRequestLookupDenied','ClientSubmissionUnresolvable','ClientSubmittedIntentConflict',
'InvalidClientHostSubmissionLookup','InvalidClientHostSubmissionOutcome','InvalidClientProgramPreparationInstallation',
'InvalidClientRequest','InvalidClientSubmissionAttempt','InvalidClientSubmissionInstallation','InvalidClientSubmittedIntent',
'InvalidHostRuntimeResult','InvalidLocalValuesRowLimit','NodeLocalPreparationAdmissionUnavailable',
'PreparationCapacityExceeded','SourceManagedPreparationUnavailable','StaleClientProgramErrorProjection','SubmissionAttemptRejected',
'ClientSubmittedIntentCustodyLost','ClientSubmittedIntentCapacity','ClientSubmittedIntentCorrupt',
'ClientRequestJournalInspectionUnavailable','ClientRequestJournalSqlUnavailable','ClientRequestJournalSqlCleanupPending',
'SqliteSchemaPreparationUnavailable','UnknownClientRequestJournalFormat','ClientSubmissionEpochExpired',
'ClientSubmissionEpochNotYetValid','ForeignRequestOriginal'];
const row={edge,type},code=Object.getOwnPropertyDescriptor(value,'code');if(code){if('value'in code&&safeCodes.includes(code.value))row.code=code.value;else row.codeOmitted=true;}
out.push(row);if(depth<16)for(const key of ['cause','primaryFailure','_0','_1','_2']){const d=Object.getOwnPropertyDescriptor(value,key);if(d&&'value'in d)queue.push([key,d.value,depth+1]);}}return out;})()`;
  session.on('Debugger.scriptParsed', async ({params}) => {
    if (params.url !== workerData.url) return;
    try {
      const {scriptSource} = await post('Debugger.getScriptSource', {scriptId: params.scriptId});
      assert.equal(createHash('sha256').update(scriptSource).digest('hex'), workerData.sha256);
      originals.add(params.scriptId);
      parentPort.postMessage({kind: 'loaded'});
    } catch {parentPort.postMessage({kind: 'unavailable'});}
  });
  session.on('Debugger.paused', async ({params}) => {
    try {
      assert.ok(!captured && originals.has(params.callFrames[0].location.scriptId));
      captured = true;
      const {result, exceptionDetails} = await post('Debugger.evaluateOnCallFrame', {
        callFrameId: params.callFrames[0].callFrameId, expression,
        returnByValue: true, silent: true});
      assert.equal(exceptionDetails, undefined);
      parentPort.postMessage({kind: 'primary', types: result.value});
    } catch {parentPort.postMessage({kind: 'unavailable'});}
    finally {
      await post('Debugger.removeBreakpoint', {breakpointId: breakpoint}).catch(() => {});
      await post('Debugger.resume').catch(() => session.disconnect());
    }
  });
  parentPort.on('message', async value => {
    if (value.kind !== 'close') return;
    try {await post('Debugger.disable');}
    finally {session.disconnect(); clearInterval(alive); parentPort.close();}
  });
  try {
    await post('Debugger.enable');
    ({breakpointId: breakpoint} = await post('Debugger.setBreakpointByUrl', {
      url: workerData.url, lineNumber: workerData.lineNumber, columnNumber: 0}));
    parentPort.postMessage({kind: 'ready'});
  } catch {parentPort.postMessage({kind: 'unavailable'});}
}

if (!isMainThread && workerData?.kind === 'packed-submission-cause') {
  await runSubmissionCauseObserver();
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
