import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';

import * as moon from
  '../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {canonicalText} from './check-canonical-json.mjs';

const readJson = path => JSON.parse(readFileSync(new URL(path,
  import.meta.url), 'utf8'));
const fixture = name => readJson(
  `../spec/frontend/fixtures/sga-surface/${name}.expected-program.json`);
const cid = value => `sha256:${createHash('sha256')
  .update(canonicalText(value)).digest('hex')}`;

const {evidence_bundle_cid: ignored, ...baseEnvironment} = readJson(
  '../spec/local-check-environment.json');
void ignored;
baseEnvironment.host_policy_profile = {...baseEnvironment.host_policy_profile,
  capacity: {...baseEnvironment.host_policy_profile.capacity,
    max_graph_construction_edges: 1000,
    max_graph_construction_input_rows: 1000,
    max_graph_construction_nodes: 1000}};
const environment = {...baseEnvironment,
  evidence_bundle_cid: cid(baseEnvironment)};
const numericProfile = readJson('../spec/contracts/actql-numeric-reduction.json');
const owner = moon.clientProgramCheckEnvironmentWithNumericProfile(
  canonicalText(environment), environment.evidence_bundle_cid,
  false, false, true, true, false, false, false, cid(numericProfile));
assert.ok(owner, 'the installed Local Check Environment is admitted');

const prepare = program => moon.clientProgramPrepareEffectFreeWithParameters(
  canonicalText(program), 'json', owner, undefined);

test('named SGA Programs pass common preparation without a new checker', () => {
  for (const name of ['graphs-equal', 'normalize-rows', 'degree-rows',
    'graph-bounds']) {
    const outcome = prepare(fixture(name));
    assert.ok(moon.clientProgramPreparationReady(outcome),
      `${name}: ${String(moon.clientProgramPreparationIssueCode(outcome))}`);
  }
});

test('a Relation cannot enter a Graph-only named operation', () => {
  const program = fixture('normalize-rows');
  program.stages[0].steps.splice(4, 2,
    {from: 'normalized', node_rows: true, as: 'relation'},
    {from: 'relation', normalize_graph: true, as: 'invalid'});
  program.stages[0].results.answer = {from: 'invalid'};
  const outcome = prepare(program);
  assert.equal(moon.clientProgramPreparationReady(outcome), undefined);
  assert.equal(moon.clientProgramPreparationIssueCode(outcome),
    'check_invalid_input');
  assert.ok(moon.clientProgramPreparationIssue(outcome));
});

test('graph_bounds requires an authored bound in common preparation', () => {
  const program = fixture('graph-bounds');
  program.stages[0].steps[3].graph_bounds = {};
  const outcome = prepare(program);
  assert.equal(moon.clientProgramPreparationReady(outcome), undefined);
  assert.equal(moon.clientProgramPreparationIssueCode(outcome),
    'check_invalid_input');
  assert.ok(moon.clientProgramPreparationIssue(outcome));
});
