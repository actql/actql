// A user-owned sink for bounded copies of original Model capture facts.
// These files are Evidence custody, not Run/admission/approval records.
import {mkdir, open, link, lstat, opendir, unlink} from 'node:fs/promises';
import {constants} from 'node:fs';
import {join, resolve} from 'node:path';
import {randomUUID} from 'node:crypto';
import {canonicalJson as sdkCanonicalJson} from '../../packages/sdk/host-port.mjs';
import {checkEvidenceReference, contentCid, evidenceParts, referenceCid} from './evidence-reference.mjs';

const canonicalJson = value => sdkCanonicalJson(value, {dataKeys: true});

const fail = code => {throw Object.assign(new Error(code), {code});};
const incomplete = reason => Object.freeze({status: 'incomplete', reason});
const positive = value => Number.isSafeInteger(value) && value > 0;
const manifestName = (subject, target) => {
  if (!/^sha256:[a-f0-9]{64}$/u.test(subject?.runDefinitionCid) ||
      !/^sha256:[a-f0-9]{64}$/u.test(subject?.authorityScopeCid) ||
      typeof target !== 'string' || !target || target.length > 256) fail('InvalidEvidenceManifest');
  // The logical target and original scope are part of custody identity. A
  // second INFER in the same Run must never overwrite the first receipt.
  return `manifest-${contentCid(canonicalJson({subject, target})).slice(7)}`;
};

export async function createCaptureSink({directory, destination, authorize,
  maxBytes, maxPendingBytes, maxRetainedBytes = maxPendingBytes, retentionMs, now = Date.now}) {
  if (typeof directory !== 'string' || !directory || typeof destination !== 'string' ||
    !destination || typeof authorize !== 'function' || typeof now !== 'function' ||
    !positive(maxBytes) || maxBytes > 1048576 || !positive(maxPendingBytes) ||
    maxPendingBytes > 16777216 || !positive(maxRetainedBytes) || maxRetainedBytes > 16777216 || !positive(retentionMs) || retentionMs > 300000) {
    fail('InvalidEvidenceSink');
  }
  const root = resolve(directory);
  await mkdir(root, {recursive: true, mode: 0o700});
  // The application exclusively owns this sink directory. Bound retained
  // originals across reopen, separately from transient copy reservations.
  const stored = new Map(), pendingHandles = new Set();
  let retained = 0;
  let entries = 0;
  for await (const entry of await opendir(root)) {
    if (++entries > 256) fail('EvaluationBudgetExceeded');
    const name = entry.name;
    if (!/^(?:[a-f0-9]{64}|manifest-[a-f0-9]{64}|pending-[a-f0-9-]{36})$/u.test(name)) fail('InvalidEvidenceSink');
    const path = join(root, name), stat = await lstat(path);
    if (!stat.isFile() || stat.isSymbolicLink() || stat.size > maxRetainedBytes - retained) fail('EvaluationBudgetExceeded');
    retained += stat.size; stored.set(path, stat.size);
  }
  let pending = 0;
  const chargeStored = (path, bytes) => {
    if (stored.size >= 256 || bytes > maxRetainedBytes - retained) fail('EvaluationBudgetExceeded');
    retained += bytes; stored.set(path, bytes);
  };
  const forgetStored = path => {
    if (stored.has(path)) {retained -= stored.get(path); stored.delete(path);}
  };
  const pendingRemoval = new Set();
  async function remove(path) {
    pendingRemoval.add(path);
    try {await unlink(path); pendingRemoval.delete(path); forgetStored(path);}
    catch (error) {if (error.code === 'ENOENT') {pendingRemoval.delete(path); forgetStored(path);} else throw error;}
  }
  async function boundedRead(path, ceiling) {
    const file = await open(path, constants.O_RDONLY | constants.O_NOFOLLOW);
    try {
      const stat = await file.stat();
      if (!stat.isFile() || stat.size > ceiling) fail('RequiredEvidenceUnavailable');
      const bytes = Buffer.alloc(ceiling + 1);
      let length = 0;
      for (;;) {
        const {bytesRead} = await file.read(bytes, length, bytes.length - length, null);
        length += bytesRead;
        if (length > ceiling) fail('RequiredEvidenceUnavailable');
        if (bytesRead === 0) break;
      }
      return new TextDecoder('utf-8', {fatal: true}).decode(bytes.subarray(0, length));
    } finally {await file.close();}
  }
  async function persistImmutable(path, wire, revalidate = async () => {}) {
    const temporary = join(root, `pending-${randomUUID()}`), size = Buffer.byteLength(wire);
    chargeStored(temporary, size);
    let file, created = false;
    try {
      file = await open(temporary, 'wx', 0o600);
      pendingHandles.add(file);
      await file.writeFile(wire); await file.sync();
      await revalidate();
      await file.close(); pendingHandles.delete(file); file = undefined;
      if (!stored.has(path)) {
        chargeStored(path, size);
        try {await link(temporary, path); created = true;}
        catch (error) {forgetStored(path); throw error;}
      } else if (await boundedRead(path, size) !== wire) fail('RequiredEvidenceUnavailable');
      const directory = await open(root, constants.O_RDONLY);
      pendingHandles.add(directory);
      try {await directory.sync();}
      finally {await directory.close(); pendingHandles.delete(directory);}
      return created;
    } catch (error) {
      if (created) await remove(path).catch(() => {});
      throw error;
    } finally {
      if (file) {
        try {await file.close(); pendingHandles.delete(file);}
        catch { /* Retain the handle and its custody for cleanup retry. */ }
      }
      if (file && pendingHandles.has(file)) pendingRemoval.add(temporary);
      else await remove(temporary);
    }
  }
  const reserve = bytes => {
    if (bytes > maxPendingBytes - pending) fail('EvaluationBudgetExceeded');
    pending += bytes;
    let released = false;
    return () => {if (!released) {released = true; pending -= bytes;}};
  };
  const permit = async (purpose, reference) => {
    if (await authorize({purpose, destination, subject: reference.subject,
      attemptCid: reference.attemptCid, original: reference.original,
      policy: reference.policy}) !== true) {
      fail(purpose === 'external_evaluation' ? 'EvidenceExternalSendDenied' : 'EvidenceReadDenied');
    }
  };
  const checkTime = ref => checkEvidenceReference(ref, ref.subject, ref.attemptCid, now());
  async function readOriginal(ref, subject, attemptCid) {
    checkEvidenceReference(ref, subject, attemptCid, now());
    if (ref.kind !== 'model_capture') fail('InvalidEvidenceReference');
    await permit('read', ref);
    const release = reserve(ref.content.sizeBytes * 6 + 32768);
    try {
      let saved;
      try {saved = await boundedRead(join(root, ref.evidenceRefCid.slice(7)), ref.content.sizeBytes * 6 + 32768);}
      catch (error) {if (error.code === 'ENOENT') fail('EvidenceOriginalMissing'); throw error;}
      // The limit/reservation precede allocating the protected owned copy.
      const record = JSON.parse(saved);
      if (canonicalJson(record.reference) !== canonicalJson(ref) ||
        typeof record.wire !== 'string' || Buffer.byteLength(record.wire) !== ref.content.sizeBytes ||
        contentCid(record.wire) !== ref.content.cid) fail('RequiredEvidenceUnavailable');
      await permit('read', ref);
      checkTime(ref);
      return record.wire;
    } finally {release();}
  }
  return Object.freeze({
    async capture({subject, attemptCid, original, policy, wires}) {
      if (evidenceParts.some(name => typeof wires?.[name] !== 'string')) return incomplete('RequiredEvidenceUnavailable');
      const total = evidenceParts.reduce((sum, name) => sum + Buffer.byteLength(wires[name]), 0);
      if (total > maxBytes) return incomplete('EvaluationBudgetExceeded');
      let release;
      const written = [];
      try {
        // Copies are already common-owner originals at this handoff. Bound
        // sink serialization separately, before its own buffers are allocated.
        release = reserve(total * 6 + 163840);
        const at = now();
        if (!Number.isFinite(at)) fail('InvalidEvaluationClock');
        const references = {};
        for (const name of evidenceParts) {
          const wire = wires[name];
          const body = {version: 'evaluation-evidence-reference/0.1', kind: 'model_capture', part: name,
            subject, attemptCid, original, policy, content: {cid: contentCid(wire),
              sizeBytes: Buffer.byteLength(wire), truncated: false,
              expiresAt: new Date(at + retentionMs).toISOString()}};
          const ref = {...body, evidenceRefCid: referenceCid(body)};
          checkTime(ref);
          await permit('capture', ref);
          const path = join(root, ref.evidenceRefCid.slice(7));
          if (await persistImmutable(path, canonicalJson({reference: ref, wire}), async () => {
            await permit('capture', ref); checkTime(ref);
          })) written.push(path);
          references[name] = ref;
        }
        // This reports optional capture only, never execution completion.
        return Object.freeze({status: 'complete', references});
      } catch (error) {
        for (const path of written) await remove(path).catch(() => {});
        return Object.freeze({...incomplete(error.code ?? 'EvidenceSinkFailure'), cleanupPending: pendingRemoval.size > 0 || pendingHandles.size > 0});
      } finally {release?.();}
    },
    async record({subject, target, manifest}) {
      const name = manifestName(subject, target);
      if (!manifest ||
        !['complete', 'incomplete'].includes(manifest.status)) fail('InvalidEvidenceManifest');
      const release = reserve(131072);
      try {
        const wire = canonicalJson({subject, target, manifest});
        if (Buffer.byteLength(wire) > 65536) fail('EvaluationBudgetExceeded');
        await persistImmutable(join(root, name), wire);
      } finally {release();}
    },
    async lookup(subject, target) {
      const name = manifestName(subject, target);
      if (await authorize({purpose: 'read_manifest', destination, subject, target}) !== true) fail('EvidenceReadDenied');
      const release = reserve(131072);
      try {
        let saved;
        try {saved = JSON.parse(await boundedRead(join(root, name), 65536));}
        catch (error) {if (error.code === 'ENOENT') fail('EvidenceOriginalMissing'); throw error;}
        if (canonicalJson(saved.subject) !== canonicalJson(subject) || saved.target !== target) fail('EvidenceSubjectMismatch');
        if (await authorize({purpose: 'read_manifest', destination, subject, target}) !== true) fail('EvidenceReadDenied');
        return saved;
      } finally {release();}
    },
    async withEvaluatorEvidence({subject, attemptCid, references}, consume) {
      if (typeof consume !== 'function') fail('InvalidEvaluatorAdapter');
      for (const name of evidenceParts) checkEvidenceReference(references?.[name], subject, attemptCid, now());
      const release = reserve(evidenceParts.reduce((sum, name) => sum + references[name].content.sizeBytes * 2, 0) + 131072);
      try {
      const resolved = {};
      for (const name of evidenceParts) {
        const ref = references?.[name];
        const wire = await readOriginal(ref, subject, attemptCid);
        // Storage/read permission is not permission for this destination.
        await permit('external_evaluation', ref);
        checkTime(ref);
        resolved[name] = {refCid: ref.evidenceRefCid, base64: Buffer.from(wire).toString('base64')};
      }
      // Recheck immediately before transferring the complete batch. A grant
      // remembered for the first item cannot authorize the last handoff.
      for (const ref of Object.values(references)) {await permit('external_evaluation', ref); checkTime(ref);}
      return await consume(resolved);
      } finally {release();}
    },
    pendingBytes: () => pending,
    retainedBytes: () => retained,
    cleanupPending: () => pendingRemoval.size > 0 || pendingHandles.size > 0,
    async cleanup() {
      for (const handle of pendingHandles) {await handle.close(); pendingHandles.delete(handle);}
      for (const path of pendingRemoval) await remove(path);
      return pendingRemoval.size === 0 && pendingHandles.size === 0;
    },
  });
}
