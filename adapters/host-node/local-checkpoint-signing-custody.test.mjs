// Actual SQLite/Checkpoint runtime custody only. These records are explicit
// fixtures, not initialized signing grants, permission or a public approval.
import assert from 'node:assert/strict';
import {mkdtemp} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import * as runtime from '../../_build/js/release/build/checkpoint_runtime_node/checkpoint_runtime_node.js';
import {openSqliteCheckpointJournal} from './sqlite-checkpoint-journal.mjs';

const operation = 'sha256:' + 'a'.repeat(64);
const options = {runtime, expectedAuthorityScopeCid: 'sha256:' + 'b'.repeat(64),
  authorizeResolution() {assert.fail('No resolution admission in this custody counter');},
  attestResolution() {assert.fail('No physical signature in this custody counter');}};

test('same original signing claim and saved outcome survive actual Journal close and reopen', async () => {
  const root = await mkdtemp(join(tmpdir(), 'actql-local-signing-custody-'));
  let journal = openSqliteCheckpointJournal(root, options);
  const claimed = JSON.stringify({state: 'claimed', preimage: operation});
  const finished = JSON.stringify({state: 'saved', preimage: operation, originalSignature: 'fixture'});
  try {
    assert.equal(journal.localSigningRecord(operation), undefined);
    assert.equal(journal.transitionLocalSigningRecord(operation, undefined, claimed), claimed);
    journal.close();
    journal = openSqliteCheckpointJournal(root, options);
    assert.equal(journal.localSigningRecord(operation), claimed);
    assert.throws(() => journal.transitionLocalSigningRecord(operation, undefined, finished),
      {code: 'LocalSigningOriginalConflict'});
    assert.equal(journal.transitionLocalSigningRecord(operation, claimed, finished), finished);
    journal.close();
    journal = openSqliteCheckpointJournal(root, options);
    assert.equal(journal.localSigningRecord(operation), finished);
  } finally {journal.close();}
});

test('foreign expected signing outcome cannot replace the original claimed use', async () => {
  const root = await mkdtemp(join(tmpdir(), 'actql-local-signing-conflict-'));
  const journal = openSqliteCheckpointJournal(root, options);
  try {
    journal.transitionLocalSigningRecord(operation, undefined, 'original claimed');
    assert.throws(() => journal.transitionLocalSigningRecord(operation, 'foreign claim', 'replacement'),
      {code: 'LocalSigningOriginalConflict'});
    assert.equal(journal.localSigningRecord(operation), 'original claimed');
    assert.throws(() => journal.transitionLocalSigningRecord(operation, 'original claimed', 'x'.repeat(32769)),
      {code: 'InvalidLocalSigningOperation'});
    assert.equal(journal.localSigningRecord(operation), 'original claimed');
  } finally {journal.close();}
});

test('a pre-COMMIT signing record failure rolls back without inventing a saved claim', async () => {
  const root = await mkdtemp(join(tmpdir(), 'actql-local-signing-rollback-'));
  const original = new Error('Original local claim storage failure');
  const journal = openSqliteCheckpointJournal(root, {...options, faults: {
    beforeCommit(step) {if (step === 'localSigningRecord') throw original;},
  }});
  try {
    assert.throws(() => journal.transitionLocalSigningRecord(operation, undefined, 'claimed'),
      cause => cause === original);
    assert.equal(journal.localSigningRecord(operation), undefined);
  } finally {journal.close();}
});
