// Trusted physical Table installation boundary, not a public Effect factory.
// The caller supplies common-admitted operation/materials, current authority,
// approval and a fresh durable Ledger claim before execute. No retry is inferred
// from an absent response or receipt. All process stop facts use the existing
// managed-process owner; none are taken from an IPC acknowledgement.
import {isAbsolute} from 'node:path';
import {prepareManagedExecution, startManagedExecution} from './process-channel.mjs';
import {encodeProcessFrame} from './process-frames.mjs';

const frames = Object.freeze({maxBytes: 4 * 1024 * 1024, maxNodes: 100000, maxDepth: 32});
const preparations = new WeakMap();
const fail = code => { throw Object.assign(new Error(code), {code}); };
const snapshot = value => JSON.parse(encodeProcessFrame(value, frames).subarray(4).toString('utf8'));
const cid = value => typeof value === 'string' && /^sha256:[0-9a-f]{64}$/u.test(value);
const keys = (value, names) => value && typeof value === 'object' && !Array.isArray(value) &&
  Object.keys(value).sort().join(',') === names.slice().sort().join(',');

export function createIcebergPhysicalBridge({python, run, catalog,
  entry = new URL('../table-iceberg/process_worker.py', import.meta.url)}) {
  const config = snapshot(catalog);
  if (!(python instanceof URL) || python.protocol !== 'file:' ||
      !keys(config, ['database', 'warehouse', 'catalogCid', 'limits']) ||
      !['database', 'warehouse'].every(key => typeof config[key] === 'string' && isAbsolute(config[key])) ||
      !cid(config.catalogCid) || !keys(config.limits, ['bytes', 'files', 'operations']) ||
      Object.values(config.limits).some(value => !Number.isSafeInteger(value) || value < 1)) {
    fail('InvalidTablePhysicalConfiguration');
  }
  // Validate and snapshot interpreter/entry/run synchronously, before a durable
  // Effect send claim. Each invocation creates one fresh process preparation.
  prepareManagedExecution({runtime: python, entry, run, frames, maxRequests: 1,
    graceMs: 100, startupMs: 5000});
  const runtime = new URL(python.href), worker = new URL(entry.href);
  const configuration = () => ({runtime, entry: worker, run, frames, maxRequests: 1,
    graceMs: 100, startupMs: 5000});
  const preflight = (command, payload) => snapshot({protocol: 'actql-local-execution/0.1',
    session: '00000000-0000-0000-0000-000000000000', run,
    kind: 'execute', sequence: 1, body: {catalog: config, command, payload}});
  const invoke = async (command, payload, signal, stopped) => {
    let channel, error;
    // A bounded physical I/O wait does not certify cancellation/noncommit.
    // Deadline failure still waits for actual exit and requires reconciliation.
    const deadline = AbortSignal.timeout(60000);
    const cancellation = signal === undefined ? deadline : AbortSignal.any([signal, deadline]);
    try {
      channel = await startManagedExecution(prepareManagedExecution(configuration()), cancellation);
      return await channel.request({catalog: config, command, payload}, cancellation);
    } catch (caught) {
      error = caught;
      throw caught;
    } finally {
      // Retain physical flight until observed exit, including failed handshake,
      // cancellation and unknown replies. The existing cleanup handle performs
      // kill-and-wait where cooperative stop is impossible.
      if (channel) await channel.close();
      else if (error?.cleanupHandle) await error.cleanupHandle.retry();
      stopped?.();
    }
  };
  const own = prepared => {
    const owned = preparations.get(prepared);
    if (!owned || owned.bridge !== bridge) fail('ForeignTablePhysicalPreparation');
    return owned;
  };
  const reconcileOperation = (operation, signal) => {
    const payload = snapshot({operation});
    if (!cid(payload.operation?.request_cid)) fail('InvalidTablePhysicalPreparation');
    preflight('reconcile', payload);
    return invoke('reconcile', payload, signal);
  };
  const bridge = Object.freeze({
    prepareWrite({operation, mapping, rows, reservation}) {
      const payload = snapshot({operation, mapping, rows, reservation});
      if (!cid(payload.operation?.request_cid) || !Array.isArray(payload.rows)) {
        fail('InvalidTablePhysicalPreparation');
      }
      // Charge/validate the entire transport envelope before claiming a send,
      // including empty typed input. This is a bounded initial I/O profile, not
      // a substitute for common input admission/retention accounting.
      preflight('write', payload);
      const prepared = Object.freeze({});
      preparations.set(prepared, {bridge, payload, attempted: false, stopped: false});
      return prepared;
    },
    async execute(prepared, {useCid, signal} = {}) {
      const owned = own(prepared);
      if (!cid(useCid)) fail('InvalidTableCredentialUse');
      signal?.throwIfAborted();
      if (owned.attempted) fail('TablePhysicalReconcileOnly');
      owned.attempted = true;
      const result = await invoke('write', owned.payload, signal, () => { owned.stopped = true; });
      if (typeof result?.ok !== 'boolean' || !keys(result, result.ok ? ['ok', 'result'] : ['ok', 'code']) ||
          (!result.ok && typeof result.code !== 'string')) fail('InvalidTablePhysicalReply');
      return Object.freeze({observation: Object.freeze({useCid,
        statusCode: result.ok ? 200 : 409,
        body: Buffer.from(JSON.stringify(result))})});
    },
    async reconcile(prepared, signal) {
      const owned = own(prepared);
      return reconcileOperation(owned.payload.operation, signal);
    },
    // Recovery needs the original sealed operation, not live input, a new
    // writer preparation or recreated payload. Caller owns evidence authority.
    reconcileOperation,
    async inspect(prepared, signal) {
      const owned = own(prepared);
      const payload = {operation: owned.payload.operation};
      preflight('inspect', payload);
      return invoke('inspect', payload, signal);
    },
    async cleanup(prepared, signal) {
      const owned = own(prepared);
      if (!owned.attempted || !owned.stopped) fail('TableWriterNotStopped');
      // The Catalog checks original-operation publication and fences commit in
      // the same transaction before deleting only this operation's staged files.
      return invoke('cleanup', {operation: owned.payload.operation}, signal);
    },
    async read(receipt, mapping, signal) {
      const payload = snapshot({receipt, mapping});
      preflight('read', payload);
      return invoke('read', payload, signal);
    },
    status(prepared) {
      const owned = own(prepared);
      return Object.freeze({attempted: owned.attempted, stopped: owned.stopped});
    },
  });
  return bridge;
}
