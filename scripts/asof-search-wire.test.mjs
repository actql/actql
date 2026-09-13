import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync, writeFileSync} from 'node:fs';
import {test} from 'node:test';
import {machineCid} from './actql-spec-family.mjs';

const contract = JSON.parse(readFileSync('spec/contracts/actql-asof-search.json', 'utf8'));
const pin = 'sha256:f6638f0527a537a66cb1bfee82c1d01ae9fb3756356fd6360b514c092f56d3f4';
const hash = text => 'sha256:' + createHash('sha256').update(text).digest('hex');
const subject = (digit, step = 0) => `unit:sha256:${digit.repeat(64)}#/steps/${step}`;
// These source proof bodies and limit bodies are authored in canonical key
// order. No product compiler, reidentification code or lowerer is consulted.
const proof = (digit, value) => ({inputs: [], law_id: 'actql.bound.values',
  semantic_ref: subject(digit), unit: 'rows', value, version: 'actql-bound-proof/0.1'});
const bodies = [proof('2', 2), proof('3', 3), proof('4', 0)];
const proofs = bodies.map(body => {
  const canonical = JSON.stringify(body), cid = hash(canonical);
  const witness = {dependencies: [cid], derivation: {op: 'source'}, law_id: body.law_id,
    role: 'proven_upper_bound', source: {kind: 'program', proof_cid: cid, semantic_ref: body.semantic_ref},
    unit: 'rows', value: body.value, version: 'actql-bound-witness/0.1'};
  return {body, canonical, cid, witness, witness_cid: hash(JSON.stringify(witness))};
});
const base = {condition: 'single_visit', enforcement: 'engine_atomic',
  left_bounds: [proofs[0].witness_cid], maximum: 6, right_bounds: [proofs[1].witness_cid],
  search_contract_cid: pin, subject_ref: subject('0'), unit: 'pair_visits',
  version: 'actql-asof-search-limit/0.1'};
const limits = [base, {...base, subject_ref: subject('1')}, {...base, subject_ref: subject('0', 1)},
  {...base, left_bounds: base.right_bounds, right_bounds: base.left_bounds},
  {...base, left_bounds: [proofs[2].witness_cid], maximum: 0, right_bounds: []}];
const expected = {version: 'actql-asof-search-wire-vectors/0.1', proofs,
  limits: limits.map(body => ({body, canonical: JSON.stringify(body), cid: hash(JSON.stringify(body))}))};
const path = 'portability/corpus/asof-search-wire.json';
if (process.argv.includes('--write')) writeFileSync(path, JSON.stringify(expected, null, 2) + '\n');

function shape(v, s = contract.schemas.limit) {
  if ('const' in s) return v === s.const;
  if (s.type === 'object') return v !== null && typeof v === 'object' && !Array.isArray(v) &&
    s.required.every(k => Object.hasOwn(v, k)) && Object.keys(v).every(k =>
      Object.hasOwn(s.properties, k) && shape(v[k], s.properties[k]));
  if (s.type === 'integer') return Number.isSafeInteger(v) && !Object.is(v, -0) && v >= s.minimum && v <= s.maximum;
  if (s.type === 'string') return typeof v === 'string' && new RegExp(s.pattern).test(v);
  if (s.type === 'array') return Array.isArray(v) && new Set(v).size === v.length && v.every(x => shape(x, s.items));
  assert.fail(`unsupported schema branch: ${JSON.stringify(s)}`);
}

// A bounded independent semantic model, not an admission API or execution proof.
function admitted(v, owner, leftSources, rightSources) {
  if (!shape(v) || v.search_contract_cid !== pin || v.subject_ref !== owner) return false;
  const minima = [];
  for (const [refs, sources] of [[v.left_bounds, leftSources], [v.right_bounds, rightSources]]) {
    if (refs.some((x, i) => i && refs[i - 1] >= x)) return false;
    const values = [];
    for (const ref of refs) {
      const p = proofs.find(p => p.witness_cid === ref);
      if (!p || p.body.unit !== 'rows' || !sources.includes(p.body.semantic_ref)) return false;
      values.push(BigInt(p.body.value));
    }
    minima.push(values.length ? values.reduce((a, b) => a < b ? a : b) : null);
  }
  if (minima.includes(0n)) return v.maximum === 0;
  if (minima.includes(null)) return false;
  return BigInt(v.maximum) === minima[0] * minima[1];
}

test('persistent search preimages separate consumers, ordinals and operand roles', () => {
  assert.equal(machineCid(contract), pin);
  assert.equal(machineCid(contract.schemas.limit), 'sha256:22b4ebc943770dde101f2f1e6cf70d2627dbc5f70eadbb7f49fc59e8f07651ec');
  assert.deepEqual(JSON.parse(readFileSync(path, 'utf8')), expected);
  assert.equal(new Set(expected.limits.map(v => v.cid)).size, limits.length);
  for (const v of [...expected.proofs, ...expected.limits]) {
    assert.equal(machineCid(v.body), v.cid);
    assert.equal(machineCid(Object.fromEntries(Object.entries(v.body).reverse())), v.cid);
    assert(!v.canonical.includes('checked-step:'));
  }
  for (const v of limits) assert(shape(v));
  for (const p of proofs) {
    assert.equal(machineCid(p.witness), p.witness_cid);
    assert.notEqual(p.cid, p.witness_cid);
  }
});

test('shape rejects foreign domains, missing fields and process-only additions', () => {
  for (const field of Object.keys(base)) { const v = {...base}; delete v[field]; assert(!shape(v)); }
  for (const field of ['self_cid', 'claim', 'producer_visit', 'attempt', 'observed_rows', 'validated']) assert(!shape({...base, [field]: 1}));
  for (const maximum of [-1, -0, 0.5, Number.MAX_SAFE_INTEGER + 1]) assert(!shape({...base, maximum}));
  assert(!shape({...base, unit: 'rows'}));
  assert(!shape({...base, condition: 'unconditional'}));
  assert(!shape({...base, subject_ref: 'checked-step:0'}));
  assert(!shape({...base, left_bounds: [proofs[0].witness_cid, proofs[0].witness_cid]}));
});

test('shape alone does not establish the pin, owner, proof correspondence or arithmetic', () => {
  const check = v => admitted(v, subject('0'), [subject('2')], [subject('3')]);
  assert(check(base));
  for (const change of [{maximum: 5}, {search_contract_cid: 'sha256:' + 'f'.repeat(64)},
    {subject_ref: subject('1')}, {left_bounds: base.right_bounds}, {right_bounds: []},
    {left_bounds: ['sha256:' + 'a'.repeat(64)]}, {left_bounds: [proofs[0].cid]}]) {
    const v = {...base, ...change}; assert(shape(v)); assert(!check(v));
  }
  assert(admitted(limits[4], subject('0'), [subject('4')], []));
  assert(!admitted({...limits[4], left_bounds: []}, subject('0'), [], []));
  assert(!admitted(limits[4], subject('0'), [subject('2')], []));
});
