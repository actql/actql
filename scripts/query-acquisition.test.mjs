import {generateQueryEvidenceVectors} from './query-evidence-vectors.mjs';
import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import test from 'node:test';
import {machineCid} from './actql-spec-family.mjs';
import {canonicalText} from './check-canonical-json.mjs';
import {contract} from './query-acquisition-contract.mjs';
import {queryTimeAcquisitionVectors} from './query-time-acquisition-vectors.mjs';

const read = p => JSON.parse(readFileSync(p, 'utf8'));
const corpus = read('portability/corpus/query-acquisition.json');
const cid = machineCid;
const label = s => cid({fixture: s});
// Independently authored source projections, not product compiler output.
const expressionPin=read('spec/contracts/actql-aoa.json').expression_contract_cid;
const parameterType={type:'string'};
const stageSemantics={version:'actql-stage-semantics/0.1',expression_contract_cid:expressionPin,
  parameters:{wanted:parameterType},parameter_references:[{name:'wanted',path:'/steps/0/filter/eq/1',type:parameterType}],
  bindings:{},binding_references:[],local_body:{
    inputs:{records:{connector:'fixture',resource:'records',view:'scan',request:{tenant:'fixture'}}},
    steps:[{filter:{eq:[{field:'status'},{$param:'wanted'}]}},{select:['id'],as:'selected'}],
    results:{out:{from:'selected',fields:['id']}},effects:{}}};
const programSemantics={version:'actql-program-semantics/0.1',actql_version:'actql/0.1',
  expression_contract_cid:expressionPin,parameters:{wanted:parameterType},
  parameter_references:[{name:'wanted',path:'/stages/0/steps/0/filter/eq/1',type:parameterType}],
  bindings:{},binding_references:[],program_template:{
    stages:[{id:'first',stage_semantics_cid:cid(stageSemantics),after:'initial',imports:{}}],
    exports:{out:{from:{stage:'first',result:'out'}}}}};
const programDefinition={version:'actql-program-definition/0.1',id:'query.fixture',program_semantics_cid:cid(programSemantics)};
const owner = {program_source_cid: cid(programDefinition), stage: 'first', input: 'records'};
const ownerFixture={stage_semantics:stageSemantics,program_semantics:programSemantics,
  program_semantics_cid:cid(programSemantics),program_definition:programDefinition,
  program_definition_cid:cid(programDefinition),owner};
const ownerPath='portability/corpus/query-acquisition-owner.json';
if(process.argv.includes('--write')) writeFileSync(ownerPath,JSON.stringify(ownerFixture,null,2)+'\n');
test('query owner selects Program Definition rather than semantics',()=>{
  assert.deepEqual(read(ownerPath),ownerFixture);
  assert.notEqual(owner.program_source_cid,cid(programSemantics));
  const verify=candidate=>assert.equal(candidate.program_source_cid,cid(programDefinition));
  verify(owner);
  assert.throws(()=>verify({...owner,program_source_cid:cid(programSemantics)}));
  assert.throws(()=>verify({...owner,program_source_cid:cid({...programDefinition,id:'other'})}));
});
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

test('query-time owner extends only the complete legacy owner and retains old absent preimages', () => {
  const previous = read('scripts/fixtures/query-time-source/acquisition-predecessor.json');
  assert.equal(cid(previous), 'sha256:ad68f7ceafeed528a29c05e726db799d0031ef46152c0385f64468d38094c606');
  const stripped = structuredClone(contract);
  for (const schema of Object.values(stripped.schemas)) delete schema.properties.owner.properties.run_definition_cid;
  delete stripped.semantics.query_time_owner;
  assert.deepEqual(stripped, previous, 'all other complete legacy contract fields remain exact');
  assert.equal(Object.hasOwn(requirement.owner, 'run_definition_cid'), false);
  assert.ok(matches(previous.schemas.requirement, requirement));
  assert.ok(matches(contract.schemas.requirement, requirement));
});

test('independent query-time requirement and observation bind one Run, not equal query data', () => {
  const records = queryTimeAcquisitionVectors(read('portability/corpus/query-acquisition-identities.json'));
  assert.deepEqual(read('portability/corpus/query-time-acquisition-identities.json'), records);
  const [first, completed, second, foreign] = records.map(row => row.body);
  for (const value of [first, second]) assert.ok(matches(contract.schemas.requirement, value));
  for (const value of [completed, foreign]) assert.ok(matches(contract.schemas.completed_observation, value));
  const original = (capture, required) => capture.requirement_cid === cid(required) &&
    canonicalText(capture.owner) === canonicalText(required.owner);
  assert.ok(original(completed, first));
  assert.equal(original(foreign, first), false);
  assert.notEqual(cid(first), cid(second));
  assert.deepEqual(first.filter, second.filter);
  assert.deepEqual(first.request, second.request);
  assert.deepEqual(completed.output, foreign.output);
  const absent = structuredClone(completed); delete absent.owner.run_definition_cid;
  assert.equal(original(absent, first), false);
  for (const invalid of [null, false, 'now', '', first.owner.run_definition_cid.toUpperCase()]) {
    for (const [schema, body] of [['requirement', first], ['completed_observation', completed]]) {
      const value = structuredClone(body); value.owner.run_definition_cid = invalid;
      assert.equal(matches(contract.schemas[schema], value), false);
    }
  }
});

test('current query fixtures change only declared containing-expression and evidence identities', () => {
  const prior = read('scripts/fixtures/query-time-source/acquisition-instance-predecessor.json');
  const restore = (current, original, paths) => {
    const restored = structuredClone(current);
    for (const path of paths) {
      const keys = path.split('/'); let target = restored, saved = original;
      for (const key of keys.slice(0, -1)) {target = target[key]; saved = saved[key];}
      target[keys.at(-1)] = structuredClone(saved[keys.at(-1)]);
    }
    assert.deepEqual(restored, original);
  };
  const originalOwner = prior['query-acquisition-owner'];
  assert.equal(originalOwner.stage_semantics.expression_contract_cid,
    'sha256:707fd38ee8c0e32b24b700b55364414362b6cbf01f99405d4fde455a8243cd35');
  restore(read(ownerPath), originalOwner, ['stage_semantics/expression_contract_cid',
    'program_semantics/expression_contract_cid',
    'program_semantics/program_template/stages/0/stage_semantics_cid',
    'program_semantics_cid','program_definition/program_semantics_cid',
    'program_definition_cid','owner/program_source_cid']);
  const paths = [['owner/program_source_cid'],
    ['owner/program_source_cid','requirement_cid','actual_access/scope_cid'],
    ['owner/program_source_cid','requirement_cid','actual_access/scope_cid'], [],
    ['requirement_cid'], ['requirement_cid'], ['expression_contract_cid'],
    ['expression_contract_cid','program_template/stages/0/stage_semantics_cid'], ['program_semantics_cid']];
  const current = read('portability/corpus/query-acquisition-identities.json');
  assert.equal(current.length, paths.length);
  for (const [i, row] of current.entries()) {
    assert.equal(cid(row.body), row.cid);
    const old = prior['query-acquisition-identities'][i]; assert.equal(cid(old.body), old.cid);
    restore(row.body, old.body, paths[i]);
  }
  for (const [i, row] of read('portability/corpus/query-process-evidence.json').entries()) {
    assert.equal(cid(row.body), row.cid);
    restore(row.body, prior['query-process-evidence'][i].body,
      ['requirement_cid','actual_access/scope_cid']);
  }
  const two = read('portability/corpus/query-two-receipt.json'), oldTwo = prior['query-two-receipt'];
  restore(two.requirement.body, oldTwo.requirement.body, ['owner/program_source_cid']);
  for (const [i, row] of two.receipts.entries()) {
    assert.equal(cid(row.body), row.cid); restore(row.body, oldTwo.receipts[i].body, ['requirement_cid']);
  }
  for (const [i, row] of two.records.entries()) {
    assert.equal(cid(row.body), row.cid); restore(row.body, oldTwo.records[i].body, ['requirement_cid','accesses']);
  }
  assert.equal(cid(two.observation.body), two.observation.cid);
  restore(two.observation.body, oldTwo.observation.body, ['owner/program_source_cid',
    'requirement_cid','accesses','evidence_contract_cid','coverage/source_validation_evidence_cid',
    'coverage/filter_evidence_cid','coverage/select_evidence_cid']);
});

test('named query fixtures bind complete current bodies and expression identity', () => {
  const expression = read('spec/contracts/actql-expressions.json');
  assert.equal(expressionPin, cid(expression));
  const current = read(ownerPath);
  assert.deepEqual(current, ownerFixture,
    'The owner preimages are independently authored above, not compiler output');
  assert.equal(current.stage_semantics.expression_contract_cid, expressionPin);
  assert.equal(current.program_semantics.expression_contract_cid, expressionPin);
  assert.equal(current.program_semantics_cid, cid(current.program_semantics));
  assert.equal(current.program_definition.program_semantics_cid, current.program_semantics_cid);
  assert.equal(current.program_definition_cid, cid(current.program_definition));
  assert.equal(current.owner.program_source_cid, current.program_definition_cid);
  for (const name of ['query-acquisition-identities', 'query-process-evidence',
    'query-two-receipt', 'query-time-acquisition-identities']) {
    const value = read(`portability/corpus/${name}.json`);
    const records = Array.isArray(value) ? value
      : [value.requirement, ...value.receipts, ...value.records, value.observation];
    assert.ok(records.length > 0, name);
    for (const record of records) {
      assert.equal(cid(record.body), record.cid, name);
      if (Object.hasOwn(record.body, 'expression_contract_cid')) {
        assert.equal(record.body.expression_contract_cid, expressionPin, name);
      }
    }
  }
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
  accessScope('native',corpus.expected_output),accessScope('broad',corpus.rows),
  stageSemantics,programSemantics,programDefinition].map(body => ({body,cid:cid(body)}));
const vectorPath = 'portability/corpus/query-acquisition-identities.json';
// Independent canonical JSON oracle; never reads product output.
if (process.argv.includes('--write')) writeFileSync(vectorPath,JSON.stringify(vectors,null,2)+'\n');
if (process.argv.includes('--write')) {
  const queryTime = queryTimeAcquisitionVectors(vectors);
  writeFileSync('portability/corpus/query-time-acquisition-identities.json', JSON.stringify(queryTime, null, 2) + '\n');
  writeFileSync('src/canonical_json/query_time_acquisition.generated_test.mbt',
    generateQueryEvidenceVectors('query_time_acquisition', queryTime));
}
test('fixed preimages and CIDs match independent canonical JSON oracle', () => assert.deepEqual(read(vectorPath),vectors));
test('public derivation names the exact shared contract', () => {
  assert.ok(readFileSync('src/sourceview_resolution/query_acquisition.mbt','utf8').includes(cid(contract)));
});
const moon = generateQueryEvidenceVectors('acquisition', vectors);
const moonPath = 'src/canonical_json/query_acquisition.generated_test.mbt';
if (process.argv.includes('--write')) writeFileSync(moonPath,moon);
test('three-target identity fixture is not stale', () => assert.equal(readFileSync(moonPath,'utf8'),moon));
