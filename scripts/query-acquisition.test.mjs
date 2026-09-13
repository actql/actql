import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import test from 'node:test';
import {machineCid} from './actql-spec-family.mjs';
import {canonicalText} from './check-canonical-json.mjs';
import {contract} from './query-acquisition-contract.mjs';

const read = p => JSON.parse(readFileSync(p, 'utf8'));
const corpus = read('portability/corpus/query-acquisition.json');
const cid = machineCid;
const label = s => cid({fixture: s});
const owner = {program_source_cid: label('program'), stage: 'first', input: 'records'};
const parameters = {version: 'actql-parameter-values/0.1', values: {wanted: 'open'}};
const requirement = {
  version: 'actql-query-acquisition/0.1', owner, source_ref: 'connector://fixture/records#scan',
  source_contract_cid: label('source'), input_contract_cid: cid(corpus.fields),
  output_contract_cid: cid({id: corpus.fields.id}), request: {tenant: 'fixture'},
  parameter_values_cid: cid(parameters),
  filter: {occurrence: '/steps/0/filter', expression_cid: cid({eq: [{field: 'status'}, {$param: 'wanted'}]})},
  select: {occurrence: '/steps/1/select', fields: [{input: 'id', output: 'id'}]},
  source_validation: {scope: 'selected_scan', fields: ['amount', 'id', 'status']},
  source_order_cid: cid({fixture_order: corpus.source_order}),
  logical_guards: {max_rows: 2, max_value_bytes: 1000},
};
const snapshot = {contract_cid: label('snapshot-contract'), token_cid: label('snapshot-token')};
const scanScope = {version:'actql-query-scan-scope/0.1',source_ref:requirement.source_ref,
  source_contract_cid:requirement.source_contract_cid,resolved_request_cid:cid(requirement.request)};
function accessScope(strategy, received) {
  return {version:'actql-query-access-scope/0.1',requirement_cid:cid(requirement),
    received_rows_cid:cid(received),received_fields:strategy === 'native' ? ['id'] : ['amount','id','status']};
}
// This is a fixed mock source/attestor, not a provider or product lowerer.
function observation(strategy, rows = corpus.rows) {
  const output = rows.filter(r => r.status === 'open').map(r => ({id: r.id}));
  const received = strategy === 'native' ? output : rows;
  return {
    version: 'actql-query-observation/0.1', requirement_cid: cid(requirement), owner,
    source_ref: requirement.source_ref, source_contract_cid: requirement.source_contract_cid,
    parameter_values_cid: requirement.parameter_values_cid, resolved_request_cid: cid(requirement.request),
    snapshot, actual_access: {scope_cid: cid(accessScope(strategy,received)), provider_scope_cid: null,
      received_rows: received.length, received_fields: strategy === 'native' ? ['id'] : ['amount', 'id', 'status'],
      received_bytes: Buffer.byteLength(canonicalText(received))},
    coverage: {scope_cid: cid(scanScope), complete: true,
      source_validation_evidence_cid: label('verified-source-admission'),
      filter_evidence_cid: label('verified-filter'), select_evidence_cid: label('verified-select')},
    output: {contract_cid: requirement.output_contract_cid, rows_cid: cid(output), row_count: output.length},
    retention: 'process',
  };
}

// Independent small interpreter for the exact schema vocabulary used here.
function matches(s, v) {
  if (s.const !== undefined && canonicalText(s.const) !== canonicalText(v)) return false;
  if (s.anyOf && !s.anyOf.some(x => matches(x,v))) return false;
  if (s.type) {
    const actual = v === null ? 'null' : Array.isArray(v) ? 'array' : typeof v;
    if (s.type === 'integer' ? !Number.isSafeInteger(v) : actual !== s.type) return false;
  }
  if (typeof v === 'string' && ((s.minLength && [...v].length < s.minLength) || (s.pattern && !new RegExp(s.pattern).test(v)))) return false;
  if (typeof v === 'number' && (v < (s.minimum ?? -Infinity) || v > (s.maximum ?? Infinity))) return false;
  if (Array.isArray(v)) {
    if (v.length < (s.minItems ?? 0)) return false;
    if (s.uniqueItems && new Set(v.map(canonicalText)).size !== v.length) return false;
    if (s.items && !v.every(x => matches(s.items,x))) return false;
  } else if (v !== null && typeof v === 'object') {
    if ((s.required ?? []).some(k => !Object.hasOwn(v,k))) return false;
    for (const [k,x] of Object.entries(v)) {
      if (s.properties?.[k]) { if (!matches(s.properties[k],x)) return false; }
      else if (s.additionalProperties === false) return false;
    }
  }
  return true;
}
function admit(o, expectedSnapshot = snapshot, verified = true) {
  if (!matches(contract.schemas.completed_observation,o)) return 'Shape';
  if (!verified) return 'UnverifiedEvidence';
  if (o.requirement_cid !== cid(requirement) || canonicalText(o.owner) !== canonicalText(owner) ||
    o.source_ref !== requirement.source_ref || o.source_contract_cid !== requirement.source_contract_cid ||
    o.parameter_values_cid !== requirement.parameter_values_cid || o.resolved_request_cid !== cid(requirement.request) ||
    canonicalText(o.snapshot) !== canonicalText(expectedSnapshot)) return 'ForeignObservation';
  if (o.coverage.scope_cid !== cid(scanScope) || o.coverage.filter_evidence_cid !== label('verified-filter')) return 'IncompleteCoverage';
  if (o.coverage.source_validation_evidence_cid !== label('verified-source-admission') ||
    o.coverage.select_evidence_cid !== label('verified-select')) return 'UnverifiedEvidence';
  const received = [['native',corpus.expected_output],['broad',corpus.rows]].find(
    ([strategy,rows]) => cid(accessScope(strategy,rows)) === o.actual_access.scope_cid);
  if (!received || o.actual_access.received_rows !== received[1].length ||
    o.actual_access.received_bytes !== Buffer.byteLength(canonicalText(received[1])) ||
    canonicalText(o.actual_access.received_fields) !== canonicalText(accessScope(...received).received_fields)) return 'AccessMismatch';
  if (o.output.contract_cid !== requirement.output_contract_cid || o.output.rows_cid !== cid(corpus.expected_output) ||
    o.output.row_count !== corpus.expected_output.length) return 'OutputMismatch';
  return 'complete';
}
test('fixed native and residual realizations preserve result, not access identity', () => {
  const n = observation('native'), b = observation('broad');
  assert.ok(matches(contract.schemas.requirement,requirement));
  assert.equal(admit(n),'complete'); assert.equal(admit(b),'complete');
  assert.deepEqual(n.output,b.output); assert.notEqual(cid(n),cid(b));
  assert.equal(n.actual_access.received_rows,2); assert.equal(b.actual_access.received_rows,3);
  assert.deepEqual(corpus.expected_output.filter(r => r.id === 'c'),corpus.expected_consumer);
  assert.equal(cid({b:2,a:1}),cid({a:1,b:2}));
  assert.notEqual(cid(corpus.expected_output),cid([...corpus.expected_output].reverse()));
  assert.notEqual(cid(corpus.expected_output),cid([...corpus.expected_output,corpus.expected_output[0]]));
});

test('closed shapes reject unknown/missing fields and proposals', () => {
  for (const [name, value] of [['requirement',requirement],['completed_observation',observation('broad')]]) {
    const s = contract.schemas[name];
    for (const key of s.required) { const v = {...value}; delete v[key]; assert.equal(matches(s,v),false,key); }
    assert.equal(matches(s,{...value,validated:true}),false);
  }
  assert.equal(matches(contract.schemas.completed_observation,{...observation('broad'),retention:'durable'}),false);
  assert.equal(admit(observation('native'),snapshot,false),'UnverifiedEvidence');
  for (const key of ['received_rows','received_bytes']) {
    const o = structuredClone(observation('broad')); o.actual_access[key]--;
    assert.equal(admit(o),'AccessMismatch');
  }
  const wrong = structuredClone(observation('broad')); wrong.output.row_count = 3;
  assert.equal(admit(wrong),'OutputMismatch');
});

for (const c of corpus.cases) test(c.id, () => {
  const rows = structuredClone(corpus.rows);
  if (c.mutation === 'invalid_unused') rows[1].amount = 'invalid';
  if (c.mutation === 'division_by_zero') rows[1].amount = 0;
  let outcome = 'complete', retained = false;
  const received = c.strategy === 'native' ? 2 : 3;
  if (received > (c.physical_rows ?? 100)) outcome = 'PhysicalBudget';
  else if (rows.some(r => typeof r.id !== 'string' || typeof r.status !== 'string' || typeof r.amount !== 'number')) outcome = 'SourceAdmission';
  else if (c.mutation === 'division_by_zero' && rows.some(r => r.amount === 0)) outcome = 'ExpressionFailure';
  else if (2 > (c.logical_rows ?? 2)) outcome = 'LogicalGuard';
  else {
    const o = structuredClone(observation(c.strategy));
    if (c.mutation === 'foreign_owner') o.owner.input = 'other';
    if (c.mutation === 'foreign_parameter') o.parameter_values_cid = label('other-values');
    if (c.mutation === 'foreign_request') o.resolved_request_cid = label('other-request');
    if (c.mutation === 'foreign_snapshot') o.snapshot.token_cid = label('other-snapshot');
    if (c.mutation === 'without_snapshot') o.snapshot = null;
    if (c.mutation === 'missing_residual') o.coverage.filter_evidence_cid = label('prefilter-only');
    outcome = admit(o,c.mutation === 'without_snapshot' ? null : snapshot,c.mutation !== 'proposal_only');
    if (outcome === 'complete') {
      if (c.mutation === 'acquisition_cancel') outcome = 'Cancelled';
      else if (c.mutation === 'capture_failure') outcome = 'CaptureFailure';
      else {
        retained = true;
        if (c.mutation === 'fresh_consumer') outcome = 'FreshRead';
        if (c.mutation === 'consumer_failure') outcome = 'ConsumerFailure';
      }
    }
  }
  assert.equal(outcome,c.outcome);
  if (c.retained_observation) assert.equal(retained,true);
  if (c.received_rows) assert.equal(received,c.received_rows);
});

const vectors = [requirement, observation('native'), observation('broad'),scanScope,
  accessScope('native',corpus.expected_output),accessScope('broad',corpus.rows)].map(body => ({body,cid:cid(body)}));
const vectorPath = 'portability/corpus/query-acquisition-identities.json';
// Independent canonical JSON oracle; never reads product output.
if (process.argv.includes('--write')) writeFileSync(vectorPath,JSON.stringify(vectors,null,2)+'\n');
test('fixed preimages and CIDs match independent canonical JSON oracle', () => assert.deepEqual(read(vectorPath),vectors));
test('public derivation names the exact shared contract', () => {
  assert.ok(readFileSync('src/sourceview_resolution/query_acquisition.mbt','utf8').includes(cid(contract)));
});
const moon = ['// Generated from the independent query-acquisition fixtures; do not edit.', ''];
for (const [i,v] of vectors.entries()) {
  moon.push('///|', `test "query acquisition preimage ${i}" {`,
    `  let input = @json.parse(${JSON.stringify(canonicalText(v.body))})`,
    '  let value = @canonical_json.from_json(input, 10000, 100, 100000)',
    `  assert_eq(@canonical_json.cid_value(value, 100000, 10000, 100), ${JSON.stringify(v.cid)})`,
    '}', '');
}
const moonPath = 'src/canonical_json/query_acquisition.generated_test.mbt';
if (process.argv.includes('--write')) writeFileSync(moonPath,moon.join('\n'));
test('three-target identity fixture is not stale', () => assert.equal(readFileSync(moonPath,'utf8'),moon.join('\n')));
