import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {gunzipSync} from 'node:zlib';
import {createHash} from 'node:crypto';
import test from 'node:test';
import {verifyIdentity} from './check-canonical-json.mjs';
import {machineCid} from './actql-spec-family.mjs';
const read = path => JSON.parse(readFileSync(path, 'utf8'));
const history = JSON.parse(gunzipSync(readFileSync('scripts/fixtures/pre-int64-comparison-literal-identities.json.gz')));
const vectors = read('portability/corpus/int64-comparison-literals.json');
const prior = history.records['spec/contracts/actql-expressions.json'];
const current = read('spec/contracts/actql-expressions.json');
const priorCid = 'sha256:ed54dd0a56f4bfc7811a600db137ae5b32b24c2819a81ab69c7c5f06d349da7b';
const currentCid = 'sha256:707fd38ee8c0e32b24b700b55364414362b6cbf01f99405d4fde455a8243cd35';
// Effect literal DATA keys keep their exact code units. General canonical JSON
// identifier normalization is a different owner and cannot verify this body.
const exactLiteralData=value=>Array.isArray(value)?'['+value.map(exactLiteralData).join(',')+']'
  :value!==null&&typeof value==='object'?'{'+Object.keys(value).sort()
    .map(key=>JSON.stringify(key)+':'+exactLiteralData(value[key])).join(',')+'}'
    :JSON.stringify(value);


test('comparison extension retains the complete predecessor expression and only two explicit law positions change', () => {
  verifyIdentity(prior, priorCid);
  verifyIdentity(current, currentCid);
  assert.equal(history.expression_contract_cid, priorCid);
  assert.equal(vectors.prior_expression_contract_cid, priorCid);
  assert.equal(vectors.current_expression_contract_cid, currentCid);
  const restored = structuredClone(current);
  delete restored.laws.signed64_comparison_context;
  restored.laws.lowering = prior.laws.lowering;
  assert.deepEqual(restored, prior, 'grammar, literal bodies, signatures and all other laws remain exact');
  assert.deepEqual(current.laws.signed64_comparison_context.predicates,
    ['eq','neq','lt','lte','gt','gte','between','is_distinct_from','in','not_in']);
  for (const field of ['evidence','admission','normalization','lowering','separation'])
    assert.equal(typeof current.laws.signed64_comparison_context[field], 'string');
  assert.equal(createHash('sha256').update(readFileSync('scripts/fixtures/pre-int64-comparison-literal-identities.json.gz')).digest('hex'), vectors.history_archive_sha256);
});

test('fixed Number normalization and exact signed64 wire preimages remain distinct', () => {
  for (const c of vectors.literals) {
    const number = JSON.parse(c.source_number);
    assert(Number.isFinite(number) && Number.isInteger(number));
    assert.equal(JSON.stringify(number), c.normalized_number);
    const exact = BigInt(number);
    assert(exact >= -(1n << 63n) && exact < (1n << 63n));
    assert.equal(Number(exact), number);
    assert.equal(exact.toString(), c.signed64);
    verifyIdentity(c.lowered_body, c.lowered_cid, c.lowered_preimage);
  }
  for (const text of vectors.rejected_numbers) {
    const number = JSON.parse(text);
    assert(!Number.isInteger(number) || number < -(2 ** 63) || number >= 2 ** 63);
  }
  const ordinary = vectors.ordinary_number_literal;
  verifyIdentity(ordinary.body, ordinary.cid, ordinary.canonical_preimage);
  assert.notEqual(ordinary.cid, vectors.literals[0].lowered_cid);
  assert.equal(vectors.literals[2].signed64, vectors.literals[3].signed64,
    'a raw spelling cannot recover precision lost by Number normalization');
});

test('original typed int64 Parameters retain four independent full-domain identities', () => {
  const identities = new Set();
  for (const c of vectors.typed_parameters) {
    const integer = BigInt(c.value);
    assert(integer >= -(1n << 63n) && integer < (1n << 63n));
    verifyIdentity(c.identity_body, c.cid, c.canonical_preimage);
    assert.deepEqual(c.identity_body, {$actql_value:['int64', c.value]});
    identities.add(c.cid);
  }
  assert.equal(identities.size, 4);
  assert.notEqual(vectors.typed_parameters[1].cid, vectors.typed_parameters[2].cid);
});

function programEnvelope(stages, cid, mode, accepted) {
  const [a,b] = stages.cases.slice(0,2).map(c => structuredClone(c.envelope));
  const port = mode === 1 ? {result:{stage:'a',result:'r'}} : mode === 2 ? {receipt:{stage:'a',effect:'d'}} : null;
  if (port) b.local_body.inputs.rows = port;
  return {version:'actql-program-semantics/0.1', actql_version:'actql/0.1', expression_contract_cid:cid,
    parameters:a.parameters,bindings:a.bindings,
    parameter_references:[a,b].flatMap((s,i)=>s.parameter_references.map(r=>({...r,path:`/stages/${i}${r.path}`}))),
    binding_references:a.binding_references.map(r=>({...r,path:`/stages/0${r.path}`})),
    program_template:{stages:[{id:'a',after:'initial',imports:{},stage_semantics_cid:machineCid(a)},
      {id:'b',after:accepted?'accepted':'completed',imports:port?{rows:port}:{},stage_semantics_cid:machineCid(b)}],
      exports:{out:{from:{stage:'b',result:'r'}}}}};
}

test('complete old Stage Program and Definition preimages remain verifiable without compiler output', () => {
  const records = history.records;
  const oldStages = records['portability/corpus/stage-semantics.json'];
  for (const name of ['stage-semantics','local-unit-stage-body']) {
    for (const c of records[`portability/corpus/${name}.json`].cases) {
      assert.equal(c.envelope.expression_contract_cid, priorCid);
      verifyIdentity(c.envelope, c.expected_cid);
    }
  }
  for (const c of records['portability/corpus/stage-definition.json'].cases) {
    const stage = oldStages.cases.find(s=>s.name===c.stage_case);
    verifyIdentity({version:'actql-stage-definition/0.1',id:c.id,stage_semantics_cid:stage.expected_cid}, c.expected_cid);
  }
  for (const c of records['portability/corpus/program-semantics.json'].cases)
    verifyIdentity(programEnvelope(oldStages, priorCid, c.import_mode, c.accepted), c.expected_cid);
  for (const c of records['portability/corpus/program-definition.json'].cases) {
    const program = records['portability/corpus/program-semantics.json'].cases.find(p=>p.import_mode===c.import_mode&&p.accepted===c.accepted);
    verifyIdentity({version:'actql-program-definition/0.1',id:c.id,program_semantics_cid:program.expected_cid}, c.expected_cid);
  }
  assert.deepEqual(read('portability/corpus/stage-parameter-declarations.json'), records['portability/corpus/stage-parameter-declarations.json']);
  for (const name of ['stage-semantics','local-unit-stage-body']) {
    const expected = structuredClone(records[`portability/corpus/${name}.json`]);
    for (const c of expected.cases) {
      c.envelope.expression_contract_cid = currentCid;
      c.expected_cid = machineCid(c.envelope);
    }
    assert.deepEqual(read(`portability/corpus/${name}.json`), expected);
  }
});

test('complete prior current Effect literal Stage Program and Definition bodies retain their old identities', () => {
  assert.equal(history.effect_current_preimages.length, 10);
  assert.equal(history.effect_current_preimages[0].definition.cid,
    'sha256:f409712b9a5e01f2c11bb14bd785fa41fd2e42cbcd46d41650c2cf29d4760f34');
  const original = read('portability/corpus/effect-literal-key-identities.json');
  for (const [i,c] of history.effect_current_preimages.entries()) {
    assert.equal(c.name, original.cases[i].name);
    assert.deepEqual(c.payload, original.cases[i].payload);
    assert.deepEqual(c.stage.body.local_body, original.cases[i].stage_envelope.local_body);
    for (const role of ['stage','program','definition']) {
      assert.equal(exactLiteralData(c[role].body),c[role].canonical_preimage);
      assert.equal('sha256:'+createHash('sha256').update(c[role].canonical_preimage,'utf8').digest('hex'),c[role].cid);
    }
    assert.equal(c.stage.body.expression_contract_cid,priorCid);
    assert.equal(c.program.body.expression_contract_cid,priorCid);
    assert.equal(c.program.body.program_template.stages[0].stage_semantics_cid,c.stage.cid);
    assert.equal(c.definition.body.program_semantics_cid,c.program.cid);
  }
});

test('the containing AoA and selected registry change only their explicit expression dependency edges', () => {
  const expected=structuredClone(history.records['spec/contracts/actql-aoa.json']);
  const registry=structuredClone(history.records['spec/dependencies/aoa-pipeline-registry.json']);
  expected.expression_contract_cid=currentCid;
  for (const name of ['ACTQL.expression_fragment/0.1','REL.derive.ordered']) {
    const body=expected.execution_contracts[name];
    assert.equal(body.dependencies.expression_contract.cid,priorCid);
    body.dependencies.expression_contract.cid=currentCid;
    if (name==='REL.derive.ordered') {
      const pin=machineCid(body);
      expected.target_registry_requirements['REL.derive'].execution_extensions.ordered_bindings.cid=pin;
      registry['REL.derive'].execution_extensions.ordered_bindings.cid=pin;
    } else {
      const pin=machineCid(body);
      expected.target_registry_requirements[name].execution_contract.cid=pin;
      registry[name].execution_contract.cid=pin;
    }
  }
  expected.pipeline_registry_cid=machineCid(registry);
  assert.deepEqual(read('spec/dependencies/aoa-pipeline-registry.json'),registry);
  assert.deepEqual(read('spec/contracts/actql-aoa.json'),expected);
});
