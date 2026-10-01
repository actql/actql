import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';

import * as moon from
  '../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {canonicalText} from './check-canonical-json.mjs';

// Reuse the independently hashed typing vector, not an execution result.
const taskSource = readFileSync(new URL(
  '../src/stage_results/infer_program_test.mbt', import.meta.url), 'utf8');
const task = JSON.parse(taskSource.match(/let body =\n\s+#\|(.+)/u)[1]);
const {evidence_bundle_cid: ignored, ...baseEnvironment} = JSON.parse(
  readFileSync(new URL('../spec/local-check-environment.json',
    import.meta.url), 'utf8'));
void ignored;
const cid = value => `sha256:${createHash('sha256')
  .update(canonicalText(value)).digest('hex')}`;

function environment(installTask = true) {
  const body = {...baseEnvironment,
    model_task_contracts: installTask ? [task] : []};
  const evidenceCid = cid(body);
  return moon.clientProgramCheckEnvironment(
    canonicalText({...body, evidence_bundle_cid: evidenceCid}), evidenceCid,
    false, false, true, false, false, false, false);
}

function program() {
  return {version: 'actql/0.1', id: 'infer-owner-checker', stages: [{
    id: 'main', inputs: {}, steps: [
      {values: {schema: {
        id: {type: 'string', nullable: false},
        text: {type: 'string', nullable: true},
      }, rows: [{id: 'a', text: 'hello'}]}, as: 'input'},
      {assert_rows: {unique_by: ['id']}, as: 'unique'},
      {infer: {contract: 'model-task:risk-score.v1', key: 'id',
        input: {text: {field: 'text'}}}, as: 'captured'},
    ], results: {captured: {from: 'captured',
      fields: ['id', 'outcome', 'value']}},
  }], results: {answer: {from: {stage: 'main', result: 'captured'}}}};
}

const prepare = (source, owner) =>
  moon.clientProgramPrepareEffectFreeWithParameters(
    canonicalText(source), 'json', owner, undefined);

test('normal Program checking retains the installed model acquisition', () => {
  const owner = environment();
  assert.ok(owner);
  const outcome = prepare(program(), owner);
  const prepared = moon.clientProgramPreparationReady(outcome);
  assert.ok(prepared, String(moon.clientProgramPreparationIssueCode(outcome)));
  assert.equal(moon.clientProgramResultCount(prepared), 1);
  assert.equal(moon.clientProgramResultName(prepared, 0), 'answer');
});

test('normal INFER still requires installation and an actual key proof', () => {
  const absent = prepare(program(), environment(false));
  assert.equal(moon.clientProgramPreparationReady(absent), undefined);
  const unkeyed = program();
  unkeyed.stages[0].steps.splice(1, 1);
  const outcome = prepare(unkeyed, environment());
  assert.equal(moon.clientProgramPreparationReady(outcome), undefined);
});
