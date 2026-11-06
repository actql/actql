import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

// Source parity only, not an execution or physical-close acknowledgement.
// The old public path keeps its original complete body: calling the new helper
// there would add an allocated Ok(Unit) even if statement ordering were equal.
const source = readFileSync(new URL('../src/platform_native/installed_arena_control/retained_execution_native.mbt', import.meta.url), 'utf8');
function body(marker) {
  const start = source.indexOf(marker);
  assert(start >= 0, `Missing original function ${marker}`);
  const end = source.indexOf('\n///|', start);
  const text = source.slice(start, end < 0 ? undefined : end);
  return text.slice(text.indexOf(' {\n') + 3, text.lastIndexOf('\n}'));
}

test('relation entry physical prefix stays identical to the allocation-neutral legacy close prefix', () => {
  const legacy = body('pub fn InstalledArenaHost::close_domain_retained_execution(');
  const entry = body('fn InstalledArenaHost::retire_retained_execution_context(');
  const report = legacy.indexOf('\n  if !record.reported &&');
  assert(report > 0);
  assert.equal(entry.slice(0, entry.lastIndexOf('\n  Ok(())')), legacy.slice(0, report));
  assert(!legacy.includes('retire_retained_execution_context('));
  const close = legacy.indexOf('close_backed_read_context');
  const retired = legacy.indexOf('require_backed_read_context_retired');
  const reportCall = legacy.indexOf('report_imported_child_ledger');
  const parentReturn = legacy.indexOf('retire_backed_live_child_after_owner_ack');
  assert(close >= 0 && close < retired && retired < reportCall && reportCall < parentReturn);
});

// Every Moon driver links its package's ordinary dependencies, including the
// empty internal driver. Test-only imports cannot provide its scoped allocator.
test('relation fixture retains the original provider as an ordinary dependency', () => {
  const manifest = readFileSync(new URL('../src/platform_native/relation_file_work_tests/moon.pkg', import.meta.url), 'utf8');
  const imports = [...manifest.matchAll(/import \{([\s\S]*?)\}(?: for "(test|wbtest)")?/gu)];
  const ordinary = imports.filter(([, , kind]) => kind === undefined).map(([, body]) => body).join('\n');
  assert.match(ordinary, /"actql\/actql\/platform_native\/host_bootstrap" @bootstrap\s*,/u);
  assert(!manifest.includes('native-stub'));
  const anchor = readFileSync(new URL('../src/platform_native/relation_file_work_tests/original_scope.mbt', import.meta.url), 'utf8');
  assert.match(anchor, /pub type OriginalReadScope = @bootstrap\.NativeBackedReadScope/u);
  assert(!/\b(?:fn|extern|struct|enum)\b/u.test(anchor.replace(/\/\/[^\n]*/gu, '')));
});

// Independently authored arithmetic catches the previous E-only assertion.
// Provider control geometry is observed by the physical case, not guessed here.
test('relation fixture checks retained plus execution and real provider layout within unchanged backing', () => {
  const fixture = readFileSync(new URL('../src/platform_native/relation_file_work_tests/relation_file_original_physical_scoped_test.mbt', import.meta.url), 'utf8');
  const mib = 1048576, addition = 23170242;
  const retained = 8 * mib + addition, execution = 105 * mib + addition;
  assert.equal(retained + execution, 164829572);
  assert(execution <= 128 * mib);
  assert(retained + execution > 128 * mib);
  assert(retained + execution <= 160 * mib);
  assert.equal(160 + 536 + 56, 752);
  assert.equal(768 - 752, 16);
  assert.match(fixture, /let read_payload = 113L \* mib \+ 2L \* read_addition/u);
  assert.match(fixture, /read_necessary > 0L && read_necessary <= 160L \* mib/u);
  assert.match(fixture, /sqlite_necessary > 0L && sqlite_necessary <= 56L \* mib/u);
  assert.match(fixture, /business_necessary > 0L && business_necessary <= 536L \* mib/u);
  assert.match(fixture, /let business_payload = selected\.retained_bytes \+ selected\.execution_bytes/u);
  assert.match(fixture, /backing_control \+ \(160L \+ 536L \+ 56L\) \* mib <= 768L \* mib/u);
  assert.match(fixture, /command_backing_control_necessary_bytes\(/u);
  assert.equal((fixture.match(/execution_domain_necessary_bytes\(/gu) ?? []).length, 3);
  assert.match(fixture, /domain\(160L \* mib/u);
  assert.match(fixture, /prepare_domain\(backing, descriptor, 536L \* mib, selected\)/u);
  assert.match(fixture, /fail\("test domain pending: " \+ @debug\.to_string\(issue\)\)/u);
  assert.match(fixture, /fail\("business domain pending: " \+ @debug\.to_string\(issue\)\)/u);
});

test('relation diagnostic preserves first Work refusal and waits for original returns before formatting', () => {
  const fixture = readFileSync(new URL('../src/platform_native/relation_file_work_tests/relation_file_original_physical_scoped_test.mbt', import.meta.url), 'utf8');
  // The earlier entry-preparation refusal also saves this out-slot. Select
  // the later Work result branch, whose two actual child-close calls we lock.
  const failed = fixture.slice(fixture.lastIndexOf('        Err(failure) => {\n          escaped_failure.val'));
  assert(failed.startsWith('        Err(failure) => {\n          escaped_failure.val = Some(failure)'));
  assert(!failed.includes('assert_true(mode != "positive")'));
  assert(failed.indexOf('if !failure.close()') < failed.indexOf('"original business return"'));
  const cleanup = failed.slice(0, failed.indexOf('      assert_eq(original_entry.usage().live_reservations, 1)'));
  assert.equal((cleanup.match(/failure\.close\(\)/gu) ?? []).length, 2);
  assert.equal((cleanup.match(/if !failure\.close\(\) \{\s*raise Failure\(relation_return_work_label\(failure\.issue\(\)\)\)\s*\}/gu) ?? []).length, 2);
  assert(cleanup.lastIndexOf('if !failure.close()') < cleanup.indexOf('if mode != "positive"'));
  assert(!cleanup.includes('close_after_original_return'));
  assert(failed.indexOf('"original routing scope cleanup"') < failed.indexOf('guard entry is Ok(_)'));
  assert(failed.indexOf('guard entry is Ok(_)') < failed.indexOf('relation_work_issue(failure.issue())'));
  assert(failed.indexOf('relation_work_issue(failure.issue())') < failed.indexOf('escaped_failure.val = None'));
  assert.match(failed, /entry close=false after original return/u);
  assert.match(failed, /Some\(Err\(primary\)\)[\s\S]*original Work assertion:/u);
  assert(!failed.includes('body.val.unwrap().relation_original_value'));
  assert(failed.indexOf('"Crypto cleanup leave"') < failed.indexOf('unexpected positive Work refusal after cleanup:'));
});

test('failed original return selects borrowed or static diagnostics without a new message buffer', () => {
  const fixture = readFileSync(new URL('../src/platform_native/relation_file_work_tests/relation_file_original_physical_scoped_test.mbt', import.meta.url), 'utf8');
  const start = fixture.indexOf('    guard entry is Ok(_) else {');
  const stop = fixture.indexOf('    let body_diagnostic', start);
  assert(start >= 0 && stop > start);
  const branch = fixture.slice(start, stop).replace(/\/\/[^\n]*/gu, '');
  assert.match(branch, /Some\(Err\(primary\)\) => raise Failure\(primary\)/u);
  assert.match(branch, /raise Failure\(relation_return_failure_label\(entry, escaped_failure\.val\)\)/u);
  assert(!/\+|\\\{|\b(?:fail|to_string|substring|slice|finish_pending_original_scope)\(/u.test(branch));
  assert(!fixture.includes('original Read return unresolved'));
  const diagnostics = readFileSync(new URL('../src/platform_native/relation_file_work_tests/relation_work_diagnostics_test.mbt', import.meta.url), 'utf8');
  const selectors = diagnostics.slice(diagnostics.indexOf('fn relation_return_adoption_label(')).replace(/\/\/[^\n]*/gu, '');
  assert(!/\+|\\\{|\b(?:Ref|Array|FixedArray|to_string|fail|finish_pending_original_scope)\(/u.test(selectors));
  assert(!/=>\s*(?:Some|Ok|Err)\(/u.test(selectors));
  const previousBound = 'original Read return unresolved; original body and Work custody retained'.length;
  const labels = [...selectors.matchAll(/"([^"\n]*)"/gu)].map(([, text]) => text);
  assert(labels.length >= 60);
  for (const label of labels) assert(label.length <= previousBound, label);
  assert.match(selectors, /Some\(original\) => relation_return_work_label\(original\.issue\(\)\)/u);
  assert.match(selectors, /Err\(original\) => relation_return_adoption_label\(original\)/u);
});

test('relation fixture compares the authored complete array across next chunks and finish tail', () => {
  const fixture = readFileSync(new URL('../src/platform_native/relation_file_work_tests/relation_file_original_physical_scoped_test.mbt', import.meta.url), 'utf8');
  const functionSource = name => {
    const start = fixture.indexOf(`fn ${name}(`);
    assert(start >= 0, name);
    const end = fixture.indexOf('\n///|', start);
    assert(end > start, name);
    return fixture.slice(start, end).replace(/\/\/[^\n]*/gu, '');
  };
  const chunk = functionSource('relation_original_match_chunk');
  const consume = functionSource('relation_original_export_matches');
  const expected = '[{"id":"second","value":2}]';
  const literal = consume.match(/let expected = ("(?:\\.|[^"\\])*")/u);
  assert(literal);
  assert.equal(JSON.parse(literal[1]), expected);
  assert.match(chunk, /chunk\.length\(\) > expected\.length\(\) - offset/u);
  assert.match(chunk, /chunk\.code_unit_at\(index\) != expected\.code_unit_at\(offset \+ index\)/u);
  assert.match(consume, /while polls <= expected\.length\(\)/u);
  assert.match(consume, /chunk\.is_empty\(\)/u);
  assert.equal((consume.match(/exported\.next\(\)/gu) ?? []).length, 1);
  assert.equal((consume.match(/exported\.finish\(\)/gu) ?? []).length, 1);
  assert.match(consume, /Ok\(None\) =>\s*return match exported\.finish\(\)/u);
  assert.match(consume, /relation_original_match_chunk\(expected, offset, tail\) ==\s*expected\.length\(\)/u);
  assert(!/\b(?:StringBuilder|Array|FixedArray|Ref|to_string|substring|slice|iter|parse)\(/u.test(chunk + consume));
  assert(!/=>\s*(?:Some|Ok|Err)\(/u.test(chunk + consume));
  assert.match(fixture, /assert_true\(relation_original_export_matches\(exported\)\)\s*exported\.cancel\(\)/u);
  assert(!fixture.includes('actual suffix row'));
  assert(!fixture.includes('actual suffix end'));
});
