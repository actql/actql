// Finite specification model, independent of the product planner/evaluator.
import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {canonicalText} from './check-canonical-json.mjs';
import {machineCid} from './actql-spec-family.mjs';
import {contract} from './fixed-compute-capacity.mjs';
const fixture = JSON.parse(readFileSync('portability/corpus/fixed-compute-capacity.json', 'utf8'));
const bytes = value => Buffer.byteLength(canonicalText(value));
const number = value => typeof value === 'number' && Number.isFinite(value) && !Object.is(value, -0);
const fields = (row, names) => Object.keys(row).sort().join(',') === names;

function outputIssue(rows, c, expected) {
  if (rows.length > c.rows) return 'OutputRows';
  for (const row of rows) {
    if (!fields(row, 'id') || !number(row.id)) return 'OutputAdmission';
    if (bytes(row.id) > c.value_bytes) return 'OutputValue';
  }
  if (canonicalText(rows) !== canonicalText(expected)) return 'OutputMismatch';
  return 'Completed';
}

function run(mode, c) {
  const input = c.scan ?? fixture.scan;
  const fail = issue => ({issue, output:null, fixed_input:input});
  // A model of candidate eligibility, not an execution proof issued by a bool.
  if (mode === 'native' && c.common_fragment_rows !== undefined && !c.exact_fragment_meter)
    return fail('Ineligible');
  if (mode === 'native' && c.native_physical_stop) return fail('PhysicalBudget');
  if (input.length > c.rows) return fail('InputRows');
  if (c.common_fragment_rows !== undefined && input.length > c.common_fragment_rows)
    return fail('CommonFragmentRows');
  if (mode === 'local' && c.local_rows !== undefined && input.length > c.local_rows)
    return fail('LocalRows');
  for (const row of input) {
    if (!fields(row, 'amount,id') || !Object.values(row).every(number)) return fail('InputAdmission');
    if (Object.values(row).some(value => bytes(value) > c.value_bytes)) return fail('InputValue');
  }
  const output = [];
  for (const row of input) {
    const threshold = c.threshold ?? 1;
    const predicate = row.id > threshold;
    if ([row.id, threshold, predicate].some(value => bytes(value) > c.value_bytes)) return fail('RootValue');
    if (predicate) output.push({id:row.id});
  }
  const issue = outputIssue(output, c, c.output ?? fixture.output);
  return {issue, output:issue === 'Completed' ? output : null, fixed_input:input};
}

for (const c of fixture.cases) for (const mode of ['local', 'native']) test(`${mode}: ${c.name}`, () => {
  const expected = c[`expected_${mode}`] ?? c.expected;
  const result = run(mode, c);
  assert.equal(result.issue, expected);
  assert.equal(result.fixed_input, c.scan ?? fixture.scan);
  if (expected === 'Completed') assert.deepEqual(result.output, c.output ?? fixture.output);
  else assert.equal(result.output, null);
});

for (const c of fixture.invalid_native_outputs) test(c.name, () => {
  // Filter/select cannot legitimately increase rows; these are faulty backend
  // outputs, not a new accepted operation or an independently selected output cap.
  assert.equal(outputIssue(c.rows, {rows:2, value_bytes:5}, fixture.output), c.expected);
});

test('per-value bytes are not aggregate row width or transfer bytes', () => {
  assert.equal(bytes(fixture.scan), 43);
  assert.equal(bytes(fixture.scan[0]), 20);
  assert.deepEqual(Object.values(fixture.scan[0]).map(bytes), [2, 1]);
  assert.equal(bytes(fixture.output), 10);
  assert.equal(bytes(false), 5);
});

test('capacity and fragment selections bind the exact completed input and consumer owner', () => {
  const input = Object.freeze({rows:fixture.scan});
  const owner = Object.freeze({});
  const common_fragment = Object.freeze({owner, max_rows:2});
  const selection = {input, owner, parameters:'p', demand:'id > 1; select id',
    capacity_cid:contract.dependencies.consumer.cid, max_rows:2, max_value_bytes:5, common_fragment};
  const issued = new WeakMap();
  const request = Object.freeze({});
  issued.set(request, selection);
  const admit = (handle, expected) => {
    const retained = issued.get(handle);
    assert.ok(retained);
    for (const key of Object.keys(selection)) assert.equal(retained[key], expected[key], key);
  };
  admit(request, selection);
  assert.throws(() => admit({}, selection));
  assert.throws(() => admit(request, {...selection, input:Object.freeze({rows:fixture.scan})}));
  assert.throws(() => admit(request, {...selection, owner:Object.freeze({})}));
  assert.throws(() => admit(request, {...selection, common_fragment:Object.freeze({owner, max_rows:2})}));
  assert.throws(() => admit(request, {...selection, common_fragment:null}));
  for (const key of ['parameters', 'demand', 'capacity_cid'])
    assert.throws(() => admit(request, {...selection, [key]:'other'}));
  for (const key of ['max_rows', 'max_value_bytes'])
    assert.throws(() => admit(request, {...selection, [key]:selection[key] + 1}));
});

test('the existing consumer and fragment contracts retain their exact pins', () => {
  for (const dependency of Object.values(contract.dependencies)) {
    const body = JSON.parse(readFileSync(dependency.path, 'utf8'));
    const selected = dependency.pointer === '' ? body : body.schemas.fragment;
    assert.equal(machineCid(selected), dependency.cid);
  }
  assert.equal(contract.dependencies.consumer.cid,
    'sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f');
  assert.equal(contract.limits.rows.subject, 'all_candidates');
  assert.equal(contract.limits.local_fragment.subject, 'Local_realization_only_unless_also_selected_common');
});
