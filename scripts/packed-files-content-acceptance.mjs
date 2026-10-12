// Independent assertions shared by the packed runner and its detector tests.
// These constants are authored byte laws, not encoder-produced expectations.
import assert from 'node:assert/strict';
import {CLIENT_PACKAGES} from './packed-client-packages.mjs';

export const packedContentBytes = Buffer.from('name\n"approved.csv"\n');
export const packedContentCid = 'sha256:11af3859185fd4b8e2cef2ba824fdddf63b8a6fbfa26aea783660fefda5459de';
export const packedContentCases = Object.freeze([
  {id: 'local-model-command', entrance: 'Local', model: true},
  {id: 'https-model-command', entrance: 'HTTPS', model: true},
  {id: 'https-intermediate-serialize', entrance: 'HTTPS', attachment: true},
  {id: 'local-unknown-command', entrance: 'Local', attachment: true, fault: 'lost_reply'},
]);

// An independent finite product lane, not permission to omit Model acceptance
// from the full objective. Every Pure case still uses a real generated Content
// holding and three separate processes for capture, approval and reread.
export const packedPureContentCases = Object.freeze([
  {id: 'local-serialize-command', entrance: 'Local', attachment: true},
  {id: 'https-serialize-command', entrance: 'HTTPS', attachment: true},
  {id: 'local-serialize-unknown-command', entrance: 'Local', attachment: true, fault: 'lost_reply'},
  {id: 'https-serialize-unknown-command', entrance: 'HTTPS', attachment: true, fault: 'lost_reply'},
].map(value => Object.freeze(value)));

// Reject typos and unsupported subsets before any producer, installation or
// custody directory is created. The default full selection is unchanged.
export function packedContentSelection(args = []) {
  const scope = args.length === 0 ? 'full'
    : args.length === 2 && args[0] === '--scope' ? args[1] : undefined;
  if (scope !== 'full' && scope !== 'pure') {
    throw new TypeError('PackedContentScope must be full or pure');
  }
  return Object.freeze({scope,
    cases: scope === 'pure' ? packedPureContentCases : packedContentCases});
}

// Data/provenance check only. The package consumer must still read and compare
// every actual tarball digest; this shape cannot issue admission or custody.
export function verifyPackedContentProducerManifest(producer, revision) {
  assert.equal(producer?.revision, revision, 'PackedContentProducerRevisionMismatch');
  assert.ok(producer.tarballs !== null && typeof producer.tarballs === 'object' &&
    !Array.isArray(producer.tarballs), 'PackedContentProducerRequiresFivePackages');
  assert.deepEqual(Object.keys(producer.tarballs).sort(), [...CLIENT_PACKAGES].sort(),
    'PackedContentProducerRequiresFivePackages');
  assert.ok(CLIENT_PACKAGES.every(name => typeof producer.tarballs[name] === 'string' &&
    /^[0-9a-f]{64}$/u.test(producer.tarballs[name])), 'PackedContentInvalidProducerDigest');
}

export function verifyPackedContentScenario({scenario, phases, bytes, receipt}) {
  const expectedPhases = scenario.model
    ? ['capture', 'approve-model', 'approve', 'read'] : ['capture', 'approve', 'read'];
  assert.deepEqual(phases.map(value => value.phase), expectedPhases);
  assert.ok(phases.every(value => Number.isSafeInteger(value.pid) && value.pid > 0));
  assert.equal(new Set(phases.map(value => value.pid)).size, phases.length,
    'every phase must actually finish in a different process');
  const [first] = phases;
  assert.equal(first.status, 'waiting_checkpoint');
  assert.deepEqual([first.reads, first.generations, first.modelCalls, first.sends,
    first.writeGrants], [1, 1, 0, 0, 0]);
  for (const value of phases.slice(1)) {
    assert.deepEqual(value.ref, first.ref, 'restart keeps the exact original Run');
    const model = value.phase === 'approve-model';
    const command = value.phase === 'approve';
    assert.deepEqual([value.reads, value.generations, value.modelCalls, value.sends,
      value.writeGrants], [0, 0, model ? 1 : 0, command ? 1 : 0, command ? 1 : 0]);
    assert.equal(value.status, model ? 'waiting_checkpoint'
      : scenario.fault ? 'needs_reconciliation' : 'succeeded');
    if (scenario.fault) {
      assert.equal(value.result_available, false);
      assert.equal(value.rows, undefined, 'an unknown write cannot publish success');
    } else if (!model) {
      assert.equal(value.rows.length, 1);
      const row = value.rows[0];
      assert.deepEqual(Object.keys(row), ['destination', 'name', 'content']);
      assert.equal(row.name, 'approved.csv');
      assert.equal(row.content.media_type, 'text/csv');
      assert.equal(row.content.metadata.content_cid, packedContentCid);
      assert.equal(row.content.metadata.size_bytes, 20);
      assert.deepEqual(row.destination, {$actql_ref: 'resource', version: 'actql-resource-ref/0.1',
        provider_namespace: 'file-fixture', resource_kind: 'file',
        provider_identity_cid: `sha256:${'a'.repeat(64)}`,
        authority_scope_cid: `sha256:${'b'.repeat(64)}`,
        boundary_cid: `sha256:${'c'.repeat(64)}`, identity_cid: `sha256:${'d'.repeat(64)}`});
      if (scenario.attachment) {
        assert.equal(value.attachmentRows.length, 1);
        const attachment = value.attachmentRows[0];
        assert.deepEqual(Object.keys(attachment), ['name', 'content', 'media_type', 'size_bytes', 'row_count']);
        assert.deepEqual(attachment, {name: 'approved.csv', content: row.content,
          media_type: 'text/csv', size_bytes: 20, row_count: 1});
      }
    }
  }
  const command = phases.find(value => value.phase === 'approve');
  const read = phases.at(-1);
  assert.deepEqual(command.rows, read.rows);
  assert.deepEqual(command.attachmentRows, read.attachmentRows);
  assert.deepEqual(bytes, packedContentBytes);
  assert.equal(receipt.content_cid, packedContentCid);
  assert.match(receipt.request_cid, /^sha256:[0-9a-f]{64}$/u);
}
