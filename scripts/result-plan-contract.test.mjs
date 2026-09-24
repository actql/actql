import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {
  checkResultPlanBindings, checkResultPlanSchema, resultPlanCid,
} from './result-plan-contract.mjs';

const registry = JSON.parse(readFileSync(
  'spec/contracts/actql-protocol-schemas.json', 'utf8',
));
const a = 'sha256:' + 'a'.repeat(64);
const b = 'sha256:' + 'b'.repeat(64);
const c = 'sha256:' + 'c'.repeat(64);

function fixture() {
  const result = {
    version: 'actql-result-plan/0.1',
    result_name: 'answer',
    unit_definition_cid: a,
    unit_result_name: 'rows',
    unit_result_ordinal: 0,
    projection: [
      {input: 'id', output: 'id', value_contract_cid: b},
    ],
    order: {strategy: 'projected_fields', terms: [
      {field: 'id', direction: 'asc', nulls: 'last', authored: false},
    ]},
    typed_output_port: {
      name: 'rows', carrier: 'relation', row_contract_cid: c,
    },
  };
  result.result_plan_logical_cid = resultPlanCid(result);
  const plan = {
    nodes: [{node_id: 'result_0', output_contracts: {rows: c}}],
    root_refs: [{
      role: 'requested_result', name: 'answer',
      ref: {node_id: 'result_0', port: 'rows'},
    }],
    execution_material: {
      result_plan_logical_cids: {answer: result.result_plan_logical_cid},
    },
  };
  return {result, plan};
}

test('registered Result Plan schema and nested root refs retain pins', () => {
  checkResultPlanSchema(registry);
});

test('independent Result Plan vector binds the checked semantic fields', () => {
  const {result} = fixture();
  assert.equal(result.result_plan_logical_cid,
    'sha256:d14737f136fab6a0a6f68ca87d9cae4d8af848ce7a138b8b47f8adc948a0c566');
  assert.notEqual(resultPlanCid({...result, unit_result_ordinal: 1}),
    result.result_plan_logical_cid);
  assert.notEqual(resultPlanCid({...result, typed_output_port: {
    ...result.typed_output_port, row_contract_cid: b,
  }}), result.result_plan_logical_cid);
});

test('Result names, roots and typed output ports bind one to one', () => {
  const {result, plan} = fixture();
  const checkedPort = () => ({carrier: 'relation', row_contract_cid: c});
  checkResultPlanBindings(plan, {answer: result}, checkedPort);
  assert.throws(() => checkResultPlanBindings(plan, {}, checkedPort));
  assert.throws(() => checkResultPlanBindings(plan, {
    answer: {...result, result_name: 'other'},
  }, checkedPort));
  assert.throws(() => checkResultPlanBindings(plan, {
    answer: {...result, typed_output_port: {
      ...result.typed_output_port, name: 'foreign',
    }},
  }, checkedPort));
  assert.throws(() => checkResultPlanBindings({
    ...plan, root_refs: [...plan.root_refs, plan.root_refs[0]],
  }, {answer: result}, checkedPort));
  assert.throws(() => checkResultPlanBindings({
    ...plan, nodes: [{node_id: 'result_0', output_contracts: {rows: b}}],
  }, {answer: result}, checkedPort));
  assert.throws(() => checkResultPlanBindings({
    ...plan, root_refs: [{...plan.root_refs[0],
      ref: {node_id: 'other', port: 'rows'}}],
  }, {answer: result}, checkedPort));
  assert.throws(() => checkResultPlanBindings({
    ...plan, execution_material: {result_plan_logical_cids: {answer: a}},
  }, {answer: result}, checkedPort));
  assert.throws(() => checkResultPlanBindings(plan, {answer: result},
    () => ({carrier: 'graph', row_contract_cid: c})));
  assert.throws(() => checkResultPlanBindings(plan, {answer: result},
    () => ({carrier: 'relation', row_contract_cid: b})));
});
