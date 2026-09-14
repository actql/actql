import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import {componentLimitModel} from './components-limit-model.mjs';
import {traversalLimitModel} from './traversal-limit-model.mjs';

const read = (path) => JSON.parse(readFileSync(new URL(path, import.meta.url), 'utf8'));
const vectors = read('../portability/corpus/publication-limit-subjects.json');
const policyContract = read('../spec/contracts/actql-capacity-host-policy.json');
// This oracle uses Node's serializer and crypto, not a compiler/lowerer emitter.
function canonical(value) {
  if (Array.isArray(value)) return value.map(canonical);
  if (value !== null && typeof value === 'object') {
    return Object.fromEntries(Object.keys(value).sort().map((key) => [key, canonical(value[key])]));
  }
  return value;
}
const cid = (value) => `sha256:${createHash('sha256').update(JSON.stringify(canonical(value))).digest('hex')}`;

test('traversal authored guards preserve non-binding candidates and independent search scopes', () => {
  const policy=Object.fromEntries(policyContract.schema.required.filter(k=>k!=='version').map(k=>[k,1000]));
  Object.assign(policy,{version:'actql-capacity-host-policy/0.1',max_graph_construction_input_rows:1000,max_graph_construction_nodes:1000,max_graph_construction_edges:1000});
  for (const {unit,guard,...expected} of read('../portability/corpus/traversal-guard-subjects.json').cases) {
    const actual=traversalLimitModel(policy,unit,false,guard);
    assert.deepEqual(actual,expected);
    assert.equal(actual.limit_cids[0],traversalLimitModel(policy,unit).limit_cids[0]);
    assert.equal(actual.limits[1].effective_max,Math.min(1000,guard));
    const foreign=traversalLimitModel(policy,'sha256:'+'1'.repeat(64),false,guard);
    assert.deepEqual(actual.host_cids,foreign.host_cids);
    assert.notEqual(actual.limit_cids[1],foreign.limit_cids[1]);
  }
});

test('traversal limits retain independent scopes and producer Unit namespaces', () => {
  for (const v of read('../portability/corpus/traversal-limit-subjects.json').cases) {
    const policy = Object.fromEntries(policyContract.schema.required.filter(k=>k!=='version').map(k=>[k,1000]));
    Object.assign(policy,{version:'actql-capacity-host-policy/0.1',max_graph_construction_input_rows:1000,
      max_graph_construction_nodes:1000,max_graph_construction_edges:1000,max_graph_output_rows:v.cap});
    const {limits,...actual}=traversalLimitModel(policy,v.unit);
    const {unit,cap,...expected}=v;
    assert.deepEqual(actual,expected);
    assert.notEqual(actual.limit_cids[0],actual.limit_cids[1]);
    const foreign=traversalLimitModel(policy,'sha256:'+'2'.repeat(64));
    assert.deepEqual(foreign.host_cids,actual.host_cids);
    assert.notDeepEqual(foreign.limit_cids,actual.limit_cids);
    const repeated=traversalLimitModel(policy,unit,true);
    assert.deepEqual(repeated.limits.map(l=>l.effective_max),limits.map(l=>l.effective_max));
    assert.notDeepEqual(repeated.limit_cids,actual.limit_cids);
    assert.notEqual(cid({...limits[0],subject_ref:'traverse:checked-step:3:paths'}),actual.limit_cids[0]);
  }
});

test('components limits rebuild Unit candidates while retaining Host identity and repetitions', () => {
  const corpus = read('../portability/corpus/components-limit-subjects.json');
  for (const v of corpus.cases) {
    const policy = Object.fromEntries(policyContract.schema.required.filter(k=>k!=='version').map(k=>[k,1000]));
    Object.assign(policy, {version:'actql-capacity-host-policy/0.1', max_graph_construction_input_rows:1000,
      max_graph_construction_nodes:1000, max_graph_construction_edges:1000, max_graph_output_rows:v.cap});
    const {limits,...actual} = componentLimitModel(policy,v.unit,v.rows);
    const {unit,rows,cap,...expected} = v;
    assert.deepEqual(actual,expected);
    assert.equal(limits[0].effective_max, rows);
    assert.equal(limits[1].effective_max, Math.min(rows,cap));
    assert.notEqual(actual.limit_cids[0], actual.limit_cids[1]);
    for(const limit of limits) {
      assert.notEqual(cid({...limit,subject_ref:'components:checked-step:3'}),cid(limit));
      assert.notEqual(cid({...limit,enforcement:'unit_preflight'}),cid(limit));
    }
    const repeated = componentLimitModel(policy,unit,rows,true);
    assert.equal(repeated.host_cid,actual.host_cid);
    assert.equal(repeated.limits[1].effective_max,limits[1].effective_max);
    assert.equal(repeated.limits[1].candidates.length,3);
    assert.notEqual(repeated.limit_cids[1],actual.limit_cids[1]);
    const foreign = componentLimitModel(policy,'sha256:'+'2'.repeat(64),rows);
    assert.equal(foreign.host_cid,actual.host_cid);
    assert.notEqual(foreign.limit_cids[0],actual.limit_cids[0]);
    assert.notEqual(foreign.witness_cids[1],actual.witness_cids[1]);
  }
});

test('aggregate author guards use local Definition identities and canonical occurrence locators', () => {
  const corpus = read('../portability/corpus/group-guard-witnesses.json');
  const ids = new Set();
  for (const v of corpus.cases) {
    const path = `$.steps[${v.step}].group.aggregates[${JSON.stringify(v.name)}].${v.scope === 'items' ? 'max_items' : 'max_bytes'}`;
    assert.equal(path, v.path);
    const body = {
      version: 'actql-bound-witness/0.1', dependencies: [corpus.unit_definition_cid],
      derivation: {op: 'source'}, role: 'author_guard',
      law_id: `actql.guard.${v.scope === 'items' ? 'array' : 'string'}-aggregate`,
      source: {kind: 'author_guard', program_definition_cid: corpus.unit_definition_cid, source_path: path},
      unit: v.scope === 'items' ? 'array_items' : 'bytes', value: v.value,
    };
    assert.equal(cid(body), v.cid);
    assert.ok(!ids.has(v.cid));
    ids.add(v.cid);
    const other = 'sha256:' + '1'.repeat(64);
    assert.notEqual(cid({...body, dependencies: [other], source: {...body.source, program_definition_cid: other}}), v.cid);
    assert.notEqual(cid({...body, source: {...body.source, source_path: path.replace('$.steps', '$.stages[0].steps')}}), v.cid);
    assert.notEqual(cid({...body, value: v.value + 1}), v.cid);
  }
});

test('ordinary group subjects distinguish calls, steps and measurement scopes', () => {
  const corpus = read('../portability/corpus/group-limit-subjects.json');
  const subjects = new Set();
  for (const v of corpus.cases) {
    const token = v.aggregate_name.replaceAll('~', '~0').replaceAll('/', '~1');
    const actual = `unit:${v.unit_definition_cid}#/steps/${v.step}/group/aggregates/${token}/${v.scope}`;
    assert.equal(actual, v.expected_subject);
    assert.ok(!subjects.has(actual));
    subjects.add(actual);
    assert.notEqual(actual, actual.replace(v.unit_definition_cid, 'sha256:' + '1'.repeat(64)));
    const proof = {version:'actql-bound-proof/0.1', semantic_ref:actual,
      law_id:'actql.bound.array-aggregate-input', unit:'array_items', value:3,
      inputs:['sha256:' + '2'.repeat(64)]};
    // A new scope requires a new proof identity, even with the same numerical bound.
    if (v.scope === 'items') {
      assert.equal(cid(proof), v.expected_proof_cid);
      assert.notEqual(cid(proof), cid({...proof, semantic_ref:actual.replace(/items$/, 'bytes')}));
    }
  }
});

test('analytic call bounds distinguish each frame from total memberships and group identity', () => {
  const v=read('../portability/corpus/analytic-limit-subjects.json');
  const token=v.name.replaceAll('~','~0').replaceAll('/','~1');
  const subject=`unit:${v.unit_definition_cid}#/steps/${v.step}/analytic/functions/${token}/items`;
  assert.equal(subject,v.subject);
  assert.equal(`$.steps[${v.step}].analytic.functions[${JSON.stringify(v.name)}].max_items`,v.author_path);
  const proof={version:'actql-bound-proof/0.1',semantic_ref:subject,
    law_id:'actql.bound.analytic-array-input',unit:'array_items',value:v.bound,inputs:[v.input]};
  assert.equal(cid(proof),v.proof_cid);
  for(const changed of [
    {...proof,law_id:'actql.bound.array-aggregate-input'},
    {...proof,semantic_ref:subject.replace('/analytic/functions/','/group/aggregates/')},
    {...proof,semantic_ref:subject.replace('/steps/1/','/steps/2/')},
    {...proof,semantic_ref:subject.replace('/items','/bytes')},
    {...proof,semantic_ref:subject.replace(v.unit_definition_cid,'sha256:'+'c'.repeat(64))},
    {...proof,inputs:['sha256:'+'c'.repeat(64)]},
  ]) assert.notEqual(cid(changed),v.proof_cid);
  assert.equal(v.frames.reduce((n,f)=>n+f.length,0),v.memberships);
  assert.equal(Math.max(...v.frames.map(f=>f.length)),v.max_frame_items);
  assert.ok(v.memberships>v.bound);
  for(const frame of v.frames) {
    assert.equal(new Set(frame).size,frame.length);
    assert.ok(frame.every(i=>i>=0&&i<v.bound));
    for(const include of [()=>true,()=>false,i=>i%2===0])
      assert.ok(frame.filter(include).length<=v.bound);
  }
  assert.equal(Math.min(v.bound,2,10),2);
  assert.equal(Math.min(0,2,10),0);
  const registry=read('../spec/contracts/actql-bound-law-registry.json');
  assert.ok(registry.law_ids.includes(proof.law_id));
});

test('Graph input preflight has Unit-scoped limit and enforced witness identities', () => {
  const corpus = read('../portability/corpus/unit-graph-input-proofs.json');
  for (const vector of corpus.cases) {
    const { input_name: name, measure } = vector;
    const host = {
      dependencies: [vectors.expected_policy_cid], derivation: { op: 'source' },
      law_id: `actql.host.graph-input-${measure}`, role: 'host_ceiling',
      source: { field: `max_graph_input_${measure}`, kind: 'host_policy', policy_cid: vectors.expected_policy_cid },
      unit: measure, value: 1000, version: 'actql-bound-witness/0.1',
    };
    host.witness_cid = cid(host);
    const ref = `unit:${vectors.unit_definition_cid}#/inputs/${name.replaceAll('~', '~0').replaceAll('/', '~1')}`;
    const limit = {
      author_guard_binding: 'absent', breach: 'fail', candidates: [host], effective_max: 1000,
      enforcement: 'unit_preflight', subject_ref: `${ref}/${measure}`,
      unit: measure, version: 'actql-resolved-limit/0.1',
    };
    assert.equal(cid(limit), vector.limit_cid);
    const witness = {
      dependencies: [cid(limit)], derivation: { op: 'enforced_ceiling', resolved_limit_cid: cid(limit) },
      law_id: `actql.bound.graph-input-${measure}`, role: 'proven_upper_bound',
      source: { kind: 'program', proof_cid: cid(limit), semantic_ref: ref },
      unit: measure, value: 1000, version: 'actql-bound-witness/0.1',
    };
    assert.equal(cid(witness), vector.witness_cid);
    assert.notEqual(cid({ ...limit, subject_ref: `graph-input:${name}:${measure}` }), cid(limit));
    assert.notEqual(cid({ ...limit, enforcement: 'static' }), cid(limit));
    assert.notEqual(cid({ ...witness, source: { ...witness.source, semantic_ref: name } }), cid(witness));
    assert.notEqual(cid({ ...limit, subject_ref: limit.subject_ref.replace('unit:sha256:0', 'unit:sha256:1') }), cid(limit));
  }
});

test('operation output proofs retain their Unit namespace and source ordinal', () => {
  const corpus = read('../portability/corpus/unit-operation-proofs.json');
  const identities = new Set();
  for (const vector of corpus.cases) {
    const semantic_ref = `unit:sha256:${'0'.repeat(63)}${vector.unit_tail}#/steps/${vector.ordinal}`;
    const proof = {
      version: 'actql-bound-proof/0.1', semantic_ref, law_id: 'actql.bound.values',
      unit: 'rows', value: 1, inputs: [],
    };
    assert.equal(cid(proof), vector.proof_cid);
    const witness = {
      version: 'actql-bound-witness/0.1', unit: 'rows', value: 1,
      role: 'proven_upper_bound', law_id: proof.law_id,
      source: { kind: 'program', semantic_ref, proof_cid: cid(proof) },
      derivation: { op: 'source' }, dependencies: [cid(proof)],
    };
    assert.equal(cid(witness), vector.witness_cid);
    identities.add(cid(witness));
    assert.notEqual(cid({ ...proof, semantic_ref: `checked-step:${vector.ordinal}` }), cid(proof));
    assert.notEqual(cid({ ...proof, inputs: [vector.witness_cid, vector.witness_cid] }),
      cid({ ...proof, inputs: [vector.witness_cid] }));
  }
  assert.equal(identities.size, corpus.cases.length);
});

test('publication subjects and Host-only resolved-limit identities are fixed independently', () => {
  const policy = Object.fromEntries(policyContract.schema.required
    .filter((key) => key !== 'version').map((key) => [key, vectors.host_policy_all_limits]));
  policy.version = 'actql-capacity-host-policy/0.1';
  assert.equal(cid(policy), vectors.expected_policy_cid);
  for (const [unit, cases, expectedWitness] of [
    ['rows', vectors.cases, vectors.expected_host_witness_cid],
    ['bytes', vectors.byte_cases, vectors.expected_byte_host_witness_cid],
  ]) {
    const witness = {
      dependencies: [cid(policy)], derivation: { op: 'source' },
      law_id: `actql.host.artifact-${unit}`, role: 'host_ceiling',
      source: { field: `max_artifact_${unit}`, kind: 'host_policy', policy_cid: cid(policy) },
      unit, value: 1000, version: 'actql-bound-witness/0.1',
    };
    assert.equal(cid(witness), expectedWitness);
    witness.witness_cid = cid(witness);
    for (const vector of cases) {
      const token = vector.result_name.replaceAll('~', '~0').replaceAll('/', '~1');
      assert.equal(token, vector.token);
      const body = {
        author_guard_binding: 'absent', breach: 'fail', candidates: [witness],
        effective_max: 1000, enforcement: 'engine_atomic',
        subject_ref: `unit:${vectors.unit_definition_cid}#/results/${token}/${unit}`,
        unit, version: 'actql-resolved-limit/0.1',
      };
      assert.equal(cid(body), vector.expected_limit_cid);
      const other = unit === 'rows' ? 'bytes' : 'rows';
      assert.notEqual(cid({ ...body, subject_ref: `unit:${vectors.unit_definition_cid}#/results/${token}/${other}` }), cid(body));
      assert.notEqual(cid({ ...body, unit: other }), cid(body));
    }
  }
});
