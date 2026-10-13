import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
const read = path => JSON.parse(readFileSync(path, 'utf8'));
const fixture = read(new URL('./independent-preimages.json', import.meta.url));
// This synthetic fixture has ASCII object keys and finite integral numbers.
// No product canonicalizer, compiler or identity emitter is imported.
const canonical = value => {
  if (Array.isArray(value)) return '[' + value.map(canonical).join(',') + ']';
  if (value && typeof value === 'object') {
    const keys = Object.keys(value).sort();
    assert(keys.every(key => /^[\x00-\x7f]*$/u.test(key)));
    return '{' + keys.map(key => JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}';
  }
  if (typeof value === 'number') assert(Number.isFinite(value));
  return JSON.stringify(value);
};
const cid = value => 'sha256:' + createHash('sha256').update(canonical(value), 'utf8').digest('hex');

test('current stage/Program Definition preimages preserve the original shared DAG', () => {
  const contract = cid(read('spec/contracts/actql-expressions.json'));
  for (const stage of fixture.stages) {
    assert.equal(stage.envelope.expression_contract_cid, contract);
    assert.equal(cid(stage.envelope), stage.cid);
  }
  assert.deepEqual(fixture.stages.map(stage => stage.id), ['a', 'compute_a', 'compute_b', 'compute_c']);
  const semantics = fixture.programSemantics.envelope;
  assert.equal(semantics.expression_contract_cid, contract);
  assert.deepEqual(semantics.program_template.stages.map(stage => stage.stage_semantics_cid), fixture.stages.map(stage => stage.cid));
  assert.deepEqual(semantics.program_template.stages.map(stage => stage.after), ['initial', 'completed', 'completed', 'completed']);
  assert.equal(cid(semantics), fixture.programSemantics.cid);
  assert.equal(fixture.programDefinition.envelope.program_semantics_cid, fixture.programSemantics.cid);
  assert.equal(fixture.programDefinition.envelope.id, 'p');
  assert.equal(cid(fixture.programDefinition.envelope), fixture.programDefinition.cid);
  assert.deepEqual(semantics.parameter_references, [{name: 'minimum', path: '/stages/0/steps/0/filter/gt/1', type: {type: 'number', nullable: false}}]);
  assert.deepEqual(fixture.stages[0].envelope.local_body.steps[0], {as: 'filtered', filter: {gt: [{field: 'id'}, {$param: 'minimum'}]}});
  assert.deepEqual(fixture.stages.slice(1).map(stage => stage.envelope.local_body.steps[0].filter), [
    {gt: [{field: 'id'}, {literal: 2}]}, {gt: [{field: 'id'}, {literal: 0}]}, {lt: [{field: 'id'}, {literal: 9}]},
  ]);
});

test('complete policy candidates retain every cost/assignment outside the definition slot', () => {
  const before = fixture.originalPolicyCandidates, after = fixture.currentPolicyCandidates;
  assert.equal(cid(before.body), before.cid);
  const expected = structuredClone(before.body);
  expected[1] = fixture.programDefinition.cid;
  assert.deepEqual(after.body, expected);
  assert.equal(cid(expected), after.cid);
  assert.notEqual(before.cid, after.cid);
  const source = readFileSync('src/query_integration/policy_candidates_body_wbtest.mbt', 'utf8');
  assert.equal(source.match(/^\s*#\|(.*)$/mu)[1], canonical(expected));
  assert(source.includes('"' + after.cid + '"'));
});

test('Graph compilation names the current normative AoA contract, not the law manifest', () => {
  const contract = read('spec/contracts/actql-aoa.json');
  assert.equal(cid(contract), fixture.currentAoAContractPin);
  assert.notEqual(fixture.currentAoAContractPin, fixture.originalAoAContractPin);
  assert.notEqual(fixture.currentAoAContractPin, contract.graph_law_manifest_cid);
  const source = readFileSync('src/query_integration/graph_plan_wbtest.mbt', 'utf8');
  assert(source.includes(fixture.currentAoAContractPin));
  assert(!source.includes(fixture.originalAoAContractPin));
});

test('an actual predicate change changes independently rebuilt Program identity', () => {
  const stage = structuredClone(fixture.stages[1].envelope);
  stage.local_body.steps[0].filter.gt[1].literal = 3;
  const semantics = structuredClone(fixture.programSemantics.envelope);
  semantics.program_template.stages[1].stage_semantics_cid = cid(stage);
  const definition = {...fixture.programDefinition.envelope, program_semantics_cid: cid(semantics)};
  assert.notEqual(cid(definition), fixture.programDefinition.cid);
  // Literal Parameter Values and Host-policy evidence are not part of this
  // unbound source envelope; do not replace a changed predicate with a policy pin.
  assert(!Object.hasOwn(semantics, 'parameter_values'));
  assert(!Object.hasOwn(semantics, 'check_environment_cid'));
});
