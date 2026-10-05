// Independent read-only custody preimage. Journal originals select the exact
// admitted attempt; the product's holding-key helper is deliberately not used.
import assert from 'node:assert/strict';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {cid} from './installed-infer-fixture.mjs';

export function scopedModelHolding(root, runDefinitionCid, storeAuthorityCid, role, ordinal = 0) {
  const journal = new DatabaseSync(join(root, 'checkpoints', 'journal',
    'checkpoint-journal.sqlite3'), {readOnly: true});
  let entries;
  try {
    entries = journal.prepare('SELECT entry_json FROM resume_model_attempts WHERE ordinal = ?')
      .all(ordinal).map(row => JSON.parse(row.entry_json))
      .filter(entry => entry.runDefinitionCid === runDefinitionCid);
  } finally { journal.close(); }
  assert.equal(entries.length, 1, 'one original physical attempt must own the saved cell');
  const [entry] = entries;
  assert.equal(entry.ordinal, ordinal);
  assert.equal(entry.attemptIndex, 1);
  return cid({version: 'actql-model-scoped-private-holding/0.1',
    run_definition_cid: runDefinitionCid, store_authority_cid: storeAuthorityCid,
    scope_cid: entry.scopeCid, slot_cid: entry.slotCid, attempt_cid: entry.attemptCid,
    attempt: 1, phase: 'settled', role});
}
