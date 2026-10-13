import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {lagIdentityOracle} from './lag-identity-oracle.mjs';
import {signatureRoleCid} from './sga-signature-role-identity-oracle.mjs';
import {valuesDependencyOracle, valuesProgramOracle} from './client-values-dependency-oracle.mjs';
const read = path => JSON.parse(readFileSync(path, 'utf8'));
test('Lag independently reseals grammar identities and retains watermark preimages', () => {
  const before = read('scripts/fixtures/pre-lag-values-identities.json');
  assert.deepEqual(before, read('scripts/fixtures/submitted-row-watermark-values-identities.json'));
  const expected = lagIdentityOracle({grammarPath:'reviews/2026-10-12-frontend-nearest-carrier-roles/preimages/query-grammar.ebnf',rulesPath:'reviews/2026-10-12-frontend-nearest-carrier-roles/preimages/query-rules.md'});
  assert.deepEqual(expected, read('scripts/fixtures/submitted-lag-values-identities.json'));
  assert.deepEqual(expected.grammar, read('reviews/2026-10-12-frontend-nearest-carrier-roles/preimages/grammar-manifest.json'));
  assert.equal(before.run_preimages.run.run_definition_cid,
    'sha256:f20f0c27ff197830a5bb7fd601e02d738547745bd1657cb42db376f754498adb');
  assert.notEqual(expected.run_preimages.run.run_definition_cid, before.run_preimages.run.run_definition_cid);
  // Independent input Catalog from the actual Lag introduction, not current
  // normative bodies or the historical fixture's submitted dependency array.
  const bytes = readFileSync('scripts/fixtures/submitted-lag-values-contracts.json');
  assert.equal(createHash('sha256').update(bytes).digest('hex'),
    '62a2a8c03c227035afb456163f9a5bbf93de752cb39cf45dc14df2305bfa9a50');
  const catalog = JSON.parse(bytes);
  assert.equal(catalog.source_revision,'9dfd3e8723b9dfa18f9463576b038db3a01d4183');
  assert.equal(catalog.normative_inputs.length,32);
  assert.deepEqual(catalog.normative_inputs.map(input=>input.role).sort(),
    Object.keys(catalog.contract_cids).sort());
  for (const input of catalog.normative_inputs) {
    assert.equal(input.source_mode,'100644');
    assert.equal(input.selected_body_cid,catalog.contract_cids[input.role]);
  }
  const historical = {retainedContractCids:catalog.contract_cids};
  assert.deepEqual(expected.values_dependencies, valuesDependencyOracle(historical));
  assert.deepEqual(expected.program_identity, valuesProgramOracle(historical));
  for (const key of Object.keys(before.grammar)) {
    if (!['query_text_grammar_sha256','query_text_rules_sha256','grammar_manifest_cid'].includes(key))
      assert.deepEqual(expected.grammar[key], before.grammar[key], key);
  }
  for (const [name, field] of [['template','bound_invocation_template_cid'],
    ['executable','executable_plan_cid'],['compiled','compiled_plan_cid'],['run','run_definition_cid']]) {
    const {[field]: seal, ...body} = expected.run_preimages[name];
    assert.equal(signatureRoleCid(body), seal, name);
  }
  assert.deepEqual(expected.run_preimages.executable.resolved_limits, before.run_preimages.executable.resolved_limits);
  assert.deepEqual(expected.run_preimages.executable.execution_material.program,
    before.run_preimages.executable.execution_material.program);
});


test('current Values inputs use current normative contracts separately from retained Lag history', () => {
  const historical = read('scripts/fixtures/submitted-lag-values-identities.json');
  const dependencies = valuesDependencyOracle();
  const program = valuesProgramOracle();
  const expressionCid = signatureRoleCid(read('spec/contracts/actql-expressions.json'));
  assert.equal(dependencies.local.expression_contract_cid,expressionCid);
  assert.equal(program.semantics.expression_contract_cid,expressionCid);
  assert.equal(program.semantics.program_template.stages[0].stage_semantics_cid,
    signatureRoleCid(dependencies.local));
  assert.equal(program.semanticsCid,signatureRoleCid(program.semantics));
  assert.equal(program.programCid,signatureRoleCid(program.definition));
  assert.notEqual(dependencies.unit,historical.values_dependencies.unit);
  assert.notEqual(program.programCid,historical.program_identity.programCid);
});

test('retained Values input Catalog rejects missing, extra and invalid roles without invoking getters', () => {
  const input = read('scripts/fixtures/submitted-lag-values-contracts.json').contract_cids;
  const [first] = Object.keys(input);
  const missing = {...input};delete missing[first];
  const invalid = {message:'InvalidRetainedValuesContractCids'};
  for (const catalog of [missing,{...input,extra:input[first]},
    {...input,[first]:'sha256:invalid'},null,[]]) {
    assert.throws(()=>valuesDependencyOracle({retainedContractCids:catalog}),invalid);
  }
  let reads = 0;
  const getter = {...input};
  Object.defineProperty(getter,first,{get(){reads++;return input[first];}});
  assert.throws(()=>valuesDependencyOracle({retainedContractCids:getter}),invalid);
  assert.equal(reads,0);
  for (const options of [{legacy:true},{beforeMembership:true},{preTypedJson:true}]) {
    assert.throws(()=>valuesDependencyOracle({...options,retainedContractCids:input}),invalid);
  }
});
