import assert from 'node:assert/strict';
const path = 'src/connectors/local/selected_relation_provider.mbt';
const suite = 'src/connectors/local/relation_chain_lifetime_wbtest.mbt';
const clean = '  match cleanup_managed_provider(active) {\n    Ok(true) => {\n      // Output provenance retains exact identities, not the child execution.';
const ordinary = 'built-in chains reclaim each intermediate execution and preserve exact outputs';
const retry = 'intermediate cleanup false and error preserve child custody until parent retry';
export const retirementCases = Object.freeze([
  ['intermediate-cleanup-omitted', path, clean,
    '  let premature : Result[Bool, @connector.FixedComputeIssue] = Ok(true)\n  match premature {\n    Ok(true) => {\n      // Output provenance retains exact identities, not the child execution.',
    suite, ordinary, 'assert_eq(cleanups[before], 1)'],
  ['intermediate-cleanup-repeated', path, clean,
    '  match cleanup_managed_provider(active) {\n    Ok(true) => {\n      cleanup_managed_provider(active) |> ignore\n      // Output provenance retains exact identities, not the child execution.',
    suite, ordinary, 'assert_eq(cleanups[before], 1)'],
  ['pending-cleanup-starts-successor', path,
    'Ok(false) => return Ok(managed_provider_waiting(0L, 0L))', 'Ok(false) => ()',
    suite, retry, 'assert_true(\n      advance_managed_provider(active, 1).unwrap() is Waiting(work=0L, ..),'],
].map(row => Object.freeze(row)));

// Default CI retains every original recipe and adds the three shared-owner
// cases. The local subset is explicit and writes a distinct report.
export function selectCases(cases, args) {
  assert(args.length <= 1 && ['all', 'retirement'].includes(args[0] ?? 'all'), 'Use all or retirement');
  assert.equal(new Set(cases.map(row => row[0])).size, cases.length, 'Duplicate mutation');
  const selected = args[0] === 'retirement' ? cases.filter(row => retirementCases.some(r => r[0] === row[0])) : cases;
  assert(selected.length > 0, 'Empty mutation selection');
  assert(retirementCases.every(row => selected.some(r => r[0] === row[0])), 'Missing shared retirement mutation');
  return selected;
}

export function retirementWitness(recipe, fixture) {
  const [id, , , , suite, name, anchor] = recipe;
  const start = fixture.indexOf(`test "${name}" {`);
  assert(start >= 0 && fixture.split(`test "${name}" {`).length === 2, 'Missing unique authored test');
  const next = fixture.indexOf('\ntest "', start + 1), end = next < 0 ? fixture.length : next;
  const body = fixture.slice(start, end);
  assert(body.split(anchor).length === 2, 'Missing unique intended assertion');
  const position = start + body.indexOf(anchor);
  return {id, suite, test: name, line: fixture.slice(0, position).split('\n').length, assertion: anchor};
}

export function requireRetirementDetection(result, output, witness) {
  assert(!result.error && !result.signal && Number.isSafeInteger(result.status) && result.status > 0, 'Process failure is not assertion detection');
  assert(!/Error: \[\d+\]/u.test(output), 'Compile failure is not assertion detection');
  assert.match(output, /Total tests: 1, passed: 0, failed: 1\./u, 'Exactly the authored test must fail');
  const lines = output.split(/\r?\n/u);
  assert(lines.some(line => line.includes(`("${witness.test}") failed:`) &&
    line.includes(`${witness.suite}:${witness.line}:`) && line.includes('FAILED:')),
    'The intended ownership assertion did not fail');
}
