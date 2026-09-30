// Inspect the checked Program and common task compiler for the pending
// Graph provider handoff. Build the JS bridge before running this script.
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import * as moon from
  '../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {canonicalText} from './check-canonical-json.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const read = path => JSON.parse(readFileSync(join(root, path), 'utf8'));
const cid = value => `sha256:${createHash('sha256')
  .update(canonicalText(value)).digest('hex')}`;
const {evidence_bundle_cid: ignored, ...baseEnvironment} =
  read('spec/local-check-environment.json');
void ignored;
baseEnvironment.host_policy_profile = {...baseEnvironment.host_policy_profile,
  capacity: {...baseEnvironment.host_policy_profile.capacity,
    max_graph_construction_edges: 1000,
    max_graph_construction_input_rows: 1000,
    max_graph_construction_nodes: 1000}};
const environment = {...baseEnvironment,
  evidence_bundle_cid: cid(baseEnvironment)};
const numericProfile = read('spec/contracts/actql-numeric-reduction.json');
const owner = moon.clientProgramCheckEnvironmentWithNumericProfile(
  canonicalText(environment), environment.evidence_bundle_cid,
  false, false, true, true, false, false, false, cid(numericProfile));
if (!owner) throw new Error('LocalCheckEnvironmentRejected');
const issuePath = value => {
  const path = [];
  for (let current = value;
    current && typeof current === 'object' && path.length < 12;
    current = current._0) {
    path.push({tag: current.$tag ?? null,
      keys: Reflect.ownKeys(current).map(String)});
  }
  return path;
};

for (const name of ['graphs-equal', 'reach-subgraph', 'diff-apply']) {
  const program = read(
    `spec/frontend/fixtures/sga-surface/${name}.expected-program.json`);
  const preparation = moon.clientProgramPrepareEffectFreeWithParameters(
    canonicalText(program), 'json', owner, undefined);
  const prepared = moon.clientProgramPreparationReady(preparation);
  if (!prepared) {
    console.log(JSON.stringify({name, prepared: false,
      issue: moon.clientProgramPreparationIssueCode(preparation)}));
    continue;
  }
  const tasks = [];
  for (let index = 0; index < moon.clientProgramTaskCount(prepared); index++) {
    const pipeline = moon.clientProgramTaskPipelineWire(prepared, index);
    tasks.push({index, pipeline: pipeline.$tag === 1
      ? (() => {
        const parsed = JSON.parse(pipeline._0);
        return {output: parsed.output,
          steps: parsed.steps.map(step => ({id: step.id, op: step.op,
            input: step.in}))};
      })() : null,
    pipelineIssue: pipeline.$tag === 1 ? null : issuePath(pipeline._0)});
  }
  const compiled = moon.clientProgramCompileLocalTasks(prepared);
  console.log(JSON.stringify({name, prepared: true, tasks,
    compiled: compiled.$tag === 1,
    compilationIssue: compiled.$tag === 1 ? null : issuePath(compiled._0)}));
}
