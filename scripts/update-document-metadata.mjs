import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, relative } from 'node:path';
import { pathToFileURL } from 'node:url';
import assert from 'node:assert/strict';
import { normalizedParagraphs } from './actql-requirement-extraction.mjs';
import { fingerprint, machineCid, documentCid } from './actql-spec-family.mjs';

// Explicit requirement IDs belong to authors. Never infer ID continuity from similar prose.
export function updateRequirements(descriptor, source, registry) {
  const body = source.replace(/^---\n[\s\S]*?\n---\n/u, '');
  const marks = [...body.matchAll(/^<!-- requirement-block: ([^\n]+) -->$/gmu)];
  const old = new Map(registry.requirements.map(r => [r.requirement_id, r]));
  const requirements = [], changes = [], ids = new Set();
  const completeEntries = normalizedParagraphs(body);
  let offset = 0;
  for (const [i, mark] of marks.entries()) {
    const keys = mark[1].split(' ').map(key => `${descriptor.spec_id}/${key}`);
    const localEntries = normalizedParagraphs(body.slice(mark.index + mark[0].length, marks[i + 1]?.index ?? body.length));
    const entries = completeEntries.slice(offset, offset + localEntries.length);
    assert.deepEqual(entries.map(fingerprint), localEntries.map(fingerprint), `Unmarked requirement before ${mark[1]}`);
    offset += entries.length;
    assert.equal(keys.length, entries.length, `Assign one explicit requirement ID per extracted obligation: ${mark[1]}`);
    for (const [j, entry] of entries.entries()) {
      const id = keys[j], hash = fingerprint(entry), previous = old.get(id);
      assert.ok(!ids.has(id), `Duplicate ID ${id}`); ids.add(id);
      if (previous?.statement_sha256 === hash && previous.source.anchor === entry.section) requirements.push(previous);
      else {
        changes.push({ id, change: previous ? 'changed' : 'added', before: previous?.statement_sha256, after: hash });
        requirements.push({ requirement_id: id, statement_sha256: hash,
          status: 'pending', reason: 'implementation_evidence_required',
          next_action: 'Verify this requirement against the MoonBit implementation with independent positive and negative evidence.',
          source: { anchor: entry.section, kind: previous?.source.kind ?? 'prose' } });
      }
    }
  }
  assert.equal(requirements.length, normalizedParagraphs(body).length, `Unmarked requirement in ${descriptor.path}`);
  for (const id of old.keys()) if (!ids.has(id)) changes.push({ id, change: 'removed' });
  return { registry: { ...registry, requirements }, changes };
}

export function updateDocumentMetadata(write = false) {
  const read = path => JSON.parse(readFileSync(path, 'utf8'));
  const manifestPath = 'spec/spec-family.json', manifest = read(manifestPath);
  const pending = new Map(), changes = [];
  for (const d of manifest.documents) {
    let source = readFileSync(d.path, 'utf8');
    for (const ref of d.machine_contracts ?? []) {
      const object = read(ref.path);
      const value = ref.pointer.split('/').slice(1).reduce((v, key) => v?.[key.replace(/~1/g, '/').replace(/~0/g, '~')], object);
      assert.notEqual(value, undefined, `Missing pinned body ${ref.path}#${ref.pointer}`);
      const cid = machineCid(value);
      if (ref.cid !== cid) {
        const prefix = `${relative(dirname(d.path), ref.path)}#${ref.pointer} `;
        assert.ok(source.includes(prefix + ref.cid), `Missing pin declaration ${prefix}`);
        source = source.replaceAll(prefix + ref.cid, prefix + cid);
        changes.push({ path: ref.path, pointer: ref.pointer, before: ref.cid, after: cid });
        ref.cid = cid;
      }
      // Version changes require a separate explicit edit, never an inferred upgrade.
      if (ref.version !== undefined) assert.equal(ref.version, object.version, `Review version change: ${ref.path}`);
    }
    pending.set(d.path, source);
    const update = updateRequirements(d, source, read(d.evidence));
    changes.push(...update.changes);
    pending.set(d.evidence, JSON.stringify(update.registry, null, 2) + '\n');
  }
  for (const d of manifest.documents) for (const ref of d.normative_imports ?? []) {
    const owner = manifest.documents.find(other => other.spec_id === ref.owner);
    assert.ok(owner, `Missing owner ${ref.owner}`);
    const cid = documentCid(pending.get(owner.path));
    if (cid !== ref.document_cid) changes.push({ owner: ref.owner, before: ref.document_cid, after: cid });
    ref.document_cid = cid;
  }
  pending.set(manifestPath, JSON.stringify(manifest, null, 2) + '\n');
  console.log(JSON.stringify({ changes, writes: write }, null, 2));
  // Build and validate every update before writing any file.
  if (write) {
    for (const [path, content] of pending) if (readFileSync(path, 'utf8') !== content) writeFileSync(path, content);
  } else if (changes.length) process.exitCode = 1;
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) updateDocumentMetadata(process.argv.includes('--write'));
