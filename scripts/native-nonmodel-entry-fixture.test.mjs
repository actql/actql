import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {nativeCoreScopedAllocationProfile, nativeCoreScopedBackingPages,
  nativeNonModelEntryTestFile, nativeScopedTestFiles} from './native-core-test-selection.mjs';

const source = readFileSync(new URL('../' + nativeNonModelEntryTestFile, import.meta.url), 'utf8');

test('eligible nonmodel entry retains the selected provider and original backing geometry', () => {
  assert.equal(nativeScopedTestFiles.filter(file => file === nativeNonModelEntryTestFile).length, 1);
  assert.equal(nativeCoreScopedAllocationProfile(nativeNonModelEntryTestFile), 'scoped-review-values');
  assert.equal(nativeCoreScopedBackingPages(nativeNonModelEntryTestFile), 8192);
  assert.equal(nativeCoreScopedBackingPages('src/platform_native/installed_arena_control/local_host_crypto_physical_scoped_wbtest.mbt'), 8192);
  assert.equal(nativeCoreScopedBackingPages('src/platform_native/installed_arena_control/retained_execution_physical_scoped_wbtest.mbt'), 256);
  const runner = readFileSync(new URL('./test-native-core.mjs', import.meta.url), 'utf8');
  assert.match(runner, /backingPages: nativeCoreScopedBackingPages\(test\.source\)/u);
  assert.equal((source.match(/execution_domain_necessary_bytes\(/gu) ?? []).length, 3);
  assert.match(source, /command_backing_control_necessary_bytes\(/u);
});

test('eligible copy proof keeps genuine scope, original take and retirement ordering', () => {
  const body = source.slice(0, source.indexOf('test "eligible copied entry'));
  const ordered = ['.enter_local_host_phase(pair, HostRead)', '.prepare_domain_nonmodel_work_entry(',
    'let copied = { ..entry, }', '.leave_local_host_phase(pair)', '.enter_domain_retained_execution(execution)',
    'let eligible =', 'let copy_refused =', 'let original_unchanged =', 'let original_taken =',
    'let original_reuse_refused =', 'let finished = entry.finish_business_cleanup()',
    '.leave_domain_retained_execution(execution)', 'entry.close_after_original_return()'];
  let previous = -1;
  for (const text of ordered) { const next = body.indexOf(text); assert(next > previous, text); previous = next; }
  const entered = body.slice(body.indexOf('let eligible ='), body.indexOf('.leave_domain_retained_execution(execution)'));
  assert.doesNotMatch(entered, /assert_|fail\(|raise |borrow_domain_retained_execution_ledger|observe_domain/u);
  assert.match(body, /physical_equal\(ledger, execution\.ledger\.unwrap\(\)\)/u);
  assert.doesNotMatch(body, /(?:physical_retired|reported|settled|closed)\s*=/u);
  const cleanup = source.slice(source.indexOf('let proved ='));
  assert(cleanup.indexOf('close_domain_after_owner_ack(business_domain)') < cleanup.indexOf('close_local_host_resources(pair)'));
  assert(cleanup.indexOf('close_local_host_resources(pair)') < cleanup.indexOf('host.try_close()'));
});

test('eligible entry finite owner components remain independently authored', () => {
  assert.equal(26 * 16 + 20 * 8 + 60 * 8, 1056);
  assert.equal(4 * 16 + 11 * 8 + 8 * 8, 216);
  assert.equal(3 * 16 + 3 * 8 + 3 * 8, 96);
  assert.equal(1 * 16 + 8 * 8 + 6 * 8, 128);
  assert.equal(34 * 16 + 42 * 8 + 77 * 8, 1496);
  assert.equal(8 * 16 + 4 * 8 + 10 * 8, 240);
  assert.equal(33 * 16 + 14 * 8 + 79 * 8, 1272);
  assert.match(source, /let read_entry_bytes = 34L \* 16L \+ 42L \* 8L \+ 77L \* 8L/u);
  assert.match(source, /let control_bytes = 8L \* 16L \+ 4L \* 8L \+ 10L \* 8L/u);
  assert.match(source, /65536L \+ 65536L \+ outer_entry_bytes/u);
  assert.equal(8192 - (7168 + 64 + 64), 896);
});

test('eligible byte-only child preserves root attempts and exact pending refusal', () => {
  // Independent original-owner arithmetic: reserve_shared_capacity reserves
  // one attempt, and each delegation reserves one beyond its child allowance.
  const backing = 1, provisioning = 3, read = 2, sqlite = 2, business = 0;
  assert.equal(backing + provisioning + read + sqlite + business, 8);
  assert.equal(backing + provisioning + read + sqlite + 4, 12);
  assert.match(source, /let root_attempts = 8/u);
  assert.match(source, /let backing_attempts = 1/u);
  assert.match(source, /let domain_provisioning_attempts = 3/u);
  assert.match(source, /let business_limits[^]*?attempts: 0,/u);
  assert.match(source, /attempts: root_attempts,/u);
  assert.match(source, /entry\.usage\(\)\.reserved_attempts == 0/u);
  assert.match(source, /assert_eq\(entry\.usage\(\)\.reserved_attempts, 0\)/u);
  const domains = source.slice(source.indexOf('let read_domain ='), source.indexOf('host.transfer_domain(business_domain)'));
  assert.equal((domains.match(/PendingDomain\(_, issue\) =>/gu) ?? []).length, 3);
  assert.equal((domains.match(/raise EligibleEntryDomainFailure\(/gu) ?? []).length, 3);
  assert.doesNotMatch(domains, /PendingDomain\(_, _\)|@debug|fail\(|close_|retry/u);
  assert.match(source, /suberror EligibleEntryDomainFailure[^]*?String, @bootstrap\.NativeBackedExecutionIssue/u);
  assert.match(source, /impl Show for EligibleEntryDomainFailure[^]*?@debug\.to_string\(issue\)/u);
});
