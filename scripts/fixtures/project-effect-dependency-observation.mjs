// Read-only oracle over this fixture's own completed private capture. It uses
// the same authenticated physical-evidence inspection as model-resume-public
// tests, without opening a Host, manufacturing evidence, or mutating the Store.
import assert from 'node:assert/strict';
import {createDecipheriv, createHash} from 'node:crypto';
import {constants} from 'node:fs';
import {open} from 'node:fs/promises';
import {join} from 'node:path';

const cidPattern = /^sha256:[0-9a-f]{64}$/u;
const digest = value => 'sha256:' + createHash('sha256').update(value).digest('hex');
const canonical = value => {
  if (value === null || typeof value !== 'object') return JSON.stringify(value);
  if (Array.isArray(value)) return '[' + value.map(canonical).join(',') + ']';
  return '{' + Object.keys(value).sort().map(key =>
    JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}';
};
const readOriginal = async (path, maximumBytes) => {
  const handle = await open(path, constants.O_RDONLY | constants.O_NOFOLLOW);
  try {
    const metadata = await handle.stat();
    assert(metadata.isFile() && Number.isSafeInteger(metadata.size) && metadata.size <= maximumBytes);
    const bytes = await handle.readFile();
    assert.equal(bytes.byteLength, metadata.size);
    return bytes;
  } finally {await handle.close();}
};
const decoded = (text, size) => {
  assert.equal(typeof text, 'string');
  const bytes = Buffer.from(text, 'base64');
  assert.equal(bytes.toString('base64'), text);
  if (size !== undefined) assert.equal(bytes.byteLength, size);
  return bytes;
};

export async function observeProjectEffectDependencies(stateDir, ref, maximumBytes,
  keySelection = 'ordinary') {
  assert(cidPattern.test(ref?.runDefinitionCid));
  assert(Number.isSafeInteger(maximumBytes) && maximumBytes > 0);
  assert(['ordinary', 'project-mock'].includes(keySelection));
  const root = join(stateDir, 'publication');
  const store = JSON.parse(await readOriginal(join(root, 'store.json'), maximumBytes));
  assert(cidPattern.test(store.store_authority_cid));
  const recordCid = digest(canonical({run_definition_cid: ref.runDefinitionCid,
    store_authority_cid: store.store_authority_cid,
    version: 'actql-effect-computation-record/0.1'}));
  const holding = JSON.parse(await readOriginal(
    join(root, 'physical-holdings', recordCid.slice(7) + '.json'), maximumBytes));
  assert.equal(holding.holding_cid, recordCid);
  assert.equal(holding.namespace, 'publication-private');
  assert(cidPattern.test(holding.manifest_cid));
  assert.equal(holding.objects.length, 1);
  const object = holding.objects[0];
  assert(cidPattern.test(object.cid));
  const encrypted = await readOriginal(join(root, 'objects', object.cid.slice(7)), maximumBytes);
  assert.equal(encrypted.byteLength, object.byte_count);
  assert.equal(digest(encrypted), object.cid);
  const envelope = JSON.parse(encrypted);
  assert.equal(envelope.version, 'actql-private-publication-evidence/0.1');
  // The fixture explicitly names its original installation. Never try other
  // keys after an authentication failure or infer authority from ciphertext.
  const keyPath = keySelection === 'ordinary'
    ? join(stateDir, 'checkpoints', 'private-evidence.key')
    : join(stateDir, 'mock-account', 'continuation.key');
  const material = await readOriginal(keyPath, keySelection === 'ordinary' ? 32 : 44);
  let plaintext, key;
  try {
    key = keySelection === 'ordinary' ? material : decoded(material.toString('utf8'), 32);
    assert.equal(key.byteLength, 32);
    const decipher = createDecipheriv('aes-256-gcm', key, decoded(envelope.nonce, 12));
    decipher.setAAD(Buffer.from('actql-private-publication-evidence/0.1\0effect_capture\0' + holding.manifest_cid));
    decipher.setAuthTag(decoded(envelope.tag, 16));
    const initial = decipher.update(decoded(envelope.ciphertext));
    try {plaintext = Buffer.concat([initial, decipher.final()]);}
    finally {initial.fill(0);}
  } finally {key?.fill(0); material.fill(0);}
  try {
    const record = JSON.parse(plaintext);
    assert.equal(record.version, 'actql-completed-effectful-capture/0.1');
    assert.equal(record.store_authority_cid, store.store_authority_cid);
    assert.equal(JSON.parse(record.run_definition).run_definition_cid, ref.runDefinitionCid);
    const captured = JSON.parse(record.captured_run);
    assert.equal(captured.captured_run_cid, holding.manifest_cid);
    const inventory = captured.effect_context.effect_dependency_inventory;
    assert(Array.isArray(inventory) && inventory.length > 0);
    const seen = new Set(), entries = [], references = [], counts = {};
    let canonicalDataBodyBytes = 0;
    for (const entry of inventory) {
      assert.deepEqual(Object.keys(entry).sort(), ['body', 'cid', 'kind']);
      assert.equal(typeof entry.kind, 'string');
      assert(cidPattern.test(entry.cid));
      const identity = entry.kind + '\0' + entry.cid;
      assert(!seen.has(identity), 'Every observed dependency identity must be unique after deduplication');
      seen.add(identity);
      const wire = canonical(entry.body);
      canonicalDataBodyBytes += Buffer.byteLength(wire);
      entries.push({kind: entry.kind, cid: entry.cid, wire});
      counts[entry.kind] = (counts[entry.kind] ?? 0) + 1;
      // Compare every CID-valued occurrence and its exact JSON pointer. This
      // is a complete byte-level reference-change oracle; the actual normal
      // Core recovery remains the authority for typed dependency graph edges.
      const pending = [[entry.body, '']];
      while (pending.length) {
        const [value, pointer] = pending.pop();
        if (typeof value === 'string' && cidPattern.test(value)) {
          references.push({kind: entry.kind, cid: entry.cid, pointer, target: value});
        } else if (value !== null && typeof value === 'object') {
          for (const key of Object.keys(value)) {
            const segment = key.replaceAll('~', '~0').replaceAll('/', '~1');
            pending.push([value[key], pointer + '/' + segment]);
          }
        }
      }
    }
    entries.sort((a, b) => a.kind.localeCompare(b.kind) || a.cid.localeCompare(b.cid));
    references.sort((a, b) => a.kind.localeCompare(b.kind) || a.cid.localeCompare(b.cid) ||
      a.pointer.localeCompare(b.pointer) || a.target.localeCompare(b.target));
    const snapshot = {runDefinitionCid: ref.runDefinitionCid, capturedRunCid: holding.manifest_cid,
      recordHoldingCid: recordCid, encryptedObjectCid: object.cid, entries, references};
    return {summary: {uniqueData: entries.length, canonicalDataBodyBytes,
      inventoryBytes: Buffer.byteLength(canonical(inventory)), counts, references: references.length,
      snapshotCid: digest(canonical(snapshot))}, snapshot};
  } finally {plaintext?.fill(0);}
}

// The real children and tests share this bounded diagnostic projection.
export const dependencyBoundaryFailureData = (value, depth = 8) => {
  if (depth === 0 || value === null || typeof value !== 'object') return undefined;
  const data = key => {
    try {
      for (let owner = value, level = 0; owner !== null && typeof owner === 'object' && level < 4;
        owner = Object.getPrototypeOf(owner), level++) {
        const property = Object.getOwnPropertyDescriptor(owner, key);
        if (property) return Object.hasOwn(property, 'value') ? property.value : undefined;
      }
    } catch { /* Diagnostic inspection cannot replace the original failure. */ }
  };
  const result = {};
  for (const key of ['name', 'code', 'phase', 'kind', 'boundary', 'dimension',
    'issueTag', 'nestedIssueTag', 'required', 'available', 'limit', '$tag',
    'cause', 'primaryDiagnostic', 'issue', '_0', '_1', '_2', '_3']) {
    const field = data(key);
    if (typeof field === 'number' || typeof field === 'boolean') result[key] = field;
    else if (!key.startsWith('_') && typeof field === 'string' &&
      field.length <= 192 && /^[A-Za-z0-9_.:/-]+$/u.test(field)) result[key] = field;
    else if (field !== null && typeof field === 'object') result[key] = dependencyBoundaryFailureData(field, depth - 1);
  }
  return result;
};
