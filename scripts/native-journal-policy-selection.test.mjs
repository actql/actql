import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync, mkdtempSync, writeFileSync, rmSync} from 'node:fs';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {spawnSync} from 'node:child_process';
import {testExecutionResult} from './test-execution.mjs';

const source = name => readFileSync(new URL(`../src/cmd/native_client/${name}`, import.meta.url), 'utf8');
const block = (text, name) => {
  const selected = text.split('///|').filter(value => value.includes(`fn ${name}(`));
  assert.equal(selected.length, 1, name);
  return selected[0].trim();
};

// Actual private arithmetic only. This component probe owns no Native Host,
// backing, Journal or stored history; the consuming Native package is checked.
test('selected Journal policy preserves Int boundaries and physical source/snapshot checks', {timeout: 90_000}, t => {
  const root = mkdtempSync(join(tmpdir(), 'actql-journal-policy-selection-'));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  writeFileSync(join(root, 'moon.mod'), 'name = "actql/journal-policy-selection"\n');
  writeFileSync(join(root, 'moon.pkg'), 'supported_targets = "js"\n');
  writeFileSync(join(root, 'policy.mbt'), [
    block(source('local_adoption.mbt'), 'local_host_journal_record_limit'),
    block(source('local_command_native_storage_quote.mbt'), 'native_storage_journal_bounds_cover'),
  ].join('\n'));
  writeFileSync(join(root, 'policy_wbtest.mbt'), `
test "selected positive Int policy is not a future physical count reservation" {
  for (wire, expected) in [(1L, 1), (1023L, 1023), (1024L, 1024), (1025L, 1025), (2147483647L, 2147483647)] {
    assert_eq(local_host_journal_record_limit(wire), Some(expected))
    assert_true(native_storage_journal_bounds_cover("original", 8388608L, "original", expected, 8388608L))
    assert_false(native_storage_journal_bounds_cover("original", 8388608L, "foreign", expected, 8388608L))
    assert_false(native_storage_journal_bounds_cover("original", 8388608L, "original", expected, 8388609L))
  }
  for wire in [0L, -1L, 2147483648L, 9223372036854775807L] {
    assert_eq(local_host_journal_record_limit(wire), None)
  }
  for records in [0, -1] {
    assert_false(native_storage_journal_bounds_cover("original", 8388608L, "original", records, 1L))
  }
  assert_false(native_storage_journal_bounds_cover("original", 8388608L, "original", 1, 0L))
  assert_false(native_storage_journal_bounds_cover("original", 8388608L, "original", 1, -1L))
}
`);
  const args = ['test', '--target', 'js', '--frozen', '--jobs', '2'];
  const result = spawnSync('moon', args, {cwd: root, encoding: 'utf8', timeout: 75_000, maxBuffer: 1024 * 1024});
  const checked = testExecutionResult('moon', 'moon', args, result);
  assert.equal(checked.status, 0, `${result.stdout}\n${result.stderr}`);
  assert.equal(checked.counts?.passed ?? checked.evidence?.counts?.passed, 1);
});

test('actual Native caller forwards configured Journal policy without preallocating its count', () => {
  const adoption = source('local_adoption.mbt');
  const settings = block(adoption, 'local_host_settings');
  assert.match(settings, /local_host_journal_record_limit\(number\("journal_record_limit"\)\)/u);
  assert.match(settings, /record_limit: records,/u);
  const bounds = source('local_command_native_storage_quote.mbt');
  const quote = block(bounds, 'quote_local_command_native_storage');
  assert.doesNotMatch(quote, /max_records|records/u);
  assert.doesNotMatch(bounds.split('///|').find(value => value.includes('priv struct LocalCommandNativeStorageBounds')), /max_records/u);
  assert.doesNotMatch(source('local_command_installed_profile.mbt'), /max_records/u);
  const prepared = source('local_command_preparation.mbt');
  assert.match(prepared, /self\.native_storage\.covers_journal\([\s\S]*?options\.max_records,[\s\S]*?options\.max_snapshot_bytes,/u);
  assert.equal((prepared.match(/options\.max_records,/gu) ?? []).length, 3);
  assert.match(source('local_command_check.mbt'), /max_records: settings\.record_limit,/u);
  assert.match(adoption, /max_records: settings\.record_limit,/u);
});
