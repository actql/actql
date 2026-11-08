import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';

const source = readFileSync(new URL('../src/platform_native/client_host/journal_first_start_commit_wbtest.mbt', import.meta.url), 'utf8');

test('Journal first-start cases use the existing second-COMMIT fault without replacing operations', () => {
  assert.equal((source.match(/^test /gmu) ?? []).length, 2);
  assert.match(source, /journal_first_start_commit_failure\(false\)/u);
  assert.match(source, /journal_first_start_commit_failure\(true\)/u);
  assert.equal((source.match(/submitted_test_fail_commit_after\(database, 1, reply_lost\)/gu) ?? []).length, 1);
  assert.doesNotMatch(source, /extern |with_operations|operations=|physical_retired\s*=|\.fenced\s*=/u);
  const call = source.slice(source.indexOf('let original ='), source.indexOf('assert_true(original'));
  assert.match(call, /callbacks\.val \+= 1\s+true/u);
  assert.doesNotMatch(call, /journal\.|database\./u);
  assert.match(source, /assert_eq\(callbacks\.val, 2\)/u);
});

test('Journal first-start cleanup preserves the original Unknown and both fences', () => {
  const order = ['let original =', 'assert_true(original is Err(Journal(TransactionUnknown)))',
    'assert_true(journal.fenced)', 'assert_true(database.transaction_fenced())',
    'is Err(Journal(Fenced))', 'if reply_lost {', 'Ok(@sqlite.NoActiveSqliteTransaction)',
    'Ok(@sqlite.ActiveSqliteTransaction)', 'database.rollback().unwrap()',
    'assert_true(original is Err(Journal(TransactionUnknown)))',
    'assert_true(journal.fenced)', 'assert_true(database.transaction_fenced())',
    'let stored =', 'assert_eq(record.physical_start_claimed, reply_lost)',
    'is Err(Journal(Fenced))', 'let after =', 'assert_eq(after.body, stored.body)',
    'assert_eq(after.revision, stored.revision)', 'database.close_checked().unwrap()'];
  let previous = source.indexOf('let original =') - 1;
  for (const text of order) {
    const next = source.indexOf(text, previous + 1);
    assert(next > previous, text);
    previous = next;
  }
  assert.equal((source.match(/database\.rollback\(\)/gu) ?? []).length, 1);
  assert.equal((source.match(/database\.close_checked\(\)/gu) ?? []).length, 1);
  assert.match(source, /assert_true\(record.dispatch_reserved\)/u);
  assert.match(source, /let committed_revisions = if reply_lost \{ 2L \} else \{ 1L \}/u);
  assert.match(source, /assert_eq\(stored.revision, before.revision \+ committed_revisions\)/u);
});
