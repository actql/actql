// Local Host storage port for continuation evidence.
//
// Captured operator inputs, the invocation request, the prepared invocation,
// the review projection and the continuation record are private evidence.
// They are held as encrypted objects in the Local publication Store under the
// `local-continuation-private` holding namespace; this port never writes their
// plaintext. It owns only Host concerns: the installation key file, the
// per-continuation retention ledger and the retirement decision. Encryption,
// physical holdings, sharing and retryable deletion belong to the Store.
//
// Retention is explicit. A continuation's holdings stay while its preparation
// waits, resumes, has an unfinished Run or is unknown to the journal. A
// terminal Run exit, or a rejected, cancelled, expired or invalidated
// preparation, permits retirement of its captured inputs, prepared invocation,
// review projections and continuation records. The invocation request is the
// preparation's identity (a later `resume` or `status` of the same attempt
// still answers from it) and is retained with the journal row. There is no
// time-based deletion. Key rotation is out of scope: the ledger records the
// key id of every holding and a different installation key is refused before
// any decryption.
import {createHash, randomBytes, randomUUID} from 'node:crypto';
import {mkdir, open as openFile, readFile, readdir, rename, stat} from
  'node:fs/promises';
import {dirname, join} from 'node:path';
import {openLocalPublicationStore} from '../store-local/publication-store.mjs';

export const PRIVATE_EVIDENCE_KEY_FILE = 'private-evidence.key';
const LEDGER_VERSION = 'actql-local-continuation-retention/0.1';
const HOLDING_VERSION = 'actql-local-continuation-holding/0.1';
const NAMESPACE = 'local-continuation-private';
const NAMES = Object.freeze(['captured_input', 'invocation_request',
  'prepared_invocation', 'review_projection', 'continuation_record']);
// Terminal Run statuses. `needs_reconciliation` keeps its evidence.
const TERMINAL_RUNS = Object.freeze(['succeeded', 'failed', 'cancelled']);
const ATTEMPT = /^[A-Za-z0-9._:-]{1,128}$/u;

const fail = (code, cause) => {
  throw Object.assign(new Error(code, {cause}), {code});
};
const cidOf = bytes =>
  `sha256:${createHash('sha256').update(bytes).digest('hex')}`;

async function durableWrite(path, bytes, mode = 0o600) {
  await mkdir(dirname(path), {recursive: true, mode: 0o700});
  const temporary = `${path}.${process.pid}.${randomUUID()}.tmp`;
  const handle = await openFile(temporary, 'wx', mode);
  try {
    await handle.writeFile(bytes);
    await handle.sync();
  } finally { await handle.close(); }
  await rename(temporary, path);
  const directory = await openFile(dirname(path), 'r');
  try { await directory.sync(); } finally { await directory.close(); }
}

// Installation key setup (Host work): one random 32-byte key, owner-only.
export async function createPrivateEvidenceKey(stateDirectory) {
  await mkdir(stateDirectory, {recursive: true, mode: 0o700});
  const path = join(stateDirectory, PRIVATE_EVIDENCE_KEY_FILE);
  const key = randomBytes(32);
  try {
    const handle = await openFile(path, 'wx', 0o600);
    try {
      await handle.writeFile(key);
      await handle.sync();
    } finally { await handle.close(); }
  } finally { key.fill(0); }
  const directory = await openFile(stateDirectory, 'r');
  try { await directory.sync(); } finally { await directory.close(); }
  return path;
}

// The key and its id (`sha256:` over the key bytes). The id identifies the
// key generation; it never reveals the key.
export async function loadPrivateEvidenceKey(stateDirectory) {
  const path = join(stateDirectory, PRIVATE_EVIDENCE_KEY_FILE);
  let key;
  try {
    const info = await stat(path);
    if (!info.isFile() || (info.mode & 0o077) !== 0) {
      fail('PrivateEvidenceKeyExposed');
    }
    key = await readFile(path);
  } catch (error) {
    if (error?.code === 'ENOENT') fail('PrivateEvidenceKeyUnavailable');
    throw error;
  }
  if (key.byteLength !== 32) {
    key.fill(0);
    fail('InvalidPrivateEvidenceKey');
  }
  return Object.freeze({key, keyId: cidOf(key)});
}

const holdingCidOf = (prepareAttemptId, name, semanticCid) => cidOf(
  Buffer.from(JSON.stringify({version: HOLDING_VERSION,
    prepare_attempt_id: prepareAttemptId, name, semantic_cid: semanticCid}),
  'utf8'));

// `preparation(id)` returns undefined when the journal has no preparation,
// else {status, runStatus}. It is the only retention input.
export function openContinuationEvidence({stateDirectory, key, keyId,
  contractControl, preparation, busyTimeoutMs = 60_000, store: storeOptions}) {
  if (!(key instanceof Uint8Array) || key.byteLength !== 32 ||
      typeof keyId !== 'string' || typeof preparation !== 'function') {
    fail('InvalidContinuationEvidencePort');
  }
  const ledgers = join(stateDirectory, 'attempts');
  const ledgerPath = id => {
    if (typeof id !== 'string' || !ATTEMPT.test(id)) fail('InvalidPrepareAttemptId');
    return join(ledgers, `${id}.json`);
  };
  const configuration = Object.freeze({
    directory: join(stateDirectory, 'private-store'),
    storeAuthorityCid: cidOf(Buffer.from(
      'actql-local-host-continuation-store/0.1', 'utf8')),
    capacityBytes: 1024 * 1024 * 1024,
    maxObjectBytes: 4 * 1024 * 1024,
    maxObjects: 100_000,
    maxContractNodes: 4096,
    maxContractDepth: 64,
    ...storeOptions,
  });

  // One Store owner at a time: each operation opens, works and closes. A
  // Store left with a pending deletion keeps its in-process cleanup owner
  // and is reused until that deletion completes (or the process exits,
  // after which the next owner recovers the durable deletion record).
  let retained;
  let queue = Promise.resolve();
  async function openStore() {
    const deadline = Date.now() + busyTimeoutMs;
    for (;;) {
      try {
        return await openLocalPublicationStore({...configuration,
          privateEvidenceKey: Buffer.from(key)}, contractControl);
      } catch (error) {
        if (error?.code !== 'PublicationStoreBusy' || Date.now() > deadline) {
          throw error;
        }
        await new Promise(done => setTimeout(done, 10 + Math.random() * 30));
      }
    }
  }
  function withStore(work) {
    const operation = queue.then(async () => {
      const store = retained ?? await openStore();
      retained = undefined;
      const cleanups = [];
      try {
        cleanups.push(...await store.recoverPhysicalHoldingDeletions());
        return await work(store, cleanup => cleanups.push(cleanup));
      } finally {
        if (cleanups.some(item => item.status().pending)) retained = store;
        else await store.close();
      }
    });
    queue = operation.catch(() => {});
    return operation;
  }

  async function readLedger(id) {
    let text;
    try { text = await readFile(ledgerPath(id), 'utf8'); }
    catch (error) {
      if (error?.code === 'ENOENT') return undefined;
      throw error;
    }
    let ledger;
    try { ledger = JSON.parse(text); }
    catch (error) { fail('InvalidContinuationLedger', error); }
    if (ledger?.version !== LEDGER_VERSION ||
        ledger.prepare_attempt_id !== id ||
        !Array.isArray(ledger.holdings)) {
      fail('InvalidContinuationLedger');
    }
    return ledger;
  }
  const writeLedger = ledger => durableWrite(ledgerPath(ledger.prepare_attempt_id),
    Buffer.from(JSON.stringify(ledger), 'utf8'));
  // Refuse a different installation key before any decryption.
  const sameKey = entry => {
    if (entry.key_id !== keyId) fail('PrivateEvidenceKeyMismatch');
  };

  // Hold one item under one continuation: reuse this continuation's holding,
  // else share an existing holding of the same evidence held by another
  // continuation, else encrypt and commit a new one.
  async function holdOne(store, prepareAttemptId, entry, wire) {
    const record = holding => Object.freeze({
      version: 'actql-local-physical-holding/0.1', namespace: NAMESPACE,
      holding_cid: entry.holding_cid, manifest_cid: entry.semantic_cid,
      objects: holding.objects,
    });
    const verify = async () => {
      const stored = await store.readPrivateEvidence(entry.name,
        entry.semantic_cid, entry.holding_cid);
      if (!stored.equals(Buffer.from(wire, 'utf8'))) {
        fail('PrivateEvidenceConflict');
      }
    };
    if (await store.inspectPhysicalHolding(entry.holding_cid) !== undefined) {
      return verify();
    }
    for (const name of await listLedgers()) {
      if (name === prepareAttemptId) continue;
      const other = await readLedger(name);
      const source = other?.holdings.find(item => item.state === 'held' &&
        item.key_id === keyId && item.name === entry.name &&
        item.semantic_cid === entry.semantic_cid);
      if (source === undefined) continue;
      const held = await store.inspectPhysicalHolding(source.holding_cid);
      if (held?.namespace !== NAMESPACE) continue;
      try {
        await store.sharePhysicalHolding(source.holding_cid, record(held));
        return verify();
      } catch (error) {
        // The source retired concurrently: hold an own copy instead.
        if (!['PublicationPhysicalHoldingRetiring',
          'PublicationPhysicalHoldingUnavailable'].includes(error?.code)) {
          throw error;
        }
      }
    }
    const prepared = await store.preparePrivateEvidence(entry.name, wire,
      entry.semantic_cid);
    try {
      await store.commitPhysicalHolding(record({objects: [{
        cid: prepared.physicalCid, byte_count: prepared.bytes}]}),
      [prepared.prepared]);
    } finally {
      if (prepared.prepared.status().pending) await prepared.prepared.release();
    }
    return verify();
  }

  async function listLedgers() {
    let names;
    try { names = await readdir(ledgers); }
    catch (error) {
      if (error?.code === 'ENOENT') return [];
      throw error;
    }
    return names.filter(name => /^[A-Za-z0-9._:-]{1,128}\.json$/u.test(name))
      .map(name => name.slice(0, -'.json'.length)).sort();
  }

  function needed(ledger) {
    const current = preparation(ledger.prepare_attempt_id);
    if (current === undefined) return ledger.abandoned !== true;
    if (current.status === 'ended') return false;
    if (current.status === 'run_created') {
      return !TERMINAL_RUNS.includes(current.runStatus);
    }
    return true;
  }

  const reference = (prepareAttemptId, name, wire) => {
    if (!NAMES.includes(name) || typeof wire !== 'string') {
      fail('InvalidContinuationEvidence');
    }
    ledgerPath(prepareAttemptId);
    const semanticCid = cidOf(Buffer.from(wire, 'utf8'));
    return Object.freeze({name, semantic_cid: semanticCid,
      holding_cid: holdingCidOf(prepareAttemptId, name, semanticCid),
      key_id: keyId});
  };

  return Object.freeze({
    keyId,

    // The exact reference and holding of one evidence item of a continuation.
    reference,

    // Hold `items` ({name, wire}) for one continuation; returns their
    // semantic CIDs in order. The ledger names every holding before the
    // Store commits it, so a crash never leaves unowned evidence.
    async hold(prepareAttemptId, requestCid, items) {
      const entries = items.map(({name, wire}) =>
        ({...reference(prepareAttemptId, name, wire), state: 'held'}));
      const ledger = await readLedger(prepareAttemptId) ?? {
        version: LEDGER_VERSION, prepare_attempt_id: prepareAttemptId,
        request_cid: requestCid, key_id: keyId, holdings: []};
      sameKey(ledger);
      if (ledger.request_cid !== requestCid) fail('ContinuationRequestMismatch');
      for (const entry of entries) {
        const existing = ledger.holdings.find(item =>
          item.holding_cid === entry.holding_cid);
        if (existing === undefined) ledger.holdings.push(entry);
        else if (existing.state !== 'held') fail('ContinuationEvidenceRetired');
      }
      await writeLedger(ledger);
      await withStore(async store => {
        for (const [index, entry] of entries.entries()) {
          await holdOne(store, prepareAttemptId, entry, items[index].wire);
        }
      });
      return entries.map(entry => entry.semantic_cid);
    },

    // The exact references of one continuation. Reads check the recorded key
    // id first and verify the decrypted bytes against their semantic CID.
    async open(prepareAttemptId) {
      const ledger = await readLedger(prepareAttemptId);
      if (ledger === undefined) fail('ContinuationEvidenceNotFound');
      sameKey(ledger);
      const bytes = async (name, semanticCid) => {
        const current = await readLedger(prepareAttemptId);
        const entry = current?.holdings.find(item => item.name === name &&
          item.semantic_cid === semanticCid);
        if (entry === undefined) fail('ContinuationEvidenceNotHeld');
        sameKey(entry);
        if (entry.state !== 'held') fail('ContinuationEvidenceRetired');
        const stored = await withStore(store => store.readPrivateEvidence(
          name, semanticCid, entry.holding_cid));
        if (cidOf(stored) !== semanticCid) fail('ArtifactIntegrityFailed');
        return stored;
      };
      return Object.freeze({
        requestCid: ledger.request_cid,
        bytes,
        record: async (name, cid) => JSON.parse(
          (await bytes(name, cid)).toString('utf8')),
      });
    },

    // A continuation whose Checkpoint was never committed has no remaining
    // need: its evidence may be retired even though the journal has no row.
    async abandon(prepareAttemptId) {
      const ledger = await readLedger(prepareAttemptId);
      if (ledger === undefined || preparation(prepareAttemptId) !== undefined) {
        return;
      }
      await writeLedger({...ledger, abandoned: true});
    },

    // Retire every holding whose continuation has no remaining need. A failed
    // deletion stays `retiring` in the ledger and in the Store's durable
    // deletion record; the next call (or Store recovery) retries it.
    async settle() {
      const retired = [];
      const pending = [];
      for (const id of await listLedgers()) {
        const ledger = await readLedger(id);
        const releasable = ledger.holdings.filter(item =>
          item.name !== 'invocation_request' && item.state !== 'retired');
        if (releasable.length === 0 || needed(ledger)) continue;
        for (const item of releasable) item.state = 'retiring';
        await writeLedger(ledger);
        await withStore(async (store, keep) => {
          for (const item of releasable) {
            const result = await store.retirePhysicalHolding(item.holding_cid);
            if (result.deleted) {
              item.state = 'retired';
              delete item.cleanup_error;
              retired.push(item.holding_cid);
            } else {
              keep(result.cleanup);
              item.cleanup_error = result.cleanup.status().errors.at(-1)?.code ??
                'PrivateEvidenceDeletionPending';
              pending.push({prepare_attempt_id: id,
                holding_cid: item.holding_cid, code: item.cleanup_error});
            }
          }
        });
        await writeLedger(ledger);
      }
      return Object.freeze({retired, pending});
    },

    // Release this process's Store owner if one is still retained. Waiting
    // evidence is never deleted here.
    async close() {
      await queue;
      const store = retained;
      retained = undefined;
      if (store !== undefined) {
        try { await store.close(); } catch { /* durable deletion record */ }
      }
    },
  });
}
