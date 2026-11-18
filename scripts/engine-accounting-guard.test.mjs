import test from 'node:test';
import assert from 'node:assert/strict';
import {workspaceCustodyMutation} from './engine-accounting-guard.mjs';
import {fileURLToPath} from 'node:url';
import {checkResourceLifecycle, resourceLifecycleProblems} from './resource-lifecycle-guard.mjs';

test('workspace custody comparisons do not count as assignments', () => {
  for (const source of [
    'if cursor.workspace.live == 0 { None }',
    'if workspace.live==expected { release() }',
    'assert_true(workspace.live != 0)',
    'workspace.live <= limit',
    'workspace.live >= minimum',
    'let live = workspace.live',
  ]) assert.doesNotMatch(source, workspaceCustodyMutation);
});

test('workspace custody assignments are rejected with each guarded operator', () => {
  for (const operator of ['=', '+=', '-=']) {
    for (const spacing of ['', ' ', '\n  ']) {
      const source = `cursor.workspace.live${spacing}${operator} 0`;
      assert.match(source, workspaceCustodyMutation);
    }
  }
  assert.match('if workspace.live == 0 { workspace.live = count }',
    workspaceCustodyMutation);
});

const constructionModule = 'src/run_publication_host/client_keyed_example.mbt';
const constructionInventory = [[constructionModule, 'construct']];
const guardedConstruction = body => `fn construct(lookup : ClientKeyedLookupInput) -> Unit {
  ${body}
  with_keyed_protocol_construction(lookup, 1, 4L, 10, 2,
    fn() { let writer = @encode.writer(1, 1, 1); Ok(keyed_protocol_built(())) },
    _ => Ok(()),
  ) |> ignore
}`;
const problems = (source, extra = []) => resourceLifecycleProblems(new Map([
  [constructionModule, source], ...extra,
]), {inventory: constructionInventory});

test('managed lifecycle guard ignores data and comparisons while checking real code', () => {
  assert.deepEqual(problems(guardedConstruction(`
    // grow_keyed_lookup_protocol_metadata(lookup)
    let data = "finish_keyed_lookup_protocol_metadata }"
    let raw =
      #|keyed_lookup_body_grow(lookup) {
    if lookup.retained_bytes == 0 { () }
    if lookup.execution_bytes >= 0 { () }
  `)), []);
});

test('managed lifecycle guard rejects manual calls and function-value aliases', () => {
  for (const body of [
    'grow_keyed_lookup_protocol_metadata(lookup, 1, 4L)',
    'let escaped = grow_keyed_lookup_protocol_metadata',
    'finish_keyed_lookup_protocol_metadata(lookup, foreign)',
  ]) assert(problems(guardedConstruction(body)).some(issue => issue.rule === 'manual-protocol-phase'));
});

test('managed lifecycle guard requires classified ownership in newly discovered files', () => {
  for (const body of [
    'keyed_lookup_body_grow(lookup, 0L, 0L, 1L, None)',
    '@resources.grow_execution_reservation_capacity(lookup.ledger, lookup.reservation, 1L, 1L)',
  ]) {
    const extra = [['src/run_publication_host/new_receiver.mbt',
      `fn added(lookup : ClientKeyedLookupInput) -> Unit { ${body} }`]];
    assert(problems(guardedConstruction(''), extra).some(issue =>
      ['unclassified-body-growth', 'unclassified-reservation-mutation'].includes(issue.rule)));
  }
});

test('managed lifecycle guard rejects raw builders and nominal exit forgery', () => {
  assert(problems(guardedConstruction('let raw = keyed_protocol_built(())'))
    .some(issue => issue.rule === 'unsettled-builder-escape'));
  const extra = [['src/run_publication_host/new_receiver.mbt',
    'fn forge() -> SettledKeyedProtocolMetadata[Unit] { { value: (), } }']];
  assert(problems(guardedConstruction(''), extra).some(issue => issue.rule === 'private-construction-forgery'));
  assert(problems('fn construct(lookup : ClientKeyedLookupInput) -> Unit { () }')
    .some(issue => issue.rule === 'missing-managed-construction'));
});

test('managed lifecycle guard rejects direct byte updates regardless of local alias', () => {
  for (const operator of ['=', '+=', '-=']) {
    assert(problems(guardedConstruction(`let original = lookup; original.retained_bytes ${operator} 1L`))
      .some(issue => issue.rule === 'direct-byte-custody-assignment'));
  }
});

test('managed lifecycle guard rejects allocation outside its scope and executable interpolation', () => {
  assert(problems(guardedConstruction('let writer = @encode.writer(1, 1, 1)'))
    .some(issue => issue.rule === 'constructor-outside-managed-scope'));
  assert(problems(guardedConstruction('let dynamic = "\\{grow_keyed_lookup_protocol_metadata()}"'))
    .some(issue => issue.rule === 'unclassified-interpolation'));
});

test('managed lifecycle guard refuses executable resource interpolation in new callers and files', () => {
  for (const body of [
    '"\\{grow_keyed_lookup_protocol_metadata(lookup, 1, 1L) is Ok(_)}"',
    '"\\{(finish_keyed_lookup_protocol_metadata)(lookup, phase, 1, 1, []) is Ok(_)}"',
    '"\\{{ lookup.retained_bytes += 1L; true }}"',
    'let grow = @resources.grow_execution_reservation_capacity; "\\{grow(lookup.ledger, lookup.reservation, 1L, 1L) is Ok(_)}"',
  ]) {
    const extra = [['src/run_publication_host/new_interpolating_caller.mbt',
      `fn added(lookup : ClientKeyedLookupInput) -> String { ${body} }`]];
    assert(problems(guardedConstruction(''), extra).some(issue => issue.rule === 'unclassified-interpolation'));
    const addedFunction = guardedConstruction('') +
      `\nfn added(lookup : ClientKeyedLookupInput) -> String { ${body} }`;
    assert(problems(addedFunction).some(issue =>
      issue.function === 'added' && issue.rule === 'unclassified-interpolation'));
  }
  // Direct primitive references are also refused without an old inventory
  // entry or a recognizable parameter name/type at the interpolation site.
  const extra = [['src/run_publication_host/new_module.mbt',
    'fn added() -> String { "\\{@resources.reduce_execution_reservation(ledger, reservation, 1L) is Ok(_)}" }']];
  assert(problems(guardedConstruction(''), extra).some(issue => issue.rule === 'unclassified-interpolation'));
  const aliased = [['src/run_publication_host/new_alias.mbt',
    'fn added(ledger : Ledger, reservation : Reservation) -> String { let grow = @resources.grow_execution_reservation_capacity; "\\{grow(ledger, reservation, 1L, 1L) is Ok(_)}" }']];
  assert(problems(guardedConstruction(''), aliased).some(issue => issue.rule === 'unclassified-interpolation'));
  const globalAlias = [['src/run_publication_host/new_alias.mbt',
    'let grow = @resources.grow_execution_reservation_capacity\nfn added() -> String { "\\{grow(ledger, reservation, 1L, 1L) is Ok(_)}" }']];
  assert(problems(guardedConstruction(''), globalAlias).some(issue => issue.rule === 'unclassified-reservation-mutation'));
  const rawData = [['src/run_publication_host/new_data.mbt',
    'fn data() -> String {\n #|\\{grow_keyed_lookup_protocol_metadata(lookup)}\n }']];
  assert.deepEqual(problems(guardedConstruction(''), rawData), []);
});

test('actual finite keyed lifecycle inventory uses its owned construction boundaries', () => {
  const root = fileURLToPath(new URL('../', import.meta.url));
  assert.deepEqual(checkResourceLifecycle(root).problems, []);
});

test('managed scan guard keeps private phase and builder references inside the original wrapper', () => {
  for (const body of [
    'let grow = grow_keyed_body_construction',
    'grow_keyed_body_construction(foreign, capacity)',
    'keyed_body_construction_controls()',
  ]) assert(problems(guardedConstruction(body)).some(issue => issue.rule === 'manual-scan-phase'));
  for (const body of [
    'scan_keyed_lookup_identity_bodies(lookup, output, read, grow)',
    'let scan = scan_client_keyed_native_page',
  ]) assert(problems(guardedConstruction(body)).some(issue => issue.rule === 'unsettled-scan-builder'));
  assert(problems(guardedConstruction('let forged : KeyedBodyConstruction = foreign'))
    .some(issue => issue.rule === 'private-construction-forgery'));
  const source = 'fn construct(lookup : ClientKeyedLookupInput) -> Unit { () }';
  assert(resourceLifecycleProblems(new Map([[constructionModule, source]]), {
    inventory: [], scanInventory: constructionInventory,
  }).some(issue => issue.rule === 'missing-managed-scan'));
  for (const call of ['grow_keyed_body_construction', 'scan_client_keyed_native_whole_source']) {
    assert(problems(guardedConstruction(`let data = "\\{${call}(lookup)}"`))
      .some(issue => issue.rule === 'unclassified-interpolation'));
  }
});
